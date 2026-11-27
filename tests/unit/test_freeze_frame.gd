extends GutTest

var ff: FreezeFrame

func before_each() -> void:
	InputSetup.register()
	ff = FreezeFrame.new()
	add_child_autofree(ff)

func after_each() -> void:
	if ff.frozen:
		ff.release()

func _key(code: Key, down: bool, echo := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	e.echo = echo
	return e

func _button(b: JoyButton, down: bool) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = down
	return e

func _axis(value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_Y
	e.axis_value = value
	return e

## Feed events while the tree is paused, then resume before GUT needs to run again.
func _frozen_after(events: Array) -> bool:
	ff.handle(_key(KEY_BACKSPACE, true))
	for e in events:
		ff.handle(e)
	var still := ff.frozen
	if still:
		ff.release()
	return still

func test_backspace_freezes() -> void:
	ff.handle(_key(KEY_BACKSPACE, true))
	var state := [ff.frozen, get_tree().paused, Engine.time_scale]
	ff.release()
	assert_eq(state, [true, true, 0.0])
	assert_eq([get_tree().paused, Engine.time_scale], [false, 1.0])

func test_clicks_resume_on_release() -> void:
	assert_true(_frozen_after([_key(KEY_J, true)]), "held key: still frozen")
	assert_false(_frozen_after([_key(KEY_J, true), _key(KEY_J, false)]))
	assert_false(_frozen_after([_button(JOY_BUTTON_A, true), _button(JOY_BUTTON_A, false)]))
	assert_false(_frozen_after([_axis(-1.0), _axis(0.0)]), "axis D-pad")

func test_things_that_do_not_resume() -> void:
	assert_true(_frozen_after([_key(KEY_BACKSPACE, false), _key(KEY_BACKSPACE, true), _key(KEY_BACKSPACE, false)]))
	assert_true(_frozen_after([_key(KEY_W, false)]), "releasing a key held since before the freeze")
	assert_true(_frozen_after([_key(KEY_J, true, true)]), "key repeat")
	assert_true(_frozen_after([_key(KEY_PRINT, true), _key(KEY_PRINT, false)]))
	assert_true(_frozen_after([_key(KEY_SHIFT, true), _key(KEY_SHIFT, false)]))
	assert_true(_frozen_after([_axis(0.2), _axis(0.0)]), "stick drift")

func test_no_freeze_over_the_pause_menu() -> void:
	get_tree().paused = true
	ff.handle(_key(KEY_BACKSPACE, true))
	var was_frozen := ff.frozen
	get_tree().paused = false
	assert_false(was_frozen)
