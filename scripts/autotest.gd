extends Node
## Автопроверка уровня. Запуск (с окном — нужен рендер):
##   Godot --path . -- --autotest shots           скриншоты ключевых точек → _verify/
##   Godot --path . -- --autotest map             карта сверху без потолков → _verify/map.png
##   Godot --path . -- --autotest route_main      прохождение основного маршрута по таймеру свечи
##   Godot --path . -- --autotest route_shortcut  то же через срезку (винтовая лестница)
##   Godot --path . -- --autotest route_deadends  основной маршрут с заходом в оба тупика
## Без флага --autotest узел ничего не делает.

const OUT_DIR := "res://_verify"
const TIME_SCALE := 3.0

## Основной маршрут (x, z): старт → галерея → «Дева» → колоннада → зал → склеп → «Ангел» →
## парадная лестница → галерея с окнами → «Два зеркала» → ухоженный коридор → «Своя комната».
const MAIN_A := [
	Vector2(40.7, 66), Vector2(40.6, 58), Vector2(41, 55), Vector2(25, 55), Vector2(25, 45), Vector2(25, 43), Vector2(25, 29),
	Vector2(25, 27)]
const MAIN_F1 := [Vector2(26.8, 25.2), Vector2(26.8, 22.5), Vector2(25, 21)]
const MAIN_B := [
	Vector2(25, 19), Vector2(25, 15), Vector2(24.6, 13.5), Vector2(24.6, 11.6), Vector2(25, 10), Vector2(25, 7),
	Vector2(25, 5)]
const MAIN_C := [
	Vector2(20, 1.2), Vector2(17, 1.2), Vector2(14, 1.3), Vector2(9, 1.3), Vector2(4.5, 1.3), Vector2(4.6, -2),
	Vector2(5.2, -11), Vector2(5.2, -17), Vector2(4.6, -20), Vector2(5, -25), Vector2(5, -27)]
const MAIN_F2 := [Vector2(6.3, -29), Vector2(7, -31)]
const MAIN_D := [
	Vector2(9, -31), Vector2(11, -31), Vector2(16.2, -31), Vector2(17, -31), Vector2(17, -33), Vector2(17, -35),
	Vector2(17, -55), Vector2(29, -55), Vector2(29, -25), Vector2(29, -23), Vector2(31, -21), Vector2(33, -21)]
const FINISH := [Vector2(46.5, -20.2), Vector2(48.5, -20), Vector2(51, -20)]
const SHORT_A := [
	Vector2(28, -3), Vector2(29, -5), Vector2(29, -7), Vector2(29, -12.9), Vector2(31, -13), Vector2(32.6, -13.3),
	Vector2(32.7, -13.9), Vector2(32.8, -14.45), Vector2(33.35, -14.24)]
const SHORT_B := [
	Vector2(33.1, -13.3), Vector2(31.5, -13), Vector2(31, -13), Vector2(31, -15), Vector2(31, -17), Vector2(31, -19),
	Vector2(33, -19)]
const DEAD1 := [
	Vector2(21.5, 23), Vector2(19, 23), Vector2(14, 23), Vector2(9.2, 23), Vector2(14, 23), Vector2(19, 23),
	Vector2(21.5, 23), Vector2(22.5, 21.3), Vector2(25, 21)]
const DEAD2 := [
	Vector2(1.5, -29), Vector2(1.5, -31), Vector2(-1, -31), Vector2(-5, -31), Vector2(-8, -31), Vector2(-5, -31),
	Vector2(-1, -31), Vector2(1.5, -31), Vector2(7, -31)]

