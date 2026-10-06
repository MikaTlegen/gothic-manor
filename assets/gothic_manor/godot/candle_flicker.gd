extends OmniLight3D
## Мерцание огня свечи: плавный шум яркости + лёгкое дрожание позиции.

@export var flicker_strength := 0.25  ## Амплитуда колебания яркости (доля от базовой)
@export var speed := 7.0              ## Скорость мерцания
@export var jitter := 0.004           ## Дрожание источника, метры

var _base_energy := 1.0
var _base_pos := Vector3.ZERO
var _noise := FastNoiseLite.new()
var _t := 0.0


func _ready() -> void:
	_base_energy = light_energy
	_base_pos = position
	_noise.seed = randi()
	_noise.frequency = 0.6
	_t = randf() * 100.0


func _process(delta: float) -> void:
	_t += delta * speed
	light_energy = _base_energy * (1.0 + _noise.get_noise_1d(_t) * flicker_strength)
	position = _base_pos + Vector3(
		_noise.get_noise_1d(_t + 31.0),
		_noise.get_noise_1d(_t + 67.0),
		_noise.get_noise_1d(_t + 97.0)
	) * jitter
