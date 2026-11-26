extends Node
## 소리 (자동 로드: Sfx) — 원본처럼 파일 없이 코드로 만들어요

const RATE := 22050

var _cache := {}
var _p3: Array[AudioStreamPlayer3D] = []
var _p2: Array[AudioStreamPlayer] = []
var _i3 := 0
var _i2 := 0
var _ring: AudioStreamPlayer
var muted := false # 자동 테스트 등


func _ready() -> void:
	for i in 24:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_distance = 400.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_p3.append(p)
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_p2.append(p)
	_ring = AudioStreamPlayer.new()
	add_child(_ring)
	apply_volume()
	Settings.changed.connect(apply_volume)


func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, Settings.volume)))


# ---------- 소리 만들기 ----------
func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	return w


## 총소리: 터지는 소리(잡음) + 낮은 '쿵'
func _gun(dur: float, decay: float, thump: float, bright: float, supp: bool) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := randf_range(-1.0, 1.0)
		lp += (x - lp) * (0.25 if supp else bright)
		lp2 += (lp - lp2) * 0.08
		var crack := (lp - lp2 * 0.6) * exp(-t * decay * (2.2 if supp else 1.0))
		var body := sin(TAU * thump * t * (1.0 - t * 1.5)) * exp(-t * 18.0) * (0.25 if supp else 0.9)
		var tail := lp2 * exp(-t * decay * 0.35) * (0.1 if supp else 0.5)
		s[i] = (crack * 1.1 + body + tail) * (0.45 if supp else 1.0)
	return _wav(s)


func _noise_burst(dur: float, decay: float, bright: float, vol: float, tone := 0.0) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (randf_range(-1.0, 1.0) - lp) * bright
		var v := lp * 2.0
		if tone > 0.0:
			v = v * 0.5 + sin(TAU * tone * t) * 0.6
		s[i] = v * exp(-t * decay) * vol
	return _wav(s)


func _tone(freq: float, dur: float, vol: float, decay := 6.0) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t * 200.0) * exp(-t * decay)
		s[i] = sin(TAU * freq * t) * env * vol
	return _wav(s)


