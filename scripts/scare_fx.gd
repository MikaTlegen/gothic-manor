class_name ScareFX
## Общие эффекты гарантированных скримеров: облако пыли, рассыпающийся пепел, вдох у самого уха.

const TEX := "res://assets/horror/textures/"

## Материалы прогрева живут до конца игры: пока жив хоть один материал с таким набором флагов,
## его скомпилированный шейдер остаётся в кэше и при скримере не компилируется заново
static var _warm: Array = []


## Разовый выброс частиц (GPUParticles3D): billboard-квадраты с мягкой текстурой, сами удаляются.
static func burst(parent: Node, pos: Vector3, tex: String, amount: int, lifetime: float, size: float,
		velocity: Vector2, gravity: float, box: Vector3, color := Color.WHITE) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.9
	p.fixed_fps = 30
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = velocity.x
	pm.initial_velocity_max = velocity.y
	pm.gravity = Vector3(0, gravity, 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var fade := Gradient.new()
	fade.set_color(0, Color(color, 0.9))
	fade.set_color(1, Color(color, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	if _warm.size() < 64:
		_warm.append(pm)
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = load(TEX + tex + ".png")
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	if _warm.size() < 64:
		_warm.append(m)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Облако пыли от удара о пол.
static func dust(parent: Node, pos: Vector3) -> void:
	burst(parent, pos, "dust_puff", 64, 3.2, 0.65, Vector2(0.5, 1.6), -0.25, Vector3(0.45, 0.05, 0.3),
		Color(0.75, 0.7, 0.62))


## Пепел: хлопья осыпаются вниз, кружась.
static func ash(parent: Node, pos: Vector3) -> void:
	burst(parent, pos, "ash_flake", 90, 2.6, 0.09, Vector2(0.3, 1.6), -1.6, Vector3(0.3, 0.9, 0.15))
	burst(parent, pos, "dust_puff", 24, 2.0, 0.6, Vector2(0.2, 0.8), -0.2, Vector3(0.25, 0.8, 0.1),
		Color(0.12, 0.11, 0.1))


## Вдох или шёпот вплотную к уху: 3D-источник в полуметре от головы (панорама в одно ухо).
static func near_ear(head: Node3D, stream: AudioStream, volume_db := -8.0) -> void:
	var w := AudioStreamPlayer3D.new()
	w.stream = stream
	w.volume_db = volume_db
	w.unit_size = 0.6
	w.max_distance = 6.0
	w.bus = "Scare"
	w.position = Vector3(0.4 if randf() < 0.5 else -0.4, 0.05, 0.15)
	head.add_child(w)
	w.finished.connect(w.queue_free)
	w.play()


## Короткая тряска камеры (удар рядом).
static func shake(camera: Camera3D, strength := 0.04, time := 0.35) -> void:
	var base := camera.h_offset
	var tw := camera.create_tween()
	for k in 6:
		tw.tween_property(camera, "h_offset", base + randf_range(-strength, strength), time / 6.0)
	tw.tween_property(camera, "h_offset", base, 0.05)


## Прогрев: один кадр всех эффектов перед камерой, пока экран чёрный (интро) — шейдеры частиц
## и материалов компилируются заранее, а не в момент скримера (без рывка кадра).
static func prewarm(camera: Camera3D) -> void:
	var root := camera.get_tree().current_scene
	var pos := camera.global_position - camera.global_basis.z * 1.5
	dust(root, pos)
	ash(root, pos)
	var temp := []
	var hand_script := load("res://scripts/scare_hand_window.gd")
	for hand in [true, false]:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.3, 0.3)
		mi.mesh = q
		var m: StandardMaterial3D = hand_script.make_material(hand)
		_warm.append(m)
		m.albedo_color.a = 0.01
		mi.material_override = m
		root.add_child(mi)
		mi.global_position = pos
		temp.append(mi)
	var fig := MeshInstance3D.new()
	fig.mesh = QuadMesh.new()
	fig.material_override = ShadowFigure.make_material("shadow_photo")
	_warm.append(fig.material_override)
	root.add_child(fig)
	fig.global_position = pos
	temp.append(fig)
	await camera.get_tree().create_timer(0.3).timeout
	for n in temp:
		n.queue_free()


## Видит ли камера точку: она в пирамиде видимости и между ними нет стен (игрок не мешает лучу).
## Правило гарантированных скримеров: визуал появляется только там, где его точно видно.
static func can_see(cam: Camera3D, point: Vector3) -> bool:
	if cam == null or not cam.is_position_in_frustum(point):
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, point)
	var player := cam.get_tree().get_first_node_in_group("player") as CollisionObject3D
	if player:
		q.exclude = [player.get_rid()]
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit.position as Vector3).distance_to(point) < 0.35
