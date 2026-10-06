extends "res://scripts/prop_tweak.gd"
## Портрет (Portrait_Frame): своё полотно из assets/horror/textures. «Следящие» портреты незаметно
## переводят взгляд на игрока — только пока на них не смотрят прямо; под прямым взглядом зрачки замирают.

const TEX := "res://assets/horror/textures/"
## Глаза следящих полотен в долях кадра (кадрирование — tools/process_external.py): левый, правый, радиус радужки
const EYES := {
	"rembrandt": [Vector2(0.516, 0.313), Vector2(0.658, 0.313), 0.012],
	"innocent": [Vector2(0.585, 0.439), Vector2(0.689, 0.441), 0.009],
	"lady_blue": [Vector2(0.525, 0.471), Vector2(0.694, 0.491), 0.013],
	"bocklin": [Vector2(0.357, 0.239), Vector2(0.468, 0.246), 0.011],
}
const WATCHED_COS := 0.94            ## cos 20°: портрет почти в центре взгляда — «замереть»
const WATCH_DIST := 9.0              ## дальше — глаза не следят
const GAZE_SPEED := 1.4              ## скорость перевода взгляда, доли/с
const CREEP_COS := 0.64              ## cos 50°: картина в естественном поле зрения, не обязательно в центре
const CREEP_DIST := 4.5              ## и близко — свет свечи ложится на полотно
const CREEP_TIME := 0.35             ## резкое бесшовное превращение

@export var painting := "rembrandt"
@export var follow := false
@export var creep_painting := ""      ## жуткий двойник (painting_<имя>.jpg); пусто — картина не меняется

var fired := false                   ## превращение уже было (одноразово)
var _creep_sound: AudioStream

var gaze := Vector2.ZERO
var _mat: ShaderMaterial


func _ready() -> void:
	super._ready()
	var canvas := find_child("Portrait_Frame_Canvas", true, false) as MeshInstance3D
	if canvas == null:
		push_warning("[PORTRAIT] нет полотна у %s" % name)
		set_process(false)
		return
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/portrait.gdshader")
	_mat.set_shader_parameter("albedo_tex", load(TEX + "painting_%s.jpg" % painting))
	_mat.set_shader_parameter("normal_tex", load(TEX + "canvas_normal.jpg"))
	_mat.set_shader_parameter("rough_tex", load(TEX + "canvas_rough.jpg"))
	_mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	follow = follow and EYES.has(painting)
	if follow:
		var e: Array = EYES[painting]
		_mat.set_shader_parameter("eye_l", e[0])
		_mat.set_shader_parameter("eye_r", e[1])
		_mat.set_shader_parameter("eye_radius", e[2])
	for i in canvas.mesh.get_surface_count():
		canvas.set_surface_override_material(i, _mat)
	canvas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # плоское полотно у свечи — без самозатенения (ряби)
	if creep_painting != "":
		_mat.set_shader_parameter("creep_tex", load(TEX + "painting_%s.jpg" % creep_painting))
		var noise := NoiseTexture2D.new()
		noise.width = 256
		noise.height = 256
		noise.seamless = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.03
		noise.noise = fn
		_mat.set_shader_parameter("creep_noise", noise)
		_creep_sound = HorrorAudio.one("portrait_creep")
	set_process(follow or creep_painting != "")


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_me := global_position - cam.global_position
	if creep_painting != "" and not fired:
		_check_creep(cam, to_me)
	if not follow or to_me.length() > WATCH_DIST:
		return
	if (-cam.global_basis.z).dot(to_me.normalized()) > WATCHED_COS:
		return              # на портрет смотрят — зрачки неподвижны
	var local := to_local(cam.global_position)
	if local.z < 0.2:
		return              # зритель за плоскостью картины
	var target := Vector2(clampf(local.x / local.z * 0.9, -1.0, 1.0), clampf(-local.y / local.z * 0.9, -1.0, 1.0))
	gaze = gaze.move_toward(target, GAZE_SPEED * delta)
	_mat.set_shader_parameter("gaze", gaze)


## Превращение: игрок близко и перед полотном, картина в кадре под углом до 50° от центра взгляда
## (скалярное произведение направления камеры и направления на картину), без стен между, свеча горит —
## полотно за CREEP_TIME
## растворяется в жуткого двойника под нарастающий звук. Один раз.
func _check_creep(cam: Camera3D, to_me: Vector3) -> void:
	if to_me.length() > CREEP_DIST or (-cam.global_basis.z).dot(to_me.normalized()) < CREEP_COS:
		return
	if to_local(cam.global_position).z < 0.2:
		return              # зритель сбоку или за плоскостью картины
	if not ScareFX.can_see(cam, global_position + global_basis.z * 0.08):
		return              # вне кадра или за стеной
	if not ScareLedger.can_fire("portrait_creep"):
		return              # передышка после предыдущего скримера
	var player := get_tree().get_first_node_in_group("player")
	var candle := player.get_node_or_null("Head/Camera3D/Hand") if player else null
	if candle == null or not candle.get("lit") or candle.call("is_snuffed"):
		return
	fired = true
	print("[SCARE] картина %s превращается" % name)
	ScareLedger.note_scare("portrait_creep")
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = _creep_sound
	sfx.bus = "Scare"
	sfx.unit_size = 3.0
	add_child(sfx)
	sfx.play()
	# Звук нарастает 0.9 с — полотно меняется на его пике
	var tw := create_tween()
	tw.tween_interval(0.55)
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("creep", v), 0.0, 1.0, CREEP_TIME)