## Ключевые точки для скриншотов: имя, позиция, точка взгляда, доля сгоревшей свечи.
const SHOTS := [
	["01_start", Vector3(41, 0, 67), Vector3(41, 1.5, 55), 0.0],
	["02_servants_corridor", Vector3(25, 0, 53), Vector3(25, 1.4, 44), 0.05],
	["03_portrait_gallery", Vector3(24, 0, 42.5), Vector3(24, 1.5, 30), 0.1],
	["04_weeping_maiden", Vector3(25, 0, 27.4), Vector3(24, 2.0, 24), 0.15],
	["05_burned_dining", Vector3(13.2, 0, 23), Vector3(8, 1.0, 22), 0.2],
	["06_colonnade_terrace", Vector3(24.5, 0, 16.5), Vector3(24.5, -1.0, 9), 0.25],
	["07_colonnade_lower", Vector3(24, -1.08, 7.6), Vector3(24, 0.2, 14), 0.3],
	["08_hall_locked_door", Vector3(23, -1.08, 1.5), Vector3(22, 0.2, -6), 0.35],
	["09_hall_breach", Vector3(27, -1.08, -2.5), Vector3(29, -0.1, -6), 0.35],
	["10_crypt_k1", Vector3(16.5, -1.08, 1.0), Vector3(4, -0.4, 0), 0.4],
	["11_crypt_k2", Vector3(5, -1.08, -4.5), Vector3(4, -0.4, -20), 0.45],
	["12_angel", Vector3(5.2, -1.08, -26.6), Vector3(4, 0.8, -30), 0.5],
	["13_chapel", Vector3(-6.4, -1.08, -31), Vector3(-12, -0.4, -31), 0.55],
	["14_grand_stairs", Vector3(9.8, -1.08, -31), Vector3(17, 1.4, -31), 0.55],
	["15_spiral", Vector3(31.2, -1.08, -13), Vector3(34, 0.4, -14), 0.4],
	["16_upper_windows", Vector3(17, 2.16, -40), Vector3(17, 3.6, -54), 0.65],
	["17_upper_east", Vector3(29, 2.16, -36), Vector3(29, 3.4, -24), 0.7],
	["18_two_mirrors", Vector3(29, 2.16, -20.5), Vector3(24, 3.4, -20), 0.75],
	["19_care_corridor", Vector3(35, 2.16, -20), Vector3(48, 3.2, -20), 0.85],
	["20_plaque_door", Vector3(44.6, 2.16, -19.6), Vector3(47.9, 3.4, -21.0), 0.6],
	["22_window_north", Vector3(17, 2.16, -52.5), Vector3(17, 3.4, -60), 0.65],
	["23_window_west", Vector3(17.6, 2.16, -45.5), Vector3(8, 3.4, -47.5), 0.65],
	["24_cobweb_candle", Vector3(41, 0, 59.4), Vector3(41, 2.3, 57.5), 0.05],
	["25_portraits", Vector3(24.4, 0, 38.6), Vector3(22.1, 1.95, 41), 0.1],
	["26_shadow_hall", Vector3(23.4, -1.08, 2.4), Vector3(20.5, -0.1, -2.5), 0.35],
	["27_mirror", Vector3(25.0, 2.16, -19.4), Vector3(25, 3.3, -16), 0.75],
	["21_safe_room", Vector3(49.6, 2.16, -18.2), Vector3(56, 3.0, -21), 0.9],   # последним: вход в зону = победа
]

var game: Node3D
var player: CharacterBody3D
var candle: Node3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--autotest")
	if i < 0:
		return
	var mode: String = args[i + 1] if args.size() > i + 1 else "shots"
	game = get_parent()
	player = game.get_node("Player")
	candle = game.get_node("Player/Head/Camera3D/Hand")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# Замер производительности: --hide путь1,путь2 — отключить узлы сцены (A/B по FPS)
	var h := args.find("--hide")
	if h >= 0 and args.size() > h + 1:
		for path in args[h + 1].split(","):
			var n := game.get_node_or_null(path)
			if n:
				n.queue_free()
				print("[AUTOTEST] отключено: ", path)
	await get_tree().create_timer(0.5).timeout
	match mode:
		"shots":
			await _shots()
		"map":
			await _map()
		"route_main":
			await _route("main", MAIN_A + MAIN_F1 + MAIN_B + MAIN_C + MAIN_F2 + MAIN_D + FINISH)
		"route_shortcut":
			await _route("shortcut", MAIN_A + MAIN_F1 + MAIN_B + SHORT_A + _spiral() + SHORT_B + FINISH)
		"route_deadends":
			await _route("deadends", MAIN_A + DEAD1 + MAIN_B + MAIN_C + DEAD2 + MAIN_D + FINISH)
		"scares":
			await _scares()
		"rails":
			await _rails()
		"candle":
			await _candle_test()
	get_tree().quit()


## Подъём по винтовой лестнице: ступень 0 на азимуте 185°, полный оборот (+X → -Z → -X → +Z).
## Заходить нужно по касательной от начала марша (азимут ~170°), как живой игрок, — сбоку торец пандуса.
func _spiral() -> Array:
	var pts := []
	for a in range(170, 530, 10):
		var r := deg_to_rad(a)
		pts.append(Vector2(34.0 + 0.72 * cos(r), -14.0 - 0.72 * sin(r)))
	return pts


