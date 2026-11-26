extends Node3D
## 총알(탄도) · 벽 뚫기 · 피해 계산 · 수류탄 · 연막 · 섬광 · 이펙트

const G = preload("res://scripts/game_data.gd")

var game # main
var bullets: Array = []
var grenades: Array = []
var smokes: Array = []
var _decals: Array = []
var _tracer_mesh: BoxMesh
var _tracer_mat: StandardMaterial3D
var _decal_mesh: QuadMesh
var _decal_mat: StandardMaterial3D
var _blood_mat: StandardMaterial3D
var _smoke_mat: StandardMaterial3D


func _ready() -> void:
	_tracer_mesh = BoxMesh.new()
	_tracer_mesh.size = Vector3(1, 1, 1)
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.8)
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_decal_mesh = QuadMesh.new()
	_decal_mesh.size = Vector2(0.09, 0.09)
	_decal_mat = StandardMaterial3D.new()
	_decal_mat.albedo_color = Color(0.06, 0.06, 0.06, 0.85)
	_decal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blood_mat = StandardMaterial3D.new()
	_blood_mat.albedo_color = Color(0.55, 0.03, 0.03)
	_blood_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.albedo_color = Color(0.84, 0.84, 0.83, 0.0)
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func clear() -> void:
	for b in bullets:
		if b.tracer:
			b.tracer.queue_free()
	bullets.clear()
	for g in grenades:
		g.mesh.queue_free()
	grenades.clear()
	for s in smokes:
		s.node.queue_free()
	smokes.clear()
	for d in _decals:
		d.queue_free()
	_decals.clear()


# ================= 총알 =================
func spawn_bullet(owner, origin: Vector3, dir: Vector3, st: Dictionary, dmg: float, visual := false) -> void:
	var b := {"owner": owner, "st": st, "pos": origin, "vel": dir * st.def.vel, "age": 0.0, "dist": 0.0, "dmg": dmg, "tracer": null, "cracked": false, "walls": 0, "wall_mul": 1.0, "visual": visual}
	# 온라인: 내가(또는 내 AI가) 쏜 총알은 다른 사람에게도 보여줘요
	if game and game.mp and not visual and game.mpx.is_local(owner):
		game.mpx.queue_shot(owner, st.def.id, origin, dir)
	if st.cat != "SG" or randf() < 0.35:
		var t := MeshInstance3D.new()
		t.mesh = _tracer_mesh
		t.material_override = _tracer_mat
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		add_child(t)
		b.tracer = t
	bullets.append(b)


func _physics_process(dt: float) -> void:
	_update_bullets(dt)
	_update_grenades(dt)
	_update_smokes(dt)


