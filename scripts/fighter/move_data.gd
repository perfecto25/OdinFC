class_name MoveData
extends Resource
## One technique. Frame counts are at 60 Hz. Specials later reuse this with an input sequence + meter cost.

enum Zone { HEAD, BODY, LEGS }
enum StrikeType { PUNCH, KICK, KNEE, TEEP }  ## elbows later
enum Action { STRIKE, CLINCH_ENTRY, DASH }

@export var id: StringName
@export var display_name := ""
@export var animation: StringName          ## AnimationTree state (art pass, milestone 6a)
@export var hit_bone: StringName = &"fist" ## BoneAttachment3D that carries the hitbox (milestone 6a)
@export var zone: Zone = Zone.HEAD
@export var strike_type: StrikeType = StrikeType.PUNCH  ## drives scoring weight + leg-damage weakening
@export var action: Action = Action.STRIKE                ## CLINCH_ENTRY ties up, DASH only moves
@export var travel := 0.0                  ## metres driven toward the opponent during startup + active (< 0 = away)
@export var startup := 6                   ## frames before the hit can connect
@export var active := 3                    ## frames the hit can connect
@export var recovery := 10                 ## frames of vulnerability afterwards
@export var damage := 5.0
@export var stamina_cost := 5.0
@export var reach := 1.4                   ## max centre-to-centre distance (m) at which it connects
@export var hit_stun := 14                 ## frames the defender is stunned on a clean hit
@export var block_stun := 8                ## frames the defender is stunned on a block
@export var guard_break := 0.0             ## extra chip/stamina drain against a guard (0 = none)
@export var counter_bonus := 0.3           ## damage multiplier bonus when hitting an attacker mid-move
@export var parryable := true              ## kicks are not
@export var slippable := true              ## head punches miss a slip (uppercuts come up through it)

func total_frames() -> int:
	return startup + active + recovery
