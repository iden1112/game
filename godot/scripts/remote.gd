extends "res://scripts/actor.gd"
## 온라인 상대 (웹·Godot 모두): 받은 위치·자세·조준을 부드럽게 따라가요. 피해 계산은 상대 컴퓨터에서.

var is_remote := true
var _to_pos := Vector3.ZERO
var _to_yaw := 0.0
var _to_pitch := 0.0
var _vel := Vector3.ZERO
var _last_ts := -1.0
var _got := false
var _speed := 0.0
var _last_pos := Vector3.ZERO

const STANCES := ["stand", "crouch", "prone"]


func _ready() -> void:
	setup([Color(0.42, 0.23, 0.2), Color(0.25, 0.27, 0.21), Color(0.77, 0.56, 0.42)])


func reset_for_round(pos: Vector3, yaw: float, armor_lv: int) -> void:
	super.reset_for_round(pos, yaw, armor_lv)
	_to_pos = pos
	_to_yaw = yaw
	_last_pos = pos
	_got = false
	_last_ts = -1.0


## 이 상대의 총 수치 (파츠 포함)
func stats_for(id: String) -> Dictionary:
	for wp in weapons:
		if wp.id == id:
			return wp.stats
	return G.weapon_stats(id, G.full_attachments(id))


## 웹과 같은 상태 메시지: p, v, y, pi, s, l, a, sp, h, d, hl, hd, vl, vd, w, m(g/t/f), tt, he
func apply_state(s: Dictionary) -> void:
	var ts := float(s.get("ts", -1))
	if ts >= 0.0 and _last_ts >= 0.0 and ts <= _last_ts and ts > _last_ts - 60000.0:
		return # 늦게 도착한 옛날 상태
	_last_ts = ts
	var p: Array = s.get("p", [0, 0, 0])
	_to_pos = Vector3(p[0], p[1], p[2])
	var v: Array = s.get("v", [0, 0])
	_vel = Vector3(v[0], 0, v[1])
	_to_yaw = float(s.get("y", 0.0))
	_to_pitch = float(s.get("pi", 0.0))
	if not _got or global_position.distance_to(_to_pos) > 4.0:
		global_position = _to_pos
		rotation.y = _to_yaw
		_got = true
	var st: String = STANCES[clampi(int(s.get("s", 0)), 0, 2)]
	if st != stance:
		stance = st
		_apply_shape()
	lean_target = float(s.get("l", 0.0))
	ads_t = float(s.get("a", 0.0))
	sprint = int(s.get("sp", 0)) == 1
	health = float(s.get("h", health))
	if int(s.get("d", 0)) == 0 and dead and game.state == "pre":
		dead = false
		_col.disabled = false
		soldier.body.rotation = Vector3.ZERO
		soldier.body.position = Vector3.ZERO
	var hl := int(s.get("hl", helmet_lv))
	var vl := int(s.get("vl", vest_lv))
	if hl != helmet_lv or vl != vest_lv:
		helmet_lv = hl
		vest_lv = vl
		soldier.set_armor(helmet_lv, vest_lv)
	helmet_dur = float(s.get("hd", helmet_dur))
	vest_dur = float(s.get("vd", vest_dur))
	heal_t = 1.0 if int(s.get("he", 0)) == 1 else 0.0
	var m: String = str(s.get("m", "g"))
	if m == "f":
		if mode != "fist":
			mode = "fist"
			soldier.set_gun("", {})
	elif m == "t":
		var tt := str(s.get("tt", "frag"))
		if mode != "throw" or throw_type != tt:
			mode = "throw"
			throw_type = tt
			soldier.set_gun("nade:" + tt, {})
	elif not weapons.is_empty():
		var c := clampi(int(s.get("w", 0)), 0, weapons.size() - 1)
		if mode != "gun" or c != cur:
			mode = "gun"
			cur = c
			soldier.set_gun(weapons[cur].id, weapons[cur].att)


func set_loadout(list: Array) -> void:
	var keep := cur
	super.set_loadout(list)
	cur = clampi(keep, 0, weapons.size() - 1)
	if mode == "gun" and not weapons.is_empty():
		soldier.set_gun(weapons[cur].id, weapons[cur].att)


func _physics_process(dt: float) -> void:
	if dead:
		soldier.animate({"speed": 0.0, "stance": stance, "sprint": false, "lean": 0.0, "pitch": 0.0, "dead": true, "prone_t": 0.0}, dt)
		return
	# 조금 앞을 내다보고 따라가요 (속도 × 0.04초)
	var target := _to_pos + _vel * 0.04
	var k := 1.0 - exp(-dt * 14.0)
	global_position = global_position.lerp(target, k)
	rotation.y = lerp_angle(rotation.y, _to_yaw, k)
	pitch = lerpf(pitch, _to_pitch, k)
	lean = lerpf(lean, lean_target, minf(1.0, dt * 12.0))
	stance_h = lerpf(stance_h, G.STANCE[stance].eye, minf(1.0, dt * 10.0))
	_speed = Vector2(_vel.x, _vel.z).length()
	soldier.animate({"speed": _speed, "stance": stance, "sprint": sprint, "lean": lean, "pitch": pitch, "dead": false, "prone_t": 1.0 if stance == "prone" else 0.0, "heal": heal_t > 0.0}, dt)
	if _speed > 1.0:
		_step_acc += _speed * dt
		if _step_acc > 1.6:
			_step_acc = 0.0
			Sfx.step(global_position, false, stance != "stand" or _speed < 3.0)


## 피해는 상대 컴퓨터가 계산해요 (여기서는 안 줄여요)
func take_damage(_dmg: float, _from, _info: Dictionary) -> void:
	pass


func mark_dead(killer, info: Dictionary) -> void:
	if dead:
		return
	health = 0.0
	_die(killer, info)