func _update_bullets(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	for i in range(bullets.size() - 1, -1, -1):
		var b: Dictionary = bullets[i]
		b.age += dt
		var p0: Vector3 = b.pos
		b.vel.y -= G.BULLET_G * dt
		b.vel *= 1.0 - 0.06 * dt
		var p1: Vector3 = p0 + b.vel * dt
		var excl: Array[RID] = []
		if b.owner and is_instance_valid(b.owner):
			excl.append(b.owner.get_rid())
			if game and game.mp and not game.mpx.is_ffa():
				for a in game.actors(): # 같은 팀은 총알이 그냥 지나가요
					if a != b.owner and a.team == b.owner.team:
						excl.append(a.get_rid())
		var q := PhysicsRayQueryParameters3D.create(p0, p1, G.LAYER_WORLD | G.LAYER_ACTOR, excl)
		var hit := space.intersect_ray(q)
		var seg := p0.distance_to(p1)
		var dirn := (p1 - p0) / maxf(seg, 0.0001)
		var hit_t := seg if hit.is_empty() else p0.distance_to(hit.position)
		# 스치는 소리 (내 옆을 지나가면)
		var pl = game.player if game else null
		if not b.cracked and pl and b.owner != pl and not pl.dead:
			var e: Vector3 = pl.eye_position()
			var t := clampf((e - p0).dot(dirn), 0.0, hit_t)
			if (p0 + dirn * t).distance_to(e) < 2.2 and (hit.is_empty() or hit.collider != pl):
				b.cracked = true
				Sfx.crack(p0 + dirn * t)
		b.dist += hit_t
		if b.tracer:
			var tip := p0 + dirn * hit_t
			var len := minf(b.dist - 2.5, 2.2 + b.st.def.vel * 0.004)
			if len > 0.05:
				var w := 0.012 + minf(0.03, b.dist * 0.0004)
				b.tracer.visible = true
				b.tracer.global_transform = Transform3D(Basis.looking_at(dirn, Vector3.UP if absf(dirn.y) < 0.99 else Vector3.RIGHT).scaled(Vector3(w, w, len)), tip - dirn * len / 2.0)
		var done: bool = b.age > 3.0 or p1.y < -5.0
		if not hit.is_empty():
			var c = hit.collider
			if c != null and c.has_method("hit_part"):
				if b.visual:
					blood(hit.position, dirn, c.hit_part(hit.position) == "head")
				elif not c.dead and not (game and game.same_team(b.owner, c)):
					_bullet_hit(b, c, c.hit_part(hit.position), hit.position, dirn)
				done = true
			else:
				var kind: String = c.get_meta("kind", "solid") if c else "solid"
				_impact(hit.position, hit.normal, kind)
				done = true
				# 월샷: 얇은 벽(30cm 이하)은 소총·지정사수·저격·기관총 총알이 뚫어요
				var wm = G.WALLBANG.get(b.st.cat)
				if wm != null and b.walls < 1 and not (kind in ["ground", "sand", "barrier", "stair"]):
					var back := PhysicsRayQueryParameters3D.create(hit.position + dirn * 0.31, hit.position, G.LAYER_WORLD)
					var ex := space.intersect_ray(back)
					if not ex.is_empty() and ex.collider == c:
						b.walls += 1
						b.wall_mul *= wm
						b.pos = ex.position + dirn * 0.02
						b.vel *= 0.85
						_impact(ex.position, -hit.normal, kind)
						done = false
						continue
		else:
			b.pos = p1
		if done:
			if b.tracer:
				b.tracer.queue_free()
			bullets.remove_at(i)


func _bullet_hit(b: Dictionary, victim, part: String, hp: Vector3, dir: Vector3) -> void:
	var st: Dictionary = b.st
	if victim.get("is_remote"):
		# 온라인 상대: 피해 계산은 상대 컴퓨터에서 (상대의 방어구로) — 웹과 같은 'hit' 메시지
		blood(hp, dir, part == "head")
		var att = {}
		if st.cat != "FIST" and b.owner:
			for wp in b.owner.weapons:
				if wp.id == st.def.get("id", ""):
					att = wp.att
		game.mpx.send_hit(b.owner, victim, {"id": st.def.get("id", "fist"), "att": att, "dmg": b.dmg, "wm": b.wall_mul, "part": part, "dist": b.dist, "hp": [hp.x, hp.y, hp.z], "dir": [dir.x, dir.y, dir.z]})
		if b.owner == game.player:
			game.hud.hit_marker(false, part == "head")
			Sfx.hit(part == "head")
		return
	var c: Dictionary = G.CAT_INFO[st.cat]
	var dmg: float = b.dmg * G.falloff_mul(st.cat, b.dist)
	var mult: float = c.head if part == "head" else (c.limb if part == "leg" else c.body)
	dmg *= mult
	var head := part == "head"
	if head and victim.helmet_lv > 0:
		dmg *= 1.0 - G.ARMOR_RED[victim.helmet_lv]
		victim.helmet_dur -= dmg
		if victim.helmet_dur <= 0:
			victim.break_armor("helmet")
	if part == "torso" and victim.vest_lv > 0:
		dmg *= 1.0 - G.ARMOR_RED[victim.vest_lv]
		victim.vest_dur -= dmg * 0.8
		if victim.vest_dur <= 0:
			victim.break_armor("vest")
	# 저격총 몸샷: 조끼 없으면 2방, 있으면 레벨만큼 더 버텨요
	if not head and st.cat == "SR":
		dmg = G.MAX_HP / 2.0
		if part == "torso" and victim.vest_lv > 0:
			dmg *= 1.0 - G.ARMOR_RED[victim.vest_lv] * 0.75
	dmg *= b.wall_mul
	blood(hp, dir, head)
	if game:
		game.on_bullet_hit(b.owner, victim, part, minf(dmg, victim.health), b.dist, st)
	victim.take_damage(dmg, b.owner, {"head": head, "weapon": st.def.name, "dir": dir, "dist": b.dist, "part": part})
	if b.owner and b.owner == (game.player if game else null):
		game.hud.hit_marker(victim.dead, head)
		Sfx.hit(head)


## 맨손 (주먹)
func punch(owner, victim, part: String, hp: Vector3, dir: Vector3) -> void:
	_bullet_hit({"owner": owner, "st": {"cat": "FIST", "def": {"id": "fist", "name": "맨손", "vel": 0.0}}, "dmg": 18.0, "dist": 1.0, "wall_mul": 1.0}, victim, part, hp, dir)


## 온라인: 상대가 나(또는 내 AI)를 맞혔어요 → 맞은 쪽 방어구로 피해 계산
func apply_remote_hit(shooter, victim, m: Dictionary) -> void:
	if victim.dead:
		return
	var st: Dictionary
	var wid := str(m.get("id", "m416"))
	if wid == "fist":
		st = {"cat": "FIST", "def": {"id": "fist", "name": "맨손", "vel": 0.0}}
	else:
		var att = m.get("att")
		st = G.weapon_stats(wid, att if typeof(att) == TYPE_DICTIONARY and not att.is_empty() else G.full_attachments(wid))
	var d: Array = m.get("dir", [0, 0, -1])
	var dir := Vector3(d[0], d[1], d[2])
	var h: Array = m.get("hp", [])
	var hp: Vector3 = Vector3(h[0], h[1], h[2]) if h.size() == 3 else victim.eye_position() - dir * 0.2
	var wm = m.get("wm")
	_bullet_hit({"owner": shooter, "st": st, "dmg": float(m.get("dmg", 0)), "dist": float(m.get("dist", 0)), "wall_mul": float(wm) if wm != null else 1.0}, victim, str(m.get("part", "torso")), hp, dir)


# ================= 이펙트 =================
func _impact(p: Vector3, n: Vector3, kind: String) -> void:
	if kind != "ground" or randf() < 0.5:
		var d := MeshInstance3D.new()
		d.mesh = _decal_mesh
		d.material_override = _decal_mat
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)
		d.global_position = p + n * 0.012
		if absf(n.dot(Vector3.UP)) > 0.99:
			d.global_basis = Basis.looking_at(-n, Vector3.FORWARD)
		else:
			d.global_basis = Basis.looking_at(-n, Vector3.UP)
		_decals.append(d)
		if _decals.size() > 80:
			_decals.pop_front().queue_free()
	_puff(p, n, Color(0.55, 0.5, 0.42) if kind in ["ground", "sand"] else Color(0.6, 0.6, 0.6), 6, 0.06)
	if randf() < 0.25 and game and game.camera_pos().distance_to(p) < 30:
		Sfx.impact(p)


