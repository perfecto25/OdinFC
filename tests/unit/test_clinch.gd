extends GutTest
## Clinch: entry, position contest, knees, sweeps, escapes, referee breaks.

class Bot extends Node:
	var queue: Array[StringName] = []
	var move := Vector2.ZERO
	var guard := false
	func get_move() -> Vector2: return move
	func is_guard_held() -> bool: return guard
	func poll_attack() -> StringName:
		return queue.pop_front() if not queue.is_empty() else &""

var a: Fighter
var b: Fighter
var ba: Bot
var bb: Bot
var rng := RandomNumberGenerator.new()

func before_each():
	rng.seed = 7
	a = _fighter(Vector3(-0.5, 0, 0))
	b = _fighter(Vector3(0.5, 0, 0))
	a.opponent = b
	b.opponent = a
	ba = Bot.new()
	bb = Bot.new()
	_own(ba)
	_own(bb)
	a.controller = ba
	b.controller = bb

func _fighter(pos: Vector3) -> Fighter:
	var f: Fighter = load("res://scenes/fighter.tscn").instantiate()
	_own(f)
	f.set_physics_process(false)
	f.setup(Color.RED, pos)
	f.global_position = pos
	return f

## Flow with fighters already in range and the intro skipped.
func _flow(cfg := {"round_seconds": 60, "seed": 3}) -> FightFlow:
	var f := FightFlow.new(a, b, cfg)
	f.start_positions = [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0)]
	for i in 2:
		f.fighters[i].reset_for_round(f.start_positions[i])
	for i in FightFlow.INTRO_FRAMES:
		f.tick()
	return f

func _tick(f: FightFlow, n: int) -> void:
	for i in n:
		f.tick()

## A clinch built directly (no flow); the caller ticks fighters + clinch.
func _clinch(adv: float) -> Clinch:
	var c := Clinch.new(a, b, rng)
	c.advantage = adv
	return c

func _step(c: Clinch, n: int) -> void:
	for i in n:
		a.tick()
		b.tick()
		c.tick()

# --- entry ---

func test_clinch_entry_in_range():
	var f := _flow()
	ba.queue = [&"clinch"]
	_tick(f, 12)
	assert_true(f.in_clinch())
	assert_eq(a.state, Fighter.State.CLINCH)
	assert_eq(b.state, Fighter.State.CLINCH)
	assert_almost_eq(a.global_position.distance_to(b.global_position), Clinch.SNAP_DISTANCE, 0.01)

func test_clinch_entry_whiffs_out_of_range():
	var f := _flow()
	b.global_position = Vector3(2.5, 0, 0)
	ba.queue = [&"clinch"]
	_tick(f, 30)
	assert_false(f.in_clinch())

func test_clinch_beats_guard():
	var f := _flow()
	bb.guard = true
	_tick(f, 20)
	ba.queue = [&"clinch"]
	_tick(f, 12)
	assert_true(f.in_clinch())

func test_strike_interrupts_clinch_entry():
	var f := _flow()
	ba.queue = [&"clinch"]
	bb.queue = [&"jab"]  # jab (startup 5) lands during the clinch entry's startup (6)
	_tick(f, 12)
	assert_false(f.in_clinch())
	assert_lt(a.body.hp[MoveData.Zone.HEAD], BodyDamage.MAX_HP)

# --- position contest ---

func test_stronger_fighter_wins_position():
	var c := _clinch(0.0)
	a.strength = 2.0
	for i in 12:
		c._resolve_pummel(0)
		c._resolve_pummel(1)
	assert_eq(c.position_of(0), Clinch.Pos.DOMINANT)
	assert_eq(c.position_of(1), Clinch.Pos.CONTROLLED)

func test_tired_fighter_loses_position():
	var c := _clinch(0.0)
	b.stam.value = 0.0
	for i in 12:
		c._resolve_pummel(0)
		c._resolve_pummel(1)
	assert_gt(c.advantage, Clinch.DOMINANT_AT)

func test_pummel_via_input():
	var c := _clinch(0.0)
	a.strength = 3.0
	for k in 4:
		ba.queue = [&"clinch"]
		_step(c, Clinch.PUMMEL_FRAMES + 2)
	assert_gt(c.advantage, 0.0)

func test_controlled_cannot_knee():
	var c := _clinch(-0.8)
	ba.queue = [&"knee"]
	_step(c, 2)
	assert_eq(c.current_action(0), &"")

func test_dominant_body_knee_lands():
	var c := _clinch(0.8)
	ba.queue = [&"knee"]
	_step(c, 15)
	assert_lt(b.body.hp[MoveData.Zone.BODY], BodyDamage.MAX_HP)
	assert_eq(b.body.hp[MoveData.Zone.HEAD], BodyDamage.MAX_HP)
	assert_eq(b.state, Fighter.State.CLINCH, "a knee doesn't knock you out of the clinch")

func test_dominant_knee_with_up_goes_to_head():
	var c := _clinch(0.8)
	ba.move = Vector2(1, 0)  # forward: a is at -x, facing b
	ba.queue = [&"knee"]
	_step(c, 15)
	assert_lt(b.body.hp[MoveData.Zone.HEAD], BodyDamage.MAX_HP)

