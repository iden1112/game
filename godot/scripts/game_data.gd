extends RefCounted
## 게임 수치 — 웹 버전(훈련장 1v1.html)의 값을 그대로 옮겼어요.

const MAX_HP := 150.0
const RADIUS := 0.33
const STEP := 0.46
const JUMP_V := 6.1
const GRAVITY := 15.0 # 사람
const BULLET_G := 9.8 # 총알·수류탄
const WIN_SCORE := 7
const ROUND_TIME := 150.0

const STANCE := {
	"stand": {"h": 1.8, "eye": 1.62, "speed": 4.7, "sprint": 6.0, "recoil": 1.0, "spread": 1.0},
	"crouch": {"h": 1.25, "eye": 1.12, "speed": 2.6, "sprint": 4.0, "recoil": 0.8, "spread": 0.8},
	"prone": {"h": 0.6, "eye": 0.38, "speed": 1.15, "sprint": 1.15, "recoil": 0.55, "spread": 0.6},
}

# [id, 이름, 분류, 탄, 피해, 탄속(m/s), 발사간격(s), 탄창, 대용량탄창, 재장전(s), 사격모드, 수직반동(도), 수평반동, 최대조준경, 파츠칸]
# 파츠칸: m=총구 g=손잡이 x=탄창 s=개머리판 / 최대조준경: SCOPES 번호 (-1 = 일체형)
const WEAPON_TABLE := [
	["m416", "M416", "AR", "5.56×45mm NATO", 40, 880, 0.0857, 30, 40, 2.1, "SA", 0.42, 0.20, 7, "mgxs"],
	["akm", "AKM", "AR", "7.62×39mm", 47, 715, 0.100, 30, 40, 2.7, "SA", 0.74, 0.30, 7, "mx"],
	["beryl", "Beryl M762", "AR", "7.62×39mm", 44, 715, 0.086, 30, 40, 2.9, "SBA", 0.84, 0.38, 7, "mgx"],
	["scar", "SCAR-L", "AR", "5.56×45mm NATO", 42, 870, 0.096, 30, 40, 2.2, "SA", 0.45, 0.22, 7, "mgx"],
	["aug", "AUG", "AR", "5.56×45mm NATO", 41, 940, 0.0857, 30, 40, 3.0, "SA", 0.40, 0.21, 7, "mgx"],
	["groza", "Groza", "AR", "7.62×39mm", 47, 715, 0.080, 30, 40, 3.0, "SA", 0.62, 0.30, 5, "mx"],
	["qbz", "QBZ95", "AR", "5.8×42mm", 42, 870, 0.092, 30, 40, 2.8, "SA", 0.45, 0.22, 7, "mgx"],
	["g36c", "G36C", "AR", "5.56×45mm NATO", 41, 870, 0.086, 30, 40, 2.5, "SA", 0.44, 0.22, 5, "mgx"],
	["m16", "M16A4", "AR", "5.56×45mm NATO", 43, 900, 0.075, 30, 40, 2.3, "SB", 0.48, 0.20, 7, "mx"],
	["mk47", "Mk47 Mutant", "AR", "7.62×39mm", 49, 780, 0.100, 20, 30, 2.7, "SB", 0.70, 0.30, 7, "mgx"],
	["ace32", "ACE32", "AR", "7.62×39mm", 43, 715, 0.088, 30, 40, 2.6, "SA", 0.60, 0.26, 7, "mgxs"],
	["famas", "FAMAS", "AR", "5.56×45mm NATO", 39, 925, 0.0667, 25, 35, 2.8, "SBA", 0.50, 0.26, 7, "mx"],
	["ump", "UMP45", "SMG", ".45 ACP", 41, 360, 0.092, 25, 35, 2.4, "SBA", 0.32, 0.15, 5, "mgx"],
	["vector", "Vector", "SMG", ".45 ACP", 31, 380, 0.055, 19, 33, 1.9, "SBA", 0.42, 0.20, 3, "mgxs"],
	["uzi", "Micro UZI", "SMG", "9×19mm 파라벨룸", 26, 350, 0.048, 25, 35, 2.2, "SA", 0.30, 0.18, 1, "mxs"],
	["tommy", "Tommy Gun", "SMG", ".45 ACP", 40, 280, 0.086, 30, 50, 3.0, "SA", 0.38, 0.20, 0, "mgx"],
	["bizon", "PP-19 Bizon", "SMG", "9×18mm 마카로프", 35, 408, 0.086, 53, 53, 3.2, "SA", 0.30, 0.15, 5, "m"],
	["mp5k", "MP5K", "SMG", "9×19mm 파라벨룸", 33, 400, 0.067, 30, 40, 2.4, "SBA", 0.32, 0.15, 5, "mgxs"],
	["p90", "P90", "SMG", "5.7×28mm", 35, 715, 0.060, 50, 50, 2.5, "A", 0.28, 0.15, 5, ""],
	["js9", "JS9", "SMG", "9×19mm 파라벨룸", 34, 400, 0.067, 30, 40, 2.4, "SA", 0.28, 0.14, 5, "mgx"],
	["sks", "SKS", "DMR", "7.62×39mm", 53, 800, 0.090, 10, 20, 2.9, "S", 1.30, 0.50, 8, "mgxs"],
	["slr", "SLR", "DMR", "7.62×51mm NATO", 56, 840, 0.100, 10, 20, 2.9, "S", 1.60, 0.60, 8, "mxs"],
	["mini14", "Mini14", "DMR", "5.56×45mm NATO", 48, 990, 0.100, 20, 30, 2.6, "S", 0.90, 0.35, 8, "mxs"],
	["mk14", "Mk14 EBR", "DMR", "7.62×51mm NATO", 61, 853, 0.090, 10, 20, 3.0, "SA", 1.60, 0.60, 8, "mxs"],
	["qbu", "QBU", "DMR", "5.8×42mm", 48, 945, 0.100, 10, 20, 2.6, "S", 0.90, 0.35, 8, "mx"],
	["vss", "VSS", "DMR", "9×39mm", 41, 330, 0.086, 10, 20, 2.6, "SA", 0.45, 0.25, -1, "gx"],
	["mk12", "Mk12", "DMR", "5.56×45mm NATO", 50, 930, 0.100, 20, 30, 2.6, "S", 1.00, 0.40, 8, "mgxs"],
	["dragunov", "Dragunov", "DMR", "7.62×54mmR", 60, 830, 0.150, 10, 20, 3.2, "S", 1.70, 0.60, 8, "mxs"],
	["kar98k", "Kar98k", "SR", "7.92×57mm 마우저", 79, 760, 1.90, 5, 5, 4.0, "S", 2.5, 0.6, 8, "mxs"],
	["m24", "M24", "SR", "7.62×51mm NATO", 75, 790, 1.80, 5, 7, 3.4, "S", 2.4, 0.6, 8, "mxs"],
	["awm", "AWM", "SR", ".300 윈체스터 매그넘", 105, 945, 1.85, 5, 7, 4.0, "S", 3.0, 0.7, 8, "mxs"],
	["mosin", "Mosin Nagant", "SR", "7.62×54mmR", 79, 870, 1.90, 5, 5, 4.0, "S", 2.5, 0.6, 8, "mxs"],
	["win94", "Win94", "SR", ".30-30 윈체스터", 66, 760, 1.30, 8, 8, 4.0, "S", 2.2, 0.6, 2, "m"],
	["lynx", "Lynx AMR", "SR", ".50 BMG (12.7×99mm)", 118, 1000, 1.80, 5, 5, 4.5, "S", 4.0, 0.8, 8, ""],
	["s1897", "S1897", "SG", "12게이지 산탄", 26, 360, 0.75, 5, 5, 3.0, "S", 3.5, 0.8, 1, "m"],
	["s686", "S686", "SG", "12게이지 산탄", 26, 370, 0.20, 2, 2, 2.2, "S", 3.5, 0.8, 0, "m"],
	["s12k", "S12K", "SG", "12게이지 산탄", 24, 350, 0.25, 5, 8, 2.6, "S", 3.0, 0.8, 2, "mx"],
	["dbs", "DBS", "SG", "12게이지 산탄", 26, 400, 0.30, 14, 14, 4.5, "S", 3.2, 0.8, 2, ""],
	["o12", "O12", "SG", "12게이지 슬러그", 30, 350, 0.20, 5, 8, 2.6, "SA", 3.0, 0.8, 2, "mx"],
	["sawed", "Sawed-off", "SG", "12게이지 산탄", 21, 340, 0.20, 2, 2, 2.0, "S", 3.5, 0.8, 0, ""],
	["m249", "M249", "LMG", "5.56×45mm NATO", 41, 915, 0.075, 75, 150, 6.5, "A", 0.48, 0.22, 7, ""],
	["dp28", "DP-28", "LMG", "7.62×54mmR", 52, 715, 0.109, 47, 47, 4.5, "A", 0.60, 0.25, 7, ""],
	["mg3", "MG3", "LMG", "7.62×51mm NATO", 42, 820, 0.060, 75, 75, 6.5, "A", 0.60, 0.28, 7, ""],
	["crossbow", "석궁", "XB", "석궁 볼트(화살)", 105, 100, 0.3, 1, 1, 3.4, "S", 1.0, 0.25, 5, ""],
	["p92", "P92", "HG", "9×19mm 파라벨룸", 34, 380, 0.135, 15, 20, 2.0, "S", 0.9, 0.4, 2, "mx"],
	["p1911", "P1911", "HG", ".45 ACP", 42, 250, 0.110, 7, 12, 2.1, "S", 1.1, 0.5, 2, "mx"],
	["p18c", "P18C", "HG", "9×19mm 파라벨룸", 23, 375, 0.060, 17, 25, 2.0, "SA", 0.7, 0.4, 2, "mx"],
	["r1895", "R1895", "HG", "7.62×38mmR 나강", 64, 330, 0.40, 7, 7, 3.0, "S", 1.6, 0.6, 2, "m"],
	["r45", "R45", "HG", ".45 ACP", 65, 330, 0.25, 6, 6, 2.2, "S", 1.6, 0.6, 2, ""],
	["deagle", "Desert Eagle", "HG", ".50 AE", 62, 420, 0.20, 7, 10, 2.2, "S", 2.2, 0.7, 2, "x"],
	["skorpion", "Skorpion", "HG", ".32 ACP (7.65×17mm)", 22, 300, 0.070, 20, 40, 2.6, "SA", 0.45, 0.25, 2, "gxs"],
]

