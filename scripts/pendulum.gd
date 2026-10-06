extends Node3D
## Маятник напольных часов (Clock_Grandfather_Pendulum): период 2 с — «тик» на каждом крайнем положении.

@export var amplitude_deg := 6.0
@export var period := 2.0

var _pendulum: Node3D
var _t := 0.0


func _ready() -> void:
	_pendulum = find_child("Clock_Grandfather_Pendulum", true, false) as Node3D


func _process(delta: float) -> void:
	if _pendulum == null:
		return
	_t += delta
	_pendulum.rotation.z = deg_to_rad(amplitude_deg) * cos(TAU * _t / period)
