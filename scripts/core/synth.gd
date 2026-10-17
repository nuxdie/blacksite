class_name Synth
extends RefCounted
## Renders layered procedural sounds (filtered noise + oscillators) into AudioStreamWAV.
## A layer is a Dictionary: type (noise|sine|square|saw|tri), f0, f1, dur, vol, at, attack,
## and for noise: filter (lp|hp|bp) and q.

const RATE := 44100


static func render(layers: Array, loop := false, length := -1.0) -> AudioStreamWAV:
	var total := 0.0
	for l: Dictionary in layers:
		total = maxf(total, float(l.get("at", 0.0)) + float(l.get("dur", 0.2)) + 0.03)
	if length > 0.0:
		total = length
	var n := int(total * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for l: Dictionary in layers:
		_layer(buf, l, loop)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav


static func _layer(buf: PackedFloat32Array, l: Dictionary, sustain: bool) -> void:
	var kind: String = l.get("type", "sine")
	var f0: float = l.get("f0", 440.0)
	var f1: float = l.get("f1", f0)
	var dur: float = l.get("dur", 0.2)
	var vol: float = l.get("vol", 0.3)
	var at: float = l.get("at", 0.0)
	var attack: float = maxf(l.get("attack", 0.003), 0.0005)
	var filt: String = l.get("filter", "lp")
	var damp := 1.0 / maxf(float(l.get("q", 0.7)), 0.5)
	var start := int(at * RATE)
	var count := mini(int(dur * RATE), buf.size() - start)
	var ratio := f1 / f0
	var phase := 0.0
	var low := 0.0
	var band := 0.0
	var floor_db := 0.0001 / vol
	for i in count:
		var t := float(i) / RATE
		var k := t / dur
		var f := f0 * pow(ratio, k)
		var env: float
		if sustain:
			env = vol
		elif t < attack:
			env = vol * (t / attack)
		else:
			env = vol * pow(floor_db, (t - attack) / maxf(dur - attack, 0.001))
		var s := 0.0
		if kind == "noise":
			var fk := 2.0 * sin(PI * minf(f, 9000.0) / RATE)
			low += fk * band
			var high := (randf() * 2.0 - 1.0) - low - damp * band
			band += fk * high
			if filt == "lp":
				s = low
			elif filt == "hp":
				s = high
			else:
				s = band * damp
		else:
			phase += f / RATE
			var p := phase - floorf(phase)
			match kind:
				"sine": s = sin(TAU * p)
				"square": s = 0.6 if p < 0.5 else -0.6
				"saw": s = (p * 2.0 - 1.0) * 0.7
				_: s = (4.0 * absf(p - 0.5) - 1.0)
		buf[start + i] += s * env