func _puff(p: Vector3, n: Vector3, col: Color, amount: int, size: float) -> void:
	if Settings.quality == "low":
		return
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.emitting = true
	ps.amount = amount
	ps.lifetime = 0.45
	ps.explosiveness = 1.0
	ps.direction = n
	ps.spread = 35.0
	ps.initial_velocity_min = 1.0
	ps.initial_velocity_max = 3.0
	ps.gravity = Vector3(0, -4, 0)
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2
	sm.radial_segments = 4
	sm.rings = 2
	ps.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ps.material_override = m
	add_child(ps)
	ps.global_position = p
	get_tree().create_timer(1.0).timeout.connect(ps.queue_free)


func blood(p: Vector3, dir: Vector3, head: bool) -> void:
	_puff(p, dir, Color(0.6, 0.04, 0.04), 14 if head else 8, 0.05 if head else 0.04)


# ================= 수류탄 =================
func throw_grenade(owner, type: String, origin: Vector3, vel: Vector3, fuse: float) -> void:
	if game and game.mp and game.mpx.is_local(owner):
		game.mpx.send_nade(owner, type, origin, vel, fuse)
	var mesh := MeshInstance3D.new()
	var sm: PrimitiveMesh = CapsuleMesh.new() if type == "frag" else CylinderMesh.new()
	if sm is CapsuleMesh:
		sm.radius = 0.05
		sm.height = 0.13
	else:
		sm.top_radius = 0.045
		sm.bottom_radius = 0.045
		sm.height = 0.14
	mesh.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = G.THROWABLES[type].color
	mesh.material_override = m
	add_child(mesh)
	mesh.global_position = origin
	grenades.append({"owner": owner, "type": type, "pos": origin, "vel": vel, "fuse": fuse, "mesh": mesh, "spin": Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))})


