class_name AIController
extends Node
## CPU opponent. Same interface as PlayerController, so a fighter can be driven by either.
## poll_attack() is called first in Fighter.tick(), so it is also where the AI thinks; get_move() and
## is_guard_held() return what that decision chose.
##
## Utility-based: the AI scores its options (strike, clinch, defend, punish, reposition) from what it
## *perceives*. Perception of the opponent's actions lags reality by the profile's reaction time, so an
## Easy AI sees a cross coming far too late to parry it and a Hard one usually doesn't. Health and stamina
## are read live (a human sees them on the HUD too).
##
## Deterministic: all randomness comes from `rng`, seeded by whoever creates the controller.

enum Difficulty { EASY, MEDIUM, HARD }

## Everything that makes one CPU fighter differ from another. Difficulty presets fill the skill fields;
## style fields default to a balanced fighter (FighterData style profiles override them in milestone 8b).
class Profile:
	var name := "Medium"
	# --- skill ---
	var reaction := 12        ## frames of perception lag
	var think_every := 6      ## frames between offensive decisions
	var defense := 0.6        ## chance of reacting to an incoming strike at all
	var read := 0.75          ## chance that reaction is the right one (guard vs check)
	var parry := 0.25         ## chance of timing a parry instead of just covering up
	var slip := 0.2           ## chance of slipping a head punch instead of covering up
	var punish := 0.5         ## chance of punishing a whiff, a stagger or a missed check
	var combo := 0.4          ## chance of chaining a follow-up after a landed/blocked strike
	var counter := 0.2        ## chance of beating a slow strike with a faster one instead of defending
	var aggression := 0.5     ## how often it opens up when nothing better is on
	var noise := 0.35         ## softmax temperature over move utilities (higher = sloppier choices)
	var range_error := 0.15   ## distance misjudgement (m)
	var gas := 0.6            ## stamina management (0 = gasses out, 1 = paces itself)
	var smart := 0.6          ## targets damaged zones / exploits a held guard with low kicks
	var shell := 0.4          ## how often it keeps a guard up while in the opponent's range
	# --- style ---
	var punch_bias := 1.0
	var kick_bias := 1.0
	var knee_bias := 1.0
	var clinch_bias := 1.0
	var preferred_range := 1.45  ## where it likes to hover when not attacking (m, centre to centre)
	var move_bias := {}          ## move id -> extra pick weight (FighterData signatures "ai")

	const SKILL_FIELDS := ["reaction", "think_every", "defense", "read", "parry", "slip", "punish", "combo",
			"counter", "aggression", "noise", "range_error", "gas", "smart", "shell"]

	## Roster difficulty 1..5: 1/3/5 are the Easy/Medium/Hard presets, 2 and 4 sit halfway between.
	static func for_rating(r: int) -> Profile:
		r = clampi(r, 1, 5)
		var lo := for_difficulty([Difficulty.EASY, Difficulty.EASY, Difficulty.MEDIUM, Difficulty.MEDIUM, Difficulty.HARD][r - 1])
		if r % 2 == 1:
			return lo
		var hi := for_difficulty(Difficulty.MEDIUM if r == 2 else Difficulty.HARD)
		for k in SKILL_FIELDS:
			var v = lerpf(float(lo.get(k)), float(hi.get(k)), 0.5)
			lo.set(k, roundi(v) if typeof(lo.get(k)) == TYPE_INT else v)
		lo.name = "Level %d" % r
		return lo

	## Copy a roster fighter's style (biases, range, signature preferences); skill fields are untouched.
	func apply_style(d: FighterData) -> Profile:
		if d == null:
			return self
		punch_bias = d.punch_bias
		kick_bias = d.kick_bias
		knee_bias = d.knee_bias
		clinch_bias = d.clinch_bias
		preferred_range = d.preferred_range * d.reach_factor()
		for mid in d.signatures:
			move_bias[mid] = d.signature(mid, "ai")
		return self

	static func for_difficulty(d: Difficulty) -> Profile:
		var p := Profile.new()
		match d:
			Difficulty.EASY:
				p.name = "Easy"
				p.reaction = 24
				p.think_every = 12
				p.defense = 0.3
				p.read = 0.5
				p.parry = 0.0
				p.slip = 0.03
				p.punish = 0.15
				p.combo = 0.1
				p.counter = 0.0
				p.aggression = 0.35
				p.noise = 0.9
				p.range_error = 0.35
				p.gas = 0.1
				p.smart = 0.1
				p.shell = 0.1
			Difficulty.MEDIUM:
				pass
			Difficulty.HARD:
				p.name = "Hard"
				p.reaction = 6
				p.think_every = 3
				p.defense = 0.85
				p.read = 0.92
				p.parry = 0.55
				p.slip = 0.35
				p.punish = 0.85
				p.combo = 0.65
				p.counter = 0.35
				p.aggression = 0.6
				p.noise = 0.15
				p.range_error = 0.05
				p.gas = 0.9
				p.smart = 1.0
				p.shell = 0.6
		return p

