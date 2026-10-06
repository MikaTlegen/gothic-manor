extends Node3D
## Живое зеркало (F3, «Два зеркала»): отражение — камера в SubViewport, отражённая относительно стекла,
## с косой пирамидой видимости (ближняя плоскость = стекло, всё за зеркалом отсекается).
## Рендер идёт только когда игрок рядом, перед стеклом и зеркало на экране (экономия для встроенной графики).
##
## В отражении видно тело персонажа игрока (слои 11 и 14) и — один раз — высокий силуэт за его спиной
## (слой 12). Основная камера слоя 12 не видит: обернёшься — никого. Стоит отвернуться — силуэт исчезает.
##
## Гарантированный скример 4 «Рассинхрон» (взводится узким проходом Chokepoint_* при входе в зал):
## отражение застывает — игрок двигается, а двойник в зеркале нет; затем двойник медленно поворачивает
## голову к смотрящему. Это клон тела на слое 15, который видит только камера зеркала. Силуэт за спиной
## появляется только после рассинхрона.

const RES_W := 256                   ## ширина кадра отражения, px (высота — по пропорции стекла)
const LIVE_DIST := 7.0               ## дальше зеркало не обновляется (тусклое стекло)
const SCARE_DIST := 4.5
const STARE_TIME := 1.2              ## сколько секунд смотреть в зеркало до появления силуэта
const LOOK_COS := 0.9                ## cos ~25°: «смотрит в зеркало»
const AWAY_COS := 0.35               ## cos ~70°: «отвернулся»
const BODY_LAYER := 1 << 10
const GHOST_LAYER := 1 << 11
const GLASS_LAYER := 1 << 12         ## стекло не попадает в собственное отражение
const CLONE_LAYER := 1 << 14         ## застывший клон тела (скример «рассинхрон»): видит только зеркало
const FP_LAYER := 1 << 15            ## перчатки от первого лица — в отражении их заменяют руки персонажа
const PLAYER_LAYER := 1 << 13        ## ноги и полы сюртука игрока (видны и в игре, и в зеркале)
const FP_BODY_LAYER := 1 << 16       ## FP-костюм (срезан по грудь) — в отражении его заменяет полный костюм
const HAND_LAYER := 2                ## свеча в руке
const DESYNC_STARE := 0.9            ## сколько смотреть в зеркало до рассинхрона, с
const FREEZE_TIME := 1.3             ## двойник стоит неподвижно, пока игрок двигается
const TURN_TIME := 1.6               ## медленный поворот головы двойника
const HOLD_TIME := 1.4

@export var player_path: NodePath
@export var desync_id := "mirror_desync"

var fired := false
var ghost_visible := false
var desync_fired := false
var desync_done := false

var _armed := false
var _clone: Node3D
var _base_mask := 0

var _player: Node3D
var _glass: MeshInstance3D
var _vp: SubViewport
var _cam: Camera3D
var _mat: ShaderMaterial
var _notifier: VisibleOnScreenNotifier3D
var _ghost: MeshInstance3D
var _ghost_mat: ShaderMaterial
var _rect: AABB
var _live := 0.0
var _stare := 0.0


func _ready() -> void:
	_player = get_node(player_path)
	_glass = find_child("*_Glass", true, false) as MeshInstance3D
	if _glass == null or _player == null:
		push_warning("[MIRROR] нет стекла или игрока")
		set_process(false)
		return
	_rect = _glass.mesh.get_aabb()
	_glass.layers = GLASS_LAYER
	_make_viewport()
	_make_material()
	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = _rect
	_glass.add_child(_notifier)
	_make_body()
	_make_ghost()
	ScareLedger.register(desync_id)
	for c in get_children():
		if c is Area3D and String(c.name).begins_with("Chokepoint"):
			(c as Area3D).body_entered.connect(_on_chokepoint)


func _on_chokepoint(body: Node) -> void:
	if body.is_in_group("player"):
		_armed = true


