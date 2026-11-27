class_name PadRebindPanel
extends VBoxContainer
## Gamepad layout editor. Pick an action, then press the face button you want it on; hold L or R while
## pressing to put it on that layer. Whatever was there swaps into the action's old slot.

var settings_page: Control  ## the page this one replaces while open
var _rows := {}              ## action -> value Label
var _hint: Label
var _waiting := &""

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(MenuKit.label("CONTROLLER", 32, MenuKit.GOLD))
	_hint = MenuKit.label("", 18, MenuKit.DIM)
	add_child(_hint)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)
	for a in PadLayout.ACTIONS:
		var b := Button.new()
		b.text = PadLayout.action_label(a)
		b.custom_minimum_size = Vector2(230, 32)
		b.pressed.connect(_start.bind(a))
		grid.add_child(b)
		var l := MenuKit.label("", 20)
		_rows[a] = l
		grid.add_child(l)
	add_child(MenuKit.label("Move: D-pad / left stick | Guard: R (tap = parry) | Pause: Start | Camera: Select", 16, MenuKit.DIM))
	add_child(MenuKit.button("Reset to default", func():
		Settings.pad_layout = PadLayout.default_map()
		_refresh()))
	add_child(MenuKit.button("Back", hide_panel))
	_refresh()

func show_panel() -> void:
	settings_page.visible = false
	visible = true
	_waiting = &""
	_refresh()

func hide_panel() -> void:
	_waiting = &""
	Settings.save()
	visible = false
	settings_page.visible = true

func _start(action: StringName) -> void:
	_waiting = action
	_hint.text = "Press a face button for %s (hold L or R first for that layer)..." % PadLayout.action_label(action)

func _refresh() -> void:
	for a in _rows:
		_rows[a].text = PadLayout.slot_label(PadLayout.slot_of(Settings.pad_layout, a))
	_hint.text = "Pick an action, then press its new button on the pad." if _waiting == &"" else _hint.text

func _input(event: InputEvent) -> void:
	if _waiting == &"" or not visible:
		return
	if event is InputEventJoypadButton and event.pressed:
		for face in PadLayout.FACE:
			if PadLayout.FACE[face] == event.button_index:
				var slot := PadLayout.slot_for(face, Input.is_joy_button_pressed(event.device, PadLayout.LAYER_L),
						Input.is_joy_button_pressed(event.device, PadLayout.LAYER_R))
				if slot != "":
					Settings.pad_layout = PadLayout.assign(Settings.pad_layout, _waiting, slot)
					_waiting = &""
					_hint.text = "Saved. Pick another action, or go Back."
					_refresh()
					get_viewport().set_input_as_handled()
				return
