extends CharacterBody3D
## 플레이어와 봇이 같이 쓰는 캐릭터 — 원본 Actor 클래스를 옮긴 것

signal died(actor, killer, info: Dictionary)
signal damaged(actor, amount: float, from, info: Dictionary)

const G = preload("res://scripts/game_data.gd")
const SoldierScript = preload("res://scripts/soldier.gd")

var display_name := ""
var net_id := "" # 온라인 id (h / c… / b1 …)
var game: Node = null
var is_player := false
var team := -1
var kills := 0
var deaths := 0
var heads := 0

var health: float = G.MAX_HP
var dead := false
var helmet_lv := 2
var vest_lv := 2
var helmet_dur := 0.0
var vest_dur := 0.0
var blind := 0.0
var meds := 1
var heal_t := 0.0
var heal_stance := ""

# 총
var weapons: Array = [] # [{id, att, stats, mag, reserve, fire_mode, zoom_sel}]
var cur := 0
var mode := "gun" # gun | throw | fist
var cooldown := 0.0
var switch_t := 0.0
var reload_t := 0.0
var reload_dur := 1.0
var shell_phase := ""
var bolt_t := 0.0
var burst := 0
var trigger := false
var trigger_edge := false
var ads := false
var ads_t := 0.0
var shoulder := false
var shoulder_t := 0.0
var shots := 0
var since_shot := 9.0
var recoil_acc := 0.0
var punch_cd := 0.0
# 던지기
var throwables := {}
var throw_type := "frag"
var pin := false
var cook_t := -1.0
var throw_anim_t := 0.0

# 자세·이동
var pitch := 0.0
var stance := "stand"
var stance_h: float = G.STANCE.stand.eye
var prone_lock := 0.0
var prone_dur := 1.0
var prone_from_h := 1.62
var lean := 0.0
var lean_target := 0.0
var sprint := false
var wish := Vector3.ZERO # 지역 좌표: x 오른쪽, z 뒤(+)
var jump_req := false
var _jump_buf := 0.0
var _air_t := 0.0
var vault = null
var _step_acc := 0.0

var soldier
var _col: CollisionShape3D
var _cap: CapsuleShape3D
var _prone_col: CollisionShape3D
var _muzzle_light: OmniLight3D


func setup(colors: Array) -> void:
	collision_layer = G.LAYER_ACTOR
	collision_mask = G.LAYER_WORLD | G.LAYER_ACTOR
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	_cap = CapsuleShape3D.new()
	_cap.radius = G.RADIUS
	_col = CollisionShape3D.new()
	_col.shape = _cap
	add_child(_col)
	_prone_col = CollisionShape3D.new()
	var pb := BoxShape3D.new()
	pb.size = Vector3(0.5, 0.45, 1.55)
	_prone_col.shape = pb
	_prone_col.position = Vector3(0, 0.25, -0.3)
	_prone_col.disabled = true
	add_child(_prone_col)
	soldier = Node3D.new()
	soldier.set_script(SoldierScript)
	add_child(soldier)
	soldier.build(colors[0], colors[1], colors[2])
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1, 0.8, 0.45)
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range = 5.0
	add_child(_muzzle_light)
	_apply_shape()


# ================= 총 지급 =================
func set_loadout(list: Array) -> void:
	weapons.clear()
	for it in list:
		var att: Dictionary = G.full_attachments(it.id, it)
		var st := G.weapon_stats(it.id, att)
		var modes: String = st.def.modes
		weapons.append({"id": it.id, "att": att, "stats": st, "mag": st.mag, "reserve": st.mag * 6, "fire_mode": "A" if "A" in modes else ("B" if "B" in modes else modes[0]), "zoom_sel": 0.0})
	equip(0, true)


func w():
	return weapons[cur] if mode == "gun" and cur < weapons.size() else null


