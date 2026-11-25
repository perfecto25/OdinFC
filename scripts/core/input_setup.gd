class_name InputSetup
## Registers named InputMap actions (keyboard now; gamepad bindings added in milestone 8a).

const KEYS := {
	"move_left": KEY_A, "move_right": KEY_D, "move_up": KEY_W, "move_down": KEY_S,
	"jab": KEY_J, "cross": KEY_K, "lead_hook": KEY_U, "rear_hook": KEY_I,
	"uppercut": KEY_O, "teep": KEY_L, "side_kick": KEY_SEMICOLON,
	"round_kick": KEY_H, "knee": KEY_N, "guard": KEY_SPACE,
	"camera_toggle": KEY_TAB, "dummy_cycle": KEY_F1,
	"skip": KEY_ENTER, "clinch": KEY_C, "check": KEY_E, "slip": KEY_Q, "debug_end_round": KEY_F2,
	"arena_cycle": KEY_F3, "help_toggle": KEY_F4, "debug_labels": KEY_F5,
}
## Gamepad buttons already wired (the full pad layout + rebind menu is milestone 8a).
const PAD := {"camera_toggle": JOY_BUTTON_TOUCHPAD}

static func register() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = KEYS[action]
			InputMap.action_add_event(action, ev)
	for action in PAD:
		var has := false
		for e in InputMap.action_get_events(action):
			has = has or e is InputEventJoypadButton
		if not has:
			var jb := InputEventJoypadButton.new()
			jb.button_index = PAD[action]
			InputMap.action_add_event(action, jb)
