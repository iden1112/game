extends Node3D
## 군인 캐릭터 모델 — 자세(서기·앉기·엎드리기), 기울이기, 걷기, 쓰러짐, 총 들기

const Guns = preload("res://scripts/guns.gd")

var body: Node3D # 엎드리기·쓰러짐 회전용
var hips: Node3D
var torso: Node3D
var head: Node3D
var leg_l: Node3D
var leg_r: Node3D
var gun_pivot: Node3D
var gun_holder: Node3D
var helmet: MeshInstance3D
var vest: MeshInstance3D
var _phase := 0.0
var _gun: Node3D = null
var muzzle: Node3D = null


func _part(parent: Node3D, size: Vector3, pos: Vector3, col: Color, sphere := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if sphere:
		var s := SphereMesh.new()
		s.radius = size.x
		s.height = size.y
		mi.mesh = s
	else:
		var b := BoxMesh.new()
		b.size = size
		mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func build(shirt: Color, pants: Color, skin: Color) -> void:
	body = Node3D.new()
	add_child(body)
	hips = Node3D.new()
	hips.position.y = 0.95
	body.add_child(hips)
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.11, 0, 0)
		hips.add_child(leg)
		_part(leg, Vector3(0.15, 0.9, 0.17), Vector3(0, -0.45, 0), pants)
		_part(leg, Vector3(0.16, 0.1, 0.26), Vector3(0, -0.9, -0.04), Color(0.12, 0.11, 0.1))
		if side < 0:
			leg_l = leg
		else:
			leg_r = leg
	torso = Node3D.new()
	hips.add_child(torso)
	_shirt_mats.append(_part(torso, Vector3(0.42, 0.58, 0.24), Vector3(0, 0.3, 0), shirt).material_override)
	vest = _part(torso, Vector3(0.46, 0.42, 0.28), Vector3(0, 0.33, 0), Color(0.3, 0.33, 0.24))
	_part(torso, Vector3(0.34, 0.4, 0.14), Vector3(0, 0.3, 0.18), shirt.darkened(0.3)) # 배낭
	head = Node3D.new()
	head.position.y = 0.67
	torso.add_child(head)
	_part(head, Vector3(0.12, 0.25, 0), Vector3(0, 0.0, 0), skin, true)
	helmet = _part(head, Vector3(0.145, 0.2, 0), Vector3(0, 0.04, 0), Color(0.27, 0.31, 0.23), true)
	gun_pivot = Node3D.new()
	gun_pivot.position = Vector3(0.0, 0.48, 0)
	torso.add_child(gun_pivot)
	for side in [-1, 1]:
		var arm := _part(gun_pivot, Vector3(0.1, 0.1, 0.42), Vector3(side * 0.16 + 0.04, -0.06, -0.2), shirt)
		arm.rotation.y = -side * 0.35
		_shirt_mats.append(arm.material_override)
	gun_holder = Node3D.new()
	gun_holder.position = Vector3(0.08, -0.02, -0.35)
	gun_pivot.add_child(gun_holder)


var _shirt_mats: Array = []


## 팀 색 (내 팀 파랑 / 상대 빨강)
func set_shirt(c: Color) -> void:
	for m in _shirt_mats:
		m.albedo_color = c


func set_armor(helmet_lv: int, vest_lv: int) -> void:
	helmet.visible = helmet_lv > 0
	vest.visible = vest_lv > 0
	var hc := [Color(0, 0, 0), Color(0.44, 0.42, 0.31), Color(0.27, 0.31, 0.23), Color(0.15, 0.16, 0.16)]
	var vc := [Color(0, 0, 0), Color(0.54, 0.5, 0.4), Color(0.31, 0.35, 0.24), Color(0.17, 0.18, 0.16)]
	(helmet.material_override as StandardMaterial3D).albedo_color = hc[helmet_lv]
	(vest.material_override as StandardMaterial3D).albedo_color = vc[vest_lv]


func set_gun(id: String, att: Dictionary) -> void:
	if _gun:
		_gun.queue_free()
		_gun = null
		muzzle = null
	if id == "":
		return
	if id.begins_with("nade:"):
		_gun = Guns.grenade_model(id.substr(5))
		muzzle = _gun
	else:
		var g := Guns.build(id, att)
		_gun = g.node
		muzzle = g.muzzle
	gun_holder.add_child(_gun)


## s: {speed, stance, sprint, lean, pitch, dead, prone_t(0~1 엎드린 정도), vault, heal}
func animate(s: Dictionary, dt: float) -> void:
	var stance: String = s.stance
	var spd: float = s.speed
	if s.dead:
		body.rotation.x = lerpf(body.rotation.x, -PI / 2, minf(1.0, dt * 6.0))
		body.position.y = lerpf(body.position.y, 0.2, minf(1.0, dt * 6.0))
		gun_pivot.rotation.x = 0.6
		return
	var pr: float = s.get("prone_t", 0.0)
	# 엎드리기: 몸 전체를 앞으로 눕혀요
	body.rotation.x = lerpf(0.0, -PI / 2, pr)
	body.position = Vector3(0, lerpf(0.0, 0.22, pr), lerpf(0.0, 0.55, pr))
	var crouch := 1.0 if stance == "crouch" else 0.0
	hips.position.y = lerpf(0.95, 0.58, crouch)
	leg_l.rotation.x = lerpf(0.0, -1.1, crouch)
	leg_r.rotation.x = lerpf(0.0, 0.3, crouch)
	torso.rotation.x = lerpf(0.0, 0.25, crouch)
	# 걷기
	if spd > 0.3 and pr < 0.5:
		_phase += dt * spd * (2.2 if s.sprint else 2.8)
		var a := sin(_phase) * clampf(spd / 5.0, 0.2, 0.7)
		leg_l.rotation.x += a
		leg_r.rotation.x -= a
	# 기울이기
	torso.rotation.z = -float(s.lean) * 0.35
	# 총: 위아래 조준 (엎드리면 몸이 누운 만큼 빼요), 달리면 내려요
	var pitch: float = s.pitch
	gun_pivot.rotation.x = pitch - torso.rotation.x + (PI / 2) * pr - (0.7 if s.sprint else 0.0)
	head.rotation.x = clampf(pitch * 0.5, -0.6, 0.6) + (PI / 2) * pr * 0.8
	if s.get("heal", false):
		gun_pivot.rotation.x = -0.9


func set_visible_all(v: bool) -> void:
	visible = v
