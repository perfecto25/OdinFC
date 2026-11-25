extends GutTest

func test_even_round_is_10_10():
	assert_eq(Judges.ten_point(50.0, 51.0, 0, 0), [10, 10])

func test_clear_winner_is_10_9():
	assert_eq(Judges.ten_point(60.0, 40.0, 0, 0), [10, 9])
	assert_eq(Judges.ten_point(40.0, 60.0, 0, 0), [9, 10])

func test_knockdown_makes_it_10_8():
	assert_eq(Judges.ten_point(80.0, 40.0, 1, 0), [10, 8])

func test_dominant_round_without_knockdown_is_10_8():
	assert_eq(Judges.ten_point(120.0, 30.0, 0, 0), [10, 8])

func test_loser_score_floor_is_7():
	assert_eq(Judges.ten_point(200.0, 10.0, 4, 0), [10, 7])

func test_kicks_outscore_punches_for_same_damage():
	var kick := Judges.RoundStats.new()
	var punch := Judges.RoundStats.new()
	var hit := {"outcome": CombatResolver.Outcome.HIT, "damage": 8.0}
	kick.record(MoveLibrary.all()[&"round_kick_body"], hit)
	punch.record(MoveLibrary.all()[&"cross"], hit)
	assert_gt(kick.total_points(), punch.total_points())

func test_damage_beats_volume():
	# Muay Thai weighting: three hard kicks should beat many light jabs.
	var kicker := Judges.RoundStats.new()
	var jabber := Judges.RoundStats.new()
	for i in 3:
		kicker.record(MoveLibrary.all()[&"round_kick_high"], {"outcome": CombatResolver.Outcome.HIT, "damage": 12.0})
	for i in 10:
		jabber.record(MoveLibrary.all()[&"jab"], {"outcome": CombatResolver.Outcome.HIT, "damage": 3.0})
	assert_gt(kicker.total_points(), jabber.total_points())

func _judges_with_cards(cards: Array) -> Judges:
	var j := Judges.new(0)
	j.cards = cards
	return j

func test_unanimous_decision():
	var d := _judges_with_cards([[[10, 9]], [[10, 9]], [[10, 9]]]).decision()
	assert_eq(d, {"method": "UD", "winner": 0})

func test_split_decision():
	var d := _judges_with_cards([[[9, 10]], [[10, 9]], [[9, 10]]]).decision()
	assert_eq(d, {"method": "SD", "winner": 1})

func test_majority_decision():
	var d := _judges_with_cards([[[10, 9]], [[10, 10]], [[10, 9]]]).decision()
	assert_eq(d, {"method": "MD", "winner": 0})

func test_draw():
	var d := _judges_with_cards([[[10, 9]], [[10, 10]], [[9, 10]]]).decision()
	assert_eq(d, {"method": "DRAW", "winner": -1})

func test_judges_vary_on_close_rounds():
	# With variance, a near-even round should not always be scored identically by all three judges.
	var differed := false
	for seed in 30:
		var j := Judges.new(seed)
		var a := Judges.RoundStats.new()
		var b := Judges.RoundStats.new()
		a.points = 50.0
		b.points = 46.0
		var r := j.score_round(a, b)
		if r[0] != r[1] or r[1] != r[2]:
			differed = true
	assert_true(differed)
