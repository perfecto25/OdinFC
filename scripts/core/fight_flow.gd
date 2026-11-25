class_name FightFlow
extends RefCounted
## Referee + clock. Ticks both fighters at 60 Hz and runs rounds, knockdown counts,
## doctor checks and the decision. Pure logic (no rendering), so it runs headless in tests.

enum Phase { INTRO, FIGHTING, KNOCKDOWN, DOCTOR, ROUND_BREAK, OVER }

const FPS := 60
const INTRO_FRAMES := 90
const DOCTOR_FRAMES := 180
const MIN_COUNT := 8       ## mandatory count before the fight resumes
const COUNT_OUT := 10
const KD_TKO := 3          ## knockdowns in one round = TKO

signal phase_changed(phase: Phase)
signal fight_ended(result: Dictionary)

var fighters: Array[Fighter] = []
var rounds := 3
var round_frames := 180 * FPS
var rest_frames := 60 * FPS
var rng := RandomNumberGenerator.new()
var judges: Judges
var phase := Phase.INTRO
var phase_frame := 0
var round := 0
var clock := 0              ## frames left in the round
var stats: Array = []       ## stats[round-1] = [RoundStats a, RoundStats b]
var count := 0              ## referee's count during a knockdown
var downed: Fighter
var rise_at := 0            ## count at which the downed fighter gets up (>= COUNT_OUT = KO)
var doctor_for: Fighter
var result: Dictionary = {}
var start_positions: Array[Vector3] = [Vector3(-1.6, 0, 0), Vector3(1.6, 0, 0)]
var clinch: Clinch          ## the active clinch, if any
var event_text := ""        ## short call-out for the HUD ("SWEEP!", "BREAK!", "CHECKED!")
var event_frames := 0

var _pending_kd: Fighter
var _pending_doctor: Fighter

## cfg: rounds, round_seconds, rest_seconds, seed
func _init(a: Fighter, b: Fighter, cfg: Dictionary = {}) -> void:
	fighters = [a, b]
	rounds = cfg.get("rounds", 3)
	round_frames = int(cfg.get("round_seconds", 180) * FPS)
	rest_frames = int(cfg.get("rest_seconds", 60) * FPS)
	var seed: int = cfg.get("seed", 0)
	rng.seed = seed
	judges = Judges.new(seed)
	for f in fighters:
		f.rng = rng
		f.set_physics_process(false)
		f.move_resolved.connect(_on_resolved)
		f.attack_started.connect(_on_attack_started)
		f.clinch_requested.connect(_on_clinch_requested)
	_start_round(1)

func other(f: Fighter) -> Fighter:
	return fighters[1] if f == fighters[0] else fighters[0]

func tick() -> void:
	phase_frame += 1
	if event_frames > 0:
		event_frames -= 1
	match phase:
		Phase.INTRO:
			_tick_fighters(false)
			if phase_frame >= INTRO_FRAMES:
				_set_phase(Phase.FIGHTING)
		Phase.FIGHTING:
			_tick_fighters(true)
			if in_clinch():
				clinch.tick()
				_record_clinch_control()
			if _pending_kd:
				_begin_knockdown()
			elif _pending_doctor:
				_begin_doctor()
			else:
				clock -= 1
				if clock <= 0:
					_end_round()
		Phase.KNOCKDOWN:
			_tick_fighters(false)
			count = phase_frame / FPS
			if rise_at < COUNT_OUT and count >= rise_at and downed.state == Fighter.State.KNOCKDOWN:
				downed.rise()
			if rise_at >= COUNT_OUT and count >= COUNT_OUT:
				downed.set_ko()
				_finish("KO", other(downed))
			elif rise_at < COUNT_OUT and count >= maxi(rise_at, MIN_COUNT):
				_set_phase(Phase.FIGHTING)
		Phase.DOCTOR:
			_tick_fighters(false)
			if phase_frame >= DOCTOR_FRAMES:
				if rng.randf() < doctor_stoppage_chance(doctor_for.body.cut):
					_finish("TKO (doctor)", other(doctor_for))
				else:
					_set_phase(Phase.FIGHTING)
		Phase.ROUND_BREAK:
			_tick_fighters(false)
			if phase_frame >= rest_frames:
				_start_round(round + 1)
		Phase.OVER:
			_tick_fighters(false)

## Skip the rest period (player pressed Enter).
func skip_break() -> void:
	if phase == Phase.ROUND_BREAK:
		_start_round(round + 1)

func in_clinch() -> bool:
	return clinch != null and clinch.active

func elapsed_seconds() -> int:
	return (round_frames - clock) / FPS