func reset_for_round(pos: Vector3, yaw: float, armor_lv: int) -> void:
	global_position = pos
	rotation = Vector3(0, yaw, 0)
	velocity = Vector3.ZERO
	pitch = 0.0
	health = G.MAX_HP
	dead = false
	blind = 0.0
	vault = null
	meds = 1
	heal_t = 0.0
	helmet_lv = armor_lv
	vest_lv = armor_lv
	helmet_dur = G.HELMET_DUR[armor_lv]
	vest_dur = G.VEST_DUR[armor_lv]
	soldier.set_armor(helmet_lv, vest_lv)
	stance = "stand"
	stance_h = G.STANCE.stand.eye
	prone_lock = 0.0
	lean = 0.0
	lean_target = 0.0
	sprint = false
	cooldown = 0.0
	reload_t = 0.0
	shell_phase = ""
	bolt_t = 0.0
	switch_t = 0.0
	ads = false
	ads_t = 0.0
	shoulder = false
	shoulder_t = 0.0
	burst = 0
	shots = 0
	since_shot = 9.0
	recoil_acc = 0.0
	trigger = false
	trigger_edge = false
	pin = false
	cook_t = -1.0
	mode = "gun"
	throwables = {}
	for t in G.THROWABLES:
		throwables[t] = G.THROWABLES[t].count
	for wp in weapons:
		wp.mag = wp.stats.mag
		wp.reserve = maxi(wp.stats.mag * 6, 15)
	soldier.body.rotation = Vector3.ZERO
	soldier.body.position = Vector3.ZERO
	_col.disabled = false
	_apply_shape()
	equip(cur if cur < 2 else 0, true)


func equip(i: int, instant := false) -> void:
	if weapons.is_empty() or pin:
		return
	i = clampi(i, 0, weapons.size() - 1)
	if i == cur and mode == "gun" and not instant:
		return
	cur = i
	mode = "gun"
	reload_t = 0.0
	shell_phase = ""
	ads = false
	burst = 0
	bolt_t = 0.0
	cancel_heal()
	switch_t = 0.0 if instant else G.DRAW_TIME.get(weapons[cur].stats.cat, 0.6)
	soldier.set_gun(weapons[cur].id, weapons[cur].att)
	_on_equip()


func equip_throw(type := "") -> void:
	if pin or dead:
		return
	cancel_heal()
	if type == "":
		if mode == "throw":
			var k := G.THROW_ORDER.find(throw_type)
			for n in range(1, 4):
				var t: String = G.THROW_ORDER[(k + n) % 3]
				if throwables[t] > 0:
					type = t
					break
		else:
			type = throw_type if throwables.get(throw_type, 0) > 0 else ""
			if type == "":
				for t in G.THROW_ORDER:
					if throwables[t] > 0:
						type = t
						break
	if type == "" or throwables.get(type, 0) <= 0:
		return
	throw_type = type
	mode = "throw"
	ads = false
	reload_t = 0.0
	switch_t = 0.35
	soldier.set_gun("nade:" + type, {})
	_on_equip()


func holster() -> void:
	if pin or dead:
		return
	if mode == "fist":
		equip(cur, true)
		return
	mode = "fist"
	ads = false
	reload_t = 0.0
	burst = 0
	bolt_t = 0.0
	switch_t = 0.3
	punch_cd = 0.0
	soldier.set_gun("", {})
	_on_equip()


func _on_equip() -> void:
	pass # 플레이어: 1인칭 총 바꾸기


# ================= 자세 =================
func height() -> float:
	return G.STANCE[stance].h


func _apply_shape() -> void:
	var h := 1.8 if stance == "stand" else (1.25 if stance == "crouch" else 0.66)
	_cap.height = h
	_col.position.y = h / 2.0
	_prone_col.disabled = stance != "prone" or dead


func _can_stand(h: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.3, 0), global_position + Vector3(0, h + 0.05, 0), G.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func set_stance(s: String) -> void:
	if dead or vault != null or s == stance:
		return
	if not is_on_floor() and s != "stand":
		return
	if G.STANCE[s].h > G.STANCE[stance].h and not _can_stand(G.STANCE[s].h):
		return
	if prone_lock > 0.0:
		return
	if s == "prone" or stance == "prone":
		# 엎드리기 1초, 일어나기 0.85초 — 그동안 못 쏴요
		prone_dur = 1.0 if s == "prone" else 0.85
		prone_lock = prone_dur
		prone_from_h = stance_h
		ads = false
	stance = s
	_apply_shape()


