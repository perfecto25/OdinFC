class_name PadLayout
extends RefCounted
## Gamepad layout: D-pad / left stick move, R = guard (tap = parry), L / R act as modifier layers on the
## four face buttons. A slot is "<layer>:<face>" with layer "-" (none), "L" or "R", and face S/E/W/N
## (bottom / right / left / top, i.e. Godot's A / B / X / Y; the same positions on SNES, Xbox and PS pads).
## Start = pause, Select/Back = camera. Slots are rebindable (Settings > Controller) and saved in Settings.

const FACE := {"S": JOY_BUTTON_A, "E": JOY_BUTTON_B, "W": JOY_BUTTON_X, "N": JOY_BUTTON_Y}
const FACE_NAMES := {"S": "Bottom", "E": "Right", "W": "Left", "N": "Top"}
const LAYER_L := JOY_BUTTON_LEFT_SHOULDER
const LAYER_R := JOY_BUTTON_RIGHT_SHOULDER
## Actions that live on face-button slots (same ids PlayerController maps to moves).
const ACTIONS := [&"jab", &"cross", &"lead_hook", &"rear_hook", &"uppercut", &"teep", &"round_kick",
		&"side_kick", &"knee", &"clinch", &"check", &"slip"]

static func default_map() -> Dictionary:
	return {
		"-:S": &"jab", "-:E": &"cross", "-:W": &"lead_hook", "-:N": &"rear_hook",
		"L:S": &"teep", "L:E": &"round_kick", "L:W": &"knee", "L:N": &"side_kick",
		"R:S": &"uppercut", "R:E": &"check", "R:W": &"slip", "R:N": &"clinch",
	}

## "-:S" -> "Bottom", "L:E" -> "L + Right".
static func slot_label(slot: String) -> String:
	var p := slot.split(":")
	var face: String = FACE_NAMES[p[1]]
	return face if p[0] == "-" else "%s + %s" % [p[0], face]

static func action_label(action: StringName) -> String:
	return String(action).replace("_", " ").capitalize()

## A map is usable when every action sits on exactly one valid slot.
static func is_valid(m: Dictionary) -> bool:
	var seen := {}
	for slot in m:
		var p: PackedStringArray = String(slot).split(":")
		if p.size() != 2 or not (p[0] in ["-", "L", "R"]) or not FACE.has(p[1]):
			return false
		seen[StringName(m[slot])] = true
	return m.size() == ACTIONS.size() and ACTIONS.all(func(a): return seen.has(a))

## Put `action` on `slot`; whatever was there swaps into the action's old slot.
static func assign(m: Dictionary, action: StringName, slot: String) -> Dictionary:
	var out := m.duplicate()
	var old := ""
	for s in out:
		if StringName(out[s]) == action:
			old = s
	if old == slot:
		return out
	var displaced = out.get(slot)
	out[slot] = action
	if old != "":
		if displaced != null:
			out[old] = displaced
		else:
			out.erase(old)
	return out

static func slot_of(m: Dictionary, action: StringName) -> String:
	for s in m:
		if StringName(m[s]) == action:
			return s
	return ""

## The slot for a face-button press given which shoulder buttons are held ("" if L and R are both held).
static func slot_for(face_key: String, l_held: bool, r_held: bool) -> String:
	if l_held and r_held:
		return ""
	return "%s:%s" % ["L" if l_held else ("R" if r_held else "-"), face_key]