func _hide_ui() -> void:
	for t in get_tree().get_processed_tweens():
		t.kill()
	game.get_node("UI/Fade").color.a = 0.0
	game.get_node("UI/Message").modulate.a = 0.0


func _shots() -> void:
	await get_tree().create_timer(1.0).timeout
	_hide_ui()
	candle.stop()
	player.input_enabled = false
	for s in SHOTS:
		player.global_position = s[1] + Vector3(0, 0.05, 0)
		player.velocity = Vector3.ZERO
		var eye: Vector3 = s[1] + Vector3(0, 1.62, 0)
		var to: Vector3 = s[2] - eye
		player.rotation.y = atan2(-to.x, -to.z)
		player.get_node("Head").rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
		candle.burned = s[3]
		for k in 40:
			await get_tree().process_frame
		_save(s[0])


## Поставить игрока в точку и направить взгляд; burned — доля сгоревшей свечи (радиус света).
func _pose(pos: Vector3, look: Vector3, burned: float, frames := 20) -> void:
	player.global_position = pos + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	var to: Vector3 = look - (pos + Vector3(0, 1.62, 0))
	player.rotation.y = atan2(-to.x, -to.z)
	player.get_node("Head").rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	candle.burned = burned
	for k in frames:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Проход по всем скримерам: шесть гарантированных (узкие проходы, ScareLedger) и прежние одноразовые.
