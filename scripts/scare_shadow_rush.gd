extends Area3D
## Гарантированный скример 6 «Рывок тени» (склеп, объединён с «шагами из темноты»): за узким поворотом
## в глубине коридора из темноты проступает силуэт с горящими глазами — и бросается навстречу.
## В шаге от игрока он распадается на пепел: хлопья осыпаются, пламя свечи шарахается.
## Силуэт — из рефа 15 (с туманным ореолом). Появляется только в поле зрения: на луче взгляда
## у границы света (до 8 м, без стен между), иначе ждёт, пока игрок посмотрит в коридор.

@export var scare_id := "shadow_rush"
@export var start_point := Vector3.ZERO      ## где появляется (низ фигуры, мир)
@export var speed := 10.0
@export var stop_dist := 1.4

const APPEAR_TIME := 0.6             ## силуэт стоит, прежде чем сорваться
const MAX_RUSH := 2.5
const WAIT_LIMIT := 8.0              ## сколько ждать удобного взгляда, прежде чем отложить скример
const SPAWN_DISTS := [5.5, 5.0, 4.5, 4.0, 3.5]   ## у границы света свечи — силуэт видно

var fired := false
var _sounds := {}
var _figure: MeshInstance3D
var _mat: ShaderMaterial
var _player: Node3D
var _rushing := false
var _t := 0.0
var _steps: AudioStreamPlayer3D
var _pending := false
var _wait := 0.0


func _ready() -> void:
	ScareLedger.register(scare_id)
	_sounds = {"run": HorrorAudio.variants("run", 6, 1.06, 1.5), "rush": HorrorAudio.one("shadow_rush"),
		"low": HorrorAudio.one("stinger_low")}
	body_entered.connect(_on_body_entered)
	set_process(false)


func _on_body_entered(body: Node) -> void:
	if not fired and body.is_in_group("player"):
		fire(body as Node3D)


func fire(player: Node3D) -> void:
	fired = true
	_player = player
	_pending = true
	_wait = 0.0
	set_process(true)


## Точка появления на луче взгляда: дальше всего, куда ещё видно (луч не упирается в стену), на полу.
func _find_spawn() -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.3:
		return null                       # смотрит в пол или в потолок
	fwd = fwd.normalized()
	var space := get_world_3d().direct_space_state
	var eye := cam.global_position
	for d in SPAWN_DISTS:
		var cand: Vector3 = eye + fwd * d
		var q := PhysicsRayQueryParameters3D.create(eye, cand)
		q.exclude = [(_player as CollisionObject3D).get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(cand, cand + Vector3.DOWN * 3.5))
		if down.is_empty():
			continue
		var foot: Vector3 = down.position
		if ScareFX.can_see(cam, foot + Vector3.UP * 1.2):
			return foot
	if ScareFX.can_see(cam, start_point + Vector3.UP * 1.2):
		return start_point
	return null


func _spawn(foot: Vector3) -> void:
	_pending = false
	ScareLedger.mark_fired(scare_id)
	print("[SCARE] тень бросилась из темноты (%.1f м)" % foot.distance_to(_player.global_position))
	_figure = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.95, 2.35)
	_figure.mesh = q
	_mat = ShadowFigure.make_material("shadow_photo")
	_mat.set_shader_parameter("eye_glow", 2.0)
	_mat.set_shader_parameter("tex_color", 1.0)
	_mat.set_shader_parameter("halo_glow", 1.6)
	_figure.material_override = _mat
	_figure.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_figure.top_level = true
	add_child(_figure)
	_figure.global_position = foot + Vector3.UP * 1.17
	_steps = AudioStreamPlayer3D.new()
	_steps.stream = _sounds.run
	_steps.unit_size = 4.0
	_steps.bus = "SFX"
	_figure.add_child(_steps)
	_face()
	set_process(true)
	await get_tree().create_timer(APPEAR_TIME).timeout
	_rushing = true
	var whoosh := AudioStreamPlayer3D.new()
	whoosh.stream = _sounds.rush
	whoosh.bus = "Scare"
	whoosh.unit_size = 5.0
	_figure.add_child(whoosh)
	whoosh.play()


func _process(delta: float) -> void:
	if _pending:
		_wait += delta
		var foot: Variant = _find_spawn()
		if foot != null:
			_spawn(foot)
		elif _wait > WAIT_LIMIT:
			_pending = false              # так и не посмотрел в коридор — скример остаётся на потом
			fired = false
			set_process(false)
		return
	_face()
	if not _rushing:
		return
	_t += delta
	var target := _player.global_position + Vector3.UP * 1.17
	var to := target - _figure.global_position
	to.y = 0.0
	if to.length() <= stop_dist or _t > MAX_RUSH:
		_burst()
		return
	_figure.global_position += to.normalized() * minf(speed * delta, to.length())
	_figure.global_position.y = target.y + absf(sin(_t * 9.0)) * 0.06
	if fmod(_t, 0.18) < delta:
		_steps.play()


## Билборд по вертикальной оси — силуэт всегда лицом к игроку.
func _face() -> void:
	var to := _player.global_position - _figure.global_position
	_figure.global_rotation = Vector3(0.0, atan2(to.x, to.z), 0.0)


func _burst() -> void:
	set_process(false)
	_rushing = false
	ScareFX.ash(get_tree().current_scene, _figure.global_position)
	var candle := _player.get_node_or_null("Head/Camera3D/Hand")
	if candle and candle.has_method("gust"):
		candle.gust(1.2)
	HorrorAudio.play_2d(self, _sounds.low, -4.0)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("dissolve", v), 0.0, 1.0, 0.35)
	tw.tween_callback(_figure.queue_free)