# ================= 눈·조준 =================
func right_vec() -> Vector3:
	return global_basis.x


func fwd_vec() -> Vector3:
	return -global_basis.z


func eye_position() -> Vector3:
	var e := global_position + Vector3(0, stance_h, 0) + right_vec() * lean * (0.25 if stance == "prone" else 0.42)
	e.y -= absf(lean) * 0.06
	if stance == "prone":
		e += fwd_vec() * 0.55
	return e


func look_dir() -> Vector3:
	var yaw := rotation.y
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


## 총알이 나가는 곳과 방향 (플레이어는 카메라 기준으로 바꿔요)
func get_aim() -> Array:
	return [eye_position(), look_dir()]


func can_shoot() -> bool:
	return not dead and vault == null and heal_t <= 0.0 and switch_t <= 0.0 and reload_t <= 0.0 and bolt_t <= 0.0 \
		and not (sprint and Vector2(velocity.x, velocity.z).length() > 3.0) and prone_lock <= 0.0


# ================= 이동 =================
func physics_step(dt: float) -> void:
	var st: Dictionary = G.STANCE[stance]
	if prone_lock > 0.0:
		var q := clampf(1.0 - (prone_lock - dt) / prone_dur, 0.0, 1.0)
		stance_h = lerpf(prone_from_h, st.eye, q * q * (3.0 - 2.0 * q))
		ads = false
	else:
		stance_h = lerpf(stance_h, st.eye, minf(1.0, dt * (6.0 if stance == "prone" else 12.0)))
	lean = lerpf(lean, lean_target * (0.5 if stance == "prone" else 1.0), minf(1.0, dt * 12.0))
	if vault != null:
		_update_vault(dt)
		_after_move(dt)
		return
	var sp: float = st.sprint if sprint else st.speed
	var wp = w()
	if wp:
		sp *= G.CAT_INFO[wp.stats.cat].move
	elif mode == "fist":
		sp *= 1.13 if sprint else 1.06
	if ads and not sprint:
		sp *= 0.0 if stance == "prone" else 0.6
	elif shoulder_t > 0.5:
		sp *= 0.8
	if prone_lock > 0.0:
		sp *= 0.12
	if heal_t > 0.0:
		sp *= 0.42
	if reload_t > 0.0 and stance == "prone":
		sp = 0.0
	var tx := 0.0
	var tz := 0.0
	var wl := Vector2(wish.x, wish.z).length()
	if wl > 0.01 and not dead:
		var lx := wish.x / wl
		var lz := wish.z / wl
		var dir_mul := 0.8 if lz > 0.2 else (0.9 if absf(lx) > 0.7 else 1.0)
		var v := global_basis * Vector3(lx, 0, lz)
		tx = v.x * sp * dir_mul * minf(1.0, wl)
		tz = v.z * sp * dir_mul * minf(1.0, wl)
	var k := 11.0 if is_on_floor() else 1.5
	velocity.x = lerpf(velocity.x, tx, minf(1.0, k * dt))
	velocity.z = lerpf(velocity.z, tz, minf(1.0, k * dt))
	if dead:
		velocity.x = lerpf(velocity.x, 0.0, minf(1.0, dt * 5.0))
		velocity.z = lerpf(velocity.z, 0.0, minf(1.0, dt * 5.0))
	# 점프 / 넘기 (0.15초 기억, 땅에서 떨어진 0.12초 안에도 허용)
	if jump_req:
		_jump_buf = 0.15
		jump_req = false
	_jump_buf -= dt
	_air_t = 0.0 if is_on_floor() else _air_t + dt
	if _jump_buf > 0.0 and not dead and (is_on_floor() or (_air_t < 0.12 and velocity.y <= 0.5)):
		_jump_buf = 0.0
		if not _try_vault():
			if stance == "prone":
				set_stance("crouch")
			elif stance == "crouch":
				set_stance("stand")
			else:
				velocity.y = G.JUMP_V
				ads = false
		if vault != null:
			_after_move(dt)
			return
	if not is_on_floor() or velocity.y > 0.0:
		velocity.y -= G.GRAVITY * dt
	var was_floor := is_on_floor()
	var hv := Vector3(velocity.x, 0, velocity.z)
	var vy_before := velocity.y
	move_and_slide()
	if was_floor and hv.length() > 0.5 and is_on_wall():
		_try_step(hv * dt)
	if not was_floor and is_on_floor() and vy_before < -6.0:
		_on_land(-vy_before)
	_after_move(dt)


