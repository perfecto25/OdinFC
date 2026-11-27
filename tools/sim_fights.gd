extends SceneTree
## Balance harness: runs N full-length fights and prints outcome stats.
##   godot --headless --path . -s tools/sim_fights.gd -- --fights=40 [--a=hard --b=easy]
## Controllers: random (default), easy, medium, hard, rating (the roster fighter's own difficulty).
## --fa / --fb: roster ids for A's and B's fighter (default: neutral generic fighters), e.g. --fa=buakaw --fb=haggerty.
## AI controllers take the fighter's style (biases, signatures) whenever a roster fighter is given. --arena=cage fights inside the circular cage. Sides alternate each fight so the clinch initiator /
## fighters[0] tick order can't bias a matchup; "A" always means the --a controller.

class RandomBot extends Node:
	var rng := RandomNumberGenerator.new()
	var aggression := 0.5   ## chance per decision to attack
	var guard_rate := 0.3
	var _guard_left := 0
	var _cooldown := 0
	const MOVES := [&"jab", &"cross", &"lead_hook", &"rear_hook", &"uppercut", &"teep", &"side_kick",
			&"round_kick_low", &"round_kick_body", &"round_kick_high", &"knee", &"clinch", &"check"]
	var me: Fighter
	var _range := 1.2
	var _range_timer := 0
	## Footwork: pick a preferred distance every ~2 s and drift toward it.
	func get_move() -> Vector2:
		if me == null or me.opponent == null:
			return Vector2.ZERO
		_range_timer -= 1
		if _range_timer <= 0:
			_range = rng.randf_range(0.8, 1.8)
			_range_timer = rng.randi_range(60, 180)
		var d := me.opponent.global_position - me.global_position
		var dist := Vector2(d.x, d.z).length()
		var dir := Vector2(d.x, d.z).normalized()
		if dist > _range + 0.1:
			return dir
		if dist < _range - 0.1:
			return -dir
		return Vector2.ZERO
	func is_guard_held() -> bool:
		if _guard_left > 0:
			_guard_left -= 1
			return true
		return false
	func poll_attack() -> StringName:
		_cooldown -= 1
		if _cooldown > 0:
			return &""
		_cooldown = rng.randi_range(20, 60)
		var roll := rng.randf()
		if roll < aggression:
			return MOVES[rng.randi() % MOVES.size()]
		if roll < aggression + guard_rate:
			_guard_left = rng.randi_range(10, 40)
		return &""

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run_all()
	return true

var _cage := false

