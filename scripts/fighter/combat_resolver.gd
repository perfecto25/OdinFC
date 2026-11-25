class_name CombatResolver
## Pure hit resolution: no scene dependency, randomness only from the passed RNG (deterministic + testable).

enum Outcome { HIT, BLOCK, PARRY, CHECKED, SLIPPED }

const PARRY_WINDOW := 8           ## frames after guard press during which a parry is possible
const PARRY_STAGGER := 40         ## frames the attacker is staggered after being parried
const BLOCK_DAMAGE_FACTOR := 0.1  ## fraction of damage through a fresh guard
const BLOCK_FATIGUE_LEAK := 0.2   ## extra fraction through a fully fatigued guard
const BLOCK_STAMINA_FACTOR := 0.5
## A knee blocked by framing arms in the clinch still drives into the upper body: this fraction of the
## clean-hit damage goes to the BODY zone (fresh .. fully fatigued), whatever zone the knee aimed at.
const FRAMED_KNEE_DAMAGE := 0.12
const FRAMED_KNEE_FATIGUE_LEAK := 0.08
## A move's `damage` is its IMPACT (how hard it lands, ~3 jab .. 12 high kick).
## Zone HP loss = impact * DAMAGE_SCALE, so damage accumulates over a fight;
## knockdowns and cuts are driven by impact, so one heavy clean shot matters more than many light ones.
const DAMAGE_SCALE := 0.15
## Knockdown chance = impact^2 * (1 - zone_ratio_after)^2 * KD_FACTOR[zone]  (x1.5 on a counter).
## e.g. head at 50%: jab ~0.6%, cross ~2.5%, rear hook ~5.5%, high kick ~10%.
const KD_FACTOR := {MoveData.Zone.HEAD: 0.0028, MoveData.Zone.BODY: 0.0011, MoveData.Zone.LEGS: 0.001}
const KD_MAX_CHANCE := 0.6
const KD_COUNTER_MULT := 1.25
const CHECK_DEFENDER_FACTOR := 0.15  ## fraction of a checked kick's damage the checker's shin takes
const CHECK_REFLECT := 0.8           ## fraction the kicker's own leg takes
const CHECK_STAGGER := 24            ## frames the kicker is off balance after being checked
const CUT_MIN_IMPACT := 8.0       ## only heavy head shots open cuts (elbows later)
const CUT_CHANCE := 0.005         ## x (2 - head ratio): rarer from punches/kicks than from elbows
const CUT_GROWTH := 0.03          ## cut severity added per point of head HP lost once open

## What the resolver needs to know about one fighter at the moment of impact.
class Snapshot:
	var guarding := false
	var framing := false    ## guarding with forearms inside the clinch
	var guard_frames := 0
	var checking := false   ## shin raised (check active frames)
	var slipping := false   ## head off the centre line (slip active frames)
	var counter_ready := false  ## just slipped a punch: this strike counts as a counter
	var mid_attack := false
	var stamina_ratio := 1.0
	var fatigue := 0.0
	var leg_ratio := 1.0
	var zone_hp := {MoveData.Zone.HEAD: 100.0, MoveData.Zone.BODY: 100.0, MoveData.Zone.LEGS: 100.0}
	var cut := 0.0

static func _result(outcome: Outcome) -> Dictionary:
	return {"outcome": outcome, "damage": 0.0, "stamina_loss": 0.0, "stun": 0,
			"attacker_stagger": 0, "attacker_damage": 0.0, "counter": false, "knockdown": false, "cut_delta": 0.0,
			"zone": -1}  ## zone: where the damage lands when it isn't the move's own zone (-1 = move's zone)

## Low stamina weakens everything; damaged legs weaken kicks and knees.
static func strength(move: MoveData, att: Snapshot) -> float:
	var s := 0.6 + 0.4 * clampf(att.stamina_ratio, 0.0, 1.0)
	if move.strike_type != MoveData.StrikeType.PUNCH:
		s *= 0.6 + 0.4 * clampf(att.leg_ratio, 0.0, 1.0)
	return s

## Guard covers head and body only. A raised shin (check) stops leg kicks and hurts the kicker,
## and blocks body kicks/knees/teeps like a guard; punches still get through.
static func resolve(move: MoveData, att: Snapshot, def: Snapshot, rng: RandomNumberGenerator) -> Dictionary:
	var s := strength(move, att)
	if def.slipping and move.zone == MoveData.Zone.HEAD and move.strike_type == MoveData.StrikeType.PUNCH \
			and move.slippable:
		return _result(Outcome.SLIPPED)  # whiff: the attacker just recovers, the defender gets a counter window
	var shin_in_way := def.checking and move.strike_type != MoveData.StrikeType.PUNCH
	if shin_in_way and move.zone == MoveData.Zone.LEGS:
		var c := _result(Outcome.CHECKED)
		var impact := move.damage * s
		c.damage = impact * DAMAGE_SCALE * CHECK_DEFENDER_FACTOR
		c.attacker_damage = impact * DAMAGE_SCALE * CHECK_REFLECT
		c.attacker_stagger = CHECK_STAGGER
		return c
	var guards := (def.guarding and move.zone != MoveData.Zone.LEGS) or (shin_in_way and move.zone == MoveData.Zone.BODY)
	if guards and def.guarding and move.parryable and def.guard_frames <= PARRY_WINDOW:
		var p := _result(Outcome.PARRY)
		p.attacker_stagger = PARRY_STAGGER
		return p
	if guards:
		var b := _result(Outcome.BLOCK)
		var gb := 1.0 + move.guard_break
		b.damage = move.damage * s * DAMAGE_SCALE * (BLOCK_DAMAGE_FACTOR + BLOCK_FATIGUE_LEAK * def.fatigue) * gb
		b.stamina_loss = move.damage * s * BLOCK_STAMINA_FACTOR * gb * (1.0 + 0.5 * def.fatigue)
		b.stun = move.block_stun
		if def.framing and move.strike_type == MoveData.StrikeType.KNEE:
			b.damage = move.damage * s * DAMAGE_SCALE * (FRAMED_KNEE_DAMAGE + FRAMED_KNEE_FATIGUE_LEAK * def.fatigue)
			b.zone = MoveData.Zone.BODY
		return b
	var h := _result(Outcome.HIT)
	h.counter = def.mid_attack or att.counter_ready
	var impact := move.damage * s * ((1.0 + move.counter_bonus) if h.counter else 1.0)
	var dmg := impact * DAMAGE_SCALE
	h.damage = dmg
	h.stun = move.hit_stun
	var hp_after: float = def.zone_hp[move.zone] - dmg
	var ratio_after := clampf(hp_after / BodyDamage.MAX_HP, 0.0, 1.0)
	if hp_after <= 0.0:
		h.knockdown = true
	else:
		var chance: float = impact * impact * pow(1.0 - ratio_after, 2.0) * KD_FACTOR[move.zone]
		if h.counter:
			chance *= KD_COUNTER_MULT
		h.knockdown = rng.randf() < minf(chance, KD_MAX_CHANCE)
	if move.zone == MoveData.Zone.HEAD:
		if def.cut > 0.0:
			h.cut_delta = dmg * CUT_GROWTH
		elif impact >= CUT_MIN_IMPACT and rng.randf() < CUT_CHANCE * (2.0 - ratio_after):
			h.cut_delta = 1.0
	return h
