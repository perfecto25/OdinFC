extends GutTest
## Opponent-relative movement, double-tap lunges and the moves that travel.

class Idle extends Node:
	func get_move() -> Vector2: return Vector2.ZERO
	func is_guard_held() -> bool: return false
	func poll_attack() -> StringName: return &""

func _pair(gap: float) -> Array[Fighter]:
	var out: Array[Fighter] = []
	for x in [-gap * 0.5, gap * 0.5]:
		var f: Fighter = load("res://scenes/fighter.tscn").instantiate()
		add_child_autofree(f)
		f.set_physics_process(false)
		f.setup(Color.RED, Vector3(x, 0, 0))
		var c := Idle.new()
		add_child_autofree(c)
		f.controller = c
		out.append(f)
	out[0].opponent = out[1]
	out[1].opponent = out[0]
	for f in out:
		f.tick()  # turn to face each other
	return out

func _gap(p: Array[Fighter]) -> float:
	return p[0].global_position.distance_to(p[1].global_position)

func test_up_is_always_toward_the_opponent():
	var p := _pair(2.0)
	for angle in [0.0, 1.3, PI, -2.2]:  # wherever the opponent has circled to
		p[1].position = p[0].position + Vector3(cos(angle), 0, sin(angle)) * 2.0
		p[0].tick()
		var to := Vector2(cos(angle), sin(angle))
		var up := PlayerController.facing_relative(Vector2(0, -1), p[0].global_basis)
		assert_almost_eq(up.dot(to), 1.0, 0.001, "forward")
		var down := PlayerController.facing_relative(Vector2(0, 1), p[0].global_basis)
		assert_almost_eq(down.dot(to), -1.0, 0.001, "back")
		var right := PlayerController.facing_relative(Vector2(1, 0), p[0].global_basis)
		assert_almost_eq(to.angle_to(right), PI / 2, 0.001, "sidestep to the fighter's right")

func test_double_tap():
	var c := PlayerController.new()
	autofree(c)
	assert_eq(c.register_tap("move_up", 10), &"")
	assert_eq(c.register_tap("move_up", 20), &"superman_punch")
	assert_eq(c.register_tap("move_up", 24), &"", "a third tap starts over")
	assert_eq(c.register_tap("move_down", 100), &"")
	assert_eq(c.register_tap("move_down", 100 + PlayerController.DOUBLE_TAP_FRAMES + 1), &"", "too slow")
	assert_eq(c.register_tap("move_up", 200), &"")
	assert_eq(c.register_tap("move_down", 203), &"")
	assert_eq(c.register_tap("move_up", 206), &"", "another direction in between")
	assert_eq(c.register_tap("move_down", 300), &"")
	assert_eq(c.register_tap("move_down", 305), &"dash_back")

func test_superman_punch_covers_ground_and_lands_from_range():
	var p := _pair(2.8)
	var m: MoveData = p[0].moves[&"superman_punch"]
	assert_gt(m.stamina_cost, p[0].moves[&"rear_hook"].stamina_cost)
	watch_signals(p[0])
	p[0]._start_attack(m)
	for i in m.total_frames():
		p[0].tick()
	assert_lt(_gap(p), 1.5)
	assert_gte(_gap(p), Fighter.LUNGE_STOP - 0.01)
	assert_signal_emitted(p[0], "move_resolved")

func test_dash_back_makes_room_without_striking():
	var p := _pair(1.0)
	var m: MoveData = p[0].moves[&"dash_back"]
	watch_signals(p[0])
	p[0]._start_attack(m)
	assert_false(p[0].is_committed_to_attack())
	for i in m.total_frames():
		p[0].tick()
	assert_almost_eq(_gap(p), 2.1, 0.1)
	assert_signal_not_emitted(p[0], "move_resolved")

func test_double_move_speed_is_for_one_fighter_only():
	var p := _pair(1.0)
	var base: MoveData = MoveLibrary.all()[&"uppercut"]
	var frames := base.total_frames()
	p[0].double_move_speed(&"uppercut")
	assert_eq((p[0].moves[&"uppercut"] as MoveData).total_frames(), 13)
	assert_eq((p[1].moves[&"uppercut"] as MoveData).total_frames(), frames)
	assert_eq((MoveLibrary.all()[&"uppercut"] as MoveData).total_frames(), frames)

func test_high_kick_has_its_own_key():
	InputSetup.register()
	assert_true(InputMap.has_action("round_kick_high"))
	assert_eq(PlayerController.ACTION_TO_MOVE["round_kick_high"], &"round_kick_high")