func test_framing_blocks_knee():
	var c := _clinch(0.8)
	bb.guard = true
	ba.queue = [&"knee"]
	_step(c, 15)
	assert_gt(b.body.hp[MoveData.Zone.BODY], BodyDamage.MAX_HP - 0.5)

func _framed(knee: StringName, fatigue: float) -> Dictionary:
	var m: MoveData = MoveLibrary.all()[knee]
	var d := CombatResolver.Snapshot.new()
	d.guarding = true
	d.framing = true
	d.guard_frames = 999
	d.fatigue = fatigue
	var r := CombatResolver.resolve(m, CombatResolver.Snapshot.new(), d, rng)
	r["clean"] = m.damage * CombatResolver.DAMAGE_SCALE
	return r

func test_framed_knee_hurts_upper_body_10_to_20_percent():
	for knee in [&"clinch_knee", &"clinch_knee_body", &"clinch_knee_head"]:
		for fatigue in [0.0, 1.0]:
			var r := _framed(knee, fatigue)
			assert_eq(r.outcome, CombatResolver.Outcome.BLOCK)
			assert_eq(r.zone, MoveData.Zone.BODY, "%s lands on the arms/upper body" % knee)
			assert_between(r.damage / r.clean, 0.1, 0.2 + 1e-6, "%s fatigue %s" % [knee, fatigue])

func test_framed_head_knee_damages_body_not_head():
	var c := _clinch(0.8)
	bb.guard = true
	ba.move = Vector2(1, 0)  # forward: a is at -x, facing b
	ba.queue = [&"knee"]
	_step(c, 15)
	assert_eq(b.body.hp[MoveData.Zone.HEAD], BodyDamage.MAX_HP)
	assert_lt(b.body.hp[MoveData.Zone.BODY], BodyDamage.MAX_HP)

func test_framed_knee_hurts_less_than_clean():
	var c := _clinch(0.8)
	ba.queue = [&"knee"]
	_step(c, 15)
	var clean: float = BodyDamage.MAX_HP - b.body.hp[MoveData.Zone.BODY]
	assert_gt(clean, 0.0)
	after_each()
	before_each()
	c = _clinch(0.8)
	bb.guard = true
	ba.queue = [&"knee"]
	_step(c, 15)
	var framed: float = BodyDamage.MAX_HP - b.body.hp[MoveData.Zone.BODY]
	assert_gt(framed, 0.0)
	assert_lt(framed, clean * 0.25)

func test_stamina_drains_faster_when_controlled():
	var c := _clinch(0.8)
	_step(c, 60)
	assert_lt(b.stam.value, a.stam.value)

# --- sweeps ---

func test_sweep_from_dominant_on_tired_opponent():
	var c := _clinch(1.0)
	b.stam.value = 0.0
	var swept := false
	for k in 3:
		if not c.active:
			break
		ba.queue = [&"round_kick_body"]
		_step(c, Clinch.SWEEP_FRAMES + 2)
	assert_false(c.active)
	assert_eq(b.state, Fighter.State.SWEPT)
	assert_true(b.is_down())

func test_failed_sweeps_cost_position():
	# weak, tired attacker sweeping from neutral: mostly fails and hands over position
	var fails := 0
	for k in 100:
		a.reset_for_round(Vector3(-0.5, 0, 0))
		b.reset_for_round(Vector3(0.5, 0, 0))
		a.stam.value = 0.0
		var c := _clinch(0.2)
		c._resolve_sweep(0)
		if c.active:
			fails += 1
			assert_almost_eq(c.advantage, 0.2 - Clinch.SWEEP_FAIL_SHIFT, 0.001)
			c.end(&"halt")
	assert_gt(fails, 85)

func test_controlled_cannot_sweep():
	var c := _clinch(-0.8)
	ba.queue = [&"round_kick_body"]
	_step(c, 2)
	assert_eq(c.current_action(0), &"")

func test_off_balance_opponent_is_easier_to_sweep():
	var plain := 0
	var off := 0
	for k in 300:
		var c := _clinch(0.0)  # neutral: low base chance
		c._resolve_sweep(0)
		if not c.active:
			plain += 1
		_reset()
		c = _clinch(0.0)
		c._act[1] = {"id": &"knee", "frame": 1, "len": 20, "move": null}
		c._resolve_sweep(0)
		if not c.active:
			off += 1
		_reset()
	assert_gt(off, plain * 1.5)  # expected ~14% vs ~28%

func _reset() -> void:
	for f in [a, b]:
		f.reset_for_round(f.global_position)
		f.stam.value = Stamina.MAX

# --- escape ---

func test_escape_harder_when_controlled():
	var neutral := 0
	var controlled := 0
	for k in 300:
		var c := _clinch(0.0)
		c._resolve_escape(0)
		if not c.active:
			neutral += 1
		_reset()
		c = _clinch(-0.8)
		c._resolve_escape(0)
		if not c.active:
			controlled += 1
		_reset()
	assert_gt(neutral, controlled * 1.5)

