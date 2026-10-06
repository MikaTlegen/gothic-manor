extends RefCounted
## Горрор-слой уровня поверх готовой геометрии (вызывается из tools/build_level.gd, стены не трогает):
## зоны комнат (пол + реверберация), звуки, фоновые источники, вид из окон, картины, статуи, зеркало,
## тени, сквозняки и одноразовые скримеры. Все скримеры — в группе "scares" (флаг fired).
## Шесть гарантированных скримеров срабатывают в узких проходах и учитываются ScareLedger
## (не сработавшие на этом уровне переносятся на следующий).

const UP := 2.16
const LOW := -1.08
const CELL := 2.0                    ## шаг сетки планировки, м (как в build_level.gd)
const GROUND := -1.0                 ## земля снаружи особняка (вид из окон бельэтажа)
const TEX := "res://assets/horror/textures/"
const HA := preload("res://scripts/horror_audio.gd")
const ROOM_ZONE := preload("res://scripts/room_zone.gd")
const VIEW_SHADER := preload("res://shaders/window_view.gdshader")
const AT := preload("res://scripts/autotest.gd")          ## маршруты (воск вдоль основного пути)
const EYE := UP + 1.62                                      ## высота глаз в галерее бельэтажа

## Реверберация по комнатам: коридоры, залы, склеп. «Своя комната» — сухая и тёплая.
const REVERB := {
	"S": "RevCorridor", "G": "RevCorridor", "U": "RevCorridor", "R": "RevCorridor", "D1a": "RevCorridor",
	"D2a": "RevCorridor", "P": "RevCorridor", "Q": "RevCorridor",
	"F1": "RevHall", "C": "RevHall", "H": "RevHall", "F2": "RevHall", "ST": "RevHall", "F3": "RevHall",
	"D1": "RevHall", "SP": "RevHall",
	"K": "RevCrypt", "D2": "RevCrypt",
}
const REVERB_AMOUNT := {"RevCorridor": 0.45, "RevHall": 0.6, "RevCrypt": 0.75}
## Полотна по комнатам (по кругу); «*» — следящий портрет
const PAINTINGS := {
	"G": ["rembrandt*", "saturn", "lady_blue*", "nightmare", "bocklin*", "leocadia", "innocent*", "witches"],
	"F1": ["tetschen", "witches", "nightmare", "saturn"],
	"D1": ["saturn", "leocadia", "witches"],
	"D1a": ["leocadia", "nightmare"],
	"U": ["tetschen", "saturn", "nightmare", "witches", "leocadia", "innocent"],
	"R": ["rembrandt", "lady_blue*", "bocklin", "innocent"],
	"SR": ["rembrandt"],
	"S": ["leocadia"],
}
const CREEP := ["innocent", "saturn"]   ## полотна с жутким двойником
const CREEP_ROOMS := ["U"]          ## темп: превращение только в галерее U — в G уже падает картина (F1)
const CLOCK_PERIOD := 2.0            ## период маятника = тик + так записи часов (петля 8.0 с / 4)
const CRYPT_BREATH_POS := Vector3(4, LOW + 0.75, -14)   ## дыхание из саркофага в глубине склепа K

var b                                ## сборщик уровня (build_level.gd)
var zones: Node3D
var horror: Node3D


func _init(builder) -> void:
	b = builder


func build() -> void:
	horror = b._group("Horror", b.groups.Gameplay)
	zones = b._group("Zones", horror)
	_room_zones()
	_sounds()
	_ambient_emitters()
	_dress_props()
	_window_views()
	_window_scare()
	_shadows()
	_guaranteed_scares()
	_navigation()
	_drafts()
	var dressing := Node.new()
	dressing.name = "Dressing"
	dressing.set_script(load("res://scripts/dressing.gd"))
	b._own(horror, dressing)


# ---------------------------------------------------------------------------
# Зоны комнат и звук
# ---------------------------------------------------------------------------

