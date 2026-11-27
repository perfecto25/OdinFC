class_name Stamina
extends RefCounted
## Spent by strikes and blocking, recovers when not attacking. Body damage slows recovery.
## Below FATIGUE_START the fighter gets slower (frame_scale), weaker and leaks damage through the guard.

const MAX := 100.0
const REGEN_IDLE := 0.2       ## per frame (12/s) while idle or moving
const REGEN_GUARD := 0.06     ## per frame while guarding
const FATIGUE_START := 40.0
const MAX_SLOWDOWN := 0.4     ## startup/recovery frames x1.4 at zero stamina
const ROUND_RECOVERY := 0.7   ## fraction of missing stamina restored between rounds

var value := MAX
var regen_mult := 1.0  ## cardio (FighterData.regen_factor())

func ratio() -> float:
	return value / MAX

## 0 = fresh, 1 = empty tank.
func fatigue() -> float:
	return clampf((FATIGUE_START - value) / FATIGUE_START, 0.0, 1.0)

func frame_scale() -> float:
	return 1.0 + MAX_SLOWDOWN * fatigue()

func spend(amount: float) -> void:
	value = maxf(0.0, value - amount)

func regen(rate: float, body_ratio: float) -> void:
	value = minf(MAX, value + rate * regen_mult * (0.4 + 0.6 * body_ratio))

func between_rounds() -> void:
	value += (MAX - value) * ROUND_RECOVERY
