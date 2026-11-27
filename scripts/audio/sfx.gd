extends Node
## Autoload "Sfx": all sound is synthesised at startup (no audio assets yet), so swapping in recorded
## samples later only means replacing the streams in _build(). Fire-and-forget: Sfx.play(&"punch").

const RATE := 22050
const POOL := 10

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _crowd: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _enabled := true

func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless"  # sims/tests never need the synthesis cost
	if not _enabled:
		return
	_rng.seed = 7
	_build()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_crowd = AudioStreamPlayer.new()
	_crowd.stream = _streams[&"crowd"]
	add_child(_crowd)
	Settings.changed.connect(_apply_crowd)

## Start/stop the arena ambience (fight scene only).
func set_crowd(on: bool) -> void:
	if not _enabled:
		return
	if on and not _crowd.playing:
		_crowd.play()
	elif not on:
		_crowd.stop()
	_apply_crowd()

func _apply_crowd() -> void:
	if _crowd:
		_crowd.volume_db = linear_to_db(maxf(Settings.crowd_volume * 0.35, 0.0001))

func play(id: StringName, volume := 1.0, pitch_jitter := 0.08) -> void:
	if not _enabled or not _streams.has(id):
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[id]
	p.volume_db = linear_to_db(maxf(volume, 0.0001))
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()

# --- synthesis ---

func _build() -> void:
	_streams[&"punch"] = _thump(0.13, 130.0, 0.55, 0.9)
	_streams[&"kick"] = _thump(0.2, 85.0, 0.65, 1.0)
	_streams[&"knee"] = _thump(0.17, 100.0, 0.5, 0.9)
	_streams[&"block"] = _thump(0.09, 260.0, 0.85, 0.55)
	_streams[&"check"] = _thump(0.12, 420.0, 0.9, 0.7)
	_streams[&"parry"] = _tone([1400.0, 2100.0], 0.12, 22.0, 0.3)
	_streams[&"whoosh"] = _whoosh(0.16)
	_streams[&"knockdown"] = _thump(0.45, 55.0, 0.2, 1.0)
	_streams[&"bell"] = _bell()
	_streams[&"crowd"] = _crowd_bed(4.0)

func _make(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w

## Low-passed noise crack on top of a falling-pitch body thump.
func _thump(dur: float, freq: float, noise_mix: float, gain: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 6.0 / dur)
		phase += TAU * freq * (1.0 - 0.5 * t / dur) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.35
		s[i] = (sin(phase) * (1.0 - noise_mix * 0.5) + lp * noise_mix) * env * gain
	return _make(s)

func _tone(freqs: Array, dur: float, decay: float, gain: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for f in freqs:
			v += sin(TAU * f * t)
		s[i] = v / freqs.size() * exp(-t * decay) * gain
	return _make(s)

func _whoosh(dur: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var x := float(i) / n
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * (0.08 + 0.25 * x)
		s[i] = lp * sin(PI * x) * 0.5
	return _make(s)

func _bell() -> AudioStreamWAV:
	var dur := 1.8
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var partials := [[880.0, 1.0, 2.2], [1320.0, 0.6, 2.8], [2290.0, 0.4, 4.0], [3100.0, 0.2, 6.0]]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for p in partials:
			v += sin(TAU * p[0] * t) * p[1] * exp(-t * p[2])
		# A quick tremolo gives the "ding-ding" ring of a struck bell.
		s[i] = v * 0.3 * (0.75 + 0.25 * sin(TAU * 12.0 * t))
	return _make(s)

## Looping band-passed noise with slow swell; crossfaded ends so the loop doesn't click.
func _crowd_bed(dur: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var x := _rng.randf_range(-1.0, 1.0)
		lp1 += (x - lp1) * 0.12
		lp2 += (x - lp2) * 0.015
		s[i] = (lp1 - lp2) * 1.6
	var fade := RATE / 4
	for i in fade:
		var k := float(i) / fade
		s[i] = lerpf(s[n - fade + i], s[i], k)  # blend the tail into the head
	s.resize(n - fade)
	return _make(s, true)
