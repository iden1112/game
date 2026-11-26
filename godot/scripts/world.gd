extends Node3D
## 맵 만들기 — 원본의 맵(벽돌 골목, 훈련장, 눈 덮인 산장, 사막 마을, 컨테이너 부두)을 같은 배치로 옮겼어요.

const G = preload("res://scripts/game_data.gd")

const MAPS := {
	"duel": {"name": "벽돌 골목", "W": 28.0, "L": 72.0, "theme": "base"},
	"arena": {"name": "훈련장", "W": 100.0, "L": 100.0, "theme": "base"},
	"d_snow": {"name": "눈 덮인 산장", "W": 30.0, "L": 72.0, "theme": "snow"},
	"d_desert": {"name": "사막 마을", "W": 32.0, "L": 70.0, "theme": "desert"},
	"d_harbor": {"name": "컨테이너 부두", "W": 30.0, "L": 74.0, "theme": "gray"},
	"range": {"name": "사격장", "W": 60.0, "L": 240.0, "theme": "base"},
	# 2대2
	"t2_farm": {"name": "시골 농장", "W": 44.0, "L": 84.0, "theme": "base", "seed": 201, "floor": "grass", "wall": "palis", "out": "trees"},
	"t2_ruins": {"name": "돌 유적", "W": 44.0, "L": 84.0, "theme": "dusk", "seed": 202, "floor": "dirt", "wall": "rock", "out": ""},
	"t2_forest": {"name": "숲 속 캠프", "W": 44.0, "L": 84.0, "theme": "forest", "seed": 203, "floor": "grass", "wall": "palis", "out": "pines"},
	"t2_town": {"name": "마을 광장", "W": 44.0, "L": 84.0, "theme": "base", "seed": 204, "floor": "cobble", "wall": "brick", "out": "city"},
	# 3대3
	"t3_factory": {"name": "공장", "W": 60.0, "L": 96.0, "theme": "gray", "seed": 301, "floor": "concrete", "wall": "concrete", "out": "city"},
	"t3_snowbase": {"name": "설원 기지", "W": 60.0, "L": 96.0, "theme": "snow", "seed": 302, "floor": "snow", "wall": "fence", "out": "snowpines"},
	"t3_canyon": {"name": "사막 협곡", "W": 60.0, "L": 96.0, "theme": "desert", "seed": 303, "floor": "sand", "wall": "rock", "out": "palms"},
	"t3_village": {"name": "폐허 마을", "W": 60.0, "L": 96.0, "theme": "gray", "seed": 304, "floor": "dirt", "wall": "stone", "out": "trees"},
	# 4대4
	"t4_city": {"name": "도심", "W": 80.0, "L": 110.0, "theme": "base", "seed": 401, "floor": "asphalt", "wall": "concrete", "out": "city"},
	"t4_port": {"name": "항구", "W": 80.0, "L": 110.0, "theme": "gray", "seed": 402, "floor": "concrete", "wall": "fence", "out": "cranes"},
	"t4_fort": {"name": "숲 속 요새", "W": 80.0, "L": 110.0, "theme": "forest", "seed": 403, "floor": "grass", "wall": "rock", "out": "pines"},
	# 개인전
	"f_plaza": {"name": "사거리 광장", "W": 64.0, "L": 64.0, "theme": "base", "seed": 501, "floor": "asphalt", "wall": "concrete", "out": "city", "ffa": true},
	"f_ruins": {"name": "무너진 신전", "W": 64.0, "L": 64.0, "theme": "dusk", "seed": 502, "floor": "dirt", "wall": "rock", "out": "", "ffa": true},
	"f_snow": {"name": "눈 덮인 숲속 오두막", "W": 64.0, "L": 64.0, "theme": "snow", "seed": 503, "floor": "snow", "wall": "rockSnow", "out": "snowpines", "ffa": true},
	"f_yard": {"name": "컨테이너 야적장", "W": 66.0, "L": 66.0, "theme": "gray", "seed": 504, "floor": "concrete", "wall": "fence", "out": "cranes", "ffa": true},
}
const MAP_ORDER := ["duel", "arena", "d_snow", "d_desert", "d_harbor"] # AI 대전
# 온라인: 인원별 맵 (원본 MAP_LIST 와 같은 순서)
const MAP_LIST := {
	1: ["duel", "d_snow", "d_desert", "d_harbor"],
	2: ["t2_farm", "t2_ruins", "t2_forest", "t2_town"],
	3: ["t3_factory", "t3_snowbase", "t3_canyon", "t3_village"],
	4: ["arena", "t4_city", "t4_port", "t4_fort"],
	"ffa": ["f_plaza", "f_ruins", "f_snow", "f_yard"],
}
var ffa_spawns: Array = []

var map_id := ""
var boxes: Array = [] # [{min, max, kind}]
var spots: Array = [] # 봇이 갈 만한 자리 [x, z]
var bounds := Rect2()
var spawn_z := -30.0
var env: Environment
var sun: DirectionalLight3D

var _rng := RandomNumberGenerator.new()
var _collide := true
var _mats := {}
var _spots_on := false


# ================= 재질 =================
func _tex(kind: String) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = kind.hash()
	for y in n:
		for x in n:
			var v := 0.85 + r.randf() * 0.15
			match kind:
				"brick":
					var row := y / 8
					var off := (row % 2) * 8
					if y % 8 == 0 or (x + off) % 16 == 0:
						v = 0.55
				"plank", "log":
					if y % 16 == 0:
						v = 0.6
					v *= 0.92 + 0.08 * sin(x * 0.9 + y * 0.05)
				"concrete", "asphalt", "stone":
					if (x == 0 or y == 0) and kind == "concrete":
						v = 0.75
				"metal":
					if x % 16 == 0:
						v = 0.7
				"cont":
					if x % 6 < 2:
						v = 0.78
				"sandbag":
					if y % 10 == 0 or (x + (y / 10) * 7) % 14 == 0:
						v = 0.65
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


func mat(name: String) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var spec := {
		"concrete": [Color(0.5, 0.49, 0.47), "concrete", 0.5], "concreteDark": [Color(0.45, 0.45, 0.44), "concrete", 0.4],
		"brick": [Color(0.55, 0.3, 0.24), "brick", 0.5], "wood": [Color(0.55, 0.4, 0.24), "plank", 0.8], "metal": [Color(0.45, 0.47, 0.5), "metal", 0.5],
		"dark": [Color(0.15, 0.15, 0.16), "", 1.0], "sandbag": [Color(0.62, 0.56, 0.4), "sandbag", 0.8], "barrel": [Color(0.25, 0.38, 0.55), "metal", 1.0],
		"glass": [Color(0.25, 0.32, 0.38), "", 1.0], "asphalt": [Color(0.24, 0.24, 0.25), "asphalt", 0.2], "ground": [Color(0.36, 0.38, 0.3), "asphalt", 0.15],
		"plaster": [Color(0.84, 0.77, 0.63), "concrete", 0.5], "stone": [Color(0.6, 0.58, 0.54), "stone", 0.5], "plank": [Color(0.5, 0.36, 0.22), "plank", 0.6],
		"log": [Color(0.45, 0.32, 0.2), "log", 0.6], "redwood": [Color(0.52, 0.22, 0.18), "plank", 0.6], "rock": [Color(0.48, 0.47, 0.45), "stone", 0.35],
		"rockSnow": [Color(0.75, 0.77, 0.8), "stone", 0.35], "snow": [Color(0.88, 0.9, 0.94), "stone", 0.1], "snowCap": [Color(0.93, 0.95, 0.98), "", 1.0],
		"sand": [Color(0.8, 0.7, 0.5), "stone", 0.12], "grass": [Color(0.34, 0.45, 0.24), "stone", 0.15], "trunk": [Color(0.36, 0.26, 0.17), "log", 1.0],
		"leaf": [Color(0.2, 0.36, 0.22), "", 1.0], "leafRound": [Color(0.3, 0.45, 0.22), "", 1.0], "leafSnow": [Color(0.55, 0.65, 0.58), "", 1.0],
		"palm": [Color(0.3, 0.5, 0.22), "", 1.0], "roofTile": [Color(0.55, 0.28, 0.2), "brick", 0.6], "hay": [Color(0.8, 0.68, 0.36), "plank", 0.8],
		"tent": [Color(0.42, 0.45, 0.3), "", 1.0], "tank": [Color(0.7, 0.72, 0.7), "metal", 0.4], "water": [Color(0.25, 0.4, 0.5), "", 1.0],
		"dirt": [Color(0.45, 0.37, 0.27), "stone", 0.12], "cobble": [Color(0.5, 0.48, 0.45), "brick", 0.4], "white": [Color(0.86, 0.85, 0.82), "concrete", 0.5],
		"cloth0": [Color(0.7, 0.2, 0.18), "", 1.0], "cloth1": [Color(0.2, 0.4, 0.65), "", 1.0], "cloth2": [Color(0.75, 0.62, 0.2), "", 1.0],
	}
	for i in 6:
		spec["cont%d" % i] = [[Color(0.62, 0.22, 0.18), Color(0.2, 0.36, 0.55), Color(0.25, 0.45, 0.3), Color(0.7, 0.5, 0.15), Color(0.5, 0.5, 0.52), Color(0.4, 0.25, 0.45)][i], "cont", 0.4]
	for i in 4:
		spec["car%d" % i] = [[Color(0.65, 0.15, 0.12), Color(0.2, 0.3, 0.55), Color(0.82, 0.82, 0.8), Color(0.15, 0.16, 0.18)][i], "", 1.0]
	var s: Array = spec.get(name, [Color(0.6, 0.6, 0.6), "", 1.0])
	var m := StandardMaterial3D.new()
	m.albedo_color = s[0]
	m.roughness = 0.9
	if s[1] != "" and Settings.quality != "low":
		m.albedo_texture = _tex(s[1])
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * float(s[2])
	if name in ["metal", "barrel", "tank", "glass"] or name.begins_with("car"):
		m.metallic = 0.4
		m.roughness = 0.45
	if name == "water":
		m.roughness = 0.1
	_mats[name] = m
	return m


# ================= 상자 =================
func add_box(cx: float, y0: float, cz: float, w: float, h: float, d: float, m: String, opt := {}) -> void:
	if w <= 0.01 or h <= 0.01 or d <= 0.01:
		return
	var center := Vector3(cx, y0 + h / 2.0, cz)
	if _collide:
		var kind: String = opt.get("kind", "solid")
		boxes.append({"min": Vector3(cx - w / 2, y0, cz - d / 2), "max": Vector3(cx + w / 2, y0 + h, cz + d / 2), "kind": kind})
		var body := StaticBody3D.new()
		body.collision_layer = G.LAYER_WORLD
		body.collision_mask = 0
		body.set_meta("kind", kind)
		body.position = center
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(w, h, d)
		col.shape = shape
		body.add_child(col)
		add_child(body)
	if opt.get("invisible", false):
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	mi.mesh = bm
	mi.material_override = mat(m)
	mi.position = center
	if opt.get("shadow", true) == false:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func add_sym(cx, y0, cz, w, h, d, m, opt := {}) -> void:
	add_box(cx, y0, cz, w, h, d, m, opt)
	add_box(-cx, y0, -cz, w, h, d, m, opt)