const STRIKES: Array[StringName] = [&"jab", &"cross", &"lead_hook", &"rear_hook", &"uppercut", &"teep",
		&"side_kick", &"round_kick_low", &"round_kick_body", &"round_kick_high", &"knee"]
## Natural follow-ups after a strike connects (or is blocked).
const FOLLOW_UPS := {
	&"jab": [&"cross", &"cross", &"round_kick_low", &"jab"],
	&"cross": [&"lead_hook", &"round_kick_low", &"round_kick_body"],
	&"lead_hook": [&"rear_hook", &"cross", &"round_kick_body"],
	&"rear_hook": [&"lead_hook", &"round_kick_low"],
	&"uppercut": [&"lead_hook", &"rear_hook"],
	&"teep": [&"round_kick_body", &"cross"],
	&"knee": [&"rear_hook", &"uppercut"],
}
const EDGE_MARGIN := 1.0       ## start steering away from the ropes this far from them
const STRIKE_MARGIN := 0.08    ## aim to be this much inside a move's reach before throwing it
const PARRY_LEAD := 3          ## press guard this many frames before the hit for a parry
const GUARD_LINGER := 6        ## keep the guard up this long after a threat passes
const ASSUMED_REACTION := 10   ## how fast we assume the opponent reacts when judging a strike

var profile := Profile.new()
var me: Fighter
var rng := RandomNumberGenerator.new()

var _frame := 0
var _seen: Array[Dictionary] = []   ## perception ring buffer, oldest first
var _move := Vector2.ZERO
var _guard := false
var _guard_until := 0               ## keep guard held until this frame
var _guard_release_at := -1         ## drop the guard on this frame (to re-press it for a parry)
var _threat_id := -1                ## which opponent attack we've already decided about
var _threat_plan := &""             ## &"guard", &"parry", &"check", &"evade", &"counter", &"none"
var _punished_id := -1
var _next_think := 0
var _intent: StringName = &""       ## move we're closing distance to throw
var _intent_until := 0
var _combo_next: StringName = &""
var _circle := 1.0
var _circle_until := 0
var _range_jitter := 0.0
var _connected := false
var debug_sources := {}            ## "path:move" -> count (sim harness diagnostics)
var _src := ""
var _defending := false             ## _defend() took over this frame's inputs
var _opp_guard_rate := 0.3          ## running estimate of how much the opponent shells up
var _shell_until := 0               ## pocket guard: decided per short window
var _shell_on := false
var _slip_countered := false        ## already decided about the counter window from this slip

func _init(p: Profile = null, seed: int = 0) -> void:
	if p:
		profile = p
	rng.seed = seed

static func create(d: Difficulty, seed: int = 0) -> AIController:
	return AIController.new(Profile.for_difficulty(d), seed)

