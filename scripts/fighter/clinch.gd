class_name Clinch
extends RefCounted
## Pair-level clinch contest. While active, both fighters sit in Fighter.State.CLINCH and only forward
## their button presses; FightFlow ticks this after the fighters each frame.
##
## Position is one number, `advantage` in [-1, 1], seen from fighters[0] (the initiator).
## |advantage| < DOMINANT_AT is neutral; beyond it one fighter is dominant and the other controlled.
##
## Inputs inside the clinch (same buttons as outside):
##   clinch (C)      pummel: contest for position (strength x stamina x body condition)
##   knee (N)        knee: neutral = short knee to body; dominant = plum knee (body, or head with W held)
##   round kick (H)  sweep/dump: from dominant; easier against a fighter standing on one leg mid-knee
##   teep (L)        escape: push off; easy from dominant/neutral, hard when controlled
##   walk away       hold a direction away from the opponent (when not dominant): repeated escape attempts
##   guard (Space)   frame: blocks knees and makes you harder to pummel

enum Pos { NEUTRAL, DOMINANT, CONTROLLED }

const DOMINANT_AT := 0.35
const START_ADVANTAGE := 0.15     ## the initiator starts slightly ahead
const PUMMEL_FRAMES := 18
const PUMMEL_STEP := 0.4          ## advantage gained on a won pummel
const PUMMEL_FAIL_STEP := 0.1     ## advantage lost on a lost pummel
const PUMMEL_COST := 4.0
const FRAMING_RESIST := 1.25      ## framing multiplies your resistance to pummels
const OFF_BALANCE_MULT := 1.3     ## pummel bonus against a fighter mid-knee
const SWEEP_FRAMES := 14
const SWEEP_COST := 10.0
const SWEEP_BASE := 0.35
const SWEEP_OFF_BALANCE_BONUS := 0.35
const SWEEP_NEUTRAL_MULT := 0.4   ## sweeping from neutral is a gamble
const SWEEP_FAIL_SHIFT := 0.5     ## a failed sweep hands position to the opponent
const ESCAPE_FRAMES := 12
const ESCAPE_COST := 6.0
const ESCAPE_CHANCE := {Pos.DOMINANT: 1.0, Pos.NEUTRAL: 0.6, Pos.CONTROLLED: 0.25}
const HIT_LOCK_FACTOR := 0.5      ## fraction of a knee's hit stun the victim can't act in the clinch
const BREAK_FRAMES := 150         ## referee separates after this long without a knee or sweep
const MAX_FRAMES := 360           ## ...and after this long no matter what (no endless knee-until-KO clinches)
const WALK_ESCAPE_HOLD := 10      ## frames of holding away before the first push-off attempt
const WALK_ESCAPE_EVERY := 24     ## then one attempt per this many frames while still held
const DRAIN := {Pos.DOMINANT: 0.02, Pos.NEUTRAL: 0.04, Pos.CONTROLLED: 0.08}  ## stamina per frame
const SNAP_DISTANCE := 0.6
const BREAK_DISTANCE := 1.5

signal swept(attacker: Fighter, defender: Fighter)
signal escape_failed(fighter: Fighter)
## reason: &"sweep", &"escape", &"break" (referee), &"down" (knockdown), &"halt" (round end etc.)
signal ended(reason: StringName)

var fighters: Array[Fighter] = []
var advantage := START_ADVANTAGE
var active := true
var idle_frames := 0               ## frames since the last knee or sweep attempt
var frames := 0                    ## total frames in this clinch
var rng: RandomNumberGenerator
var _act: Array = [{}, {}]         ## per fighter: {} or {"id", "frame", "len", "move"}
var _lock: Array[int] = [0, 0]     ## frames a fighter can't start a new action (just got kneed)
var _away: Array[int] = [0, 0]     ## frames each fighter has been holding a direction away from the other

func _init(initiator: Fighter, other: Fighter, r: RandomNumberGenerator) -> void:
	fighters = [initiator, other]
	rng = r
	_place(SNAP_DISTANCE)
	for f in fighters:
		f.enter_clinch()
		f.clinch = self
	_update_notes()

