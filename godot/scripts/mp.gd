extends Node
## 친구와 대전 — 웹 게임의 온라인 규칙을 그대로 옮겼어요 (같은 방에서 웹·Godot 같이 가능)
## 1대1 · 2대2 · 3대3 · 4대4 · 개인전(1v1v1v1), 빈자리 AI, 방장이 라운드를 정해요.

signal changed

const G = preload("res://scripts/game_data.gd")
const RemoteScript = preload("res://scripts/remote.gd")
const BotScript = preload("res://scripts/bot.gd")
const TEAM_NAME := ["블루", "레드"]
const TEAM_COLOR := [Color("5aa9ff"), Color("ff6a5a")]
const MY_SHIRT := Color("3d5f8c")
const ENEMY_SHIRT := Color("8a3a30")
const STANCE_CODE := {"stand": 0, "crouch": 1, "prone": 2}

var game
var net
var my_name := ""
var lobby := {"size": 1, "players": []}
var active := false
var welcomed := false
var status := ""
var status_bad := false
var remotes := {} # id → 상대 캐릭터
var bots := {} # id → AI (방장 컴퓨터만)
var score: Array = [0, 0]
var win_to := 7
var my_team := 0
var match_map := ""
var armor := 2
var rtt := 0.0

var _hello_t := 0.0
var _hello_n := 0
var _send_t := 0.0
var _lo_n := 0
var _lo_keys := {}
var _dupe := {}
var _bot_n := 0
var _ping_t := 0.0
var _last_recv := 0
var _shots := {} # 보낼 총알: 보낸 사람 id → {id, o, d}


func _ready() -> void:
	net.recv.connect(_recv)
	net.status_changed.connect(func(): changed.emit())


# ================= 공용 =================
func is_ffa() -> bool:
	return lobby.get("ffa", false)


func in_room() -> bool:
	return net.code != ""


func actor_by_id(id: String):
	if id == net.my_id:
		return game.player
	if remotes.has(id):
		return remotes[id]
	if bots.has(id):
		return bots[id]
	return null


func actor_list() -> Array:
	var out: Array = [game.player]
	for id in remotes:
		out.append(remotes[id])
	for id in bots:
		out.append(bots[id])
	return out


func is_local(a) -> bool:
	return a == game.player or bots.values().has(a)


func team_label(t: int) -> String:
	if is_ffa():
		for p in lobby.players:
			if p.team == t:
				return "나" if p.id == net.my_id else str(p.name)
		return "?"
	return TEAM_NAME[clampi(t, 0, 1)] + " 팀"


func _set_status(s: String, bad := false) -> void:
	status = s
	status_bad = bad
	changed.emit()


# ================= 방 만들기 / 참가 / 나가기 =================
func host_room(name: String, fixed := "") -> void:
	leave()
	my_name = name
	net.host = true
	net.my_id = "h"
	var c: String = fixed if fixed != "" else "R" + net.make_code()
	net.open(c)
	lobby = {"size": 1, "players": [{"id": "h", "name": my_name, "team": 0}], "armor": Settings.armor}
	_set_status("방이 만들어졌어요! 코드 %s 를 알려 주세요 · 웹 게임의 「학교 와이파이용 방 참가」로도 들어올 수 있어요" % c)


func join_room(c: String, name: String) -> void:
	leave()
	my_name = name
	c = c.to_upper().strip_edges()
	var clean := ""
	for ch in c:
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			clean += ch
	if clean.length() < 4:
		_set_status("방 코드를 입력해 주세요", true)
		return
	if not clean.begins_with("R"):
		_set_status("웹의 일반 방(코드가 R로 시작하지 않는 방)은 Godot에서 들어갈 수 없어요. 방장에게 웹에서 「학교 와이파이용 방」으로 만들어 달라고 하세요", true)
		return
	net.host = false
	net.my_id = "c" + net.make_code().to_lower()
	net.open(clean)
	welcomed = false
	_hello_n = 0
	_hello_t = 0.3
	_last_recv = Time.get_ticks_msec()
	_set_status("방 %s 찾는 중…" % clean)


