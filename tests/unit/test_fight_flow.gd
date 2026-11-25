extends GutTest
## Full fight flow, headless, with scripted controllers and short rounds.

class Bot extends Node:
	var guard := false
	var spam: StringName = &""
	var every := 20
	var _n := 0
	func get_move() -> Vector2: return Vector2.ZERO
	func is_guard_held() -> bool: return guard
	func poll_attack() -> StringName:
		_n += 1
		return spam if spam != &"" and _n % every == 0 else &""

var a: Fighter
var b: Fighter
var ba: Bot
var bb: Bot

func _setup_fight(cfg: Dictionary) -> FightFlow:
	a = _fighter(Vector3(-0.6, 0, 0))
	b = _fighter(Vector3(0.6, 0, 0))
	a.opponent = b
	b.opponent = a
	ba = Bot.new()
	bb = Bot.new()
	_own(ba)
	_own(bb)
	a.controller = ba
	b.controller = bb
	var f := FightFlow.new(a, b, cfg)
	f.start_positions = [Vector3(-0.6, 0, 0), Vector3(0.6, 0, 0)]  # in range
	f._start_round(1)  # re-place at the new start positions
	f.stats.pop_front()
	return f

func _fighter(pos: Vector3) -> Fighter:
	var f: Fighter = load("res://scenes/fighter.tscn").instantiate()
	_own(f)
	f.setup(Color.RED, pos)
	return f

func _run(f: FightFlow, frames: int) -> void:
	for i in frames:
		f.tick()
		if f.phase == FightFlow.Phase.OVER:
			return

func test_intro_then_fighting():
	var f := _setup_fight({"round_seconds": 5, "seed": 1})
	assert_eq(f.phase, FightFlow.Phase.INTRO)
	_run(f, FightFlow.INTRO_FRAMES)
	assert_eq(f.phase, FightFlow.Phase.FIGHTING)

func test_round_ends_at_zero_and_goes_to_break():
	var f := _setup_fight({"rounds": 3, "round_seconds": 2, "rest_seconds": 1, "seed": 1})
	_run(f, FightFlow.INTRO_FRAMES + 2 * 60)
	assert_eq(f.phase, FightFlow.Phase.ROUND_BREAK)
	assert_eq(f.judges.cards[0].size(), 1)
	_run(f, 60)
	assert_eq(f.phase, FightFlow.Phase.INTRO)
	assert_eq(f.round, 2)

func test_skip_break():
	var f := _setup_fight({"rounds": 2, "round_seconds": 1, "rest_seconds": 60, "seed": 1})
	_run(f, FightFlow.INTRO_FRAMES + 60)
	f.skip_break()
	assert_eq(f.round, 2)

func test_no_action_scores_draw_decision():
	var f := _setup_fight({"rounds": 3, "round_seconds": 1, "rest_seconds": 0.1, "seed": 1})
	_run(f, 2000)
	assert_eq(f.phase, FightFlow.Phase.OVER)
	assert_eq(f.result.method, "DRAW")
	assert_eq(f.judges.cards[0], [[10, 10], [10, 10], [10, 10]])

func test_one_sided_fight_wins_decision():
	var f := _setup_fight({"rounds": 3, "round_seconds": 3, "rest_seconds": 0.1, "seed": 3})
	ba.spam = &"jab"
	ba.every = 25
	_run(f, 20000)
	assert_eq(f.phase, FightFlow.Phase.OVER)
	assert_eq(f.result.winner, a)
	assert_true(f.result.method in ["UD", "KO", "TKO", "TKO (doctor)"])

func test_round_stats_recorded():
	var f := _setup_fight({"round_seconds": 3, "seed": 1})
	ba.spam = &"jab"
	_run(f, FightFlow.INTRO_FRAMES + 100)
	var s: Judges.RoundStats = f.stats[0][0]
	assert_gt(s.thrown, 0)
	assert_gt(s.landed, 0)

func test_knockdown_count_and_rise():
	var f := _setup_fight({"round_seconds": 60, "seed": 1})
	_run(f, FightFlow.INTRO_FRAMES)
	b.body.hp[MoveData.Zone.HEAD] = 0.5  # next head shot forces a knockdown
	ba.spam = &"cross"
	ba.every = 1
	_run(f, 15)
	assert_eq(f.phase, FightFlow.Phase.KNOCKDOWN)
	assert_eq(b.state, Fighter.State.KNOCKDOWN)
	ba.spam = &""
	# head hp 0 after the cross -> can't beat the count -> KO
	_run(f, (FightFlow.COUNT_OUT + 1) * 60)
	assert_eq(f.phase, FightFlow.Phase.OVER)
	assert_eq(f.result.method, "KO")
	assert_eq(f.result.winner, a)

func test_beats_count_when_healthy_enough():
	var f := _setup_fight({"round_seconds": 60, "seed": 1})
	_run(f, FightFlow.INTRO_FRAMES)
	f.rng.seed = 5
	b.body.hp[MoveData.Zone.HEAD] = 70.0
	b.receive({"outcome": CombatResolver.Outcome.HIT, "damage": 0.0, "stun": 0, "knockdown": true, "cut_delta": 0.0}, MoveLibrary.all()[&"jab"])
	b.body.knockdowns_round = 1
	f._pending_kd = b
	_run(f, 1)
	assert_eq(f.phase, FightFlow.Phase.KNOCKDOWN)
	assert_lt(f.rise_at, FightFlow.COUNT_OUT)
	_run(f, FightFlow.MIN_COUNT * 60 + 61)
	assert_eq(f.phase, FightFlow.Phase.FIGHTING)
	assert_false(b.is_down())

func test_three_knockdowns_is_tko():
	var f := _setup_fight({"round_seconds": 60, "seed": 1})
	_run(f, FightFlow.INTRO_FRAMES)
	b.body.knockdowns_round = 3
	f._pending_kd = b
	_run(f, 1)
	assert_eq(f.result.method, "TKO")

func test_count_to_rise_rules():
	var r := RandomNumberGenerator.new()
	r.seed = 1
	assert_true(FightFlow.count_to_rise(0.0, 1, r) >= FightFlow.COUNT_OUT, "empty zone = KO")
	assert_lt(FightFlow.count_to_rise(0.9, 1, r), 6)
	assert_gt(FightFlow.count_to_rise(0.2, 2, r), FightFlow.count_to_rise(0.9, 1, r))

func test_doctor_stoppage_chance_scales_with_cut():
	assert_eq(FightFlow.doctor_stoppage_chance(1.0), 0.0)
	assert_eq(FightFlow.doctor_stoppage_chance(4.5), 1.0)

func test_doctor_check_flow():
	var f := _setup_fight({"round_seconds": 60, "seed": 1})
	_run(f, FightFlow.INTRO_FRAMES)
	b.body.cut = 5.0  # certain stoppage
	f._pending_doctor = b
	_run(f, 1 + FightFlow.DOCTOR_FRAMES)
	assert_eq(f.result.method, "TKO (doctor)")
	assert_eq(f.result.winner, a)

func test_same_seed_same_fight():
	var results := []
	for i in 2:
		var f := _setup_fight({"rounds": 2, "round_seconds": 5, "rest_seconds": 0.1, "seed": 42})
		ba.spam = &"rear_hook"
		ba.every = 23
		bb.spam = &"round_kick_body"
		bb.every = 37
		_run(f, 5000)
		results.append([f.result.method, f.result.winner_index, f.judges.totals(), a.body.hp, b.body.hp])
	assert_eq(results[0], results[1])

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
