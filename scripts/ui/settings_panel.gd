class_name SettingsPanel
extends PanelContainer
## Audio / feel / video settings. Edits the Settings autoload live and saves on close.

signal closed

var _controller: PadRebindPanel

func _ready() -> void:
	add_theme_stylebox_override("panel", MenuKit.panel().get_theme_stylebox("panel"))
	custom_minimum_size.x = 520
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	v.add_child(MenuKit.label("SETTINGS", 32, MenuKit.GOLD))
	v.add_child(MenuKit.row("Master volume", MenuKit.slider(Settings.master_volume, func(x):
		Settings.master_volume = x
		Settings.apply())))
	v.add_child(MenuKit.row("Crowd volume", MenuKit.slider(Settings.crowd_volume, func(x):
		Settings.crowd_volume = x
		Settings.apply())))
	v.add_child(MenuKit.row("Camera shake", MenuKit.check(Settings.camera_shake, func(on): Settings.camera_shake = on)))
	v.add_child(MenuKit.row("Hit-stop", MenuKit.check(Settings.hit_stop, func(on): Settings.hit_stop = on)))
	v.add_child(MenuKit.row("Fullscreen", MenuKit.check(Settings.fullscreen, func(on):
		Settings.fullscreen = on
		Settings.apply())))
	v.add_child(MenuKit.button("Controller layout", func(): _controller.show_panel()))
	v.add_child(MenuKit.button("Back", func():
		Settings.save()
		closed.emit()))
	_controller = PadRebindPanel.new()
	_controller.settings_page = v
	add_child(_controller)
	_controller.visible = false