func get_move() -> Vector2:
	return _move

func is_guard_held() -> bool:
	return _guard

## Called once per tick while the fighter has control. Updates perception and decides this frame.
func poll_attack() -> StringName:
	_frame += 1
	if me == null or me.opponent == null:
		return &""
	if not _connected:
		me.move_resolved.connect(_on_my_strike_resolved)
		_connected = true
	_observe()
	_move = Vector2.ZERO
	_guard = false
	_src = "offense"
	var out: StringName
	if me.state == Fighter.State.CLINCH and me.clinch:
		_combo_next = &""
		_src = "clinch"
		out = _think_clinch()
	else:
		out = _think_free()
	if out != &"":
		var k := _src + ":" + String(out)
		debug_sources[k] = debug_sources.get(k, 0) + 1
	return out

# --- perception ---

func _observe() -> void:
	var o := me.opponent
	var d := o.global_position - me.global_position
	_seen.append({
		"frame": _frame,
		"state": o.state,
		"move": o.current_move,
		"phase": o.attack_phase(),
		"to_active": o.frames_to_active(),
		"free_in": o.frames_until_free(),
		"guarding": o.state == Fighter.State.GUARD,
		"checking": o.state == Fighter.State.CHECK,
		"dist": Vector2(d.x, d.z).length(),
		"attack_id": _attack_id(o),
		"c_act": o.clinch.current_action(o.clinch.index_of(o)) if o.clinch else &"",
	})
	var g := 1.0 if _seen[0].guarding else 0.0
	_opp_guard_rate = lerpf(_opp_guard_rate, g, 0.01)
	while _seen.size() > profile.reaction + 1:
		_seen.pop_front()

## What the AI "sees" now: the opponent as they were `reaction` frames ago.
func _perceived() -> Dictionary:
	return _seen[0]

## Identifies one particular attack so each gets exactly one defensive decision.
func _attack_id(o: Fighter) -> int:
	if o.state != Fighter.State.ATTACK:
		return -1
	return _frame - o.state_frame  # the frame it started: stable for the whole attack

## Distance right now (footwork uses live distance: you can see where they stand).
func _dist() -> float:
	var d := me.opponent.global_position - me.global_position
	return Vector2(d.x, d.z).length()

func _free() -> bool:
	return me.state == Fighter.State.IDLE or me.state == Fighter.State.MOVE or me.state == Fighter.State.GUARD

# --- standing up ---

func _think_free() -> StringName:
	var o := _perceived()
	var opp := me.opponent
	if opp.is_down():
		_footwork(profile.preferred_range + 0.6)
		return &""
	# A follow-up we decided on when the last strike connected: buffer it near the end of recovery.
	if _combo_next != &"":
		if me.state == Fighter.State.ATTACK:
			if me.frames_until_free() <= Fighter.BUFFER_FRAMES - 2:
				var c := _combo_next
				_combo_next = &""
				if _reaches(c, 0.05):
					_src = "combo"
					return c
			return &""
		_combo_next = &""
	var sc := _slip_counter()
	if sc != &"":
		_src = "slip_counter"
		return sc
	if not _free():
		return &""
	_defending = false
	_src = "defend"
	var out := _defend(o)
	if out != &"" or _defending:
		return out
	out = _punish(o)
	if out != &"":
		_src = "punish"
		return out
	_src = "offense"
	# Hold a pending guard (after a threat, or while waiting for a parry window).
	if _frame < _guard_until:
		_guard = true
	out = _offense(o)
	if out != &"":
		return out
	_pocket_guard()
	var want := _intent_range()
	_footwork(want)
	return &""

## Jabs are faster than anyone's reactions: inside their range, a good fighter keeps the hands up.
func _pocket_guard() -> void:
	if _frame >= _shell_until:
		_shell_until = _frame + rng.randi_range(20, 50)
		_shell_on = rng.randf() < profile.shell
	if _shell_on and _dist() <= 1.6 and _intent == &"":
		_guard = true

