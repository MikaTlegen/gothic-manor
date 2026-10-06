extends Node3D
## Настройки экземпляра ассета без правки модели: погасить огонь (неактивные подсвечники),
## затемнить материалы (обгоревший декор), переопределить свет живых источников.

@export var lights_off := false
@export var tint := Color.WHITE
@export var light_energy := -1.0     ## >= 0 — своя яркость
@export var light_range := -1.0      ## >= 0 — свой радиус
@export var light_shadows := false


func _ready() -> void:
	for n in find_children("*", "OmniLight3D", true, false):
		var l := n as OmniLight3D
		if lights_off:
			l.visible = false
			l.set_process(false)
			continue
		if light_energy >= 0.0:
			l.light_energy = light_energy
			if "_base_energy" in l:
				l.set("_base_energy", light_energy)   # мерцание candle_flicker.gd берёт базу отсюда
		if light_range >= 0.0:
			l.omni_range = light_range
		l.shadow_enabled = light_shadows
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if lights_off and String(mi.name).contains("_Flame"):
			mi.visible = false
		if tint != Color.WHITE and mi.mesh:
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
				if m:
					var d := m.duplicate() as StandardMaterial3D
					d.albedo_color = d.albedo_color * tint
					mi.set_surface_override_material(i, d)
