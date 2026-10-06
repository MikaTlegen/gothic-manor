extends Area3D
## Гарантированный скример 3 «Захлопнутая дверь»: дверь в узком проёме стоит распахнутой. Стоит игроку
## пройти дальше — створки с грохотом захлопываются за спиной, порыв задувает свечу на 1.5 с,
## и в полной темноте у самого уха кто-то вдыхает. Затем фитиль вспыхивает снова.

@export var scare_id := "door_slam"
@export var door_path: NodePath
@export var open_angle := 95.0
@export var dark_time := 1.5

var fired := false
var _slam: AudioStream
var _inhale: AudioStream
var _left: Node3D
var _right: Node3D


func _ready() -> void:
	ScareLedger.register(scare_id)
	_slam = HorrorAudio.one("door_slam")
	_inhale = HorrorAudio.one("inhale_ear")
	var door := get_node_or_null(door_path) as Node3D
	if door:
		_left = door.find_child("Door_Gothic_LeafL", true, false) as Node3D
		_right = door.find_child("Door_Gothic_LeafR", true, false) as Node3D
	if _left:
		_left.rotation.y = deg_to_rad(open_angle)
	if _right:
		_right.rotation.y = deg_to_rad(-open_angle)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not fired and body.is_in_group("player"):
		fire(body as Node3D)


func fire(player: Node3D) -> void:
	fired = true
	ScareLedger.mark_fired(scare_id)
	print("[SCARE] дверь захлопнулась за спиной")
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _left:
		tw.tween_property(_left, "rotation:y", 0.0, 0.22)
	if _right:
		tw.tween_property(_right, "rotation:y", 0.0, 0.22)
	await tw.finished
	var door := get_node_or_null(door_path) as Node3D
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = _slam
	sfx.bus = "SFX"
	sfx.unit_size = 6.0
	get_tree().current_scene.add_child(sfx)
	sfx.global_position = (door.global_position if door else global_position) + Vector3.UP * 1.4
	sfx.finished.connect(sfx.queue_free)
	sfx.play()
	var candle := player.get_node_or_null("Head/Camera3D/Hand")
	if candle and candle.has_method("snuff"):
		candle.snuff(dark_time)
	var cam := get_viewport().get_camera_3d()
	if cam:
		ScareFX.shake(cam, 0.05, 0.4)
	await get_tree().create_timer(0.55).timeout
	if is_instance_valid(player):
		ScareFX.near_ear(player.get_node("Head") as Node3D, _inhale, -6.0)