## Каждый должен сработать ровно один раз (повторный заход — без реакции).
func _scares() -> void:
	get_node("/root/ScareLedger").set("pacing", false)     # автолоад по пути: autotest.gd компилируется и в сборщике уровня
	await _wait(1.0)
	_hide_ui()
	candle.stop()
	player.input_enabled = false
	# 1. Картина: проём галерея → «Дева»
	await _pose(Vector3(24.5, 0, 24.0), Vector3(27.9, 1.4, 21.0), 0.1, 30)
	_save("g1_painting_before")
	await _pose(Vector3(24, 0, 30.5), Vector3(27.5, 1.2, 24.5), 0.1)
	await _pose(Vector3(24, 0, 28.3), Vector3(27.5, 1.2, 24.5), 0.1, 5)
	await _pose(Vector3(24.5, 0, 24.0), Vector3(27.9, 1.4, 21.0), 0.1, 5)
	await _wait(0.45)
	_save("g1_painting_falling")
	await _wait(1.2)
	_save("g1_painting_dust")
	# 2. Ладони в окно: верх парадной лестницы
	await _pose(Vector3(17, 2.16, -35.2), Vector3(15.9, 3.7, -39), 0.65)
	await _pose(Vector3(17, 2.16, -36.6), Vector3(15.9, 3.7, -39), 0.65, 5)
	await _pose(Vector3(17.1, 2.16, -38.2), Vector3(15.9, 3.7, -39.1), 0.65, 5)
	await _wait(0.9)
	_save("g2_hand_slam")
	await _pose(Vector3(17.5, 2.16, -39.0), Vector3(15.85, 3.76, -39.0), 0.65, 3)
	_save("g2_figure_front")
	await _wait(2.5)
	await _pose(Vector3(16.7, 2.16, -38.5), Vector3(15.85, 3.75, -39.0), 0.65, 10)
	_save("g2_hand_print")
	# 3. Дверь: проём галерея → «Два зеркала», захлопывается за спиной; свеча гаснет на 1.5 с
	await _pose(Vector3(29, 2.16, -25.5), Vector3(29, 3.6, -20), 0.7)
	await _pose(Vector3(29, 2.16, -24.0), Vector3(29, 3.6, -20), 0.7, 10)
	await _pose(Vector3(29.5, 2.16, -21.6), Vector3(29.5, 3.6, -16), 0.7, 10)
	await _wait(0.6)
	_save("g3_door_dark")
	await _wait(2.0)
	await _pose(Vector3(29.5, 2.16, -21.6), Vector3(29, 3.4, -24.5), 0.7)
	_save("g3_door_shut")
	# 4. Зеркало: рассинхрон отражения (проход взведён выше), затем силуэт за спиной
	await _pose(Vector3(25.0, 2.16, -18.6), Vector3(25, 3.3, -16), 0.75, 30)
	await _wait(1.2)
	await _pose(Vector3(25.5, 2.16, -18.9), Vector3(25, 3.3, -16), 0.75, 10)
	await _wait(1.8)
	_save("g4_mirror_desync")
	_save_mirror("g4_mirror_view")
	await _wait(4.1)
	_save("scare_mirror_ghost")
	_save_mirror("scare_mirror_ghost_view")
	await _pose(Vector3(25.0, 2.16, -19.4), Vector3(25, 3.3, -24), 0.75)
	# 5. Статуя: проход склеп → «Ангел», подход вплотную
	await _pose(Vector3(4, -1.08, -26), Vector3(4, 0.6, -30), 0.5, 10)
	await _pose(Vector3(5.4, -1.08, -28.0), Vector3(4, 0.9, -30), 0.5, 10)
	await _wait(2.2)
	_save("g5_statue_head")
	# 6. Рывок тени: поворот склепа на север
	await _pose(Vector3(4.5, -1.08, -2.0), Vector3(5.3, 0.1, -17), 0.45)
	await _pose(Vector3(4.5, -1.08, -3.5), Vector3(5.3, 0.1, -17), 0.45, 5)
	await _wait(0.4)
	_save("g6_shadow_appears")
	await _wait(1.15)
	_save("g6_shadow_rush")
	await _wait(0.35)
	_save("g6_shadow_ash")
	# Превращение картины под взглядом пламени
	for n in get_tree().get_nodes_in_group("portraits"):
		if n.get("creep_painting") != "":
			var p: Node3D = n
			var foot: Vector3 = p.global_position + p.global_basis.z.normalized() * 2.0
			foot.y = p.global_position.y - 1.95
			await _pose(foot + p.global_basis.z.normalized() * 3.0, p.global_position, 0.2, 10)
			_save("g7_portrait_before")
			await _pose(foot, p.global_position, 0.2, 2)
			await _wait(1.5)
			_save("g7_portrait_creep")
			print("[AUTOTEST] картина %s (%s) превратилась=%s" % [p.name, p.get("painting"), p.get("fired")])
			break
	# Прежние: силуэт за окном, тень в зале, «Дева», сквозняк
	await _pose(Vector3(17, 2.16, -49.5), Vector3(17, 3.2, -60), 0.65)
	await _wait(1.2)
	_save("scare_window_run")
	await _pose(Vector3(22.0, -1.08, 0.5), Vector3(20.5, -0.1, -2.5), 0.35)
	await _wait(0.3)
	await _pose(Vector3(26.8, 0, 22.5), Vector3(24, 1.5, 24), 0.15)
	await _pose(Vector3(25, 0, 17), Vector3(25, 1.5, 8), 0.15)
	await _pose(Vector3(25, 0, 17), Vector3(24, 1.8, 24), 0.15)
	await _pose(Vector3(25, 0, 44), Vector3(25, 1.5, 36), 0.1)
	await _wait(0.6)
	# Повторные заходы во все проходы: ничего не должно сработать снова
	for pt in [Vector3(24, 0, 28.3), Vector3(17, 2.16, -36.6), Vector3(29.5, 2.16, -21.6), Vector3(4, -1.08, -26),
			Vector3(4.5, -1.08, -3.5), Vector3(25, 0, 44)]:
		await _pose(pt + Vector3(0, 0, 2.0), pt + Vector3(0, 1.5, -5), 0.3, 5)
		await _pose(pt, pt + Vector3(0, 1.5, -5), 0.3, 10)
	await _wait(1.0)
	var n := 0
	var fired := 0
	for sc in get_tree().get_nodes_in_group("scares"):
		n += 1
		fired += 1 if sc.get("fired") else 0
		print("[AUTOTEST] скример %s сработал=%s" % [sc.name, sc.get("fired")])
	print("[AUTOTEST] скримеров %d, сработало %d" % [n, fired])
	# Автолоад берётся по пути: autotest.gd подключается и сборщиком уровня, где автолоадов нет
	print("[AUTOTEST] гарантированные не сработали: %s" % [get_node("/root/ScareLedger").missed()])


func _save_mirror(shot_name: String) -> void:
	for m in get_tree().get_nodes_in_group("scares"):
		for c in m.get_children():
			if c is SubViewport:
				c.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + shot_name + ".png"))


