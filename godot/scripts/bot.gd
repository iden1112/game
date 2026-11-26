extends "res://scripts/actor.gd"
## AI 봇 — 원본 AI 를 옮긴 것: 길찾기, 밀기/지키기 작전, 소리 듣기, 거리별 총 고르기, 끊어 쏘기, 수류탄, 치료

var level: Dictionary = G.BOT_LEVELS[1]
var target = null

var ai := {}
var _time := 0.0


func _ready() -> void:
	setup([Color(0.42, 0.23, 0.2), Color(0.25, 0.27, 0.21), Color(0.77, 0.56, 0.42)])


func round_start(flip: bool) -> void:
	ai = {
		"see": false, "see_t": 0.0, "last_seen": null, "last_seen_t": -99.0, "heard": null, "heard_t": -99.0, "hurt_t": -99.0,
		"path": [], "path_i": 0, "goal": null, "repath_t": 0.0, "strafe": 1.0, "strafe_t": 0.0, "crouch_t": 0.0, "burst_left": 0, "pause_t": 0.0,
		"err": Vector2.ZERO, "aim_t": 0.0, "aim_head": randf() < level.head, "mode": "push" if randf() < 0.55 else "hold",
		"hold_t": randf_range(6, 14), "stuck_t": 0.0, "last_pos": global_position, "nade_cd": randf_range(6, 12), "think_t": 0.0, "alert_turn": false,
	}
	var spots: Array = game.world.spots
	var s: Array = spots[randi() % spots.size()]
	var g := Vector3(s[0] + randf_range(-1, 1), 0, s[1] + randf_range(-1, 1))
	if flip:
		g = Vector3(-g.x, 0, -g.z)
	ai.goal = g
	_time = 0.0


func pick_loadout() -> Array:
	var p: String = G.BOT_PRIMARY[randi() % G.BOT_PRIMARY.size()]
	var s: String = G.BOT_SECONDARY[randi() % G.BOT_SECONDARY.size()]
	if G.weapon(p).cat == "SMG" and G.weapon(s).cat == "SMG":
		s = ["m416", "akm", "scar"][randi() % 3]
	var h: String = G.BOT_PISTOL[randi() % G.BOT_PISTOL.size()]
	return [{"id": p}, {"id": s}, {"id": h}]


func apply_recoil(v: float, h: float) -> void:
	var c: float = level.comp
	pitch += v * (1.0 - c) * randf_range(-0.4, 1.0)
	rotate_y(-(h * (1.0 - c) + randf_range(-1, 1) * v * (1.0 - c) * 0.5))


var _pick_t := 0.0


## 상대 고르기: 보이는 적 중 가장 가까운 (없으면 그냥 가장 가까운 적)
func _pick_target() -> void:
	var best = null
	var bd := 1e9
	var best_vis = null
	var bvd := 1e9
	for a in game.actors():
		if a == self or a.dead or game.same_team(self, a) or a.get("home") != null:
			continue
		var d: float = global_position.distance_to(a.global_position)
		if d < bd:
			bd = d
			best = a
		if d < bvd and _can_see(a):
			bvd = d
			best_vis = a
	var nt = best_vis if best_vis != null else best
	if nt != target:
		ai.see_t = 0.0
		ai.aim_t = 0.0
	target = nt


func hear_shot(shooter, supp: bool) -> void:
	if ai.is_empty() or shooter == self or game.same_team(self, shooter):
		return
	if shooter.global_position.distance_to(global_position) < (22.0 if supp else 160.0):
		ai.heard = shooter.global_position
		ai.heard_t = _time


func take_damage(dmg: float, from, info: Dictionary) -> void:
	super.take_damage(dmg, from, info)
	if not ai.is_empty() and from and from != self:
		ai.heard = from.global_position
		ai.heard_t = _time
		ai.hurt_t = _time
		if not ai.see:
			ai.alert_turn = true


func _can_see(t) -> bool:
	if t == null or t.dead or blind > 0.4:
		return false
	var from := eye_position()
	var to: Vector3 = t.global_position + Vector3(0, t.height() * 0.7, 0)
	var d := from.distance_to(to)
	if d > 220.0:
		return false
	# 시야각: 앞쪽 150도 (맞았거나 소리 들었으면 돌아봐요)
	var f := look_dir()
	if f.dot((to - from).normalized()) < cos(deg_to_rad(75)) and d > 4.0:
		return false
	if game.combat.smoke_blocks(from, to):
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to, G.LAYER_WORLD)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		# 머리만 보여도 봐요
		var q2 := PhysicsRayQueryParameters3D.create(from, t.eye_position(), G.LAYER_WORLD)
		return get_world_3d().direct_space_state.intersect_ray(q2).is_empty()
	return true


