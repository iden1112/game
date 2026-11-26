extends Node3D
## 훈련장 1v1 (Godot) — 경기 진행

const G = preload("res://scripts/game_data.gd")
const WorldScript = preload("res://scripts/world.gd")
const CombatScript = preload("res://scripts/combat.gd")
const NavScript = preload("res://scripts/nav.gd")
const PlayerScript = preload("res://scripts/player.gd")
const BotScript = preload("res://scripts/bot.gd")
const HudScript = preload("res://scripts/hud.gd")
const MenusScript = preload("res://scripts/menus.gd")
const RangeScript = preload("res://scripts/range.gd")
const NetScript = preload("res://scripts/net.gd")
const MpScript = preload("res://scripts/mp.gd")
const AuthScript = preload("res://scripts/auth.gd")
const SocialScript = preload("res://scripts/social.gd")

var auth
var social
var net
var mpx # 온라인 경기 (mp.gd)
var mp := false # 지금 온라인 경기 중인지

var world
var combat
var nav
var hud
var menus
var range_mode
var camera: Camera3D
var player
var bot

var state := "menu" # menu | pre | live | post | over | range
var round_no := 0
var score_p := 0
var score_b := 0
var pre_t := 0.0
var round_left := 0.0
var post_t := 0.0
var shake := 0.0
var dealt := {}
var _menu_open := false
var _last_beep := 0

# 자동 테스트 (명령줄: -- --autotest [--map=id] [--diff=n] [--range] [--shot=경로] [--shot-frame=n]
#              온라인: --mphost=R코드 [--mpsize=n] [--mpffa] [--mpbots] [--mpmap=id] / --mpjoin=R코드)
var _auto := false
var _shot_path := ""
var _shot_frame := 120
var _frames := 0
var _auto_range := false
var _mp_test := ""
var _mp_opts := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--autotest":
			_auto = true
		elif a == "--range":
			_auto_range = true
		elif a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-frame="):
			_shot_frame = int(a.substr(13))
		elif a.begins_with("--map="):
			Settings.map_id = a.substr(6)
		elif a.begins_with("--diff="):
			Settings.difficulty = int(a.substr(7))
		elif a.begins_with("--mphost="):
			_mp_test = "host:" + a.substr(9)
		elif a.begins_with("--mpjoin="):
			_mp_test = "join:" + a.substr(9)
		elif a.begins_with("--mpsize="):
			_mp_opts.size = int(a.substr(9))
		elif a == "--mpffa":
			_mp_opts.ffa = true
		elif a == "--mpbots":
			_mp_opts.bots = true
		elif a.begins_with("--mpmap="):
			_mp_opts.map = a.substr(8)
		elif a.begins_with("--mpwait="):
			_mp_opts.wait = int(a.substr(9))
	if _auto:
		Sfx.muted = true
	world = Node3D.new()
	world.set_script(WorldScript)
	add_child(world)
	combat = Node3D.new()
	combat.set_script(CombatScript)
	combat.game = self
	combat.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(combat)
	nav = NavScript.new()
	camera = Camera3D.new()
	camera.near = 0.03
	camera.far = 900.0
	add_child(camera)
	camera.make_current()
	player = CharacterBody3D.new()
	player.set_script(PlayerScript)
	player.game = self
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.attach_camera(camera)
	bot = CharacterBody3D.new()
	bot.set_script(BotScript)
	bot.game = self
	bot.display_name = "봇"
	bot.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(bot)
	for a in [player, bot]:
		a.died.connect(_on_died)
	player.damaged.connect(_on_player_damaged)
	range_mode = RangeScript.new()
	range_mode.game = self
	add_child(range_mode)
	auth = Node.new()
	auth.set_script(AuthScript)
	add_child(auth)
	social = Node.new()
	social.set_script(SocialScript)
	social.auth = auth
	add_child(social)
	if social.data.nick == "" and Settings.nick != "":
		social.data.nick = Settings.nick # 전에 쓰던 닉네임은 그대로
	elif social.data.nick != "":
		Settings.nick = social.data.nick
	auth.changed.connect(func():
		if auth.logged_in():
			social._register_topics()
		social.changed.emit())
	net = Node.new()
	net.set_script(NetScript)
	add_child(net)
	mpx = Node.new()
	mpx.set_script(MpScript)
	mpx.game = self
	mpx.net = net
	add_child(mpx)
	hud = CanvasLayer.new()
	hud.set_script(HudScript)
	hud.game = self
	add_child(hud)
	menus = CanvasLayer.new()
	menus.set_script(MenusScript)
	menus.game = self
	add_child(menus)
	player.set_loadout(Settings.get_loadout())
	bot.set_loadout(bot.pick_loadout())
	apply_quality()
	for a in args:
		if a.begins_with("--dumpmaps="):
			_dump_maps(a.substr(11))
			return
	if "--authtest" in args:
		_auth_test()
		return
	if _mp_test != "":
		_start_mp_test()
	elif _auto:
		if _auto_range:
			start_range()
		else:
			player.auto_target = "enemy"
			start_match()
	else:
		go_menu()
		social.start()
		# 처음이면 닉네임 정하기 (로그인 창에서)
		if social.data.nick == "":
			menus.open_login()