const CAT_NAME := {"AR": "돌격소총", "SMG": "기관단총", "DMR": "지정사수소총", "SR": "저격소총", "SG": "산탄총", "LMG": "경기관총", "HG": "권총", "XB": "석궁"}
const CAT_ORDER := ["AR", "SMG", "DMR", "SR", "SG", "LMG", "HG", "XB"]
const CAT_INFO := {
	"AR": {"body": 1.0, "head": 2.35, "limb": 0.9, "hip": 2.2, "ads": 0.06, "adsTime": 0.22, "move": 0.97, "falloff": [120.0, 400.0, 0.75]},
	"SMG": {"body": 1.05, "head": 2.1, "limb": 1.3, "hip": 1.5, "ads": 0.10, "adsTime": 0.17, "move": 1.0, "falloff": [40.0, 150.0, 0.6]},
	"DMR": {"body": 1.05, "head": 2.35, "limb": 0.95, "hip": 2.6, "ads": 0.02, "adsTime": 0.28, "move": 0.95, "falloff": [200.0, 600.0, 0.8]},
	"SR": {"body": 1.3, "head": 6.0, "limb": 0.95, "hip": 3.5, "ads": 0.0, "adsTime": 0.32, "move": 0.94, "falloff": [300.0, 800.0, 0.85]},
	"SG": {"body": 0.9, "head": 1.5, "limb": 1.05, "hip": 3.6, "ads": 2.6, "adsTime": 0.22, "move": 0.97, "falloff": [7.0, 30.0, 0.08]},
	"LMG": {"body": 1.05, "head": 2.3, "limb": 0.9, "hip": 3.0, "ads": 0.10, "adsTime": 0.35, "move": 0.9, "falloff": [120.0, 400.0, 0.75]},
	"HG": {"body": 1.0, "head": 2.1, "limb": 1.0, "hip": 1.6, "ads": 0.15, "adsTime": 0.15, "move": 1.08, "falloff": [30.0, 120.0, 0.6]},
	"XB": {"body": 1.4, "head": 2.3, "limb": 1.2, "hip": 2.4, "ads": 0.0, "adsTime": 0.26, "move": 0.98, "falloff": [500.0, 900.0, 1.0]},
	"FIST": {"body": 1.0, "head": 2.0, "limb": 0.8, "hip": 0.0, "ads": 0.0, "adsTime": 0.2, "move": 1.1, "falloff": [100.0, 200.0, 1.0]},
}
# 벽 뚫은 뒤 남는 피해 비율 (기관단총·권총·산탄총·석궁은 못 뚫어요)
const WALLBANG := {"AR": 0.55, "DMR": 0.6, "SR": 0.65, "LMG": 0.55}
# 꺼내는 시간
const DRAW_TIME := {"HG": 0.4, "SMG": 0.5, "SG": 0.6, "AR": 0.6, "DMR": 0.7, "SR": 0.8, "LMG": 0.9, "XB": 0.7}
# 한 발씩 넣는 총
const PER_SHELL := {"s1897": 0.5, "kar98k": 0.55, "mosin": 0.55, "win94": 0.45, "dbs": 0.5, "r1895": 0.4}

