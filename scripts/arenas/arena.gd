class_name Arena
extends Node3D
## Shared venue for both arenas: dark arena environment, broadcast lighting rig over the canvas,
## crowd placeholders on stepped tiers, and the generic "OdinFC" branding. Subclasses build the
## enclosure (ring ropes / cage fence) and set `bounds`, which the fighters use as their edge.
## Everything is built procedurally from primitives so it stays light on an iGPU.

const VENUE_FLOOR := -1.0      ## the platform is raised; the venue floor is this far below the canvas
const CROWD_INNER := 12.5      ## first crowd row, as a half-width of the seating square
const CROWD_ROWS := 6
const ROW_DEPTH := 0.9
const ROW_RISE := 0.45
const SEAT_SPACING := 0.62
const CANVAS_COLOR := Color(0.62, 0.63, 0.66)
const BRAND_DARK := Color(0.05, 0.06, 0.1)
const BRAND_GOLD := Color(0.95, 0.72, 0.2)

var bounds := ArenaBounds.ring()
var crowd: Crowd
var camera_height := 2.3  ## broadcast cam height; the cage raises it so the shot clears the fence rail

static func create(kind: String) -> Arena:
	var path := "res://scenes/arenas/cage.tscn" if kind == "cage" else "res://scenes/arenas/ring.tscn"
	return load(path).instantiate()

func _ready() -> void:
	_build_environment()
	_build_lights()
	_build_venue()
	_build_crowd()
	_build_enclosure()
	_add_logo()
	_build_banners()

## Subclass hook: platform, canvas, ropes or fence. Must also set `bounds`.
func _build_enclosure() -> void:
	pass

# --- shared pieces ---

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.012, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.22, 0.24, 0.32)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.95
	e.tonemap_white = 1.4
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.92
	# Contact shadows in the creases: under the chin, between arm and ribs, around the muscles.
	e.ssao_enabled = true
	e.ssao_radius = 0.18
	e.ssao_intensity = 3.0
	e.ssao_power = 1.4
	e.ssao_light_affect = 0.35
	e.glow_enabled = true
	e.glow_intensity = 0.3
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.3
	we.environment = e
	add_child(we)

## Broadcast rig: a shadowed key light coming in at an angle (so bodies model and cast shadows), a cooler
## rim light from the far side without shadows, and four spots from the truss corners; two diagonal spots
## also cast shadows.
func _build_lights() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 40, 0)
	key.light_energy = 1.0
	key.light_color = Color(1.0, 0.95, 0.88)
	key.shadow_enabled = true
	key.shadow_blur = 1.5
	key.shadow_normal_bias = 2.5
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	key.directional_shadow_max_distance = 22.0
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-22, 215, 0)
	rim.light_energy = 0.65
	rim.light_color = Color(0.7, 0.8, 1.0)
	add_child(rim)
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var s := SpotLight3D.new()
		s.position = Vector3(c.x * 4.5, 7.0, c.y * 4.5)
		s.light_energy = 0.95
		s.light_color = Color(1.0, 0.97, 0.92)
		s.spot_range = 14.0
		s.spot_angle = 32.0
		s.spot_attenuation = 0.6
		s.shadow_enabled = c.x == c.y
		s.shadow_blur = 2.0
		s.shadow_opacity = 0.7
		s.shadow_normal_bias = 2.0
		add_child(s)
		s.look_at(Vector3(0, 0, 0))
	# The lighting truss hanging over the canvas (it frames the wide shots).
	var t := 4.6
	for z in [-t, t]:
		_box(Vector3(t * 2, 0.25, 0.25), Vector3(0, 7.8, z), Color(0.08, 0.08, 0.09)).cast_shadow = \
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x in [-t, t]:
		_box(Vector3(0.25, 0.25, t * 2), Vector3(x, 7.8, 0), Color(0.08, 0.08, 0.09)).cast_shadow = \
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_venue() -> void:
	_box(Vector3(60, 0.2, 60), Vector3(0, VENUE_FLOOR - 0.1, 0), Color(0.04, 0.04, 0.05))
	# Stepped seating tiers, one box per side per row.
	for r in CROWD_ROWS:
		var half := CROWD_INNER + r * ROW_DEPTH
		var top := VENUE_FLOOR + r * ROW_RISE
		var h := top - VENUE_FLOOR + 0.05
		var y := VENUE_FLOOR + h * 0.5
		var c := Color(0.07, 0.07, 0.09)
		_box(Vector3(half * 2 + ROW_DEPTH * 2, h, ROW_DEPTH), Vector3(0, y, -half - ROW_DEPTH * 0.5), c)
		_box(Vector3(half * 2 + ROW_DEPTH * 2, h, ROW_DEPTH), Vector3(0, y, half + ROW_DEPTH * 0.5), c)
		_box(Vector3(ROW_DEPTH, h, half * 2), Vector3(-half - ROW_DEPTH * 0.5, y, 0), c)
		_box(Vector3(ROW_DEPTH, h, half * 2), Vector3(half + ROW_DEPTH * 0.5, y, 0), c)