# ================= 공용 =================
func actors() -> Array:
	if state == "range":
		return [player] + range_mode.dummies
	if mp:
		return mpx.actor_list()
	return [player, bot]


func same_team(a, b) -> bool:
	if a == null or b == null or a == b:
		return false
	if mp and mpx.is_ffa():
		return false
	return a.team >= 0 and a.team == b.team


func is_live() -> bool:
	return state == "live" and not get_tree().paused


func can_look() -> bool:
	return state in ["pre", "live", "post", "range"] and not get_tree().paused and not _menu_open


func damage_allowed() -> bool:
	return state == "live" or state == "range"


func camera_pos() -> Vector3:
	return camera.global_position


func apply_quality() -> void:
	var q: String = Settings.quality
	if world.sun:
		world.sun.shadow_enabled = q != "low"
	get_viewport().msaa_3d = Viewport.MSAA_2X if q == "high" else Viewport.MSAA_DISABLED
	get_viewport().scaling_3d_scale = 1.0 if q != "low" else 0.75


func _capture(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func score_text() -> String:
	if mp:
		return mpx.score_text()
	return "%s    %d  :  %d    %s" % [player.display_name, score_p, score_b, bot.display_name]


# ================= 메뉴 =================
func go_menu() -> void:
	get_tree().paused = false
	if mpx.in_room():
		mpx.leave()
	mp = false
	player.team = -1
	state = "menu"
	_menu_open = false
	combat.clear()
	range_mode.clear()
	for p in [menus.pause_panel, menus.end_panel, menus.range_panel, menus.loadout_panel, menus.mp_panel]:
		p.visible = false
	menus.show_start(true)
	hud.show_dealt({})
	preview_map()
	_capture(false)


func preview_map() -> void:
	world.build(Settings.map_id)
	player.visible = false
	bot.visible = false
	var b: Rect2 = world.bounds
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(-0.35, PI * 0.85, 0)), Vector3(b.position.x * 0.2, 9.0, b.end.y * 0.55))
	camera.fov = 70


func on_menu_open(open: bool) -> void:
	_menu_open = open
	if state in ["pre", "live", "post", "range"]:
		_capture(not open and not get_tree().paused)


func toggle_loadout() -> void:
	if menus.loadout_panel.visible:
		menus.close_loadout()
	elif state in ["menu", "pre", "range"]:
		menus.open_loadout()
	else:
		hud.toast("라운드가 시작되면 총을 바꿀 수 없어요")


func on_loadout_changed() -> void:
	if state in ["pre", "range"]:
		var keep_pos: Vector3 = player.global_position
		var keep_yaw: float = player.rotation.y
		player.set_loadout(Settings.get_loadout())
		hud.refresh_slots()
		player.global_position = keep_pos
		player.rotation.y = keep_yaw


func set_paused(p: bool) -> void:
	if state in ["menu", "over"]:
		return
	# 온라인 경기는 멈추지 않아요 (메뉴만 열려요)
	if not mp:
		get_tree().paused = p
	menus.pause_panel.visible = p
	_menu_open = p and mp
	_capture(not p and not menus.any_open())


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_ESCAPE:
			if menus.loadout_panel.visible:
				menus.close_loadout()
			elif menus.range_panel.visible:
				menus.toggle_range_menu()
			elif state != "menu" and state != "over":
				set_paused(not menus.pause_panel.visible)
			return
		if state == "range" and Settings.action_of(e) == "score":
			menus.toggle_range_menu()
			get_viewport().set_input_as_handled()
			return
		if state == "menu" and Settings.action_of(e) == "loadout":
			toggle_loadout()
	if e is InputEventMouseButton and e.pressed and state in ["pre", "live", "post", "range"] and not get_tree().paused and not menus.any_open():
		_capture(true)


