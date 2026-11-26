extends "res://scripts/actor.gd"
## 플레이어: 키 설정대로 조작, 1인칭·3인칭, 조준경, 숨 참기, 둘러보기, 1인칭 총

const Guns = preload("res://scripts/guns.gd")

var camera: Camera3D
var third := false
var free_yaw := 0.0 # 둘러보기
var free_pitch := 0.0
var _free := false
var breath := 1.0 # 숨 참기 (0~1)
var holding_breath := false
var _sway_t := 0.0
var sway := Vector2.ZERO

var _vm: Node3D # 1인칭 총 받침
var _vm_gun: Node3D
var _vm_muzzle: Node3D
var _vm_sight_y := 0.07
var _vm_flash: OmniLight3D
var _kick := 0.0
var _bob := 0.0
var _rmb_down_t := -1.0
var _rmb := false
var _lmb := false
var _crouch_toggle_hold := false
var auto_target = null # 자동 테스트 전용


func _ready() -> void:
	is_player = true
	setup([Color(0.24, 0.42, 0.62), Color(0.25, 0.28, 0.3), Color(0.86, 0.7, 0.58)])
	_vm = Node3D.new()
	_vm.scale = Vector3.ONE * 0.55
	_vm_flash = OmniLight3D.new()
	_vm_flash.light_color = Color(1, 0.8, 0.45)
	_vm_flash.light_energy = 0.0
	_vm_flash.omni_range = 4.0


func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.add_child(_vm)
	_vm.add_child(_vm_flash)


func _on_equip() -> void:
	if _vm_gun:
		_vm_gun.queue_free()
		_vm_gun = null
		_vm_muzzle = null
	var wp = w()
	if mode == "gun" and wp:
		var g := Guns.build(wp.id, wp.att)
		_vm_gun = g.node
		_vm_muzzle = g.muzzle
		_vm_sight_y = g.sight_y
	elif mode == "throw":
		_vm_gun = Guns.grenade_model(throw_type)
		_vm_sight_y = 0.0
	else:
		_vm_gun = Node3D.new()
		for s in [-1, 1]:
			var f := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.09, 0.09, 0.12)
			f.mesh = b
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.86, 0.7, 0.58)
			f.material_override = m
			f.position = Vector3(s * 0.16, 0, 0)
			_vm_gun.add_child(f)
	_vm.add_child(_vm_gun)
	if game and game.hud:
		game.hud.refresh_slots()


func get_aim() -> Array:
	if camera == null:
		return super.get_aim()
	var dir := look_dir()
	dir = (dir.rotated(Vector3.UP, sway.x)).rotated(right_vec(), sway.y).normalized()
	if not third or ads_t > 0.5:
		return [eye_position(), dir]
	# 3인칭: 화면 가운데가 가리키는 곳으로 눈에서 쏴요
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 400.0, G.LAYER_WORLD | G.LAYER_ACTOR, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var target: Vector3 = hit.position if not hit.is_empty() else from + dir * 400.0
	var e := eye_position()
	return [e, (target - e).normalized()]


func muzzle_world() -> Vector3:
	if not third and _vm_muzzle:
		return _vm_muzzle.global_position
	return super.muzzle_world()


func _on_fire(st: Dictionary) -> void:
	_kick = 0.05 if st.cat in ["SR", "SG"] else 0.025
	if not st.flashHidden and st.cat != "XB" and _vm_muzzle and not third:
		_vm_flash.global_position = _vm_muzzle.global_position
		_vm_flash.light_energy = 3.0
	if game:
		game.shake = maxf(game.shake, 0.05 * st.shake)
		game.on_player_fire()


func _scoped() -> bool:
	var wp = w()
	return wp != null and ads_t > 0.6 and effective_zoom() >= 3.0


