extends RefCounted
## AI 길찾기 격자 (1m 칸) + A* — 원본의 NAV 와 같은 방식

var ox := 0.0
var oz := 0.0
var nx := 0
var nz := 0
var blocked := PackedByteArray()


func build(world) -> void:
	var b: Rect2 = world.bounds
	ox = b.position.x
	oz = b.position.y
	nx = int(ceil(b.size.x))
	nz = int(ceil(b.size.y))
	blocked.resize(nx * nz)
	blocked.fill(0)
	var r := 0.4
	for bx in world.boxes:
		if bx.kind == "ground" or bx.max.y < 0.5 or bx.min.y > 1.7:
			continue
		var i0 := int(floor(bx.min.x - r - ox))
		var i1 := int(floor(bx.max.x + r - ox))
		var k0 := int(floor(bx.min.z - r - oz))
		var k1 := int(floor(bx.max.z + r - oz))
		for k in range(maxi(0, k0), mini(nz - 1, k1) + 1):
			for i in range(maxi(0, i0), mini(nx - 1, i1) + 1):
				# 칸 가운데가 상자(+여유) 안이면 막힘
				var cx := ox + i + 0.5
				var cz := oz + k + 0.5
				if cx > bx.min.x - r and cx < bx.max.x + r and cz > bx.min.z - r and cz < bx.max.z + r:
					blocked[i + k * nx] = 1
	# 가장자리
	for i in nx:
		blocked[i] = 1
		blocked[i + (nz - 1) * nx] = 1
	for k in nz:
		blocked[k * nx] = 1
		blocked[nx - 1 + k * nx] = 1


func cell(p: Vector3) -> int:
	var i := clampi(int(floor(p.x - ox)), 0, nx - 1)
	var k := clampi(int(floor(p.z - oz)), 0, nz - 1)
	return i + k * nx


func free_at(p: Vector3) -> bool:
	return blocked[cell(p)] == 0


func center(c: int) -> Vector3:
	return Vector3(ox + (c % nx) + 0.5, 0, oz + (c / nx) + 0.5)


## 두 점 사이를 막힘 없이 걸을 수 있나 (격자 따라 확인)
func line_free(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var n := int(ceil(d.length() / 0.4))
	for s in range(1, n + 1):
		var t := float(s) / n
		if blocked[cell(Vector3(a.x + d.x * t, 0, a.z + d.y * t))] != 0:
			return false
	return true


func _nearest_free(c: int) -> int:
	if blocked[c] == 0:
		return c
	var ci := c % nx
	var ck := c / nx
	for r in range(1, 6):
		for dk in range(-r, r + 1):
			for di in range(-r, r + 1):
				var i := ci + di
				var k := ck + dk
				if i >= 0 and i < nx and k >= 0 and k < nz and blocked[i + k * nx] == 0:
					return i + k * nx
	return c


## 길 찾기: 점 목록 (다듬은 것), 못 찾으면 []
func find_path(from: Vector3, to: Vector3) -> Array:
	var start := _nearest_free(cell(from))
	var goal := _nearest_free(cell(to))
	if start == goal:
		return [to]
	var n := nx * nz
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(1e9)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var open: Array = [] # [f, cell] — 작은 힙 대신 정렬 삽입 (맵이 작아서 충분)
	g[start] = 0.0
	var gx := goal % nx
	var gz := goal / nx
	open.append([0.0, start])
	var guard := 0
	while not open.is_empty() and guard < 20000:
		guard += 1
		var cur: int = open.pop_back()[1]
		if cur == goal:
			break
		if closed[cur]:
			continue
		closed[cur] = 1
		var ci := cur % nx
		var ck := cur / nx
		for dk in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				if di == 0 and dk == 0:
					continue
				var i: int = ci + di
				var k: int = ck + dk
				if i < 0 or i >= nx or k < 0 or k >= nz:
					continue
				var nk: int = i + k * nx
				if blocked[nk] or closed[nk]:
					continue
				if di != 0 and dk != 0 and (blocked[ci + di + ck * nx] or blocked[ci + (ck + dk) * nx]):
					continue # 모서리 끼기 방지
				var ng: float = g[cur] + (1.414 if di != 0 and dk != 0 else 1.0)
				if ng < g[nk]:
					g[nk] = ng
					came[nk] = cur
					var f: float = ng + Vector2(i - gx, k - gz).length()
					# 정렬 유지 (뒤에서 꺼내니까 큰 값이 앞)
					var lo := 0
					var hi := open.size()
					while lo < hi:
						var mid := (lo + hi) / 2
						if open[mid][0] > f:
							lo = mid + 1
						else:
							hi = mid
					open.insert(lo, [f, nk])
	if came[goal] < 0:
		return []
	var pts: Array = []
	var k2 := goal
	while k2 >= 0 and k2 != start:
		pts.push_front(center(k2))
		k2 = came[k2]
	pts[pts.size() - 1] = Vector3(to.x, 0, to.z) if free_at(to) else pts[pts.size() - 1]
	# 다듬기: 바로 갈 수 있는 가장 먼 점으로
	var out: Array = []
	var c := Vector3(from.x, 0, from.z)
	var idx := 0
	while idx < pts.size():
		var far := idx
		for j in range(pts.size() - 1, idx, -1):
			if line_free(c, pts[j]):
				far = j
				break
		out.append(pts[far])
		c = pts[far]
		idx = far + 1
	return out