func _weapon_for(dist: float) -> int:
	var best := cur
	var bs := -9.0
	for i in weapons.size():
		var wp: Dictionary = weapons[i]
		var c: String = wp.stats.cat
		var s := 2.2 if dist < 90 else 1.8
		match c:
			"SG":
				s = 3.0 if dist < 18 else -1.0
			"SMG":
				s = 2.5 if dist < 30 else (1.5 if dist < 60 else 0.5)
			"SR":
				s = 3.0 if dist > 40 else (1.5 if dist > 18 else 0.2)
			"DMR":
				s = 2.6 if dist > 30 else 1.2
			"HG":
				s = 0.3
		s += 0.0 if wp.mag > 0 else -1.0
		if s > bs:
			bs = s
			best = i
	return best


func _physics_process(dt: float) -> void:
	if game == null:
		return
	var live: bool = game.is_live()
	wish = Vector3.ZERO
	trigger = false
	if live and not dead and not ai.is_empty():
		_pick_t -= dt
		if _pick_t <= 0.0 or target == null or target.dead:
			_pick_t = 0.5
			_pick_target()
	if live and not dead and target != null and not ai.is_empty():
		_think(dt)
	var mag_before: int = w().mag if w() else 0
	update_weapon(dt)
	if w() and w().mag < mag_before and ai.has("burst_left"):
		ai.burst_left -= 1
		if ai.burst_left <= 0:
			ai.pause_t = randf_range(level.pause[0], level.pause[1])
	physics_step(dt)


func _think(dt: float) -> void:
	_time += dt
	var t = target
	var sees := _can_see(t)
	ai.see = sees
	if sees:
		ai.see_t += dt
		ai.last_seen = t.global_position
		ai.last_seen_t = _time
	else:
		ai.see_t = 0.0
		ai.aim_t = 0.0
	sprint = false
	var dist: float = global_position.distance_to(t.global_position)
	# 총 고르기
	if mode == "gun" and switch_t <= 0.0 and reload_t <= 0.0 and heal_t <= 0.0:
		var bi := _weapon_for(dist)
		if bi != cur and (not sees or w().mag == 0):
			equip(bi)
	if mode != "gun" and not pin:
		equip(cur, false)
	if sees and ai.see_t > 0.05:
		_combat(dt, dist)
		return
	# ---- 안 보일 때 ----
	ai.burst_left = 0
	# 맞았는데 못 봤으면 그쪽으로 돌아봐요
	var goal = null
	if ai.alert_turn and ai.heard != null:
		var to: Vector3 = ai.heard - global_position
		_turn_to(atan2(-to.x, -to.z), dt * level.turn)
		if absf(wrapf(atan2(-to.x, -to.z) - rotation.y, -PI, PI)) < 0.3:
			ai.alert_turn = false
	if ai.last_seen != null and _time - ai.last_seen_t < 8.0:
		goal = ai.last_seen
	elif ai.heard != null and _time - ai.heard_t < 10.0:
		goal = ai.heard
	elif ai.mode == "hold":
		ai.hold_t -= dt
		goal = ai.goal
		if ai.hold_t <= 0.0:
			ai.mode = "push"
	else:
		goal = t.global_position # 밀기: 상대 쪽으로
	# 치료·재장전 (안 보일 때)
	if health < 90.0 and meds > 0 and heal_t <= 0.0 and _time - ai.hurt_t > 2.0:
		start_heal()
	var wp = w()
	if wp and wp.mag < wp.stats.mag * 0.5 and reload_t <= 0.0:
		start_reload()
	# 수류탄: 최근에 본 곳이 10~30m 면 던져요
	ai.nade_cd -= dt
	if ai.nade_cd <= 0.0 and ai.last_seen != null and _time - ai.last_seen_t < 5.0 and throwables.get("frag", 0) > 0:
		var ld: float = global_position.distance_to(ai.last_seen)
		if ld > 10.0 and ld < 30.0:
			_throw_at(ai.last_seen)
			ai.nade_cd = randf_range(10, 18)
			return
	if goal != null:
		var at_goal: bool = global_position.distance_to(goal) < 1.5
		if at_goal and goal == ai.last_seen:
			ai.last_seen = null
		elif at_goal and goal == ai.heard:
			ai.heard = null
		if not at_goal:
			_move_to(goal, dt, ai.mode == "push" and heal_t <= 0.0)
	_unstick(dt)