# ================= AI 대전 =================
func start_match() -> void:
	if mpx.in_room():
		if mpx.net.host:
			mpx.start_game()
		else:
			hud.toast("방장이 다시 시작할 수 있어요")
		return
	mp = false
	player.team = -1
	bot.team = -1
	bot.target = player
	get_tree().paused = false
	menus.show_start(false)
	menus.end_panel.visible = false
	menus.pause_panel.visible = false
	range_mode.clear()
	world.build(Settings.map_id)
	nav.build(world)
	bot.level = G.BOT_LEVELS[Settings.difficulty]
	player.display_name = Settings.nick if Settings.nick != "" else "나"
	score_p = 0
	score_b = 0
	round_no = 0
	for a in [player, bot]:
		a.kills = 0
		a.deaths = 0
		a.heads = 0
	_new_round()
	_capture(true)


func _new_round() -> void:
	round_no += 1
	combat.clear()
	player.visible = true
	bot.visible = true
	player.set_loadout(Settings.get_loadout())
	bot.set_loadout(bot.pick_loadout())
	var side := round_no % 2 == 0
	var sz: float = absf(world.spawn_z)
	var pz := sz if side else -sz
	player.reset_for_round(Vector3(randf_range(-5, 5), 0.05, pz), PI if pz < 0 else 0.0, Settings.armor)
	bot.reset_for_round(Vector3(randf_range(-5, 5), 0.05, -pz), 0.0 if pz < 0 else PI, Settings.armor)
	bot.round_start(side)
	state = "pre"
	pre_t = 10.0 if round_no == 1 else 8.0
	round_left = G.ROUND_TIME
	dealt = {}
	hud.show_dealt({})
	hud.refresh_slots()
	hud.message("라운드 %d" % round_no, "~ 키로 총 바꾸기 · %d점 먼저 따면 승리" % G.WIN_SCORE, 3.0)
	_log("라운드 %d 시작 (%d : %d) · 맵 %s · 내 총 %s / 봇 총 %s" % [round_no, score_p, score_b, world.map_id, player.weapons[0].id, bot.weapons[0].id])


func _go_live() -> void:
	if mp:
		mpx.go_live_host()
	state = "live"
	Sfx.beep(990, 0.25, 0.3)
	hud.message("전투 시작!", "", 1.2)
	if menus.loadout_panel.visible:
		menus.close_loadout()


func _on_died(victim, killer, info: Dictionary) -> void:
	if mp:
		mpx.on_actor_died(victim, killer, info)
		return
	if state != "live" or victim == null or not (victim == player or victim == bot):
		return
	var p_win: bool = victim != player
	if p_win:
		score_p += 1
	else:
		score_b += 1
	var head: String = " [헤드샷]" if info.get("head", false) else ""
	var dist: String = (" %dm" % int(info.dist)) if info.has("dist") else ""
	var kname: String = victim.display_name if (killer == null or killer == victim) else killer.display_name
	hud.add_feed("%s  [%s]  %s%s%s" % [kname, info.get("weapon", ""), victim.display_name, head, dist], killer == player)
	if p_win:
		hud.message("라운드 승리", "%s%s%s" % [info.get("weapon", ""), " · 헤드샷" if head != "" else "", dist], 3.5, "win")
	else:
		hud.message("라운드 패배", "%s의 %s%s" % [bot.display_name, info.get("weapon", ""), dist], 3.5, "lose")
	_log("라운드 %d 끝: %s 승 (%d : %d) · %s%s%s · %.0f초" % [round_no, "나" if p_win else "봇", score_p, score_b, info.get("weapon", ""), head, dist, G.ROUND_TIME - round_left])
	state = "post"
	post_t = 4.0
	hud.show_dealt(dealt)


