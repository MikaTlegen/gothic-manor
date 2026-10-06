extends AudioStreamPlayer3D
## Фоновый 3D-источник дома: петля (сквозняк в окнах) или редкие случайные звуки (скрип балок, пола).
## Случайные звуки играют, только если слушатель в пределах max_distance.

@export var min_interval := 12.0
@export var max_interval := 35.0
@export var loop_stream := false

var _wait := 0.0


func _ready() -> void:
	if loop_stream:
		var ogg := stream as AudioStreamOggVorbis
		if ogg:
			ogg.loop = true
		play(randf() * 10.0)
		set_process(false)
		return
	_wait = randf_range(min_interval, max_interval) * 0.5


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = randf_range(min_interval, max_interval)
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(global_position) < max_distance:
		play()
