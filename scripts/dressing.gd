extends Node
## Подмена материалов импортированных ассетов при старте уровня (модели не трогаем):
## — Cobweb → шейдер паутины из фото-рефов (угол и полотно — разные текстуры), отсвет от свечи;
## — Glass_Leaded → прозрачный свинцовый переплёт, сквозь который виден ночной пейзаж.

const TEX := "res://assets/horror/textures/"
const GLASS_TEX := "res://assets/gothic_manor/models/textures/"


func _ready() -> void:
	var swaps := {"Cobweb": _cobweb("sheet"), "Glass_Leaded": _glass()}
	var corner := _cobweb("corner")
	var count := 0
	var root: Node = owner if owner else get_parent()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m and swaps.has(m.resource_name):
				var swap: Material = swaps[m.resource_name]
				if m.resource_name == "Cobweb" and String(mi.name).contains("Corner"):
					swap = corner
				mi.set_surface_override_material(i, swap)
				count += 1
	print("[DRESSING] заменено материалов: %d" % count)


func _cobweb(kind: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/cobweb.gdshader")
	m.set_shader_parameter("albedo_tex", load(TEX + "cobweb_%s_albedo.png" % kind))
	m.set_shader_parameter("normal_tex", load(TEX + "cobweb_%s_normal.jpg" % kind))
	return m


func _glass() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/glass_leaded.gdshader")
	m.set_shader_parameter("albedo_tex", load(GLASS_TEX + "glass_leaded_albedo.png"))
	m.set_shader_parameter("normal_tex", load(GLASS_TEX + "glass_leaded_normal.jpg"))
	return m