func _move_to(goal: Vector3, dt: float, run: bool) -> void:
	ai.repath_t -= dt
	if ai.repath_t <= 0.0 or ai.path.is_empty():
		ai.path = game.nav.find_path(global_position, goal)
		ai.path_i = 0
		ai.repath_t = 1.0
	if ai.path_i >= ai.path.size():
		return
	var p: Vector3 = ai.path[ai.path_i]
	var to := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
	if to.length() < 0.6:
		ai.path_i += 1
		return
	var dir := to.normalized()
	_turn_to(atan2(-dir.x, -dir.z), dt * level.turn * 0.8)
	pitch = lerpf(pitch, 0.0, minf(1.0, dt * 3.0))
	wish = global_basis.inverse() * dir
	wish.y = 0
	sprint = run and to.length() > 4.0 and reload_t <= 0.0
	if stance != "stand" and prone_lock <= 0.0:
		set_stance("stand")


func _unstick(dt: float) -> void:
	if wish.length() < 0.1:
		ai.stuck_t = 0.0
		ai.last_pos = global_position
		return
	if global_position.distance_to(ai.last_pos) < 0.3:
		ai.stuck_t += dt
		if ai.stuck_t > 0.8:
			jump_req = true # 넘기·점프
			ai.repath_t = 0.0
			ai.stuck_t = 0.0
	else:
		ai.stuck_t = 0.0
		ai.last_pos = global_position


func _turn_to(want_yaw: float, step: float) -> void:
	var diff := wrapf(want_yaw - rotation.y, -PI, PI)
	rotation.y += clampf(diff, -step, step)


func _combat(dt: float, dist: float) -> void:
	var t = target
	var eye := eye_position()
	var aim_point: Vector3 = t.eye_position() if ai.aim_head else t.global_position + Vector3(0, t.height() * 0.68, 0)
	var d := (aim_point - eye).normalized()
	ai.aim_t += dt
	var k := maxf(level.floor, 1.0 - level.comp * minf(1.0, ai.aim_t / 1.5))
	var want_yaw := atan2(-d.x, -d.z) + deg_to_rad(ai.err.x * k)
	var want_pitch := asin(clampf(d.y, -1.0, 1.0)) + deg_to_rad(ai.err.y * k)
	_turn_to(want_yaw, level.turn * dt)
	pitch = move_toward(pitch, want_pitch, level.turn * dt)
	var off := absf(wrapf(want_yaw - rotation.y, -PI, PI)) + absf(want_pitch - pitch)
	# 조준: 멀면 조준경
	var wp = w()
	ads = wp != null and dist > 12.0 and wp.stats.cat != "SG"
	if ai.pause_t > 0.0:
		ai.pause_t -= dt
	elif ai.see_t >= level.react and off < deg_to_rad(6.0) and wp != null:
		if ai.burst_left <= 0:
			ai.burst_left = randi_range(level.burst[0], level.burst[1]) if wp.fire_mode == "A" else randi_range(2, 4)
			var e: float = level.err
			ai.err = Vector2(randf_range(-e, e), randf_range(-e, e) * 0.6)
			ai.aim_head = randf() < level.head
		if wp.fire_mode == "A":
			trigger = true
			if since_shot > 0.3:
				trigger_edge = true
		elif cooldown <= 0.0 and bolt_t <= 0.0:
			trigger_edge = true
	if wp and wp.mag == 0:
		start_reload()
	# 싸우는 중 움직임: 좌우로, 가끔 앉기
	ai.strafe_t -= dt
	if ai.strafe_t <= 0.0:
		ai.strafe = -ai.strafe if randf() < 0.7 else ai.strafe
		ai.strafe_t = randf_range(0.5, 1.5)
	ai.crouch_t -= dt
	if ai.crouch_t <= 0.0:
		ai.crouch_t = randf_range(1.5, 4.0)
		var want := "crouch" if randf() < 0.3 else "stand"
		if dist > 60.0 and randf() < 0.2 and wp and wp.stats.cat in ["SR", "DMR"]:
			want = "prone"
		set_stance(want)
	var fwd := 0.0
	if dist > 45.0:
		fwd = -0.6
	elif dist < 8.0:
		fwd = 0.4
	wish = Vector3(ai.strafe * 0.55, 0, fwd)
	if stance == "prone":
		wish = Vector3.ZERO


func _throw_at(p: Vector3) -> void:
	equip_throw("frag")
	if mode != "throw":
		return
	var to := p - eye_position()
	var flat := Vector2(to.x, to.z).length()
	rotation.y = atan2(-to.x, -to.z)
	# 포물선 각도 (속도 19 + 위로 2.4)
	var best := 0.3
	var best_err := 1e9
	for i in 30:
		var a := -0.2 + i * 0.03
		var vx := 19.0 * cos(a)
		var vy := 19.0 * sin(a) + 2.4
		var tt := flat / maxf(vx, 0.1)
		var y := vy * tt - 0.5 * G.BULLET_G * tt * tt
		var err := absf(y - to.y)
		if err < best_err:
			best_err = err
			best = a
	pitch = best
	switch_t = 0.0
	pull_pin()
	release(false)
