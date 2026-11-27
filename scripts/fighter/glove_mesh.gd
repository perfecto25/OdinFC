class_name GloveMesh
## A 10 oz boxing glove built in code, about 28 cm long: black leather fist, thumb and wrist cuff, with the
## cuff taped in the corner colour and lettered (the mask comes from tools/gen_glove_tape.gd).
## Origin = wrist joint, +Y along the fingers, +Z out of the back of the hand, thumb toward +X * side.

const SIDES := 24
const LEATHER := Color(0.022, 0.022, 0.026)
const LETTERING := Color(0.93, 0.93, 0.9)
const TAPE_TEXT := "res://assets/branding/glove_tape.res"
const TAPE_SIDES := 64
const TAPE_TEXTURE := Vector2i(512, 256)

## Cross-sections along the glove: [y, half width, half depth, depth offset].
const BODY := [[-0.108, 0.0440, 0.0400, 0.0], [-0.101, 0.0490, 0.0450, 0.0], [-0.055, 0.0475, 0.0432, 0.0],
	[-0.010, 0.0430, 0.0380, 0.0], [0.015, 0.0540, 0.0450, 0.002], [0.045, 0.0680, 0.0560, 0.005],
	[0.085, 0.0735, 0.0635, 0.008], [0.125, 0.0715, 0.0625, 0.008], [0.155, 0.0620, 0.0530, 0.004],
	[0.175, 0.0450, 0.0370, -0.001], [0.186, 0.0200, 0.0170, -0.004]]
## The tape stands proud of the cuff; its first and last sections tuck the edges down onto the leather.
const TAPE := [[-0.091, 0.0482, 0.0442, 0.0], [-0.088, 0.0505, 0.0465, 0.0], [-0.055, 0.0498, 0.0455, 0.0],
	[-0.022, 0.0472, 0.0422, 0.0], [-0.019, 0.0442, 0.0392, 0.0]]
## Thumb spine: [x, y, z, radius]; it lies along the palm side of the fist.
const THUMB := [[0.026, -0.002, -0.006, 0.030], [0.056, 0.030, -0.022, 0.036], [0.068, 0.072, -0.031, 0.034],
	[0.055, 0.108, -0.037, 0.028], [0.040, 0.126, -0.038, 0.012]]

static var _cache := {}
static var _grain: NoiseTexture2D

static func build(color: Color, side: float) -> ArrayMesh:
	var key := [color, side]
	if _cache.has(key):
		return _cache[key]
	var rings: Array = []
	for s in BODY:
		rings.append(_ring(Vector3(0, s[0], s[3]), Vector3.RIGHT * s[1], Vector3.BACK * s[2], 0.75))
	var thumb: Array = []
	for i in THUMB.size():
		var p := _point(THUMB[i])
		var along := (_point(THUMB[mini(i + 1, THUMB.size() - 1)]) - _point(THUMB[maxi(i - 1, 0)])).normalized()
		var u := along.cross(Vector3.BACK).normalized()
		thumb.append(_ring(p, u * THUMB[i][3], u.cross(along).normalized() * THUMB[i][3], 1.0))

	var mesh := ArrayMesh.new()
	_add_surface(mesh, [rings, thumb], LEATHER, 0.3, side)
	_add_tape(mesh, color, side)
	_cache[key] = mesh
	return mesh

static func _point(t: Array) -> Vector3:
	return Vector3(t[0], t[1], t[2])

