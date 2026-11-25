class_name PlayerController
extends Node
## Human input. Same interface as DummyController / the future AIController.

const ACTION_TO_MOVE := {
	"jab": &"jab", "cross": &"cross", "lead_hook": &"lead_hook", "rear_hook": &"rear_hook",
	"uppercut": &"uppercut", "teep": &"teep", "side_kick": &"side_kick", "knee": &"knee",
	"clinch": &"clinch", "check": &"check", "slip": &"slip",
}

func get_move() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func is_guard_held() -> bool:
	return Input.is_action_pressed("guard")

## Returns a move id for an action pressed this frame, or &"".
func poll_attack() -> StringName:
	for a in ACTION_TO_MOVE:
		if Input.is_action_just_pressed(a):
			return ACTION_TO_MOVE[a]
	if Input.is_action_just_pressed("round_kick"):
		if Input.is_action_pressed("move_up"):
			return &"round_kick_high"
		if Input.is_action_pressed("move_down"):
			return &"round_kick_low"
		return &"round_kick_body"
	return &""