## 계단·턱 오르기 (STEP 높이까지)
func _try_step(motion: Vector3) -> void:
	var t := global_transform
	var up := Vector3(0, G.STEP if stance != "prone" else 0.12, 0)
	if test_move(t, up):
		return
	var t2 := t.translated(up)
	var m := motion.normalized() * maxf(motion.length(), 0.1)
	if test_move(t2, m):
		return
	t2 = t2.translated(m)
	var col := KinematicCollision3D.new()
	if test_move(t2, -up * 1.2, col):
		t2 = t2.translated(col.get_travel())
		if t2.origin.y - t.origin.y > 0.02 and col.get_normal().y > 0.7:
			global_transform = t2
			velocity.y = 0.0


func _on_land(_speed: float) -> void:
	pass


## 파쿠르: 앞의 장애물을 넘거나 올라가기
func _try_vault() -> bool:
	if stance == "prone" or game == null:
		return false
	var world = game.world
	var f := fwd_vec()
	f.y = 0
	f = f.normalized()
	var p := global_position
	for d in [0.0, 0.35, 0.65, 0.95]:
		var x: float = p.x + f.x * d
		var z: float = p.z + f.z * d
		for b in world.boxes:
			if b.kind == "stair" and x + 0.25 > b.min.x and x - 0.25 < b.max.x and z + 0.25 > b.min.z and z - 0.25 < b.max.z and b.max.y > p.y - 0.05 and b.min.y < p.y + 2.8:
				return false
	var top := -1.0
	var hit_d := 0.0
	for d in [0.45, 0.65, 0.85]:
		var t: float = world.ground_at(p.x + f.x * d, p.z + f.z * d, 0.12, p.y, 2.75)
		if t - p.y > 0.4 and t > top:
			top = t
			hit_d = d
	var rise := top - p.y
	if top < 0.0 or rise < 0.4 or rise > 2.75:
		return false
	var o := Vector3(p.x + f.x * (hit_d + 0.15), top + 0.05, p.z + f.z * (hit_d + 0.15))
	if world.point_blocked(o, 0.2, top + 0.01, top + 0.95):
		return false
	if world.point_blocked(Vector3(p.x, 0, p.z), 0.25, p.y + height() - 0.1, top + 0.9):
		return false
	var far := -1.0
	var on_top := false
	var d2 := hit_d - 0.3
	while d2 < hit_d + 1.9:
		var t2: float = world.ground_at(p.x + f.x * d2, p.z + f.z * d2, 0.03, top + 0.02, 0.05)
		if t2 >= top - 0.05:
			on_top = true
		elif on_top and t2 < top - 0.3:
			far = d2
			break
		d2 += 0.06
	var to: Vector3
	var over := false
	if far > 0.0 and rise < 1.3:
		var land := far + G.RADIUS + 0.15
		to = Vector3(p.x + f.x * land, top, p.z + f.z * land)
		if not world.point_blocked(to, G.RADIUS, top + 0.1, top + 1.5):
			over = true
	if not over:
		var dd := minf(hit_d + 0.45, far - 0.1 if far > 0.0 else hit_d + 0.45)
		to = Vector3(p.x + f.x * dd, top, p.z + f.z * dd)
	var dur := (0.55 if rise < 1.1 else 0.75) if over else (0.6 if rise < 1.2 else (0.95 if rise < 2.0 else 1.25))
	vault = {"t": 0.0, "dur": dur, "from": p, "to": to, "top": top, "over": over}
	velocity = Vector3.ZERO
	ads = false
	reload_t = 0.0
	stance = "stand"
	_apply_shape()
	_col.disabled = true
	return true


