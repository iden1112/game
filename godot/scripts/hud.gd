extends CanvasLayer
## 화면 표시 (HUD) — 원본 화면 요소를 옮겼어요

const G = preload("res://scripts/game_data.gd")

var game
var root: Control
var draw: Control # 조준선·나침반·조준경·피격 방향 (직접 그리기)
var theme_res: Theme

var lb_names: Label
var lb_score_p: Label
var lb_score_b: Label
var lb_round: Label
var lb_msg: Label
var lb_sub: Label
var lb_toast: Label
var lb_pre: Label
var lb_feed: VBoxContainer
var lb_help: Label
var lb_armor: Label
var lb_weapon: Label
var lb_ammo: Label
var lb_mode: Label
var slots_box: VBoxContainer
var hp_bar: Control
var flash_rect: ColorRect
var smoke_rect: ColorRect
var hurt_rect: ColorRect
var board: PanelContainer
var board_lb: Label
var dealt_lb: Label
var range_lb: Label

var hp_lag := 150.0
var _hit_t := 0.0
var _hit_col := Color.WHITE
var _hit_kill := false
var _msg_t := 0.0
var _toast_t := 0.0
var _flash := 0.0
var _dmg_dirs: Array = [] # [{yaw, t}]
var _spread_px := 0.0


func _ready() -> void:
	layer = 1
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_res = Theme.new()
	var font: Font = load("res://fonts/NanumGothic-Regular.ttf") # 게임에 넣은 한글 글꼴 (웹에서도 한글이 보이게)
	theme_res.default_font = font
	theme_res.default_font_size = 15
	root.theme = theme_res
	add_child(root)
	smoke_rect = _rect(Color(0.8, 0.8, 0.79, 0.0))
	hurt_rect = _rect(Color(0.55, 0.0, 0.0, 0.0))
	draw = Control.new()
	draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw.draw.connect(_on_draw)
	root.add_child(draw)
	# 위: 점수
	lb_score_p = _label("0", 24, Control.PRESET_CENTER_TOP, Vector2(0, 6))
	lb_score_b = _label("", 12, Control.PRESET_CENTER_TOP, Vector2(0, 6))
	lb_names = _label("", 12, Control.PRESET_CENTER_TOP, Vector2(0, -40))
	lb_round = _label("", 12, Control.PRESET_CENTER_TOP, Vector2(0, 40))
	lb_pre = _label("", 14, Control.PRESET_CENTER_TOP, Vector2(0, 130))
	lb_pre.add_theme_color_override("font_color", Color(1, 0.82, 0.29))
	lb_msg = _label("", 42, Control.PRESET_CENTER_TOP, Vector2(0, 170))
	lb_sub = _label("", 17, Control.PRESET_CENTER_TOP, Vector2(0, 226))
	lb_toast = _label("", 14, Control.PRESET_CENTER, Vector2(0, 70))
	lb_help = _label("V 1/3인칭 · Alt 둘러보기 · Q/E 기울이기 · C 앉기 · Z 엎드리기 · Space 점프/넘기 · B 사격모드 · G 수류탄 · 4 구급상자 · X 맨손 · ~ 총 고르기", 11, Control.PRESET_BOTTOM_LEFT, Vector2(16, -28))
	lb_help.modulate.a = 0.6
	lb_feed = VBoxContainer.new()
	lb_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lb_feed.position = Vector2(-20, 14)
	lb_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lb_feed.alignment = BoxContainer.ALIGNMENT_END
	lb_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lb_feed)
	# 아래: 방어구·체력
	lb_armor = _label("", 13, Control.PRESET_CENTER_BOTTOM, Vector2(0, -60))
	hp_bar = Control.new()
	hp_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hp_bar.position = Vector2(-230, -36)
	hp_bar.size = Vector2(460, 14)
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.draw.connect(_draw_hp)
	root.add_child(hp_bar)
	# 오른쪽 아래: 총
	lb_weapon = _label("", 15, Control.PRESET_BOTTOM_RIGHT, Vector2(-360, -210))
	lb_ammo = _label("", 40, Control.PRESET_BOTTOM_RIGHT, Vector2(-360, -190))
	lb_mode = _label("", 12, Control.PRESET_BOTTOM_RIGHT, Vector2(-360, -140))
	lb_mode.add_theme_color_override("font_color", Color(1, 0.82, 0.29))
	slots_box = VBoxContainer.new()
	slots_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	slots_box.position = Vector2(-360, -118)
	slots_box.add_theme_constant_override("separation", 2)
	slots_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(slots_box)
	range_lb = _label("", 13, Control.PRESET_TOP_LEFT, Vector2(18, 96))
	range_lb.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	dealt_lb = _label("", 14, Control.PRESET_CENTER, Vector2(0, 90))
	dealt_lb.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	flash_rect = _rect(Color(1, 1, 1, 0.0))
	# 점수판 (Tab)
	board = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.08, 0.9)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(18)
	board.add_theme_stylebox_override("panel", sb)
	board.set_anchors_preset(Control.PRESET_CENTER)
	board.grow_horizontal = Control.GROW_DIRECTION_BOTH
	board.grow_vertical = Control.GROW_DIRECTION_BOTH
	board.visible = false
	board_lb = Label.new()
	board_lb.add_theme_font_size_override("font_size", 15)
	board.add_child(board_lb)
	root.add_child(board)


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r