## React to an incoming strike. Returns a move id (check / counter) or sets _guard / _move.
func _defend(o: Dictionary) -> StringName:
	if o.state != Fighter.State.ATTACK or o.move == null:
		return &""
	var m: MoveData = o.move
	if m.action != MoveData.Action.STRIKE or o.phase == &"recovery":
		return &""
	# Frames until the hit lands, extrapolated from the delayed sighting (we know how long the windup is).
	var eta: int = o.to_active - profile.reaction
	var live := me.opponent
	if live.state != Fighter.State.ATTACK or live.attack_phase() == &"recovery":
		return &""  # it's over (we just haven't "seen" it yet: harmless either way)
	if o.dist > m.reach + 0.35:
		return &""  # out of range when they started: let it whiff
	if o.attack_id != _threat_id:
		_threat_id = o.attack_id
		_threat_plan = _plan_defense(m, eta, o.dist)
	_defending = _threat_plan != &"none" and _threat_plan != &"done"
	match _threat_plan:
		&"check":
			if me.state != Fighter.State.CHECK and eta <= Fighter.CHECK_ACTIVE - 2:
				_threat_plan = &"done"
				return &"check"
		&"guard":
			_guard = true
			_guard_until = _frame + GUARD_LINGER
		&"parry":
			# Guard must be *fresh* when the hit lands: release, then press PARRY_LEAD frames before impact.
			if eta > PARRY_LEAD:
				_guard = false
			else:
				_guard = true
				_guard_until = _frame + GUARD_LINGER
		&"slip":
			# Press so the slip's active frames cover the punch's: eta counts down to its first active frame.
			if eta <= Fighter.SLIP_STARTUP + 6:
				_threat_plan = &"done"
				var to := _to_opponent()
				_move = Vector2(-to.y, to.x) * (1.0 if rng.randf() < 0.5 else -1.0)
				return &"slip"
		&"evade":
			_move = -_to_opponent()
			_guard = eta <= 2  # too close to call: cover up as we step out
		&"counter":
			var c := _fastest_counter(eta)
			_threat_plan = &"none"
			if c != &"":
				return c
			_guard = true
	return &""

func _plan_defense(m: MoveData, eta: int, dist: float) -> StringName:
	if rng.randf() > profile.defense or eta < -m.active:
		return &"none"
	# Step out of range if the strike barely reaches and there's time.
	var spare := m.reach - dist
	var step := Fighter.SPEED * me.body.speed_factor() * Fighter.FRAME
	if spare >= 0.0 and spare < step * maxf(eta, 0) - 0.05 and rng.randf() < 0.5:
		return &"evade"
	if rng.randf() < profile.counter and _fastest_counter(eta) != &"":
		return &"counter"
	var correct: StringName
	if m.zone == MoveData.Zone.HEAD and m.strike_type == MoveData.StrikeType.PUNCH and m.slippable \
			and eta >= Fighter.SLIP_STARTUP + 1 and rng.randf() < profile.slip:
		correct = &"slip"
	elif m.zone == MoveData.Zone.LEGS:
		correct = &"check" if m.strike_type != MoveData.StrikeType.PUNCH else &"evade"
	elif m.parryable and rng.randf() < profile.parry:
		correct = &"parry"
	else:
		correct = &"guard"
	if rng.randf() < profile.read:
		return correct
	# Misread: guard a leg kick, or lift the shin against a punch.
	return &"guard" if correct == &"check" else &"check"