func _room_zones() -> void:
	for id in b.rooms:
		var r: Dictionary = b.rooms[id]
		var a := Area3D.new()
		a.name = "Zone_" + id
		a.set_script(ROOM_ZONE)
		a.set("surface", "wood" if r.fkind == "wood" else "stone")
		var bus: String = REVERB.get(id, "")
		if bus != "":
			a.reverb_bus_enabled = true
			a.reverb_bus_name = bus
			a.reverb_bus_amount = REVERB_AMOUNT[bus]
			a.reverb_bus_uniformity = 0.3
		b._own(zones, a)
		for rc in r.rects:
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(rc.size.x * CELL, r.ceil - r.min + 0.6, rc.size.y * CELL)
			cs.shape = box
			cs.position = Vector3((rc.position.x + rc.size.x * 0.5) * CELL, (r.min + r.ceil) * 0.5,
				(rc.position.y + rc.size.y * 0.5) * CELL)
			b._own(a, cs)


func _sounds() -> void:
	var gp: Node3D = b.groups.Gameplay
	var clock := gp.get_node("ClockTick") as AudioStreamPlayer3D
	clock.stream = HA.one("clock_user_loop")   # запись пользователя (Pixabay), петля из 8 ударов
	clock.unit_size = 5.0                    # 3D: слышен далеко, громче вблизи, панорама по направлению
	clock.max_distance = 75.0
	clock.volume_db = 4.0
	clock.attenuation_filter_cutoff_hz = 6000.0   # сквозь стены приглушён, но тиканье читается
	clock.attenuation_filter_db = -8.0
	clock.bus = "SFX"
	var fire := gp.get_node("FireCrackle") as AudioStreamPlayer3D
	fire.stream = HA.one("fire_loop")
	fire.bus = "SFX"
	var creak := gp.get_node("Creak") as AudioStreamPlayer3D
	creak.stream = HA.one("door_creak")
	creak.bus = "SFX"
	var stalker := gp.get_node("Stalker") as AudioStreamPlayer3D
	stalker.stream = HA.one("stalker_run_loop")       # бег пользователя (Pixabay): темп и громкость — в game.gd
	stalker.bus = "SFX"
	stalker.unit_size = 3.0
	stalker.max_distance = 40.0
	stalker.max_db = 10.0                          # по умолчанию 3 дБ — срезало бы нарастание громкости
	var breath := gp.get_node("StalkerBreath") as AudioStreamPlayer3D
	breath.stream = HA.one("stalker_breath")         # тяжёлое дыхание (Pixabay) — отдельная шина, поверх шагов
	breath.bus = "Scare"
	breath.unit_size = 2.0
	breath.max_distance = 30.0
	breath.max_db = 8.0
	var amb := gp.get_node("Ambience") as AudioStreamPlayer
	amb.stream = HA.one("drone_loop")
	amb.volume_db = -8.0
	amb.bus = "Ambient"
	var heart := gp.get_node("Heartbeat") as AudioStreamPlayer
	heart.stream = HA.one("heartbeat_loop")
	heart.bus = "Scare"


func _ambient_emitters() -> void:
	var beams := HA.variants("creak_beam", 4, 1.15, 3.0)
	var floors := HA.variants("creak_floor", 3, 1.1, 3.0)
	var spots := [
		["Beam_G", Vector3(24, 3.4, 36), beams], ["Beam_F1", Vector3(24, 3.7, 22), beams],
		["Beam_D1", Vector3(10, 3.3, 22), beams], ["Beam_C", Vector3(24, 1.8, 10), beams],
		["Beam_H", Vector3(24, 3.6, 0), beams], ["Beam_U1", Vector3(17, 5.0, -46), beams],
		["Beam_U2", Vector3(29, 5.0, -40), beams], ["Beam_F3", Vector3(28, 5.0, -20), beams],
		["Floor_S", Vector3(25, 0.1, 50), floors], ["Floor_U", Vector3(29, UP + 0.1, -30), floors],
		["Floor_G", Vector3(23, 0.1, 30), floors],
	]
	for s in spots:
		var e := _emitter(s[0], s[1], s[2], -6.0, 4.0, 22.0)
		e.set("min_interval", 14.0)
		e.set("max_interval", 40.0)
	# Сквозняк в окнах галереи и холодная тяга склепа — тихие петли
	for s in [["Wind_U_West", Vector3(16.4, UP + 1.6, -45)], ["Wind_U_North", Vector3(23, UP + 1.6, -55.6)],
			["Wind_K", Vector3(4, LOW + 1.2, -14)]]:
		var w := _emitter(s[0], s[1], HA.one("wind_loop"), -16.0, 3.0, 18.0)
		w.set("loop_stream", true)
	# Испуганное дыхание / мычание из саркофага (запись пользователя, Pixabay): локальный источник —
	# обратный квадрат (−12 дБ на удвоение расстояния), за стенами глушится ФНЧ; громче и отчётливее вблизи
	var crypt := _emitter("Crypt_Breath", CRYPT_BREATH_POS, HA.one("crypt_breath_loop"), 4.0, 2.0, 16.0)
	crypt.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	crypt.attenuation_filter_cutoff_hz = 2500.0
	crypt.attenuation_filter_db = -18.0
	crypt.set("loop_stream", true)