func _label(text: String, size: int, preset: int, off: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.set_anchors_preset(preset)
	if preset in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER, Control.PRESET_CENTER_BOTTOM]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.position += off
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


# ================= 알림 =================
func message(a: String, b := "", sec := 3.0, kind := "") -> void:
	lb_msg.text = a
	lb_sub.text = b
	lb_msg.add_theme_color_override("font_color", Color(0.49, 0.84, 1.0) if kind == "win" else (Color(1, 0.48, 0.42) if kind == "lose" else Color.WHITE))
	_msg_t = sec


func toast(s: String) -> void:
	lb_toast.text = s
	_toast_t = 2.0


func add_feed(s: String, mine := false) -> void:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0) if mine else Color(1, 0.6, 0.55))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lb_feed.add_child(l)
	if lb_feed.get_child_count() > 5:
		lb_feed.get_child(0).queue_free()
	get_tree().create_timer(7.0).timeout.connect(func(): if is_instance_valid(l): l.queue_free())


func hit_marker(kill: bool, head: bool) -> void:
	_hit_t = 0.22
	_hit_kill = kill
	_hit_col = Color(1, 0.23, 0.19) if kill else (Color(1, 0.82, 0.29) if head else Color.WHITE)


func hurt(from_pos: Vector3) -> void:
	hurt_rect.color.a = 0.35
	var p = game.player
	var to: Vector3 = from_pos - p.global_position
	var yaw: float = atan2(-to.x, -to.z) - p.rotation.y
	_dmg_dirs.append({"yaw": yaw, "t": 1.2})


func flashbang(power: float) -> void:
	_flash = maxf(_flash, power * 5.0)


func show_board(v: bool) -> void:
	board.visible = v and game.state != "menu"
	if v:
		var p = game.player
		var b = game.bot
		var t := "점수판 (Tab)\n\n이름            처치   죽음   헤드샷\n"
		for a in game.actors():
			t += "%-14s  %4d   %4d   %4d\n" % [a.display_name, a.kills, a.deaths, a.heads]
		board_lb.text = t


func show_dealt(dealt: Dictionary) -> void:
	if dealt.is_empty():
		dealt_lb.text = ""
		return
	var t := "넣은 피해\n"
	for k in dealt:
		t += "%s  %d (%d발)\n" % [k, int(dealt[k].dmg), dealt[k].hits]
	dealt_lb.text = t


func refresh_slots() -> void:
	for c in slots_box.get_children():
		c.queue_free()
	var p = game.player if game else null
	if p == null:
		return
	for i in p.weapons.size():
		var wp: Dictionary = p.weapons[i]
		var on: bool = p.mode == "gun" and p.cur == i
		var att := []
		if wp.att.get("scope") and wp.att.scope != "iron":
			att.append(_scope_name(wp.att.scope))
		for k in ["muzzle", "grip", "mag", "stock"]:
			if wp.att.get(k):
				att.append(G.ATT_NAME[k][wp.att[k]])
		_slot("%d  %s" % [i + 1, wp.stats.def.name], ", ".join(att.slice(0, 3)), on)
	var th := []
	for t in G.THROW_ORDER:
		if p.throwables.get(t, 0) > 0:
			th.append("%s ×%d" % [G.THROWABLES[t].name, p.throwables[t]])
	_slot("G  " + (" · ".join(th) if not th.is_empty() else "투척물 없음"), "", p.mode == "throw")
	_slot("4  구급상자 ×%d" % p.meds, "6초 · 체력 +75", p.heal_t > 0.0)


func _scope_name(id) -> String:
	for s in G.SCOPES:
		if s.id == id:
			return s.name
	return ""


