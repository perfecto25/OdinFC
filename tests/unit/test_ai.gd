extends GutTest
## CPU opponent: perception lag, defensive reads, punishing, clinch play, footwork, pacing, difficulty.

## Scripted opponent: throws queued moves (one per `gap` frames), otherwise stands still.
class Ctl extends Node:
	var queue: Array[StringName] = []
	var gap := 0
	var _wait := 0
	func get_move() -> Vector2: return Vector2.ZERO
	func is_guard_held() -> bool: return false
	func poll_attack() -> StringName:
		_wait -= 1
		if _wait > 0 or queue.is_empty():
			return &""
		_wait = gap
		return queue.pop_front()

var a: Fighter   ## scripted
var b: Fighter   ## AI
var ca: Ctl
var ai: AIController
var outcomes: Array = []

func before_each():
	outcomes.clear()
	a = _fighter(Vector3(-0.6, 0, 0))
	b = _fighter(Vector3(0.6, 0, 0))
	a.opponent = b
	b.opponent = a
	ca = Ctl.new()
	_own(ca)
	a.controller = ca
	a.move_resolved.connect(func(_x, _y, _m, r): outcomes.append(r.outcome))

func _fighter(pos: Vector3) -> Fighter:
	var f: Fighter = load("res://scenes/fighter.tscn").instantiate()
	_own(f)
	f.set_physics_process(false)
	f.setup(Color.RED, pos)
	f.global_position = pos
	return f

## An AI with a hand-set profile (perfect defense by default, so tests aren't dice rolls).
func _ai(p: AIController.Profile = null, seed := 1) -> AIController:
	if p == null:
		p = AIController.Profile.for_difficulty(AIController.Difficulty.HARD)
		p.defense = 1.0
		p.read = 1.0
		p.parry = 0.0
		p.counter = 0.0
		p.aggression = 0.0
		p.shell = 0.0
		p.punish = 0.0
	var c := AIController.new(p, seed)
	c.me = b
	_own(c)
	b.controller = c
	return c

func _tick(n: int) -> void:
	for i in n:
		a.tick()
		b.tick()

# --- perception + defense ---

func test_checks_a_low_kick_it_sees_coming():
	ai = _ai()
	ca.queue = [&"round_kick_low"]
	_tick(40)
	assert_eq(outcomes, [CombatResolver.Outcome.CHECKED])

func test_guards_a_high_kick_it_sees_coming():
	ai = _ai()
	ca.queue = [&"round_kick_high"]
	_tick(40)
	assert_eq(outcomes, [CombatResolver.Outcome.BLOCK])

func test_parries_a_cross_with_good_timing():
	var p := AIController.Profile.for_difficulty(AIController.Difficulty.HARD)
	p.defense = 1.0
	p.read = 1.0
	p.parry = 1.0
	p.counter = 0.0
	p.aggression = 0.0
	p.shell = 0.0
	p.punish = 0.0
	p.reaction = 2  # a cross is 7 frames: only very fast eyes can time the parry
	ai = _ai(p)
	ca.queue = [&"cross"]
	_tick(30)
	assert_eq(outcomes, [CombatResolver.Outcome.PARRY])

func test_slow_reactions_miss_the_same_kick():
	var p := AIController.Profile.for_difficulty(AIController.Difficulty.HARD)
	p.defense = 1.0
	p.read = 1.0
	p.aggression = 0.0
	p.shell = 0.0
	p.reaction = 30  # sees the kick only after it has landed
	ai = _ai(p)
	ca.queue = [&"round_kick_high"]
	_tick(40)
	assert_eq(outcomes, [CombatResolver.Outcome.HIT])

func test_misread_guards_a_leg_kick_and_eats_it():
	var p := AIController.Profile.for_difficulty(AIController.Difficulty.HARD)
	p.defense = 1.0
	p.read = 0.0
	p.aggression = 0.0
	p.shell = 0.0
	p.counter = 0.0
	ai = _ai(p)
	ca.queue = [&"round_kick_low"]
	_tick(40)
	assert_eq(outcomes, [CombatResolver.Outcome.HIT], "guard doesn't cover the legs")

# --- offense ---

func test_punishes_a_staggered_opponent():
	var p := AIController.Profile.for_difficulty(AIController.Difficulty.HARD)
	p.punish = 1.0
	p.aggression = 0.0
	ai = _ai(p)
	a.stun_frames = 40
	a.state = Fighter.State.STAGGER
	var head_before: float = a.body.hp[MoveData.Zone.HEAD] + a.body.hp[MoveData.Zone.BODY] + a.body.hp[MoveData.Zone.LEGS]
	for i in 40:
		b.tick()
	var after: float = a.body.hp[MoveData.Zone.HEAD] + a.body.hp[MoveData.Zone.BODY] + a.body.hp[MoveData.Zone.LEGS]
	assert_lt(after, head_before, "a free shot at a staggered opponent should land")