## 보기용 물체 (충돌 없음)
func add_mesh(mesh: Mesh, m: String, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(m)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	add_child(mi)
	return mi


func cyl(top: float, bottom: float, h: float, seg := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func box_mesh(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b


## 원본과 똑같은 난수 (mulberry32) — 씨앗이 같으면 웹과 맵 모양이 똑같아요
var _seed_a := 0


func _seed(s: int) -> void:
	_seed_a = s & 0xFFFFFFFF


static func _imul(a: int, b: int) -> int:
	return ((a & 0xFFFF) * b + ((((a >> 16) & 0xFFFF) * b & 0xFFFF) << 16)) & 0xFFFFFFFF


func MR() -> float:
	_seed_a = (_seed_a + 0x6D2B79F5) & 0xFFFFFFFF
	var a := _seed_a
	var t := _imul(a ^ (a >> 15), 1 | a)
	t = ((t + _imul(t ^ (t >> 7), 61 | t)) & 0xFFFFFFFF) ^ t
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0


func mr(a: float, b: float) -> float:
	return a + MR() * (b - a)


# ================= 원본의 부품 =================
func container(cx, y0, cz, long: bool, along_x: bool, color: int) -> void:
	var L := 12.2 if long else 6.1
	var W := 2.44
	var H := 2.6
	var w := L if along_x else W
	var d := W if along_x else L
	add_box(cx, y0, cz, w, H, d, "cont%d" % (color % 6), {"kind": "metal"})
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			add_mesh(box_mesh(0.16, H + 0.02, 0.16), "dark", Vector3(cx + sx * (w / 2 - 0.07), y0 + H / 2, cz + sz * (d / 2 - 0.07)))


func container_sym(cx, y0, cz, long, along_x, color) -> void:
	container(cx, y0, cz, long, along_x, color)
	container(-cx, y0, -cz, long, along_x, color + 1)


func crate(cx, y0, cz, s := 1.3) -> void:
	add_box(cx, y0, cz, s, s, s, "wood", {"kind": "wood"})


func crate_sym(cx, y0, cz, s) -> void:
	crate(cx, y0, cz, s)
	crate(-cx, y0, -cz, s)


func stairs(x0, z0, width, steps: int, rise, run, dir: String, m: String) -> void:
	for i in steps:
		var h: float = rise * (i + 1)
		var cx: float = x0
		var cz: float = z0
		var w: float = width
		var d: float = run
		match dir:
			"z+":
				cz = z0 + run * (i + 0.5)
			"z-":
				cz = z0 - run * (i + 0.5)
			"x+":
				cx = x0 + run * (i + 0.5)
				w = run
				d = width
			"x-":
				cx = x0 - run * (i + 0.5)
				w = run
				d = width
		add_box(cx, 0, cz, w, h, d, m, {"kind": "stair"})


func scaffold(cx, cz, w, d, h, stair_dir: String) -> void:
	var top: float = h + 0.2
	add_box(cx, h, cz, w, 0.2, d, "metal", {"kind": "metal"})
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			add_box(cx + sx * (w / 2 - 0.12), 0, cz + sz * (d / 2 - 0.12), 0.22, h, 0.22, "dark", {"kind": "metal"})
	if stair_dir != "z-":
		add_box(cx, top, cz - d / 2 + 0.06, w, 0.9, 0.12, "metal", {"kind": "metal"})
	if stair_dir != "z+":
		add_box(cx, top, cz + d / 2 - 0.06, w, 0.9, 0.12, "metal", {"kind": "metal"})
	if stair_dir != "x-":
		add_box(cx - w / 2 + 0.06, top, cz, 0.12, 0.9, d, "metal", {"kind": "metal"})
	if stair_dir != "x+":
		add_box(cx + w / 2 - 0.06, top, cz, 0.12, 0.9, d, "metal", {"kind": "metal"})
	var steps := ceili(top / 0.32)
	var rise := top / steps
	var run := 0.45
	match stair_dir:
		"z-":
			stairs(cx, cz - d / 2 - steps * run, minf(1.4, w), steps, rise, run, "z+", "metal")
		"z+":
			stairs(cx, cz + d / 2 + steps * run, minf(1.4, w), steps, rise, run, "z-", "metal")
		"x-":
			stairs(cx - w / 2 - steps * run, cz, minf(1.4, d), steps, rise, run, "x+", "metal")
		"x+":
			stairs(cx + w / 2 + steps * run, cz, minf(1.4, d), steps, rise, run, "x-", "metal")


func scaffold_sym(cx, cz, w, d, h, dir: String) -> void:
	scaffold(cx, cz, w, d, h, dir)
	scaffold(-cx, -cz, w, d, h, {"z-": "z+", "z+": "z-", "x-": "x+", "x+": "x-"}[dir])


func crate_steps(cx, cz, dir: String, sign := 1.0) -> void:
	var s := 1.2
	var dx := 1.0 if dir == "x" else 0.0
	var dz := 1.0 if dir == "z" else 0.0
	for i in 3:
		for k in i + 1:
			crate(sign * (cx + dx * i * s), k * s, sign * (cz + dz * i * s), s)


func car(cx, cz, along_z: bool, color: int) -> void:
	var L := 4.4
	var W := 1.9
	var w := W if along_z else L
	var d := L if along_z else W
	add_box(cx, 0, cz, w, 1.1, d, "car%d" % (color % 4), {"kind": "metal"})
	add_box(cx, 1.1, cz, w - (0.25 if along_z else 2.0), 0.62, d - (2.0 if along_z else 0.25), "glass", {"kind": "metal"})
	for a in [-1, 1]:
		for b in [-1, 1]:
			if along_z:
				add_mesh(cyl(0.36, 0.36, 0.26, 12), "dark", Vector3(cx + a * (W / 2 + 0.02), 0.36, cz + b * 1.35), Vector3(0, 0, PI / 2))
			else:
				add_mesh(cyl(0.36, 0.36, 0.26, 12), "dark", Vector3(cx + b * 1.35, 0.36, cz + a * (W / 2 + 0.02)), Vector3(PI / 2, 0, 0))


func barrel(x, z) -> void:
	add_box(x, 0, z, 0.62, 0.95, 0.62, "barrel", {"invisible": true, "kind": "metal"})
	add_mesh(cyl(0.31, 0.31, 0.95, 14), "barrel", Vector3(x, 0.475, z))


## 구멍 뚫린 벽 (문·창문)
func hole_wall(along: String, fixed, a0, a1, h, T, m: String, holes: Array) -> void:
	var put := func(c: float, len: float, y0: float, hh: float):
		if len < 0.02 or hh < 0.02:
			return
		if along == "x":
			add_box(c, y0, fixed, len, hh, T, m)
		else:
			add_box(fixed, y0, c, T, hh, len, m)
	var cur: float = a0
	var hs := holes.duplicate()
	hs.sort_custom(func(p, q): return p.c < q.c)
	for o in hs:
		var l: float = o.c - o.w / 2.0
		put.call((cur + l) / 2.0, l - cur, 0.0, h)
		put.call(o.c, o.w, 0.0, o.y0)
		put.call(o.c, o.w, o.y1, h - o.y1)
		cur = o.c + o.w / 2.0
	put.call((cur + a1) / 2.0, a1 - cur, 0.0, h)


func shack(cx: float, cz: float) -> void:
	var w := 6.5
	var d := 6.0
	var h := 3.0
	var T := 0.3
	var sx := signf(cx)
	var sz := signf(cz)
	var door := {"c": cz, "w": 1.4, "y0": 0.0, "y1": 2.3}
	var win := func(c): return {"c": c, "w": 1.5, "y0": 1.05, "y1": 2.05}
	hole_wall("z", cx - sx * (w / 2 - T / 2), cz - d / 2, cz + d / 2, h, T, "brick", [door])
	hole_wall("z", cx + sx * (w / 2 - T / 2), cz - d / 2, cz + d / 2, h, T, "brick", [win.call(cz)])
	hole_wall("x", cz - sz * (d / 2 - T / 2), cx - w / 2 + T, cx + w / 2 - T, h, T, "brick", [win.call(cx + sx * 1.2)])
	hole_wall("x", cz + sz * (d / 2 - T / 2), cx - w / 2 + T, cx + w / 2 - T, h, T, "brick", [{"c": cx + sx * 1.6, "w": 1.2, "y0": 0.0, "y1": 2.3}])
	add_box(cx, h, cz, w, 0.25, d, "concreteDark")
	add_box(cx, h + 0.25, cz - sz * (d / 2 - 0.15), w, 0.85, 0.3, "concrete")
	add_box(cx + sx * (w / 2 - 0.15), h + 0.25, cz, 0.3, 0.85, d, "concrete")
	var steps := 10
	stairs(cx - sx * 1.7, cz + sz * (d / 2 + steps * 0.45), 1.2, steps, (h + 0.25) / steps, 0.45, "z+" if sz < 0 else "z-", "metal")
	crate(cx + sx * 1.6, 0, cz - sz * 1.4, 1.1)


# ---------- 지역 좌표틀 (90도 단위 회전) ----------
class Frame:
	var w # world
	var x: float
	var z: float
	var rot: int
	var c: int
	var s: int
	var odd: bool

	func _init(world, px: float, pz: float, r: int) -> void:
		w = world
		x = px
		z = pz
		rot = ((r % 4) + 4) % 4
		var a := rot * PI / 2.0
		c = roundi(cos(a))
		s = roundi(sin(a))
		odd = rot % 2 == 1

	func P(lx: float, lz: float) -> Vector2:
		return Vector2(x + lx * c + lz * s, z - lx * s + lz * c)

	func box(lx, y, lz, bw, bh, bd, m: String, opt := {}) -> void:
		var p := P(lx, lz)
		w.add_box(p.x, y, p.y, bd if odd else bw, bh, bw if odd else bd, m, opt)

	func mesh(mesh: Mesh, m: String, lx: float, ly: float, lz: float, rot_extra := Vector3.ZERO, scl := Vector3.ONE) -> void:
		var p := P(lx, lz)
		w.add_mesh(mesh, m, Vector3(p.x, ly, p.y), rot_extra + Vector3(0, rot * PI / 2.0, 0), scl)

	func dir(d: String) -> String:
		var v: Vector2 = {"x+": Vector2(1, 0), "x-": Vector2(-1, 0), "z+": Vector2(0, 1), "z-": Vector2(0, -1)}[d]
		var wx := v.x * c + v.y * s
		var wz := -v.x * s + v.y * c
		return "x+" if wx > 0 else ("x-" if wx < 0 else ("z+" if wz > 0 else "z-"))

	func stairs(lx0, lz0, width, steps, rise, run, d: String, m: String) -> void:
		var p := P(lx0, lz0)
		w.stairs(p.x, p.y, width, steps, rise, run, dir(d), m)


func _call(fn: String, F: Frame, args: Array) -> void:
	if fn in ["house", "fountain", "well", "bunker"]:
		callv("p_" + fn, [F] + args)
	else:
		callv("p_" + fn, [F, 0.0, 0.0] + args)


## 네 방향으로 똑같이 (개인전 맵: 90도씩 4번)
func Q(fn: String, x: float, z: float, rot: int, args := []) -> void:
	var px := x
	var pz := z
	for k in 4:
		_call(fn, Frame.new(self, px, pz, rot + k), args)
		if _spots_on:
			spots.append([px, pz])
		var t := px
		px = pz
		pz = -t


## 점대칭으로 두 번 (내 쪽 + 상대 쪽)
func S(fn: String, x: float, z: float, rot: int, args := []) -> void:
	_call(fn, Frame.new(self, x, z, rot), args)
	_call(fn, Frame.new(self, -x, -z, rot + 2), args)
	if _spots_on:
		var bz := -z if z < 0 else z
		var bx := -x if z < 0 else x
		spots.append([bx, bz + 2.2])


## 가운데 한 번
func C(fn: String, x: float, z: float, rot: int, args := []) -> void:
	_call(fn, Frame.new(self, x, z, rot), args)
	if _spots_on:
		spots.append([x, z + 4])


func lwall(F: Frame, along: String, fixed, a0, a1, h, T, m: String, holes: Array) -> void:
	var put := func(cc: float, len: float, y0: float, hh: float):
		if len < 0.02 or hh < 0.02:
			return
		if along == "x":
			F.box(cc, y0, fixed, len, hh, T, m)
		else:
			F.box(fixed, y0, cc, T, hh, len, m)
	var cur: float = a0
	var hs := holes.duplicate()
	hs.sort_custom(func(p, q): return p.c < q.c)
	for o in hs:
		var l: float = o.c - o.w / 2.0
		put.call((cur + l) / 2.0, l - cur, 0.0, h)
		put.call(o.c, o.w, 0.0, o.y0)
		put.call(o.c, o.w, o.y1, h - o.y1)
		cur = o.c + o.w / 2.0
	put.call((cur + a1) / 2.0, a1 - cur, 0.0, h)


func p_house(F: Frame, w: float, d: float, h: float, m: String, o := {}) -> void:
	var T := 0.3
	var door := {"w": 1.4, "y0": 0.0, "y1": 2.3}
	var win := {"w": 1.5, "y0": 1.05, "y1": 2.05}
	var holes := func(side: String, len: float) -> Array:
		var r := []
		var doors: Array = o.get("door", [])
		var wins: Array = o.get("win", [])
		if side in doors:
			var dd := door.duplicate()
			dd["c"] = 0.0
			r.append(dd)
		if side in wins:
			var c := 0.0
			if side in doors:
				c = len / 2 - 1.4 if len / 2 - 1.3 > 1.6 else 99.0
			if c < 50:
				var ww := win.duplicate()
				ww["c"] = c
				r.append(ww)
		return r
	if not o.has("ruin"):
		lwall(F, "x", d / 2 - T / 2, -w / 2, w / 2, h, T, m, holes.call("f", w))
		lwall(F, "x", -d / 2 + T / 2, -w / 2, w / 2, h, T, m, holes.call("b", w))
		lwall(F, "z", -w / 2 + T / 2, -d / 2 + T, d / 2 - T, h, T, m, holes.call("l", d))
		lwall(F, "z", w / 2 - T / 2, -d / 2 + T, d / 2 - T, h, T, m, holes.call("r", d))
	var roof = o.get("roof", null)
	var pitched: bool = o.get("pitched", false)
	if o.has("ruin"):
		_ruin_walls(F, w, d, h, m)
		return
	if roof != false or pitched:
		if not pitched or roof == true:
			F.box(0, h, 0, w, 0.25, d, o.get("roofMat", "concreteDark"))
		else:
			F.box(0, h, 0, w, 0.25, d, o.get("pitchMat", "roofTile"))
		if roof == true:
			F.box(0, h + 0.25, d / 2 - 0.15, w, 0.85, 0.3, o.get("roofMat", "concrete"))
			var steps := ceili((h + 0.25) / 0.33)
			var rise := (h + 0.25) / steps
			var run := 0.45
			match o.get("stairs", "b"):
				"b":
					F.stairs(w / 2 - 0.9, -d / 2 - steps * run, 1.2, steps, rise, run, "z+", "metal")
				"l":
					F.stairs(-w / 2 - steps * run, -d / 2 + 0.8, 1.2, steps, rise, run, "x+", "metal")
				"r":
					F.stairs(w / 2 + steps * run, -d / 2 + 0.8, 1.2, steps, rise, run, "x-", "metal")
		elif pitched:
			var r := maxf(w, d)
			F.mesh(cyl(0.01, r * 0.62, 1.8, 4), o.get("pitchMat", "roofTile"), 0, h + 0.25 + 0.9, 0, Vector3(0, PI / 4, 0), Vector3(w / r, 1, d / r))


func p_wallL(F: Frame, lx, lz, len, h, along_x: bool, m: String) -> void:
	if along_x:
		F.box(lx, 0, lz, len, h, 0.5, m)
	else:
		F.box(lx, 0, lz, 0.5, h, len, m)


func p_rock(F: Frame, lx, lz, w := 2.0, h := 1.4, d := 0.0, snowy := false) -> void:
	if d <= 0.0:
		d = w * 0.85
	for l in [[0.0, 0.22, 0.66], [0.22, 0.7, 0.92], [0.7, 0.92, 0.72]]:
		var bh: float = (l[1] - l[0]) * h
		F.box(lx, l[0] * h, lz, w * l[2], bh, d * l[2] * 0.62, "rock", {"invisible": true})
		F.box(lx, l[0] * h, lz, w * l[2] * 0.62, bh, d * l[2], "rock", {"invisible": true})
	var sm := SphereMesh.new()
	sm.radial_segments = 7
	sm.rings = 4
	sm.radius = 1.0
	sm.height = 2.0
	var rx := mr(-0.12, 0.12)
	var rz := mr(-0.12, 0.12)
	var ry := 0.0 if MR() < 0.5 else PI # 원본과 같은 순서로 난수 3번
	F.mesh(sm, "rockSnow" if snowy else "rock", lx, h / 2 - 0.05, lz, Vector3(rx, ry, rz), Vector3(w / 2.0, h / 1.9, d / 2.0))


func p_pine(F: Frame, lx, lz, s := 1.0, snowy := false) -> void:
	F.box(lx, 0, lz, 0.55 * s, 3.2 * s, 0.55 * s, "trunk", {"invisible": true, "kind": "wood"})
	F.mesh(cyl(0.2 * s, 0.3 * s, 3.4 * s, 7), "trunk", lx, 1.7 * s, lz)
	for k in 3:
		F.mesh(cyl(0.0, (2.2 - k * 0.55) * s, 2.8 * s, 8), "leafSnow" if snowy else "leaf", lx, (3.2 + k * 1.5) * s, lz)


func p_tree(F: Frame, lx, lz, s := 1.0) -> void:
	F.box(lx, 0, lz, 0.6 * s, 3 * s, 0.6 * s, "trunk", {"invisible": true, "kind": "wood"})
	F.mesh(cyl(0.22 * s, 0.32 * s, 3.2 * s, 7), "trunk", lx, 1.6 * s, lz)
	for k in 3:
		var sm := SphereMesh.new()
		sm.radius = (1.6 - k * 0.2) * s
		sm.height = sm.radius * 2
		sm.radial_segments = 8
		sm.rings = 4
		F.mesh(sm, "leafRound", lx + mr(-0.7, 0.7) * s, (3.6 + k * 0.7) * s, lz + mr(-0.7, 0.7) * s)


func p_palm(F: Frame, lx, lz, s := 1.0) -> void:
	F.box(lx, 0, lz, 0.5, 3, 0.5, "trunk", {"invisible": true, "kind": "wood"})
	F.mesh(cyl(0.16 * s, 0.26 * s, 5.5 * s, 7), "trunk", lx, 2.75 * s, lz, Vector3(0, 0, 0.12))
	for k in 6:
		var a := k * PI / 3
		F.mesh(box_mesh(0.7 * s, 0.05, 3 * s), "palm", lx + 0.3 * s + sin(a) * 1.3 * s, 5.2 * s, lz + cos(a) * 1.3 * s, Vector3(-0.45, a, 0))


func p_logs(F: Frame, lx, lz, len := 4.0, along_x := true) -> void:
	if along_x:
		F.box(lx, 0, lz, len, 1.1, 1.3, "log", {"invisible": true, "kind": "wood"})
	else:
		F.box(lx, 0, lz, 1.3, 1.1, len, "log", {"invisible": true, "kind": "wood"})
	for oy in [[-0.32, 0.3], [0.32, 0.3], [0.0, 0.82]]:
		var r := Vector3(0, 0, PI / 2) if along_x else Vector3(PI / 2, 0, 0)
		F.mesh(cyl(0.3, 0.3, len, 10), "log", lx + (0.0 if along_x else oy[0]), oy[1], lz + (oy[0] if along_x else 0.0), r)


func p_hay(F: Frame, lx, lz, n := 1) -> void:
	for i in n:
		F.box(lx + (i % 2) * 1.25, 1.0 if i >= 2 else 0.0, lz, 1.2, 1.0, 1.2, "hay", {"kind": "sand"})


func p_tent(F: Frame, lx, lz) -> void:
	F.box(lx, 0, lz, 2.8, 1.5, 3.4, "tent", {"invisible": true, "kind": "wood"})
	F.mesh(cyl(1.7, 1.7, 3.4, 3), "tent", lx, 0.85, lz, Vector3(PI / 2, 0, PI))


func p_tankV(F: Frame, lx, lz, r := 2.0, h := 6.0, m := "tank") -> void:
	F.box(lx, 0, lz, r * 1.8, h, r * 1.8, m, {"invisible": true, "kind": "metal"})
	F.mesh(cyl(r, r, h, 18), m, lx, h / 2, lz)


# ---------- 팀전·개인전 맵 부품 (원본과 같은 모양·난수 순서) ----------
func _ruin_walls(F: Frame, w: float, d: float, h: float, m: String) -> void:
	var T := 0.35
	var seg := 1.5
	for sd in [["x", d / 2, w], ["x", -d / 2, w], ["z", -w / 2, d - 0.4], ["z", w / 2, d - 0.4]]:
		var len: float = sd[2]
		var a := -len / 2
		while a < len / 2 - 0.1:
			var hh := 0.0 if MR() < 0.25 else mr(0.8, h)
			var l := minf(seg, len / 2 - a)
			if hh > 0.3:
				if sd[0] == "x":
					F.box(a + l / 2, 0, sd[1], l, hh, T, m)
				else:
					F.box(sd[1], 0, a + l / 2, T, hh, l, m)
			a += seg
	for i in 3:
		var bx := mr(-w / 3, w / 3)
		var bz := mr(-d / 3, d / 3)
		var bw := mr(0.6, 1.2)
		var bh := mr(0.3, 0.7)
		var bd := mr(0.6, 1.2)
		F.box(bx, 0, bz, bw, bh, bd, "rock")


func p_broken(F: Frame, lx, lz, len, along_x: bool, m: String) -> void:
	var n := maxi(2, roundi(len / 1.4))
	var sl: float = len / n
	for i in n:
		var hh := mr(0.9, 2.8)
		var c: float = -len / 2.0 + sl * (i + 0.5)
		if MR() < 0.18:
			continue
		if along_x:
			F.box(lx + c, 0, lz, sl, hh, 0.5, m)
		else:
			F.box(lx, 0, lz + c, 0.5, hh, sl, m)


func p_pillar(F: Frame, lx, lz, s := 0.9, h := 4.0, m := "stone") -> void:
	F.box(lx, 0, lz, s, h, s, m, {"invisible": true})
	F.mesh(cyl(s * 0.45, s * 0.5, h, 10), m, lx, h / 2, lz)
	F.mesh(box_mesh(s * 1.15, 0.25, s * 1.15), m, lx, h - 0.12, lz)


func p_platform(F: Frame, lx, lz, w, d, h, m: String, dirs := ["z-"], rail := true) -> void:
	F.box(lx, 0, lz, w, h, d, m)
	var steps := ceili(h / 0.33)
	var rise: float = h / steps
	var run := 0.45
	for dr in dirs:
		match dr:
			"z-":
				F.stairs(lx, lz - d / 2 - steps * run, 1.6, steps, rise, run, "z+", m)
			"z+":
				F.stairs(lx, lz + d / 2 + steps * run, 1.6, steps, rise, run, "z-", m)
			"x-":
				F.stairs(lx - w / 2 - steps * run, lz, 1.6, steps, rise, run, "x+", m)
			"x+":
				F.stairs(lx + w / 2 + steps * run, lz, 1.6, steps, rise, run, "x-", m)
	if rail:
		F.box(lx - w / 2 + 0.6, h, lz + d / 2 - 0.2, 1.2, 0.9, 0.4, m)
		F.box(lx + w / 2 - 0.6, h, lz - d / 2 + 0.2, 1.2, 0.9, 0.4, m)


func p_mesa(F: Frame, lx, lz, w, d, h) -> void:
	F.box(lx, 0, lz, w, h, d, "rock")
	var ox := mr(-w / 5.0, w / 5.0)
	var oz := mr(-d / 5.0, d / 5.0)
	var tw: float = w * mr(0.4, 0.7)
	var th := mr(0.8, 2)
	var td: float = d * mr(0.4, 0.7)
	F.box(lx + ox, h, lz + oz, tw, th, td, "rock")
	for i in 3:
		var rx: float = lx + mr(-w / 2.0, w / 2.0)
		var side := -1.0 if MR() < 0.5 else 1.0
		var rw := mr(1.2, 2.2)
		var rh := mr(0.8, 1.6)
		p_rock(F, rx, lz + side * (d / 2.0 + 0.6), rw, rh)


func p_bus(F: Frame, lx, lz, along_z := true, color := 1) -> void:
	var W := 2.5
	var L := 10.0
	var cm := "car%d" % (color % 4)
	if along_z:
		F.box(lx, 0.3, lz, W, 2.6, L, cm, {"kind": "metal"})
		F.box(lx, 0, lz, W - 0.3, 0.3, L - 1, "dark")
		F.mesh(box_mesh(W + 0.02, 0.8, L - 1), "glass", lx, 2.2, lz)
	else:
		F.box(lx, 0.3, lz, L, 2.6, W, cm, {"kind": "metal"})
		F.box(lx, 0, lz, L - 1, 0.3, W - 0.3, "dark")
		F.mesh(box_mesh(L - 1, 0.8, W + 0.02), "glass", lx, 2.2, lz)


func p_bunker(F: Frame) -> void:
	p_sandbag(F, 0, 1.6, 4, true)
	p_sandbag(F, -2, 0.4, 2.4, false)
	p_sandbag(F, 2, 0.4, 2.4, false)


func p_block(F: Frame, lx, lz, w, d, h, m: String) -> void:
	F.box(lx, 0, lz, w, h, d, m)
	F.box(lx, h, lz, w + 0.3, 0.4, d + 0.3, "concreteDark")


func p_snowTop(F: Frame, lx, lz, w, d, y) -> void:
	F.mesh(box_mesh(w + 0.1, 0.12, d + 0.1), "snowCap", lx, y + 0.06, lz)


func p_fountain(F: Frame) -> void:
	for k in 8:
		var a := k * PI / 4
		F.box(cos(a) * 3, 0, sin(a) * 3, 1.4, 0.75, 1.4, "stone")
	F.box(0, 0, 0, 1.2, 2.2, 1.2, "stone")
	F.mesh(cyl(2.8, 2.8, 0.1, 24), "water", 0, 0.5, 0)


func p_palis(F: Frame, lx, lz, len, along_x := true, h := 3.6, gaps := []) -> void:
	var cur: float = -len / 2.0
	var gs: Array = gaps.duplicate()
	gs.append({"c": len / 2.0 + 99.0, "w": 0.0})
	gs.sort_custom(func(a, b): return a.c < b.c)
	for gp in gs:
		var l: float = minf(gp.c - gp.w / 2.0, len / 2.0) - cur
		if l > 0.1:
			var c := cur + l / 2.0
			if along_x:
				F.box(lx + c, 0, lz, l, h, 0.6, "log", {"kind": "wood"})
			else:
				F.box(lx, 0, lz + c, 0.6, h, l, "log", {"kind": "wood"})
		cur = gp.c + gp.w / 2.0
		if cur > len / 2.0:
			break


func p_pipe(F: Frame, lx, lz, len, y := 2.0, along_x := true) -> void:
	if along_x:
		F.box(lx, y - 0.35, lz, len, 0.7, 0.7, "tank", {"invisible": true, "kind": "metal"})
	else:
		F.box(lx, y - 0.35, lz, 0.7, 0.7, len, "tank", {"invisible": true, "kind": "metal"})
	F.mesh(cyl(0.35, 0.35, len, 12), "tank", lx, y, lz, Vector3(0 if along_x else PI / 2, 0, PI / 2 if along_x else 0))
	var a: float = -len / 2.0 + 1.0
	while a < len / 2.0:
		if along_x:
			F.box(lx + a, 0, lz, 0.25, y - 0.35, 0.25, "dark")
		else:
			F.box(lx, 0, lz + a, 0.25, y - 0.35, 0.25, "dark")
		a += 4.0


func p_crates(F: Frame, lx, lz) -> void:
	for c in [[0.0, 0.0, 0.0, 1.3], [1.3, 0.0, 0.0, 1.3], [0.0, 1.3, 0.0, 1.3], [0.0, 0.0, 1.3, 1.2]]:
		var p := F.P(lx + c[0], lz + c[2])
		crate(p.x, c[1], p.y, c[3])


func p_cont(F: Frame, lx, lz, long: bool, along_x: bool, color: int, y0 := 0.0) -> void:
	var p := F.P(lx, lz)
	container(p.x, y0, p.y, long, (not along_x) if F.odd else along_x, color)


func p_scaf(F: Frame, lx, lz, w, d, h, dir: String) -> void:
	var p := F.P(lx, lz)
	scaffold(p.x, p.y, d if F.odd else w, w if F.odd else d, h, F.dir(dir))


func p_carF(F: Frame, lx, lz, along_z: bool, color := 0) -> void:
	var p := F.P(lx, lz)
	car(p.x, p.y, (not along_z) if F.odd else along_z, color)


func p_barrels(F: Frame, lx, lz) -> void:
	for o in [Vector2(0, 0), Vector2(0.66, 0), Vector2(0.33, 0.6)]:
		var p := F.P(lx + o.x, lz + o.y)
		barrel(p.x, p.y)


func p_sandbag(F: Frame, lx, lz, len := 3.0, along_x := true) -> void:
	if along_x:
		F.box(lx, 0, lz, len, 0.95, 0.8, "sandbag", {"kind": "sand"})
	else:
		F.box(lx, 0, lz, 0.8, 0.95, len, "sandbag", {"kind": "sand"})


func p_jersey(F: Frame, lx, lz, len := 3.0, along_x := true) -> void:
	if along_x:
		F.box(lx, 0, lz, len, 1.05, 0.6, "concrete", {"kind": "barrier"})
	else:
		F.box(lx, 0, lz, 0.6, 1.05, len, "concrete", {"kind": "barrier"})


func p_fence(F: Frame, lx, lz, len, along_x := true, m := "plank") -> void:
	if along_x:
		F.box(lx, 0, lz, len, 1.1, 0.12, m, {"invisible": true, "kind": "wood"})
	else:
		F.box(lx, 0, lz, 0.12, 1.1, len, m, {"invisible": true, "kind": "wood"})
	for y in [0.45, 0.95]:
		F.mesh(box_mesh(len if along_x else 0.08, 0.12, 0.08 if along_x else len), m, lx, y, lz)
	var a: float = -len / 2.0
	while a <= len / 2.0 + 0.01:
		F.mesh(box_mesh(0.12, 1.15, 0.12), m, lx + (a if along_x else 0.0), 0.575, lz + (0.0 if along_x else a))
		a += 1.5


func p_well(F: Frame) -> void:
	for k in 6:
		var a := k * PI / 3
		F.box(cos(a) * 1.4, 0, sin(a) * 1.4, 1.0, 1.0, 1.0, "plaster")
	for sx in [-1, 1]:
		F.box(sx * 1.5, 1.0, 0, 0.2, 1.8, 0.2, "plank")
	F.box(0, 2.8, 0, 3.6, 0.15, 1.6, "roofTile")


func p_stall(F: Frame, lx, lz, color := 0) -> void:
	F.box(lx, 0, lz, 2.6, 1.0, 1.1, "plank", {"kind": "wood"})
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			F.mesh(box_mesh(0.1, 2.4, 0.1), "plank", lx + sx * 1.3, 1.2, lz + sz * 0.7)
	F.mesh(box_mesh(3, 0.06, 2), "cloth%d" % (color % 3), lx, 2.45, lz, Vector3(0.12, 0, 0))


func p_arch(F: Frame, lx, lz, span := 5.0, h := 4.5, along_x := true, m := "stone") -> void:
	var off := span / 2 + 0.6
	if along_x:
		F.box(lx - off, 0, lz, 1.2, h, 1.2, m)
		F.box(lx + off, 0, lz, 1.2, h, 1.2, m)
		F.box(lx, h - 1, lz, span + 2.4, 1, 1.2, m)
	else:
		F.box(lx, 0, lz - off, 1.2, h, 1.2, m)
		F.box(lx, 0, lz + off, 1.2, h, 1.2, m)
		F.box(lx, h - 1, lz, 1.2, 1, span + 2.4, m)


# ---------- 바닥 + 둘레 ----------
func map_floor(W: float, L: float, m: String) -> void:
	add_box(0, -1.0, 0, W + 160, 1.0, L + 160, m, {"kind": "ground"})


func perimeter(W: float, L: float, type: String) -> void:
	var hw := W / 2
	var hl := L / 2
	var solid := func(m: String, H: float):
		add_box(0, 0, -hl - 0.5, W + 2, H, 1, m)
		add_box(0, 0, hl + 0.5, W + 2, H, 1, m)
		add_box(-hw - 0.5, 0, 0, 1, H, L, m)
		add_box(hw + 0.5, 0, 0, 1, H, L, m)
	var F := Frame.new(self, 0, 0, 0)
	if type == "rock" or type == "rockSnow":
		solid.call("rock", 3.2)
		_collide = false
		for side in [["x", W + 6, -hl - 2.2], ["x", W + 6, hl + 2.2], ["z", L, -hw - 2.2], ["z", L, hw + 2.2]]:
			var a: float = -side[1] / 2.0
			while a < side[1] / 2.0:
				var w := mr(3.5, 6)
				var h := mr(5, 11)
				if side[0] == "x":
					p_rock(F, a, side[2], w, h, 4, type == "rockSnow")
				else:
					p_rock(F, side[2], a, 4, h, w, type == "rockSnow")
				a += mr(3, 5)
		_collide = true
		return
	if type == "fence":
		for f in [[0, -hl - 0.3, W + 1, 0.4], [0, hl + 0.3, W + 1, 0.4], [-hw - 0.3, 0, 0.4, L], [hw + 0.3, 0, 0.4, L]]:
			add_box(f[0], 0, f[1], f[2], 6, f[3], "metal", {"invisible": true, "kind": "metal"})
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.54, 0.56, 0.59, 0.35)
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		for f in [[0, -hl - 0.3, W, false], [0, hl + 0.3, W, false], [-hw - 0.3, 0, L, true], [hw + 0.3, 0, L, true]]:
			var q := MeshInstance3D.new()
			q.mesh = box_mesh(0.02 if f[3] else f[2], 3.2, f[2] if f[3] else 0.02)
			q.material_override = fm
			q.position = Vector3(f[0], 1.6, f[1])
			add_child(q)
		return
	if type == "palis":
		for f in [[0, -hl - 0.4, W + 1, 0.6], [0, hl + 0.4, W + 1, 0.6], [-hw - 0.4, 0, 0.6, L], [hw + 0.4, 0, 0.6, L]]:
			add_box(f[0], 0, f[1], f[2], 4.4, f[3], "log", {"kind": "wood"})
		return
	solid.call({"brick": "brick", "plaster": "plaster", "concrete": "concreteDark", "stone": "stone", "plank": "plank"}.get(type, "concreteDark"), 6.0 if type == "concrete" else 5.0)


func outskirts(W: float, L: float, kind: String) -> void:
	var hw := W / 2
	var hl := L / 2
	var F := Frame.new(self, 0, 0, 0)
	_collide = false
	var put := func(x: float, z: float):
		match kind:
			"pines", "snowpines":
				p_pine(F, x, z, mr(1, 1.7), kind == "snowpines")
			"trees":
				p_tree(F, x, z, mr(1, 1.6))
			"palms":
				if MR() < 0.4:
					p_palm(F, x, z, mr(0.9, 1.3))
				else:
					var w := mr(2, 5)
					p_rock(F, x, z, w, mr(1, 3))
			"city":
				var h := mr(10, 24)
				var bw := mr(6, 9)
				var bd := mr(6, 9)
				p_block(F, x, z, bw, bd, h, ["brick", "concrete", "plaster"][int(MR() * 3)])
			"cranes":
				if MR() < 0.15:
					add_mesh(box_mesh(1, 22, 1), "cont3", Vector3(x, 11, z))
					add_mesh(box_mesh(14, 0.8, 0.8), "cont3", Vector3(x, 21.5, z))
				elif MR() < 0.5:
					var lg := MR() < 0.5
					var ax := MR() < 0.5
					container(x, 0, z, lg, ax, int(MR() * 6))
	var gap: float = {"pines": 5.0, "snowpines": 5.0, "trees": 6.0, "palms": 8.0, "city": 9.0, "cranes": 8.0}.get(kind, 8.0)
	var a := -hw - 10
	while a <= hw + 10:
		put.call(a, -hl - mr(6, 14))
		put.call(a, hl + mr(6, 14))
		a += gap
	a = -hl
	while a <= hl:
		put.call(-hw - mr(6, 14), a)
		put.call(hw + mr(6, 14), a)
		a += gap
	_collide = true


# ================= 맵 =================
func build(id: String) -> void:
	if not MAPS.has(id):
		id = "duel"
	if id == map_id:
		return
	for c in get_children():
		if c != sun and c.get_parent() == self and not (c is WorldEnvironment) and c != sun:
			c.queue_free()
	boxes.clear()
	spots.clear()
	map_id = id
	var D: Dictionary = MAPS[id]
	var W: float = D.W
	var L: float = D.L
	bounds = Rect2(-W / 2, -L / 2, W, L)
	spawn_z = -(L / 2 - 3.5)
	_setup_env(D.theme)
	match id:
		"duel":
			_build_duel()
			spots = [[0, 4], [6.5, 9.5], [-8, 15], [8, 21], [-3, 26], [10, 2.5], [-10.5, 4.5]]
		"arena":
			_build_arena()
			spots = [[16, 20], [0, 17], [-19, 13], [6, 8], [-8, 9.5], [30, 14], [-22, 6], [13, 6.5], [0, 7.2]]
		"d_snow":
			_builder(101, W, L, "snow", "rockSnow", "snowpines", _layout_snow)
		"d_desert":
			_builder(102, W, L, "sand", "plaster", "palms", _layout_desert)
		"d_harbor":
			_builder(103, W, L, "asphalt", "fence", "cranes", _layout_harbor)
		"range":
			_build_range()
		_:
			_builder(D.seed, W, L, D.floor, D.wall, D.out, Callable(self, "_layout_" + id))
	ffa_spawns = []
	if D.get("ffa", false):
		var X := W / 2 - 4.5
		ffa_spawns = [[-X, -X], [X, X], [X, -X], [-X, X]]
	if spots.is_empty():
		spots = [[0, 8]]


func _builder(seed: int, W: float, L: float, floor_m: String, wall: String, outside: String, layout: Callable) -> void:
	_seed(seed)
	map_floor(W, L, floor_m)
	perimeter(W, L, wall)
	if outside != "":
		outskirts(W, L, outside)
	_spots_on = true
	layout.call(W / 2, L / 2)
	_spots_on = false


func _layout_snow(_hw, _hl) -> void:
	C("house", 0, 0, 0, [7.0, 5.0, 3.0, "log", {"door": ["l", "r"], "win": ["f", "b"], "roof": false, "pitched": true, "pitchMat": "snowCap"}])
	S("pine", -10.5, -8, 0, [1.1, true]); S("pine", -5.5, -15, 0, [1.0, true]); S("pine", 10, -18, 0, [1.2, true]); S("pine", 4, -7, 0, [0.9, true]); S("pine", 12, -3, 0, [1.0, true]); S("pine", -12, -22, 0, [1.1, true])
	S("rock", -2.5, -12, 0, [2.6, 1.5, 0.0, true]); S("rock", 7.5, -11, 0, [3.0, 1.3, 0.0, true]); S("rock", -8.5, -18, 0, [2.0, 2.2, 0.0, true])
	S("logs", 2.5, -24, 0, [4.0, true]); S("logs", -10, -3, 0, [3.5, false])
	S("house", 9, -27, 0, [5.0, 4.0, 2.6, "plank", {"door": ["f"], "win": ["l"], "roof": true, "stairs": "l"}])
	S("rock", -4.5, -29, 0, [2.6, 1.3, 0.0, true]); S("logs", 4.5, -30.5, 0, [3.5, true])
	S("fence", 0, -18.5, 0, [6.0, true, "plank"])
	S("scaf", -11.5, -13, 0, [3.0, 3.0, 3.0, "z-"])


func _layout_desert(_hw, _hl) -> void:
	C("well", 0, 0, 0)
	S("house", -9.5, -12, 0, [7.0, 6.0, 3.2, "plaster", {"door": ["r"], "win": ["f", "l"], "roof": true, "stairs": "b"}])
	S("house", 10.5, -22, 0, [6.0, 5.0, 3.0, "plaster", {"door": ["l", "f"], "win": ["r"], "roof": false}])
	S("stall", 5, -6, 0, [0]); S("stall", -4.5, -3.5, 0, [2])
	S("wallL", 5, -16, 0, [6.0, 2.2, true, "plaster"]); S("wallL", -12.8, -26, 0, [5.0, 1.2, false, "plaster"])
	S("palm", -13.5, -4, 0, [1.0]); S("palm", 13.5, -11, 0, [1.1]); S("palm", -3.5, -23, 0, [0.9])
	S("crates", 6, -12, 0); S("barrels", 12, -5, 0)
	S("wallL", 0, -29, 0, [5.0, 1.1, true, "plaster"]); S("crates", -9, -30, 0)
	S("arch", 0, -19.5, 0, [3.4, 4.0, true, "plaster"])


func _layout_harbor(_hw, _hl) -> void:
	C("cont", 0, 0, 0, [true, true, 2])
	S("cont", -9, -10, 0, [false, false, 0]); S("cont", 8, -14, 0, [false, false, 1]); S("cont", 8, -14, 0, [false, false, 3, 2.6])
	S("crates", 3.5, -18.5, 0); S("cont", -4, -23, 0, [false, true, 4])
	S("barrels", 12, -5, 0); S("barrels", -13, -18, 0); S("jersey", 2, -8, 0, [3.2, true]); S("jersey", -12.5, -3, 0, [3.0, false])
	S("scaf", 11.5, -26, 0, [3.0, 3.0, 3.2, "z-"])
	S("jersey", 0, -30, 0, [5.0, true]); S("crates", -10, -31, 0); S("carF", 5, -27, 0, [false, 2])


# ----- 2대2 -----
func _layout_t2_farm(_hw, _hl) -> void:
	C("house", 0, 0, 0, [10.0, 8.0, 4.5, "redwood", {"door": ["f", "b"], "win": ["l", "r"], "roof": false, "pitched": true}])
	S("hay", -3, -2, 0, [2]); S("hay", 3.2, 1.5, 0, [1])
	S("tankV", -15, -14, 0, [2.2, 9.0, "tank"])
	S("hay", 6, -12, 0, [3]); S("hay", -8, -21, 0, [2]); S("hay", 13, -27, 0, [4])
	S("fence", -6, -8, 0, [8.0, true]); S("fence", 15, -6, 0, [9.0, false]); S("fence", -16, -24, 0, [8.0, true])
	S("carF", 9, -19, 0, [true, 3])
	S("house", -12, -31, 0, [9.0, 7.0, 3.2, "plank", {"door": ["f", "r"], "win": ["l", "b", "f"], "roof": true, "stairs": "l"}])
	S("tree", 17, -14, 0, [1.3]); S("tree", -18, -4, 0, [1.2]); S("tree", 3, -33, 0, [1.1]); S("tree", 18, -33, 0, [1.4])
	S("hay", -4, -36, 0, [2]); S("hay", 7, -36.5, 0, [2])
	S("logs", 18, -20, 0, [4.0, false])


func _layout_t2_ruins(_hw, _hl) -> void:
	C("platform", 0, 0, 0, [8.0, 8.0, 1.6, "stone", ["z-", "z+"]])
	S("pillar", -3.2, -3.2, 0, [0.9, 4.5]); S("pillar", 3.2, -3.2, 0, [0.9, 4.5])
	S("pillar", -9, -6, 0); S("pillar", -9, -12, 0); S("pillar", 9, -8, 0, [0.9, 2.5])
	S("broken", -12, -15, 0, [8.0, true, "stone"]); S("broken", 5, -20, 0, [10.0, true, "stone"]); S("broken", -17, -27, 0, [6.0, false, "stone"]); S("broken", 15, -11, 0, [7.0, false, "stone"])
	S("arch", 0, -27, 0, [6.0, 4.5, true]); S("rock", 10, -30, 0, [3.0, 1.6]); S("rock", -6, -9, 0, [2.0, 1.2]); S("rock", 17, -22, 0, [2.6, 2.0])
	S("platform", -15, -33, 0, [6.0, 4.0, 2.2, "stone", ["z-"]])
	S("broken", -3, -36, 0, [7.0, true, "stone"]); S("broken", 9, -36, 0, [4.0, true, "stone"])


func _layout_t2_forest(_hw, _hl) -> void:
	S("logs", 0, -2.8, 0, [3.2, true]); S("logs", -2.8, 0, 1, [3.2, true])
	S("pine", -6, -6, 0, [1.2]); S("pine", 8, -4, 0, [1.4]); S("pine", -14, -12, 0, [1.3]); S("pine", 4, -15, 0, [1.1]); S("pine", 16, -16, 0, [1.5]); S("pine", -9, -24, 0, [1.2]); S("pine", 12, -30, 0, [1.3]); S("pine", -18, -36, 0, [1.4]); S("pine", 0, -26, 0, [1.0])
	S("tent", -6, -15, 0); S("tent", 9, -24, 1)
	S("scaf", 15, -9, 0, [3.0, 3.0, 4.0, "z-"])
	S("rock", -16, -4, 0, [3.0, 1.8]); S("rock", 3, -9, 0, [2.2, 1.3]); S("rock", -3, -33, 0, [3.0, 1.4]); S("rock", 19, -24, 0, [2.4, 2.4])
	S("logs", 10, -14, 0, [4.0, false]); S("logs", -12, -30, 0, [4.0, true])
	S("house", -14, -20, 0, [6.0, 5.0, 3.0, "log", {"door": ["f", "r"], "win": ["l"], "roof": false, "pitched": true}])
	S("logs", 5, -36, 0, [4.0, true])


func _layout_t2_town(_hw, _hl) -> void:
	C("fountain", 0, 0, 0)
	S("house", -12, -10, 0, [8.0, 7.0, 3.2, "white", {"door": ["f", "r"], "win": ["l", "b"], "roof": true, "stairs": "l"}])
	S("house", 12, -21, 0, [7.0, 6.0, 3.0, "brick", {"door": ["l"], "win": ["f", "b"], "roof": true, "stairs": "b"}])
	S("stall", 6, -7, 0, [1]); S("stall", -4, -15, 0, [3])
	S("carF", -3, -25, 0, [false, 0]); S("carF", 17, -5, 0, [true, 2])
	S("tree", 8, -13, 0, [1.1]); S("tree", -18, -23, 0, [1.3])
	S("wallL", -8, -4, 0, [3.0, 1.0, true, "stone"]); S("wallL", 15, -32, 0, [4.0, 1.0, false, "stone"])
	S("house", -14, -32, 0, [7.0, 6.0, 3.2, "plaster", {"door": ["f", "b"], "win": ["r"], "roof": false, "pitched": true}])
	S("carF", 5, -36, 0, [false, 1]); S("wallL", -5, -37, 0, [4.0, 1.0, true, "stone"])


# ----- 3대3 -----
func _layout_t3_factory(_hw, _hl) -> void:
	C("house", 0, 0, 0, [14.0, 10.0, 5.0, "metal", {"door": ["f", "b", "l", "r"], "win": [], "roofMat": "metal"}])
	S("crates", -3, -1.5, 0); S("cont", 4, 2.5, 0, [false, true, 1])
	S("tankV", -20, -12, 0, [3.0, 7.0]); S("tankV", -13.5, -13, 0, [2.2, 5.5])
	S("pipe", 8, -19, 0, [18.0, 2.1, true])
	S("cont", 20, -12, 0, [false, false, 2]); S("cont", 20, -12, 0, [false, false, 4, 2.6]); S("crates", 17, -17.5, 0)
	S("scaf", -6, -26, 0, [10.0, 2.5, 3.5, "x-"])
	S("house", 18, -38, 0, [8.0, 6.0, 3.2, "concrete", {"door": ["f", "l"], "win": ["b"], "roof": true, "stairs": "r"}])
	S("barrels", 3, -31, 0); S("jersey", -16, -24, 0, [4.0, true]); S("jersey", 8, -10, 0, [3.0, false])
	S("bus", -22, -33, 0, [true, 2]); S("cont", -10, -40, 0, [true, true, 0]); S("jersey", 4, -43, 0, [6.0, true])


func _layout_t3_snowbase(_hw, _hl) -> void:
	C("platform", 0, 0, 0, [5.0, 5.0, 3.0, "metal", ["z-", "z+"]])
	S("bunker", -10, -13, 0); S("bunker", 14, -6, 1)
	S("cont", 16, -14, 0, [false, false, 0]); S("snowTop", 16, -14, 0, [2.44, 6.1, 2.6])
	S("cont", -18, -6, 0, [true, true, 2]); S("snowTop", -18, -6, 0, [12.2, 2.44, 2.6])
	S("house", -18, -30, 0, [12.0, 6.0, 3.0, "plank", {"door": ["f", "r"], "win": ["f", "b", "l"], "roof": true, "stairs": "l", "roofMat": "snowCap"}])
	S("pine", 24, -24, 0, [1.3, true]); S("pine", -26, -18, 0, [1.4, true]); S("pine", 6, -26, 0, [1.1, true]); S("pine", -4, -38, 0, [1.2, true])
	S("rock", 9, -20, 0, [3.0, 1.5, 0.0, true]); S("rock", -5, -20, 0, [2.4, 1.2, 0.0, true]); S("rock", 22, -36, 0, [4.0, 2.0, 0.0, true])
	S("tankV", 22, -2, 0, [2.0, 4.0, "tank"]); S("jersey", 2, -12, 0, [4.0, true]); S("jersey", -2, -40.5, 0, [6.0, true]); S("crates", 14, -42, 0)
	S("scaf", 26, -40, 0, [3.0, 3.0, 4.0, "z-"])


func _layout_t3_canyon(_hw, _hl) -> void:
	C("mesa", 0, 0, 0, [6.0, 6.0, 2.6]); S("rock", 4.5, -3.5, 0, [1.6, 1.3])
	S("mesa", -17, -10, 0, [10.0, 14.0, 7.0]); S("mesa", 18, -24, 0, [12.0, 10.0, 6.0]); S("mesa", -6, -32, 0, [8.0, 6.0, 4.5])
	S("rock", 6, -10, 0, [3.0, 1.6]); S("rock", -4, -18, 0, [2.6, 1.3]); S("rock", 24, -8, 0, [3.5, 2.0]); S("rock", -24, -28, 0, [3.0, 1.8])
	S("carF", 8, -16, 0, [false, 0]); S("barrels", -10, -22, 0)
	S("house", 8, -38, 0, [7.0, 6.0, 3.0, "plaster", {"door": ["f", "l"], "win": ["r"], "roof": true, "stairs": "b"}])
	S("platform", -22, -40, 0, [6.0, 5.0, 2.4, "rock", ["x+"]])
	S("wallL", 0, -40.5, 0, [6.0, 1.1, true, "plaster"]); S("palm", 20, -42, 0, [1.1]); S("palm", -14, -44, 0, [1.0])


func _layout_t3_village(_hw, _hl) -> void:
	C("platform", 0, 0, 0, [5.0, 5.0, 3.0, "stone", ["x-", "x+"]])
	S("house", -14, -12, 0, [8.0, 7.0, 3.0, "brick", {"ruin": 1}]); S("house", 13, -8, 0, [7.0, 6.0, 3.0, "plaster", {"ruin": 1}])
	S("house", -4, -26, 0, [9.0, 6.0, 3.0, "brick", {"ruin": 1}]); S("house", 20, -30, 0, [8.0, 8.0, 3.2, "stone", {"door": ["f", "l"], "win": ["r", "b"], "roof": true, "stairs": "b"}])
	S("rock", 6, -16, 0, [2.0, 1.0]); S("rock", -22, -24, 0, [2.6, 1.4]); S("rock", 2, -10, 0, [1.6, 0.9])
	S("carF", -18, -36, 0, [true, 3]); S("broken", 9, -42, 0, [8.0, true, "brick"]); S("broken", -10, -42, 0, [6.0, true, "brick"])
	S("tree", 25, -14, 0, [1.2]); S("tree", -25, -6, 0, [1.3]); S("tree", 0, -36, 0, [1.0])
	S("broken", -24, -14, 0, [6.0, false, "stone"]); S("broken", 25, -20, 0, [6.0, false, "stone"])


# ----- 4대4 -----
func _layout_t4_city(_hw, _hl) -> void:
	C("fountain", 0, 0, 0); S("bus", 8, -6, 0, [true, 1])
	S("block", -26, -14, 0, [14.0, 12.0, 14.0, "brick"]); S("block", 26, -30, 0, [12.0, 14.0, 18.0, "concrete"]); S("block", -24, -40, 0, [14.0, 10.0, 10.0, "plaster"])
	S("house", 14, -16, 0, [10.0, 8.0, 3.4, "white", {"door": ["f", "b", "l"], "win": ["r"], "roof": true, "stairs": "r"}])
	S("house", -10, -28, 0, [8.0, 7.0, 3.2, "brick", {"door": ["f", "r"], "win": ["l", "b"], "roof": true, "stairs": "l"}])
	S("carF", -4, -12, 0, [true, 0]); S("carF", 4, -26, 0, [false, 2]); S("carF", 34, -12, 0, [true, 3]); S("carF", -34, -24, 0, [true, 1])
	S("jersey", 0, -38, 0, [6.0, true]); S("jersey", 10, -44, 0, [4.0, false]); S("jersey", -14, -50, 0, [5.0, true])
	S("scaf", 32, -48, 0, [3.0, 3.0, 4.0, "z-"]); S("barrels", -2, -20, 0); S("crates", 22, -4, 0); S("bus", -16, -4, 0, [false, 2])


func _layout_t4_port(_hw, _hl) -> void:
	C("cont", 0, 0, 0, [true, true, 0]); C("cont", 0, 0, 0, [false, true, 1, 2.6])
	S("cont", -14, -8, 0, [true, true, 2]); S("cont", -14, -8, 0, [false, true, 3, 2.6]); S("cont", 14, -14, 0, [false, false, 4])
	S("cont", -28, -14, 0, [false, false, 5]); S("cont", -28, -14, 0, [false, false, 1, 2.6]); S("cont", 30, -6, 0, [true, false, 0])
	S("house", -18, -30, 0, [16.0, 10.0, 6.0, "metal", {"door": ["f", "b", "r"], "win": [], "roofMat": "metal"}])
	S("crates", -21, -31, 0); S("cont", -14, -30, 0, [false, false, 2])
	S("cont", 18, -28, 0, [true, true, 3]); S("crates", 10, -24, 0); S("scaf", 32, -36, 0, [4.0, 4.0, 4.5, "z-"])
	S("barrels", 4, -12, 0); S("jersey", 6, -40, 0, [6.0, true]); S("jersey", -6, -48, 0, [4.0, false]); S("carF", 24, -48, 0, [false, 1])
	S("crates", 34, -20, 0); S("cont", 0, -34, 0, [false, true, 4])


func _layout_t4_fort(_hw, _hl) -> void:
	C("palis", 0, -9, 0, [18.0, true, 3.4, [{"c": 0.0, "w": 3.0}]]); C("palis", 0, 9, 0, [18.0, true, 3.4, [{"c": 0.0, "w": 3.0}]])
	C("palis", -9, 0, 0, [18.0, false, 3.4, [{"c": 0.0, "w": 2.5}]]); C("palis", 9, 0, 0, [18.0, false, 3.4, [{"c": 0.0, "w": 2.5}]])
	S("scaf", -7, -7, 0, [2.6, 2.6, 4.0, "x+"]); S("scaf", 7, -7, 0, [2.6, 2.6, 4.0, "x-"])
	C("house", 0, 0, 0, [5.0, 4.0, 2.6, "log", {"door": ["l", "r"], "win": ["f", "b"], "roof": false, "pitched": true}])
	S("pine", -16, -6, 0, [1.4]); S("pine", 18, -12, 0, [1.5]); S("pine", -24, -20, 0, [1.3]); S("pine", 6, -22, 0, [1.2]); S("pine", 28, -26, 0, [1.6]); S("pine", -8, -34, 0, [1.3]); S("pine", 16, -40, 0, [1.4]); S("pine", -30, -42, 0, [1.5]); S("pine", 34, -8, 0, [1.3])
	S("tent", -16, -28, 0); S("tent", 22, -34, 1); S("logs", -4, -18, 0, [4.0, true]); S("logs", 26, -18, 0, [4.0, false])
	S("rock", -30, -10, 0, [4.0, 2.4]); S("rock", 12, -28, 0, [3.0, 1.6]); S("rock", -18, -48, 0, [3.5, 1.8]); S("rock", 4, -46, 0, [3.0, 1.4])
	S("house", -30, -32, 0, [6.0, 5.0, 3.0, "log", {"door": ["f", "r"], "win": ["b"], "roof": true, "stairs": "l"}])
	S("scaf", 30, -48, 0, [3.0, 3.0, 4.0, "z-"])


# ----- 개인전 -----
func _layout_f_plaza(_hw, _hl) -> void:
	C("fountain", 0, 0, 0)
	Q("house", 0, -16, 0, [9.0, 7.0, 3.4, "brick", {"door": ["f", "b"], "win": ["l", "r"], "roof": true, "stairs": "l"}])
	Q("carF", -8, -6, 0, [true, 1]); Q("jersey", 8, -8, 0, [4.0, true]); Q("crates", 13, -21, 0); Q("barrels", -13, -24, 0)
	Q("sandbag", 21, -11, 0, [3.0, false]); Q("stall", -6, -27, 0, [2])


func _layout_f_ruins(_hw, _hl) -> void:
	C("well", 0, 0, 0)
	Q("pillar", 5, -5, 0, [0.9, 4.0]); Q("pillar", 0, -8, 0, [0.9, 3.2, "stone"])
	Q("broken", 0, -14, 0, [8.0, true, "stone"]); Q("arch", 13, -13, 0, [5.0, 4.5, true])
	Q("rock", -10, -21, 0, [3.2, 1.8]); Q("wallL", 19, -4, 0, [6.0, 2.2, false, "stone"]); Q("pillar", -19, -15, 0, [1.1, 3.6])
	Q("rock", 8, -25, 0, [2.6, 1.4]); Q("broken", -12, -6, 0, [5.0, false, "stone"]); Q("wallL", 6, -20, 0, [4.0, 1.6, true, "stone"])


func _layout_f_snow(_hw, _hl) -> void:
	C("house", 0, 0, 0, [7.0, 7.0, 3.0, "log", {"door": ["f", "b", "l", "r"], "win": [], "roof": false, "pitched": true, "pitchMat": "snowCap"}])
	Q("pine", -6, -12, 0, [1.1, true]); Q("pine", 11, -17, 0, [1.2, true]); Q("pine", -20, -9, 0, [1.0, true])
	Q("rock", 3, -21, 0, [3.0, 1.6, 0.0, true]); Q("logs", -13, -8, 0, [4.0, false]); Q("tent", 17, -6, 0)
	Q("rock", -17, -21, 0, [2.6, 2.0, 0.0, true]); Q("logs", 6, -9, 0, [3.0, true])
	Q("rock", 13, -6, 0, [2.4, 1.5, 0.0, true]); Q("logs", -5, -24, 0, [4.0, true]); Q("pine", 21, -14, 0, [0.9, true])


func _layout_f_yard(_hw, _hl) -> void:
	C("cont", 0, 0, 0, [true, true, 0]); C("cont", 0, 0, 0, [false, true, 1, 2.6])
	Q("cont", 0, -15, 0, [true, true, 2]); Q("cont", -13, -12, 0, [false, false, 3]); Q("crates", 10, -9, 0)
	Q("scaf", 19, -16, 0, [3.0, 3.0, 4.0, "z-"]); Q("barrels", -6, -24, 0); Q("cont", 22, -3, 0, [false, true, 4]); Q("jersey", -19, -3, 0, [4.0, false])


func _build_duel() -> void:
	var W := 28.0
	var L := 72.0
	map_floor(W, L, "asphalt")
	var H := 5.5
	add_box(0, 0, -36.5, W + 2, H, 1, "brick")
	add_box(0, 0, 36.5, W + 2, H, 1, "brick")
	add_box(-14.5, 0, 0, 1, H, L, "brick")
	add_box(14.5, 0, 0, 1, H, L, "brick")
	# 벽 너머 건물 (보기용)
	_collide = false
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for s in [-1, 1]:
		var z := -40
		while z <= 40:
			var h := r.randf_range(12, 22)
			add_box(s * 21, 0, z, 10, h, 12, ["concreteDark", "brick", "concrete"][(absi(z) + (1 if s > 0 else 0)) % 3])
			z += 13
	for s in [-1, 1]:
		add_box(0, 0, s * 43, 40, r.randf_range(14, 20), 10, "concreteDark")
	_collide = true
	# 도로 선
	for z in range(-33, 34, 4):
		add_mesh(box_mesh(0.22, 0.01, 2.2), "cont3", Vector3(0, 0.005, z))
	# 가운데
	add_box(0, 0, 0, 3.6, 2.2, 3.6, "concrete")
	crate_sym(2.5, 0, -1.1, 1.2)
	shack(-8, -15)
	shack(8, 15)
	for c in [[5.8, -8.5, true, 0], [-2.8, -24.5, false, 2], [-11.2, -27, true, 3]]:
		car(c[0], c[1], c[2], c[3])
		car(-c[0], -c[1], c[2], c[3] + 1)
	add_sym(-3.8, 0, -6, 3.2, 1.0, 0.6, "concrete", {"kind": "barrier"})
	add_sym(10.6, 0, -17, 0.6, 1.0, 3.2, "concrete", {"kind": "barrier"})
	add_sym(0, 0, -29.5, 5, 1.1, 0.6, "concrete", {"kind": "barrier"})
	add_sym(8.5, 0, -29.5, 0.6, 1.0, 2.6, "concrete", {"kind": "barrier"})
	add_sym(3.6, 0, -18.5, 0.5, 3.0, 5.0, "brick")
	add_sym(11.2, 0, -5, 3.2, 0.95, 0.8, "sandbag", {"kind": "sand"})
	add_sym(-1.5, 0, -14, 2.6, 0.95, 0.8, "sandbag", {"kind": "sand"})
	for b in [[12.6, -23.5], [12.6, -22.8], [11.95, -23.15], [-12.7, -3.2], [-12.7, -2.5]]:
		barrel(b[0], b[1])
		barrel(-b[0], -b[1])
	crate_sym(12.7, 0, -12, 1.25)
	crate_sym(12.7, 1.25, -12, 1.25)
	crate_sym(12.7, 0, -10.75, 1.25)
	crate_sym(-5.5, 0, -33.5, 1.2)


func _build_arena() -> void:
	var A := 50.0
	map_floor(A * 2, A * 2, "concrete")
	var H := 5.0
	add_box(0, 0, -A - 0.5, A * 2 + 2, H, 1, "concreteDark")
	add_box(0, 0, A + 0.5, A * 2 + 2, H, 1, "concreteDark")
	add_box(-A - 0.5, 0, 0, 1, H, A * 2, "concreteDark")
	add_box(A + 0.5, 0, 0, 1, H, A * 2, "concreteDark")
	# 가운데 2층 건물
	var T := 0.3
	var F1 := 3.2
	var BW := 14.0
	var BD := 10.0
	var hx := BW / 2
	var hz := BD / 2
	var Cm := "concrete"
	for s in [-1, 1]:
		var z: float = s * (hz - T / 2)
		for side in [-1, 1]:
			var segL := hx - 0.9
			var winC: float = side * (0.9 + segL * 0.55)
			var ww := 1.6
			var aW := absf(winC - side * 0.9) - ww / 2
			var bW := segL - aW - ww
			add_box(side * (0.9 + aW / 2), 0, z, aW, F1, T, Cm)
			add_box(side * (0.9 + aW + ww + bW / 2), 0, z, bW, F1, T, Cm)
			add_box(winC, 0, z, ww, 1.1, T, Cm)
			add_box(winC, 2.1, z, ww, F1 - 2.1, T, Cm)
		add_box(0, 2.3, z, 1.8, F1 - 2.3, T, Cm)
	for s in [-1, 1]:
		var x: float = s * (hx - T / 2)
		var Lw := BD - 2 * T
		add_box(x, 0, -Lw / 2 + 1.2, T, F1, 2.4, Cm)
		add_box(x, 0, 0, T, F1, 1.8, Cm)
		add_box(x, 0, Lw / 2 - 1.2, T, F1, 2.4, Cm)
		for zc in [-1.7, 1.7]:
			add_box(x, 0, zc, T, 1.1, 1.6, Cm)
			add_box(x, 2.1, zc, T, F1 - 2.1, 1.6, Cm)
	add_box(-2.5, 0, 0, 0.25, 2.4, 3.4, Cm)
	add_box(2.5, 0, 0, 0.25, 2.4, 3.4, Cm)
	add_box(0, F1, 0, BW, 0.25, BD, "concreteDark")
	var P := 1.05
	var Y2 := F1 + 0.25
	add_box(0, Y2, -hz + T / 2, BW, P, T, Cm)
	add_box(0, Y2, hz - T / 2, BW, P, T, Cm)
	add_box(hx - T / 2, Y2, -1.85, T, P, BD - 3.7 - 2 * T + 0.3, Cm)
	add_box(hx - T / 2, Y2, 4.85, T, P, 0.3, Cm)
	add_box(-hx + T / 2, Y2, 1.85, T, P, BD - 3.7 - 2 * T + 0.3, Cm)
	add_box(-hx + T / 2, Y2, -4.85, T, P, 0.3, Cm)
	add_box(-3.5, Y2, 1.5, 1.2, 1.2, 1.2, "wood", {"kind": "wood"})
	add_box(3.5, Y2, -1.5, 1.2, 1.2, 1.2, "wood", {"kind": "wood"})
	add_box(0, Y2, 0, 0.6, 2.2, 0.6, Cm)
	var steps := 10
	var rise := (F1 + 0.25) / steps
	stairs(hx + 0.75, -3.0, 1.3, steps, rise, 0.5, "z+", "metal")
	stairs(-hx - 0.75, 3.0, 1.3, steps, rise, 0.5, "z-", "metal")
	add_box(hx + 0.4, F1, 2.95, 1.4, 0.25, 2.1, "metal")
	add_box(-hx - 0.4, F1, -2.95, 1.4, 0.25, 2.1, "metal")
	# 컨테이너
	container_sym(-16, 0, -20, true, true, 0)
	stairs(-6.3, -20, 1.4, 8, 2.6 / 8, 0.45, "x-", "metal")
	stairs(6.3, 20, 1.4, 8, 2.6 / 8, 0.45, "x+", "metal")
	container_sym(19, 0, -13, false, false, 1)
	container_sym(26, 0, -31, false, true, 2)
	container_sym(26, 2.6, -31.6, false, true, 3)
	container_sym(-31, 0, -38, true, false, 4)
	container_sym(36, 0, -6, false, false, 5)
	container_sym(-38, 0, -4, false, true, 2)
	# 벽
	add_sym(-30, 0, -14, 0.5, 3.0, 9, Cm)
	add_sym(12, 0, -6, 7, 3.0, 0.5, Cm)
	add_sym(40, 0, -22, 6, 3.0, 0.5, Cm)
	add_sym(-8, 0, -40.5, 7, 3.0, 0.5, Cm)
	for b in [[-5, -29, 4.2, 1.0, 0.6], [8, -23, 3.6, 1.0, 0.6], [0, -15.5, 5, 1.0, 0.6], [0, -42, 6, 1.1, 0.6], [-22, -6, 0.6, 1.0, 4.0], [30, -42, 0.6, 1.0, 4.0], [44, -32, 4.0, 1.0, 0.6]]:
		add_sym(b[0], 0, b[1], b[2], b[3], b[4], Cm, {"kind": "barrier"})
	for b in [[15, -33, 4.4, 0.8], [-13, -9.5, 3.2, 0.8], [-40, -24, 0.8, 4.4], [22, -2, 0.8, 3.2]]:
		add_sym(b[0], 0, b[1], b[2], 0.95, b[3], "sandbag", {"kind": "sand"})
	for c in [[-22, 0, -34, 1.4], [-20.6, 0, -34, 1.4], [-21.3, 1.4, -34, 1.4], [10, 0, -38.5, 1.3], [11.3, 0, -38.5, 1.3], [-35, 0, -27, 1.4], [-35, 1.4, -27, 1.4],
			[31, 0, -18, 1.3], [31, 0, -16.7, 1.3], [31, 1.3, -17.35, 1.3], [-26, 0, -26, 1.2], [4, 0, -34, 1.2], [44, 0, -14, 1.4], [44, 1.4, -14, 1.4], [-44, 0, -42, 1.4],
			[28.2, 0, -29.1, 1.3], [-33.2, 0, -32, 1.3]]:
		crate_sym(c[0], c[1], c[2], c[3])
	scaffold_sym(22, -23, 4.4, 4.4, 2.4, "x-")
	scaffold_sym(-40, -12, 4.0, 5.0, 3.0, "z-")
	scaffold_sym(12, -46, 5.0, 2.6, 1.8, "x+")
	crate_steps(-12, -26, "x")
	crate_steps(-12, -26, "x", -1.0)
	crate_steps(34, -38, "z")
	crate_steps(34, -38, "z", -1.0)
	for c in [[-47, -47], [47, -47], [-47, 47], [47, 47]]:
		add_box(c[0], 0, c[1], 0.5, 9, 0.5, "metal")


func _build_range() -> void:
	# 사격장: 선 쪽(z=30~)에서 아래(-z)로 쏴요
	map_floor(60, 240, "ground")
	add_box(0, 0, -120.5, 62, 8, 1, "concreteDark")
	add_box(0, 0, 120.5, 62, 5, 1, "concreteDark")
	add_box(-30.5, 0, 0, 1, 5, 240, "concreteDark")
	add_box(30.5, 0, 0, 1, 5, 240, "concreteDark")
	# 사로 (사격대)
	for x in [-18, -10, -2, 6, 14, 22]:
		add_box(x, 0, 33, 3, 1.05, 0.5, "wood", {"kind": "wood"})
	# 거리 표지판
	for d in [10, 25, 50, 75, 100, 150, 200]:
		add_mesh(box_mesh(56, 0.02, 0.15), "cont3", Vector3(0, 0.01, 30 - d))
		add_box(-26, 0, 30 - d, 1.2, 2.2 + d * 0.01, 0.2, "cont%d" % (d / 25 % 6), {"kind": "wood"})
	# 연습용 엄폐물·넘기 상자
	add_box(18, 0, 22, 4, 1.0, 0.6, "concrete", {"kind": "barrier"})
	crate(23, 0, 18, 1.3)
	crate(23, 1.3, 18, 1.3)
	add_box(-20, 0, 14, 0.5, 3, 4, "brick")
	stairs(26, 6, 1.4, 8, 0.33, 0.45, "z-", "metal")
	add_box(26, 0, 1.5, 4, 2.64, 3, "concrete")
	spawn_z = 36.0


# ================= 하늘·빛 =================
func _setup_env(theme: String) -> void:
	if env == null:
		var we := WorldEnvironment.new()
		env = Environment.new()
		var sky := Sky.new()
		sky.sky_material = ProceduralSkyMaterial.new()
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.fog_enabled = true
		we.environment = env
		add_child(we)
		sun = DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, -35, 0)
		sun.shadow_enabled = Settings.quality != "low"
		sun.directional_shadow_max_distance = 90.0
		add_child(sun)
	var t: Array = {
		"base": [Color(0.36, 0.55, 0.8), Color(0.72, 0.78, 0.84), Color(0.62, 0.68, 0.78), Color(1.0, 0.95, 0.86), 0.9, 0.003],
		"snow": [Color(0.55, 0.62, 0.72), Color(0.82, 0.85, 0.88), Color(0.7, 0.74, 0.8), Color(0.95, 0.95, 1.0), 0.75, 0.008],
		"desert": [Color(0.4, 0.6, 0.85), Color(0.9, 0.82, 0.68), Color(0.75, 0.68, 0.58), Color(1.0, 0.92, 0.78), 1.0, 0.002],
		"gray": [Color(0.5, 0.55, 0.62), Color(0.7, 0.72, 0.74), Color(0.62, 0.65, 0.7), Color(0.92, 0.92, 0.95), 0.75, 0.005],
		"dusk": [Color(0.35, 0.38, 0.6), Color(0.9, 0.62, 0.45), Color(0.6, 0.55, 0.6), Color(1.0, 0.75, 0.55), 0.8, 0.004],
		"forest": [Color(0.4, 0.55, 0.7), Color(0.68, 0.76, 0.7), Color(0.55, 0.62, 0.58), Color(0.98, 0.95, 0.85), 0.8, 0.006],
	}[theme]
	var sm := env.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = t[0]
	sm.sky_horizon_color = t[1]
	sm.ground_horizon_color = t[1]
	env.ambient_light_color = t[2]
	env.ambient_light_energy = 0.45
	env.fog_light_color = t[1].darkened(0.1)
	env.fog_density = t[5]
	sun.light_color = t[3]
	sun.light_energy = t[4]


# ================= 길 찾기 도우미 =================
## (x,z) 자리에서 가장 높은 바닥 높이 (from_y 위로 max_up 까지)
func ground_at(x: float, z: float, r: float, from_y: float, max_up: float) -> float:
	var g := 0.0
	for b in boxes:
		if x + r > b.min.x and x - r < b.max.x and z + r > b.min.z and z - r < b.max.z:
			var top: float = b.max.y
			if top <= from_y + max_up and top > g:
				g = top
	return g


func point_blocked(p: Vector3, r: float, y0: float, y1: float) -> bool:
	for b in boxes:
		if b.kind == "ground":
			continue
		if p.x + r > b.min.x and p.x - r < b.max.x and p.z + r > b.min.z and p.z - r < b.max.z and b.max.y > y0 and b.min.y < y1:
			return true
	return false