func _slot(t: String, sub: String, on: bool) -> void:
	var l := Label.new()
	l.text = t + ("\n    " + sub if sub != "" else "")
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color.WHITE if on else Color(0.72, 0.74, 0.76))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	if on:
		l.text = "▶ " + l.text
	slots_box.add_child(l)


# ================= 매 프레임 =================
func update(dt: float) -> void:
	var p = game.player
	var playing: bool = game.state != "menu"
	for n in [lb_score_p, lb_score_b, lb_names, lb_round, hp_bar, lb_armor, lb_weapon, lb_ammo, lb_mode, slots_box, lb_feed, lb_help, draw]:
		n.visible = playing
	var rng: bool = game.state == "range"
	lb_score_p.visible = playing and not rng
	lb_score_b.visible = playing and not rng
	range_lb.visible = rng
	lb_names.text = ""
	lb_score_p.text = game.score_text()
	lb_score_b.text = ""
	if rng:
		lb_round.text = "훈련장 · Tab 메뉴"
	else:
		var tl: float = maxf(0.0, game.round_left)
		if game.mp:
			lb_round.text = "라운드 %d · %d:%02d · %d점 선승 · %s · %s · 핑 %dms" % [game.round_no, int(tl) / 60, int(tl) % 60, game.mpx.win_to, game.mpx.alive_text(), game.world.MAPS[game.world.map_id].name, int(game.mpx.rtt)]
		else:
			lb_round.text = "라운드 %d · %d:%02d · %d점 선승 · 봇 %s · %s" % [game.round_no, int(tl) / 60, int(tl) % 60, G.WIN_SCORE, G.BOT_LEVELS[Settings.difficulty].name, game.world.MAPS[game.world.map_id].name]
	lb_pre.text = "~ 총 바꾸기 (풀파츠) · 시작하면 바꿀 수 없어요 · %d" % ceili(game.pre_t) if game.state == "pre" else ""
	# 방어구·자세
	var arm := []
	if p.helmet_lv > 0:
		arm.append("헬멧 Lv.%d (%d)" % [p.helmet_lv, int(p.helmet_dur)])
	if p.vest_lv > 0:
		arm.append("조끼 Lv.%d (%d)" % [p.vest_lv, int(p.vest_dur)])
	arm.append({"stand": "서기", "crouch": "앉기", "prone": "엎드리기"}[p.stance] + (" · 달리기" if p.sprint else ""))
	if p.heal_t > 0.0:
		arm.append("치료 중 %.1f초" % p.heal_t)
	lb_armor.text = "   ·   ".join(arm)
	hp_lag = move_toward(hp_lag, p.health, dt * 40.0) if hp_lag > p.health else p.health
	hp_bar.queue_redraw()
	# 총
	var wp = p.w()
	if p.mode == "throw":
		lb_weapon.text = G.THROWABLES[p.throw_type].name
		lb_ammo.text = "×%d" % p.throwables[p.throw_type]
		lb_mode.text = "좌클릭 꾹: 안전핀 · 떼면 던지기 · 우클릭 같이: 굴리기 · R 쿠킹 · G 바꾸기"
	elif p.mode == "fist":
		lb_weapon.text = "맨손"
		lb_ammo.text = "—"
		lb_mode.text = "좌클릭 주먹 (18)"
	elif wp:
		lb_weapon.text = "%s  ·  %s" % [wp.stats.def.name, G.CAT_NAME[wp.stats.cat]]
		lb_ammo.text = "%d / %d" % [wp.mag, wp.reserve]
		lb_ammo.add_theme_color_override("font_color", Color(1, 0.42, 0.35) if wp.mag <= wp.stats.mag * 0.2 else Color.WHITE)
		var mname: String = {"S": "단발", "B": "점사", "A": "연사"}[wp.fire_mode]
		var extra := ""
		if p.reload_t > 0.0:
			extra = " · 재장전 중"
		elif p.bolt_t > 0.0 and wp.stats.def.bolt:
			extra = " · 노리쇠"
		elif p.switch_t > 0.0:
			extra = " · 꺼내는 중"
		if p.ads_t > 0.5 and p.effective_zoom() >= 2.0:
			extra += " · %.1f배" % p.effective_zoom()
		lb_mode.text = mname + extra
	# 화면 효과
	_hit_t = maxf(0.0, _hit_t - dt)
	hurt_rect.color.a = maxf(0.0, hurt_rect.color.a - dt * 0.8)
	_flash = maxf(0.0, _flash - dt)
	flash_rect.color.a = clampf(_flash / 2.0, 0.0, 1.0)
	smoke_rect.color.a = game.combat.smoke_density(game.camera.global_position) * 0.93
	_msg_t -= dt
	if _msg_t <= 0.0:
		lb_msg.text = ""
		lb_sub.text = ""
	_toast_t -= dt
	lb_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	for d in _dmg_dirs:
		d.t -= dt
	_dmg_dirs = _dmg_dirs.filter(func(d): return d.t > 0.0)
	draw.queue_redraw()