func leave() -> void:
	if in_room():
		net.send({"t": "bye"})
	net.close()
	for id in remotes.keys():
		_remove_remote(id)
	for id in bots.keys():
		_remove_bot(id)
	net.bots.clear()
	lobby = {"size": 1, "players": []}
	active = false
	welcomed = false
	_dupe.clear()
	_lo_keys.clear()
	changed.emit()


# ================= 대기실 (방장) =================
func _host_hello(m: Dictionary) -> void:
	var L := lobby
	var from: String = m.from
	if int(m.get("ver", 0)) != net.NET_VER:
		net.send({"t": "reject", "why": "방장과 게임 파일 버전이 달라요. 모두 가장 새 게임 파일로 받아서 열어 주세요"}, from)
		_set_status("버전이 다른 게임으로 누가 들어오려고 했어요", true)
		return
	for p in L.players:
		if p.id == from:
			net.send({"t": "welcome"}, from)
			net.send({"t": "lobby", "lobby": L}, from)
			return
	if active:
		net.send({"t": "reject", "why": "이미 게임이 시작됐어요"}, from)
		return
	var nm := str(m.get("name", "친구")).substr(0, 12)
	if L.get("ffa", false):
		if L.players.size() >= 4:
			var bt = null
			for i in range(L.players.size() - 1, -1, -1):
				if L.players[i].get("bot", false):
					bt = L.players[i]
					break
			if bt == null:
				net.send({"t": "reject", "why": "방이 꽉 찼어요 (개인전은 4명)"}, from)
				return
			L.players.erase(bt)
		L.players.append({"id": from, "name": nm, "team": 0})
		_ffa_teams()
	else:
		if L.players.size() >= 8:
			var bt = null
			for p in L.players:
				if p.get("bot", false):
					bt = p
					break
			if bt == null:
				net.send({"t": "reject", "why": "방이 꽉 찼어요 (최대 8명)"}, from)
				return
			L.players.erase(bt)
		var team := 0 if _team_count(0) <= _team_count(1) else 1
		if _team_count(team) >= int(L.size):
			var bt = null
			for p in L.players:
				if p.get("bot", false) and p.team == team:
					bt = p
					break
			if bt == null:
				for p in L.players:
					if p.get("bot", false):
						bt = p
						break
			if bt != null:
				L.players.erase(bt)
				team = bt.team
		L.players.append({"id": from, "name": nm, "team": team})
		_auto_size()
	net.send({"t": "welcome"}, from)
	broadcast_lobby()
	Sfx.beep(880, 0.1, 0.2)


func _team_count(t: int) -> int:
	var n := 0
	for p in lobby.players:
		if p.team == t:
			n += 1
	return n


func _ffa_teams() -> void:
	for i in lobby.players.size():
		lobby.players[i].team = i


func _auto_size() -> void:
	if is_ffa():
		return
	lobby.size = maxi(int(lobby.size), mini(4, maxi(_team_count(0), _team_count(1))))


func broadcast_lobby() -> void:
	net.send({"t": "lobby", "lobby": lobby})
	changed.emit()


func add_bot(team: int) -> void:
	var L := lobby
	if is_ffa():
		if L.players.size() < 4:
			_bot_n += 1
			L.players.append({"id": "b%d" % _bot_n, "name": "AI %d" % _bot_n, "team": 0, "bot": true})
			_ffa_teams()
			broadcast_lobby()
		return
	if L.players.size() >= 8 or _team_count(team) >= int(L.size):
		return
	_bot_n += 1
	L.players.append({"id": "b%d" % _bot_n, "name": "AI %d" % _bot_n, "team": team, "bot": true})
	broadcast_lobby()


func fill_bots() -> void:
	var L := lobby
	if is_ffa():
		while L.players.size() < 4:
			_bot_n += 1
			L.players.append({"id": "b%d" % _bot_n, "name": "AI %d" % _bot_n, "team": 0, "bot": true})
		_ffa_teams()
	else:
		for t in [0, 1]:
			while _team_count(t) < int(L.size) and L.players.size() < 8:
				_bot_n += 1
				L.players.append({"id": "b%d" % _bot_n, "name": "AI %d" % _bot_n, "team": t, "bot": true})
	broadcast_lobby()