func _make_viewport() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(RES_W, int(RES_W * _rect.size.y / _rect.size.x))
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_cam.cull_mask = 0xFFFFF & ~(GLASS_LAYER | CLONE_LAYER | FP_LAYER | FP_BODY_LAYER)
	_base_mask = _cam.cull_mask
	var level: Node = owner if owner else get_tree().current_scene
	var world_env := level.get_node_or_null("Environment") as WorldEnvironment
	if world_env:
		# Дешёвое окружение для отражения: без объёмного тумана и экранных эффектов
		var e := world_env.environment.duplicate() as Environment
		e.volumetric_fog_enabled = false
		e.ssr_enabled = false
		e.ssil_enabled = false
		e.ssao_enabled = false
		e.fog_enabled = true
		e.fog_light_color = Color(0.05, 0.055, 0.07)
		e.fog_density = 0.04
		_cam.environment = e
	_vp.add_child(_cam)


func _make_material() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/mirror.gdshader")
	_mat.set_shader_parameter("reflection_tex", _vp.get_texture())
	_mat.set_shader_parameter("tarnish_tex", load("res://assets/gothic_manor/models/textures/mirror_albedo.jpg"))
	var c := _rect.get_center()
	_mat.set_shader_parameter("rect_center", Vector2(c.x, c.y))
	_mat.set_shader_parameter("rect_size", Vector2(_rect.size.x, _rect.size.y))
	for i in _glass.mesh.get_surface_count():
		_glass.set_surface_override_material(i, _mat)


## Запасное тело для отражения (если у игрока нет персонажа Body): тёмный силуэт в плаще.
func _make_body() -> void:
	if _player.has_node("MirrorBody") or _player.has_node("Body"):
		return
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.025, 0.022, 0.02)
	cloth.roughness = 0.95
	var body := MeshInstance3D.new()
	body.name = "MirrorBody"
	var cap := CapsuleMesh.new()
	cap.radius = 0.24
	cap.height = 1.45
	cap.material = cloth
	body.mesh = cap
	body.position = Vector3(0, 0.78, 0.05)
	_hide_from_main(body, BODY_LAYER)
	_player.add_child(body)
	var head := MeshInstance3D.new()
	head.name = "MirrorHead"
	var sph := SphereMesh.new()
	sph.radius = 0.11
	sph.height = 0.25
	sph.material = cloth
	head.mesh = sph
	head.position = Vector3(0, -0.02, 0.06)
	_hide_from_main(head, BODY_LAYER)
	_player.get_node("Head").add_child(head)


func _make_ghost() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.name = "MirrorGhost"
	var q := QuadMesh.new()
	q.size = Vector2(0.95, 2.35)
	_ghost.mesh = q
	_ghost_mat = ShadowFigure.make_material("ghost_standing")
	_ghost_mat.set_shader_parameter("opacity", 0.0)
	_ghost_mat.set_shader_parameter("color", Color(0.3, 0.28, 0.3))   # чуть светлее тьмы — ловит отсвет свечи
	_ghost_mat.set_shader_parameter("eye_glow", 2.5)
	_ghost.material_override = _ghost_mat
	_ghost.top_level = true
	_ghost.visible = false
	_hide_from_main(_ghost, GHOST_LAYER)
	add_child(_ghost)


func _hide_from_main(mi: MeshInstance3D, layer: int) -> void:
	mi.layers = layer
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var c := _glass.global_transform * _rect.get_center()
	var n := _glass.global_basis.z.normalized()
	var d := (eye - c).dot(n)
	var dist := eye.distance_to(c)
	var on_screen := _notifier.is_on_screen()
	var live := d > 0.05 and dist < LIVE_DIST and on_screen
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
	_live = move_toward(_live, 1.0 if live else 0.0, delta * 3.0)
	_mat.set_shader_parameter("live", _live)
	if live:
		_update_camera(eye, c, n, d)
	var looking := (-cam.global_basis.z).dot((c - eye).normalized())
	var lateral := absf((eye - c).dot(n.cross(Vector3.UP).normalized()))
	var staring := live and lateral < _rect.size.x * 0.4 and d > 0.3 and dist < SCARE_DIST and looking > LOOK_COS
	if not desync_fired:
		if _armed:
			_stare = _stare + delta if staring else maxf(_stare - delta * 0.5, 0.0)
			if _stare > DESYNC_STARE:
				_stare = 0.0
				_start_desync(c)
		return
	if not desync_done:
		return
	if not fired:
		# Игрок видит в зеркале себя: стоит напротив стекла (отражение — у основания перпендикуляра)
		_stare = _stare + delta if staring else maxf(_stare - delta * 0.5, 0.0)
		if _stare > STARE_TIME:
			_show_ghost(eye, c)
	elif ghost_visible:
		_follow_player(eye, c, delta)
		if not on_screen or looking < AWAY_COS or dist > LIVE_DIST:
			_remove_ghost()