## Just slipped a punch: fire a counter out of the slip (once per slip, `punish` decides whether).
func _slip_counter() -> StringName:
	if me.slip_counter <= 0:
		_slip_countered = false
		return &""
	if _slip_countered or not (_free() or me.state == Fighter.State.SLIP):
		return &""
	_slip_countered = true
	if rng.randf() > profile.punish:
		return &""
	var opts: Array[StringName] = [&"cross", &"rear_hook", &"lead_hook", &"uppercut", &"jab"]
	for i in opts.size():
		var j := rng.randi_range(i, opts.size() - 1)
		var t := opts[i]
		opts[i] = opts[j]
		opts[j] = t
	for id in opts:
		if _reaches(id):
			return id
	return &""

## A strike that lands before theirs does (counter hits get the counter bonus).
func _fastest_counter(eta: int) -> StringName:
	var best: StringName = &""
	var best_start := 999
	var scale := me.stam.frame_scale()
	for id in [&"jab", &"cross", &"lead_hook", &"teep"]:
		var mv: MoveData = me.moves.get(id)
		if mv == null:
			continue
		var s := roundi(mv.startup * scale) + 1
		if s < eta and s < best_start and _reaches(id):
			best = id
			best_start = s
	return best

## Opponent is stuck (stagger after parry/check, whiffed strike, missed check, stun): hit them.
func _punish(o: Dictionary) -> StringName:
	var vulnerable := false
	match o.state:
		Fighter.State.STAGGER, Fighter.State.HITSTUN:
			vulnerable = true
		Fighter.State.ATTACK:
			vulnerable = o.phase == &"recovery"
		Fighter.State.CHECK:
			vulnerable = o.to_active < 0 and o.free_in > 0 and o.free_in < Fighter.CHECK_RECOVERY + 1
	if not vulnerable:
		return &""
	var window: int = o.free_in - profile.reaction
	var key: int = o.frame + o.free_in  # the frame they recover: one decision per opening
	if key == _punished_id:
		return &""
	_punished_id = key
	if window < 4 or rng.randf() > profile.punish:
		return &""
	var ids: Array[StringName] = []
	var us: Array[float] = []
	var scale := me.stam.frame_scale()
	for id in STRIKES:
		var mv: MoveData = me.moves.get(id)
		if mv == null or roundi(mv.startup * scale) + 1 > window or not _reaches(id):
			continue
		ids.append(id)
		us.append(_value(mv) - mv.stamina_cost * 0.05)
	var pick := _softmax_pick(us, ids)
	return ids[pick] if pick >= 0 else &""

## Pick a strike (or a clinch entry) by utility; if the best is out of range, walk in to throw it.
func _offense(o: Dictionary) -> StringName:
	if _intent != &"" and _frame < _intent_until:
		if _reaches(_intent, rng.randf_range(-profile.range_error, profile.range_error)):
			_src = "intent"
			var go := _intent
			_intent = &""
			return go
		return &""
	_intent = &""
	if _frame < _next_think:
		return &""
	_next_think = _frame + profile.think_every + rng.randi_range(0, profile.think_every)
	# Pace yourself: a good AI backs off to breathe instead of throwing on an empty tank.
	var stam := me.stam.ratio()
	if stam < 0.3 * profile.gas + 0.05 and rng.randf() < profile.gas:
		return &""
	var rate := profile.aggression * (0.55 + 0.45 * stam)
	if rng.randf() > rate:
		return &""
	var ids: Array[StringName] = []
	var us: Array[float] = []
	for id in STRIKES:
		var mv: MoveData = me.moves.get(id)
		if mv == null:
			continue
		ids.append(id)
		us.append(_utility(mv, o))
	if me.moves.has(&"clinch"):
		ids.append(&"clinch")
		us.append(_clinch_utility(o))
	var pick := _softmax_pick(us, ids)
	if pick < 0 or us[pick] <= 0.0:
		return &""
	var choice := ids[pick]
	if _reaches(choice, rng.randf_range(-profile.range_error, profile.range_error)):
		return choice
	# Walk in for it (but not forever).
	_intent = choice
	_intent_until = _frame + 45
	return &""