## Пробы падения с лестниц: игрок стоит на марше и идёт наружу через край (к перилам).
## Перепад высоты больше 0.4 м — падение (перила не держат).
func _rails() -> void:
	await _wait(1.0)
	_hide_ui()
	candle.stop()
	var probes := [
		["colonnade_W_top", Vector3(22.5, -0.2, 13.4), Vector3(19.5, 0, 13.4)],
		["colonnade_W_mid", Vector3(22.5, -0.6, 12.8), Vector3(19.5, 0, 12.8)],
		["colonnade_E_top", Vector3(25.5, -0.2, 13.4), Vector3(28.5, 0, 13.4)],
		["colonnade_E_mid", Vector3(25.5, -0.6, 12.8), Vector3(28.5, 0, 12.8)],
		["grand_N", Vector3(13.0, -0.3, -31.0), Vector3(13.0, 0, -34.0)],
		["grand_S", Vector3(13.0, -0.3, -31.0), Vector3(13.0, 0, -28.0)],
		["landing_E", Vector3(17.0, 1.1, -31.0), Vector3(20.0, 0, -31.0)],
		["narrow_W", Vector3(17.0, 1.6, -33.0), Vector3(14.0, 0, -33.0)],
		["narrow_E", Vector3(17.0, 1.6, -33.0), Vector3(20.0, 0, -33.0)],
	]
	for a in [230, 290, 350, 410, 470]:
		var r := deg_to_rad(a)
		var c: Vector2 = Vector2(34.0 + 0.72 * cos(r), -14.0 - 0.72 * sin(r))
		var o: Vector2 = Vector2(34.0 + 3.0 * cos(r), -14.0 - 3.0 * sin(r))
		var h: float = -1.08 + (a - 185) / 360.0 * 3.24
		probes.append(["spiral_%d" % a, Vector3(c.x, h + 0.1, c.y), Vector3(o.x, 0, o.y)])
	var falls := 0
	for pr in probes:
		player.global_position = pr[1] + Vector3.UP * 0.3
		player.velocity = Vector3.ZERO
		player.autopilot = PackedVector3Array()
		for k in 30:
			await get_tree().physics_frame
		var y0 := player.global_position.y
		player.autopilot_index = 0
		player.autopilot_done = false
		player.autopilot = PackedVector3Array([pr[2]])
		var y_min := y0
		for k in 150:
			await get_tree().physics_frame
			y_min = minf(y_min, player.global_position.y)
		player.autopilot = PackedVector3Array()
		var drop := y0 - y_min
		var fell := drop > 0.4
		falls += 1 if fell else 0
		print("[AUTOTEST] перила %s старт_y=%.2f перепад=%.2f %s" % [pr[0], y0, drop, "ПАДЕНИЕ" if fell else "ок"])
	print("[AUTOTEST] перила: падений %d из %d" % [falls, probes.size()])


## Свеча: кадры от первого лица (обычный свет, ладонь, взгляд вниз, зеркало), затем бег с ладонью
## (свеча должна гореть) и бег без ладони (должна погаснуть примерно через 4 с).
func _candle_test() -> void:
	await _wait(1.0)
	_hide_ui()
	await _pose(Vector3(25, 0, 47), Vector3(25, 1.5, 38), 0.1, 40)
	_save("candle_fp_normal")
	player.force_shield = true
	await _pose(Vector3(25, 0, 47), Vector3(25, 1.5, 38), 0.1, 40)
	_save("candle_fp_shield")
	player.force_shield = false
	await _pose(Vector3(25, 0, 47), Vector3(25, 0.0, 46.2), 0.1, 40)
	_save("candle_fp_down")
	await _pose(Vector3(25, 0, 47), Vector3(25, 0.0, 46.8), 0.1, 40)     # предельный наклон (83°)
	_save("candle_fp_down_max")
	# Финал свечи (97% сгорело): пламя мелкое, но окружение должно читаться
	await _pose(Vector3(25, 0, 47), Vector3(25, 1.5, 38), 0.97, 40)
	_save("candle_fp_late")
	print("[AUTOTEST] финал свечи: яркость кадра %.3f, свет r=%.1f e=%.2f" % [
		_frame_luma(), candle.get_node("CandleLight").omni_range, candle.get_node("CandleLight").light_energy])
	candle.burned = 0.0
	await _pose(Vector3(25.0, 2.16, -18.6), Vector3(25, 3.3, -16), 0.4, 60)
	_save("candle_mirror")
	for m in get_tree().get_nodes_in_group("scares"):
		for c in m.get_children():
			if c is SubViewport:
				c.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/candle_mirror_view.png"))
	player.force_shield = true
	await _pose(Vector3(25.0, 2.16, -18.6), Vector3(25, 3.3, -16), 0.4, 60)
	for m in get_tree().get_nodes_in_group("scares"):
		for c in m.get_children():
			if c is SubViewport:
				c.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/candle_mirror_shield.png"))
	var run := PackedVector3Array([Vector3(40.7, 0, 66), Vector3(40.6, 0, 58), Vector3(41, 0, 55), Vector3(25, 0, 55)])
	for shielded in [true, false]:
		player.global_position = Vector3(41, 0.05, 67)
		player.velocity = Vector3.ZERO
		candle.run_strain = 0.0
		player.force_shield = shielded
		player.force_run = true
		player.autopilot_index = 0
		player.autopilot_done = false
		player.autopilot = run
		var t := 0.0
		while t < 6.0 and candle.lit:
			await get_tree().process_frame
			t += get_process_delta_time()
			if t > 2.0 and t < 2.1:
				_save("candle_run_%s" % ("shield" if shielded else "open"))
		print("[AUTOTEST] бег %s: %.1f с, свеча горит=%s, надрыв=%.2f, причина=%s" % [
			"с ладонью" if shielded else "без ладони", t, candle.lit, candle.run_strain, candle.out_reason])
	player.autopilot = PackedVector3Array()
	player.force_run = false
	await _wait(3.0)
	_save("candle_run_gameover")
	print("[AUTOTEST] после угасания: яркость кадра %.4f (нужна полная тьма)" % _frame_luma())
	await _wait(6.0)                     # преследователь добегает за ~5 с (лог [GAME])


