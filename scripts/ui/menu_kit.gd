class_name MenuKit
extends RefCounted
## Small UI builders shared by the main menu, settings panel and pause menu (everything is built in code,
## matching the HUD's navy/gold look).

const NAVY := Color(0.04, 0.05, 0.09, 0.94)
const GOLD := Color(0.95, 0.72, 0.2)
const DIM := Color(0.65, 0.68, 0.75)

static func label(text: String, size := 22, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func _box(bg: Color, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(4)
	s.set_content_margin_all(10)
	s.border_color = border
	s.set_border_width_all(2 if border.a > 0.0 else 0)
	return s

static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 46)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_stylebox_override("normal", _box(Color(0.1, 0.12, 0.2), Color(1, 1, 1, 0.12)))
	b.add_theme_stylebox_override("hover", _box(Color(0.16, 0.18, 0.3), GOLD))
	b.add_theme_stylebox_override("focus", _box(Color(0.16, 0.18, 0.3), GOLD))
	b.add_theme_stylebox_override("pressed", _box(GOLD))
	b.add_theme_color_override("font_pressed_color", Color.BLACK)
	b.pressed.connect(cb)
	return b

static func panel(content_width := 520.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(NAVY, Color(1, 1, 1, 0.1)))
	p.custom_minimum_size.x = content_width
	return p

## "Name ........ [control]" row.
static func row(name: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := label(name, 20, DIM)
	l.custom_minimum_size.x = 190
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h

static func option(items: Array, selected: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", 20)
	for i in items.size():
		o.add_item(str(items[i]), i)
	o.selected = selected
	o.item_selected.connect(cb)
	return o

static func slider(value: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size.y = 28
	s.value_changed.connect(cb)
	return s

static func check(value: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = value
	c.toggled.connect(cb)
	return c
