@tool
extends EditorScenePostImport
## Пост-импорт ассетов особняка:
## — настраивает свет свечей и вешает мерцание;
## — воск получает подповерхностное рассеивание (просвечивает);
## — пламя и стекло не отбрасывают теней.
## Указать в Import → Advanced → Import Script для .gltf из models/.

const FLICKER := preload("candle_flicker.gd")


func _post_import(scene: Node) -> Object:
	_setup(scene)
	return scene


func _setup(node: Node) -> void:
	if node is OmniLight3D:
		_setup_light(node as OmniLight3D)
	elif node is MeshInstance3D:
		_setup_mesh(node as MeshInstance3D)
	for child in node.get_children():
		_setup(child)


func _setup_light(light: OmniLight3D) -> void:
	var is_big := String(light.name).contains("Chandelier")
	light.omni_range = 7.0 if is_big else 3.5
	light.light_energy = 2.2 if is_big else 0.9
	light.light_color = Color(1.0, 0.62, 0.3)
	light.shadow_enabled = is_big
	light.set_script(FLICKER)


func _setup_mesh(mi: MeshInstance3D) -> void:
	var node_name := String(mi.name)
	if node_name.contains("_Flame") or node_name.contains("_Glass") or node_name.contains("_Crystals"):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
		if mat == null:
			continue
		if mat.resource_name.begins_with("Wax"):
			mat.subsurf_scatter_enabled = true
			mat.subsurf_scatter_strength = 0.6
			mat.backlight_enabled = true
			mat.backlight = Color(0.85, 0.5, 0.22)
