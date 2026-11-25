class_name BodyDamage
extends RefCounted
## Per-zone damage, cuts and knockdown tally for one fighter.
## Head -> knockdown/KO risk. Body -> slower stamina recovery. Legs -> slower movement, weaker kicks.

const MAX_HP := 100.0
const RISE_HP := 35.0            ## a zone is restored to at least this after beating the count
const ROUND_RECOVERY := {MoveData.Zone.HEAD: 0.25, MoveData.Zone.BODY: 0.15, MoveData.Zone.LEGS: 0.15}
const DOCTOR_FIRST_CHECK := 2.0  ## cut severity that triggers the first doctor check; +1.0 for each later one

var hp := {MoveData.Zone.HEAD: MAX_HP, MoveData.Zone.BODY: MAX_HP, MoveData.Zone.LEGS: MAX_HP}
var cut := 0.0                   ## 0 = none, 1 = opened, grows with further head hits
var knockdowns_round := 0
var knockdowns_total := 0
var doctor_checks := 0

func ratio(zone: MoveData.Zone) -> float:
	return hp[zone] / MAX_HP

func apply(zone: MoveData.Zone, dmg: float) -> void:
	hp[zone] = maxf(0.0, hp[zone] - dmg)

func add_cut(amount: float) -> void:
	cut += amount

## True once each time the cut crosses the next doctor-check threshold.
func needs_doctor_check() -> bool:
	if cut >= DOCTOR_FIRST_CHECK + doctor_checks:
		doctor_checks += 1
		return true
	return false

func speed_factor() -> float:
	return 0.5 + 0.5 * ratio(MoveData.Zone.LEGS)

func recover_after_knockdown(zone: MoveData.Zone) -> void:
	hp[zone] = maxf(hp[zone], RISE_HP)

func between_rounds() -> void:
	for z in hp:
		hp[z] += (MAX_HP - hp[z]) * ROUND_RECOVERY[z]
	knockdowns_round = 0