## Expected payoff of throwing `mv` now, from what we perceive.
##
## The model: a strike slower than the defender's reactions gets seen and covered (guard, or a check for
## leg kicks); a strike slower than one of their strikes that reaches us gets beaten to the punch; a
## defender locked in their own move can do neither. `smart` blends this model with a naive coin flip.
func _utility(mv: MoveData, o: Dictionary) -> float:
	var opp := me.opponent
	var eta := roundi(mv.startup * me.stam.frame_scale()) + 1
	var busy: bool = o.free_in - profile.reaction > eta  # they can't respond before it lands
	var p_def := 0.0
	var p_counter := 0.0
	var habit := lerpf(1.0 if o.guarding else 0.0, _opp_guard_rate, 0.5 * profile.smart)
	if not busy:
		var telegraph := clampf(float(eta - ASSUMED_REACTION) / 6.0, 0.0, 1.0)
		if mv.zone == MoveData.Zone.LEGS:
			p_def = 0.6 * telegraph  # checked
		else:
			p_def = maxf(habit, 0.75 * telegraph)
		var fastest := _fastest_threat(opp, _dist())
		p_counter = 0.4 * clampf(float(eta - fastest) / 5.0, 0.0, 1.0)
	elif o.checking and mv.strike_type != MoveData.StrikeType.PUNCH and mv.zone != MoveData.Zone.HEAD:
		p_def = 1.0  # shin already up
	var model_p := (1.0 - p_def) * (1.0 - p_counter)
	var p := lerpf(0.55, model_p, 0.4 + 0.6 * profile.smart)
	var value := _value(mv)
	if busy and o.phase == &"startup":
		value *= 1.0 + mv.counter_bonus  # catching them mid-move
	# A guarded strike still scores a little and drains their stamina (more with guard_break).
	var blocked: float = mv.damage * Judges.WEIGHT[mv.strike_type] * (0.15 + 0.3 * mv.guard_break) \
		if mv.zone != MoveData.Zone.LEGS else 0.0
	# Whiffing leaves us open for the move's recovery; getting countered costs more.
	var risk := mv.recovery * 0.12 * (0.5 + 0.5 * opp.stam.ratio())
	var cost := mv.stamina_cost * 0.05 * (1.0 + 3.0 * profile.gas * me.stam.fatigue())
	return p * value + (1.0 - p) * (1.0 - p_counter) * p_def * blocked \
		- p_counter * 8.0 - (1.0 - p) * risk - cost

## Frames until the opponent's quickest strike that reaches us right now could land.
static func _fastest_threat(f: Fighter, dist: float) -> int:
	var best := 999
	var scale := f.stam.frame_scale()
	for id in STRIKES:
		var mv: MoveData = f.moves.get(id)
		if mv and mv.reach >= dist:
			best = mini(best, roundi(mv.startup * scale) + 1)
	return best

## Raw payoff of landing `mv`: scoring weight x damage, focused on whatever is already hurt.
func _value(mv: MoveData) -> float:
	var opp := me.opponent
	var hurt := 1.0 - opp.body.ratio(mv.zone)
	var focus := 1.0 + hurt * 1.5 * profile.smart
	if mv.zone == MoveData.Zone.HEAD:
		focus += hurt * hurt * 2.0 * profile.smart  # smell blood: go for the finish
	return mv.damage * Judges.WEIGHT[mv.strike_type] * focus

## Style prior for picking `id`: how much more (or less) often this fighter reaches for it, all else equal.
## Applied to the softmax weight rather than the utility, so a 1.3 bias means "1.3x as often" at any
## difficulty instead of swamping a low-noise (Hard) AI's choice.
func _style(id: StringName) -> float:
	var mv: MoveData = me.moves.get(id) if me else null
	if mv == null:
		return 1.0
	var bias := profile.punch_bias
	match mv.strike_type:
		MoveData.StrikeType.KICK, MoveData.StrikeType.TEEP:
			bias = profile.kick_bias
		MoveData.StrikeType.KNEE:
			bias = profile.knee_bias
	if mv.action == MoveData.Action.CLINCH_ENTRY:
		bias = profile.clinch_bias
	return maxf(0.0, bias * float(profile.move_bias.get(id, 1.0)))