func kick(id: String) -> void:
	lobby.players = lobby.players.filter(func(p): return p.id != id)
	if is_ffa():
		_ffa_teams()
	broadcast_lobby()


func swap(id: String) -> void:
	for p in lobby.players:
		if p.id == id:
			p.team = 1 - int(p.team)
	_auto_size()
	broadcast_lobby()


func set_size(n: int) -> void:
	var L := lobby
	if is_ffa():
		L.ffa = false
		for i in L.players.size():
			L.players[i].team = i % 2
	L.size = n
	for t in [0, 1]:
		while _team_count(t) > n:
			var bt = null
			for p in L.players:
				if p.team == t and p.get("bot", false):
					bt = p
			if bt == null:
				break
			L.players.erase(bt)
	broadcast_lobby()


func set_ffa() -> void:
	var L := lobby
	var humans: Array = L.players.filter(func(p): return not p.get("bot", false))
	if humans.size() > 4:
		_set_status("개인전은 4명까지예요. 사람이 너무 많아요", true)
		return
	while L.players.size() > 4:
		for i in range(L.players.size() - 1, -1, -1):
			if L.players[i].get("bot", false):
				L.players.remove_at(i)
				break
	L.ffa = true
	L.size = 4
	_ffa_teams()
	broadcast_lobby()


func set_map(id: String) -> void:
	lobby.map = id
	broadcast_lobby()


func set_armor(lv: int) -> void:
	lobby.armor = lv
	Settings.armor = lv
	Settings.save_settings()
	broadcast_lobby()


func map_choices() -> Array:
	if is_ffa():
		return game.world.MAP_LIST.ffa + game.world.MAP_LIST[4]
	return game.world.MAP_LIST.get(int(lobby.size), ["arena"])


# ================= 라운드 (방장이 정함) =================
func start_game() -> void:
	var L := lobby
	if is_ffa():
		if L.players.size() < 2:
			add_bot(0)
	else:
		for t in [0, 1]:
			if _team_count(t) == 0:
				add_bot(t)
	var maps := map_choices()
	var rnd: Array = game.world.MAP_LIST.ffa if is_ffa() else maps
	match_map = L.map if L.get("map") != null and L.get("map") in maps else rnd[randi() % rnd.size()]
	active = true
	score = [0, 0, 0, 0] if is_ffa() else [0, 0]
	game.round_no = 0
	_next_round()


func _next_round() -> void:
	var L := lobby
	var rnd: int = game.round_no + 1
	var flip: bool = rnd % 2 == 0
	var D: Dictionary = game.world.MAPS.get(match_map, game.world.MAPS.arena)
	var W: float = D.W
	var Lz: float = D.L
	var SZ: float = Lz / 2.0 - 3.5
	var spawns := {}
	if is_ffa():
		var g4 := minf(5.0, (W / 2.0 - 4.0) * 2.0 / 4.0)
		var X := 1.5 * g4
		var ffa: bool = D.get("ffa", false)
		var slots: Array = [[-(W / 2 - 4.5), -(W / 2 - 4.5)], [W / 2 - 4.5, W / 2 - 4.5], [W / 2 - 4.5, -(W / 2 - 4.5)], [-(W / 2 - 4.5), W / 2 - 4.5]] if ffa else [[-X, -SZ], [X, SZ], [X, -SZ], [-X, SZ]]
		for i in L.players.size():
			var s: Array = slots[(i + rnd - 1) % 4]
			var yaw: float = atan2(s[0], s[1]) if ffa else (PI if s[1] < 0 else 0.0)
			spawns[L.players[i].id] = [snappedf(s[0] + randf_range(-0.4, 0.4), 0.01), snappedf(s[1], 0.01), snappedf(yaw, 0.001)]
	else:
		var gap := minf(5.0, (W / 2.0 - 4.0) * 2.0 / maxf(1.0, float(L.size)))
		for team in [0, 1]:
			var ps: Array = L.players.filter(func(p): return p.team == team)
			var z := -SZ if (team == 0) != flip else SZ
			for i in ps.size():
				var x := (i - (ps.size() - 1) / 2.0) * gap + randf_range(-0.5, 0.5)
				spawns[ps[i].id] = [snappedf(x, 0.01), z, PI if z < 0 else 0.0]
	var m := {"t": "round", "round": rnd, "score": score, "spawns": spawns, "players": L.players, "armor": L.get("armor", Settings.armor), "winTo": win_to, "map": match_map, "ffa": is_ffa()}
	net.send(m.duplicate(true))
	_apply_round(m)