func _draw_hp() -> void:
	var p = game.player
	var s := hp_bar.size
	hp_bar.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.5))
	hp_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(s.x * hp_lag / G.MAX_HP, s.y)), Color(0.79, 0.29, 0.25))
	var c := Color(0.95, 0.95, 0.95) if p.health > 75 else (Color(1, 0.8, 0.3) if p.health > 40 else Color(0.95, 0.3, 0.25))
	hp_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(s.x * p.health / G.MAX_HP, s.y)), c)
	hp_bar.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.35), false, 1.0)
	# 숨·쿠킹 막대
	if p.holding_breath or p.breath < 0.99:
		hp_bar.draw_rect(Rect2(Vector2(s.x / 2 - 70, -140), Vector2(140 * p.breath, 4)), Color(0.6, 0.82, 1.0))
	if p.cook_t >= 0.0:
		var f: float = G.THROWABLES[p.throw_type].fuse
		hp_bar.draw_rect(Rect2(Vector2(s.x / 2 - 60, -300), Vector2(120 * (1.0 - p.cook_t / f), 6)), Color(1, 0.42, 0.23))
	if p.heal_t > 0.0:
		hp_bar.draw_rect(Rect2(Vector2(s.x / 2 - 80, -120), Vector2(160 * (1.0 - p.heal_t / 6.0), 5)), Color(0.5, 0.9, 0.5))


