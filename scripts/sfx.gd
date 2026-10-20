extends Node
## Autoload "Sfx": every sound effect is synthesised at start-up, so the project
## needs no audio files at all.

const RATE := 22050
var streams := {}


func _ready() -> void:
	streams["shot_ar"] = _gun(0.28, 1.0, 140.0)
	streams["shot_smg"] = _gun(0.18, 1.4, 190.0)
	streams["shot_pistol"] = _gun(0.22, 1.2, 230.0)
	streams["shot_shotgun"] = _gun(0.45, 0.7, 90.0)
	streams["explosion"] = _gun(1.0, 0.4, 55.0)
	streams["reload"] = _clicks([0.1, 0.9, 1.5], 1.8)
	streams["empty"] = _clicks([0.0], 0.15)
	streams["step"] = _thump(0.12, 95.0)
	streams["hurt"] = _thump(0.22, 150.0)
	streams["hit"] = _tone(0.07, 1800.0, 1200.0)
	streams["pickup"] = _tone(0.12, 600.0, 950.0)
	streams["heal"] = _tone(0.35, 400.0, 720.0)


func play2d(sound: String, volume_db: float = 0.0) -> void:
	if not streams.has(sound):
		return
	var p := AudioStreamPlayer.new()
	p.stream = streams[sound]
	p.volume_db = volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func play3d(sound: String, pos: Vector3, volume_db: float = 0.0) -> void:
	if not streams.has(sound):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = streams[sound]
	p.volume_db = volume_db
	p.unit_size = 12.0
	p.max_distance = 140.0
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


# ---------------------------------------------------------------- synthesis
func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


func _gun(length: float, pitch: float, body: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var a := clampf(0.15 + pitch * 0.35, 0.05, 1.0)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 9.0 / length)
		lp += (randf_range(-1.0, 1.0) - lp) * a
		var v := lp * 1.2 + sin(TAU * body * t) * 0.7
		if t < 0.006:
			v += randf_range(-1.0, 1.0)
		s[i] = v * env * 0.8
	return _make(s)


func _clicks(times: Array, total: float) -> AudioStreamWAV:
	var n := int(total * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for tc in times:
		var start := int(float(tc) * RATE)
		for k in int(0.05 * RATE):
			var idx := start + k
			if idx < n:
				s[idx] += randf_range(-1.0, 1.0) * exp(-float(k) / (0.008 * RATE)) * 0.7
	return _make(s)


func _thump(length: float, freq: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (randf_range(-1.0, 1.0) - lp) * 0.15
		var env := exp(-t * 22.0)
		s[i] = (sin(TAU * freq * t * exp(-t * 6.0)) * 0.8 + lp * 0.4) * env
	return _make(s)


func _tone(length: float, f0: float, f1: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * lerpf(f0, f1, t / length) / RATE
		s[i] = sin(ph) * 0.45 * (1.0 - t / length)
	return _make(s)
