extends CanvasLayer
## 메뉴 화면: 시작 · 총 고르기 · 설정 · 일시정지 · 경기 끝 · 훈련장 메뉴

const G = preload("res://scripts/game_data.gd")

var game
var root: Control
var start_panel: Control
var loadout_panel: Control
var pause_panel: Control
var end_panel: Control
var range_panel: Control
var lb_end_title: Label
var lb_end_score: Label
var _lo_slot := 0
var _lo_cat := "AR"
var _lo_list: Array = []
var _lo_guns: GridContainer
var _lo_detail: VBoxContainer
var _lo_slots: HBoxContainer
var _lo_cats: HBoxContainer
var _wait_key := ""
var _key_buttons := {}
var _nick: LineEdit


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	var font: Font = load("res://fonts/NanumGothic-Regular.ttf") # 게임에 넣은 한글 글꼴 (웹에서도 한글이 보이게)
	th.default_font = font
	th.default_font_size = 15
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(1, 0.82, 0.29)
	bs.set_corner_radius_all(4)
	bs.set_content_margin_all(10)
	var bh := bs.duplicate()
	bh.bg_color = Color(1, 0.88, 0.45)
	th.set_stylebox("normal", "Button", bs)
	th.set_stylebox("hover", "Button", bh)
	th.set_stylebox("pressed", "Button", bh)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color(0.07, 0.07, 0.07))
	th.set_color("font_hover_color", "Button", Color(0.07, 0.07, 0.07))
	th.set_color("font_pressed_color", "Button", Color(0.07, 0.07, 0.07))
	root.theme = th
	add_child(root)
	_build_start()
	_build_loadout()
	_build_pause()
	_build_end()
	_build_range()
	_build_mp()
	_build_login()
	_build_friends()
	_notes = VBoxContainer.new()
	_notes.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_notes.position = Vector2(-330, 14)
	_notes.custom_minimum_size.x = 310
	root.add_child(_notes)
	game.auth.changed.connect(refresh_auth)
	game.social.changed.connect(_refresh_friends)
	game.social.note.connect(_on_note)
	refresh_auth()


# ---------- 도우미 ----------
func _overlay() -> Control:
	var o := ColorRect.new()
	o.color = Color(0.03, 0.04, 0.05, 0.62)
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.visible = false
	root.add_child(o)
	return o


func _panel(parent: Control, w: float) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.96)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(24)
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.custom_minimum_size.x = w
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	parent.add_child(p)
	return v