func _update_vault(dt: float) -> void:
	var v: Dictionary = vault
	v.t += dt / v.dur
	var t := minf(1.0, v.t)
	var up := minf(1.0, t / 0.55)
	var e := 1.0 - pow(1.0 - up, 2.0)
	var hz := t / 0.55 * 0.45 if t < 0.55 else 0.45 + (t - 0.55) / 0.45 * 0.55
	global_position = Vector3(lerpf(v.from.x, v.to.x, hz), lerpf(v.from.y, v.top + 0.12, e), lerpf(v.from.z, v.to.z, hz))
	if t >= 1.0:
		vault = null
		_col.disabled = false
		velocity = Vector3.ZERO
		if v.over:
			velocity = Vector3((v.to.x - v.from.x) * 1.2, 0, (v.to.z - v.from.z) * 1.2)
		else:
			global_position.y = v.top


func _after_move(dt: float) -> void:
	_update_heal(dt)
	if prone_lock > 0.0:
		prone_lock = maxf(0.0, prone_lock - dt)
	throw_anim_t = maxf(0.0, throw_anim_t - dt)
	_muzzle_light.light_energy = maxf(0.0, _muzzle_light.light_energy - dt * 60.0)
	var hsp := Vector2(velocity.x, velocity.z).length()
	# 기울이기는 옆에 벽이 있으면 그만큼만
	if absf(lean) > 0.01:
		var lk := 0.25 if stance == "prone" else 0.42
		var sg := signf(lean)
		var c := global_position + Vector3(0, stance_h, 0)
		var q := PhysicsRayQueryParameters3D.create(c, c + right_vec() * sg * (absf(lean) * lk + 0.25), G.LAYER_WORLD)
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty():
			var mx := maxf(0.0, c.distance_to(r.position) - 0.25) / lk
			if absf(lean) > mx:
				lean = sg * mx
	var pr := 0.0
	if stance == "prone":
		pr = 1.0 - (prone_lock / prone_dur if prone_lock > 0.0 else 0.0)
	elif prone_lock > 0.0:
		pr = prone_lock / prone_dur
	soldier.animate({"speed": hsp, "stance": stance, "sprint": sprint and hsp > 3.0, "lean": lean, "pitch": pitch, "dead": dead, "prone_t": pr, "heal": heal_t > 0.0}, dt)
	# 발소리
	if is_on_floor() and hsp > 1.0 and not dead:
		_step_acc += hsp * dt
		if _step_acc > (1.0 if stance == "prone" else 1.6):
			_step_acc = 0.0
			Sfx.step(global_position, is_player, stance != "stand" or hsp < 3.0)
			_on_step(stance != "stand" or hsp < 3.0)


func _on_step(_soft: bool) -> void:
	pass


# ================= 구급상자 =================
func start_heal() -> bool:
	if dead or vault != null or meds <= 0 or heal_t > 0.0 or health >= G.MAX_HP - 0.5 or pin or prone_lock > 0.0:
		return false
	heal_t = 6.0
	heal_stance = stance
	ads = false
	reload_t = 0.0
	sprint = false
	if is_player:
		Sfx.click(0.2, 600)
	return true


func cancel_heal() -> void:
	if heal_t > 0.0:
		heal_t = 0.0
		if is_player and game:
			game.hud.toast("치료가 끊겼어요")


func _update_heal(dt: float) -> void:
	if heal_t <= 0.0:
		return
	if dead or sprint or not is_on_floor() or vault != null or prone_lock > 0.0 or stance != heal_stance or trigger:
		cancel_heal()
		return
	heal_t -= dt
	if heal_t <= 0.0:
		heal_t = 0.0
		meds -= 1
		health = minf(G.MAX_HP, health + 75.0)
		if is_player and game:
			Sfx.beep(660, 0.12, 0.2)
			game.hud.toast("체력 +75")


# ================= 총 쏘기 =================
func _next_shell(wp: Dictionary) -> void:
	var t: float = G.PER_SHELL.get(wp.id, 0.0) * (0.75 if wp.att.get("stock") == "loops" else 1.0)
	if shell_phase == "shell":
		if wp.mag < wp.stats.mag and wp.reserve > 0:
			wp.mag += 1
			wp.reserve -= 1
		if is_player:
			Sfx.click(0.35, 1300)
	if (shell_phase == "start" or shell_phase == "shell") and wp.mag < wp.stats.mag and wp.reserve > 0:
		shell_phase = "shell"
		reload_dur = t
		reload_t = t
		return
	if shell_phase != "end":
		shell_phase = "end"
		reload_dur = 0.45
		reload_t = 0.45
		if is_player:
			Sfx.bolt()
		return
	shell_phase = ""
	reload_t = 0.0