func _emitter(n: String, pos: Vector3, stream: AudioStream, vol: float, unit: float, max_d: float) -> AudioStreamPlayer3D:
	var e := AudioStreamPlayer3D.new()
	e.name = n
	e.set_script(load("res://scripts/ambient_emitter.gd"))
	e.stream = stream
	e.position = pos
	e.volume_db = vol
	e.unit_size = unit
	e.max_distance = max_d
	e.bus = "SFX"
	b._own(horror, e)
	return e


# ---------------------------------------------------------------------------
# Картины, статуи, зеркало, часы
# ---------------------------------------------------------------------------

func _dress_props() -> void:
	var counters := {}
	for n in b.groups.Props.get_children():
		var path: String = n.scene_file_path
		if path.ends_with("Portrait_Frame.gltf"):
			_portrait(n, counters)
		elif path.ends_with("Statue_Angel_Leubner.gltf"):
			_statue(n, "Statue_Angel_Leubner_Figure", 0.0)     # памятник целиком — без наклона
		elif path.ends_with("Statue_Angel_Miller.gltf"):
			n.set_script(load("res://scripts/statue_head.gd"))
			n.set("head_name", "Statue_Angel_Miller_Head")
			n.set("head_pitch", -0.3)     # голова скана склонена — при повороте приподнимается к игроку
			n.add_to_group("scares", true)
			_chokepoint(n, "Chokepoint_K_F2", Vector3(4, LOW + 1.1, -26), Vector3(4.2, 2.2, 1.0))
		elif path.ends_with("Mirror_Baroque.gltf"):
			n.set_script(load("res://scripts/mirror.gd"))
			n.set("player_path", NodePath("../../Player"))
			n.add_to_group("scares", true)
			# Рассинхрон отражения взводится при входе в «Два зеркала» через любой из узких проходов
			_chokepoint(n, "Chokepoint_U", Vector3(29, UP + 1.2, -24), Vector3(2.0, 2.4, 1.0))
			_chokepoint(n, "Chokepoint_Q", Vector3(31, UP + 1.2, -16), Vector3(2.0, 2.4, 1.0))
		elif path.ends_with("Clock_Grandfather.gltf"):
			n.set("period", CLOCK_PERIOD)


func _portrait(n: Node3D, counters: Dictionary) -> void:
	var tint := Color.WHITE
	if n.get_script() != null:
		tint = n.get("tint")
	var room := _room_at(n.position + n.basis.z * 0.4)
	var list: Array = PAINTINGS.get(room, ["nightmare"])
	var k: int = counters.get(room, 0)
	counters[room] = k + 1
	var pick: String = list[k % list.size()]
	n.set_script(load("res://scripts/portrait.gd"))
	n.set("tint", tint)
	n.set("painting", pick.trim_suffix("*"))
	n.set("follow", pick.ends_with("*"))
	n.add_to_group("portraits", true)
	# Часть картин превращается под взглядом пламени (жуткие двойники из PD-оригиналов)
	var base := pick.trim_suffix("*")
	if base in CREEP and room in CREEP_ROOMS:
		n.set("creep_painting", base + "_creep")
		n.add_to_group("scares", true)


