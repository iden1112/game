extends Node
## 닉네임 · 친구 (웹 버전과 같은 서버 자리 tg1v1s/v2/ — 웹 친구와 목록·접속 표시가 이어져요)
## 닉네임은 로그인한 회원 계정에 묶여요. 방 초대는 Godot 끼리만 (웹 방과는 방식이 달라서)

signal changed
signal note(text: String, invite_code: String, from_name: String)

const MqttScript = preload("res://scripts/mqtt.gd")
const BROKERS := ["wss://broker.emqx.io:8084/mqtt", "wss://broker.hivemq.com:8884/mqtt"]
const P := "tg1v1s/v2/"
const PATH := "user://social.cfg"

var auth # auth.gd
var data := {"id": "", "nick": "", "reg": false, "friends": []}
var req_in := {} # id → {nick}
var online := {} # id → bool
var _cls: Array = []
var _waits := {}
var claiming := false


func _ready() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		for k in data:
			data[k] = c.get_value("s", k, data[k])
	if data.id == "":
		var b := PackedByteArray()
		for i in 12:
			b.append(randi() % 256)
		data.id = b.hex_encode()
		_save()


func _save() -> void:
	var c := ConfigFile.new()
	for k in data:
		c.set_value("s", k, data[k])
	c.save(PATH)


static func nkey(n: String) -> String:
	return n.strip_edges().to_lower().uri_encode()


func uid() -> String:
	return auth.uid if auth else ""


func is_ok() -> bool:
	for c in _cls:
		if c.ok:
			return true
	return false


func start() -> void:
	if not _cls.is_empty():
		return
	for u in BROKERS:
		var c := Node.new()
		c.set_script(MqttScript)
		add_child(c)
		c.message.connect(_on_msg)
		c.connected.connect(_on_connected.bind(c))
		c.start(u, "tgg" + data.id.substr(0, 10) + str(randi() % 10000), {"topic": P + "on/" + data.id, "payload": JSON.stringify({"on": 0, "ts": 0})})
		_cls.append(c)


func _pub(topic: String, obj, retain := false) -> void:
	var s := "" if obj == null else JSON.stringify(obj)
	for c in _cls:
		c.publish(P + topic, s, retain)


func _sub(topic: String) -> void:
	for c in _cls:
		c.subscribe(P + topic)


func _unsub(topic: String) -> void:
	for c in _cls:
		c.unsubscribe(P + topic)


func _now() -> int:
	return int(Time.get_unix_time_from_system() * 1000)


func _on_connected(_c) -> void:
	_register_topics()
	changed.emit()


func _register_topics() -> void:
	if data.nick == "" or not data.reg or uid() == "":
		return
	var me: String = data.id
	_sub("req/" + nkey(data.nick) + "/+")
	_sub("acc/" + me + "/+")
	_sub("inv/" + me)
	for f in data.friends:
		if f.id != "":
			_sub("on/" + f.id)
			_sub("u/" + f.id)
	_pub("on/" + me, {"on": 1, "ts": _now()}, true)
	_pub("u/" + me, {"nick": data.nick, "ts": _now()}, true)
	_pub("nick/" + nkey(data.nick), {"id": me, "uid": uid(), "nick": data.nick, "ts": _now()}, true)


## 남겨진 메시지 하나 읽기 (없으면 null, 서버 연결 안 됐으면 "offline")
func peek(topic: String, sec := 3.5):
	if not is_ok():
		return "offline"
	var key := P + topic
	_waits[key] = null
	for c in _cls:
		c.subscribe(key)
	var t := 0.0
	while t < sec and _waits.get(key) == null:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	for c in _cls:
		c.unsubscribe(key)
	var v = _waits.get(key)
	_waits.erase(key)
	return v


## 닉네임 정하기 — "" = 성공
func claim_nick(nick: String) -> String:
	nick = nick.strip_edges().substr(0, 12)
	if nick.length() < 2:
		return "두 글자 이상으로 정해 주세요"
	for ch in ["/", "#", "+"]:
		if ch in nick:
			return "/ # + 는 쓸 수 없어요"
	if uid() == "" or not is_ok():
		data.nick = nick
		data.reg = false
		_save()
		Settings.nick = nick
		Settings.save_settings()
		changed.emit()
		return ""
	var cur = await peek("nick/" + nkey(nick))
	if typeof(cur) == TYPE_DICTIONARY and cur.get("uid", "") != "" and cur.uid != uid():
		return "이미 누가 쓰는 닉네임이에요"
	var old := ""
	if data.nick != "" and data.reg and nkey(data.nick) != nkey(nick):
		old = data.nick
	_pub("nick/" + nkey(nick), {"id": data.id, "uid": uid(), "nick": nick, "ts": _now()}, true)
	_pub("u/" + data.id, {"nick": nick, "ts": _now()}, true)
	if old != "":
		_pub("nick/" + nkey(old), null, true)
		_unsub("req/" + nkey(old) + "/+")
	data.nick = nick
	data.reg = true
	_save()
	Settings.nick = nick
	Settings.save_settings()
	_register_topics()
	changed.emit()
	return ""


