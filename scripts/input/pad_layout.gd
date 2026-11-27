class_name PadLayout
extends RefCounted
## Gamepad layout: D-pad / left stick move, R = guard (tap = parry), L / R act as modifier layers on the
## four face buttons. A slot is "<layer>:<face>" with layer "-" (none), "L", "R" or "LR" (both), and face
## S/E/W/N (bottom / right / left / top: positions, the same on every pad). What the player sees is the
## name printed on their pad's button (button_names): on an SNES pad the bottom one is "B".
## Start = pause, Select/Back = camera. Slots are rebindable (Settings > Controller) and saved in Settings.

const FACE := {"S": JOY_BUTTON_A, "E": JOY_BUTTON_B, "W": JOY_BUTTON_X, "N": JOY_BUTTON_Y}
const BUTTON_NAMES := {
	"nintendo": {"S": "B", "E": "A", "W": "Y", "N": "X"},
	"playstation": {"S": "Cross", "E": "Circle", "W": "Square", "N": "Triangle"},
	"xbox": {"S": "A", "E": "B", "W": "X", "N": "Y"},
}
const LAYER_L := JOY_BUTTON_LEFT_SHOULDER
const LAYER_R := JOY_BUTTON_RIGHT_SHOULDER
## Actions that live on face-button slots (same ids PlayerController maps to moves).
const ACTIONS := [&"jab", &"cross", &"lead_hook", &"rear_hook", &"uppercut", &"teep", &"round_kick",
		&"round_kick_high", &"side_kick", &"knee", &"clinch", &"check", &"slip"]
const LABELS := {&"round_kick_high": "High Kick"}  ## where the id doesn't read well

static func default_map() -> Dictionary:
	return {
		"-:S": &"jab", "-:E": &"cross", "-:W": &"round_kick_high", "-:N": &"uppercut",
		"L:S": &"teep", "L:E": &"round_kick", "L:W": &"knee", "L:N": &"side_kick",
		"R:S": &"rear_hook", "R:E": &"check", "R:W": &"slip", "R:N": &"clinch",
		"LR:W": &"lead_hook",
	}

## Bring a layout saved before the high-kick slot up to date, keeping the player's own choices: high kick
## takes the left face button (what was there moves to L + R + that button), and the uppercut trades places
## with whatever was on the top button. Current layouts come back unchanged.
static func upgrade(m: Dictionary) -> Dictionary:
	if slot_of(m, &"round_kick_high") != "" or slot_of(m, &"uppercut") == "":
		return m
	var out := m.duplicate()
	if out.has("-:W"):
		out["LR:W"] = out["-:W"]
	out["-:W"] = &"round_kick_high"
	return assign(out, &"uppercut", "-:N")

## The names printed on a pad's face buttons, guessed from its device name.
static func button_names(pad_name: String) -> Dictionary:
	var n := pad_name.to_lower()
	for key in ["snes", "nintendo", "super famicom", "switch"]:
		if n.contains(key):
			return BUTTON_NAMES.nintendo
	for key in ["playstation", "dualshock", "dualsense", "sony", "ps3", "ps4", "ps5"]:
		if n.contains(key):
			return BUTTON_NAMES.playstation
	return BUTTON_NAMES.xbox

## Names for the first connected pad (SNES lettering, the pad this game is set up on, when there is none).
static func connected_names() -> Dictionary:
	var pads := Input.get_connected_joypads()
	return button_names(Input.get_joy_name(pads[0])) if not pads.is_empty() else BUTTON_NAMES.nintendo

## "-:S" -> "B", "L:E" -> "L + A", "LR:W" -> "L + R + Y" (SNES names).
static func slot_label(slot: String, names: Dictionary) -> String:
	var p := slot.split(":")
	if p.size() != 2:
		return "-"
	var face: String = names[p[1]]
	return face if p[0] == "-" else "%s + %s" % [" + ".join(p[0].split("")), face]

static func action_label(action: StringName) -> String:
	return LABELS.get(action, String(action).replace("_", " ").capitalize())

## One line per pair of layers for the in-fight help, e.g. "B Jab, A Cross, ... | L + B Teep, ...".
static func help(m: Dictionary, names: Dictionary) -> String:
	var lines: Array[String] = []
	for layers in [["-", "L"], ["R", "LR"]]:
		var parts: Array[String] = []
		for layer: String in layers:
			var entries: Array[String] = []
			for face: String in FACE:
				var slot := "%s:%s" % [layer, face]
				if m.has(slot):
					entries.append("%s %s" % [slot_label(slot, names), action_label(m[slot])])
			if not entries.is_empty():
				parts.append(", ".join(entries))
		lines.append(" | ".join(parts))
	return "\n".join(lines)

## A map is usable when every action sits on exactly one valid slot.
static func is_valid(m: Dictionary) -> bool:
	var seen := {}
	for slot in m:
		var p: PackedStringArray = String(slot).split(":")
		if p.size() != 2 or not (p[0] in ["-", "L", "R", "LR"]) or not FACE.has(p[1]):
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

## The slot for a face-button press given which shoulder buttons are held.
static func slot_for(face_key: String, l_held: bool, r_held: bool) -> String:
	var layer := ("L" if l_held else "") + ("R" if r_held else "")
	return "%s:%s" % [layer if layer != "" else "-", face_key]