func _explosion() -> AudioStreamWAV:
	var n := int(1.8 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (randf_range(-1.0, 1.0) - lp) * 0.2
		lp2 += (lp - lp2) * 0.03
		var boom := sin(TAU * 45.0 * t * (1.0 - t * 0.3)) * exp(-t * 4.0)
		s[i] = (lp * exp(-t * 9.0) * 1.3 + lp2 * 4.0 * exp(-t * 1.8) + boom * 0.9) * 0.9
	return _wav(s)


func _snd(key: String, make: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


# ---------- 틀기 ----------
func _play3(stream: AudioStream, pos: Vector3, db := 0.0, pitch := 1.0) -> void:
	if muted or not is_inside_tree():
		return
	var p := _p3[_i3]
	_i3 = (_i3 + 1) % _p3.size()
	p.stream = stream
	p.global_position = pos
	p.volume_db = db
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.play()


func _play2(stream: AudioStream, db := 0.0, pitch := 1.0) -> void:
	if muted:
		return
	var p := _p2[_i2]
	_i2 = (_i2 + 1) % _p2.size()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


const GUN_SND := {
	"AR": [0.4, 13.0, 90.0, 0.55], "SMG": [0.28, 19.0, 115.0, 0.6], "DMR": [0.55, 9.0, 80.0, 0.5], "SR": [0.9, 6.0, 60.0, 0.45],
	"SG": [0.6, 8.0, 70.0, 0.4], "LMG": [0.42, 12.0, 85.0, 0.5], "HG": [0.3, 16.0, 125.0, 0.6], "XB": [0.15, 30.0, 200.0, 0.3],
}


func shot(pos: Vector3, cat: String, suppressed: bool, is_player: bool) -> void:
	var p: Array = GUN_SND.get(cat, GUN_SND.AR)
	var key := "gun_%s_%s" % [cat, suppressed]
	var st: AudioStreamWAV = _snd(key, func(): return _gun(p[0], p[1], p[2], p[3], suppressed))
	if is_player:
		_play2(st, -4.0)
	else:
		_play3(st, pos, 4.0 if not suppressed else -6.0)


func reload(dur: float) -> void:
	var c := _snd("click", func(): return _noise_burst(0.05, 70.0, 0.7, 0.6, 1800.0))
	_play2(c, -8.0)
	get_tree().create_timer(dur * 0.45).timeout.connect(func(): _play2(c, -6.0, 0.8))
	get_tree().create_timer(dur * 0.85).timeout.connect(func(): _play2(c, -5.0, 1.15))


func click(vol := 0.3, freq := 1500.0) -> void:
	var key := "clk_%d" % int(freq)
	_play2(_snd(key, func(): return _noise_burst(0.04, 90.0, 0.8, 0.6, freq)), linear_to_db(maxf(0.02, vol)) - 2.0)


func bolt() -> void:
	var c := _snd("bolt", func(): return _noise_burst(0.12, 30.0, 0.5, 0.7, 900.0))
	_play2(c, -6.0)
	get_tree().create_timer(0.25).timeout.connect(func(): _play2(c, -6.0, 1.2))


func empty() -> void:
	click(0.25, 2200.0)


func hit(head: bool) -> void:
	if head:
		_play2(_snd("ding", func(): return _tone(1900.0, 0.25, 0.5, 14.0)), -6.0)
	else:
		_play2(_snd("tick", func(): return _noise_burst(0.05, 60.0, 0.9, 0.5, 2600.0)), -8.0)


func hurt() -> void:
	_play2(_snd("hurt", func(): return _noise_burst(0.12, 25.0, 0.15, 0.9, 140.0)), -2.0)


func step(pos: Vector3, is_player: bool, soft: bool) -> void:
	var st: AudioStreamWAV = _snd("step", func(): return _noise_burst(0.07, 45.0, 0.12, 0.9, 90.0))
	var db := -14.0 if soft else -8.0
	if is_player:
		_play2(st, db - 6.0, randf_range(0.9, 1.1))
	else:
		_play3(st, pos, db + 2.0, randf_range(0.9, 1.1))


func explosion(pos: Vector3) -> void:
	_play3(_snd("boom", _explosion), pos, 10.0)


func smoke(pos: Vector3) -> void:
	_play3(_snd("hiss", func(): return _noise_burst(2.5, 0.9, 0.6, 0.5)), pos, 0.0)


func flash(pos: Vector3) -> void:
	_play3(_snd("bang", func(): return _noise_burst(0.5, 10.0, 0.9, 1.0)), pos, 10.0)


func pin() -> void:
	_play2(_snd("pin", func(): return _noise_burst(0.08, 40.0, 0.9, 0.5, 3200.0)), -8.0)


func spoon() -> void:
	_play2(_snd("spoon", func(): return _noise_burst(0.1, 35.0, 0.9, 0.5, 2400.0)), -8.0)


func bounce(pos: Vector3) -> void:
	_play3(_snd("bounce", func(): return _noise_burst(0.06, 60.0, 0.5, 0.6, 700.0)), pos, -8.0)


func beep(freq := 660.0, dur := 0.15, vol := 0.3) -> void:
	_play2(_snd("beep_%d_%d" % [int(freq), int(dur * 100)], func(): return _tone(freq, dur, 0.6, 4.0)), linear_to_db(vol))


func crack(pos: Vector3) -> void:
	_play3(_snd("crack", func(): return _noise_burst(0.05, 80.0, 0.95, 0.8)), pos, -2.0)


func punch(hit_something: bool) -> void:
	_play2(_snd("punch_%s" % hit_something, func(): return _noise_burst(0.1 if hit_something else 0.15, 30.0, 0.2 if hit_something else 0.5, 0.8, 120.0 if hit_something else 0.0)), -6.0)


func impact(pos: Vector3) -> void:
	_play3(_snd("impact", func(): return _noise_burst(0.05, 70.0, 0.6, 0.5)), pos, -14.0, randf_range(0.8, 1.3))


## 이명: 가까이서 터지면 삐— 소리
func deafen(sec: float, k: float) -> void:
	if muted:
		return
	_ring.stream = _snd("ring", func(): return _tone(3600.0, 6.0, 0.25, 0.6))
	_ring.volume_db = linear_to_db(clampf(k, 0.05, 1.0)) - 6.0
	_ring.play()
	var tw := create_tween()
	tw.tween_property(_ring, "volume_db", -60.0, sec)
	tw.tween_callback(_ring.stop)
