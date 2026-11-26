extends Node
## 로그인 (Firebase Authentication REST) — 웹 버전과 같은 계정. 이메일/비밀번호 로그인·가입·비밀번호 재설정
## 구글 로그인은 웹에서만 돼요 (데스크톱에서는 구글 계정 연결 설정이 따로 필요해서)

signal changed

const API_KEY := "AIzaSyAEteEk9bAfkdydGeumWpSPmALXRaMDt7g"
const PATH := "user://auth.cfg"
const HEADERS := ["Content-Type: application/json", "Referer: https://training-1v1.onrender.com/"]

var uid := ""
var email := ""
var display_name := ""
var _refresh := ""

const ERR := {
	"INVALID_LOGIN_CREDENTIALS": "이메일 또는 비밀번호가 맞지 않아요", "INVALID_PASSWORD": "이메일 또는 비밀번호가 맞지 않아요",
	"EMAIL_NOT_FOUND": "가입된 이메일이 아니에요", "EMAIL_EXISTS": "이미 가입된 이메일이에요. 로그인을 눌러 주세요",
	"INVALID_EMAIL": "이메일 형식이 맞지 않아요", "MISSING_PASSWORD": "비밀번호를 입력하세요", "OPERATION_NOT_ALLOWED": "Firebase에서 이 로그인 방법이 꺼져 있어요",
	"TOO_MANY_ATTEMPTS_TRY_LATER": "시도가 너무 많아요. 잠시 뒤에 다시 해 주세요",
}


func _ready() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		_refresh = c.get_value("a", "refresh", "")
		email = c.get_value("a", "email", "")
		if _refresh != "":
			_refresh_token()


func logged_in() -> bool:
	return uid != ""


func _save() -> void:
	var c := ConfigFile.new()
	c.set_value("a", "refresh", _refresh)
	c.set_value("a", "email", email)
	c.save(PATH)


func _post(url: String, body: String) -> Dictionary:
	var h := HTTPRequest.new()
	h.timeout = 15.0
	add_child(h)
	if h.request(url, PackedStringArray(HEADERS), HTTPClient.METHOD_POST, body) != OK:
		h.queue_free()
		return {"error": {"message": "NETWORK"}}
	var r: Array = await h.request_completed
	h.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": {"message": "NETWORK"}}
	var j = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	return j if typeof(j) == TYPE_DICTIONARY else {"error": {"message": "BAD"}}


func _err(j: Dictionary) -> String:
	var m: String = str(j.get("error", {}).get("message", ""))
	if m == "NETWORK":
		return "인터넷 연결을 확인해 주세요"
	if m.begins_with("WEAK_PASSWORD"):
		return "비밀번호는 6자 이상이어야 해요"
	for k in ERR:
		if m.begins_with(k):
			return ERR[k]
	return "로그인하지 못했어요 (%s)" % m


## 결과: "" = 성공, 아니면 오류 문장
func sign_in(e: String, pw: String, signup := false) -> String:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:%s?key=%s" % ["signUp" if signup else "signInWithPassword", API_KEY]
	var j := await _post(url, JSON.stringify({"email": e, "password": pw, "returnSecureToken": true}))
	if j.has("error"):
		return _err(j)
	uid = j.get("localId", "")
	email = j.get("email", e)
	display_name = j.get("displayName", "")
	_refresh = j.get("refreshToken", "")
	_save()
	changed.emit()
	return ""


func reset_password(e: String) -> String:
	var j := await _post("https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=" + API_KEY, JSON.stringify({"requestType": "PASSWORD_RESET", "email": e}))
	return _err(j) if j.has("error") else ""


func _refresh_token() -> void:
	var h := HTTPRequest.new()
	add_child(h)
	var hd := PackedStringArray(["Content-Type: application/x-www-form-urlencoded", HEADERS[1]])
	h.request("https://securetoken.googleapis.com/v1/token?key=" + API_KEY, hd, HTTPClient.METHOD_POST, "grant_type=refresh_token&refresh_token=" + _refresh.uri_encode())
	var r: Array = await h.request_completed
	h.queue_free()
	var j = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8()) if r[0] == HTTPRequest.RESULT_SUCCESS else null
	if typeof(j) == TYPE_DICTIONARY and j.has("user_id"):
		uid = j.user_id
		_refresh = j.get("refresh_token", _refresh)
		_save()
		changed.emit()


func sign_out() -> void:
	uid = ""
	_refresh = ""
	_save()
	changed.emit()