const SCOPES := [
	{"id": "iron", "name": "아이언 사이트", "zoom": 1.15},
	{"id": "reddot", "name": "레드 도트", "zoom": 1.25},
	{"id": "holo", "name": "홀로그램", "zoom": 1.25},
	{"id": "2x", "name": "2배율", "zoom": 2.0},
	{"id": "3x", "name": "3배율", "zoom": 3.0},
	{"id": "4x", "name": "4배율", "zoom": 4.0},
	{"id": "6x", "name": "6배율", "zoom": 6.0},
	{"id": "8x", "name": "8배율", "zoom": 8.0},
	{"id": "15x", "name": "15배율", "zoom": 15.0},
]
const ATT_NAME := {
	"muzzle": {"comp": "보정기", "flash": "소염기", "supp": "소음기", "choke": "초크", "duck": "덕빌"},
	"grip": {"vert": "수직 손잡이", "angled": "앵글 손잡이", "half": "하프 그립", "thumb": "엄지 그립", "light": "라이트 그립", "laser": "레이저 사이트"},
	"stock": {"tac": "전술 개머리판", "cheek": "칙패드", "loops": "총알 고리"},
	"mag": {"ext": "대용량 탄창", "qd": "퀵드로우 탄창", "extqd": "대용량 퀵드로우"},
}
const ATT_FX := {
	"muzzle": {
		"comp": {"rv": 0.85, "rh": 0.9, "shake": 0.7, "d": "수직 반동 -15% · 수평 반동 -10% · 화면 흔들림 -30%"},
		"flash": {"rv": 0.9, "rh": 0.9, "hide": 1, "d": "수직 반동 -10% · 수평 반동 -10% · 총구 불꽃 안 보임"},
		"supp": {"supp": 1, "hide": 1, "d": "총소리가 작아져 멀리서 잘 안 들림 · 총구 불꽃 안 보임 · AI가 위치를 잘 못 찾음"},
		"choke": {"spread": 0.75, "d": "산탄 퍼짐 -25%"},
		"duck": {"spreadV": 0.6, "spreadH": 1.15, "d": "산탄 세로 퍼짐 -40% · 가로로 넓게 퍼짐"},
	},
	"grip": {
		"vert": {"rv": 0.85, "d": "수직 반동 -15%"},
		"angled": {"rh": 0.85, "adsTime": 0.8, "d": "수평 반동 -15% · 조준 속도 +20%"},
		"half": {"rv": 0.92, "rh": 0.92, "recovery": 1.2, "d": "수직·수평 반동 -8% · 반동 회복 +20%"},
		"thumb": {"rv": 0.95, "adsTime": 0.7, "d": "수직 반동 -5% · 조준 속도 +30%"},
		"light": {"rh": 0.9, "recovery": 1.1, "sway": 0.85, "d": "수평 반동 -10% · 반동 회복 +10% · 흔들림 -15%"},
		"laser": {"hip": 0.7, "d": "비조준 사격 퍼짐 -30%"},
	},
	"mag": {
		"ext": {"ext": 1, "d": "탄창 크기 늘어남"},
		"qd": {"reload": 0.7, "d": "장전 시간 -30%"},
		"extqd": {"ext": 1, "reload": 0.7, "d": "탄창 크기 늘어남 · 장전 시간 -30%"},
	},
	"stock": {
		"tac": {"rv": 0.92, "rh": 0.9, "sway": 0.85, "d": "수직 반동 -8% · 수평 반동 -10% · 흔들림 -15%"},
		"cheek": {"rv": 0.85, "sway": 0.75, "d": "수직 반동 -15% · 조준경 흔들림 -25%"},
		"loops": {"reload": 0.75, "d": "한 발씩 넣는 장전 +25% 빠름"},
	},
}

