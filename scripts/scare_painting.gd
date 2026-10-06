extends Area3D
## Гарантированный скример 1 «Падающая картина»: игрок проходит узкий проём — через мгновение портрет
## впереди срывается со стены, переворачивается и с ударом падает лицом в пол, поднимая облако пыли.
## Падает портрет, который сейчас в кадре и виден без помех (ближайший к игроку); если ни одного не видно —
## скример ждёт взгляда на стену, а не падает за спиной.

@export var scare_id := "painting_fall"
@export var painting_path: NodePath  ## портрет, который сорвётся (Portrait_Frame)
@export var delay := 0.35

const HALF_H := 0.61                 ## от центра рамы до нижней кромки, м
const FALL_TIME := 0.55

var fired := false
var _pending := false
var _sound: AudioStream
var _painting: Node3D
var _start: Transform3D
var _floor_y := 0.0


func _ready() -> void:
	ScareLedger.register(scare_id)
	_sound = HorrorAudio.one("painting_fall")
	body_entered.connect(_on_body_entered)
	set_process(false)


func _on_body_entered(body: Node) -> void:
	if not fired and not _pending and body.is_in_group("player"):
		_pending = true
		set_process(true)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if cam.global_position.distance_to(global_position) > 12.0:
		_pending = false                  # ушёл, не увидев ни одной картины — ждём следующего прохода
		set_process(false)
		return
	var pick := _visible_painting(cam)
	if pick and ScareLedger.can_fire(scare_id, ScareLedger.REST_GUARANTEED):
		set_process(false)
		_pending = false
		fire(pick)


## Ближайший к камере портрет в кадре без помех (предпочтительно — заданный в сборщике).
func _visible_painting(cam: Camera3D) -> Node3D:
	var preset := get_node_or_null(painting_path) as Node3D
	if preset and _sees(cam, preset):
		return preset
	var best: Node3D = null
	for n in get_tree().get_nodes_in_group("portraits"):
		var p := n as Node3D
		if p.get("fired") or cam.global_position.distance_to(p.global_position) > 7.0 or not _sees(cam, p):
			continue
		if best == null or cam.global_position.distance_to(p.global_position) < cam.global_position.distance_to(best.global_position):
			best = p
	return best


func _sees(cam: Camera3D, p: Node3D) -> bool:
	return ScareFX.can_see(cam, p.global_position + p.global_basis.z.normalized() * 0.15)


func fire(pick: Node3D = null) -> void:
	fired = true
	ScareLedger.mark_fired(scare_id)
	_painting = pick if pick else get_node_or_null(painting_path) as Node3D
	if _painting == null:
		push_warning("[SCARE] картина: нет портрета %s" % painting_path)
		return
	print("[SCARE] картина %s сорвалась со стены в %s" % [_painting.name, _painting.global_position])
	await get_tree().create_timer(delay).timeout
	_painting.set_process(false)          # следящий взгляд замирает
	_start = _painting.global_transform
	_floor_y = _floor_below(_start.origin)
	var tw := create_tween()
	# Рывок: гвоздь вылетает — рама проседает и чуть наклоняется
	tw.tween_method(_pose.bind(0.04), 0.0, 0.08, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.08)
	# Падение: нижняя кромка соскальзывает вниз, верх заваливается вперёд — лицом в пол
	tw.tween_method(_fall, 0.0, 1.0, FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_impact)


## Рывок: проседание drop м и наклон верхом вперёд на угол t (рад).
func _pose(t: float, drop: float) -> void:
	var xf := _start
	xf.origin -= _start.basis.y.normalized() * drop * (t / 0.08)
	var hinge := xf.origin - xf.basis.y * HALF_H
	var rot := Basis(xf.basis.x.normalized(), t)
	_painting.global_transform = Transform3D(rot * xf.basis, hinge + rot * (xf.origin - hinge))


## Падение: шарнир у нижней кромки опускается к полу, рама поворачивается на 90° лицом вниз.
func _fall(t: float) -> void:
	var hinge0 := _start.origin - _start.basis.y.normalized() * 0.04 - _start.basis.y * HALF_H
	var hinge := Vector3(hinge0.x, lerpf(hinge0.y, _floor_y + 0.1, t), hinge0.z)
	hinge += _start.basis.z.normalized() * 0.15 * t          # отходит от стены
	var rot := Basis(_start.basis.x.normalized(), lerpf(0.08, PI / 2, t))
	_painting.global_transform = Transform3D(rot * _start.basis, hinge + rot * (_start.basis.y * HALF_H))


func _impact() -> void:
	var pos := _painting.global_position
	print("[SCARE] картина упала: %s, пол %.2f" % [pos, _floor_y])
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = _sound
	sfx.bus = "SFX"
	sfx.unit_size = 4.0
	get_tree().current_scene.add_child(sfx)
	sfx.global_position = pos
	sfx.finished.connect(sfx.queue_free)
	sfx.play()
	ScareFX.dust(get_tree().current_scene, Vector3(pos.x, _floor_y + 0.05, pos.z))
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(pos) < 6.0:
		ScareFX.shake(cam, 0.03, 0.3)


func _floor_below(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 5.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else p.y - 1.9
