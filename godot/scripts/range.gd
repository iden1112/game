extends Node
## 훈련장 (사격 연습): 거리별 과녁, 움직이는 과녁, 방어구 레벨별 허수아비, 기록

const G = preload("res://scripts/game_data.gd")
const DummyScript = preload("res://scripts/dummy.gd")

var game
var dummies: Array = []
var shots := 0
var hits := 0
var heads := 0
var kills := 0
var last := ""
var _moving := false
var _armor_shift := 0


func start() -> void:
	clear()
	game.world.build("range")
	# 거리별 과녁 (방어구 없음) + 방어구 레벨별 허수아비
	var dists := [10, 25, 50, 75, 100, 150, 200]
	for i in dists.size():
		_spawn(Vector3(-12 + (i % 2) * 4, 0, 30 - dists[i]), 0)
	for lv in 4:
		_spawn(Vector3(6 + lv * 3, 0, 10), lv)
	reset_stats()


func _spawn(p: Vector3, lv: int) -> void:
	var d := CharacterBody3D.new()
	d.set_script(DummyScript)
	d.display_name = "허수아비" if lv > 0 or p.x > 0 else "과녁"
	d.game = game
	d.team = 9
	game.add_child(d)
	d.place(p, (lv + _armor_shift) % 4 if p.x > 0 else lv)
	d.moving = _moving and p.x < 0
	dummies.append(d)


func clear() -> void:
	for d in dummies:
		d.queue_free()
	dummies.clear()


func toggle_moving() -> void:
	_moving = not _moving
	for d in dummies:
		if d.home.x < 0:
			d.moving = _moving
	game.hud.toast("과녁 움직이기 " + ("켜짐" if _moving else "꺼짐"))


func cycle_dummy_armor() -> void:
	_armor_shift = (_armor_shift + 1) % 4
	for d in dummies:
		if d.home.x > 0:
			d.place(d.home, (int((d.home.x - 6) / 3) + _armor_shift) % 4)
	game.hud.toast("허수아비 방어구를 바꿨어요")


func reset_stats() -> void:
	shots = 0
	hits = 0
	heads = 0
	kills = 0
	last = ""


func on_hit(victim, part: String, dmg: float, dist: float) -> void:
	hits += 1
	if part == "head":
		heads += 1
	last = "%s · %s · 피해 %.0f · %dm%s" % [victim.display_name, {"head": "머리", "torso": "몸", "leg": "다리"}.get(part, part), dmg, int(dist), (" · 헬멧 Lv.%d" % victim.helmet_lv) if part == "head" and victim.helmet_lv > 0 else ((" · 조끼 Lv.%d" % victim.vest_lv) if part == "torso" and victim.vest_lv > 0 else "")]
	if victim.health - dmg <= 0.0:
		kills += 1


func hud_text() -> String:
	var acc := 0.0 if shots == 0 else float(hits) / shots * 100.0
	return "훈련장\n쏜 총알 %d · 맞힘 %d · 명중률 %.0f%%\n헤드샷 %d · 쓰러뜨림 %d\n마지막: %s\n\nTab 훈련장 메뉴 · ~ 총 고르기" % [shots, hits, acc, heads, kills, last if last != "" else "-"]