## Рассинхрон: клон тела в текущей позе застывает (виден только зеркалу), живое тело и свеча
## из отражения пропадают; через FREEZE_TIME двойник поворачивает голову к стеклу — к смотрящему.
func _start_desync(glass_center: Vector3) -> void:
	desync_fired = true
	ScareLedger.mark_fired(desync_id)
	var body := _player.get_node_or_null("Body") as Node3D
	if body == null:
		desync_done = true
		return
	print("[SCARE] зеркало: отражение застыло")
	_clone = body.duplicate() as Node3D
	_clone.set("animate", false)
	_clone.top_level = true
	add_child(_clone)
	_clone.global_transform = body.global_transform
	for n in _clone.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).layers = CLONE_LAYER
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(n as MeshInstance3D).visible = not String(n.name).contains("_FP_")   # клону — только полный костюм
	_cam.cull_mask = (_base_mask & ~(BODY_LAYER | PLAYER_LAYER | HAND_LAYER)) | CLONE_LAYER
	await get_tree().create_timer(FREEZE_TIME).timeout
	HorrorAudio.play_2d(self, HorrorAudio.one("stinger_mirror"), -4.0)
	var to := _clone.global_transform.affine_inverse() * glass_center
	var yaw := clampf(atan2(to.x, to.z), -1.2, 1.2)
	if absf(yaw) < 0.5:
		yaw = 0.9 * (1.0 if randf() < 0.5 else -1.0)   # стоит лицом к стеклу — голова уходит вбок, к плечу
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(v: float) -> void: _clone.call("turn_head", v * yaw, -0.18 * v), 0.0, 1.0, TURN_TIME)
	tw.tween_interval(HOLD_TIME)
	await tw.finished
	_end_desync()


func _end_desync() -> void:
	if is_instance_valid(_clone):
		_clone.queue_free()
	_cam.cull_mask = _base_mask
	desync_done = true
	print("[SCARE] зеркало: отражение снова живое")


## Камера-отражение: позиция глаза, отражённая в плоскости стекла; смотрит по нормали стекла,
## пирамида видимости проходит точно через прямоугольник стекла (set_frustum со смещением).
func _update_camera(eye: Vector3, c: Vector3, n: Vector3, d: float) -> void:
	var up := Vector3.UP
	var r := n.cross(up).normalized()
	var p := eye - 2.0 * d * n
	_cam.global_transform = Transform3D(Basis(r, up, -n), p)
	var rel := c - p
	_cam.set_frustum(_rect.size.y, Vector2(rel.dot(r), rel.dot(up)), maxf(d, 0.05), 60.0)


## Точка строго за спиной игрока по нормали стекла: в отражении силуэт встаёт прямо позади него.
func _ghost_target(_eye: Vector3, _c: Vector3) -> Vector3:
	var n := _glass.global_basis.z
	var back := Vector3(n.x, 0.0, n.z).normalized()
	return _player.global_position + back * 0.65 + Vector3.UP * 1.17


func _show_ghost(eye: Vector3, c: Vector3) -> void:
	fired = true
	ghost_visible = true
	_ghost.global_position = _ghost_target(eye, c)
	_ghost.visible = true
	create_tween().tween_method(func(v: float) -> void: _ghost_mat.set_shader_parameter("opacity", v), 0.0, 1.0, 0.6)
	HorrorAudio.play_2d(self, HorrorAudio.one("stinger_mirror"), -6.0)
	print("[SCARE] зеркало: силуэт за спиной")


func _follow_player(eye: Vector3, c: Vector3, delta: float) -> void:
	_ghost.global_position = _ghost.global_position.lerp(_ghost_target(eye, c), minf(delta * 4.0, 1.0))


func _remove_ghost() -> void:
	ghost_visible = false
	_ghost.queue_free()
	print("[SCARE] зеркало: игрок отвернулся — силуэт исчез")