func _statue(n: Node3D, figure: String, lean: float) -> void:
	n.set_script(load("res://scripts/statue_watch.gd"))
	n.set("figure_name", figure)
	n.set("lean_deg", lean)
	n.add_to_group("scares", true)


func _room_at(p: Vector3) -> String:
	var c := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	for id in b.cell_rooms.get(c, []):
		var r: Dictionary = b.rooms[id]
		if p.y >= r.min - 0.3 and p.y <= r.ceil:
			return id
	return ""


# ---------------------------------------------------------------------------
# Вид из окон: слои-диорамы (фон-картина, дальние и ближние силуэты деревьев, земля)
# ---------------------------------------------------------------------------

func _window_views() -> void:
	var views := Node3D.new()
	views.name = "WindowViews"
	b._own(horror, views)
	# Фото из рефов пользователя (2 и 4): горизонт фото — на высоте глаз, плоскость за пределами комнат.
	# Север: окна в стене z = -56 (x 17..29), взгляд на -Z; фото 2 (1.53:1), горизонт на 72% высоты
	_view_plane(views, "North_Photo", "view_photo_north.jpg", Vector3(23, EYE + 0.22 * 56.0, -100),
		Vector2(85.5, 56.0), 0.0)
	# Запад: окна в стене x = 16 (z -55..-35), взгляд на -X; фото 4 (2:1), горизонт на 80% высоты
	_view_plane(views, "West_Photo", "view_photo_west.jpg", Vector3(-40, EYE + 0.3 * 65.0, -45),
		Vector2(130.0, 65.0), PI / 2)


func _view_plane(parent: Node3D, n: String, tex: String, center: Vector3, size: Vector2, yaw: float, haze := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.name = n
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = VIEW_SHADER
	m.set_shader_parameter("tex", load(TEX + tex))
	m.set_shader_parameter("haze", haze)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	b._own(parent, mi)


func _ground(parent: Node3D, n: String, center: Vector3, size: Vector2) -> void:
	var mi := MeshInstance3D.new()
	mi.name = n
	var p := PlaneMesh.new()
	p.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.17, 0.2, 0.27)      # лунный туман над землёй: на нём читается силуэт
	m.disable_fog = true
	p.material = m
	mi.mesh = p
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = center
	b._own(parent, mi)


# ---------------------------------------------------------------------------
# Скримеры
# ---------------------------------------------------------------------------

func _window_scare() -> void:
	var s := Node3D.new()
	s.name = "WindowScare"
	s.set_script(load("res://scripts/scare_window.gd"))
	s.set("window_point", Vector3(17, UP + 1.6, -56))
	s.set("run_from", Vector3(21.5, GROUND, -93))
	s.set("run_to", Vector3(17.6, GROUND, -57))
	s.add_to_group("scares", true)
	b._own(horror, s)
	_trigger(s, "Trigger", Vector3(17, UP + 1.5, -49.5), Vector3(2.0, 3.0, 5.0))
	var runner := MeshInstance3D.new()
	runner.name = "Runner"
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 2.0)
	runner.mesh = q
	runner.top_level = true
	b._own(s, runner)


func _shadows() -> void:
	var spots := [
		["Shadow_Hall", Vector3(20.5, LOW, -2.5)],
		["Shadow_Chapel", Vector3(-9.0, LOW, -33.6)],
		["Shadow_Gallery", Vector3(29.6, UP, -32.0)],
	]
	for s in spots:
		var mi := MeshInstance3D.new()
		mi.name = s[0]
		var q := QuadMesh.new()
		q.size = Vector2(0.95, 2.3)
		mi.mesh = q
		mi.set_script(load("res://scripts/shadow_figure.gd"))
		mi.position = s[1] + Vector3.UP * 1.15
		mi.add_to_group("scares", true)
		b._own(horror, mi)


