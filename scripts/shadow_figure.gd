class_name ShadowFigure
extends MeshInstance3D
## Тень в глубокой темноте: тёмный силуэт-билборд. Стоит свету свечи дотянуться до него
## (ближе доли радиуса света и без стен между ними) — бесшумно растворяется. Один раз.

const TEX := "res://assets/horror/textures/"
const CHECK_INTERVAL := 0.1
const LIT_FRACTION := 0.65           ## доля радиуса света свечи, на которой силуэт «попадает под свет»
const DISSOLVE_TIME := 0.45

var fired := false
var _t := 0.0
var _mat: ShaderMaterial
var _light: OmniLight3D
var _player: CollisionObject3D


## Материал силуэта с шумом растворения (общий для теней, призрака в зеркале и бегущего за окном).
static func make_material(mask: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/shadow_figure.gdshader")
	m.set_shader_parameter("mask_tex", load(TEX + mask + ".png"))
	var noise := NoiseTexture2D.new()
	noise.width = 128
	noise.height = 128
	noise.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.06
	noise.noise = fn
	m.set_shader_parameter("noise_tex", noise)
	return m


func _ready() -> void:
	_mat = make_material("ghost_standing")
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_player = get_tree().get_first_node_in_group("player") as CollisionObject3D
	if _player:
		_light = _player.get_node_or_null("Head/Camera3D/Hand/CandleLight") as OmniLight3D


func _process(delta: float) -> void:
	if fired or _light == null:
		return
	_t += delta
	if _t < CHECK_INTERVAL:
		return
	_t = 0.0
	if not _light.is_visible_in_tree():
		return
	var lp := _light.global_position
	if lp.distance_to(global_position) > _light.omni_range * LIT_FRACTION:
		return
	var q := PhysicsRayQueryParameters3D.create(lp, global_position)
	q.exclude = [_player.get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return              # свет загорожен стеной
	dissolve()


func dissolve() -> void:
	if fired:
		return
	fired = true
	print("[SCARE] тень %s растворилась" % name)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("dissolve", v), 0.0, 1.0, DISSOLVE_TIME)
	tw.tween_callback(hide)