func _apply_round(m: Dictionary) -> void:
	active = true
	game.mp = true
	match_map = str(m.get("map", "arena"))
	armor = int(m.get("armor", 2))
	win_to = int(m.get("winTo", 7))
	score = m.get("score", [0, 0]).duplicate()
	lobby.players = m.get("players", [])
	lobby.ffa = m.get("ffa", false)
	my_team = 0
	for p in lobby.players:
		if p.id == net.my_id:
			my_team = int(p.team)
	game.player.team = my_team
	game.player.net_id = net.my_id
	# 나간 사람 정리, 새 사람 만들기
	var ids: Array = lobby.players.map(func(p): return p.id)
	for id in remotes.keys():
		if not id in ids:
			_remove_remote(id)
	for id in bots.keys():
		if not id in ids:
			_remove_bot(id)
	for p in lobby.players:
		if p.id == net.my_id:
			continue
		var a = _ensure_bot(p.id) if (net.host and p.get("bot", false)) else _ensure_remote(p.id)
		a.display_name = str(p.name)
		a.team = int(p.team)
		a.soldier.set_shirt(MY_SHIRT if a.team == my_team and not is_ffa() else ENEMY_SHIRT)
	if int(m.round) == 1:
		for a in actor_list():
			a.kills = 0
			a.deaths = 0
			a.heads = 0
	game.mp_round(m, int(m.round))
	var spawns: Dictionary = m.get("spawns", {})
	for a in actor_list():
		var s = spawns.get(a.net_id)
		if s == null:
			continue
		var pos := Vector3(float(s[0]), 0.05, float(s[1]))
		if a == game.player:
			a.set_loadout(Settings.get_loadout())
		elif bots.values().has(a):
			a.set_loadout(a.pick_loadout())
		a.reset_for_round(pos, float(s[2]), armor)
		a.visible = true
		if bots.values().has(a):
			a.round_start(pos.z < 0)
	_lo_keys.clear()
	game.hud.refresh_slots()
	var n0: int = _team_count(0)
	var n1: int = lobby.players.size() - n0
	var sub := "개인전 %d명 · 모두가 적 · ~ 키로 총 바꾸기 · %d점 선승" % [lobby.players.size(), win_to] if is_ffa() else "%s 팀 · %d대%d · ~ 키로 총 바꾸기 · %d점 선승" % [TEAM_NAME[my_team], n0, n1, win_to]
	game.hud.message("라운드 %d" % int(m.round), sub, 3.0)
	changed.emit()


func _ensure_remote(id: String):
	if remotes.has(id):
		return remotes[id]
	var r := CharacterBody3D.new()
	r.set_script(RemoteScript)
	r.game = game
	r.net_id = id
	r.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.add_child(r)
	r.died.connect(game._on_died)
	remotes[id] = r
	return r


func _remove_remote(id: String) -> void:
	if remotes.has(id):
		remotes[id].queue_free()
		remotes.erase(id)


func _ensure_bot(id: String):
	if bots.has(id):
		return bots[id]
	var b := CharacterBody3D.new()
	b.set_script(BotScript)
	b.game = game
	b.net_id = id
	b.level = G.BOT_LEVELS[Settings.difficulty]
	b.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.add_child(b)
	b.died.connect(game._on_died)
	bots[id] = b
	net.bots[id] = true
	return b


func _remove_bot(id: String) -> void:
	if bots.has(id):
		bots[id].queue_free()
		bots.erase(id)
	net.bots.erase(id)


func go_live_host() -> void:
	if net.host:
		net.send({"t": "go"})


func _alive_team(t: int) -> int:
	var n := 0
	for a in actor_list():
		if a.team == t and not a.dead:
			n += 1
	return n