func _drafts() -> void:
	var spots := [
		["Draft_S_G", Vector3(25, 1.2, 44), Vector3(2.0, 2.4, 1.6), "whisper_1"],
		["Draft_D1a", Vector3(14.6, 1.2, 23), Vector3(1.6, 2.4, 2.0), "whisper_2"],
		["Draft_D2a", Vector3(-0.6, LOW + 1.2, -31), Vector3(1.6, 2.4, 2.0), "whisper_1"],
		["Draft_P", Vector3(29, LOW + 1.0, -7.5), Vector3(2.0, 2.0, 2.0), "whisper_2"],
		["Draft_F3_R", Vector3(32.6, UP + 1.2, -20), Vector3(1.6, 2.4, 4.0), "whisper_1"],
	]
	for s in spots:
		var a := Area3D.new()
		a.name = s[0]
		a.set_script(load("res://scripts/draft_zone.gd"))
		a.set("whisper", s[3])
		a.position = s[1]
		a.add_to_group("scares", true)
		b._own(horror, a)
		_shape(a, Vector3.ZERO, s[2])
		var gust := AudioStreamPlayer3D.new()
		gust.name = "Gust"
		gust.stream = HA.one("draft_gust")
		gust.volume_db = -4.0
		gust.unit_size = 3.0
		gust.bus = "SFX"
		b._own(a, gust)


# ---------------------------------------------------------------------------
# Гарантированные скримеры в узких проходах (ScareLedger)
# ---------------------------------------------------------------------------

func _guaranteed_scares() -> void:
	var g := Node3D.new()
	g.name = "Guaranteed"
	b._own(horror, g)
	# 1. Картина: проём галерея → «Дева»; срывается портрет на восточной стене F1 (лицом на запад) у тропы
	var pick: Node3D = null
	for n in b.groups.Props.get_children():
		if not n.scene_file_path.ends_with("Portrait_Frame.gltf") or n.basis.z.normalized().x > -0.9:
			continue
		if _room_at(n.position + n.basis.z * 0.4) != "F1":
			continue
		if pick == null or absf(n.position.z - 24.5) < absf(pick.position.z - 24.5):
			pick = n
	var painting := _scare_area(g, "PaintingFall", "res://scripts/scare_painting.gd", Vector3(24, 1.2, 28.3),
		Vector3(4.2, 2.4, 1.0))
	if pick:
		painting.set("painting_path", painting.get_path_to(pick))
	# 2. Ладони в окно: верх парадной лестницы → западное окно галереи (z -39)
	var hand := _scare_area(g, "HandSlam", "res://scripts/scare_hand_window.gd", Vector3(17, UP + 1.2, -36.6),
		Vector3(2.0, 2.4, 1.2))
	hand.set("window_point", Vector3(15.85, UP + 1.6, -39))
	hand.set("inward", Vector3.RIGHT)
	# 3. Дверь в проёме галерея → «Два зеркала»: распахнута, захлопывается за спиной
	var door: Node3D = b._inst("Door_Gothic")
	door.name = "SlamDoor"
	door.transform = Transform3D(Basis().scaled(Vector3.ONE * 0.78), Vector3(29, UP, -24))
	b._own(g, door)
	var slam := _scare_area(g, "DoorSlam", "res://scripts/scare_door_slam.gd", Vector3(29.5, UP + 1.2, -21.6),
		Vector3(4.0, 2.4, 1.4))
	slam.set("door_path", slam.get_path_to(door))
	# 6. Рывок тени: поворот склепа на север; силуэт встаёт в глубине коридора за пределом света
	var rush := _scare_area(g, "ShadowRush", "res://scripts/scare_shadow_rush.gd", Vector3(4.5, LOW + 1.1, -3.5),
		Vector3(4.0, 2.2, 1.2))
	rush.set("start_point", Vector3(5.3, LOW, -17))
	# Темп: «шаги из темноты» — вход в зал H из колоннады (общий участок основного пути и срезки, ~55 с);
	# бег начинается в глубине зала у пролома и обрывается у границы света
	var steps_zone := _scare_area(g, "StalkerSteps", "res://scripts/scare_stalker.gd", Vector3(25, LOW + 1.1, 3.2),
		Vector3(4.0, 2.2, 1.2))
	steps_zone.set("start_point", Vector3(28.5, LOW, -9.5))
	var run := AudioStreamPlayer3D.new()
	run.name = "Steps"
	run.stream = HA.variants("run", 6, 1.08, 2.0)
	run.bus = "SFX"
	run.unit_size = 3.0
	run.max_distance = 30.0
	b._own(steps_zone, run)
	# 4 и 5 — зеркало и статуя: их проходы — в _dress_props (Chokepoint_*)


