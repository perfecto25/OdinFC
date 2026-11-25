extends GutTest
## Leg kicks vs checks.

class Ctl extends Node:
	var queue: Array[StringName] = []
	func get_move() -> Vector2: return Vector2.ZERO
	func is_guard_held() -> bool: return false
	func poll_attack() -> StringName:
		return queue.pop_front() if not queue.is_empty() else &""

var rng := RandomNumberGenerator.new()

func _move(id: StringName) -> MoveData:
	return MoveLibrary.all()[id]

func _checking() -> CombatResolver.Snapshot:
	var s := CombatResolver.Snapshot.new()
	s.checking = true
	return s

func test_check_stops_low_kick_and_hurts_kicker():
	var r := CombatResolver.resolve(_move(&"round_kick_low"), CombatResolver.Snapshot.new(), _checking(), rng)
	assert_eq(r.outcome, CombatResolver.Outcome.CHECKED)
	assert_gt(r.attacker_damage, r.damage, "the kicker's leg should take more than the checker's")
	assert_gt(r.attacker_stagger, 0)

func test_check_blocks_body_kick():
	var r := CombatResolver.resolve(_move(&"round_kick_body"), CombatResolver.Snapshot.new(), _checking(), rng)
	assert_eq(r.outcome, CombatResolver.Outcome.BLOCK)

func test_check_blocks_teep():
	var r := CombatResolver.resolve(_move(&"teep"), CombatResolver.Snapshot.new(), _checking(), rng)
	assert_eq(r.outcome, CombatResolver.Outcome.BLOCK)

func test_punch_beats_check():
	var r := CombatResolver.resolve(_move(&"cross"), CombatResolver.Snapshot.new(), _checking(), rng)
	assert_eq(r.outcome, CombatResolver.Outcome.HIT)

func test_high_kick_goes_over_check():
	var r := CombatResolver.resolve(_move(&"round_kick_high"), CombatResolver.Snapshot.new(), _checking(), rng)
	assert_eq(r.outcome, CombatResolver.Outcome.HIT)

# --- in the fighter ---

var a: Fighter
var b: Fighter
var ca: Ctl
var cb: Ctl

func before_each():
	rng.seed = 1
	a = _fighter(Vector3(-0.7, 0, 0))
	b = _fighter(Vector3(0.7, 0, 0))
	a.opponent = b
	b.opponent = a
	ca = Ctl.new()
	cb = Ctl.new()
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

func test_timed_check_punishes_low_kick():
	ca.queue = [&"check"]
	cb.queue = [&"round_kick_low"]
	_run(16)
	assert_lt(b.body.hp[MoveData.Zone.LEGS], a.body.hp[MoveData.Zone.LEGS])
	assert_lt(a.body.hp[MoveData.Zone.LEGS], BodyDamage.MAX_HP, "checking still costs the checker a little")
	assert_eq(b.state, Fighter.State.STAGGER)

func test_check_too_late_eats_the_kick():
	cb.queue = [&"round_kick_low"]
	_run(10)
	ca.queue = [&"check"]  # shin not up until 3 frames later; kick lands first
	_run(6)
	assert_eq(b.body.hp[MoveData.Zone.LEGS], BodyDamage.MAX_HP)
	assert_lt(a.body.hp[MoveData.Zone.LEGS], BodyDamage.MAX_HP)

func test_whiffed_check_has_recovery():
	ca.queue = [&"check"]
	a.tick()
	assert_eq(a.state, Fighter.State.CHECK)
	ca.queue = [&"jab"]
	for i in 10:
		a.tick()
	assert_eq(a.state, Fighter.State.CHECK, "can't act out of a check early")
	for i in Fighter.CHECK_STARTUP + Fighter.CHECK_ACTIVE + Fighter.CHECK_RECOVERY:
		a.tick()
	assert_ne(a.state, Fighter.State.CHECK)

func test_check_costs_stamina():
	ca.queue = [&"check"]
	a.tick()
	assert_almost_eq(a.stam.value, Stamina.MAX - Fighter.CHECK_COST, 0.001)

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