# ================= 입력 =================
func _unhandled_input(e: InputEvent) -> void:
	if game == null or not game.can_look():
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var zm := effective_zoom() if ads_t > 0.5 else 1.0
		var s: float = 0.0022 * Settings.sens * (Settings.ads_sens / maxf(1.0, zm * 0.8) if ads_t > 0.5 else 1.0)
		if _free:
			free_yaw = clampf(free_yaw - e.relative.x * s, -2.2, 2.2)
			free_pitch = clampf(free_pitch - e.relative.y * s, -1.2, 1.2)
		else:
			rotate_y(-e.relative.x * s)
			pitch = clampf(pitch - e.relative.y * s, deg_to_rad(-88), deg_to_rad(88))
		return
	if e is InputEventMouseButton:
		_mouse_button(e)
		return
	if e is InputEventKey and not e.echo:
		var act: String = Settings.action_of(e)
		if act == "":
			return
		if e.pressed:
			_key_down(act)
		else:
			_key_up(act)


func _mouse_button(e: InputEventMouseButton) -> void:
	var live: bool = game.is_live() or game.state == "pre" or game.state == "range"
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			_lmb = e.pressed
			if e.pressed:
				if mode == "throw":
					pull_pin()
				else:
					trigger_edge = true
			elif mode == "throw" and pin:
				release(_rmb)
		MOUSE_BUTTON_RIGHT:
			_rmb = e.pressed
			if mode != "gun":
				return
			match Settings.aim_mode:
				"hold":
					ads = e.pressed
				"toggle":
					if e.pressed:
						ads = not ads
				_:
					# 배그식: 짧게 누르면 조준 켜기/끄기, 길게 누르면 누르는 동안 견착
					if e.pressed:
						_rmb_down_t = 0.0
						if ads:
							ads = false
							_rmb_down_t = -1.0
					else:
						if _rmb_down_t >= 0.0 and _rmb_down_t < 0.22:
							ads = true
						_rmb_down_t = -1.0
						shoulder = false
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not e.pressed or not live:
				return
			var dirw := -1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			var wp = w()
			if wp and ads_t > 0.5 and wp.stats.scopeZoom >= 3.0:
				# 조준경 배율 조절 (원래 배율의 절반 ~ 원래 배율)
				var mx: float = wp.stats.scopeZoom
				var cz: float = wp.zoom_sel if wp.zoom_sel > 0.0 else mx
				wp.zoom_sel = clampf(cz - dirw * mx * 0.125, mx * 0.5, mx)
			else:
				equip(clampi(cur + dirw, 0, weapons.size() - 1))


func _key_down(act: String) -> void:
	match act:
		"reload":
			if mode == "throw":
				cook()
			else:
				start_reload()
		"firemode":
			cycle_fire_mode()
		"slot1":
			equip(0)
		"slot2":
			equip(1)
		"slot3":
			equip(2)
		"throw":
			equip_throw()
		"throw_next":
			equip_throw("" if mode == "throw" else throw_type)
		"heal":
			start_heal()
		"fist":
			holster()
		"view":
			third = not third
		"crouch":
			if Settings.crouch_mode == "toggle":
				set_stance("stand" if stance == "crouch" else "crouch")
			else:
				set_stance("crouch")
		"prone":
			set_stance("stand" if stance == "prone" else "prone")
		"jump":
			jump_req = true
		"lean_l":
			lean_target = 0.0 if (Settings.lean_mode == "toggle" and lean_target < 0) else -1.0
		"lean_r":
			lean_target = 0.0 if (Settings.lean_mode == "toggle" and lean_target > 0) else 1.0
		"freelook":
			_free = true
		"sprint":
			if Settings.sprint_mode == "toggle":
				sprint = not sprint
		"score":
			game.hud.show_board(true)
		"loadout":
			game.toggle_loadout()


