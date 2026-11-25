extends GutTest

var rng := RandomNumberGenerator.new()

func before_each():
	rng.seed = 1

func _move(id: StringName) -> MoveData:
	return MoveLibrary.all()[id]

func _snap(guarding := false, guard_frames := 0, mid_attack := false) -> CombatResolver.Snapshot:
	var s := CombatResolver.Snapshot.new()
	s.guarding = guarding
	s.guard_frames = guard_frames
	s.mid_attack = mid_attack
	return s

func test_all_moves_load():
	for id in [&"jab", &"cross", &"lead_hook", &"rear_hook", &"uppercut", &"teep", &"side_kick",
			&"round_kick_low", &"round_kick_body", &"round_kick_high", &"knee"]:
		assert_true(MoveLibrary.all().has(id), "missing move %s" % id)

func test_clean_hit():
	var r := CombatResolver.resolve(_move(&"cross"), _snap(), _snap(), rng)
	assert_eq(r.outcome, CombatResolver.Outcome.HIT)
	assert_almost_eq(r.damage, 6.0 * CombatResolver.DAMAGE_SCALE, 0.001)
	assert_false(r.counter)
	assert_false(r.knockdown, "a cross on a fresh fighter should not drop him")

func test_counter_hit_bonus():
	var r := CombatResolver.resolve(_move(&"cross"), _snap(), _snap(false, 0, true), rng)
	assert_true(r.counter)
	assert_almost_eq(r.damage, 6.0 * (1.0 + _move(&"cross").counter_bonus) * CombatResolver.DAMAGE_SCALE, 0.001)

func test_low_stamina_weakens_strike():
	var tired := _snap()
	tired.stamina_ratio = 0.0
	var full := CombatResolver.resolve(_move(&"cross"), _snap(), _snap(), rng)
	var weak := CombatResolver.resolve(_move(&"cross"), tired, _snap(), rng)
	assert_lt(weak.damage, full.damage)

func test_damaged_legs_weaken_kicks_not_punches():
	var hurt := _snap()
	hurt.leg_ratio = 0.0
	assert_lt(CombatResolver.strength(_move(&"round_kick_body"), hurt), 1.0)
	assert_eq(CombatResolver.strength(_move(&"cross"), hurt), 1.0)

func test_block_reduces_damage_and_drains_stamina():
	var r := CombatResolver.resolve(_move(&"cross"), _snap(), _snap(true, 20), rng)
	assert_eq(r.outcome, CombatResolver.Outcome.BLOCK)
	assert_lt(r.damage, 1.0)
	assert_gt(r.stamina_loss, 0.0)

func test_tired_guard_leaks_more():
	var tired := _snap(true, 20)
	tired.fatigue = 1.0
	var fresh := CombatResolver.resolve(_move(&"cross"), _snap(), _snap(true, 20), rng)
	var leaky := CombatResolver.resolve(_move(&"cross"), _snap(), tired, rng)
	assert_gt(leaky.damage, fresh.damage)
	assert_gt(leaky.stamina_loss, fresh.stamina_loss)

func test_parry_inside_window_staggers_attacker():
	var r := CombatResolver.resolve(_move(&"jab"), _snap(), _snap(true, 3), rng)
	assert_eq(r.outcome, CombatResolver.Outcome.PARRY)
	assert_eq(r.damage, 0.0)
	assert_gt(r.attacker_stagger, 0)

func test_kicks_cannot_be_parried():
	var r := CombatResolver.resolve(_move(&"round_kick_high"), _snap(), _snap(true, 3), rng)
	assert_eq(r.outcome, CombatResolver.Outcome.BLOCK)

func test_leg_kick_ignores_guard():
	var r := CombatResolver.resolve(_move(&"round_kick_low"), _snap(), _snap(true, 30), rng)
	assert_eq(r.outcome, CombatResolver.Outcome.HIT)

func test_zone_depleted_forces_knockdown():
	var d := _snap()
	d.zone_hp[MoveData.Zone.HEAD] = 0.5
	var r := CombatResolver.resolve(_move(&"cross"), _snap(), d, rng)
	assert_true(r.knockdown)

func test_hurt_head_knocks_down_more_often():
	var fresh_kd := 0
	var hurt_kd := 0
	for i in 500:
		var hurt := _snap()
		hurt.zone_hp[MoveData.Zone.HEAD] = 35.0
		if CombatResolver.resolve(_move(&"round_kick_high"), _snap(), _snap(), rng).knockdown:
			fresh_kd += 1
		if CombatResolver.resolve(_move(&"round_kick_high"), _snap(), hurt, rng).knockdown:
			hurt_kd += 1
	assert_lt(fresh_kd, 25)  # ~2% on a fresh fighter: rare but possible
	assert_gt(hurt_kd, 80)  # ~27% at 35% head

func test_heavy_head_shots_can_open_cuts_and_cuts_grow():
	var opened := 0
	for i in 500:
		if CombatResolver.resolve(_move(&"round_kick_high"), _snap(), _snap(), rng).cut_delta > 0.0:
			opened += 1
	assert_between(opened, 1, 30)  # ~1% per heavy head shot
	var cut := _snap()
	cut.cut = 1.0
	assert_gt(CombatResolver.resolve(_move(&"jab"), _snap(), cut, rng).cut_delta, 0.0)
	assert_eq(CombatResolver.resolve(_move(&"jab"), _snap(), _snap(), rng).cut_delta, 0.0, "light shots don't open cuts")

func test_deterministic_with_same_seed():
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	r1.seed = 99
	r2.seed = 99
	var hurt := _snap()
	hurt.zone_hp[MoveData.Zone.HEAD] = 40.0
	for i in 50:
		var a := CombatResolver.resolve(_move(&"rear_hook"), _snap(), hurt, r1)
		var b := CombatResolver.resolve(_move(&"rear_hook"), _snap(), hurt, r2)
		assert_eq(a.knockdown, b.knockdown)