func test_escape_separates_fighters():
	var c := _clinch(0.8)  # dominant: escape always works
	ba.queue = [&"teep"]
	_step(c, Clinch.ESCAPE_FRAMES + 2)
	assert_false(c.active)
	assert_eq(a.state, Fighter.State.IDLE)
	assert_almost_eq(a.global_position.distance_to(b.global_position), Clinch.BREAK_DISTANCE, 0.01)

# --- referee + flow ---

func test_referee_breaks_stalled_clinch():
	var f := _flow()
	ba.queue = [&"clinch"]
	_tick(f, 12)
	assert_true(f.in_clinch())
	_tick(f, Clinch.BREAK_FRAMES + 2)
	assert_false(f.in_clinch())
	assert_eq(f.event_text, "BREAK!")
	assert_eq(a.state, Fighter.State.IDLE)
	assert_eq(b.state, Fighter.State.IDLE)

func test_knee_knockdown_ends_clinch_and_starts_count():
	var f := _flow()
	ba.queue = [&"clinch"]
	_tick(f, 12)
	f.clinch.advantage = 0.9 if f.clinch.fighters[0] == a else -0.9
	b.body.hp[MoveData.Zone.HEAD] = 0.5
	ba.move = Vector2(1, 0)  # forward: a is at -x, facing b
	ba.queue = [&"knee"]
	_tick(f, 15)
	assert_false(f.in_clinch())
	assert_eq(f.phase, FightFlow.Phase.KNOCKDOWN)

func test_round_end_ends_clinch():
	var f := _flow({"round_seconds": 1, "rest_seconds": 5, "seed": 3})
	ba.queue = [&"clinch"]
	_tick(f, 12)
	assert_true(f.in_clinch())
	_tick(f, 60)
	assert_eq(f.phase, FightFlow.Phase.ROUND_BREAK)
	assert_false(f.in_clinch())
	assert_ne(a.state, Fighter.State.CLINCH)

func test_sweep_scores_and_control_counts():
	var f := _flow()
	ba.queue = [&"clinch"]
	_tick(f, 12)
	f.clinch.advantage = 1.0 if f.clinch.fighters[0] == a else -1.0
	_tick(f, 30)
	b.stam.value = 0.0
	for k in 4:
		if not f.in_clinch():
			break
		ba.queue = [&"round_kick_body"]
		_tick(f, Clinch.SWEEP_FRAMES + 2)
	var s: Judges.RoundStats = f.stats[0][0]
	assert_eq(s.sweeps, 1)
	assert_gt(s.control_frames, 25)
	assert_gt(s.total_points(), Judges.SWEEP_POINTS)

func test_check_recorded_for_checker():
	var f := _flow()
	ba.queue = [&"check"]
	bb.queue = [&"round_kick_low"]
	_tick(f, 16)
	assert_eq(f.stats[0][0].checks, 1)
	assert_eq(f.event_text, "CHECKED!")

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

# --- getting out (walk away, time cap) ---

func test_walking_away_escapes_from_neutral():
	var c := _clinch(0.0)
	bb.move = Vector2(1, 0)  # b is at +x: walking further +x is away from a
	var frames := 0
	while c.active and frames < 300:
		_step(c, 1)
		frames += 1
	assert_false(c.active, "holding away should push off within a few attempts")
	assert_eq(b.state, Fighter.State.IDLE)

func test_walking_away_needs_a_short_hold():
	var c := _clinch(0.0)
	bb.move = Vector2(1, 0)
	_step(c, Clinch.WALK_ESCAPE_HOLD - 2)
	assert_eq(c.current_action(1), &"", "a brief tap of a direction isn't an escape attempt")

func test_walking_toward_does_not_escape():
	var c := _clinch(0.0)
	bb.move = Vector2(-1, 0)  # toward a
	_step(c, 120)
	assert_true(c.active)

func test_dominant_fighter_walking_away_does_not_escape():
	var c := _clinch(-0.8)  # b (fighters[1]) dominant
	bb.move = Vector2(1, 0)
	_step(c, 60)
	assert_true(c.active, "the dominant side holds W for head knees; movement never lets go of the clinch")

func test_failed_escape_is_signalled():
	var c := _clinch(0.9)  # b controlled: 25% escape
	var fails := [0]
	c.escape_failed.connect(func(_f): fails[0] += 1)
	bb.move = Vector2(1, 0)
	_step(c, 200)
	assert_gt(fails[0], 0)

func test_referee_breaks_long_clinch_even_with_knees():
	var f := _flow()
	ba.queue = [&"clinch"]
	_tick(f, 12)
	assert_true(f.in_clinch())
	var c := f.clinch
	for i in Clinch.MAX_FRAMES:
		if not c.active:
			break
		c.idle_frames = 0  # as if knees keep landing
		b.body.hp = {MoveData.Zone.HEAD: 100.0, MoveData.Zone.BODY: 100.0, MoveData.Zone.LEGS: 100.0}
		f.tick()
	assert_false(c.active)
	assert_eq(f.event_text, "BREAK!")
