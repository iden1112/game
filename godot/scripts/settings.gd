extends Node
## 설정 (자동 로드: Settings) — user://settings.cfg 에 저장돼요

const PATH := "user://settings.cfg"

# 키 설정: [묶음, [[이름, 동작, 기본 키]]]
const KEY_ACTIONS := [
	["이동", [["앞으로", "forward", KEY_W], ["뒤로", "back", KEY_S], ["왼쪽", "left", KEY_A], ["오른쪽", "right", KEY_D],
		["달리기 · 숨 참기", "sprint", KEY_SHIFT], ["점프 · 넘기", "jump", KEY_SPACE], ["앉기", "crouch", KEY_C], ["엎드리기", "prone", KEY_Z],
		["왼쪽 기울이기", "lean_l", KEY_Q], ["오른쪽 기울이기", "lean_r", KEY_E], ["둘러보기", "freelook", KEY_ALT]]],
	["무기", [["재장전 · 쿠킹", "reload", KEY_R], ["단발/점사/연사", "firemode", KEY_B], ["1번 무기", "slot1", KEY_1], ["2번 무기", "slot2", KEY_2],
		["3번 무기 (권총)", "slot3", KEY_3], ["투척물", "throw", KEY_G], ["투척물 바꾸기", "throw_next", KEY_5], ["구급상자", "heal", KEY_4], ["맨손", "fist", KEY_X]]],
	["기타", [["1인칭/3인칭", "view", KEY_V], ["점수판", "score", KEY_TAB], ["총 고르기", "loadout", KEY_QUOTELEFT]]],
]

var nick := ""
var sens := 1.0
var ads_sens := 1.0
var fov := 80.0
var quality := "high" # high | mid | low
var volume := 0.8
var aim_mode := "pubg" # pubg(짧게=조준, 길게=견착) | toggle | hold
var sprint_mode := "hold"
var crouch_mode := "toggle"
var lean_mode := "hold"
var difficulty := 1
var armor := 2
var map_id := "duel"
var loadout: Array = []
var keys := {} # 동작 → 키 코드 (바꾼 것만)
var xh := {"preset": "pubg", "color": Color.WHITE, "len": 6, "th": 2, "gap": 4, "dot": 0, "out": 1, "dyn": 1}

const XH_PRESETS := {
	"pubg": {"len": 6, "th": 2, "gap": 4, "dot": 0, "out": 1, "dyn": 1},
	"valo": {"len": 4, "th": 2, "gap": 3, "dot": 0, "out": 1, "dyn": 0},
	"dot": {"len": 0, "th": 2, "gap": 0, "dot": 4, "out": 1, "dyn": 0},
	"tiny": {"len": 3, "th": 1, "gap": 2, "dot": 0, "out": 1, "dyn": 0},
	"big": {"len": 12, "th": 3, "gap": 6, "dot": 0, "out": 1, "dyn": 1},
}
const XH_COLORS := [Color.WHITE, Color(0.3, 1, 0.4), Color(1, 1, 0.2), Color(0.2, 1, 1), Color(1, 0.3, 1), Color(1, 0.25, 0.25)]

signal changed


func _ready() -> void:
	load_settings()


func key_for(action: String) -> int:
	if keys.has(action):
		return int(keys[action])
	for g in KEY_ACTIONS:
		for a in g[1]:
			if a[1] == action:
				return a[2]
	return KEY_NONE


func is_down(action: String) -> bool:
	var k := key_for(action)
	return k != KEY_NONE and Input.is_physical_key_pressed(k)


## 이 키 눌림이 어떤 동작인지 ("" = 아무것도 아님)
func action_of(e: InputEventKey) -> String:
	for g in KEY_ACTIONS:
		for a in g[1]:
			if key_for(a[1]) == e.physical_keycode:
				return a[1]
	return ""


func key_label(code: int) -> String:
	if code == KEY_NONE:
		return "없음"
	if code == KEY_QUOTELEFT:
		return "~"
	return OS.get_keycode_string(code)


func get_loadout() -> Array:
	var W = preload("res://scripts/game_data.gd")
	var out: Array = []
	var src: Array = loadout if loadout.size() == 3 else W.DEFAULT_LOADOUT
	for i in 3:
		var s: Dictionary = src[i] if i < src.size() else W.DEFAULT_LOADOUT[i]
		var w: Dictionary = W.weapon(s.get("id", ""))
		var ok: bool = W.weapons().has(s.get("id", "")) and (w.side if i == 2 else not w.side)
		if not ok:
			s = W.DEFAULT_LOADOUT[i]
		out.append(s.duplicate())
	return out


func save_settings() -> void:
	var c := ConfigFile.new()
	for p in ["nick", "sens", "ads_sens", "fov", "quality", "volume", "aim_mode", "sprint_mode", "crouch_mode", "lean_mode", "difficulty", "armor", "map_id", "loadout", "keys", "xh"]:
		c.set_value("s", p, get(p))
	c.save(PATH)
	changed.emit()


func load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	for p in c.get_section_keys("s"):
		if p in self:
			set(p, c.get_value("s", p))