func test_walks_in_and_attacks_from_long_range():
	var p := AIController.Profile.for_difficulty(AIController.Difficulty.HARD)
	p.aggression = 1.0
	ai = _ai(p)
	b.global_position = Vector3(2.5, 0, 0)
	var thrown := [0]
	b.attack_started.connect(func(_f, _m): thrown[0] += 1)
	_tick(180)
	assert_gt(thrown[0], 0, "an aggressive AI should close the distance and throw")

func test_rests_when_out_of_gas():
	var p := AIController.Profile.for_difficulty(AIController.Difficulty.HARD)
	p.aggression = 1.0
	p.gas = 1.0
	ai = _ai(p)
	var thrown := [0]
	b.attack_started.connect(func(_f, _m): thrown[0] += 1)
	for i in 30:
		b.stam.value = 5.0
		a.tick()
		b.tick()
	assert_eq(thrown[0], 0, "a paced fighter doesn't throw on an empty tank")

# --- footwork ---

func test_steers_off_the_ropes():
	ai = _ai()
	b.global_position = Vector3(Fighter.RING_HALF, 0, Fighter.RING_HALF)
	a.global_position = Vector3(Fighter.RING_HALF - 1.2, 0, Fighter.RING_HALF)
	_tick(1)
	var corner := Vector2(1, 1).normalized()
	assert_lt(ai.get_move().dot(corner), 0.0, "should move out of the corner")

func test_steers_off_the_cage_fence():
	ai = _ai()
	for f in [a, b]:
		f.bounds = ArenaBounds.cage()
	var out := Vector2(1, 1).normalized()
	var p := out * (ArenaBounds.CAGE_RADIUS - 0.05)
	b.global_position = Vector3(p.x, 0, p.y)
	var q := out * (ArenaBounds.CAGE_RADIUS - 1.3)
	a.global_position = Vector3(q.x, 0, q.y) + Vector3(0.2, 0, -0.2)
	_tick(1)
	assert_lt(ai.get_move().dot(out), 0.0, "should move off the fence toward the centre")

# --- clinch ---

func test_dominant_clinch_throws_knees():
	var p := AIController.Profile.for_difficulty(AIController.Difficulty.HARD)
	ai = _ai(p)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var c := Clinch.new(b, a, rng)
	c.advantage = 0.9  # the AI (fighters[0]) is dominant
	var knees := [0]
	b.attack_started.connect(func(_f, m): if m.strike_type == MoveData.StrikeType.KNEE: knees[0] += 1)
	for i in 120:
		a.tick()
		b.tick()
		c.tick()
		if not c.active:
			break
	assert_gt(knees[0], 0)

func test_clinch_ref_cleared_when_clinch_ends():
	var rng := RandomNumberGenerator.new()
	var c := Clinch.new(a, b, rng)
	assert_eq(a.clinch, c)
	c.end(&"break")
	assert_null(a.clinch)
	assert_null(b.clinch)

# --- whole fights ---

func _fight(da: AIController.Difficulty, db: AIController.Difficulty, seed: int) -> FightFlow:
	var c1 := AIController.create(da, seed * 2 + 1)
	var c2 := AIController.create(db, seed * 2 + 2)
	_own(c1)
	_own(c2)
	c1.me = a
	c2.me = b
	a.controller = c1
	b.controller = c2
	var f := FightFlow.new(a, b, {"rounds": 1, "round_seconds": 60, "rest_seconds": 0, "seed": seed})
	while f.phase != FightFlow.Phase.OVER:
		f.tick()
	return f

func test_same_seed_same_fight():
	var f1 := _fight(AIController.Difficulty.MEDIUM, AIController.Difficulty.MEDIUM, 9)
	var r1 := [f1.result.method, f1.result.time, a.body.hp.duplicate(), b.body.hp.duplicate()]
	after_each()
	before_each()
	var f2 := _fight(AIController.Difficulty.MEDIUM, AIController.Difficulty.MEDIUM, 9)
	var r2 := [f2.result.method, f2.result.time, a.body.hp.duplicate(), b.body.hp.duplicate()]
	assert_eq(r1, r2)

func test_hard_outscores_easy():
	var hard_better := 0
	for s in 4:
		after_each()
		before_each()
		var f := _fight(AIController.Difficulty.HARD, AIController.Difficulty.EASY, s)
		var pa: float = f.stats[0][0].total_points()
		var pb: float = f.stats[0][1].total_points()
		if f.result.winner_index == 0 or (f.result.winner_index < 0 and pa > pb):
			hard_better += 1
	assert_gte(hard_better, 3, "Hard should beat Easy in most one-round fights")

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