func _grenade_step(g: Dictionary, dt: float) -> void:
	var space := get_world_3d().direct_space_state
	g.vel.y -= G.BULLET_G * dt
	var p0: Vector3 = g.pos
	var p1: Vector3 = p0 + g.vel * dt
	var q := PhysicsRayQueryParameters3D.create(p0, p1, G.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		g.pos = p1
		return
	var n: Vector3 = hit.normal
	var vn: Vector3 = n * g.vel.dot(n)
	var vt: Vector3 = g.vel - vn
	var floor_hit := n.y > 0.7
	var sp := vn.length()
	g.vel = -vn * (0.3 if floor_hit else 0.38) + vt * (0.65 if floor_hit else 0.8)
	g.pos = hit.position + n * 0.05
	if sp > 1.2:
		Sfx.bounce(g.pos)


func _update_grenades(dt: float) -> void:
	for i in range(grenades.size() - 1, -1, -1):
		var g: Dictionary = grenades[i]
		for k in 3:
			_grenade_step(g, dt / 3.0)
		g.mesh.global_position = g.pos
		var sp: float = g.vel.length()
		g.mesh.rotation += g.spin * dt * minf(1.0, sp / 3.0)
		g.fuse -= dt
		if g.fuse <= 0:
			explode(g.type, g.pos, g.owner)
			g.mesh.queue_free()
			grenades.remove_at(i)


func _los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, G.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func explode(type: String, pos: Vector3, owner) -> void:
	if type == "frag":
		Sfx.explosion(pos)
		_explosion_fx(pos)
		var src := pos + Vector3(0, 0.25, 0)
		for a in game.actors():
			if a.dead or a.get("is_remote"):
				continue # 온라인 상대는 자기 컴퓨터에서 계산해요
			if game.same_team(owner, a) and a != owner:
				continue
			var d: float = a.global_position.distance_to(pos)
			if d > 10.0:
				continue
			var chest: Vector3 = a.global_position + Vector3(0, a.height() * 0.75, 0)
			var pelvis: Vector3 = a.global_position + Vector3(0, a.height() * 0.45, 0)
			if not _los(src, chest) and not _los(src, pelvis):
				continue
			var dmg := 200.0 if d < 2.2 else 150.0 * pow(1.0 - (d - 2.2) / 7.8, 1.6)
			if a.vest_lv > 0:
				dmg *= 1.0 - G.ARMOR_RED[a.vest_lv] * 0.6
				a.vest_dur -= dmg * 0.5
				if a.vest_dur <= 0:
					a.break_armor("vest")
			if owner == game.player and a != game.player:
				game.hud.hit_marker(a.health - dmg <= 0, false)
				game.on_bullet_hit(owner, a, "torso", minf(dmg, a.health), d, {"cat": "frag", "def": {"name": "세열 수류탄"}})
			a.take_damage(dmg, owner, {"weapon": "세열 수류탄", "grenade": true, "dir": (a.global_position - pos).normalized(), "dist": d})
		var cd: float = game.camera_pos().distance_to(pos)
		if cd < 30:
			game.shake = maxf(game.shake, (1.0 - cd / 30.0) * 1.2)
		var pl = game.player
		if pl and not pl.dead and pl.global_position.distance_to(pos) < 14:
			var d2: float = pl.global_position.distance_to(pos)
			var k := (1.0 - d2 / 14.0) * (1.0 if _los(src, pl.eye_position()) else 0.5)
			if k > 0.12:
				Sfx.deafen(1.5 + 5.5 * k, k)
	elif type == "smoke":
		Sfx.smoke(pos)
		var node := Node3D.new()
		add_child(node)
		node.global_position = Vector3(pos.x, maxf(1.2, pos.y + 1.2), pos.z)
		var puffs := []
		for k in 16:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 1.0
			sm.height = 2.0
			sm.radial_segments = 8
			sm.rings = 4
			mi.mesh = sm
			mi.material_override = _smoke_mat.duplicate()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var a := k / 16.0 * TAU + randf_range(-0.3, 0.3)
			var r := 1.2 + sqrt(randf()) * 4.2
			mi.position = Vector3(cos(a) * r, randf_range(-0.8, 2.4), sin(a) * r) * 0.2
			node.add_child(mi)
			puffs.append({"mi": mi, "off": Vector3(cos(a) * r, randf_range(-0.8, 2.4), sin(a) * r), "size": randf_range(3.5, 5.0)})
		smokes.append({"node": node, "pos": node.global_position, "age": 0.0, "life": 28.0, "radius": 0.0, "puffs": puffs})
	elif type == "flash":
		Sfx.flash(pos)
		_flash_fx(pos)
		for a in game.actors():
			if a.dead or a.get("is_remote"):
				continue # 온라인 상대는 자기 컴퓨터에서 계산해요
			var eye: Vector3 = a.eye_position()
			var d: float = eye.distance_to(pos)
			if d > 28.0 or not _los(pos, eye):
				continue
			var facing := clampf((a.look_dir().dot((pos - eye).normalized()) + 0.35) / 1.35, 0.0, 1.0)
			var power := clampf((1.0 - d / 28.0) * (0.35 + 0.65 * facing) * 1.4, 0.0, 1.0)
			a.blind = maxf(a.blind, power * 5.0)
			if a == game.player:
				game.hud.flashbang(power)
				if power > 0.15:
					Sfx.deafen(2.0 + 4.5 * power, power)


func _explosion_fx(pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.7, 0.35)
	l.light_energy = 8.0
	l.omni_range = 12.0
	add_child(l)
	l.global_position = pos + Vector3(0, 0.6, 0)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	ball.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 0.65, 0.25, 0.9)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.material_override = m
	add_child(ball)
	ball.global_position = pos + Vector3(0, 0.4, 0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * 2.6, 0.35)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(l, "light_energy", 0.0, 0.5)
	tw.chain().tween_callback(func(): ball.queue_free(); l.queue_free())
	_puff(pos, Vector3.UP, Color(0.25, 0.23, 0.2), 24, 0.12)