func _key_up(act: String) -> void:
	match act:
		"crouch":
			if Settings.crouch_mode == "hold" and stance == "crouch":
				set_stance("stand")
		"lean_l":
			if Settings.lean_mode == "hold" and lean_target < 0:
				lean_target = 0.0
		"lean_r":
			if Settings.lean_mode == "hold" and lean_target > 0:
				lean_target = 0.0
		"freelook":
			_free = false
		"score":
			game.hud.show_board(false)


# ================= 매 프레임 =================
func _physics_process(dt: float) -> void:
	if game == null:
		return
	var live: bool = game.is_live() or game.state == "range"
	var can_move: bool = live or game.state == "pre"
	# 이동 입력
	wish = Vector3.ZERO
	if can_move and not dead:
		wish.x = float(Settings.is_down("right")) - float(Settings.is_down("left"))
		wish.z = float(Settings.is_down("back")) - float(Settings.is_down("forward"))
		if Settings.sprint_mode == "hold":
			sprint = Settings.is_down("sprint") and wish.z < 0.0 and not (ads and ads_t > 0.3) and reload_t <= 0.0 and heal_t <= 0.0
		elif wish.z >= 0.0 or ads:
			sprint = false
		if sprint and stance != "stand" and prone_lock <= 0.0:
			set_stance("stand")
	else:
		sprint = false
	if _rmb_down_t >= 0.0:
		_rmb_down_t += dt
		if _rmb_down_t >= 0.22 and mode == "gun":
			shoulder = true
	# 숨 참기 (조준 중 Shift)
	holding_breath = ads_t > 0.6 and Settings.is_down("sprint") and breath > 0.0
	breath = clampf(breath + (-dt / 5.0 if holding_breath else dt / 4.0), 0.0, 1.0)
	# 사격
	trigger = _lmb and live and mode == "gun"
	if auto_target != null and live:
		trigger = _auto_aim(auto_target)
		if trigger and since_shot > 0.3:
			trigger_edge = true
	if not live:
		trigger_edge = false
		trigger = false
	update_weapon(dt)
	physics_step(dt)
	_update_sway(dt)


func _update_sway(dt: float) -> void:
	var wp = w()
	_sway_t += dt
	var amp := 0.0
	if wp and ads_t > 0.5:
		var zm := effective_zoom()
		amp = deg_to_rad(0.06 + 0.035 * zm) * wp.stats.sway * (0.15 if holding_breath else 1.0) * (0.5 if stance == "prone" else (0.75 if stance == "crouch" else 1.0))
	elif wp:
		amp = deg_to_rad(0.15)
	sway = Vector2(sin(_sway_t * 0.9) * amp, sin(_sway_t * 1.7 + 1.0) * amp * 0.6)