## Position of fighter i (0/1) from their own point of view.
func position_of(i: int) -> Pos:
	var adv := advantage if i == 0 else -advantage
	if adv >= DOMINANT_AT:
		return Pos.DOMINANT
	if adv <= -DOMINANT_AT:
		return Pos.CONTROLLED
	return Pos.NEUTRAL

func index_of(f: Fighter) -> int:
	return fighters.find(f)

## Clinch strength: base strength scaled by stamina, legs and body condition.
func power(i: int) -> float:
	var f := fighters[i]
	return f.strength * (0.4 + 0.6 * f.stam.ratio()) \
		* (0.6 + 0.4 * f.body.ratio(MoveData.Zone.LEGS)) \
		* (0.7 + 0.3 * f.body.ratio(MoveData.Zone.BODY))

## True while fighter i is throwing a knee (standing on one leg).
func off_balance(i: int) -> bool:
	return _act[i].get("id", &"") == &"knee"

func current_action(i: int) -> StringName:
	return _act[i].get("id", &"")

## True when fighter i can start a new clinch action this frame (not busy, not locked out by a knee).
func can_act(i: int) -> bool:
	return _act[i].is_empty() and _lock[i] == 0

func tick() -> void:
	if not active:
		return
	for f in fighters:
		if f.state != Fighter.State.CLINCH:
			end(&"down")
			return
	idle_frames += 1
	frames += 1
	for i in 2:
		fighters[i].stam.spend(DRAIN[position_of(i)])
		if _lock[i] > 0:
			_lock[i] -= 1
	for i in 2:
		_tick_action(i)
		if not active:
			return
	for i in 2:
		_start_intent(i)
	if idle_frames >= BREAK_FRAMES or frames >= MAX_FRAMES:
		end(&"break")
		return
	_update_notes()

func end(reason: StringName) -> void:
	if not active:
		return
	_deactivate()
	var standing := fighters.all(func(f: Fighter) -> bool: return not f.is_down())
	for f in fighters:
		f.exit_clinch()
	if standing and reason != &"halt":
		_place(BREAK_DISTANCE)
	ended.emit(reason)

# --- actions ---

func _start_intent(i: int) -> void:
	var f := fighters[i]
	var pos := position_of(i)
	var id := f.take_clinch_intent()
	_away[i] = _away[i] + 1 if pos != Pos.DOMINANT and walking_away(i) else 0
	if id == &"" and _away[i] >= WALK_ESCAPE_HOLD and (_away[i] - WALK_ESCAPE_HOLD) % WALK_ESCAPE_EVERY == 0:
		id = &"teep"  # pushing off by walking away
	if id == &"" or not _act[i].is_empty() or _lock[i] > 0:
		return
	match id:
		&"clinch":
			_begin(i, &"pummel", PUMMEL_FRAMES, PUMMEL_COST)
		&"knee":
			if pos == Pos.CONTROLLED:
				return  # no room to knee when you're being controlled
			var key := &"clinch_knee"
			if pos == Pos.DOMINANT:
				key = &"clinch_knee_head" if _pushing(i) > 0.5 else &"clinch_knee_body"
			var m: MoveData = f.moves[key]
			_begin(i, &"knee", m.total_frames(), m.stamina_cost, m)
			f.attack_started.emit(f, m)
			idle_frames = 0
		&"round_kick_low", &"round_kick_body", &"round_kick_high":
			if pos == Pos.CONTROLLED:
				return
			_begin(i, &"sweep", SWEEP_FRAMES, SWEEP_COST)
			idle_frames = 0
		&"teep":
			_begin(i, &"escape", ESCAPE_FRAMES, ESCAPE_COST)

## Fighter i is holding a direction pointing away from the other fighter.
func walking_away(i: int) -> bool:
	var mv := fighters[i].get_move_input()
	return mv.length() >= 0.5 and _pushing(i) / mv.length() < -0.5

## How far fighter i's held direction points at the other fighter (+1 = straight forward, -1 = straight back).
func _pushing(i: int) -> float:
	var d := fighters[1 - i].global_position - fighters[i].global_position
	return fighters[i].get_move_input().dot(Vector2(d.x, d.z).normalized())

func _begin(i: int, id: StringName, length: int, cost: float, m: MoveData = null) -> void:
	_act[i] = {"id": id, "frame": 0, "len": length, "move": m}
	fighters[i].stam.spend(cost)

