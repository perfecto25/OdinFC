class_name InputSetup
## Registers named InputMap actions (keyboard now; gamepad bindings added in milestone 8a).

const KEYS := {
	"move_left": KEY_A, "move_right": KEY_D, "move_up": KEY_W, "move_down": KEY_S,
	"jab": KEY_J, "cross": KEY_K, "lead_hook": KEY_U, "rear_hook": KEY_I,
	"uppercut": KEY_O, "teep": KEY_L, "side_kick": KEY_SEMICOLON,
	"round_kick": KEY_H, "knee": KEY_N, "guard": KEY_SPACE,
	"camera_toggle": KEY_TAB, "dummy_cycle": KEY_F1,
	"skip": KEY_ENTER, "clinch": KEY_C, "check": KEY_E, "slip": KEY_Q, "debug_end_round": KEY_F2,
	"arena_cycle": KEY_F3, "help_toggle": KEY_F4, "debug_labels": KEY_F5, "pause": KEY_ESCAPE,
}
## Gamepad bindings: movement (D-pad + left stick), pause, camera. Strikes/guard are face-button slots
## handled by PlayerController via PadLayout.
const PAD_BUTTONS := {
	"move_up": [JOY_BUTTON_DPAD_UP], "move_down": [JOY_BUTTON_DPAD_DOWN],
	"move_left": [JOY_BUTTON_DPAD_LEFT], "move_right": [JOY_BUTTON_DPAD_RIGHT],
	"pause": [JOY_BUTTON_START], "camera_toggle": [JOY_BUTTON_BACK, JOY_BUTTON_TOUCHPAD],
}
## Raw D-pads that report as axes (many cheap pads) are covered by the left stick bindings, which use
## the same axes (0 = X, 1 = Y).
const PAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0],
}

static func register() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = KEYS[action]
			InputMap.action_add_event(action, ev)
	# Menus: make sure the pad's bottom/right face buttons accept/cancel (built-in defaults don't always apply).
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		if InputMap.has_action(pair[0]) and not _has_pad_event(pair[0], pair[1], -1):
			var ub := InputEventJoypadButton.new()
			ub.button_index = pair[1]
			InputMap.action_add_event(pair[0], ub)
	for action in PAD_BUTTONS:
		for btn in PAD_BUTTONS[action]:
			if not _has_pad_event(action, btn, -1):
				var jb := InputEventJoypadButton.new()
				jb.button_index = btn
				InputMap.action_add_event(action, jb)
	for action in PAD_AXES:
		var axis: int = PAD_AXES[action][0]
		var dir: float = PAD_AXES[action][1]
		if not _has_pad_event(action, -1, axis, dir):
			var jm := InputEventJoypadMotion.new()
			jm.axis = axis
			jm.axis_value = dir
			InputMap.action_add_event(action, jm)

static func _has_pad_event(action: String, button: int, axis: int, dir := 0.0) -> bool:
	for e in InputMap.action_get_events(action):
		if button >= 0 and e is InputEventJoypadButton and e.button_index == button:
			return true
		if axis >= 0 and e is InputEventJoypadMotion and e.axis == axis and signf(e.axis_value) == dir:
			return true
	return false
