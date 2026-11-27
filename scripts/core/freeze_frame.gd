class_name FreezeFrame
extends Node
## Backspace during a fight holds the picture still for a screenshot: no overlay, nothing moves.
## The next click (press and release) of any other key or any pad button / D-pad direction resumes.
## That click is swallowed, and the game resumes on its release, so it never becomes a strike or a menu.

## Keys that belong to taking the screenshot (Print, Shift+Print, Super+Shift+S...): these don't resume.
const IGNORED_KEYS: Array[Key] = [KEY_BACKSPACE, KEY_PRINT, KEY_SYSREQ, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]
const AXIS_PRESS := 0.5  ## a stick or axis D-pad counts as clicked past this, released below it

var frozen := false
var _down := {}  ## inputs pressed since the freeze; only their release resumes (not that of a key already held)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _exit_tree() -> void:
	if frozen:
		release()

func _input(event: InputEvent) -> void:
	if handle(event):
		get_viewport().set_input_as_handled()

## Returns true if the event was used up here.
func handle(event: InputEvent) -> bool:
	if not frozen:
		# Not from the pause menu: the tree is already stopped there.
		if event.is_action_pressed("freeze_frame") and not get_tree().paused:
			freeze()
			return true
		return false
	var id := ""
	var down := false
	if event is InputEventKey:
		if event.echo or event.physical_keycode in IGNORED_KEYS or event.keycode in IGNORED_KEYS:
			return true
		id = "key %d %d" % [event.physical_keycode, event.keycode]
		down = event.pressed
	elif event is InputEventJoypadButton:
		id = "button %d %d" % [event.device, event.button_index]
		down = event.pressed
	elif event is InputEventJoypadMotion:
		id = "axis %d %d" % [event.device, event.axis]
		down = absf(event.axis_value) > AXIS_PRESS
	else:
		return false
	if down:
		_down[id] = true
	elif _down.has(id):
		release()
	return true

func freeze() -> void:
	frozen = true
	_down.clear()
	get_tree().paused = true
	Engine.time_scale = 0.0  # also stops shader time (the crowd)

func release() -> void:
	frozen = false
	_down.clear()
	Engine.time_scale = 1.0
	get_tree().paused = false