const THROWABLES := {
	"frag": {"name": "세열 수류탄", "fuse": 5.0, "count": 2, "color": Color("3f4a2e")},
	"smoke": {"name": "연막탄", "fuse": 2.0, "count": 1, "color": Color("8a8f94")},
	"flash": {"name": "섬광탄", "fuse": 2.5, "count": 1, "color": Color("2d3a4d")},
}
const THROW_ORDER := ["frag", "smoke", "flash"]

const ARMOR_RED := [0.0, 0.3, 0.4, 0.55]
const HELMET_DUR := [0.0, 80.0, 150.0, 230.0]
const VEST_DUR := [0.0, 200.0, 220.0, 250.0]

const BOT_LEVELS := [
	{"name": "쉬움", "react": 0.85, "err": 4.6, "floor": 0.6, "turn": 2.8, "comp": 0.3, "head": 0.02, "burst": [3, 5], "pause": [0.5, 0.9]},
	{"name": "보통", "react": 0.6, "err": 3.2, "floor": 0.5, "turn": 4.2, "comp": 0.5, "head": 0.06, "burst": [3, 6], "pause": [0.35, 0.65]},
	{"name": "어려움", "react": 0.4, "err": 2.0, "floor": 0.4, "turn": 6.0, "comp": 0.7, "head": 0.14, "burst": [4, 8], "pause": [0.25, 0.45]},
	{"name": "프로", "react": 0.25, "err": 1.1, "floor": 0.32, "turn": 9.0, "comp": 0.85, "head": 0.28, "burst": [6, 10], "pause": [0.15, 0.3]},
]
const BOT_PRIMARY := ["m416", "m416", "akm", "beryl", "scar", "aug", "ace32", "mk47", "ump", "vector", "mini14", "sks", "kar98k", "m24", "slr", "g36c", "qbz", "groza", "m249"]
const BOT_SECONDARY := ["ump", "vector", "s12k", "mp5k", "s1897", "uzi", "p90", "js9"]
const BOT_PISTOL := ["p92", "p1911", "p18c", "deagle"]

