class_name PlayerController
extends Node
## Human input. Same interface as DummyController / the future AIController.
## Directions are relative to the opponent, whatever the camera shows: up = forward, down = back,
## left / right = sidestep. Double-tapping up or down lunges.

const ACTION_TO_MOVE := {
	"jab": &"jab", "cross": &"cross", "lead_hook": &"lead_hook", "rear_hook": &"rear_hook",
	"uppercut": &"uppercut", "teep": &"teep", "side_kick": &"side_kick", "knee": &"knee",
	"clinch": &"clinch", "check": &"check", "slip": &"slip", "round_kick_high": &"round_kick_high",
}
const DOUBLE_TAP_MOVES := {"move_up": &"superman_punch", "move_down": &"dash_back"}
const DOUBLE_TAP_FRAMES := 15  ## the second press must come within a quarter of a second

var pad_layout: Dictionary = PadLayout.default_map()  ## slot -> action id (FightManager sets it from Settings)
var me: Fighter  ## the fighter this controller drives (null: directions are taken as world axes)
var _pad_prev := {}  ## "device:button" -> was down last poll
var _frame := 0
var _last_tap := {}  ## movement action -> frame of its last single press

## World-space direction (x, z), like every controller returns.
func get_move() -> Vector2:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return facing_relative(input, me.global_basis) if me else input

## Stick input (x = right, -y = forward) turned into world space for a fighter facing -Z of `basis`.
static func facing_relative(input: Vector2, basis: Basis) -> Vector2:
	var world := basis * Vector3(input.x, 0, input.y)
	return Vector2(world.x, world.z)

## Record a press of a movement action; returns the lunge move if it completes a double tap, else &"".
func register_tap(action: String, frame: int) -> StringName:
	if frame - int(_last_tap.get(action, -1000)) <= DOUBLE_TAP_FRAMES:
		_last_tap.clear()
		return DOUBLE_TAP_MOVES[action]
	_last_tap = {action: frame}  # a press in another direction breaks the double tap
	return &""

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
	_frame += 1
	var lunge := &""
	for a: String in DOUBLE_TAP_MOVES:
		if Input.is_action_just_pressed(a):
			lunge = register_tap(a, _frame)
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
	return lunge