func _run_all() -> void:
	var n := 40
	var kinds := ["random", "random"]
	var datas: Array = [null, null]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fights="):
			n = arg.split("=")[1].to_int()
		elif arg.begins_with("--a="):
			kinds[0] = arg.split("=")[1]
		elif arg.begins_with("--b="):
			kinds[1] = arg.split("=")[1]
		elif arg.begins_with("--fa="):
			datas[0] = Roster.get_fighter(StringName(arg.split("=")[1]))
		elif arg.begins_with("--fb="):
			datas[1] = Roster.get_fighter(StringName(arg.split("=")[1]))
		elif arg.begins_with("--arena="):
			_cage = arg.split("=")[1] == "cage"
	var wins := [0, 0, 0]  # A, B, draw
	var per_move := {}     # id -> [thrown, hit, block, parry, checked]
	var show_moves := "--moves" in OS.get_cmdline_user_args()
	var sources := {}
	var a_methods := {}
	var methods := {}
	var rounds_sum := 0
	var kd_sum := 0
	var cut_fights := 0
	var landed_sum := 0
	var time_sum := 0
	var counters := [0]
	var zone_dmg := [0.0, 0.0, 0.0]
	var clinches := [0]
	var breaks := [0]
	var sweeps := 0
	var checks := 0
	var control := 0
	var t0 := Time.get_ticks_msec()
	for i in n:
		var a := _fighter()
		var b := _fighter()
		a.opponent = b
		b.opponent = a
		var swap := i % 2 == 1  # A drives fighter b on odd fights
		a.apply_data(datas[1] if swap else datas[0])
		b.apply_data(datas[0] if swap else datas[1])
		var ba := _controller(kinds[1] if swap else kinds[0], i * 2 + 1, a.data)
		var bb := _controller(kinds[0] if swap else kinds[1], i * 2 + 2, b.data)
		if bb is RandomBot and ba is RandomBot:
			bb.aggression = 0.4
		root.add_child(ba)
		root.add_child(bb)
		a.controller = ba
		b.controller = bb
		ba.me = a
		bb.me = b
		var f := FightFlow.new(a, b, {"rounds": 3, "round_seconds": 180, "rest_seconds": 0.05, "seed": i})
		f.start_positions = [Vector3(-1.0, 0, 0), Vector3(1.0, 0, 0)]
		for k in 2:
			f.fighters[k].reset_for_round(f.start_positions[k])
		a.move_resolved.connect(func(_x, _y, _m, r): if r.counter: counters[0] += 1)
		b.move_resolved.connect(func(_x, _y, _m, r): if r.counter: counters[0] += 1)
		for fx in [a, b]:
			fx.attack_started.connect(func(_x, m):
				if not per_move.has(m.id): per_move[m.id] = [0, 0, 0, 0, 0, 0]
				per_move[m.id][0] += 1)
			fx.move_resolved.connect(func(_x, _y, m, r):
				if not per_move.has(m.id): per_move[m.id] = [0, 0, 0, 0, 0, 0]
				per_move[m.id][1 + r.outcome] += 1)
		a.clinch_requested.connect(func(_x): clinches[0] += 1)
		b.clinch_requested.connect(func(_x): clinches[0] += 1)
		f.phase_changed.connect(func(_p): pass)
		var guard := 0
		var last_clinch: Clinch = null
		while f.phase != FightFlow.Phase.OVER and guard < 200000:
			f.tick()
			guard += 1
			if f.clinch != last_clinch and f.clinch != null:
				last_clinch = f.clinch
				last_clinch.ended.connect(func(r): if r == &"break": breaks[0] += 1)
		var m: String = f.result.method
		methods[m] = methods.get(m, 0) + 1
		var wi: int = f.result.winner_index
		if wi < 0:
			wins[2] += 1
		else:
			var a_won := (wi == 0) != swap
			wins[0 if a_won else 1] += 1
			if a_won:
				a_methods[m] = a_methods.get(m, 0) + 1
		rounds_sum += f.result.round
		kd_sum += a.body.knockdowns_total + b.body.knockdowns_total
		if a.body.cut > 0 or b.body.cut > 0:
			cut_fights += 1
		for s in f.stats:
			landed_sum += s[0].landed + s[1].landed
			sweeps += s[0].sweeps + s[1].sweeps
			checks += s[0].checks + s[1].checks
			control += s[0].control_frames + s[1].control_frames
		time_sum += (f.result.round - 1) * 180 + f.result.time
		for k in 3:
			zone_dmg[k] += 200.0 - a.body.hp[k] - b.body.hp[k]
		for ctl in [ba, bb]:
			if ctl is AIController:
				for k in ctl.debug_sources:
					sources[k] = sources.get(k, 0) + ctl.debug_sources[k]
		for node in [a, b, ba, bb]:
			node.free()
	var names: Array = datas.map(func(d): return ("(" + d.display_name + ")") if d else "")
	print("fights: %d  (%.1fs)  A=%s%s vs B=%s%s" % [n, (Time.get_ticks_msec() - t0) / 1000.0, kinds[0], names[0], kinds[1], names[1]])
	print("A wins %d (%d%%)  B wins %d  draws %d   A's wins by: %s" % [wins[0], wins[0] * 100 / n, wins[1], wins[2], a_methods])
	print("methods: ", methods)
	print("avg rounds: %.2f  avg knockdowns/fight: %.2f  fights with a cut: %d%%  avg landed/fight: %.0f" % [
		float(rounds_sum) / n, float(kd_sum) / n, cut_fights * 100 / n, float(landed_sum) / n])
	print("avg fight length: %ds  counter hits/fight: %.1f  avg dmg taken per fight head/body/legs: %.0f/%.0f/%.0f" % [
		time_sum / n, float(counters[0]) / n, zone_dmg[0] / n, zone_dmg[1] / n, zone_dmg[2] / n])
	print("clinches/fight: %.1f  ref breaks/fight: %.1f  sweeps/fight: %.2f  checks/fight: %.1f  dominant clinch time/fight: %ds" % [
		float(clinches[0]) / n, float(breaks[0]) / n, float(sweeps) / n, float(checks) / n, control / 60 / n])
	if show_moves:
		print("move               thrown/fight  hit%  block%  parry%  checked%  whiff%")
		for id in per_move:
			var c: Array = per_move[id]
			var t: float = maxf(c[0], 1)
			print("%-18s %8.1f   %4.0f  %5.0f  %6.0f  %8.0f  %6.0f" % [id, c[0] / float(n), c[1] * 100 / t, c[2] * 100 / t,
				c[3] * 100 / t, c[4] * 100 / t, (t - c[1] - c[2] - c[3] - c[4]) * 100 / t])
	if show_moves and not sources.is_empty():
		var keys := sources.keys()
		keys.sort_custom(func(x, y): return sources[x] > sources[y])
		print("AI decision sources (per fight): ", ", ".join(keys.slice(0, 20).map(func(k): return "%s %.1f" % [k, sources[k] / float(n)])))
	quit()

func _controller(kind: String, seed: int, data: FighterData) -> Node:
	var levels := {"easy": AIController.Difficulty.EASY, "medium": AIController.Difficulty.MEDIUM,
			"hard": AIController.Difficulty.HARD}
	if kind in levels or kind == "rating":
		var p := AIController.Profile.for_rating(data.difficulty if data else 3) if kind == "rating" \
				else AIController.Profile.for_difficulty(levels[kind])
		return AIController.new(p.apply_style(data), seed)
	var r := RandomBot.new()
	r.rng.seed = seed
	return r

func _fighter() -> Fighter:
	var f: Fighter = load("res://scenes/fighter.tscn").instantiate()
	root.add_child(f)
	f.setup(Color.RED, Vector3.ZERO)
	if _cage:
		f.bounds = ArenaBounds.cage()
	return f
