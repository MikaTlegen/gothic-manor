extends Node3D
## Правила уровня «Догорающая свеча».
## Игрок появляется в темноте с одной свечой и должен дойти до «Своей комнаты» до того, как она догорит.
## Победа — вход в зону SafeZone. Проигрыш — свеча гаснет: кромешная тьма, тишина, затем из-за спины
## приближается преследователь: шаг переходит в бег (pitch и громкость растут), поверх — его тяжёлое дыхание.

enum State { INTRO, PLAYING, WON, LOST }

const STALKER_START_DIST := 16.0     ## С какого расстояния начинаются шаги, м
const STALKER_END_DIST := 0.9        ## Где преследователь останавливается — за самой спиной, м
const STALKER_DELAY := 1.5           ## Тишина после угасания до первого шага, с
const STALKER_PITCH := Vector2(0.7, 1.6)      ## Темп записи бега: быстрый шаг (0.39 с между шагами) → бег (0.17 с)
const STALKER_VOLUME := Vector2(-10.0, 8.0)   ## Громкость шагов, дБ: издалека → у спины
const BREATH_VOLUME := Vector2(-24.0, 6.0)    ## Громкость дыхания, дБ (шина Scare, поверх шагов на SFX)
const STALKER_RAMP := 3.0            ## За сколько секунд шаг переходит в бег, с
const STALKER_WALK_SPEED := 2.0      ## Скорость при начальном темпе, м/с (растёт пропорционально темпу)
const BREATH_HEIGHT := 1.6           ## Высота дыхания над полом (голова преследователя), м

var state := State.INTRO
var elapsed := 0.0

var _steps_by_surface := {}

@onready var player: CharacterBody3D = $Player
@onready var candle: Node3D = $Player/Head/Camera3D/Hand
@onready var safe_zone: Area3D = $Gameplay/SafeZone
@onready var door_trigger: Area3D = $Gameplay/DoorTrigger
@onready var safe_door: Node3D = $Gameplay/SafeDoor
@onready var env: WorldEnvironment = $Environment
@onready var fade: ColorRect = $UI/Fade
@onready var message: Label = $UI/Message
@onready var hint: Label = $UI/Hint
@onready var sfx_steps: AudioStreamPlayer3D = $Player/Steps
@onready var sfx_clock: AudioStreamPlayer3D = $Gameplay/ClockTick
@onready var sfx_fire: AudioStreamPlayer3D = $Gameplay/FireCrackle
@onready var sfx_creak: AudioStreamPlayer3D = $Gameplay/Creak
@onready var sfx_stalker: AudioStreamPlayer3D = $Gameplay/Stalker
@onready var sfx_breath: AudioStreamPlayer3D = $Gameplay/StalkerBreath
@onready var sfx_ambience: AudioStreamPlayer = $Gameplay/Ambience
@onready var sfx_heart: AudioStreamPlayer = $Gameplay/Heartbeat
@onready var sfx_out: AudioStreamPlayer = $Gameplay/CandleOut


func _enter_tree() -> void:
	ScareLedger.begin_level(1)
	_define_input()
	HorrorAudio.setup_buses()


func _ready() -> void:
	# Шаги игрока: варианты записей по камню и дереву, случайный тон и громкость каждого шага
	_steps_by_surface = {
		"stone": HorrorAudio.variants("step_stone", 6, 1.1, 2.5),
		"wood": _wood_steps(),
	}
	sfx_steps.stream = _steps_by_surface.wood
	for p in [sfx_clock, sfx_fire, sfx_ambience, sfx_heart, sfx_stalker]:
		if p.stream is AudioStreamOggVorbis:
			p.stream.loop = true
	_fill_placeholder_sounds()
	candle.extinguished.connect(_on_extinguished)
	candle.phase_changed.connect(_on_phase)
	safe_zone.body_entered.connect(_on_safe_entered)
	door_trigger.body_entered.connect(_on_door_approach)
	player.step_taken.connect(_on_player_step)
	sfx_clock.play()
	sfx_fire.play()
	sfx_ambience.play()
	ScareFX.prewarm(player.camera)
	_intro()


func _define_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "restart": [KEY_R],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	# ПКМ — прикрыть пламя ладонью
	if not InputMap.has_action("shield"):
		InputMap.add_action("shield")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("shield", mb)


## Заглушки звуков: подставляются, только если в сцене не задана настоящая запись.
func _fill_placeholder_sounds() -> void:
	var fill := {
		sfx_steps: SoundBank.footstep(false), sfx_clock: SoundBank.clock_tick(),
		sfx_fire: SoundBank.fire_crackle(), sfx_creak: SoundBank.door_creak(),
		sfx_stalker: SoundBank.footstep(true), sfx_ambience: SoundBank.drone(),
		sfx_heart: SoundBank.heartbeat(), sfx_out: SoundBank.candle_out(),
	}
	for p in fill:
		if p.stream == null:
			p.stream = fill[p]