func _time_up() -> void:
	if mp:
		mpx.time_up()
		return
	var ph: float = player.health
	var eh: float = bot.health
	var res := 0 if absf(ph - eh) < 0.5 else (1 if ph > eh else -1)
	if res > 0:
		score_p += 1
		hud.message("시간 종료", "체력이 더 많아서 승리", 3.0, "win")
	elif res < 0:
		score_b += 1
		hud.message("시간 종료", "체력이 더 적어서 패배", 3.0, "lose")
	else:
		hud.message("시간 종료", "무승부 - 점수 없음", 3.0)
	_log("라운드 %d 시간 종료 (%d : %d)" % [round_no, score_p, score_b])
	state = "post"
	post_t = 3.5
	hud.show_dealt(dealt)


func _end_match() -> void:
	state = "over"
	var win := score_p > score_b
	menus.show_end(win, "%d : %d" % [score_p, score_b], false)
	_capture(false)
	_log("경기 끝: %s (%d : %d)" % ["승리" if win else "패배", score_p, score_b])
	if _auto:
		get_tree().quit()


func on_bullet_hit(owner, victim, part: String, dmg: float, dist: float, _st: Dictionary) -> void:
	if owner == player and victim != player:
		if not (mp and victim.get("is_remote")): # 온라인 상대는 상대 컴퓨터가 'dealt' 로 알려줘요
			var k: String = victim.display_name
			if not dealt.has(k):
				dealt[k] = {"dmg": 0.0, "hits": 0}
			dealt[k].dmg += dmg
			dealt[k].hits += 1
		if state == "range":
			range_mode.on_hit(victim, part, dmg, dist)


func on_player_fire() -> void:
	if state == "range":
		range_mode.shots += 1


func _on_player_damaged(_a, amount: float, from, _info: Dictionary) -> void:
	if from and from != player:
		hud.hurt(from.global_position)
	Sfx.hurt()
	shake = maxf(shake, minf(0.6, amount / 60.0))
	if mp:
		mpx.on_local_damaged(player, amount, from)


# ================= 온라인 =================
## 방장이 라운드를 시작했어요 (mp.gd 에서)
func mp_round(m: Dictionary, n: int) -> void:
	mp = true
	get_tree().paused = false
	menus.show_start(false)
	for p in [menus.mp_panel, menus.end_panel, menus.pause_panel]:
		p.visible = false
	_menu_open = false
	range_mode.clear()
	combat.clear()
	if world.map_id != str(m.get("map", "arena")):
		world.build(str(m.get("map", "arena")))
	nav.build(world)
	bot.visible = false
	bot.global_position = Vector3(0, -60, 0)
	player.display_name = mpx.my_name
	round_no = n
	state = "pre"
	pre_t = 10.0 if n == 1 else 8.0
	round_left = G.ROUND_TIME
	dealt = {}
	hud.show_dealt({})
	_capture(true)


func mp_end_match() -> void:
	state = "over"
	_capture(false)
	var me: int = mpx.my_team
	var sc: Array = mpx.score
	var txt := ""
	var win := false
	if mpx.is_ffa():
		var rank := []
		for p in mpx.lobby.players:
			rank.append([("나" if p.id == net.my_id else str(p.name)), int(sc[int(p.team)]) if int(p.team) < sc.size() else 0])
		rank.sort_custom(func(a, b): return a[1] > b[1])
		var mine := int(sc[me]) if me < sc.size() else 0
		var my_rank := 1
		for r in rank:
			if r[1] > mine:
				my_rank += 1
		win = my_rank == 1
		for i in rank.size():
			txt += "%d. %s — %d점\n" % [i + 1, rank[i][0], rank[i][1]]
		menus.show_end(win, txt, true, "1등!" if win else "%d등" % my_rank)
	else:
		win = int(sc[me]) > int(sc[1 - me])
		txt = "%d : %d" % [int(sc[me]), int(sc[1 - me])]
		menus.show_end(win, txt, true)
	_log("경기 끝: %s %s" % ["승리" if win else "패배", txt.replace("\n", " / ")])
	if _auto:
		get_tree().quit()


func mp_to_lobby() -> void:
	state = "menu"
	combat.clear()
	for a in mpx.actor_list():
		a.visible = false
	menus.end_panel.visible = false
	menus.open_mp()
	_capture(false)


func spectate_target():
	return mpx.spectate_target() if mp else null


