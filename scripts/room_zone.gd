extends Area3D
## Зона комнаты: материал пола для звука шагов игрока. Реверберацию 3D-звукам внутри зоны задают
## свойства Area3D reverb_bus_* (выставляет сборщик tools/build_horror.gd).

@export var surface := "stone"       ## stone | wood


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		body.set("surface", surface)