func _tick_action(i: int) -> void:
	if _act[i].is_empty():
		return
	var a: Dictionary = _act[i]
	a.frame += 1
	match a.id:
		&"pummel":
			if a.frame == a.len:
				_resolve_pummel(i)
		&"knee":
			if a.frame == (a.move as MoveData).startup:
				_resolve_knee(i, a.move)
		&"sweep":
			if a.frame == a.len:
				_resolve_sweep(i)
		&"escape":
			if a.frame == a.len:
				_resolve_escape(i)
	if active and a.frame >= a.len and _act[i] == a:
		_act[i] = {}

func _resolve_pummel(i: int) -> void:
	var j := 1 - i
	var mine := power(i)
	if off_balance(j):
		mine *= OFF_BALANCE_MULT
	var theirs := power(j) * (FRAMING_RESIST if fighters[j].is_framing() else 1.0)
	var won := rng.randf() < mine / (mine + theirs)
	var sign := 1.0 if i == 0 else -1.0
	advantage = clampf(advantage + sign * (PUMMEL_STEP if won else -PUMMEL_FAIL_STEP), -1.0, 1.0)

func _resolve_knee(i: int, m: MoveData) -> void:
	var j := 1 - i
	var att := fighters[i]
	var def := fighters[j]
	var sd := def.snapshot()
	sd.mid_attack = off_balance(j)  # knee-vs-knee: the one caught on one leg eats a counter
	var res := CombatResolver.resolve(m, att.snapshot(), sd, rng)
	def.receive(res, m)
	if res.outcome == CombatResolver.Outcome.HIT:
		_act[j] = {}  # a clean knee interrupts whatever they were doing
		_lock[j] = int(res.stun * HIT_LOCK_FACTOR)
	att.move_resolved.emit(att, def, m, res)
	if def.state != Fighter.State.CLINCH:
		end(&"down")

func _resolve_sweep(i: int) -> void:
	var j := 1 - i
	var chance := SWEEP_BASE * power(i) / maxf(power(j), 0.01)
	if off_balance(j):
		chance += SWEEP_OFF_BALANCE_BONUS
	chance *= 1.3 - 0.3 * fighters[j].body.ratio(MoveData.Zone.LEGS)  # bad legs are easier to take out
	if position_of(i) == Pos.NEUTRAL:
		chance *= SWEEP_NEUTRAL_MULT
	chance = clampf(chance, 0.05, 0.9)
	if rng.randf() < chance:
		var att := fighters[i]
		var def := fighters[j]
		_deactivate()
		att.exit_clinch()
		def.get_swept()
		swept.emit(att, def)
		ended.emit(&"sweep")
	else:
		var sign := 1.0 if i == 0 else -1.0
		advantage = clampf(advantage - sign * SWEEP_FAIL_SHIFT, -1.0, 1.0)

func _resolve_escape(i: int) -> void:
	var j := 1 - i
	var chance: float = ESCAPE_CHANCE[position_of(i)] * clampf(power(i) / maxf(power(j), 0.01), 0.5, 1.5)
	if rng.randf() < clampf(chance, 0.05, 1.0):
		end(&"escape")
	else:
		escape_failed.emit(fighters[i])

# --- helpers ---

func _deactivate() -> void:
	active = false
	for f in fighters:
		if f.clinch == self:
			f.clinch = null

## Put the fighters `dist` apart along the line between them, around their midpoint.
func _place(dist: float) -> void:
	var a := fighters[0]
	var b := fighters[1]
	var mid := (a.global_position + b.global_position) * 0.5
	var dir := b.global_position - a.global_position
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.RIGHT
	var pa := mid - dir * dist * 0.5
	var pb := mid + dir * dist * 0.5
	pa.y = a.global_position.y
	pb.y = b.global_position.y
	a.global_position = a.bounds.clamp_position(pa)
	b.global_position = b.bounds.clamp_position(pb)

func _update_notes() -> void:
	for i in 2:
		var note: String = ["(neutral)", "(dominant)", "(controlled)"][position_of(i)]
		var act := current_action(i)
		if act != &"":
			note += " " + String(act)
		fighters[i].status_note = note