const DEFAULT_LOADOUT := [
	{"id": "m416", "scope": "reddot", "muzzle": "comp", "grip": "vert"},
	{"id": "kar98k", "scope": "8x", "muzzle": "supp"},
	{"id": "p92", "muzzle": "supp"},
]

const LAYER_WORLD := 1
const LAYER_ACTOR := 2


static var _weapons: Dictionary = {}


## 총 정보 (id → 사전)
static func weapons() -> Dictionary:
	if _weapons.is_empty():
		for r in WEAPON_TABLE:
			var id: String = r[0]
			var cat: String = r[2]
			_weapons[id] = {
				"id": id, "name": r[1], "cat": cat, "ammo": r[3], "dmg": float(r[4]), "vel": float(r[5]), "interval": float(r[6]),
				"mag": int(r[7]), "ext": int(r[8]), "reload": float(r[9]), "modes": r[10], "rv": float(r[11]), "rh": float(r[12]),
				"scopeMax": int(r[13]), "slots": r[14],
				"pellets": (8 if id == "o12" else 9) if cat == "SG" else 1,
				"bolt": cat == "SR" and float(r[6]) > 1.0,
				"integrated": id == "vss",
				"side": cat == "HG" or id == "sawed",
			}
	return _weapons


static func weapon(id: String) -> Dictionary:
	return weapons().get(id, weapons()["m416"])


static func muzzle_options(w: Dictionary) -> Array:
	if not "m" in w.slots:
		return []
	if w.cat == "SG":
		return ["choke", "duck"]
	if w.cat == "HG":
		return ["supp"]
	return ["comp", "flash", "supp"]


static func grip_options(w: Dictionary) -> Array:
	return ATT_FX.grip.keys() if "g" in w.slots else []


static func mag_options(w: Dictionary) -> Array:
	return ["ext", "qd", "extqd"] if "x" in w.slots else []


static func stock_options(w: Dictionary) -> Array:
	if not "s" in w.slots:
		return []
	match w.cat:
		"SR":
			return ["cheek", "loops"]
		"DMR":
			return ["cheek"]
		"SG":
			return ["loops"]
	return ["tac"]