func _map() -> void:
	_hide_ui()
	candle.stop()
	game.get_node("Architecture/Ceilings").visible = false
	var env: Environment = game.get_node("Environment").environment
	env.ambient_light_energy = 1.2
	env.volumetric_fog_enabled = false
	env.ssao_enabled = false
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, 30, 0)
	sun.light_energy = 1.2
	game.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 140.0
	cam.far = 200.0
	cam.position = Vector3(21, 80, 7)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	game.add_child(cam)
	cam.current = true
	for k in 30:
		await get_tree().process_frame
	_save("map")


func _route(route_name: String, pts: Array) -> void:
	_hide_ui()
	var length := 0.0
	var path := PackedVector3Array()
	var prev := Vector2(player.global_position.x, player.global_position.z)
	for p in pts:
		length += prev.distance_to(p)
		prev = p
		path.append(Vector3(p.x, 0, p.y))
	Engine.time_scale = TIME_SCALE
	player.autopilot = path
	var t0: float = game.elapsed
	var frames := 0
	var worst_ms := 0.0
	var us0 := Time.get_ticks_usec()
	var us_prev := us0
	while game.state == game.State.PLAYING and game.elapsed - t0 < 600.0:
		await get_tree().process_frame
		var us := Time.get_ticks_usec()
		frames += 1
		if frames > 30:          # первые кадры — компиляция шейдеров, не считаем
			worst_ms = maxf(worst_ms, (us - us_prev) / 1000.0)
			if (us - us_prev) > 150000:
				print("[AUTOTEST] рывок %.0f мс в %s (t=%.1f с)" % [(us - us_prev) / 1000.0, player.global_position, game.elapsed - t0])
		us_prev = us
		if player.autopilot_done:
			await get_tree().create_timer(2.0 * TIME_SCALE).timeout
			break
	var state_name: String = game.State.keys()[game.state]
	print("[AUTOTEST] маршрут=%s длина_по_точкам=%.1f м пройдено=%.1f м время=%.1f с состояние=%s свеча_осталось=%.0f%% точка=%d/%d" % [
		route_name, length, player.distance_walked, game.elapsed - t0, state_name,
		candle.remaining() * 100.0, player.autopilot_index, path.size()])
	print("[AUTOTEST] производительность: средний FPS=%.1f, худший кадр=%.1f мс" % [
		frames / ((us_prev - us0) / 1000000.0), worst_ms])
	if game.state == game.State.LOST:
		await get_tree().create_timer(14.0 * TIME_SCALE).timeout
		Engine.time_scale = 1.0
		_save("gameover_" + route_name)
	elif game.state == game.State.WON:
		Engine.time_scale = 1.0
		await get_tree().create_timer(3.0).timeout
		_save("win_" + route_name)
	Engine.time_scale = 1.0


func _save(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR + "/" + shot_name + ".png")
	img.save_png(path)
	print("[AUTOTEST] снимок ", path)


## Средняя яркость текущего кадра 0..1 (кадр сжимается до 1×1).
func _frame_luma() -> float:
	var img := get_viewport().get_texture().get_image()
	img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	return img.get_pixel(0, 0).get_luminance()