func _team_health(t: int) -> float:
	var h := 0.0
	for a in actor_list():
		if a.team == t and not a.dead:
			h += a.health
	return h


func check_round_end() -> void:
	if not net.host or game.state != "live":
		return
	var winner := -1
	if is_ffa():
		var alive := {}
		for a in actor_list():
			if not a.dead:
				alive[a.team] = true
		if alive.size() > 1:
			return
		winner = alive.keys()[0] if alive.size() == 1 else -1
	else:
		var a0 := _alive_team(0)
		var a1 := _alive_team(1)
		if a0 > 0 and a1 > 0:
			return
		winner = -1 if a0 == 0 and a1 == 0 else (1 if a0 == 0 else 0)
	if winner >= 0:
		score[winner] += 1
	var m := {"t": "rend", "winner": winner, "score": score.duplicate(), "why": "kill"}
	net.send(m.duplicate(true))
	_show_round_end(m)


func time_up() -> void:
	if not net.host:
		return
	var winner := -1
	if is_ffa():
		var best := -1
		var bh := 0.0
		var tie := false
		for a in actor_list():
			if a.dead:
				continue
			if a.health > bh + 0.5:
				best = a.team
				bh = a.health
				tie = false
			elif absf(a.health - bh) <= 0.5:
				tie = true
		winner = -1 if tie else best
	else:
		var h0 := _team_health(0)
		var h1 := _team_health(1)
		winner = -1 if absf(h0 - h1) < 0.5 else (0 if h0 > h1 else 1)
	if winner >= 0:
		score[winner] += 1
	var m := {"t": "rend", "winner": winner, "score": score.duplicate(), "why": "time"}
	net.send(m.duplicate(true))
	_show_round_end(m)


func _show_round_end(m: Dictionary) -> void:
	var w := int(m.get("winner", -1))
	score = m.get("score", score).duplicate()
	var ffa := is_ffa()
	var sub := ""
	if m.get("why") == "time":
		sub = "시간 종료 · 체력이 가장 많은 사람이 이겨요" if ffa else "시간 종료 · 남은 체력이 많은 팀이 이겨요"
	if w < 0:
		game.hud.message("무승부", sub if sub != "" else ("모두 쓰러졌어요" if ffa else "양쪽 모두 쓰러졌어요"), 3.5)
	elif w == my_team:
		game.hud.message("라운드 승리", sub if sub != "" else ("마지막까지 살아남았어요!" if ffa else "%s 팀이 이겼어요" % TEAM_NAME[w]), 3.5, "win")
	else:
		game.hud.message("라운드 패배", sub if sub != "" else ("%s 님이 살아남았어요" % team_label(w) if ffa else "%s 팀이 이겼어요" % TEAM_NAME[clampi(w, 0, 1)]), 3.5, "lose")
	game.state = "post"
	game.post_t = 4.0
	game.player.trigger = false
	game.hud.show_dealt(game.dealt)
	game._log("[mp] 라운드 %d 끝 · 이긴 쪽 %d · 점수 %s" % [game.round_no, w, str(score)])


## 라운드 끝 시간이 다 됐을 때 (방장)
func after_post() -> void:
	if not net.host:
		return
	var mx := 0
	for s in score:
		mx = maxi(mx, int(s))
	if mx >= win_to:
		net.send({"t": "over", "score": score.duplicate()})
		game.mp_end_match()
	else:
		_next_round()


func to_lobby() -> void:
	active = false
	if net.host:
		net.send({"t": "tolobby"})
		broadcast_lobby()
	game.mp_to_lobby()