func _on_draw() -> void:
	var p = game.player
	var c := draw.size / 2.0
	var wp = p.w()
	# 나침반
	var heading := fposmod(-rad_to_deg(p.rotation.y + p.free_yaw), 360.0)
	var cw := 460.0
	var cy := 66.0
	draw.draw_rect(Rect2(c.x - cw / 2, cy, cw, 22), Color(0, 0, 0, 0.25))
	for deg in range(0, 360, 15):
		var dd := wrapf(deg - heading, -180.0, 180.0)
		if absf(dd) > 60.0:
			continue
		var x := c.x + dd / 60.0 * cw / 2
		var big := deg % 45 == 0
		draw.draw_line(Vector2(x, cy), Vector2(x, cy + (10 if big else 5)), Color(1, 1, 1, 0.8), 1.0)
		if big:
			var name: String = {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}[deg]
			draw.draw_string(theme_res.default_font, Vector2(x - 8, cy + 21), name, HORIZONTAL_ALIGNMENT_CENTER, 16, 11, Color(1, 0.82, 0.29) if deg == 0 else Color.WHITE)
	draw.draw_string(theme_res.default_font, Vector2(c.x - 20, cy + 38), "%d" % int(heading), HORIZONTAL_ALIGNMENT_CENTER, 40, 12, Color(1, 0.82, 0.29))
	# 피격 방향
	for d in _dmg_dirs:
		var a: float = -d.yaw
		var dir := Vector2(sin(a), -cos(a))
		var pt := c + dir * 120.0
		var side := Vector2(-dir.y, dir.x)
		draw.draw_colored_polygon(PackedVector2Array([pt + dir * 22, pt + side * 14, pt - side * 14]), Color(0.9, 0.1, 0.1, clampf(d.t, 0.0, 1.0) * 0.8))
	if p.dead or game.state == "menu":
		return
	# 조준경 (3배율 이상)
	if p._scoped():
		var r := draw.size.y * 0.39
		var outer := PackedVector2Array()
		for i in 64:
			outer.append(c + Vector2(cos(i / 64.0 * TAU), sin(i / 64.0 * TAU)) * r)
		draw.draw_rect(Rect2(0, 0, c.x - r, draw.size.y), Color(0.03, 0.03, 0.04))
		draw.draw_rect(Rect2(c.x + r, 0, draw.size.x - c.x - r, draw.size.y), Color(0.03, 0.03, 0.04))
		draw.draw_rect(Rect2(c.x - r, 0, r * 2, c.y - r), Color(0.03, 0.03, 0.04))
		draw.draw_rect(Rect2(c.x - r, c.y + r, r * 2, draw.size.y - c.y - r), Color(0.03, 0.03, 0.04))
		# 모서리 채우기
		for q in 4:
			var pts := PackedVector2Array()
			var a0 := q * PI / 2
			var corner := c + Vector2(cos(a0 + PI / 4), sin(a0 + PI / 4)) * r * 1.5
			pts.append(corner)
			for i in 17:
				pts.append(c + Vector2(cos(a0 + i / 16.0 * PI / 2), sin(a0 + i / 16.0 * PI / 2)) * r)
			draw.draw_colored_polygon(pts, Color(0.03, 0.03, 0.04))
		draw.draw_arc(c, r, 0, TAU, 96, Color(0.05, 0.05, 0.05), 6.0)
		draw.draw_line(Vector2(c.x - r, c.y), Vector2(c.x - 6, c.y), Color(0, 0, 0), 1.5)
		draw.draw_line(Vector2(c.x + 6, c.y), Vector2(c.x + r, c.y), Color(0, 0, 0), 1.5)
		draw.draw_line(Vector2(c.x, c.y + 6), Vector2(c.x, c.y + r), Color(0, 0, 0), 2.5)
		draw.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y - 6), Color(0, 0, 0), 1.5)
		for k in [1, 2, 3, 4]:
			draw.draw_line(Vector2(c.x - 8 + k, c.y + k * 22), Vector2(c.x + 8 - k, c.y + k * 22), Color(0, 0, 0), 1.0)
		draw.draw_circle(c, 2.0, Color(1, 0.15, 0.1))
	elif wp and p.ads_t > 0.6 and p.effective_zoom() >= 2.0:
		draw.draw_circle(c, 2.5, Color(1, 0.15, 0.1)) # 2배율
	elif p.ads_t < 0.6 and p.mode != "throw":
		_crosshair(c, wp)
	# 맞힘 표시
	if _hit_t > 0.0:
		var s := 11.0 if not _hit_kill else 15.0
		for k in 4:
			var a := PI / 4 + k * PI / 2
			var d := Vector2(cos(a), sin(a))
			draw.draw_line(c + d * 9, c + d * (9 + s), _hit_col, 2.0)
	# 수류탄 궤적
	if p.mode == "throw" and p.pin:
		var pos: Vector3 = p.throw_origin()
		var vel: Vector3 = p.throw_velocity(Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
		var cam: Camera3D = game.camera
		var prev = null
		for i in 60:
			vel.y -= G.BULLET_G / 30.0
			pos += vel / 30.0
			if pos.y < 0.0 or cam.is_position_behind(pos):
				break
			var sp := cam.unproject_position(pos)
			if prev != null:
				draw.draw_line(prev, sp, Color(1, 1, 1, 0.6), 2.0)
			prev = sp


func _crosshair(c: Vector2, wp) -> void:
	var xh: Dictionary = Settings.xh
	var col: Color = xh.get("color", Color.WHITE)
	var p = game.player
	var spread := 0.0
	if wp:
		var st: Dictionary = wp.stats
		spread = st.hip * lerpf(1.0, 0.42, p.shoulder_t) + Vector2(p.velocity.x, p.velocity.z).length() / 6.0 * 2.0
		if not p.is_on_floor():
			spread += 4.0
	var px := tan(deg_to_rad(spread)) / tan(deg_to_rad(game.camera.fov / 2.0)) * draw.size.y / 2.0
	_spread_px = lerpf(_spread_px, px, 0.3)
	if wp and wp.stats.cat == "SG":
		draw.draw_arc(c, maxf(8.0, _spread_px), 0, TAU, 48, Color(0.3, 1, 0.45, 0.85), 2.0)
		draw.draw_circle(c, 1.5, Color(0.35, 1, 0.55))
		return
	var gap: float = xh.gap + (_spread_px * 0.5 if xh.dyn else 0.0)
	var L: float = xh.len
	var th: float = xh.th
	var outline: bool = xh.out
	var segs := [[Vector2(0, -1)], [Vector2(0, 1)], [Vector2(-1, 0)], [Vector2(1, 0)]]
	if L > 0:
		for s in segs:
			var d: Vector2 = s[0]
			var a := c + d * gap
			var b := c + d * (gap + L)
			if outline:
				draw.draw_line(a - d, b + d, Color(0, 0, 0, 0.85), th + 2.0)
			draw.draw_line(a, b, col, th)
	if xh.dot > 0:
		if outline:
			draw.draw_circle(c, xh.dot / 2.0 + 1.0, Color(0, 0, 0, 0.85))
		draw.draw_circle(c, xh.dot / 2.0, col)
	if L <= 0 and xh.dot <= 0:
		draw.draw_circle(c, 1.5, col)
