extends Node
## 온라인 연결 — 웹 게임의 「학교 와이파이용 방」(코드가 R로 시작)과 똑같은 방식이에요.
## 우리 전용 중계 서버(Cloudflare) + 공개 MQTT 서버 여러 곳에 동시에 붙고, 같은 메시지는 한 번만 받아요.
## 그래서 웹 게임과 Godot 게임이 같은 방에서 만날 수 있어요.

signal recv(m: Dictionary)
signal status_changed

const MqttScript = preload("res://scripts/mqtt.gd")
const NET_VER := 21
const RELAY_WS := "wss://tg1v1-relay.jangiden091112-d5a.workers.dev"
const BROKERS := [
	{"url": "wss://mqtt.eclipseprojects.io:443/mqtt"},
	{"url": "wss://broker.emqx.io:8084/mqtt"},
	{"url": "wss://broker.hivemq.com:8884/mqtt"},
	{"url": "wss://public.cloud.shiftr.io", "user": "public", "pass": "public"},
	{"url": "wss://test.mosquitto.org:8081/mqtt"},
]
# 꼭 전달돼야 하는 메시지는 번호를 붙여 3번 보내요 (웹과 같은 목록)
const IMPORTANT := ["chat", "hit", "died", "round", "go", "over", "dealt", "nade", "boom", "tolobby", "mark"]

var my_id := ""
var code := ""
var host := false
var topic := ""
var bots := {} # 방장 컴퓨터의 AI id (그 앞으로 온 메시지도 받아요)
var seen := {} # 방장: 사람마다 마지막으로 소식 들은 때

var _mq: Array = []
var _ws: WebSocketPeer = null
var _ws_state := WebSocketPeer.STATE_CLOSED
var _ws_retry := 0.0
var _busn := 0
var _bus_dup := {}
var _seq := 0


static func make_code() -> String:
	const A := "ABCDEFGHJKMNPQSTUVWXYZ23456789"
	var s := ""
	for i in 5:
		s += A[randi() % A.length()]
	return s


func open(c: String) -> void:
	close()
	code = c
	topic = "tg1v1/v%d/%s" % [NET_VER, c]
	_bus_dup.clear()
	for B in BROKERS:
		var m := Node.new()
		m.set_script(MqttScript)
		add_child(m)
		m.message.connect(func(_t, payload, _r): _on_raw(payload))
		m.connected.connect(func(): status_changed.emit())
		m.disconnected.connect(func(): status_changed.emit())
		m.subscribe(topic)
		m.start(B.url, "tg" + str(randi() % 0xFFFFFFF).sha256_text().substr(0, 8), {}, B.get("user", ""), B.get("pass", ""))
		_mq.append(m)
	_ws_open()


func _ws_open() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	_ws.connect_to_url(RELAY_WS + "/room/" + topic)
	_ws_state = WebSocketPeer.STATE_CONNECTING


func close() -> void:
	for m in _mq:
		m.stop()
		m.queue_free()
	_mq.clear()
	if _ws:
		_ws.close()
	_ws = null
	_ws_state = WebSocketPeer.STATE_CLOSED
	code = ""
	topic = ""
	seen.clear()
	status_changed.emit()


func live_count() -> int:
	var n := 1 if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN else 0
	for m in _mq:
		if m.ok:
			n += 1
	return n


func server_count() -> int:
	return BROKERS.size() + 1


## 그대로 올리기 (모든 서버에)
func post(msg: Dictionary) -> void:
	_busn += 1
	msg["_n"] = "%s.%d.%d" % [my_id, _busn, Time.get_ticks_msec() % 100000]
	var s := JSON.stringify(msg)
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(s)
	for m in _mq:
		if m.ok:
			m.publish(topic, s)


## 논리적으로 보내기: to = "*" (모두) 또는 사람 id
func send(msg: Dictionary, to := "*", from := "") -> void:
	if code == "":
		return
	msg["from"] = from if from != "" else my_id
	msg["to"] = to
	if msg.get("t", "") in IMPORTANT:
		_seq += 1
		msg["k"] = _seq
		get_tree().create_timer(0.09).timeout.connect(func(): post(msg.duplicate()))
		get_tree().create_timer(0.26).timeout.connect(func(): post(msg.duplicate()))
	post(msg)


func _on_raw(payload: String) -> void:
	var m = JSON.parse_string(payload)
	if typeof(m) != TYPE_DICTIONARY or not m.has("t") or m.get("from", "") == my_id:
		return
	var n = m.get("_n")
	if n != null:
		if _bus_dup.has(n):
			return
		_bus_dup[n] = true
		if _bus_dup.size() > 4000:
			_bus_dup.clear()
	var to: String = str(m.get("to", "*"))
	if host:
		seen[m.get("from", "")] = Time.get_ticks_msec()
		if m.t == "hello" or to == "*" or to == "h" or bots.has(to):
			recv.emit(m)
	elif to == "*" or to == my_id:
		recv.emit(m)


func _process(dt: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st != _ws_state:
		_ws_state = st
		status_changed.emit()
	if st == WebSocketPeer.STATE_OPEN:
		while _ws.get_available_packet_count() > 0:
			_on_raw(_ws.get_packet().get_string_from_utf8())
	elif st == WebSocketPeer.STATE_CLOSED and topic != "":
		_ws_retry -= dt
		if _ws_retry <= 0.0:
			_ws_retry = 3.0
			_ws_open()