# ================= 죽음 · 맞힘 =================
func on_actor_died(victim, killer, info: Dictionary) -> void:
	if game.state != "live":
		return
	if is_local(victim):
		var kid: String = killer.net_id if killer and killer.net_id != "" else victim.net_id
		net.send({"t": "died", "killer": kid, "as": [], "weapon": info.get("weapon", ""), "head": info.get("head", false), "dist": info.get("dist", 0.0)}, "*", victim.net_id)
	var head := " [헤드샷]" if info.get("head", false) else ""
	var dist := (" %dm" % int(info.dist)) if info.get("dist", 0.0) else ""
	var kname: String = "" if (killer == null or killer == victim) else killer.display_name + "  "
	game.hud.add_feed("%s[%s]  %s%s%s" % [kname, info.get("weapon", ""), victim.display_name, head, dist], killer == game.player or (killer != null and killer.team == my_team and not is_ffa()))
	if killer == game.player and victim != game.player:
		game.hud.hit_marker(true, info.get("head", false))
	if victim == game.player:
		game.hud.message("쓰러졌어요", "다른 사람을 관전해요" if is_ffa() else ("팀원을 관전해요" if _alive_team(my_team) > 0 else ""), 2.5, "lose")
	game._log("[mp] %s → %s%s" % [kname.strip_edges(), victim.display_name, head])
	check_round_end()


## 내 캐릭터(또는 내 AI)가 상대에게 맞았을 때: 넣은 피해를 쏜 사람에게 알려줘요
func on_local_damaged(victim, amount: float, from) -> void:
	if from and from != victim and remotes.values().has(from) and amount > 0.0:
		net.send({"t": "dealt", "d": snappedf(minf(amount, victim.health + amount), 0.1), "n": victim.display_name}, from.net_id, victim.net_id)


func send_hit(owner, victim, m: Dictionary) -> void:
	m["t"] = "hit"
	net.send(m, victim.net_id, owner.net_id if owner else net.my_id)


func queue_shot(owner, wid: String, o: Vector3, d: Vector3) -> void:
	var k: String = owner.net_id
	if not _shots.has(k):
		_shots[k] = {"id": wid, "o": [snappedf(o.x, 0.001), snappedf(o.y, 0.001), snappedf(o.z, 0.001)], "d": []}
	_shots[k].d.append([snappedf(d.x, 0.00001), snappedf(d.y, 0.00001), snappedf(d.z, 0.00001)])


func send_nade(owner, type: String, o: Vector3, v: Vector3, fuse: float) -> void:
	net.send({"t": "nade", "type": type, "o": [o.x, o.y, o.z], "v": [v.x, v.y, v.z], "fuse": fuse}, "*", owner.net_id)


func send_boom(owner, type: String, p: Vector3) -> void:
	net.send({"t": "boom", "type": type, "p": [p.x, p.y, p.z]}, "*", owner.net_id)


