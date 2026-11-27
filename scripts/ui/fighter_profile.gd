class_name FighterProfile
extends PanelContainer
## Pre-fight page for one fighter: a live portrait of their model beside their statistics. Values come from
## FighterData; unknown ones (0 / empty) are left out.

signal confirmed
signal closed

const PORTRAIT := Vector2i(300, 440)

var _model: FighterModel

func _init() -> void:
	add_theme_stylebox_override("panel", MenuKit.panel().get_theme_stylebox("panel"))
	custom_minimum_size.x = 820

func show_fighter(d: FighterData, corner: Color) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	add_child(columns)
	columns.add_child(_portrait(d, corner))

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	columns.add_child(v)
	v.add_child(MenuKit.label("FIGHTER PROFILE", 18, MenuKit.GOLD))
	v.add_child(MenuKit.label(d.full_name if d.full_name != "" else d.display_name, 36))
	if d.nickname != "":
		v.add_child(MenuKit.label("\"%s\"" % d.nickname, 20, MenuKit.DIM))
	v.add_child(HSeparator.new())
	_stat(v, "Age", str(d.age) if d.age > 0 else "")
	_stat(v, "Weight", "%.1f lbs" % d.weight_lbs())
	_stat(v, "Height", d.height_ft_in())
	_stat(v, "Reach", "%.1f\"" % (d.reach_cm / 2.54) if d.reach_cm > 0.0 else "")
	_stat(v, "Class", d.weight_class)
	_stat(v, "Fighting out of", d.fighting_out_of)
	_stat(v, "Gym", d.gym)
	_stat(v, "Record", d.record)
	if d.bio != "":
		v.add_child(HSeparator.new())
		var bio := MenuKit.label(d.bio, 16, MenuKit.DIM)
		bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(bio)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap)
	v.add_child(MenuKit.button("Fight", func(): confirmed.emit()))
	v.add_child(MenuKit.button("Back", func(): closed.emit()))

func _stat(parent: Control, name: String, value: String) -> void:
	if value != "":
		parent.add_child(MenuKit.row(name, MenuKit.label(value, 22)))

## The fighter's in-game model in its stance, rendered in a little world of its own.
func _portrait(d: FighterData, corner: Color) -> Control:
	var box := SubViewportContainer.new()
	var view := SubViewport.new()
	view.size = PORTRAIT
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_4X
	box.add_child(view)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.3, 0.32, 0.4)
	env.environment.ssao_enabled = true
	env.environment.ssao_radius = 0.18
	env.environment.ssao_intensity = 3.0
	view.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, 12, 0)  # near frontal: the guard must not shade the chest
	key.light_energy = 1.1
	key.shadow_enabled = true
	key.shadow_opacity = 0.45
	key.shadow_blur = 2.5
	key.shadow_normal_bias = 2.5
	key.directional_shadow_max_distance = 8.0
	view.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 215, 0)
	rim.light_energy = 0.8
	rim.light_color = Color(0.7, 0.8, 1.0)
	view.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 0.92, 3.8)
	view.add_child(cam)

	_model = FighterModel.new()
	view.add_child(_model)
	_model.setup(corner)
	_model.apply_look(d)
	_model.scale = Vector3.ONE * d.model_scale()
	_model.rotation.y = PI + 0.35  # fighters face -Z: turn to the camera, countering the bladed stance
	return box

func _process(delta: float) -> void:
	if _model and is_visible_in_tree():
		_model.idle_tick(delta)
