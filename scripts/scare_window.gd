extends Node3D
## Скример за окном (галерея бельэтажа): когда игрок в зоне и смотрит в окно, вдалеке между деревьев
## появляется силуэт и резко бежит к окну — и исчезает за секунду до стекла. Один раз.

const LOOK_COS := 0.88               ## окно в центре взгляда (~28°)
const SPEED := 11.0                  ## м/с
const VANISH_BEFORE := 1.0           ## исчезает за столько секунд до стекла
const STRIDE := 1.6                  ## период покачивания бега, м

@export var window_point := Vector3.ZERO     ## центр окна, куда смотрит игрок
@export var run_from := Vector3.ZERO         ## старт бега (низ фигуры)
@export var run_to := Vector3.ZERO           ## стекло (куда бежит)

var fired := false
var _armed := false
var _runner: MeshInstance3D


func _ready() -> void:
	_runner = $Runner as MeshInstance3D
	var mat := ShadowFigure.make_material("ghost_running")
	mat.set_shader_parameter("eye_glow", 0.0)     # силуэт вдалеке — без глаз
	_runner.material_override = mat
	_runner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_runner.visible = false
	var trigger := $Trigger as Area3D
	trigger.body_entered.connect(_on_trigger.bind(true))
	trigger.body_exited.connect(_on_trigger.bind(false))


func _on_trigger(body: Node, inside: bool) -> void:
	if body.is_in_group("player"):
		_armed = inside


func _process(_delta: float) -> void:
	if fired or not _armed or not ScareLedger.can_fire("window_runner"):
		return
	var cam := get_viewport().get_camera_3d()
	if cam and (-cam.global_basis.z).dot((window_point - cam.global_position).normalized()) > LOOK_COS:
		fire()


func fire() -> void:
	fired = true
	set_process(false)
	print("[SCARE] силуэт за окном")
	ScareLedger.note_scare("window_runner")
	var path := run_to - run_from
	var run_dist := maxf(path.length() - SPEED * VANISH_BEFORE, 1.0)
	var half_h := (_runner.mesh as QuadMesh).size.y * 0.5
	_runner.global_position = run_from + Vector3.UP * half_h
	_runner.visible = true
	get_tree().create_timer(0.25).timeout.connect(
		func() -> void: HorrorAudio.play_2d(self, HorrorAudio.one("stinger_window"), -3.0))
	var tw := create_tween()
	tw.tween_method(_place_runner.bind(path.normalized(), half_h), 0.0, run_dist, run_dist / SPEED)
	tw.tween_callback(func() -> void: _runner.visible = false)


func _place_runner(s: float, dir: Vector3, half_h: float) -> void:
	var bob := absf(sin(s / STRIDE * PI)) * 0.12
	_runner.global_position = run_from + dir * s + Vector3.UP * (half_h + bob)