# ================= 받기 =================
func _recv(m: Dictionary) -> void:
	var from: String = str(m.get("from", ""))
	_last_recv = Time.get_ticks_msec()
	if net.host and m.t == "hello":
		_host_hello(m)
		return
	if m.has("k"):
		var key := "%s:%s" % [from, m.k]
		if _dupe.has(key):
			return
		_dupe[key] = true
		if _dupe.size() > 3000:
			_dupe.clear()
	match m.t:
		"welcome":
			welcomed = true
			_set_status("들어왔어요! 방장이 시작하길 기다려요")
		"ping":
			net.send({"t": "pong", "ts": m.get("ts", 0)}, from)
		"pong":
			var r := Time.get_ticks_msec() - float(m.get("ts", 0))
			if r >= 0 and r < 10000:
				rtt = r if rtt == 0.0 else rtt * 0.7 + r * 0.3
		"reject":
			welcomed = false
			_set_status(str(m.get("why", "들어갈 수 없어요")), true)
		"lobby":
			if not net.host:
				welcomed = true
				lobby = m.get("lobby", lobby)
				changed.emit()
		"round":
			if not net.host:
				_apply_round(m)
		"go":
			if not net.host and game.state == "pre":
				game._go_live()
		"rend":
			if not net.host:
				_show_round_end(m)
		"over":
			if not net.host:
				score = m.get("score", score).duplicate()
				game.mp_end_match()
		"tolobby":
			if not net.host:
				active = false
				game.mp_to_lobby()
		"left":
			var r = remotes.get(str(m.get("id", "")))
			if r:
				game.hud.add_feed("%s  나갔어요" % r.display_name, false)
			_remove_remote(str(m.get("id", "")))
		"bye":
			if from == "h":
				_lost()
			elif net.host:
				_player_left(from)
		"lo":
			var r = remotes.get(from)
			if r:
				var list := []
				for it in m.get("list", []):
					var d: Dictionary = (it.get("att", {}) if typeof(it.get("att")) == TYPE_DICTIONARY else {}).duplicate()
					d["id"] = it.get("id", "m416")
					list.append(d)
				if not list.is_empty():
					r.set_loadout(list)
		"sb":
			for s in m.get("a", []):
				if typeof(s) == TYPE_DICTIONARY:
					s["t"] = "st"
					_recv(s)
		"st":
			var r = remotes.get(from)
			if r and game.state in ["pre", "live", "post"]:
				r.apply_state(m)
		"punch":
			var r = remotes.get(from)
			if r:
				Sfx.punch(false)
		"shot":
			var r = remotes.get(from)
			if r == null:
				return
			var st: Dictionary = r.stats_for(str(m.get("id", "m416")))
			var o: Array = m.get("o", [0, 0, 0])
			var ov := Vector3(o[0], o[1], o[2])
			for d in m.get("d", []):
				game.combat.spawn_bullet(r, ov, Vector3(d[0], d[1], d[2]), st, 0.0, true)
			Sfx.shot(ov, st.cat, st.suppressed, false)
			for b in bots.values():
				b.hear_shot(r, st.suppressed)
		"dealt":
			var k := str(m.get("n", "?"))
			if not game.dealt.has(k):
				game.dealt[k] = {"dmg": 0.0, "hits": 0}
			game.dealt[k].dmg += float(m.get("d", 0))
			game.dealt[k].hits += 1
		"hit":
			var r = remotes.get(from)
			var to := str(m.get("to", ""))
			var victim = bots[to] if net.host and bots.has(to) else game.player
			if r == null or victim.dead or game.state != "live" or (r.team == victim.team and not is_ffa()):
				return
			game.combat.apply_remote_hit(r, victim, m)
		"nade":
			var r = remotes.get(from)
			if r:
				var o: Array = m.get("o", [0, 0, 0])
				var v: Array = m.get("v", [0, 0, 0])
				game.combat.throw_grenade(r, str(m.get("type", "frag")), Vector3(o[0], o[1], o[2]), Vector3(v[0], v[1], v[2]), float(m.get("fuse", 3.0)))
				Sfx.spoon()
		"boom":
			var r = remotes.get(from)
			if r:
				var p: Array = m.get("p", [0, 0, 0])
				game.combat.explode(str(m.get("type", "frag")), Vector3(p[0], p[1], p[2]), r)
		"died":
			var r = remotes.get(from)
			if r == null or r.dead:
				return
			var killer = actor_by_id(str(m.get("killer", from)))
			if killer == null:
				killer = r
			r.mark_dead(killer, {"weapon": m.get("weapon", ""), "head": m.get("head", false), "dist": m.get("dist", 0.0)})


func _player_left(id: String) -> void:
	var p = null
	for x in lobby.players:
		if x.id == id:
			p = x
	if p == null:
		return
	lobby.players.erase(p)
	if active:
		game.hud.add_feed("%s  나갔어요" % p.name, false)
		net.send({"t": "left", "id": id})
		_remove_remote(id)
		if game.state == "live":
			check_round_end()
	else:
		broadcast_lobby()


func _lost() -> void:
	if active:
		game.hud.message("방장과 연결이 끊겼어요", "처음 화면으로 돌아가요", 3.0, "lose")
		active = false
		game.go_menu()
	else:
		_set_status("방장과 연결이 끊겼어요", true)
		lobby = {"size": 1, "players": []}
	leave()