# ================= 훈련장 =================
func start_range() -> void:
	get_tree().paused = false
	menus.show_start(false)
	combat.clear()
	state = "range"
	mp = false
	player.team = -1
	bot.visible = false
	bot.global_position = Vector3(0, -50, 0)
	player.visible = true
	player.display_name = Settings.nick if Settings.nick != "" else "나"
	range_mode.start()
	nav.build(world)
	player.set_loadout(Settings.get_loadout())
	player.reset_for_round(Vector3(0, 0.05, world.spawn_z), 0.0, Settings.armor)
	hud.refresh_slots()
	hud.message("훈련장", "Tab 메뉴 · ~ 총 고르기 · 마음껏 쏴 보세요", 3.0)
	_capture(true)
	if _auto:
		player.auto_target = range_mode.dummies[2]


# ================= 매 프레임 =================
func _process(dt: float) -> void:
	_frames += 1
	if _shot_path != "" and _frames == _shot_frame:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("screenshot saved: ", _shot_path)
		if not _auto:
			get_tree().quit()
	mpx.update(dt)
	if not get_tree().paused:
		match state:
			"pre":
				if not _menu_open or _auto or mp:
					pre_t -= dt
				var s := ceili(pre_t)
				if s != _last_beep and s <= 3 and s > 0:
					Sfx.beep(660)
					_last_beep = s
				if pre_t <= 0.0 and (not mp or net.host or pre_t < -1.5):
					_go_live()
			"live":
				round_left -= dt
				if round_left <= 0.0 and (not mp or net.host):
					_time_up()
			"post":
				post_t -= dt
				if post_t <= 0.0:
					if mp:
						if net.host:
							post_t = 999.0
							mpx.after_post()
					elif maxi(score_p, score_b) >= G.WIN_SCORE:
						_end_match()
					else:
						_new_round()
	if menus.mp_panel.visible:
		menus.update_mp()
	shake = maxf(0.0, shake - dt * 2.0)
	if state != "menu":
		player.update_view(dt, shake)
	if state == "range":
		hud.range_lb.text = range_mode.hud_text()
	hud.update(dt)


func _log(s: String) -> void:
	if _auto:
		print(s)


# ================= 테스트 도우미 =================
func _dump_maps(path: String) -> void:
	var out := {}
	for id in world.MAPS:
		if id == "range":
			continue
		world.build(id)
		var arr := []
		for b in world.boxes:
			if b.kind == "ground":
				continue
			arr.append([snappedf(b.min.x, 0.001), snappedf(b.min.y, 0.001), snappedf(b.min.z, 0.001), snappedf(b.max.x, 0.001), snappedf(b.max.y, 0.001), snappedf(b.max.z, 0.001)])
		out[id] = arr
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("dumped ", out.size(), " maps")
	get_tree().quit()


func _auth_test() -> void:
	Sfx.muted = true
	go_menu()
	var e: String = await auth.sign_in("nobody-test-%d@example.com" % (randi() % 100000), "x12345678")
	print("[auth] 없는 계정 로그인 결과: ", e)
	social.start()
	for i in 60:
		await get_tree().create_timer(0.25).timeout
		if social.is_ok():
			break
	print("[social] 친구 서버 연결: ", social.is_ok())
	get_tree().quit()


func _start_mp_test() -> void:
	Sfx.muted = true
	_auto = true
	player.auto_target = "enemy"
	go_menu()
	var parts := _mp_test.split(":")
	if parts[0] == "host":
		mpx.host_room("방장봇", parts[1])
		if _mp_opts.get("ffa", false):
			mpx.set_ffa()
		elif _mp_opts.has("size"):
			mpx.set_size(int(_mp_opts.size))
		if _mp_opts.has("map"):
			mpx.set_map(str(_mp_opts.map))
		if _shot_path != "":
			menus.open_mp()
			mpx.fill_bots()
		var need := int(_mp_opts.get("wait", 1)) # 기다릴 사람 수
		var started := [false]
		mpx.changed.connect(func():
			var humans: int = mpx.lobby.players.filter(func(p): return not p.get("bot", false)).size()
			if not started[0] and humans >= 1 + need:
				started[0] = true
				_log("[mp] 사람 %d명 모임 → 시작" % humans)
				if _mp_opts.get("bots", false):
					mpx.fill_bots()
				get_tree().create_timer(1.0).timeout.connect(mpx.start_game))
	else:
		mpx.join_room(parts[1], "참가봇%d" % (randi() % 90 + 10))
	mpx.changed.connect(func(): _log("[net] " + mpx.status + " · 서버 %d/%d" % [net.live_count(), net.server_count()]))
