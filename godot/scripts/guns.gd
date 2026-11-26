extends RefCounted
## 총 모델 (코드로 만든 3D) — 분류마다 다른 생김새 + 파츠가 보여요. 앞쪽 = -Z

const G = preload("res://scripts/game_data.gd")

const WOOD := ["akm", "kar98k", "mosin", "win94", "s1897", "s686", "sawed", "dbs", "sks", "dragunov", "tommy", "dp28", "crossbow", "r1895"]

static var _mats := {}


static func _m(name: String) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	match name:
		"metal":
			m.albedo_color = Color(0.11, 0.11, 0.12)
			m.metallic = 0.5
			m.roughness = 0.45
		"metal2":
			m.albedo_color = Color(0.2, 0.21, 0.22)
			m.metallic = 0.4
			m.roughness = 0.5
		"poly":
			m.albedo_color = Color(0.16, 0.16, 0.15)
			m.roughness = 0.8
		"tan":
			m.albedo_color = Color(0.55, 0.47, 0.34)
			m.roughness = 0.8
		"wood":
			m.albedo_color = Color(0.42, 0.25, 0.13)
			m.roughness = 0.7
		"glass":
			m.albedo_color = Color(0.2, 0.35, 0.45)
			m.metallic = 0.6
			m.roughness = 0.1
		"red":
			m.albedo_color = Color(1, 0.15, 0.1)
			m.emission_enabled = true
			m.emission = Color(1, 0.1, 0.05)
			m.emission_energy_multiplier = 4.0
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[name] = m
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: String, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.rotation = rot
	mi.material_override = _m(mat)
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r: float, len: float, pos: Vector3, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = len
	c.radial_segments = 10
	mi.mesh = c
	mi.position = pos
	mi.rotation = Vector3(PI / 2, 0, 0)
	mi.material_override = _m(mat)
	parent.add_child(mi)
	return mi