## 화면 (카메라·1인칭 총) — main 이 매 프레임 불러요
func update_view(dt: float, shake: float) -> void:
	if camera == null:
		return
	if not _free:
		free_yaw = lerpf(free_yaw, 0.0, minf(1.0, dt * 10.0))
		free_pitch = lerpf(free_pitch, 0.0, minf(1.0, dt * 10.0))
	var use_third := third and ads_t < 0.5 and not dead
	soldier.visible = use_third or dead
	var yaw := rotation.y + free_yaw
	var p := pitch + free_pitch
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.02
	var basis := Basis.from_euler(Vector3(p + sway.y, yaw + sway.x, -lean * 0.12))
	var eye := eye_position()
	if dead:
		eye = global_position + Vector3(0, 0.4, 0) - basis.z * 2.5 + Vector3(0, 1.2, 0)
		var spec = game.spectate_target()
		if spec != null:
			# 관전: 살아 있는 팀원(개인전은 아무나) 뒤에서 봐요
			eye = spec.eye_position()
			use_third = true
	if use_third:
		var back := basis * Vector3(0.55, 0.25, 2.4)
		var q := PhysicsRayQueryParameters3D.create(eye, eye + back, G.LAYER_WORLD)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var pos := eye + back
		if not hit.is_empty():
			pos = hit.position - back.normalized() * 0.2
		camera.global_transform = Transform3D(basis, pos + sh)
	else:
		camera.global_transform = Transform3D(basis, eye + sh)
	# 배율
	var base: float = Settings.fov
	var zm := 1.0 + (effective_zoom() - 1.0) * ads_t if mode == "gun" else 1.0
	if shoulder_t > 0.0 and ads_t < 0.5:
		zm = maxf(zm, lerpf(1.0, 1.15, shoulder_t))
	camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(base) / 2.0) / zm))
	# 1인칭 총
	_vm.visible = not use_third and not dead and not (w() != null and ads_t > 0.6 and effective_zoom() >= 2.0)
	_kick = move_toward(_kick, 0.0, dt * 0.35)
	_vm_flash.light_energy = maxf(0.0, _vm_flash.light_energy - dt * 60.0)
	var hsp := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hsp > 0.5:
		_bob += dt * hsp * 1.6
	var bob := Vector3(sin(_bob) * 0.006, -absf(cos(_bob)) * 0.006, 0) * (1.0 - ads_t) * minf(1.0, hsp / 4.0)
	var hip := Vector3(0.14, -0.15, -0.3)
	var aim_pos := Vector3(0.0, -_vm_sight_y * 0.55, -0.36)
	var pos2 := hip.lerp(aim_pos, ads_t) + bob + Vector3(0, 0, _kick)
	var rot := Vector3.ZERO
	if sprint and hsp > 3.0:
		rot = Vector3(-0.35, 0.6, 0.2)
		pos2 += Vector3(-0.04, -0.05, 0.04)
	if reload_t > 0.0:
		var k := sin(clampf(1.0 - reload_t / maxf(reload_dur, 0.01), 0.0, 1.0) * PI)
		rot += Vector3(-0.5 * k, 0.2 * k, 0.5 * k)
		pos2 += Vector3(0, -0.08 * k, 0)
	if switch_t > 0.0:
		pos2 += Vector3(0, -0.25 * clampf(switch_t / 0.6, 0.0, 1.0), 0)
	if bolt_t > 0.0 and mode == "gun":
		rot += Vector3(0, 0, 0.25 * sin(clampf(bolt_t, 0.0, 1.0) * PI))
	if heal_t > 0.0:
		pos2 += Vector3(0, -0.3, 0)
	if mode == "throw":
		pos2 = Vector3(0.18, -0.15 + (0.08 if pin else 0.0), -0.35)
	_vm.position = _vm.position.lerp(pos2, minf(1.0, dt * 18.0))
	_vm.rotation = _vm.rotation.lerp(rot, minf(1.0, dt * 12.0))


## 자동 테스트 전용: 상대가 보이면 가슴을 조준해요 ("enemy" = 가장 가까운 적)
func _auto_aim(t) -> bool:
	if typeof(t) == TYPE_STRING:
		var best = null
		var bd := 1e9
		for a in game.actors():
			if a == self or a.dead or game.same_team(self, a):
				continue
			var dd: float = global_position.distance_to(a.global_position)
			if dd < bd:
				bd = dd
				best = a
		t = best
	if t == null or t.dead:
		return false
	var to: Vector3 = t.global_position + Vector3(0, t.height() * 0.65, 0)
	var e := eye_position()
	var q := PhysicsRayQueryParameters3D.create(e, to, G.LAYER_WORLD)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		# 안 보이면 길찾기로 다가가요
		var path: Array = game.nav.find_path(global_position, t.global_position)
		if not path.is_empty():
			var step: Vector3 = path[0] - global_position
			step.y = 0
			if step.length() < 0.7 and path.size() > 1:
				step = path[1] - global_position
				step.y = 0
			rotation.y = atan2(-step.x, -step.z)
			pitch = 0.0
			wish = Vector3(0, 0, -1)
		return false
	var d := (to - e).normalized()
	rotation.y = atan2(-d.x, -d.z)
	pitch = asin(d.y)
	ads = true
	return true