func _intro() -> void:
	fade.color.a = 1.0
	message.text = "Найди свою комнату, пока горит свеча"
	message.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(message, "modulate:a", 1.0, 1.2)
	tw.tween_interval(2.0)
	tw.tween_property(message, "modulate:a", 0.0, 1.5)
	tw.parallel().tween_property(fade, "color:a", 0.0, 3.0)
	state = State.PLAYING     # свеча горит с первой секунды — темнота не ждёт


func _process(delta: float) -> void:
	if state == State.PLAYING:
		elapsed += delta
	if Input.is_action_just_pressed("restart") and state != State.PLAYING:
		get_tree().reload_current_scene()


func _wood_steps() -> AudioStreamRandomizer:
	var r := HorrorAudio.variants("step_wood", 4, 1.1, 2.5)
	for i in 3:
		r.add_stream(-1, HorrorAudio.one("step_wood_b_%02d" % (i + 1)))
	return r


func _on_player_step() -> void:
	sfx_steps.stream = _steps_by_surface.get(player.surface, _steps_by_surface.stone)
	sfx_steps.volume_db = -3.0 if player.is_running else -7.0
	sfx_steps.play()


func _on_phase(phase: int) -> void:
	if phase >= 3 and not sfx_heart.playing:
		sfx_heart.volume_db = -14.0
		sfx_heart.play()
		create_tween().tween_property(sfx_heart, "volume_db", -3.0, 20.0)


func _on_door_approach(body: Node) -> void:
	if body == player and state == State.PLAYING and not safe_door.is_open:
		safe_door.open(sfx_creak)


func _on_safe_entered(body: Node) -> void:
	if body != player or state != State.PLAYING:
		return
	state = State.WON
	candle.stop()
	ScareLedger.level_completed()
	sfx_heart.stop()
	var left := int(round(candle.remaining() * 100.0))
	message.text = "Ты дома.\nСвеча продержалась %d:%02d — осталось %d%% воска" % [
		int(elapsed) / 60, int(elapsed) % 60, left]
	hint.text = "R — пройти снова"
	var tw := create_tween()
	tw.tween_property(message, "modulate:a", 1.0, 2.0)
	tw.parallel().tween_property(fade, "color:a", 0.55, 4.0)


## Game Over: свет гаснет полностью, тишина, затем из темноты за спиной приближается преследователь.
## Запись бега играет петлёй: темп (pitch_scale) растёт — шаг переходит в бег, скорость приближения
## пропорциональна темпу, громкость нарастает. Дыхание — отдельный 3D-источник на высоте головы, шина Scare.
func _on_extinguished() -> void:
	if state != State.PLAYING:
		return
	state = State.LOST
	player.input_enabled = false
	sfx_heart.stop()
	sfx_out.play()
	_blackout()
	await get_tree().create_timer(STALKER_DELAY).timeout
	var behind := player.global_transform.basis.z
	behind.y = 0.0
	behind = behind.normalized()
	var dist := STALKER_START_DIST
	var t := 0.0
	_place_stalker(behind, dist, 0.0)
	sfx_stalker.play()
	sfx_breath.play()
	while dist > STALKER_END_DIST:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		var k := smoothstep(0.0, STALKER_RAMP, t)
		dist -= STALKER_WALK_SPEED * sfx_stalker.pitch_scale / STALKER_PITCH.x * dt
		_place_stalker(behind, maxf(dist, STALKER_END_DIST), k)
	print("[GAME] преследователь у спины через %.1f с, темп %.2f" % [t, sfx_stalker.pitch_scale])
	sfx_stalker.stop()
	player.look_enabled = false
	message.text = "Пламя сорвалось на бегу." if candle.out_reason == "run" else "Свеча догорела."
	hint.text = "R — начать заново"
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.15)
	tw.tween_property(message, "modulate:a", 1.0, 1.5)
	tw.parallel().tween_property(sfx_breath, "volume_db", -40.0, 6.0)


## Шаги и дыхание преследователя: позиция за спиной игрока, темп и громкость по доле разгона k (0..1).
func _place_stalker(behind: Vector3, dist: float, k: float) -> void:
	var base := player.global_position + behind * dist
	sfx_stalker.global_position = base + Vector3.UP * 0.1
	sfx_stalker.pitch_scale = lerpf(STALKER_PITCH.x, STALKER_PITCH.y, k)
	sfx_stalker.volume_db = lerpf(STALKER_VOLUME.x, STALKER_VOLUME.y, k)
	sfx_breath.global_position = base + Vector3.UP * BREATH_HEIGHT
	sfx_breath.volume_db = lerpf(BREATH_VOLUME.x, BREATH_VOLUME.y, pow(k, 1.5))


## Кромешная тьма: все источники света уровня выключены, фон и туман погашены, экран — чёрный.
func _blackout() -> void:
	for n in find_children("*", "Light3D", true, false):
		(n as Light3D).visible = false
	env.environment.ambient_light_energy = 0.0
	env.environment.volumetric_fog_enabled = false
	env.environment.glow_enabled = false
	fade.color.a = 1.0
	RenderingServer.global_shader_parameter_set("candle_energy", 0.0)
