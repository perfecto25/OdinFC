extends GutTest
## Drives two fighters frame by frame with scripted controllers.

class Script_ extends Node:
	var guard := false
	var queue: Array[StringName] = []
	func get_move() -> Vector2: return Vector2.ZERO
	func is_guard_held() -> bool: return guard
	func poll_attack() -> StringName:
		return queue.pop_front() if not queue.is_empty() else &""

var a: Fighter
var b: Fighter
var ca: Script_
var cb: Script_

func before_each():
	a = _fighter(Vector3(-0.6, 0, 0))
	b = _fighter(Vector3(0.6, 0, 0))
	a.opponent = b
	b.opponent = a
	ca = Script_.new()
	cb = Script_.new()
	_own(ca)
	_own(cb)
	a.controller = ca
	b.controller = cb

func _fighter(pos: Vector3) -> Fighter:
	var f: Fighter = load("res://scenes/fighter.tscn").instantiate()
	_own(f)
	f.set_physics_process(false)
	f.setup(Color.RED, pos)
	f.global_position = pos
	return f

func _run(n: int) -> void:
	for i in n:
		a.tick()
		b.tick()

func test_idle_by_default():
	_run(5)
	assert_eq(a.state, Fighter.State.IDLE)

func test_jab_follows_frame_data():
	ca.queue = [&"jab"]
	a.tick()
	assert_eq(a.state, Fighter.State.ATTACK)
	var jab: MoveData = MoveLibrary.all()[&"jab"]
	assert_eq(a.attack_phase(), &"startup")
	for i in jab.startup:
		a.tick()
	assert_eq(a.attack_phase(), &"startup")  # frames 1..startup are startup
	a.tick()
	assert_eq(a.attack_phase(), &"active")
	for i in jab.active + jab.recovery:
		a.tick()
	assert_eq(a.state, Fighter.State.IDLE)

func test_jab_lands_and_damages_head():
	ca.queue = [&"jab"]
	_run(12)
	assert_lt(b.body.hp[MoveData.Zone.HEAD], BodyDamage.MAX_HP)
	assert_eq(b.state, Fighter.State.HITSTUN)

func test_out_of_reach_whiffs():
	b.global_position = Vector3(3, 0, 0)
	ca.queue = [&"jab"]
	_run(12)
	assert_eq(b.body.hp[MoveData.Zone.HEAD], BodyDamage.MAX_HP)

func test_guard_blocks_jab():
	cb.guard = true
	_run(20)  # past the parry window
	ca.queue = [&"jab"]
	_run(12)
	assert_almost_eq(b.body.hp[MoveData.Zone.HEAD], BodyDamage.MAX_HP, 0.5)
	assert_lt(b.stam.value, Stamina.MAX)

func test_parry_staggers_attacker():
	cb.guard = true
	b.tick()  # guard just pressed -> inside parry window
	ca.queue = [&"jab"]
	_run(8)
	assert_eq(a.state, Fighter.State.STAGGER)
	assert_eq(b.body.hp[MoveData.Zone.HEAD], BodyDamage.MAX_HP)

func test_attack_costs_stamina():
	ca.queue = [&"cross"]
	a.tick()
	assert_almost_eq(a.stam.value, Stamina.MAX - 6.0, 0.001)

func test_input_buffer_queues_next_attack():
	ca.queue = [&"jab"]
	a.tick()
	# press cross during jab recovery; should fire right after the jab ends
	for i in 10:
		a.tick()
	ca.queue = [&"cross"]
	for i in 7:
		a.tick()
	assert_eq(a.state, Fighter.State.ATTACK)
	assert_eq(a.current_move.id, &"cross")

func test_counter_hit_hurts_more():
	var normal: float = MoveLibrary.all()[&"jab"].damage * CombatResolver.DAMAGE_SCALE
	# b starts a cross, a's jab (faster) lands during b's startup
	cb.queue = [&"cross"]
	ca.queue = [&"jab"]
	_run(10)
	var dealt: float = BodyDamage.MAX_HP - b.body.hp[MoveData.Zone.HEAD]
	assert_gt(dealt, normal)

func test_fatigue_slows_attacks():
	a.stam.value = 0.0
	ca.queue = [&"cross"]
	a.tick()
	var cross: MoveData = MoveLibrary.all()[&"cross"]
	for i in cross.startup + 1:
		a.tick()
	assert_eq(a.attack_phase(), &"startup", "tired fighter should still be winding up")

func test_body_damage_slows_stamina_recovery():
	a.stam.value = 50.0
	b.stam.value = 50.0
	b.body.hp[MoveData.Zone.BODY] = 0.0
	_run(30)
	assert_gt(a.stam.value, b.stam.value)

func test_leg_damage_slows_movement():
	assert_lt(_with_legs(0.0), _with_legs(100.0))

func _with_legs(hp: float) -> float:
	b.body.hp[MoveData.Zone.LEGS] = hp
	return Fighter.SPEED * b.body.speed_factor()

func test_knocked_down_fighter_cannot_be_hit():
	b.receive({"outcome": CombatResolver.Outcome.HIT, "damage": 0.0, "stun": 0, "knockdown": true, "cut_delta": 0.0},
		MoveLibrary.all()[&"jab"])
	assert_eq(b.state, Fighter.State.KNOCKDOWN)
	ca.queue = [&"jab"]
	_run(12)
	assert_eq(b.body.hp[MoveData.Zone.HEAD], BodyDamage.MAX_HP)

# Free test nodes immediately: queue_free()'d fighters linger in the physics world and push new ones apart.
var _owned: Array[Node] = []

func _own(n: Node) -> void:
	add_child(n)
	_owned.append(n)

func after_each():
	for n in _owned:
		if is_instance_valid(n):
			n.free()
	_owned.clear()

# --- slip ---

func _capture() -> Array:
	var got := []
	a.move_resolved.connect(func(_x, _y, _m, r): got.append(r))
	b.move_resolved.connect(func(_x, _y, _m, r): got.append(r))
	return got

func test_slip_makes_a_cross_miss_and_opens_a_counter():
	var got := _capture()
	ca.queue = [&"cross"]
	cb.queue = [&"slip"]
	_run(25)
	assert_eq(got.size(), 1)
	assert_eq(got[0].outcome, CombatResolver.Outcome.SLIPPED)
	assert_eq(b.body.hp[MoveData.Zone.HEAD], BodyDamage.MAX_HP)

func test_strike_out_of_a_slip_is_a_counter():
	var got := _capture()
	ca.queue = [&"cross"]
	cb.queue = [&"slip"]
	_run(14)
	assert_gt(b.slip_counter, 0)
	cb.queue = [&"jab"]
	_run(30)
	assert_eq(got.size(), 2)
	assert_true(got[1].counter, "a strike thrown right after slipping counts as a counter")
	assert_eq(b.slip_counter, 0, "the counter window is spent")

func test_uppercut_catches_a_slip():
	b.global_position = Vector3(0.3, 0, 0)  # uppercut range
	var got := _capture()
	ca.queue = [&"uppercut"]
	cb.queue = [&"slip"]
	_run(25)
	assert_eq(got.size(), 1)
	assert_eq(got[0].outcome, CombatResolver.Outcome.HIT)

func test_slip_recovers_to_idle():
	cb.queue = [&"slip"]
	_run(Fighter.SLIP_STARTUP + Fighter.SLIP_ACTIVE + Fighter.SLIP_RECOVERY + 2)
	assert_eq(b.state, Fighter.State.IDLE)
	assert_lt(b.stam.value, Stamina.MAX)