func _scare_area(parent: Node3D, n: String, script: String, pos: Vector3, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.name = n
	a.set_script(load(script))
	a.position = pos
	a.add_to_group("scares", true)
	b._own(parent, a)
	_shape(a, Vector3.ZERO, size)
	return a


## Узкий проход-триггер внутри ассета (мировые координаты, не наследует поворот ассета).
func _chokepoint(owner_node: Node3D, n: String, pos: Vector3, size: Vector3) -> void:
	var a := Area3D.new()
	a.name = n
	a.top_level = true
	b._own(owner_node, a)
	a.position = pos
	_shape(a, Vector3.ZERO, size)


# ---------------------------------------------------------------------------
# Неявная навигация: капли воска вдоль верного пути, вытоптанные дорожки на коврах
# ---------------------------------------------------------------------------

func _navigation() -> void:
	var nav := Node3D.new()
	nav.name = "Navigation"
	b._own(horror, nav)
	# Капли воска — один MultiMesh (один вызов отрисовки): плоские квады на полу с альфа-отсечением
	var route: Array = AT.MAIN_A + AT.MAIN_F1 + AT.MAIN_B + AT.MAIN_C + AT.MAIN_F2 + AT.MAIN_D + AT.FINISH
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var xfs: Array[Transform3D] = []
	var step := 4.5
	var acc := 0.0
	for i in range(route.size() - 1):
		var a: Vector2 = route[i]
		var c: Vector2 = route[i + 1]
		var seg := a.distance_to(c)
		var t := step - acc
		while t < seg:
			var p := a.lerp(c, t / seg) + Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35))
			var y := _floor_at(p)
			if not is_nan(y):
				var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2))
				xfs.append(Transform3D(basis, Vector3(p.x, y + 0.006, p.y)))
			t += step
		acc = fmod(acc + seg, step)
	var wax := MultiMeshInstance3D.new()
	wax.name = "WaxDrops"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := PlaneMesh.new()
	q.size = Vector2(0.3, 0.3)
	q.material = _floor_decal_mat("wax_drops_albedo.png", "wax_drops_normal.jpg", 0.35)
	mm.mesh = q
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
	wax.multimesh = mm
	wax.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b._own(nav, wax)
	# Дорожки на коврах вдоль маршрута: ворс сбит посередине — ходили здесь часто
	var wear_mat := _floor_decal_mat("carpet_wear_albedo.png", "", 0.85, true)
	for n in b.groups.Props.get_children():
		if not n.scene_file_path.ends_with("Carpet_Runner.gltf"):
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Wear_" + n.name
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.9, 4.4)
		pm.material = wear_mat
		mi.mesh = pm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(n.basis.orthonormalized(), n.position + Vector3.UP * 0.03)
		b._own(nav, mi)


## Материал «наклейки» на пол: альфа-отсечение (воск) или полупрозрачность (потёртость ковра).
func _floor_decal_mat(albedo: String, normal: String, rough: float, blend := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + albedo)
	if normal != "":
		m.normal_enabled = true
		m.normal_texture = load(TEX + normal)
	m.roughness = rough
	if blend:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.4
	return m


## Высота пола в точке плана (по комнате и клетке); NaN — лестницы и места без ровного пола.
func _floor_at(p: Vector2) -> float:
	var c := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	for id in b.cell_rooms.get(c, []):
		if id in ["ST", "SP", "Q"]:
			return NAN
		if id == "C" and p.y > 11.6 and p.y < 14.6:
			return NAN                   # марш колоннады
		return b.cfloor(b.rooms[id], c)
	return NAN


func _trigger(parent: Node3D, n: String, pos: Vector3, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.name = n
	a.position = pos
	a.top_level = true
	b._own(parent, a)
	_shape(a, Vector3.ZERO, size)
	return a


func _shape(a: Area3D, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	b._own(a, cs)