static func scope_options(w: Dictionary) -> Array:
	if w.scopeMax < 0:
		return []
	if w.cat == "SG":
		return ["iron"]
	var out := []
	for i in range(w.scopeMax + 1):
		out.append(SCOPES[i].id)
	return out


static func default_scope(w: Dictionary):
	var o := scope_options(w)
	if o.is_empty():
		return null
	var want: String = {"AR": "reddot", "SMG": "holo", "DMR": "4x", "SR": "8x", "SG": "reddot", "LMG": "reddot", "HG": "reddot", "XB": "reddot"}[w.cat]
	return want if want in o else o[o.size() - 1]


## 풀파츠 장착 (choice 에 "" 이면 '없음')
static func full_attachments(id: String, choice: Dictionary = {}) -> Dictionary:
	var w := weapon(id)
	var pick := func(key: String, opts: Array, def):
		if opts.is_empty():
			return null
		if choice.has(key):
			var v = choice[key]
			if v == "" or v == null:
				return null
			if v in opts:
				return v
		return def
	var so := stock_options(w)
	var scope = choice.get("scope")
	if not (scope in scope_options(w)):
		scope = default_scope(w)
	return {
		"scope": scope,
		"muzzle": pick.call("muzzle", muzzle_options(w), "choke" if w.cat == "SG" else ("supp" if w.cat == "HG" else "comp")),
		"grip": pick.call("grip", grip_options(w), "half" if w.cat == "DMR" else "vert"),
		"mag": pick.call("mag", mag_options(w), "extqd"),
		"stock": pick.call("stock", so, so[0] if not so.is_empty() else null),
	}


static func scope_zoom(id) -> float:
	for s in SCOPES:
		if s.id == id:
			return s.zoom
	return 1.15


## 파츠를 적용한 실제 수치
static func weapon_stats(id: String, att: Dictionary) -> Dictionary:
	var w := weapon(id)
	var c: Dictionary = CAT_INFO[w.cat]
	var s := {
		"def": w, "cat": w.cat, "mag": w.mag, "reload": w.reload, "rv": w.rv * 1.65, "rh": w.rh * 1.5, "hip": c.hip, "ads": c.ads, "adsTime": c.adsTime,
		"suppressed": w.integrated, "flashHidden": w.integrated, "pelletSpread": 4.2, "sway": 1.0, "recovery": 1.0, "scopeZoom": 1.15,
		"spreadMul": 1.0, "spreadV": 1.0, "spreadH": 1.0, "shake": 1.0,
	}
	if w.integrated:
		s.scopeZoom = 4.0
	if w.cat == "XB":
		s.suppressed = true
		s.flashHidden = true
	if att.get("scope") != null:
		s.scopeZoom = scope_zoom(att.scope)
	for key in ["muzzle", "grip", "mag", "stock"]:
		var a = att.get(key)
		if a == null or not ATT_FX[key].has(a):
			continue
		var fx: Dictionary = ATT_FX[key][a]
		for k in ["rv", "rh", "adsTime", "recovery", "sway", "hip", "reload", "shake"]:
			if fx.has(k):
				s[k] *= fx[k]
		if fx.has("ext"):
			s.mag = w.ext
		if fx.has("supp"):
			s.suppressed = true
		if fx.has("hide"):
			s.flashHidden = true
		if fx.has("spread"):
			s.spreadMul *= fx.spread
		if fx.has("spreadV"):
			s.spreadV *= fx.spreadV
		if fx.has("spreadH"):
			s.spreadH *= fx.spreadH
	if w.cat == "SG":
		s.pelletSpread *= s.spreadMul
		s.ads = s.pelletSpread * 0.7
		s.hip *= s.spreadMul
	return s


static func falloff_mul(cat: String, d: float) -> float:
	var f: Array = CAT_INFO[cat].falloff
	var d0: float = f[0]
	var d1: float = f[1]
	var m: float = f[2]
	if d <= d0:
		return 1.0
	if d >= d1:
		return maxf(0.02, m * (1.0 - (d - d1) / 30.0)) if cat == "SG" else m
	var k := (d - d0) / (d1 - d0)
	return lerpf(1.0, m, sqrt(k)) if cat == "SG" else lerpf(1.0, m, k)
