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
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.3
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.3
	we.environment = e
	add_child(we)

## Broadcast rig: one shadowed key light straight down-ish on the canvas plus four unshadowed spots
## from the truss corners. Only the key casts shadows, to keep the iGPU cost low.
func _build_lights() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-72, 25, 0)
	key.light_energy = 0.4
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 25.0
	add_child(key)
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var s := SpotLight3D.new()
		s.position = Vector3(c.x * 4.5, 7.5, c.y * 4.5)
		s.light_energy = 3.0
		s.light_color = Color(1.0, 0.97, 0.92)
		s.spot_range = 14.0
		s.spot_angle = 32.0
		s.spot_attenuation = 0.6
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

## Crowd placeholders: one MultiMesh of capsules (a single draw call) with per-instance shirt colours.
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
				if rng.randf() < 0.12:
					continue  # empty seat
				var along := -half + (i + 0.5) * (half * 2 / n) + rng.randf_range(-0.08, 0.08)
				var p: Vector3
				match side:
					0: p = Vector3(along, 0, -half)
					1: p = Vector3(along, 0, half)
					2: p = Vector3(-half, 0, along)
					3: p = Vector3(half, 0, along)
				var s := rng.randf_range(0.9, 1.1)
				p.y = seat_y + 0.55 * s
				var basis := Basis.from_scale(Vector3(s, s, s))
				xforms.append(Transform3D(basis, p))
				var shade := rng.randf_range(0.15, 0.55)
				var tint := Color.from_hsv(rng.randf(), rng.randf_range(0.1, 0.6), shade)
				colors.append(tint)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = 1.1
	cap.radial_segments = 8
	cap.rings = 2
	mm.mesh = cap
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

## Centre-canvas logo (generic branding: no real promotion or sponsor marks).
func _add_logo() -> void:
	var l := Label3D.new()
	l.text = "OdinFC"
	l.font_size = 180
	l.pixel_size = 0.006
	l.outline_size = 0
	l.modulate = Color(BRAND_DARK, 0.35)
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.position = Vector3(0, 0.004, 0)
	l.double_sided = false
	l.shaded = true
	add_child(l)

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