func _lbl(parent: Control, t: String, size := 14, col := Color(0.8, 0.84, 0.86)) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _btn(parent: Control, t: String, cb: Callable, sub := false) -> Button:
	var b := Button.new()
	b.text = t
	if sub:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(1, 1, 1, 0.1)
		s.set_corner_radius_all(4)
		s.set_content_margin_all(10)
		var sh := s.duplicate()
		sh.bg_color = Color(1, 1, 1, 0.18)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", sh)
		b.add_theme_stylebox_override("pressed", sh)
		b.add_theme_color_override("font_color", Color(0.93, 0.93, 0.93))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _row(parent: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	parent.add_child(h)
	return h


func _option(parent: Control, items: Array, sel: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.selected = sel
	o.item_selected.connect(cb)
	parent.add_child(o)
	return o


func _slider(parent: Control, lo: float, hi: float, step: float, val: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size.x = 220
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := Label.new()
	v.text = str(val)
	v.custom_minimum_size.x = 44
	s.value_changed.connect(func(x): v.text = str(snappedf(x, step)); cb.call(x))
	parent.add_child(s)
	parent.add_child(v)
	return s


# ================= 시작 화면 =================
func _build_start() -> void:
	start_panel = _overlay()
	var v := _panel(start_panel, 900)
	var title := _lbl(v, "훈련장 1v1", 44, Color(1, 0.82, 0.29))
	title.add_theme_font_size_override("font_size", 44)
	_lbl(v, "배틀그라운드 훈련장 스타일 1대1 · AI 대전 · 사격 훈련장 · 7점 선승 · PC 전용", 13, Color(0.6, 0.64, 0.68))
	var r := _row(v)
	_lbl(r, "닉네임")
	_nick = LineEdit.new()
	_nick.text = Settings.nick
	_nick.placeholder_text = "닉네임을 정하세요"
	_nick.max_length = 12
	_nick.custom_minimum_size.x = 240
	_nick.text_changed.connect(func(t): Settings.nick = t.strip_edges(); Settings.save_settings())
	r.add_child(_nick)
	var r2 := _row(v)
	_btn(r2, "AI 대전", func(): game.start_match())
	_btn(r2, "친구와 대전", func(): open_mp())
	_btn(r2, "훈련장", func(): game.start_range())
	_btn(r2, "총 고르기 (~)", func(): open_loadout(), true)
	var ra := _row(v)
	_auth_lbl = _lbl(ra, "", 13)
	_auth_btn = _btn(ra, "로그인 / 회원가입", func(): _auth_click(), true)
	_friends_btn = _btn(ra, "친구", func(): open_friends(), true)
	var r3 := _row(v)
	_lbl(r3, "맵")
	var maps: Array = []
	for id in game.world.MAP_ORDER:
		maps.append(game.world.MAPS[id].name)
	_option(r3, maps, maxi(0, game.world.MAP_ORDER.find(Settings.map_id)), func(i): Settings.map_id = game.world.MAP_ORDER[i]; Settings.save_settings(); game.preview_map())
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	v.add_child(cols)
	var keys := _lbl(cols, "조작\nWASD 이동 · Shift 달리기 (조준 중엔 숨 참기)\nSpace 점프 · 낮은 벽/상자 앞에서 누르면 넘기·올라가기\nC 앉기 · Z 엎드리기 · Q/E 기울이기\nV 1인칭 ↔ 3인칭 · Alt 누르고 있으면 둘러보기\n좌클릭 사격 · 우클릭 짧게 = 조준, 길게 = 견착\n조준경 3배율 이상: 마우스 휠로 배율 조절 · Tab 점수판\nR 재장전 · B 단발/점사/연사 · 1 2 3 무기 · 휠 무기 바꾸기\nG/5 수류탄 (다시 누르면 연막·섬광) · 좌클릭 꾹 = 안전핀, 떼면 던지기\n수류탄 들고 R 쿠킹 · 우클릭 같이 누르고 떼면 낮게 굴리기\n4 구급상자 · X 맨손 · ~ 라운드 시작 전 총 바꾸기 · Esc 일시정지", 12)
	keys.custom_minimum_size.x = 400
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(sv)
	_settings_ui(sv)


func show_start(v: bool) -> void:
	start_panel.visible = v
	if v:
		_nick.text = Settings.nick


# ================= 설정 (탭) =================
func _settings_ui(parent: Control) -> void:
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(440, 250)
	parent.add_child(tabs)
	var g := _tab(tabs, "게임")
	var r := _row(g)
	_lbl(r, "봇 난이도")
	var names := []
	for lv in G.BOT_LEVELS:
		names.append(lv.name)
	_option(r, names, Settings.difficulty, func(i): Settings.difficulty = i; Settings.save_settings())
	r = _row(g)
	_lbl(r, "헬멧·조끼")
	_option(r, ["없음", "1레벨", "2레벨", "3레벨"], Settings.armor, func(i): Settings.armor = i; Settings.save_settings())
	var m := _tab(tabs, "마우스·조작")
	r = _row(m)
	_lbl(r, "마우스 감도")
	_slider(r, 0.2, 3.0, 0.05, Settings.sens, func(x): Settings.sens = x; Settings.save_settings())
	r = _row(m)
	_lbl(r, "조준 감도")
	_slider(r, 0.2, 2.0, 0.05, Settings.ads_sens, func(x): Settings.ads_sens = x; Settings.save_settings())
	r = _row(m)
	_lbl(r, "우클릭")
	var am := ["pubg", "toggle", "hold"]
	_option(r, ["배그식 (짧게: 조준 · 길게: 견착)", "누를 때마다 조준 켜기/끄기", "누르는 동안 조준"], am.find(Settings.aim_mode), func(i): Settings.aim_mode = am[i]; Settings.save_settings())
	for it in [["달리기 방식", "sprint_mode"], ["앉기 방식", "crouch_mode"], ["기울이기 방식", "lean_mode"]]:
		r = _row(m)
		_lbl(r, it[0])
		var k: String = it[1]
		var opts := ["hold", "toggle"]
		_option(r, ["누르는 동안", "토글"], opts.find(Settings.get(k)), func(i): Settings.set(k, opts[i]); Settings.save_settings())
	# 키 설정
	var kt := _tab(tabs, "키 설정")
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(420, 210)
	kt.add_child(sc)
	var kv := VBoxContainer.new()
	sc.add_child(kv)
	for grp in Settings.KEY_ACTIONS:
		_lbl(kv, grp[0], 13, Color(1, 0.82, 0.29))
		for a in grp[1]:
			var kr := _row(kv)
			var l := _lbl(kr, a[0])
			l.custom_minimum_size.x = 200
			var act: String = a[1]
			var b := _btn(kr, Settings.key_label(Settings.key_for(act)), func(): _start_rebind(act), true)
			b.custom_minimum_size.x = 120
			_key_buttons[act] = b
	_btn(kv, "기본 키로 되돌리기", func(): Settings.keys = {}; Settings.save_settings(); _refresh_keys(), true)
	var vt := _tab(tabs, "화면")
	r = _row(vt)
	_lbl(r, "시야각")
	_slider(r, 60, 95, 1, Settings.fov, func(x): Settings.fov = x; Settings.save_settings())
	r = _row(vt)
	_lbl(r, "그래픽 품질")
	var qs := ["high", "mid", "low"]
	_option(r, ["높음 (예쁘게)", "보통", "낮음 (빠르게)"], qs.find(Settings.quality), func(i): Settings.quality = qs[i]; Settings.save_settings(); game.apply_quality())
	r = _row(vt)
	_btn(r, "전체화면 켜기/끄기", _toggle_full, true)
	var st := _tab(tabs, "소리")
	r = _row(st)
	_lbl(r, "음량")
	_slider(r, 0.0, 1.0, 0.05, Settings.volume, func(x): Settings.volume = x; Settings.save_settings())
	var xt := _tab(tabs, "조준선")
	r = _row(xt)
	_lbl(r, "모양")
	var ps := ["pubg", "valo", "dot", "tiny", "big", "custom"]
	_option(r, ["배그 기본", "발로란트 기본", "점만", "작은 십자", "큰 십자", "직접 만들기"], ps.find(Settings.xh.get("preset", "pubg")), func(i): _xh_preset(ps[i]))
	r = _row(xt)
	_lbl(r, "색")
	for c in Settings.XH_COLORS:
		var cb := ColorRect.new()
		cb.color = c
		cb.custom_minimum_size = Vector2(22, 22)
		cb.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: Settings.xh.color = c; Settings.save_settings())
		r.add_child(cb)
	for it in [["선 길이", "len", 0, 20], ["선 두께", "th", 1, 6], ["가운데 간격", "gap", 0, 20], ["가운데 점", "dot", 0, 6]]:
		r = _row(xt)
		_lbl(r, it[0])
		var k: String = it[1]
		_slider(r, it[2], it[3], 1, Settings.xh.get(k, 0), func(x): Settings.xh[k] = int(x); Settings.xh.preset = "custom"; Settings.save_settings())
	r = _row(xt)
	_lbl(r, "쏘면 벌어짐")
	_option(r, ["켜기 (배그처럼)", "끄기 (발로란트처럼 고정)"], 0 if Settings.xh.get("dyn", 1) else 1, func(i): Settings.xh.dyn = 1 - i; Settings.save_settings())


func _toggle_full() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _xh_preset(pid: String) -> void:
	Settings.xh.preset = pid
	if Settings.XH_PRESETS.has(pid):
		for k in Settings.XH_PRESETS[pid]:
			Settings.xh[k] = Settings.XH_PRESETS[pid][k]
	Settings.save_settings()


func _pick_gun(id: String) -> void:
	_lo_list[_lo_slot] = {"id": id}
	_refresh_loadout()


func _tab(tabs: TabContainer, name: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = name
	v.add_theme_constant_override("separation", 6)
	tabs.add_child(v)
	return v


func _start_rebind(act: String) -> void:
	_wait_key = act
	_key_buttons[act].text = "키를 누르세요…"


func _refresh_keys() -> void:
	for act in _key_buttons:
		_key_buttons[act].text = Settings.key_label(Settings.key_for(act))


func _input(e: InputEvent) -> void:
	if _wait_key != "" and e is InputEventKey and e.pressed:
		if e.physical_keycode != KEY_ESCAPE:
			# 같은 키를 쓰던 동작은 '없음'
			for g2 in Settings.KEY_ACTIONS:
				for a in g2[1]:
					if a[1] != _wait_key and Settings.key_for(a[1]) == e.physical_keycode:
						Settings.keys[a[1]] = KEY_NONE
			Settings.keys[_wait_key] = e.physical_keycode
			Settings.save_settings()
		_wait_key = ""
		_refresh_keys()
		get_viewport().set_input_as_handled()


# ================= 총 고르기 =================
func _build_loadout() -> void:
	loadout_panel = _overlay()
	var v := _panel(loadout_panel, 1100)
	var top := _row(v)
	_lo_slots = HBoxContainer.new()
	_lo_slots.add_theme_constant_override("separation", 6)
	top.add_child(_lo_slots)
	_lbl(top, "   총을 고르면 풀파츠로 시작해요 · 파츠는 오른쪽에서 바꿀 수 있어요", 12, Color(0.6, 0.64, 0.68))
	_lo_cats = _row(v)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	v.add_child(body)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(520, 430)
	body.add_child(sc)
	_lo_guns = GridContainer.new()
	_lo_guns.columns = 3
	_lo_guns.add_theme_constant_override("h_separation", 6)
	_lo_guns.add_theme_constant_override("v_separation", 6)
	sc.add_child(_lo_guns)
	_lo_detail = VBoxContainer.new()
	_lo_detail.custom_minimum_size.x = 480
	body.add_child(_lo_detail)
	var foot := _row(v)
	_lbl(foot, "~ 또는 Esc 로 닫기", 12, Color(0.6, 0.64, 0.68))
	_btn(foot, "확인", func(): close_loadout())


func open_loadout() -> void:
	_lo_list = Settings.get_loadout()
	_lo_cat = G.weapon(_lo_list[_lo_slot].id).cat
	loadout_panel.visible = true
	_refresh_loadout()
	game.on_menu_open(true)


func close_loadout() -> void:
	if not loadout_panel.visible:
		return
	loadout_panel.visible = false
	Settings.loadout = _lo_list
	Settings.save_settings()
	game.on_loadout_changed()
	game.on_menu_open(false)


func _refresh_loadout() -> void:
	for c in _lo_slots.get_children():
		c.queue_free()
	for i in 3:
		var w := G.weapon(_lo_list[i].id)
		var b := _btn(_lo_slots, "%d번 %s\n%s" % [i + 1, "주무기" if i < 2 else "권총", w.name], func(): _lo_slot = i; _lo_cat = G.weapon(_lo_list[i].id).cat; _refresh_loadout(), i != _lo_slot)
		b.custom_minimum_size.x = 150
	for c in _lo_cats.get_children():
		c.queue_free()
	var cats: Array = ["HG", "SG"] if _lo_slot == 2 else G.CAT_ORDER.filter(func(x): return x != "HG")
	if not (_lo_cat in cats):
		_lo_cat = cats[0]
	for cat in cats:
		_btn(_lo_cats, G.CAT_NAME[cat], func(): _lo_cat = cat; _refresh_loadout(), cat != _lo_cat)
	for c in _lo_guns.get_children():
		c.queue_free()
	for r in G.WEAPON_TABLE:
		var w := G.weapon(r[0])
		if w.cat != _lo_cat or (w.side != (_lo_slot == 2)):
			continue
		var on: bool = _lo_list[_lo_slot].id == w.id
		var b := _btn(_lo_guns, "%s\n%s" % [w.name, w.ammo], _pick_gun.bind(w.id), not on)
		b.custom_minimum_size = Vector2(165, 52)
		b.add_theme_font_size_override("font_size", 13)
	_detail()


func _detail() -> void:
	for c in _lo_detail.get_children():
		c.queue_free()
	var s: Dictionary = _lo_list[_lo_slot]
	var w := G.weapon(s.id)
	var att := G.full_attachments(s.id, s)
	var st := G.weapon_stats(s.id, att)
	_lbl(_lo_detail, "%s   %s · %s" % [w.name, G.CAT_NAME[w.cat], w.ammo], 20, Color.WHITE)
	var modes := []
	for m in w.modes:
		modes.append({"S": "단발", "B": "점사", "A": "연사"}[m])
	_lbl(_lo_detail, "사격 모드: %s · 탄창 %d발 · 재장전 %.1f초 · 탄속 %dm/s%s" % [" / ".join(modes), st.mag, st.reload, int(w.vel), (" · 산탄 %d알" % w.pellets) if w.pellets > 1 else ""], 12)
	var bars := [["피해", w.dmg, 120.0, "%d" % int(w.dmg)], ["연사력", 60.0 / w.interval, 1300.0, "%d RPM" % int(60.0 / w.interval)],
		["수직 반동", st.rv, 7.0, "%.2f" % st.rv], ["수평 반동", st.rh, 1.5, "%.2f" % st.rh], ["조준 속도", 1.0 / st.adsTime, 8.0, "%.2f초" % st.adsTime]]
	for b in bars:
		var r := _row(_lo_detail)
		var l := _lbl(r, b[0], 12)
		l.custom_minimum_size.x = 70
		var pb := ProgressBar.new()
		pb.max_value = b[2]
		pb.value = b[1]
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(260, 8)
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(pb)
		_lbl(r, b[3], 12)
	_lbl(_lo_detail, "파츠", 13, Color(1, 0.82, 0.29))
	var groups := [["scope", "조준경", G.scope_options(w)], ["muzzle", "총구", G.muzzle_options(w)], ["grip", "손잡이", G.grip_options(w)], ["mag", "탄창", G.mag_options(w)], ["stock", "개머리판", G.stock_options(w)]]
	for gr in groups:
		var opts: Array = gr[2]
		if opts.is_empty():
			continue
		var key: String = gr[0]
		var r := _row(_lo_detail)
		var l := _lbl(r, gr[1], 12)
		l.custom_minimum_size.x = 60
		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(flow)
		var all: Array = opts.duplicate()
		if key != "scope":
			all.append("")
		for o in all:
			var name: String = "없음" if o == "" else (G.SCOPES.filter(func(x): return x.id == o)[0].name if key == "scope" else G.ATT_NAME[key][o])
			var on: bool = (att.get(key) == null and o == "") or att.get(key) == o
			var b := _btn(flow, name, func(): _lo_list[_lo_slot][key] = o; _refresh_loadout(), not on)
			b.add_theme_font_size_override("font_size", 12)
		if att.get(key) != null and key != "scope" and G.ATT_FX[key].has(att[key]):
			_lbl(_lo_detail, "      " + G.ATT_FX[key][att[key]].d, 11, Color(0.62, 0.89, 0.66))


# ================= 일시정지 / 끝 / 훈련장 =================
func _build_pause() -> void:
	pause_panel = _overlay()
	var v := _panel(pause_panel, 560)
	_lbl(v, "일시정지", 30, Color.WHITE)
	_settings_ui(v)
	var r := _row(v)
	_btn(r, "계속하기", func(): game.set_paused(false))
	_btn(r, "총 고르기", func(): open_loadout(), true)
	_btn(r, "처음 화면", func(): game.go_menu(), true)


func _build_end() -> void:
	end_panel = _overlay()
	var v := _panel(end_panel, 460)
	lb_end_title = _lbl(v, "승리!", 60, Color.WHITE)
	lb_end_score = _lbl(v, "7 : 0", 40, Color.WHITE)
	var r := _row(v)
	_end_again = _btn(r, "다시 하기", func(): game.start_match())
	_end_lobby = _btn(r, "대기실로 (맵 바꾸기 · 친구 받기)", func(): game.mpx.to_lobby(), true)
	_end_menu = _btn(r, "처음 화면 (맵 바꾸기)", func(): game.go_menu(), true)


var _end_again: Button
var _end_lobby: Button
var _end_menu: Button


func show_end(win: bool, text: String, online := false, title := "") -> void:
	lb_end_title.text = title if title != "" else ("승리!" if win else "패배")
	lb_end_title.add_theme_color_override("font_color", Color(0.49, 0.84, 1.0) if win else Color(1, 0.48, 0.42))
	lb_end_score.text = text
	lb_end_score.add_theme_font_size_override("font_size", 18 if "\n" in text else 40)
	_end_again.visible = not online or game.net.host
	_end_again.text = "같은 방식으로 다시" if online else "다시 하기"
	_end_lobby.visible = online
	_end_menu.text = "방 나가기" if online else "처음 화면 (맵 바꾸기)"
	end_panel.visible = true


func _build_range() -> void:
	range_panel = _overlay()
	var v := _panel(range_panel, 620)
	_lbl(v, "훈련장 메뉴", 28, Color.WHITE)
	_lbl(v, "과녁: 맞히면 쓰러졌다가 다시 일어나요 · 허수아비: 방어구 레벨별로 서 있어요 (피해·부위·거리가 왼쪽에 나와요)", 12)
	var r := _row(v)
	_btn(r, "과녁 움직이기 켜기/끄기", func(): game.range_mode.toggle_moving())
	_btn(r, "허수아비 방어구 바꾸기", func(): game.range_mode.cycle_dummy_armor(), true)
	var r2 := _row(v)
	_btn(r2, "닫기 (Tab)", func(): toggle_range_menu())
	_btn(r2, "기록 지우기", func(): game.range_mode.reset_stats(), true)
	_btn(r2, "처음 화면", func(): game.go_menu(), true)


# ================= 로그인 =================
var _auth_lbl: Label
var _auth_btn: Button
var _friends_btn: Button
var login_panel: Control
var _lg_title: Label
var _lg_nickbox: VBoxContainer
var _lg_nick: LineEdit
var _lg_email: LineEdit
var _lg_pw: LineEdit
var _lg_msg: Label
var _lg_login: Button
var _lg_signup: Button
var _lg_guest: Button


func _build_login() -> void:
	login_panel = _overlay()
	var v := _panel(login_panel, 420)
	_lg_title = _lbl(v, "로그인", 28, Color.WHITE)
	_lbl(v, "로그인하지 않아도 게임은 할 수 있어요. 웹 버전과 같은 계정이에요.", 12)
	_lg_nickbox = VBoxContainer.new()
	v.add_child(_lg_nickbox)
	_lbl(_lg_nickbox, "닉네임", 13, Color(1, 0.82, 0.29))
	_lg_nick = LineEdit.new()
	_lg_nick.placeholder_text = "2~12글자 (비우면 이메일 앞부분)"
	_lg_nick.max_length = 12
	_lg_nickbox.add_child(_lg_nick)
	_lbl(_lg_nickbox, "로그인하면 닉네임이 내 계정에 등록돼서 친구가 찾을 수 있어요. 로그인 없이 시작하면 이 컴퓨터에만 저장돼요.", 11)
	_lg_email = LineEdit.new()
	_lg_email.placeholder_text = "이메일"
	v.add_child(_lg_email)
	_lg_pw = LineEdit.new()
	_lg_pw.placeholder_text = "비밀번호 (6자 이상)"
	_lg_pw.secret = true
	v.add_child(_lg_pw)
	_lg_msg = _lbl(v, "", 12, Color(1, 0.55, 0.48))
	var r := _row(v)
	_lg_login = _btn(r, "로그인", func(): _do_login(false))
	_lg_signup = _btn(r, "회원가입", func(): _do_login(true), true)
	_lg_guest = _btn(r, "로그인 없이 시작", func(): _do_guest())
	_btn(r, "닫기", func(): login_panel.visible = false, true)
	_btn(v, "비밀번호를 잊었어요", func(): _do_reset(), true)
	_lbl(v, "구글 로그인은 웹 버전에서만 돼요.", 11, Color(0.6, 0.64, 0.68))


func open_login() -> void:
	var need_nick: bool = game.social.data.nick == ""
	var li: bool = game.auth.logged_in()
	_lg_nickbox.visible = need_nick
	_lg_email.visible = not li
	_lg_pw.visible = not li
	_lg_login.visible = not li
	_lg_signup.visible = not li
	_lg_guest.visible = need_nick
	_lg_guest.text = "닉네임 정하기" if li else "로그인 없이 시작"
	_lg_title.text = ("닉네임 정하기" if li else "시작하기") if need_nick else "로그인"
	_lg_msg.text = ""
	login_panel.visible = true


func _auth_click() -> void:
	if game.auth.logged_in():
		game.social.on_logout()
		game.auth.sign_out()
	else:
		open_login()


func _after_auth() -> void:
	if game.social.data.nick == "":
		var n := _lg_nick.text.strip_edges()
		if n == "":
			n = game.auth.email.split("@")[0].substr(0, 12)
		_lg_nick.text = n
		_lg_msg.text = "닉네임 확인 중… (3초쯤)"
		var e: String = await game.social.claim_nick(n)
		if e != "":
			_lg_msg.text = e
			open_login()
			_lg_msg.text = e
			return
	login_panel.visible = false
	game.hud.toast("로그인했어요")


func _do_login(signup: bool) -> void:
	var n := _lg_nick.text.strip_edges()
	if game.social.data.nick == "" and n != "" and n.length() < 2:
		_lg_msg.text = "닉네임은 두 글자 이상으로 정해 주세요"
		return
	_lg_msg.text = "가입하는 중…" if signup else "로그인 중…"
	var e: String = await game.auth.sign_in(_lg_email.text.strip_edges(), _lg_pw.text, signup)
	if e != "":
		_lg_msg.text = e
		return
	_lg_pw.text = ""
	_after_auth()


func _do_guest() -> void:
	if _lg_nick.text.strip_edges() == "":
		_lg_msg.text = "닉네임을 입력하세요"
		return
	_lg_msg.text = "닉네임 확인 중…"
	var e: String = await game.social.claim_nick(_lg_nick.text)
	if e != "":
		_lg_msg.text = e
		return
	login_panel.visible = false
	_nick.text = Settings.nick


func _do_reset() -> void:
	var em := _lg_email.text.strip_edges()
	if em == "":
		_lg_msg.text = "위에 이메일을 먼저 입력하세요"
		return
	var e: String = await game.auth.reset_password(em)
	_lg_msg.text = e if e != "" else "비밀번호 재설정 메일을 보냈어요"


func refresh_auth() -> void:
	var a = game.auth
	_auth_lbl.text = ("로그인됨: %s" % (game.social.data.nick if game.social.data.nick != "" else a.email)) if a.logged_in() else "로그인하면 계정이 기억되고 친구 기능을 쓸 수 있어요"
	_auth_btn.text = "로그아웃" if a.logged_in() else "로그인 / 회원가입"
	_nick.text = Settings.nick
	_refresh_friends()


# ================= 친구 =================
var friends_panel: Control
var _fr_me: Label
var _fr_srv: Label
var _fr_input: LineEdit
var _fr_msg: Label
var _fr_list: VBoxContainer
var _notes: VBoxContainer


func _build_friends() -> void:
	friends_panel = _overlay()
	var v := _panel(friends_panel, 540)
	_lbl(v, "친구", 28, Color.WHITE)
	_fr_srv = _lbl(v, "", 12)
	var r := _row(v)
	_fr_me = _lbl(r, "")
	_btn(r, "닉네임 바꾸기", func(): game.social.data.nick = ""; open_login(), true)
	_lbl(v, "친구 추가", 13, Color(1, 0.82, 0.29))
	var r2 := _row(v)
	_fr_input = LineEdit.new()
	_fr_input.placeholder_text = "친구 닉네임"
	_fr_input.max_length = 12
	_fr_input.custom_minimum_size.x = 240
	r2.add_child(_fr_input)
	_btn(r2, "친구 요청", func(): _add_friend())
	_fr_msg = _lbl(v, "", 12)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(500, 260)
	v.add_child(sc)
	_fr_list = VBoxContainer.new()
	_fr_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_fr_list)
	_btn(v, "닫기", func(): friends_panel.visible = false, true)


func open_friends() -> void:
	friends_panel.visible = true
	_fr_msg.text = ""
	_refresh_friends()


func _add_friend() -> void:
	_fr_msg.text = "찾는 중…"
	var r: String = await game.social.add_friend(_fr_input.text)
	_fr_msg.text = r.substr(3) if r.begins_with("ok:") else r
	if r.begins_with("ok:"):
		_fr_input.text = ""


func _refresh_friends() -> void:
	if _fr_list == null:
		return
	var s = game.social
	var n: int = s.req_in.size()
	_friends_btn.text = "친구" + (" (%d)" % n if n > 0 else "")
	if not friends_panel.visible:
		return
	_fr_me.text = "내 닉네임: %s" % (s.data.nick if s.data.nick != "" else "(아직 없음)")
	_fr_srv.text = ("친구 기능은 로그인한 회원만 쓸 수 있어요" if not game.auth.logged_in() else ("친구 서버 연결됨 · " + ("내 닉네임 등록됨" if s.data.reg else "내 닉네임 등록 중…") if s.is_ok() else "친구 서버에 연결하는 중…"))
	for c in _fr_list.get_children():
		c.queue_free()
	if not s.req_in.is_empty():
		_lbl(_fr_list, "받은 친구 요청", 13, Color(1, 0.82, 0.29))
		for fid in s.req_in:
			var r := _row(_fr_list)
			var l := _lbl(r, s.req_in[fid].nick, 15, Color.WHITE)
			l.custom_minimum_size.x = 220
			_btn(r, "받기", func(): s.accept(fid))
			_btn(r, "거절", func(): s.decline(fid), true)
	_lbl(_fr_list, "친구 목록", 13, Color(1, 0.82, 0.29))
	if s.data.friends.is_empty():
		_lbl(_fr_list, "아직 친구가 없어요. 위에 친구 닉네임을 넣고 요청을 보내 보세요.", 12)
	for f in s.data.friends:
		var r := _row(_fr_list)
		var on: bool = s.online.get(f.id, false)
		var l := _lbl(r, ("● " if on else "○ ") + f.nick + ("  접속 중" if on else "  오프라인"), 14, Color(0.5, 0.95, 0.55) if on else Color(0.7, 0.7, 0.7))
		l.custom_minimum_size.x = 260
		var fid: String = f.id
		_btn(r, "방으로 초대", func(): _invite(fid))
		_btn(r, "삭제", func(): s.remove(fid), true)


func _invite(fid: String) -> void:
	if not (game.mpx.in_room() and game.net.host):
		game.mpx.host_room(_my_name())
		open_mp()
	friends_panel.visible = false
	for i in 40:
		if game.net.code != "" and game.net.live_count() > 0:
			break
		await get_tree().create_timer(0.25).timeout
	game.social.invite(fid, game.net.code)
	game.hud.toast("%s 님에게 초대를 보냈어요" % game.social.friend_name(fid))


func _on_note(text: String, code: String, _from: String) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.95)
	sb.border_color = Color(1, 0.82, 0.29, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	p.add_child(v)
	_lbl(v, text, 13, Color.WHITE)
	var r := _row(v)
	if code != "":
		_btn(r, "들어가기", func(): p.queue_free(); _join_invite(code))
	else:
		_btn(r, "보기", func(): p.queue_free(); open_friends())
	_btn(r, "닫기", func(): p.queue_free(), true)
	_notes.add_child(p)
	get_tree().create_timer(30.0 if code != "" else 8.0).timeout.connect(func(): if is_instance_valid(p): p.queue_free())
	Sfx.beep(880, 0.12, 0.25)


func _join_invite(code: String) -> void:
	if game.state != "menu":
		game.go_menu()
	game.mpx.join_room(code, _my_name())
	open_mp()


# ================= 친구와 대전 =================
var mp_panel: Control
var _mp_code: Label
var _mp_status: Label
var _mp_input: LineEdit
var _mp_lobby: VBoxContainer
var _mp_lobby_key := ""


func _build_mp() -> void:
	mp_panel = _overlay()
	var v := _panel(mp_panel, 760)
	_lbl(v, "친구와 대전  1대1 · 2대2 · 3대3 · 4대4 · 개인전", 26, Color.WHITE)
	_lbl(v, "한 명이 방을 만들고 코드를 알려 주면 친구들이 코드로 들어와요. 공유기 설정은 필요 없어요.\n웹 게임 친구도 같이 할 수 있어요: 웹에서 「학교 와이파이용 방」으로 만들거나, 이 방 코드(R로 시작)로 참가하면 돼요.", 12)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	v.add_child(cols)
	var a := VBoxContainer.new()
	cols.add_child(a)
	_lbl(a, "방 만들기", 13, Color(1, 0.82, 0.29))
	_btn(a, "방 만들기", func(): game.mpx.host_room(_my_name()))
	var cr := _row(a)
	_mp_code = _lbl(cr, "-----", 32, Color(1, 0.82, 0.29))
	_btn(cr, "복사", func(): DisplayServer.clipboard_set(game.net.code), true)
	var b := VBoxContainer.new()
	cols.add_child(b)
	_lbl(b, "방 참가", 13, Color(1, 0.82, 0.29))
	var jr := _row(b)
	_mp_input = LineEdit.new()
	_mp_input.placeholder_text = "방 코드 (R…)"
	_mp_input.max_length = 8
	_mp_input.custom_minimum_size.x = 180
	jr.add_child(_mp_input)
	_btn(jr, "참가", func(): _join())
	_mp_status = _lbl(v, "", 13)
	_mp_lobby = VBoxContainer.new()
	_mp_lobby.add_theme_constant_override("separation", 6)
	v.add_child(_mp_lobby)
	var r := _row(v)
	_btn(r, "뒤로", func(): game.mpx.leave(); mp_panel.visible = false; show_start(true), true)
	game.mpx.changed.connect(func(): _mp_lobby_key = "")


func _my_name() -> String:
	return Settings.nick if Settings.nick != "" else "플레이어%d" % (randi() % 90 + 10)


func _join() -> void:
	if _mp_input.text.strip_edges() != "":
		game.mpx.join_room(_mp_input.text, _my_name())


func open_mp() -> void:
	show_start(false)
	mp_panel.visible = true
	_mp_lobby_key = ""
	update_mp()


func update_mp() -> void:
	var M = game.mpx
	var n = game.net
	_mp_code.text = n.code if n.host and n.code != "" else "-----"
	var srv := " · 서버 %d/%d 연결" % [n.live_count(), n.server_count()] if M.in_room() else ""
	_mp_status.text = (M.status if M.status != "" else "방을 만들거나 친구의 방 코드를 입력하세요") + srv
	_mp_status.add_theme_color_override("font_color", Color(1, 0.55, 0.48) if M.status_bad else Color(0.55, 0.85, 1.0))
	var key := JSON.stringify([M.lobby, n.host, M.welcomed])
	if key == _mp_lobby_key:
		return
	_mp_lobby_key = key
	_render_lobby()


## 대기실 (웹 renderLobby 와 같은 모양)
func _render_lobby() -> void:
	var M = game.mpx
	for c in _mp_lobby.get_children():
		c.queue_free()
	var L: Dictionary = M.lobby
	if L.players.is_empty():
		return
	var host: bool = game.net.host
	var me: String = game.net.my_id
	var ffa: bool = L.get("ffa", false)
	var r := _row(_mp_lobby)
	_lbl(r, "경기 방식")
	for n in [1, 2, 3, 4]:
		var on: bool = not ffa and int(L.size) == n
		var b := _btn(r, "%d대%d" % [n, n], func(): M.set_size(n), not on)
		b.disabled = not host
	var fb := _btn(r, "개인전 1v1v1v1", func(): M.set_ffa(), not ffa)
	fb.disabled = not host
	r = _row(_mp_lobby)
	_lbl(r, "맵")
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(flow)
	var maps: Array = M.map_choices()
	var cur = L.get("map")
	if not (cur in maps):
		cur = "random"
	var rb := _btn(flow, "랜덤", func(): M.set_map("random"), cur != "random")
	rb.disabled = not host
	for id in maps:
		var mb := _btn(flow, game.world.MAPS[id].name, func(): M.set_map(id), cur != id)
		mb.disabled = not host
		mb.add_theme_font_size_override("font_size", 12)
	r = _row(_mp_lobby)
	_lbl(r, "헬멧·조끼")
	var arm := int(L.get("armor", Settings.armor))
	for i in 4:
		var ab := _btn(r, ["없음", "1레벨", "2레벨", "3레벨"][i], func(): M.set_armor(i), arm != i)
		ab.disabled = not host
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 12)
	_mp_lobby.add_child(teams)
	var cols: Array = [[-1, "개인전 · 모두가 적이에요", Color(1, 0.82, 0.29), 4]] if ffa else [[0, M.TEAM_NAME[0] + " 팀", M.TEAM_COLOR[0], int(L.size)], [1, M.TEAM_NAME[1] + " 팀", M.TEAM_COLOR[1], int(L.size)]]
	for col in cols:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		teams.add_child(box)
		var ps: Array = L.players if col[0] < 0 else L.players.filter(func(p): return int(p.team) == col[0])
		_lbl(box, "%s  %d/%d" % [col[1], ps.size(), col[3]], 14, col[2])
		for p in ps:
			var pr := _row(box)
			var tag := ("👑 " if p.id == "h" else ("🤖 " if p.get("bot", false) else "")) + str(p.name) + ("  (나)" if p.id == me else "")
			var l := _lbl(pr, tag, 14, Color.WHITE)
			l.custom_minimum_size.x = 170
			if host:
				var pid: String = p.id
				if p.get("bot", false):
					_btn(pr, "AI 빼기", func(): M.kick(pid), true).add_theme_font_size_override("font_size", 11)
				if not ffa:
					_btn(pr, "팀 바꾸기", func(): M.swap(pid), true).add_theme_font_size_override("font_size", 11)
		for i in range(ps.size(), col[3]):
			var er := _row(box)
			_lbl(er, "빈 자리", 13, Color(0.45, 0.45, 0.45)).custom_minimum_size.x = 170
			if host and L.players.size() < 8:
				var t: int = 0 if col[0] < 0 else col[0]
				_btn(er, "+ AI 넣기", func(): M.add_bot(t), true).add_theme_font_size_override("font_size", 11)
	r = _row(_mp_lobby)
	if host:
		_btn(r, "게임 시작", func(): M.start_game())
		_btn(r, "빈자리 모두 AI로 채우기", func(): M.fill_bots(), true)
		_lbl(r, "사람이 부족해도 시작할 수 있어요 · 상대가 없으면 AI가 들어와요", 11)
	else:
		_lbl(r, "방장이 게임을 시작하면 바로 들어가요", 12)


func toggle_range_menu() -> void:
	range_panel.visible = not range_panel.visible
	game.on_menu_open(range_panel.visible)


func any_open() -> bool:
	return loadout_panel.visible or pause_panel.visible or range_panel.visible
