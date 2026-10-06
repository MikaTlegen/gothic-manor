class_name SoundBank
extends RefCounted
## Процедурные звуки-заглушки. Чтобы заменить на настоящие записи — задать stream у нужного
## AudioStreamPlayer/AudioStreamPlayer3D в сцене: game.gd подставляет заглушку, только если stream пуст.

const RATE := 22050


static func _stream(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


static func _buf(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


## Тиканье напольных часов: «тик» и «так» раз в секунду, петля 2 с.
static func clock_tick() -> AudioStreamWAV:
	var s := _buf(2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 2:
		var f := 2300.0 if k == 0 else 1650.0
		var start := k * RATE
		for i in int(0.06 * RATE):
			var t := float(i) / RATE
			var click := rng.randf_range(-1, 1) * exp(-t / 0.002)
			var ring := sin(TAU * f * t) * exp(-t / 0.012) + 0.5 * sin(TAU * f * 1.51 * t) * exp(-t / 0.008)
			s[start + i] += (click * 0.5 + ring * 0.6) * 0.8
	return _stream(s, true)


## Камин: низкий гул пламени и случайные щелчки поленьев, петля 6 с.
static func fire_crackle() -> AudioStreamWAV:
	var s := _buf(6.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.02
		s[i] = lp * 0.9 * (0.75 + 0.25 * sin(TAU * t / 3.0))
	for k in 70:
		var at := rng.randi_range(0, s.size() - 2000)
		var amp := rng.randf_range(0.15, 0.7)
		var tau := rng.randf_range(0.0008, 0.004)
		for i in int(tau * 6.0 * RATE):
			s[at + i] += rng.randf_range(-1, 1) * amp * exp(-float(i) / RATE / tau)
	return _stream(s, true)


## Тяжёлый шаг по камню.
static func footstep(heavy := true) -> AudioStreamWAV:
	var s := _buf(0.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31 if heavy else 32
	var lp := 0.0
	var amp := 0.9 if heavy else 0.35
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.08
		var thump := sin(TAU * (65.0 - 30.0 * t) * t) * exp(-t / 0.07)
		var grit := lp * exp(-t / 0.035) * 1.6 + rng.randf_range(-1, 1) * 0.15 * exp(-(t - 0.05) * (t - 0.05) / 0.0008)
		s[i] = (thump * 0.8 + grit) * amp
	return _stream(s)


## Свеча гаснет: короткий выдох.
static func candle_out() -> AudioStreamWAV:
	var s := _buf(0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var bp := 0.0
	var bp2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		bp += (rng.randf_range(-1, 1) - bp) * 0.3
		bp2 += (bp - bp2) * 0.1
		s[i] = (bp - bp2) * 1.4 * sin(PI * minf(t / 0.6, 1.0)) * exp(-t / 0.25)
	return _stream(s)


## Скрип тяжёлой двери.
static func door_creak() -> AudioStreamWAV:
	var s := _buf(1.6)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 150.0 + 70.0 * sin(TAU * 0.6 * t) + 20.0 * sin(TAU * 7.0 * t)
		phase += f / RATE
		var saw := 2.0 * fposmod(phase, 1.0) - 1.0
		var stick := 0.55 + 0.45 * sin(TAU * 17.0 * t)
		s[i] = saw * stick * 0.35 * sin(PI * t / 1.6)
	return _stream(s)


## Фоновый гул дома: низкие биения и ветер в щелях, петля 10 с.
static func drone() -> AudioStreamWAV:
	var s := _buf(10.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.01
		var wind := lp * (0.6 + 0.4 * sin(TAU * t / 10.0))
		s[i] = (sin(TAU * 55.0 * t) + sin(TAU * 55.7 * t)) * 0.12 + sin(TAU * 110.0 * t) * 0.03 + wind * 1.5
	return _stream(s, true)


## Сердцебиение (появляется, когда свеча при смерти), петля 0.9 с.
static func heartbeat() -> AudioStreamWAV:
	var s := _buf(0.9)
	for i in s.size():
		var t := float(i) / RATE
		var a := exp(-t / 0.05) * sin(TAU * 48.0 * t)
		var t2 := t - 0.28
		var b := 0.0 if t2 < 0.0 else exp(-t2 / 0.06) * sin(TAU * 42.0 * t2) * 0.7
		s[i] = (a + b) * 0.9
	return _stream(s, true)