func start_reload() -> void:
	var wp = w()
	if wp == null or reload_t > 0.0 or wp.mag >= wp.stats.mag or wp.reserve <= 0 or dead or vault != null:
		return
	burst = 0
	if G.PER_SHELL.has(wp.id):
		shell_phase = "start"
		reload_dur = 0.4
		reload_t = 0.4
		if is_player:
			Sfx.click(0.25, 1100)
		return
	shell_phase = ""
	reload_dur = wp.stats.reload * (1.15 if wp.mag == 0 else 1.0)
	reload_t = reload_dur
	if is_player:
		Sfx.reload(reload_dur)


func cycle_fire_mode() -> void:
	var wp = w()
	if wp == null:
		return
	var m: String = wp.stats.def.modes
	wp.fire_mode = m[(m.find(wp.fire_mode) + 1) % m.length()]
	if is_player:
		Sfx.click(0.2, 1800)


func update_weapon(dt: float) -> void:
	cooldown -= dt
	switch_t = maxf(0.0, switch_t - dt)
	since_shot += dt
	blind = maxf(0.0, blind - dt)
	var wp = w()
	if bolt_t > 0.0:
		bolt_t -= dt
	if reload_t > 0.0:
		reload_t -= dt
		ads = false
		if reload_t <= 0.0 and shell_phase != "":
			_next_shell(wp)
		elif reload_t <= 0.0 and wp:
			var take := mini(wp.stats.mag - wp.mag, wp.reserve)
			wp.mag += take
			wp.reserve -= take
			reload_t = 0.0
	var ads_time: float = wp.stats.adsTime if wp else 0.2
	var bolting: bool = wp != null and wp.stats.def.bolt and bolt_t > 0.0 and bolt_t < wp.stats.def.interval - 0.12
	var want_ads: bool = ads and mode == "gun" and reload_t <= 0.0 and vault == null and switch_t <= 0.0 and not bolting
	ads_t = clampf(ads_t + (dt / ads_time if want_ads else -dt / (ads_time * 0.8)), 0.0, 1.0)
	var want_sh: bool = shoulder and not ads and mode == "gun" and vault == null and not sprint
	shoulder_t = clampf(shoulder_t + (dt / 0.12 if want_sh else -dt / 0.12), 0.0, 1.0)
	# 반동 회복
	if since_shot > 0.14 and recoil_acc > 0.0:
		var rec := minf(recoil_acc, dt * 3.5 * (wp.stats.recovery if wp else 1.0) * maxf(0.4, recoil_acc))
		recoil_acc -= rec
		if since_shot < 1.2:
			pitch -= rec * 0.18
	if since_shot > 0.25:
		shots = 0
	if mode == "throw":
		_update_throw(dt)
		return
	if mode == "fist":
		punch_cd = maxf(0.0, punch_cd - dt)
		if (trigger_edge or trigger) and punch_cd <= 0.0 and switch_t <= 0.0 and vault == null and not dead:
			_punch()
		trigger_edge = false
		return
	if wp == null:
		return
	var fm: String = wp.fire_mode
	if trigger_edge and shell_phase != "" and reload_t > 0.0 and wp.mag > 0 and shell_phase != "end":
		shell_phase = "end"
		reload_dur = 0.3
		reload_t = 0.3
		if is_player:
			Sfx.bolt()
	if trigger_edge:
		trigger_edge = false
		if wp.mag <= 0:
			if is_player:
				Sfx.empty()
			start_reload()
		elif fm == "B":
			burst = 3
		elif fm == "S" or fm == "A":
			burst = 1
	var want := burst > 0 or (fm == "A" and trigger)
	if want and cooldown <= 0.0 and can_shoot():
		if wp.mag > 0:
			_fire(wp)
			if burst > 0:
				burst -= 1
				if fm == "B" and burst == 0:
					cooldown = maxf(cooldown, 0.22)
		else:
			burst = 0
			if is_player:
				Sfx.empty()
			start_reload()


