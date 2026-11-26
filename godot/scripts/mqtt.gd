extends Node
## 아주 작은 MQTT 3.1.1 클라이언트 (웹소켓) — 원본처럼 공개 MQTT 서버로 방·친구 메시지를 주고받아요

signal connected
signal disconnected
signal message(topic: String, payload: String, retained: bool)

var url := ""
var client_id := ""
var ok := false
var _ws := WebSocketPeer.new()
var _state := WebSocketPeer.STATE_CLOSED
var _ping_t := 0.0
var _retry_t := 0.0
var _subs: Array = []
var _will := {}
var _buf := PackedByteArray()
var _pid := 1


var _user := ""
var _pass := ""


func start(u: String, id: String, will := {}, user := "", pw := "") -> void:
	url = u
	client_id = id
	_will = will
	_user = user
	_pass = pw
	_open()


func _open() -> void:
	_ws = WebSocketPeer.new()
	_ws.supported_protocols = PackedStringArray(["mqtt"])
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	_buf.clear()
	ok = false
	if _ws.connect_to_url(url) != OK:
		_retry_t = 5.0


func stop() -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.put_packet(PackedByteArray([0xE0, 0x00])) # DISCONNECT
	_ws.close()
	ok = false
	url = ""


func _str(s: String) -> PackedByteArray:
	var b := s.to_utf8_buffer()
	var out := PackedByteArray([b.size() >> 8, b.size() & 0xFF])
	out.append_array(b)
	return out


func _packet(head: int, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([head])
	var n := body.size()
	while true:
		var d := n % 128
		n /= 128
		if n > 0:
			d |= 0x80
		out.append(d)
		if n == 0:
			break
	out.append_array(body)
	return out


func _send_connect() -> void:
	var vh := _str("MQTT")
	var flags := 0x02
	if not _will.is_empty():
		flags |= 0x04 | 0x20 # will + will retain
	if _user != "":
		flags |= 0x80 | 0x40 # 아이디 + 비밀번호
	vh.append_array(PackedByteArray([4, flags, 0, 30]))
	var pl := _str(client_id)
	if not _will.is_empty():
		pl.append_array(_str(_will.topic))
		pl.append_array(_str(_will.payload))
	if _user != "":
		pl.append_array(_str(_user))
		pl.append_array(_str(_pass))
	vh.append_array(pl)
	_ws.put_packet(_packet(0x10, vh))


func subscribe(topic: String) -> void:
	if not (topic in _subs):
		_subs.append(topic)
	if ok:
		_sub_now(topic)


func _sub_now(topic: String) -> void:
	_pid = (_pid % 60000) + 1
	var b := PackedByteArray([_pid >> 8, _pid & 0xFF])
	b.append_array(_str(topic))
	b.append(0)
	_ws.put_packet(_packet(0x82, b))


func unsubscribe(topic: String) -> void:
	_subs.erase(topic)
	if ok:
		_pid = (_pid % 60000) + 1
		var b := PackedByteArray([_pid >> 8, _pid & 0xFF])
		b.append_array(_str(topic))
		_ws.put_packet(_packet(0xA2, b))


func publish(topic: String, payload: String, retain := false) -> void:
	if not ok:
		return
	var b := _str(topic)
	b.append_array(payload.to_utf8_buffer())
	_ws.put_packet(_packet(0x30 | (0x01 if retain else 0), b))


func _process(dt: float) -> void:
	if url == "":
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and _state != WebSocketPeer.STATE_OPEN:
		_send_connect()
	if st == WebSocketPeer.STATE_CLOSED and _state != WebSocketPeer.STATE_CLOSED:
		var was := ok
		ok = false
		_retry_t = 5.0
		if was:
			disconnected.emit()
	_state = st
	if st == WebSocketPeer.STATE_CLOSED:
		_retry_t -= dt
		if _retry_t <= 0.0:
			_open()
		return
	while _ws.get_available_packet_count() > 0:
		_buf.append_array(_ws.get_packet())
	_parse()
	if ok:
		_ping_t += dt
		if _ping_t > 20.0:
			_ping_t = 0.0
			_ws.put_packet(PackedByteArray([0xC0, 0x00]))


func _parse() -> void:
	while _buf.size() >= 2:
		var mul := 1
		var n := 0
		var i := 1
		var done := false
		while i < _buf.size():
			var d := _buf[i]
			n += (d & 0x7F) * mul
			mul *= 128
			i += 1
			if d & 0x80 == 0:
				done = true
				break
		if not done or _buf.size() < i + n:
			return
		var head := _buf[0]
		var body := _buf.slice(i, i + n)
		_buf = _buf.slice(i + n)
		match head >> 4:
			2: # CONNACK
				if body.size() >= 2 and body[1] == 0:
					ok = true
					_ping_t = 0.0
					for t in _subs:
						_sub_now(t)
					connected.emit()
			3: # PUBLISH
				var tl := (body[0] << 8) | body[1]
				var topic := body.slice(2, 2 + tl).get_string_from_utf8()
				var p := 2 + tl
				if (head >> 1) & 0x03 > 0:
					p += 2
				message.emit(topic, body.slice(p).get_string_from_utf8(), head & 0x01 == 1)
