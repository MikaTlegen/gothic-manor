extends Node3D
## Статуя, которая меняет позу за спиной: после того как игрок прошёл рядом, в первый момент, когда
## статуя вне экрана (VisibleOnScreenNotifier3D), фигура разворачивается к игроку и чуть склоняется.
## Тихий скрежет камня. Один раз.

const PASS_DIST := 3.5               ## «прошёл мимо»: был ближе этого
const MIN_DIST := 2.0                ## вплотную не шевелится — игрок мог бы заметить краем глаза
const MAX_DIST := 16.0

@export var figure_name := ""        ## узел фигуры внутри ассета (поворачивается вокруг оси статуи)
@export var lean_deg := 8.0

var fired := false
var _passed := false
var _figure: Node3D
var _notifier: VisibleOnScreenNotifier3D
var _player: Node3D


func _ready() -> void:
	_figure = find_child(figure_name, true, false) as Node3D
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _figure == null or _player == null:
		push_warning("[STATUE] нет фигуры %s" % figure_name)
		set_process(false)
		return
	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = AABB(Vector3(-0.8, 0.0, -0.8), Vector3(1.6, 3.2, 1.6))
	add_child(_notifier)


func _process(_delta: float) -> void:
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var d := to_player.length()
	if not _passed:
		_passed = d < PASS_DIST
		return
	if _notifier.is_on_screen() or d < MIN_DIST or d > MAX_DIST or not ScareLedger.can_fire(name):
		return
	turn_to_player()


func turn_to_player() -> void:
	fired = true
	set_process(false)
	var local: Vector3 = (_figure.get_parent() as Node3D).to_local(_player.global_position)
	_figure.rotation = Vector3(deg_to_rad(lean_deg), atan2(local.x, local.z), 0.0)
	var grind := AudioStreamPlayer3D.new()
	grind.stream = HorrorAudio.one("stone_grind")
	grind.volume_db = -14.0
	grind.unit_size = 2.0
	grind.bus = "SFX"
	add_child(grind)
	grind.position.y = 1.5
	grind.play()
	print("[SCARE] статуя %s повернулась" % name)
	ScareLedger.note_scare("statue_turn")
