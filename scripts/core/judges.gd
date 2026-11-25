class_name Judges
extends RefCounted
## Three judges, 10-point-must. Muay Thai weighting: kicks/knees and damage count more than volume.
## Each judge perceives each round with a small, seeded variance.

const WEIGHT := {MoveData.StrikeType.PUNCH: 1.0, MoveData.StrikeType.KICK: 1.5,
		MoveData.StrikeType.KNEE: 1.4, MoveData.StrikeType.TEEP: 1.2}
const VOLUME_POINTS := 0.5        ## per landed strike, on top of its damage
const BLOCKED_FACTOR := 0.15      ## a blocked strike is worth this fraction of its damage
const KNOCKDOWN_POINTS := 25.0
const SWEEP_POINTS := 6.0         ## Muay Thai rewards dumping your opponent
const CHECK_POINTS := 1.0         ## credit for checking a leg kick
const CONTROL_POINTS_PER_SEC := 0.3  ## dominant clinch position
const VARIANCE := 0.1             ## +-10% per judge per fighter per round
const EVEN_MARGIN := 0.02         ## within 2% of total -> 10-10 (judges almost always pick a winner)
const DOMINANCE_RATIO := 3.0      ## 10-8 without a knockdown needs 3x the points...
const DOMINANCE_MARGIN := 30.0    ## ...and this absolute margin
const NUM_JUDGES := 3

## One fighter's offensive output in one round.
class RoundStats:
	var thrown := 0
	var landed := 0
	var blocked := 0
	var parried := 0
	var checks := 0             ## opponent's leg kicks this fighter checked
	var sweeps := 0
	var control_frames := 0     ## frames in the dominant clinch position
	var damage := 0.0
	var points := 0.0
	var knockdowns_scored := 0

	func record(move: MoveData, res: Dictionary) -> void:
		var w: float = Judges.WEIGHT[move.strike_type]
		match res.outcome:
			CombatResolver.Outcome.HIT:
				landed += 1
				damage += res.damage
				points += w * (res.damage + Judges.VOLUME_POINTS)
			CombatResolver.Outcome.BLOCK:
				blocked += 1
				points += w * move.damage * Judges.BLOCKED_FACTOR
			CombatResolver.Outcome.PARRY:
				parried += 1

	func total_points() -> float:
		return points + knockdowns_scored * Judges.KNOCKDOWN_POINTS + sweeps * Judges.SWEEP_POINTS \
			+ checks * Judges.CHECK_POINTS + control_frames / 60.0 * Judges.CONTROL_POINTS_PER_SEC

var cards: Array = []  ## cards[judge] = Array of [score_a, score_b] per round
var _rngs: Array[RandomNumberGenerator] = []

func _init(seed: int = 0) -> void:
	for j in NUM_JUDGES:
		var r := RandomNumberGenerator.new()
		r.seed = seed * 31 + j + 1
		_rngs.append(r)
		cards.append([])

## Scores one round on every card. Returns this round's [a, b] per judge.
func score_round(sa: RoundStats, sb: RoundStats) -> Array:
	var out := []
	for j in NUM_JUDGES:
		var pa := sa.total_points() * (1.0 + _rngs[j].randf_range(-VARIANCE, VARIANCE))
		var pb := sb.total_points() * (1.0 + _rngs[j].randf_range(-VARIANCE, VARIANCE))
		var s := ten_point(pa, pb, sa.knockdowns_scored, sb.knockdowns_scored)
		cards[j].append(s)
		out.append(s)
	return out

static func ten_point(pa: float, pb: float, kd_by_a: int, kd_by_b: int) -> Array:
	var margin := absf(pa - pb)
	if margin <= maxf(1.0, (pa + pb) * EVEN_MARGIN):
		return [10, 10]
	var a_wins := pa > pb
	var w_pts := maxf(pa, pb)
	var l_pts := minf(pa, pb)
	var net_kd := (kd_by_a - kd_by_b) if a_wins else (kd_by_b - kd_by_a)
	var loser := 9 - maxi(0, net_kd)
	if net_kd <= 0 and w_pts >= DOMINANCE_RATIO * l_pts and margin >= DOMINANCE_MARGIN:
		loser -= 1
	loser = maxi(7, loser)
	return [10, loser] if a_wins else [loser, 10]

## Per-judge [total_a, total_b].
func totals() -> Array:
	var out := []
	for card in cards:
		var t := [0, 0]
		for r in card:
			t[0] += r[0]
			t[1] += r[1]
		out.append(t)
	return out

## {"method": "UD"|"SD"|"MD"|"DRAW", "winner": 0|1|-1}
func decision() -> Dictionary:
	var a := 0
	var b := 0
	var d := 0
	for t in totals():
		if t[0] > t[1]:
			a += 1
		elif t[1] > t[0]:
			b += 1
		else:
			d += 1
	if a == 3 or b == 3:
		return {"method": "UD", "winner": 0 if a == 3 else 1}
	if (a == 2 and b == 1) or (b == 2 and a == 1):
		return {"method": "SD", "winner": 0 if a == 2 else 1}
	if (a == 2 or b == 2) and d == 1:
		return {"method": "MD", "winner": 0 if a == 2 else 1}
	return {"method": "DRAW", "winner": -1}
