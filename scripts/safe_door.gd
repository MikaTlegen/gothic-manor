extends Node3D
## Двустворчатая дверь «Своей комнаты» (Door_SafeRoom): створки распахиваются внутрь комнаты,
## когда игрок подходит. Створки — узлы Door_Gothic_LeafL/R с пивотом на петлях.
## Скрип звучит ровно столько, сколько идут створки: по окончании анимации — короткое затухание и stop().

signal opened

@export var open_angle := 100.0
@export var open_time := 2.4
@export var stop_fade := 0.15        ## затухание скрипа перед остановкой, с (без щелчка)

var is_open := false


func open(sound: AudioStreamPlayer3D = null) -> void:
	if is_open:
		return
	is_open = true
	var left := find_child("Door_Gothic_LeafL", true, false) as Node3D
	var right := find_child("Door_Gothic_LeafR", true, false) as Node3D
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if left:
		tw.tween_property(left, "rotation:y", deg_to_rad(open_angle), open_time)
	if right:
		tw.tween_property(right, "rotation:y", deg_to_rad(-open_angle), open_time)
	if sound:
		sound.play()
		tw.finished.connect(_stop_sound.bind(sound, sound.volume_db))
	opened.emit()


## Створки встали — звук гасится за stop_fade секунд и останавливается.
func _stop_sound(sound: AudioStreamPlayer3D, volume: float) -> void:
	var fade := create_tween()
	fade.tween_property(sound, "volume_db", -60.0, stop_fade)
	fade.tween_callback(sound.stop)
	fade.tween_callback(func() -> void: sound.volume_db = volume)
