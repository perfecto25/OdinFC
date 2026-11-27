extends GutTest
## Roster loading, FighterData scaling and its effect on a fighter / the AI profile.

func _fighter() -> Fighter:
	var f: Fighter = load("res://scenes/fighter.tscn").instantiate()
	add_child_autofree(f)
	f.set_physics_process(false)
	f.setup(Color.RED, Vector3.ZERO)
	return f

func test_roster_loads_and_sorts_by_ranking():
	var r := Roster.all()
	assert_gte(r.size(), 2)
	assert_not_null(Roster.get_fighter(&"buakaw"))
	assert_not_null(Roster.get_fighter(&"haggerty"))
	for i in r.size() - 1:
		if r[i].ranking > 0 and r[i + 1].ranking > 0:
			assert_lte(r[i].ranking, r[i + 1].ranking)

func test_every_entry_is_valid():
	var moves := MoveLibrary.all()
	for d in Roster.all():
		assert_ne(d.id, &"", "id")
		assert_ne(d.display_name, "", "name of %s" % d.id)
		assert_between(d.height_cm, 150.0, 210.0, "height of %s" % d.id)
		assert_between(d.weight_kg, 45.0, 120.0, "weight of %s" % d.id)
		assert_between(d.difficulty, 1, 5)
		for mid in d.signatures:
			assert_true(moves.has(mid), "%s: signature %s is not a move" % [d.id, mid])

func test_neutral_data_changes_nothing():
	var d := FighterData.new()
	var built := d.build_moves(MoveLibrary.all())
	for mid in MoveLibrary.all():
		var a: MoveData = MoveLibrary.all()[mid]
		var b: MoveData = built[mid]
		assert_eq(b.startup, a.startup)
		assert_eq(b.recovery, a.recovery)
		assert_almost_eq(b.damage, a.damage, 0.0001)
		assert_almost_eq(b.reach, a.reach, 0.0001)
		assert_almost_eq(b.stamina_cost, a.stamina_cost, 0.0001)
	assert_almost_eq(d.clinch_strength(), 1.0, 0.0001)
	assert_almost_eq(d.chin_factor(), 1.0, 0.0001)

func test_build_moves_does_not_touch_the_library():
	var jab: MoveData = MoveLibrary.all()[&"jab"]
	var before := jab.damage
	var d := FighterData.new()
	d.power = 100
	d.build_moves(MoveLibrary.all())
	assert_eq(jab.damage, before)

func test_attributes_scale_moves():
	var d := FighterData.new()
	d.power = 100
	d.speed = 100
	d.height_cm = 190.0
	d.signatures = {&"round_kick_body": {"damage": 1.2}}
	var built := d.build_moves(MoveLibrary.all())
	var base: MoveData = MoveLibrary.all()[&"round_kick_body"]
	var m: MoveData = built[&"round_kick_body"]
	assert_almost_eq(m.damage, base.damage * 1.15 * 1.2, 0.001)
	assert_lt(m.startup, base.startup + 1)
	assert_gt(m.reach, base.reach)

func test_apply_data_sets_fighter_traits():
	var f := _fighter()
	var bk := Roster.get_fighter(&"buakaw")
	f.apply_data(bk)
	assert_eq(f.display_name, bk.display_name)
	assert_eq(f.data, bk)
	assert_gt(f.strength, 1.0, "Buakaw's clinch is above average")
	assert_lt(f.chin, 1.0, "Buakaw's chin is above average")
	assert_gt(f.stam.regen_mult, 1.0)
	assert_gt(f.moves[&"round_kick_body"].damage, MoveLibrary.all()[&"round_kick_body"].damage)
	f.apply_data(null)
	assert_eq(f.moves, MoveLibrary.all())
	assert_eq(f.strength, 1.0)

func test_chin_scales_knockdown_chance():
	var m: MoveData = MoveLibrary.all()[&"round_kick_high"]
	var att := CombatResolver.Snapshot.new()
	var kd := [0, 0]
	for k in 2:
		var def := CombatResolver.Snapshot.new()
		def.zone_hp = {MoveData.Zone.HEAD: 40.0, MoveData.Zone.BODY: 100.0, MoveData.Zone.LEGS: 100.0}
		def.chin = [1.0, 0.65][k]
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 2000:
			if CombatResolver.resolve(m, att, def, rng).knockdown:
				kd[k] += 1
	assert_lt(kd[1], kd[0], "a better chin goes down less")

func test_rating_profiles():
	var easy := AIController.Profile.for_difficulty(AIController.Difficulty.EASY)
	var hard := AIController.Profile.for_difficulty(AIController.Difficulty.HARD)
	assert_eq(AIController.Profile.for_rating(1).defense, easy.defense)
	assert_eq(AIController.Profile.for_rating(5).defense, hard.defense)
	var four := AIController.Profile.for_rating(4)
	assert_between(four.defense, 0.6, hard.defense)
	assert_typeof(four.reaction, TYPE_INT)

func test_apply_style():
	var hg := Roster.get_fighter(&"haggerty")
	var p := AIController.Profile.for_rating(hg.difficulty).apply_style(hg)
	assert_eq(p.punch_bias, hg.punch_bias)
	assert_gt(float(p.move_bias.get(&"knee", 1.0)), 1.0)