func _clinch_utility(o: Dictionary) -> float:
	var opp := me.opponent
	var mine := me.strength * (0.4 + 0.6 * me.stam.ratio())
	var theirs := opp.strength * (0.4 + 0.6 * opp.stam.ratio())
	var u := 2.5 * clampf(mine / maxf(theirs, 0.1), 0.5, 1.5)
	u += 3.0 * profile.smart * _opp_guard_rate  # a shell can't stop a tie-up
	if me.body.ratio(MoveData.Zone.HEAD) < 0.4:
		u += 3.0 * profile.smart  # tie up to survive
	return u

func _softmax_pick(us: Array[float], ids: Array[StringName] = []) -> int:
	if us.is_empty():
		return -1
	var t := maxf(profile.noise, 0.01) * 4.0
	var mx: float = us.max()
	var ws: Array[float] = []
	var total := 0.0
	for u in us:
		var w := exp((u - mx) / t)
		if ids.size() == us.size():
			w *= _style(ids[ws.size()])
		ws.append(w)
		total += w
	var r := rng.randf() * total
	for i in ws.size():
		r -= ws[i]
		if r <= 0.0:
			return i
	return ws.size() - 1

## Will `id` still reach when it goes active? Predicts the opponent's drift during our windup
## (we stand still while striking). `err` is misjudgement added to the distance.
func _reaches(id: StringName, err := 0.0) -> bool:
	var mv: MoveData = me.moves.get(id)
	if mv == null:
		return false
	var opp := me.opponent
	var dir := _to_opponent()
	var drift := Vector2(opp.velocity.x, opp.velocity.z).dot(dir) * Fighter.FRAME
	var eta := roundi(mv.startup * me.stam.frame_scale()) + 1
	var predicted := _dist() + drift * eta * (0.3 + 0.7 * profile.smart)
	return _in_reach(id, maxf(_dist(), predicted) + err if drift > 0.0 else _dist() + err)

func _in_reach(id: StringName, dist: float) -> bool:
	var mv: MoveData = me.moves.get(id)
	return mv != null and dist <= mv.reach - STRIKE_MARGIN

func _on_my_strike_resolved(_a: Fighter, _d: Fighter, m: MoveData, res: Dictionary) -> void:
	if me.state == Fighter.State.CLINCH or not FOLLOW_UPS.has(m.id):
		return
	var landed: bool = res.outcome == CombatResolver.Outcome.HIT
	var blocked: bool = res.outcome == CombatResolver.Outcome.BLOCK
	if not (landed or blocked) or rng.randf() > profile.combo:
		return
	if blocked and rng.randf() < profile.smart:
		_combo_next = &"round_kick_low"  # they're covering up high: go low
		return
	var opts: Array = FOLLOW_UPS[m.id]
	_combo_next = opts[rng.randi() % opts.size()]

# --- footwork ---

## Preferred distance right now: close in for an intended strike, back off when tired or hurt.
func _intent_range() -> float:
	if _intent != &"":
		var mv: MoveData = me.moves[_intent]
		return mv.reach - STRIKE_MARGIN - 0.1
	if _frame % 90 == 0:
		_range_jitter = rng.randf_range(-0.25, 0.25)
	var r := profile.preferred_range + _range_jitter
	var stam := me.stam.ratio()
	if stam < 0.35:
		r += 0.7 * profile.gas  # out of range to breathe
	if me.body.ratio(MoveData.Zone.HEAD) < 0.35:
		r += 0.4 * profile.smart
	return r