func _fire(wp: Dictionary) -> void:
	var st: Dictionary = wp.stats
	var def: Dictionary = st.def
	wp.mag -= 1
	since_shot = 0.0
	shots += 1
	cooldown = 0.05 if def.bolt else (def.interval * 0.75 if wp.fire_mode == "B" else def.interval)
	if def.bolt or def.id in ["win94", "s1897", "dbs"]:
		bolt_t = def.interval
		if is_player:
			get_tree().create_timer(0.05).timeout.connect(Sfx.bolt)
	if def.cat == "SG" and not (def.id in ["s1897", "dbs"]):
		cooldown = def.interval
	var aim := get_aim()
	var origin: Vector3 = aim[0]
	var dir: Vector3 = aim[1]
	var moving := Vector2(velocity.x, velocity.z).length()
	var sst: Dictionary = G.STANCE[stance]
	var hip_eff: float = st.hip * lerpf(1.0, 0.42, shoulder_t)
	var spread: float = lerpf(hip_eff, st.ads, ads_t) * sst.spread
	spread += (moving / 6.0) * lerpf(2.0, 0.6, ads_t) * (2.0 if def.cat == "SR" else 1.0)
	if not is_on_floor():
		spread += 4.0
	if def.cat == "SR" and ads_t < 0.99:
		spread += 3.0
	var right := Vector3.UP.cross(dir).normalized()
	var up := dir.cross(right).normalized()
	for p in def.pellets:
		var sp: float = lerpf(st.hip * lerpf(1.0, 0.75, shoulder_t), st.ads, ads_t) if def.cat == "SG" else spread
		var a := randf() * TAU
		var r := sqrt(randf()) * tan(deg_to_rad(sp))
		var d: Vector3 = (dir + right * cos(a) * r * st.spreadH + up * sin(a) * r * st.spreadV).normalized()
		game.combat.spawn_bullet(self, origin, d, st, def.dmg)
	# 반동
	var ramp := 0.8 + minf(shots, 14) * 0.075
	var zm: float = effective_zoom() if ads_t > 0.5 else 1.0
	var hi_z := 1.0 + (zm - 2.0) * 0.15 + 0.15 if zm >= 3.0 and shots >= 2 and not def.bolt else 1.0
	var vk: float = st.rv * 1.35 * sst.recoil * (1.0 if ads_t > 0.5 else 1.25) * ramp * hi_z * randf_range(0.85, 1.15)
	var drift := float(def.id.unicode_at(0) % 3 - 1) * 0.25
	var hk: float = st.rh * 1.3 * sst.recoil * sqrt(hi_z) * (randf_range(-1, 1) + drift) * (0.6 if shots < 3 else 1.0)
	apply_recoil(deg_to_rad(vk), deg_to_rad(hk))
	# 소리 + 불꽃
	var mz := muzzle_world()
	Sfx.shot(mz, def.cat, st.suppressed, is_player)
	if not st.flashHidden and def.cat != "XB":
		_muzzle_light.global_position = mz
		_muzzle_light.light_energy = 2.5
	_on_fire(st)
	if game:
		for a in game.actors():
			if a != self and a.has_method("hear_shot"):
				a.hear_shot(self, st.suppressed)
	if def.cat == "XB" and wp.mag <= 0:
		cooldown = 0.35
		get_tree().create_timer(0.35).timeout.connect(func(): if w() == wp and wp.mag <= 0: start_reload())


func apply_recoil(v: float, h: float) -> void:
	pitch += v
	rotate_y(-h)
	recoil_acc += v


func _on_fire(_st: Dictionary) -> void:
	pass


func muzzle_world() -> Vector3:
	if soldier.muzzle and soldier.visible:
		return soldier.muzzle.global_position
	return eye_position() + look_dir() * 0.6


func effective_zoom() -> float:
	var wp = w()
	if wp == null:
		return 1.0
	if wp.zoom_sel > 0.0 and wp.stats.scopeZoom >= 3.0:
		return wp.zoom_sel
	return wp.stats.scopeZoom


