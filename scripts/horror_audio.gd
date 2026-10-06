class_name HorrorAudio
extends RefCounted
## Звуки уровня: записи CC0 (BigSoundBank) и синтез из tools/process_external.py → assets/horror/audio.
## Шины: Ambient (фон), SFX (шаги, предметы), Scare (скримеры) и реверберации комнат — RevCorridor,
## RevHall, RevCrypt. Реверберацию 3D-звукам задают зоны Area3D (reverb_bus_*) из tools/build_horror.gd.

const DIR := "res://assets/horror/audio/"
## Имя шины, громкость дБ, реверберация [размер комнаты, демпфирование, предзадержка с] или пусто
const BUSES := [
	["Ambient", -2.0, []],
	["SFX", 0.0, []],
	["Scare", 0.0, []],
	["RevCorridor", -3.0, [0.45, 0.55, 0.02]],
	["RevHall", -2.0, [0.8, 0.35, 0.04]],
	["RevCrypt", -1.0, [0.95, 0.6, 0.06]],
]


static func setup_buses() -> void:
	if AudioServer.get_bus_index("SFX") >= 0:
		return          # шины живут в AudioServer и переживают перезапуск уровня
	for spec in BUSES:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, spec[0])
		AudioServer.set_bus_volume_db(idx, spec[1])
		AudioServer.set_bus_send(idx, "Master")
		var rev: Array = spec[2]
		if rev.is_empty():
			continue
		var r := AudioEffectReverb.new()
		r.room_size = rev[0]
		r.damping = rev[1]
		r.predelay_msec = rev[2] * 1000.0
		r.hipass = 0.12
		r.dry = 0.0             # шина-посыл: только «хвост», прямой звук идёт своей шиной
		r.wet = 1.0
		AudioServer.add_bus_effect(idx, r)


static func one(sound: String) -> AudioStream:
	return load(DIR + sound + ".ogg")


## Петля: флаг loop ставится на загруженный ресурс (импорт по умолчанию — без петли).
static func looped(sound: String) -> AudioStream:
	var s := load(DIR + sound + ".ogg") as AudioStreamOggVorbis
	s.loop = true
	return s


## Случайный выбор из вариантов без повтора подряд, с разбросом высоты и громкости.
static func variants(prefix: String, count: int, pitch := 1.08, volume_db := 2.0) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	r.random_pitch = pitch
	r.random_volume_offset_db = volume_db
	for i in count:
		r.add_stream(-1, one("%s_%02d" % [prefix, i + 1]))
	return r


## Разовый 2D-звук (стингер): плеер удаляется сам по окончании.
static func play_2d(parent: Node, stream: AudioStream, volume_db := 0.0, bus := "Scare") -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.bus = bus
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p