func _footwork(want: float) -> void:
	var to := _to_opponent()
	var dist := _dist()
	var radial := clampf((dist - want) * 3.0, -1.0, 1.0)
	if absf(dist - want) < 0.08:
		radial = 0.0
	if _frame >= _circle_until:
		_circle = -_circle if rng.randf() < 0.5 else _circle
		_circle_until = _frame + rng.randi_range(40, 150)
	var side := Vector2(-to.y, to.x) * _circle * 0.5
	var v := to * radial + side
	# Don't get pinned on the ropes / fence: steer back toward the centre, circling out rather than straight back.
	var p := Vector2(me.global_position.x, me.global_position.z)
	var push := me.bounds.inward_push(p, EDGE_MARGIN) / EDGE_MARGIN
	if push.length() > 0.0:
		if side.dot(push) < 0.0:
			_circle = -_circle
			side = -side
		v += push * 1.5 * (0.3 + 0.7 * profile.smart)
	_move = v.limit_length(1.0)

func _to_opponent() -> Vector2:
	var d := me.opponent.global_position - me.global_position
	var v := Vector2(d.x, d.z)
	return v.normalized() if v.length() > 0.001 else Vector2.RIGHT

# --- clinch ---

func _think_clinch() -> StringName:
	var c := me.clinch
	var i := c.index_of(me)
	var j := 1 - i
	var opp := me.opponent
	var pos := c.position_of(i)
	var o := _perceived()
	var their_act: StringName = o.c_act  # seen `reaction` frames late, like a strike
	# Frame (forearms up) against a knee we see coming; when controlled (that's when knees come), sometimes
	# frame pre-emptively. Fast knees beat slow reactions: only quick fighters frame them on sight.
	if _frame < _guard_until:
		_guard = true
	if their_act == &"knee":
		if _frame >= _guard_until and rng.randf() < profile.defense:
			_guard = true
			_guard_until = _frame + 10
	if pos == Clinch.Pos.CONTROLLED:
		_pocket_guard_clinch()
		_guard = _guard or _shell_on
	if not c.can_act(i) or _frame < _next_think:
		return &""
	_next_think = _frame + profile.think_every + rng.randi_range(0, profile.think_every) + profile.reaction / 2
	var power_ratio := c.power(i) / maxf(c.power(j), 0.01)
	var stam := me.stam.ratio()
	var off_bal := their_act == &"knee"
	var r := rng.randf()
	match pos:
		Clinch.Pos.DOMINANT:
			if (off_bal or opp.body.ratio(MoveData.Zone.LEGS) < 0.45) and r < 0.3 + 0.5 * profile.smart:
				return &"round_kick_body"  # sweep
			if r < 0.75 * profile.knee_bias:
				if opp.body.ratio(MoveData.Zone.HEAD) < opp.body.ratio(MoveData.Zone.BODY) or rng.randf() < 0.35:
					_move = Vector2(0, -1)  # W held: plum knee to the head
				return &"knee"
			return &"clinch"  # pummel to keep position
		Clinch.Pos.NEUTRAL:
			if off_bal and r < 0.5 * profile.smart:
				return &"clinch"  # pummel while they're on one leg
			if profile.clinch_bias < 0.7 and rng.randf() < 0.5:
				return &"teep"  # strikers want out
			if stam < 0.2 * profile.gas:
				return &"teep"
			return &"knee" if r < 0.3 * profile.knee_bias else &"clinch"
		_:
			# Escaping from under control rarely works; mostly fight back for position.
			if stam < 0.25 or rng.randf() < 0.25 * (1.5 - clampf(power_ratio, 0.5, 1.5)) / maxf(profile.clinch_bias, 0.2):
				return &"teep"
			return &"clinch"
	return &""

func _pocket_guard_clinch() -> void:
	if _frame >= _shell_until:
		_shell_until = _frame + rng.randi_range(20, 50)
		_shell_on = rng.randf() < profile.shell
