class_name PauseMenu
extends CanvasLayer
## Esc during a fight: resume / settings / restart / back to the main menu. Pauses the tree.

var _box: VBoxContainer
var _settings: SettingsPanel
var _root: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	_box.add_child(MenuKit.label("PAUSED", 48, MenuKit.GOLD))
	_box.add_child(MenuKit.button("Resume", toggle))
	_box.add_child(MenuKit.button("Settings", func(): _page(true)))
	_box.add_child(MenuKit.button("Restart fight", func():
		get_tree().paused = false
		get_tree().reload_current_scene()))
	_box.add_child(MenuKit.button("Main menu", func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))
	center.add_child(_box)
	_settings = SettingsPanel.new()
	_settings.closed.connect(func(): _page(false))
	center.add_child(_settings)
	add_child(_root)
	_root.visible = false

func toggle() -> void:
	var on := not get_tree().paused
	get_tree().paused = on
	_root.visible = on
	if on:
		_page(false)

func _page(settings: bool) -> void:
	_box.visible = not settings
	_settings.visible = settings
	for b in (_settings if settings else _box).find_children("*", "Button", true, false):
		b.grab_focus()
		break

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if get_tree().paused and _settings.visible:
			_settings.closed.emit()
		else:
			toggle()
		get_viewport().set_input_as_handled()