## The audience: seated people on the tiers (see Crowd), facing the ring, in random shirt colours.
func _build_crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for r in CROWD_ROWS:
		var half := CROWD_INNER + r * ROW_DEPTH + ROW_DEPTH * 0.5
		var seat_y := VENUE_FLOOR + r * ROW_RISE + 0.05
		var n := int(half * 2 / SEAT_SPACING)
		for side in 4:
			for i in n:
				if rng.randf() < 0.1:
					continue  # empty seat
				var along := -half + (i + 0.5) * (half * 2 / n) + rng.randf_range(-0.08, 0.08)
				var p: Vector3
				match side:
					0: p = Vector3(along, 0, -half)
					1: p = Vector3(along, 0, half)
					2: p = Vector3(-half, 0, along)
					3: p = Vector3(half, 0, along)
				p.y = seat_y + 0.1
				var s := rng.randf_range(0.92, 1.08)
				# Face the canvas centre, with a little yaw jitter.
				var look := Vector3(-p.x, 0, -p.z).normalized().rotated(Vector3.UP, rng.randf_range(-0.3, 0.3))
				var basis := Basis.looking_at(look, Vector3.UP).scaled(Vector3(s, s, s))
				xforms.append(Transform3D(basis, p))
				colors.append(Color.from_hsv(rng.randf(), rng.randf_range(0.1, 0.75), rng.randf_range(0.2, 0.7)))
	crowd = Crowd.new()
	add_child(crowd)
	crowd.build(xforms, colors, rng)

## Cheer louder: called by the fight scene on big hits and knockdowns.
func crowd_react(amount: float) -> void:
	if crowd:
		crowd.react(amount)

## Centre-canvas logo: the OdinFC mark printed flat on the canvas.
func _add_logo() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(3.4, 3.4)
	var m := StandardMaterial3D.new()
	m.albedo_texture = Branding.logo(Color(BRAND_DARK, 0.55))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mi := _mesh(q, Vector3(0, 0.004, 0), m)
	mi.rotation_degrees = Vector3(-90, 0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Sponsor banners hung above the back row of the seating on all four sides: the gym's logo on a light
## panel, black trim and a hanging bar, like a typical venue banner.
func _build_banners() -> void:
	var logo: Texture2D = load("res://assets/branding/elevate_logo.png")
	var w := 13.0
	var logo_h := (w - 1.0) * logo.get_height() / logo.get_width()
	var h := logo_h + 1.0
	var dist := CROWD_INNER + CROWD_ROWS * ROW_DEPTH + 0.4
	var y := VENUE_FLOOR + CROWD_ROWS * ROW_RISE + 0.95 + h * 0.5
	var panel_col := Color(0.94, 0.95, 0.96)
	for side in 4:
		var n := Node3D.new()
		n.position = Vector3(0, y, 0)
		n.rotation.y = side * PI * 0.5
		add_child(n)
		var hang := Node3D.new()  # tilted a little toward the ring, like a hung banner
		hang.position = Vector3(0, 0, -dist)
		hang.rotation.x = 0.2
		n.add_child(hang)
		var back := _quad(Vector2(w + 0.3, h + 0.3), Vector3(0, 0, -0.02), _unshaded(Color(0.03, 0.03, 0.04)))
		var panel := _quad(Vector2(w, h), Vector3(0, 0, 0), _unshaded(panel_col))
		var img := _quad(Vector2(w - 1.0, logo_h), Vector3(0, 0, 0.04),
				_unshaded(Color.WHITE, logo))
		var rod := _box(Vector3(w + 0.8, 0.12, 0.12), Vector3(0, h * 0.5 + 0.25, -0.05), Color(0.05, 0.06, 0.06))
		for node in [back, panel, img, rod]:
			node.get_parent().remove_child(node)
			hang.add_child(node)

func _unshaded(color: Color, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _quad(size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var m := _mesh(q, pos, mat)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

# --- helpers for subclasses ---

func _mat(color: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m

func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(b, pos, _mat(color))

func _cylinder(radius: float, height: float, pos: Vector3, color: Color, segments := 16) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return _mesh(c, pos, _mat(color))

func _mesh(mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.material_override = mat
	add_child(m)
	return m

## Flat branded text on a vertical surface (apron skirt, banners). `facing` = the direction it faces.
func _brand_text(text: String, pos: Vector3, facing: Vector3, size := 64, color := BRAND_GOLD) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.005
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	l.shaded = true
	add_child(l)
	l.look_at(pos - facing, Vector3.UP)
	return l
