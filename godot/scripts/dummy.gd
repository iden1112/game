extends "res://scripts/actor.gd"
## 훈련장 허수아비·과녁: 맞으면 쓰러졌다가 2초 뒤 다시 일어나요

var home := Vector3.ZERO
var moving := false
var _t := 0.0
var _revive := 0.0
var armor_lv := 0


func _ready() -> void:
	setup([Color(0.55, 0.5, 0.38), Color(0.4, 0.38, 0.3), Color(0.75, 0.65, 0.5)])
	set_loadout([{"id": "m416"}])


func place(p: Vector3, lv: int) -> void:
	home = p
	armor_lv = lv
	reset_for_round(p, PI, lv)


func _physics_process(dt: float) -> void:
	if game == null:
		return
	_t += dt
	if dead:
		_revive -= dt
		if _revive <= 0.0:
			reset_for_round(home, PI, armor_lv)
		physics_step(dt)
		return
	wish = Vector3.ZERO
	if moving:
		var off := sin(_t * 0.9) * 3.0
		var to := home + Vector3(off, 0, 0) - global_position
		to.y = 0
		wish = global_basis.inverse() * to.limit_length(1.0)
		wish.y = 0
	physics_step(dt)


func _die(from, info: Dictionary) -> void:
	super._die(from, info)
	_revive = 2.0