## 결과: {node, muzzle(Node3D), sight_y(조준선 높이), length}
static func build(id: String, att: Dictionary) -> Dictionary:
	var w: Dictionary = G.weapon(id)
	var cat: String = w.cat
	var root := Node3D.new()
	var furn := "wood" if id in WOOD else ("tan" if id in ["scar", "mk14", "mk12", "p90"] else "poly")
	var L := 0.62
	var barrel := 0.3
	var sight_y := 0.075
	match cat:
		"AR":
			L = 0.62
			barrel = 0.28
			_box(root, Vector3(0.055, 0.085, L), Vector3(0, 0, -0.1), "metal")
			_box(root, Vector3(0.05, 0.06, 0.26), Vector3(0, -0.005, -0.5), furn) # 총열 덮개
			_box(root, Vector3(0.045, 0.16 if att.get("mag") in ["ext", "extqd"] else 0.13, 0.07), Vector3(0, -0.11, -0.12), "metal2", Vector3(0.18, 0, 0))
			_box(root, Vector3(0.04, 0.1, 0.045), Vector3(0, -0.08, 0.1), furn, Vector3(-0.3, 0, 0))
			_box(root, Vector3(0.05, 0.08, 0.22), Vector3(0, -0.02, 0.3), furn)
		"SMG":
			L = 0.42
			barrel = 0.12
			_box(root, Vector3(0.055, 0.09, L), Vector3(0, 0, -0.06), "metal")
			_box(root, Vector3(0.04, 0.15 if id != "p90" else 0.04, 0.05), Vector3(0, -0.1, -0.12), "metal2")
			_box(root, Vector3(0.04, 0.09, 0.04), Vector3(0, -0.08, 0.06), furn, Vector3(-0.3, 0, 0))
			_box(root, Vector3(0.03, 0.06, 0.16), Vector3(0, -0.01, 0.22), furn)
		"DMR":
			L = 0.82
			barrel = 0.32
			_box(root, Vector3(0.05, 0.08, L), Vector3(0, 0, -0.15), furn if furn == "wood" else "metal")
			_box(root, Vector3(0.04, 0.1, 0.06), Vector3(0, -0.09, -0.12), "metal2")
			_box(root, Vector3(0.04, 0.1, 0.045), Vector3(0, -0.08, 0.1), furn, Vector3(-0.3, 0, 0))
			_box(root, Vector3(0.05, 0.09, 0.24), Vector3(0, -0.02, 0.32), furn)
		"SR":
			L = 0.95
			barrel = 0.4
			_box(root, Vector3(0.05, 0.07, L), Vector3(0, -0.01, -0.15), furn if furn == "wood" else "poly")
			_box(root, Vector3(0.035, 0.035, 0.08), Vector3(0.045, 0.02, 0.05), "metal") # 노리쇠 손잡이
			_box(root, Vector3(0.055, 0.11, 0.3), Vector3(0, -0.04, 0.38), furn if furn == "wood" else "poly")
			if id == "lynx" or id == "awm":
				_box(root, Vector3(0.05, 0.1, 0.07), Vector3(0, -0.09, -0.05), "metal2")
		"SG":
			L = 0.45 if id == "sawed" else 0.8
			barrel = 0.25 if id == "sawed" else 0.45
			_box(root, Vector3(0.055, 0.075, L * 0.5), Vector3(0, -0.01, 0.0), "metal")
			_box(root, Vector3(0.06, 0.06, 0.2), Vector3(0, -0.06, -L * 0.45), furn) # 펌프
			if id != "sawed":
				_box(root, Vector3(0.055, 0.1, 0.28), Vector3(0, -0.04, 0.3), furn)
			if id in ["s12k", "o12"]:
				_box(root, Vector3(0.045, 0.12, 0.08), Vector3(0, -0.1, -0.05), "metal2")
		"LMG":
			L = 0.9
			barrel = 0.4
			_box(root, Vector3(0.07, 0.11, L * 0.7), Vector3(0, 0, -0.05), "metal")
			if id == "dp28":
				var drum := _cyl(root, 0.13, 0.04, Vector3(0, 0.08, -0.05), "metal2")
				drum.rotation = Vector3.ZERO
			else:
				_box(root, Vector3(0.1, 0.12, 0.12), Vector3(0.03, -0.1, -0.08), "metal2")
			_box(root, Vector3(0.05, 0.1, 0.25), Vector3(0, -0.03, 0.32), furn)
			_box(root, Vector3(0.012, 0.2, 0.012), Vector3(0.04, -0.1, -0.5), "metal", Vector3(0, 0, 0.4)) # 양각대
			_box(root, Vector3(0.012, 0.2, 0.012), Vector3(-0.04, -0.1, -0.5), "metal", Vector3(0, 0, -0.4))
		"HG":
			L = 0.2
			barrel = 0.04
			sight_y = 0.05
			_box(root, Vector3(0.035, 0.045, 0.2 if id not in ["r1895", "r45"] else 0.24), Vector3(0, 0.02, -0.05), "metal")
			_box(root, Vector3(0.032, 0.11, 0.05), Vector3(0, -0.05, 0.02), furn, Vector3(-0.25, 0, 0))
			if id in ["r1895", "r45"]:
				_cyl(root, 0.025, 0.05, Vector3(0, 0.01, -0.01), "metal2")
		"XB":
			L = 0.75
			barrel = 0.0
			_box(root, Vector3(0.05, 0.06, L), Vector3(0, -0.01, -0.1), furn)
			_box(root, Vector3(0.6, 0.025, 0.04), Vector3(0, 0.0, -0.42), "metal")
			_box(root, Vector3(0.012, 0.012, 0.5), Vector3(0, 0.03, -0.25), "metal2")
	var muzzle_z := -L / 2.0 - 0.1 - barrel
	if cat == "HG":
		muzzle_z = -0.16
	elif cat == "SG":
		muzzle_z = -L * 0.5 - barrel * 0.5
	if barrel > 0.0:
		_cyl(root, 0.014 if cat != "SG" else 0.02, barrel, Vector3(0, 0.012, -L / 2.0 - 0.1 - barrel / 2.0 + (0.0 if cat != "SG" else L * 0.05)), "metal")
	# 파츠
	if att.get("muzzle") == "supp":
		_cyl(root, 0.025, 0.18, Vector3(0, 0.012, muzzle_z - 0.09), "metal2")
		muzzle_z -= 0.18
	elif att.get("muzzle") in ["comp", "flash", "choke", "duck"]:
		_cyl(root, 0.02, 0.06, Vector3(0, 0.012, muzzle_z - 0.03), "metal2")
		muzzle_z -= 0.06
	if att.get("grip") != null and cat in ["AR", "SMG", "DMR"]:
		_box(root, Vector3(0.03, 0.08, 0.03), Vector3(0, -0.075, -0.4 if cat != "SMG" else -0.22), "poly")
	var scope = att.get("scope")
	if w.integrated:
		scope = "4x"
	var top := 0.06 if cat != "HG" else 0.045
	if scope in ["reddot", "holo"]:
		# 가운데가 뚫린 창 (조준할 때 앞이 보이게)
		var wy := top + 0.02
		_box(root, Vector3(0.04, 0.006, 0.05), Vector3(0, top - 0.002, -0.05), "metal")
		_box(root, Vector3(0.04, 0.005, 0.012), Vector3(0, wy + 0.02, -0.07), "metal")
		for sx in [-1, 1]:
			_box(root, Vector3(0.005, 0.04, 0.012), Vector3(sx * 0.02, wy, -0.07), "metal")
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.004
		sm.height = 0.008
		dot.mesh = sm
		dot.material_override = _m("red")
		dot.position = Vector3(0, top + 0.02, -0.075)
		root.add_child(dot)
		sight_y = top + 0.02
	elif scope != null and scope != "iron":
		var zl := clampf(0.12 + G.scope_zoom(scope) * 0.012, 0.13, 0.3)
		_cyl(root, 0.022 + minf(0.012, G.scope_zoom(scope) * 0.0015), zl, Vector3(0, top + 0.04, -0.06), "metal")
		_box(root, Vector3(0.02, 0.04, 0.02), Vector3(0, top + 0.01, -0.06), "metal")
		sight_y = top + 0.04
	else:
		_box(root, Vector3(0.008, 0.025, 0.008), Vector3(0, top + 0.01, -L / 2.0 - 0.05), "metal")
		sight_y = top + 0.02
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0.012, muzzle_z)
	root.add_child(muzzle)
	return {"node": root, "muzzle": muzzle, "sight_y": sight_y, "length": L}


static func grenade_model(type: String) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	if type == "frag":
		var s := SphereMesh.new()
		s.radius = 0.045
		s.height = 0.1
		mi.mesh = s
	else:
		var c := CylinderMesh.new()
		c.top_radius = 0.035
		c.bottom_radius = 0.035
		c.height = 0.12
		mi.mesh = c
	var m := StandardMaterial3D.new()
	m.albedo_color = G.THROWABLES[type].color
	mi.material_override = m
	root.add_child(mi)
	var muzzle := Node3D.new()
	root.add_child(muzzle)
	return root