## How long a fighter stays down. Depends on how hurt the knocked-down zone is
## and how many times they've already been dropped this round. >= COUNT_OUT means KO.
static func count_to_rise(zone_ratio: float, knockdowns_this_round: int, r: RandomNumberGenerator) -> int:
	if zone_ratio <= 0.0:
		return COUNT_OUT + 1
	var c := 3 + int((1.0 - zone_ratio) * 8.0) + (knockdowns_this_round - 1) * 2 + r.randi_range(-1, 1)
	return maxi(1, c)

static func doctor_stoppage_chance(cut: float) -> float:
	return clampf((cut - 1.75) / 2.5, 0.0, 1.0)

func _tick_fighters(enabled: bool) -> void:
	for f in fighters:
		f.controls_enabled = enabled
	for f in fighters:
		f.tick()

func _set_phase(p: Phase) -> void:
	phase = p
	phase_frame = 0
	if p != Phase.FIGHTING:
		if in_clinch():
			clinch.end(&"halt")
		for f in fighters:
			f.halt()  # no strike lands while the referee has stopped the action
	phase_changed.emit(p)

func _start_round(n: int) -> void:
	round = n
	clock = round_frames
	stats.append([Judges.RoundStats.new(), Judges.RoundStats.new()])
	for i in fighters.size():
		fighters[i].reset_for_round(start_positions[i])
		fighters[i].body.knockdowns_round = 0
	_set_phase(Phase.INTRO)

func _end_round() -> void:
	var s: Array = stats[round - 1]
	judges.score_round(s[0], s[1])
	if round >= rounds:
		var d := judges.decision()
		_finish(d.method, fighters[d.winner] if d.winner >= 0 else null)
		return
	for f in fighters:
		f.body.between_rounds()
		f.stam.between_rounds()
	_set_phase(Phase.ROUND_BREAK)

func _begin_knockdown() -> void:
	var f := _pending_kd
	_pending_kd = null
	if f.body.knockdowns_round >= KD_TKO:
		f.set_ko()
		_finish("TKO", other(f))
		return
	downed = f
	count = 0
	rise_at = count_to_rise(f.body.ratio(f.last_knockdown_zone), f.body.knockdowns_round, rng)
	f.stays_down = rise_at >= COUNT_OUT  # known now; lets the model fall flat instead of kneeling
	_set_phase(Phase.KNOCKDOWN)

func _begin_doctor() -> void:
	doctor_for = _pending_doctor
	_pending_doctor = null
	_set_phase(Phase.DOCTOR)

func _finish(method: String, winner: Fighter) -> void:
	result = {
		"method": method,
		"winner": winner,
		"winner_index": fighters.find(winner) if winner else -1,
		"round": round,
		"time": elapsed_seconds(),
		"cards": judges.cards,
		"totals": judges.totals(),
	}
	_set_phase(Phase.OVER)
	fight_ended.emit(result)

func _event(text: String) -> void:
	event_text = text
	event_frames = 60

func _on_clinch_requested(att: Fighter) -> void:
	if phase != Phase.FIGHTING or in_clinch() or other(att).is_down():
		return
	clinch = Clinch.new(att, other(att), rng)
	clinch.swept.connect(_on_swept)
	clinch.escape_failed.connect(func(_f): _event("HELD!"))
	clinch.ended.connect(_on_clinch_ended)

func _on_swept(att: Fighter, _def: Fighter) -> void:
	stats[round - 1][fighters.find(att)].sweeps += 1
	_event("SWEEP!")

func _on_clinch_ended(reason: StringName) -> void:
	if reason == &"break":
		_event("BREAK!")
	elif reason == &"escape":
		_event("ESCAPED")

func _record_clinch_control() -> void:
	for i in 2:
		if clinch.position_of(i) == Clinch.Pos.DOMINANT:
			stats[round - 1][fighters.find(clinch.fighters[i])].control_frames += 1

func _on_attack_started(att: Fighter, _m: MoveData) -> void:
	if phase == Phase.FIGHTING:
		stats[round - 1][fighters.find(att)].thrown += 1

func _on_resolved(att: Fighter, def: Fighter, m: MoveData, res: Dictionary) -> void:
	if phase != Phase.FIGHTING:
		return
	stats[round - 1][fighters.find(att)].record(m, res)
	if res.outcome == CombatResolver.Outcome.CHECKED:
		stats[round - 1][fighters.find(def)].checks += 1
		_event("CHECKED!")
	elif res.outcome == CombatResolver.Outcome.SLIPPED:
		_event("SLIPPED")
	if res.knockdown:
		stats[round - 1][fighters.find(att)].knockdowns_scored += 1
		def.body.knockdowns_round += 1
		def.body.knockdowns_total += 1
		_pending_kd = def
	if res.cut_delta > 0.0 and def.body.needs_doctor_check():
		_pending_doctor = def
