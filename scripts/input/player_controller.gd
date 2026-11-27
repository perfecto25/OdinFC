class_name PlayerController
extends Node
## Human input. Same interface as DummyController / the future AIController.

const ACTION_TO_MOVE := {
	"jab": &"jab", "cross": &"cross", "lead_hook": &"lead_hook", "rear_hook": &"rear_hook",
	"uppercut": &"uppercut", "teep": &"teep", "side_kick": &"side_kick", "knee": &"knee",
	"clinch": &"clinch", "check": &"check", "slip": &"slip",
}

var pad_layout: Dictionary = PadLayout.default_map()  ## slot -> action id (FightManager sets it from Settings)
var _pad_prev := {}  ## "device:button" -> was down last poll

func get_move() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func is_guard_held() -> bool:
	if Input.is_action_pressed("guard"):
		return true
	for d in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(d, PadLayout.LAYER_R):
			return true
	return false

## Face-button press edge on any pad -> the action in that slot (given the held L/R layer), or &"".
func _poll_pad() -> StringName:
	var found := &""
	for d in Input.get_connected_joypads():
		var l := Input.is_joy_button_pressed(d, PadLayout.LAYER_L)
		var r := Input.is_joy_button_pressed(d, PadLayout.LAYER_R)
		for face in PadLayout.FACE:
			var b: int = PadLayout.FACE[face]
			var key := "%d:%d" % [d, b]
			var down := Input.is_joy_button_pressed(d, b)
			if down and not _pad_prev.get(key, false) and found == &"":
				found = StringName(pad_layout.get(PadLayout.slot_for(face, l, r), &""))
			_pad_prev[key] = down
	return found

## Returns a move id for an action pressed this frame, or &"".
func poll_attack() -> StringName:
	var pad := _poll_pad()  # always polled so the edge state stays current
	for a in ACTION_TO_MOVE:
		if Input.is_action_just_pressed(a):
			return ACTION_TO_MOVE[a]
	var round_kick := Input.is_action_just_pressed("round_kick") or pad == &"round_kick"
	if pad != &"" and pad != &"round_kick" and ACTION_TO_MOVE.has(pad):
		return ACTION_TO_MOVE[pad]
	if round_kick:
		if Input.is_action_pressed("move_up"):
			return &"round_kick_high"
		if Input.is_action_pressed("move_down"):
			return &"round_kick_low"
		return &"round_kick_body"
	return &""
