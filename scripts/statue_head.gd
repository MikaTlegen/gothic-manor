extends Node3D
## Гарантированный скример 5 «Голова статуи» (Statue_Angel_Miller): после узкого прохода в зал игрок
## подходит к ангелу вплотную — склонённая каменная голова со скрежетом поворачивается к нему
## и дальше медленно следит за ним, пока он рядом.

@export var scare_id := "statue_head"
@export var head_name := "Statue_Angel_Wreath_Head"
@export var trigger_dist := 2.8      ## «вплотную», м (по горизонтали от оси статуи)
@export var max_yaw_deg := 80.0
@export var head_pitch := 0.28       ## наклон головы при повороте, рад (+ — ниже, − — выше)

const TURN_TIME := 1.6
const FOLLOW_SPEED := 0.35           ## рад/с — после поворота голова тянется за игроком

var fired := false
var _grind: AudioStream
var _armed := false
var _turning := false
var _head: Node3D
var _player: Node3D


func _ready() -> void:
	ScareLedger.register(scare_id)
	_grind = HorrorAudio.one("stone_grind")
	_head = find_child(head_name, true, false) as Node3D
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _head == null or _player == null:
		push_warning("[STATUE] нет головы %s" % head_name)
		set_process(false)
		return
	for c in get_children():
		if c is Area3D and String(c.name).begins_with("Chokepoint"):
			(c as Area3D).body_entered.connect(_on_chokepoint)


func _on_chokepoint(body: Node) -> void:
	if body.is_in_group("player"):
		_armed = true


func _process(delta: float) -> void:
	var to := _player.global_position - global_position
	to.y = 0.0
	if not fired:
		if _armed and to.length() < trigger_dist and _head_visible() and ScareLedger.can_fire(scare_id, ScareLedger.REST_GUARANTEED):
			fire()
		return
	if _turning or to.length() > 6.0:
		return
	_head.rotation.y = move_toward(_head.rotation.y, _target_yaw(), FOLLOW_SPEED * delta)


## Голова в кадре: точка чуть перед лицом в сторону камеры (сама статуя закрыта своей коллизией).
func _head_visible() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var p := _head.global_position
	return ScareFX.can_see(cam, p + (cam.global_position - p).normalized() * 0.5)


func _target_yaw() -> float:
	var local := to_local(_player.global_position)
	return clampf(atan2(local.x, local.z), -deg_to_rad(max_yaw_deg), deg_to_rad(max_yaw_deg))


func fire() -> void:
	fired = true
	_turning = true
	ScareLedger.mark_fired(scare_id)
	print("[SCARE] статуя повернула голову")
	var grind := AudioStreamPlayer3D.new()
	grind.stream = _grind
	grind.volume_db = -4.0
	grind.unit_size = 3.0
	grind.bus = "SFX"
	_head.add_child(grind)
	grind.play()
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_head, "rotation", Vector3(head_pitch, _target_yaw(), 0.0), TURN_TIME)
	tw.tween_callback(func() -> void: _turning = false)