func _flash_fx(pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1, 1, 1)
	l.light_energy = 16.0
	l.omni_range = 20.0
	add_child(l)
	l.global_position = pos + Vector3(0, 0.3, 0)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.3)
	tw.tween_callback(l.queue_free)


func _update_smokes(dt: float) -> void:
	for i in range(smokes.size() - 1, -1, -1):
		var s: Dictionary = smokes[i]
		s.age += dt
		var grow := clampf(s.age / 3.0, 0.0, 1.0)
		var fade := clampf((s.life - s.age) / 4.0, 0.0, 1.0)
		s.radius = 5.0 * grow * fade
		for p in s.puffs:
			p.mi.position = p.off * (0.2 + 0.8 * grow)
			p.mi.scale = Vector3.ONE * p.size * (0.3 + 0.7 * grow)
			p.mi.material_override.albedo_color.a = 0.9 * grow * fade
		if s.age >= s.life:
			s.node.queue_free()
			smokes.remove_at(i)


## 연막이 두 점 사이를 가리나
func smoke_blocks(a: Vector3, b: Vector3) -> bool:
	for s in smokes:
		var r: float = s.radius * 0.9
		if r < 1.0:
			continue
		var c: Vector3 = s.pos
		var d := b - a
		var t := clampf((c - a).dot(d) / maxf(d.length_squared(), 0.0001), 0.0, 1.0)
		if (a + d * t).distance_to(c) < r:
			return true
	return false


## 이 점이 연막 속인가 (0~1)
func smoke_density(p: Vector3) -> float:
	var k := 0.0
	for s in smokes:
		if s.radius > 0.5:
			k = maxf(k, clampf(1.0 - p.distance_to(s.pos) / s.radius, 0.0, 1.0) * 1.6)
	return clampf(k, 0.0, 1.0)
