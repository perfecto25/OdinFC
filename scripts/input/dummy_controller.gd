class_name DummyController
extends Node
## Training dummy for greybox testing. The fight manager sets the mode (F1 cycles opponents).

enum Mode { IDLE, GUARD, PARRY_SPAM, JAB_SPAM, CHECK, CLINCHER }

var mode := Mode.IDLE
var me: Fighter  ## the fighter this dummy drives
var _frame := 0

func _physics_process(_delta: float) -> void:
	_frame += 1

func mode_name() -> String:
	return Mode.keys()[mode]

func get_move() -> Vector2:
	return Vector2.ZERO

func is_guard_held() -> bool:
	match mode:
		Mode.GUARD:
			return true
		Mode.PARRY_SPAM:
			return _frame % 30 < 10
	return false

func poll_attack() -> StringName:
	match mode:
		Mode.JAB_SPAM:
			if _frame % 40 == 0:
				return &"jab"
		Mode.CHECK:
			if _frame % 36 == 0:
				return &"check"
		Mode.CLINCHER:
			# Outside the clinch: try to tie up. Inside: pummel, knee, and now and then a sweep.
			if me == null or me.state != Fighter.State.CLINCH:
				if _frame % 30 == 0:
					return &"clinch"
			elif _frame % 25 == 0:
				var r := _frame / 25 % 4
				return [&"clinch", &"knee", &"knee", &"round_kick_body"][r]
	return &""