## A closed loop around `centre` in the plane of u and v; squareness < 1 gives a padded, boxy section.
static func _ring(centre: Vector3, u: Vector3, v: Vector3, squareness: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in SIDES:
		var a := TAU * i / SIDES
		out.append(centre + u * signf(cos(a)) * pow(absf(cos(a)), squareness)
				+ v * signf(sin(a)) * pow(absf(sin(a)), squareness))
	return out

## One surface lofted through each list of rings (smoothed along its length), ends capped, mirrored by side.
static func _add_surface(mesh: ArrayMesh, tubes: Array, color: Color, roughness: float, side: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for rings: Array in tubes:
		var fine: Array = []
		for r in rings.size() - 1:
			for k in 4:
				var ring := PackedVector3Array()
				for i in SIDES:
					var a: Vector3 = rings[maxi(r - 1, 0)][i]
					var d: Vector3 = rings[mini(r + 2, rings.size() - 1)][i]
					ring.append((rings[r][i] as Vector3).cubic_interpolate(rings[r + 1][i], a, d, k / 4.0))
				fine.append(ring)
		fine.append(rings[-1])
		var points := PackedVector3Array()
		for ring: PackedVector3Array in fine:
			points.append_array(ring)
		var ends := [Vector3.ZERO, Vector3.ZERO]
		for i in SIDES:
			ends[0] += fine[0][i] / SIDES
			ends[1] += fine[-1][i] / SIDES
		points.append_array(PackedVector3Array(ends))
		for p in points:
			st.set_smooth_group(0)
			st.add_vertex(Vector3(p.x * side, p.y, p.z))
		var tris := PackedInt32Array()
		var n := fine.size()
		for r in n - 1:
			for i in SIDES:
				var a := r * SIDES + i
				var b := r * SIDES + (i + 1) % SIDES
				tris.append_array([a, b, a + SIDES, b, b + SIDES, a + SIDES])
		for i in SIDES:
			var j := (i + 1) % SIDES
			tris.append_array([n * SIDES, j, i, n * SIDES + 1, (n - 1) * SIDES + i, (n - 1) * SIDES + j])
		# front faces wind clockwise seen from outside; flip when the tube runs the other way or is mirrored
		var volume := 0.0
		for t in range(0, tris.size(), 3):
			volume += points[tris[t]].dot(points[tris[t + 1]].cross(points[tris[t + 2]]))
		var flip := (volume > 0.0) != (side < 0.0)
		for t in range(0, tris.size(), 3):
			st.add_index(base + tris[t])
			st.add_index(base + tris[t + (2 if flip else 1)])
			st.add_index(base + tris[t + (1 if flip else 2)])
		base += points.size()
	st.generate_normals()
	st.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, _leather(color, roughness))

## The wrist tape, with texture coordinates: the lettering reads upright (fingers up) on the back of the
## hand and again on the palm side. It gets its own seam column so the texture does not run backwards.
static func _add_tape(mesh: ArrayMesh, color: Color, side: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var low: float = TAPE[1][0]
	var high: float = TAPE[-2][0]
	for s in TAPE:
		for i in TAPE_SIDES + 1:
			var a := TAU * i / TAPE_SIDES
			var x: float = signf(cos(a)) * pow(absf(cos(a)), 0.75) * s[1]
			var z: float = signf(sin(a)) * pow(absf(sin(a)), 0.75) * s[2]
			# mirroring the glove reverses the way round, so the text direction flips with it
			st.set_uv(Vector2(-side * 2.0 * i / TAPE_SIDES, inverse_lerp(high, low, s[0])))
			st.set_normal(Vector3(x * side / (s[1] * s[1]), 0.0, z / (s[2] * s[2])).normalized())
			st.add_vertex(Vector3(x * side, s[0], z + s[3]))
	var row := TAPE_SIDES + 1
	for r in TAPE.size() - 1:
		for i in TAPE_SIDES:
			var a := r * row + i
			# front faces wind clockwise seen from outside; mirroring reverses that
			var quad := [a, a + 1, a + row, a + 1, a + row + 1, a + row] if side > 0.0 \
					else [a, a + row, a + 1, a + 1, a + row, a + row + 1]
			for k: int in quad:
				st.add_index(k)
	st.generate_tangents()
	st.commit(mesh)
	var m := _leather(Color.WHITE, 0.42)
	m.uv1_triplanar = false  # the tape's own coordinates place the lettering
	m.uv1_scale = Vector3.ONE
	m.normal_enabled = false
	m.albedo_texture = _tape_texture(color)
	mesh.surface_set_material(mesh.get_surface_count() - 1, m)

static func _tape_texture(color: Color) -> Texture2D:
	var img := Image.create(TAPE_TEXTURE.x, TAPE_TEXTURE.y, false, Image.FORMAT_RGB8)
	img.fill(color)
	if ResourceLoader.exists(TAPE_TEXT):
		var mask: Image = load(TAPE_TEXT)
		for y in img.get_height():
			for x in img.get_width():
				var a := mask.get_pixel(x, y).r
				if a > 0.0:
					img.set_pixel(x, y, color.lerp(LETTERING, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Coated leather: a fine grain and a thin glossy finish over the colour.
static func _leather(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness + 0.08
	m.clearcoat_enabled = true
	m.clearcoat = 0.3
	m.clearcoat_roughness = 0.28
	if _grain == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = 0.09
		noise.fractal_octaves = 2
		_grain = NoiseTexture2D.new()
		_grain.noise = noise
		_grain.width = 512
		_grain.height = 512
		_grain.seamless = true
		_grain.as_normal_map = true
		_grain.bump_strength = 3.0
		_grain.generate_mipmaps = true
	m.normal_enabled = true
	m.normal_texture = _grain
	m.normal_scale = 0.35
	m.uv1_triplanar = true  # the glove is built without UVs
	m.uv1_scale = Vector3.ONE * 14.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