# ================= 맨손 =================
func _punch() -> void:
	punch_cd = 0.55
	var aim := get_aim()
	var o: Vector3 = aim[0]
	var d: Vector3 = aim[1]
	var excl: Array[RID] = [get_rid()]
	var q := PhysicsRayQueryParameters3D.create(o, o + d * 1.7, G.LAYER_WORLD | G.LAYER_ACTOR, excl)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var ok := false
	if not hit.is_empty() and hit.collider.has_method("hit_part") and not hit.collider.dead and not game.same_team(self, hit.collider):
		game.combat.punch(self, hit.collider, hit.collider.hit_part(hit.position), hit.position, d)
		ok = true
	if is_player:
		Sfx.punch(ok)


# ================= 던지기 =================
func _update_throw(dt: float) -> void:
	if cook_t >= 0.0:
		cook_t += dt
		if cook_t >= G.THROWABLES[throw_type].fuse:
			throwables[throw_type] -= 1
			pin = false
			cook_t = -1.0
			game.combat.explode(throw_type, eye_position(), self)
			if game.mp:
				game.mpx.send_boom(self, throw_type, eye_position())
			_after_throw()


func pull_pin() -> void:
	if mode != "throw" or pin or switch_t > 0.0 or throwables.get(throw_type, 0) <= 0 or dead:
		return
	pin = true
	cook_t = -1.0
	if is_player:
		Sfx.pin()


func cook() -> void:
	if pin and cook_t < 0.0:
		cook_t = 0.0
		if is_player:
			Sfx.click(0.2, 2600)


func throw_velocity(under: bool) -> Vector3:
	var v := look_dir() * (9.0 if under else 19.0)
	v.y += 1.0 if under else 2.4
	v.x += velocity.x * 0.5
	v.z += velocity.z * 0.5
	return v


func throw_origin() -> Vector3:
	return eye_position() + right_vec() * 0.18 + Vector3(0, 0.05, 0)


func release(under: bool) -> void:
	if not pin:
		return
	var fuse: float = G.THROWABLES[throw_type].fuse - maxf(0.0, cook_t)
	game.combat.throw_grenade(self, throw_type, throw_origin(), throw_velocity(under), maxf(0.05, fuse))
	throwables[throw_type] -= 1
	pin = false
	cook_t = -1.0
	if is_player:
		Sfx.spoon()
	throw_anim_t = 0.5
	_after_throw()


func _after_throw() -> void:
	if throwables[throw_type] > 0:
		switch_t = 0.6
		soldier.set_gun("nade:" + throw_type, {})
	else:
		var other := ""
		for t in G.THROW_ORDER:
			if throwables[t] > 0:
				other = t
				break
		if other != "" and is_player:
			equip_throw(other)
		else:
			equip(cur, true)
		switch_t = 0.6
	_on_equip()


# ================= 피해 =================
## 맞은 부위: head / torso / leg
func hit_part(p: Vector3) -> String:
	var l := global_transform.affine_inverse() * p
	if stance == "prone" and prone_lock <= 0.0:
		var f := -l.z
		if f > 0.5:
			return "head"
		if f < -0.3:
			return "leg"
		return "torso"
	var h := stance_h + 0.18
	if l.y >= h - 0.3:
		return "head"
	if l.y < h * 0.45:
		return "leg"
	return "torso"


func break_armor(kind: String) -> void:
	if kind == "helmet":
		helmet_lv = 0
		helmet_dur = 0.0
	else:
		vest_lv = 0
		vest_dur = 0.0
	soldier.set_armor(helmet_lv, vest_lv)


func take_damage(dmg: float, from, info: Dictionary) -> void:
	if dead or game == null or not game.damage_allowed():
		return
	health -= dmg
	damaged.emit(self, dmg, from, info)
	if health <= 0.0:
		health = 0.0
		_die(from, info)


func _die(from, info: Dictionary) -> void:
	deaths += 1
	if from and from != self:
		from.kills += 1
		if info.get("head", false):
			from.heads += 1
	dead = true
	ads = false
	pin = false
	trigger = false
	vault = null
	heal_t = 0.0
	_col.disabled = true
	_prone_col.disabled = true
	died.emit(self, from, info)
