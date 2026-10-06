extends Area3D
## Гарантированный скример 2 «Фигура за стеклом»: после узкого прохода (верх парадной лестницы) западное окно
## галереи вдруг бледно светится, как матовое стекло, — и из темноты к нему бросается фигура: голова и две
## раскрытые ладони прилипают к стеклу (силуэт по рефу 17 пользователя). Удар, дрожь кадра, фигура держится
## у стекла, «дышит», затем отступает и растворяется; свечение гаснет, на стекле остаются отпечатки ладоней.
## Скример ждёт, пока окно реально видно (в кадре и без стен между); ушёл, так и не посмотрев, — не тратится.

@export var scare_id := "hand_slam"
@export var window_point := Vector3.ZERO     ## центр стекла (мир)
@export var inward := Vector3.RIGHT          ## нормаль стекла внутрь дома

const LOOK_COS := 0.55               ## окно примерно в поле зрения (~57°)
const GIVE_UP_DIST := 10.0           ## дальше от окна — перестать ждать
const SIL_SIZE := Vector2(1.3, 1.95) ## силуэт в метрах (стекло 1.5 × 2.75)
const GLOW_SIZE := Vector2(1.6, 2.7)
const GLOW_ALPHA := 0.8
const LUNGE_DELAY := 0.28            ## свечение успевает проявиться до броска
const LUNGE_TIME := 0.09
const HOLD_TIME := 1.6
const FADE_TIME := 1.2
## Ладони на силуэте (доли кадра рефа 17: u — вправо, v — вниз) — там остаются отпечатки
const PALMS := [Vector2(0.233, 0.547), Vector2(0.821, 0.384)]
const SIL_TEX := preload("res://assets/horror/textures/glass_silhouette.png")
const PRINT_TEX := preload("res://assets/horror/textures/hand_print.png")

var fired := false
var _waiting := false
var _slam_sound: AudioStream
var _sil_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _print_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	ScareLedger.register(scare_id)
	_slam_sound = HorrorAudio.one("glass_slam")      # загрузка заранее — без задержки в момент удара
	_sil_mat = make_material(true)
	_glow_mat = make_glow_material()
	for k in PALMS.size():
		_print_mats.append(make_material(false))
	body_entered.connect(_on_body_entered)
	set_process(false)


func _on_body_entered(body: Node) -> void:
	if not fired and not _waiting and body.is_in_group("player"):
		_waiting = true
		set_process(true)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if cam.global_position.distance_to(window_point) > GIVE_UP_DIST:
		_waiting = false
		set_process(false)
		return
	var facing := (-cam.global_basis.z).dot((window_point - cam.global_position).normalized()) > LOOK_COS
	if facing and ScareFX.can_see(cam, window_point + inward * 0.4) and ScareLedger.can_fire(scare_id, ScareLedger.REST_GUARANTEED):
		set_process(false)
		fire()


func fire() -> void:
	fired = true
	ScareLedger.mark_fired(scare_id)
	print("[SCARE] фигура прилипла к стеклу")
	var glow := _quad(_glow_mat, GLOW_SIZE)
	glow.global_transform = _facing(window_point - inward * 0.5)
	var sil := _quad(_sil_mat, SIL_SIZE)
	var far := _facing(window_point - inward * 0.9 - Vector3.UP * 0.08).scaled_local(Vector3.ONE * 0.82)
	var glass := _facing(window_point - inward * 0.03)
	sil.global_transform = far
	var tw := create_tween()
	# 1. Окно бледно светится — матовое стекло с подсветкой снаружи; в глубине угадывается фигура
	tw.tween_property(_glow_mat, "albedo_color:a", GLOW_ALPHA, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_sil_mat, "albedo_color:a", 0.3, 0.22)
	tw.tween_interval(LUNGE_DELAY - 0.22)
	# 2. Бросок: голова и ладони прилипают к стеклу
	tw.tween_property(sil, "global_transform", glass, LUNGE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_sil_mat, "albedo_color:a", 1.0, LUNGE_TIME)
	tw.tween_callback(_impact.bind(glass))
	# 3. Держится у стекла и «дышит»
	tw.tween_property(sil, "global_transform", glass.scaled_local(Vector3(1.012, 1.008, 1.0)), HOLD_TIME * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sil, "global_transform", glass, HOLD_TIME * 0.5).set_trans(Tween.TRANS_SINE)
	# 4. Отступает и растворяется в темноте; свечение гаснет следом
	tw.tween_property(sil, "global_transform", far, FADE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_sil_mat, "albedo_color:a", 0.0, FADE_TIME)
	tw.parallel().tween_property(_glow_mat, "albedo_color:a", 0.0, FADE_TIME + 0.6)
	tw.tween_callback(sil.queue_free)
	tw.tween_interval(0.6)
	tw.tween_callback(glow.queue_free)


## Удар о стекло: звук, дрожь кадра, отпечатки ладоней остаются на стекле.
func _impact(glass: Transform3D) -> void:
	print("[SCARE] фигура ударилась о стекло")
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = _slam_sound
	sfx.bus = "Scare"
	sfx.unit_size = 5.0
	get_tree().current_scene.add_child(sfx)
	sfx.global_position = window_point
	sfx.finished.connect(sfx.queue_free)
	sfx.play()
	for k in PALMS.size():
		var uv: Vector2 = PALMS[k]
		var mi := _quad(_print_mats[k], Vector2(0.36 * (1.0 if k == 1 else -1.0), 0.36))
		var off := Vector3((uv.x - 0.5) * SIL_SIZE.x, (0.5 - uv.y) * SIL_SIZE.y, 0.0)
		mi.global_transform = glass.translated_local(off + Vector3(0, 0, 0.018))
		create_tween().tween_property(_print_mats[k], "albedo_color:a", 0.7, 0.25)
	var cam := get_viewport().get_camera_3d()
	if cam:
		ScareFX.shake(cam, 0.03, 0.25)


func _quad(mat: StandardMaterial3D, size: Vector2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	return mi


## Материал силуэта (figure) или отпечатка ладони. Тот же вызов использует прогрев ScareFX.prewarm —
## шейдер компилируется под чёрным экраном интро, без рывка в момент удара.
## Силуэт без освещения: тёмная фигура читается на светлом стекле при любом свете свечи.
static func make_material(figure: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 10                       # поверх полупрозрачного стекла окна: оно не «выбеливает» фигуру
	if figure:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = SIL_TEX
		m.albedo_color = Color(1, 1, 1, 0)
	else:
		m.albedo_texture = PRINT_TEX
		m.roughness = 0.8                        # отпечаток — матовый налёт
		m.albedo_color = Color(0.55, 0.56, 0.58, 0.0)
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.emission_enabled = true
		m.emission = Color(0.05, 0.055, 0.06)
	return m


## Свечение «матового стекла»: бледный холодный овал снаружи окна, мягко гаснет к краям.
static func make_glow_material() -> StandardMaterial3D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.78, 0.82, 0.88, 1.0), Color(0.62, 0.67, 0.75, 0.75), Color(0.5, 0.55, 0.62, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.45)
	tex.fill_to = Vector2(0.5, 1.02)
	tex.width = 128
	tex.height = 192
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = tex
	m.albedo_color = Color(1, 1, 1, 0)
	m.render_priority = -10                      # свечение — позади стекла и фигуры
	return m


## Квад лицом внутрь дома (QuadMesh смотрит в +Z).
func _facing(pos: Vector3) -> Transform3D:
	var z := inward.normalized()
	var x := Vector3.UP.cross(z).normalized()
	return Transform3D(Basis(x, z.cross(x), z), pos)