# ================= 매 프레임 =================
func update(dt: float) -> void:
	if not in_room():
		return
	# 참가 인사 (방장이 받았다고 답할 때까지 1초마다)
	if not net.host and not welcomed and net.live_count() > 0:
		_hello_t -= dt
		if _hello_t <= 0.0:
			_hello_t = 1.0
			_hello_n += 1
			if _hello_n > 20:
				_set_status("방장에게서 답이 없어요. 코드가 맞는지, 방장이 방 화면을 켜 두었는지 확인해 주세요", true)
				_hello_n = 0
			net.send({"t": "hello", "name": my_name, "ver": net.NET_VER}, "h")
	_ping_t -= dt
	if _ping_t <= 0.0:
		_ping_t = 1.0
		if active or not net.host:
			net.send({"t": "ping", "ts": Time.get_ticks_msec()})
		# 방장: 30초 동안 소식 없는 사람은 나간 걸로
		if net.host:
			for p in lobby.players.duplicate():
				if p.id == "h" or p.get("bot", false):
					continue
				var t = net.seen.get(p.id)
				if t != null and Time.get_ticks_msec() - int(t) > 30000:
					_player_left(p.id)
	if not net.host and welcomed and Time.get_ticks_msec() - _last_recv > 25000:
		_lost()
		return
	if not active:
		return
	# 총알 보내기
	for k in _shots:
		var s: Dictionary = _shots[k]
		net.send({"t": "shot", "id": s.id, "o": s.o, "d": s.d}, "*", k)
	_shots.clear()
	# 상태 보내기 (초당 20번, 여러 캐릭터를 한 메시지로)
	_send_t -= dt
	if _send_t > 0.0:
		return
	_send_t = 0.05
	var senders: Array = [game.player]
	if net.host:
		senders += bots.values()
	var batch := []
	for p in senders:
		var gp: Vector3 = p.global_position
		var md := "t" if p.mode == "throw" else ("f" if p.mode == "fist" else "g")
		batch.append({"t": "st", "from": p.net_id, "ts": Time.get_ticks_msec(), "p": [snappedf(gp.x, 0.001), snappedf(gp.y, 0.001), snappedf(gp.z, 0.001)], "v": [snappedf(p.velocity.x, 0.01), snappedf(p.velocity.z, 0.01)],
			"y": snappedf(p.rotation.y, 0.0001), "pi": snappedf(p.pitch, 0.0001), "s": STANCE_CODE[p.stance], "l": snappedf(p.lean, 0.01), "a": snappedf(p.ads_t, 0.01), "sp": 1 if p.sprint else 0,
			"h": snappedf(p.health, 0.1), "d": 1 if p.dead else 0, "hl": p.helmet_lv, "hd": roundi(p.helmet_dur), "vl": p.vest_lv, "vd": roundi(p.vest_dur), "w": p.cur, "m": md, "tt": p.throw_type,
			"rl": snappedf(maxf(0.01, 1.0 - p.reload_t / maxf(p.reload_dur, 0.01)), 0.01) if p.reload_t > 0.0 else 0, "vt": snappedf(minf(1.0, p.vault.t), 0.01) if p.vault != null else -1, "vo": 1 if p.vault != null and p.vault.over else 0, "he": 1 if p.heal_t > 0.0 else 0})
		var list := []
		for wp in p.weapons:
			list.append({"id": wp.id, "att": wp.att})
		var key := JSON.stringify(list)
		_lo_n += 1
		if _lo_keys.get(p.net_id, "") != key or _lo_n % 72 == 0:
			_lo_keys[p.net_id] = key
			net.send({"t": "lo", "list": list}, "*", p.net_id)
	net.post({"t": "sb", "a": batch, "from": net.my_id, "to": "*"})


# ================= 화면용 =================
func score_text() -> String:
	if is_ffa():
		var parts := []
		for p in lobby.players:
			parts.append("%s %d" % ["나" if p.id == net.my_id else str(p.name), int(score[int(p.team)]) if int(p.team) < score.size() else 0])
		return "   ".join(parts)
	var other := 1 - my_team
	return "%s %d  :  %d %s" % [TEAM_NAME[my_team], int(score[my_team]), int(score[other]), TEAM_NAME[other]]


func alive_text() -> String:
	if is_ffa():
		var n := 0
		for a in actor_list():
			if not a.dead:
				n += 1
		return "남은 사람 %d" % n
	return "살아있음 %d : %d" % [_alive_team(my_team), _alive_team(1 - my_team)]


func spectate_target():
	var best = null
	for a in actor_list():
		if a == game.player or a.dead:
			continue
		if not is_ffa() and a.team == my_team:
			return a
		if best == null:
			best = a
	return best