func add_friend(name: String) -> String:
	name = name.strip_edges()
	if name == "":
		return "친구 닉네임을 입력하세요"
	if uid() == "":
		return "친구 기능은 로그인한 회원만 쓸 수 있어요"
	if not data.reg:
		return "먼저 내 닉네임을 등록해야 해요"
	if nkey(name) == nkey(data.nick):
		return "나 자신은 친구로 추가할 수 없어요"
	for f in data.friends:
		if nkey(f.nick) == nkey(name):
			return "이미 친구예요"
	for fid in req_in:
		if nkey(req_in[fid].nick) == nkey(name):
			accept(fid)
			return "ok:친구가 됐어요"
	var who = await peek("nick/" + nkey(name))
	if typeof(who) == TYPE_STRING:
		return "서버에 연결되지 않았어요"
	_pub("req/" + nkey(name) + "/" + data.id, {"from": data.nick, "id": data.id, "ts": _now()}, true)
	if typeof(who) == TYPE_DICTIONARY:
		return "ok:%s 님에게 친구 요청을 보냈어요" % who.get("nick", name)
	return "ok:아직 \"%s\" 닉네임을 못 찾았어요. 그래도 요청은 남겨 뒀어요" % name


func accept(fid: String) -> void:
	if not req_in.has(fid):
		return
	var r: Dictionary = req_in[fid]
	_pub("acc/" + fid + "/" + data.id, {"from": data.nick, "id": data.id, "ts": _now()}, true)
	_pub("req/" + nkey(data.nick) + "/" + fid, null, true)
	req_in.erase(fid)
	_add_friend(fid, r.nick)
	changed.emit()


func decline(fid: String) -> void:
	_pub("req/" + nkey(data.nick) + "/" + fid, null, true)
	req_in.erase(fid)
	changed.emit()


func remove(fid: String) -> void:
	data.friends = data.friends.filter(func(f): return f.id != fid)
	_save()
	_unsub("on/" + fid)
	_unsub("u/" + fid)
	changed.emit()


func invite(fid: String, code: String) -> void:
	_pub("inv/" + fid, {"from": data.nick, "id": data.id, "code": code, "ts": _now()}) # 웹과 같은 초대 (R 코드라 웹 친구도 바로 들어와요)


func _add_friend(fid: String, nick: String) -> bool:
	if fid == "" or fid == data.id:
		return false
	for f in data.friends:
		if f.id == fid:
			f.nick = nick
			_save()
			return false
	data.friends.append({"id": fid, "nick": nick})
	_save()
	_sub("on/" + fid)
	_sub("u/" + fid)
	return true


func friend_name(fid: String) -> String:
	for f in data.friends:
		if f.id == fid:
			return f.nick
	return fid


func _on_msg(topic: String, payload: String, _retained: bool) -> void:
	if not topic.begins_with(P):
		return
	var t := topic.substr(P.length())
	var m = JSON.parse_string(payload) if payload != "" else null
	if _waits.has(topic) and m != null:
		_waits[topic] = m
	var parts := t.split("/")
	var kind := parts[0]
	if data.nick == "":
		return
	match kind:
		"req":
			if parts.size() >= 3 and parts[1] == nkey(data.nick):
				var fid := parts[2]
				if typeof(m) != TYPE_DICTIONARY or not m.has("from"):
					req_in.erase(fid)
				elif m.get("id") == fid:
					for f in data.friends:
						if f.id == fid:
							_pub(t, null, true)
							return
					if not req_in.has(fid):
						note.emit("%s 님이 친구 요청을 보냈어요" % m.from, "", m.from)
					req_in[fid] = {"nick": m.from}
				changed.emit()
		"acc":
			if parts.size() >= 3 and parts[1] == data.id and typeof(m) == TYPE_DICTIONARY and m.has("id"):
				_pub(t, null, true)
				if _add_friend(m.id, m.get("from", "")):
					note.emit("%s 님과 친구가 됐어요!" % m.get("from", ""), "", "")
				changed.emit()
		"u":
			if typeof(m) == TYPE_DICTIONARY and m.has("nick"):
				for f in data.friends:
					if f.id == parts[1] and f.nick != m.nick:
						f.nick = m.nick
						_save()
						changed.emit()
		"on":
			if parts.size() >= 2:
				var on: bool = typeof(m) == TYPE_DICTIONARY and m.get("on", 0) == 1 and _now() - int(m.get("ts", 0)) < 150000
				online[parts[1]] = on
				changed.emit()
		"inv":
			if parts.size() >= 2 and parts[1] == data.id and typeof(m) == TYPE_DICTIONARY and m.has("code"):
				if _now() - int(m.get("ts", 0)) < 120000:
					var c := str(m.code)
					if c.begins_with("R"):
						note.emit("%s 님이 방으로 초대했어요" % friend_name(str(m.get("id", ""))), c, str(m.get("from", "")))
					else:
						note.emit("%s 님이 웹의 일반 방으로 초대했어요. Godot은 「학교 와이파이용 방」(R로 시작)만 들어갈 수 있어요" % friend_name(str(m.get("id", ""))), "", "")


var _beat := 0.0


func _process(dt: float) -> void:
	_beat += dt
	if _beat > 60.0:
		_beat = 0.0
		if data.reg and uid() != "":
			_pub("on/" + data.id, {"on": 1, "ts": _now()}, true)
	# 로그인했는데 닉네임이 서버에 안 올라갔으면 올려요
	if is_ok() and uid() != "" and data.nick != "" and not data.reg and not claiming:
		claiming = true
		var e: String = await claim_nick(data.nick)
		claiming = false
		if e != "":
			note.emit("닉네임을 다시 정해 주세요: " + e, "", "")
			data.nick = ""
			_save()


func on_logout() -> void:
	if data.reg:
		_pub("on/" + data.id, {"on": 0, "ts": _now()}, true)
	data.reg = false
	_save()
	changed.emit()


func _exit_tree() -> void:
	if data.reg and uid() != "":
		_pub("on/" + data.id, {"on": 0, "ts": _now()}, true)
