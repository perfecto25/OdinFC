class_name CageArena
extends Arena
## Circular cage: raised round platform, chain-link fence on posts, padded top rail and base.
## The fence is the boundary (ArenaBounds circle).

const FENCE_INSET := 0.35  ## fence sits this far outside the fighters' limit
const FENCE_HEIGHT := 1.75
const POSTS := 16
const APRON := 0.8
const LINK_CELL := 0.12    ## chain-link diamond size (m)

func _build_enclosure() -> void:
	bounds = ArenaBounds.cage()
	camera_height = 3.3
	var r: float = bounds.size + FENCE_INSET
	var plat: float = r + APRON
	var depth := -Arena.VENUE_FLOOR
	# Canvas disc + skirt.
	var canvas := _cylinder(plat, 0.06, Vector3(0, -0.03, 0), Arena.CANVAS_COLOR, 48)
	canvas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cylinder(plat + 0.01, depth - 0.06, Vector3(0, -0.06 - (depth - 0.06) * 0.5, 0), Arena.BRAND_DARK, 48)
	for i in 4:
		var d := Vector3.FORWARD.rotated(Vector3.UP, i * PI * 0.5 + PI * 0.25)
		_brand_text("OdinFC", -d * (plat + 0.03) + Vector3(0, -0.5, 0), -d, 72)
	# Dark band on the canvas outside the fence, so the circle reads clearly from the wide shots.
	var edge := TorusMesh.new()
	edge.inner_radius = r - 0.02
	edge.outer_radius = plat
	edge.rings = 48
	edge.ring_segments = 4
	var em := _mesh(edge, Vector3(0, 0.002, 0), _mat(Arena.BRAND_DARK))
	em.scale = Vector3(1, 0.01, 1)
	# Posts.
	for i in POSTS:
		var a := TAU * i / POSTS
		_cylinder(0.045, FENCE_HEIGHT + 0.1, Vector3(cos(a) * r, (FENCE_HEIGHT + 0.1) * 0.5, sin(a) * r),
				Color(0.12, 0.12, 0.13), 8)
	# Chain-link fence: an open cylinder with a tiled, alpha-blended diamond texture (mipmapped, so
	# from the broadcast distance it reads as a light mesh haze instead of shimmering).
	var fence := CylinderMesh.new()
	fence.top_radius = r
	fence.bottom_radius = r
	fence.height = FENCE_HEIGHT
	fence.radial_segments = 64
	fence.rings = 1
	fence.cap_top = false
	fence.cap_bottom = false
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = _chain_link_texture()
	fm.albedo_color = Color(0.55, 0.57, 0.6, 1.0)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	fm.uv1_scale = Vector3(TAU * r / LINK_CELL, FENCE_HEIGHT / LINK_CELL, 1)
	fm.metallic = 0.6
	fm.roughness = 0.5
	var fmi := _mesh(fence, Vector3(0, FENCE_HEIGHT * 0.5, 0), fm)
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Padded top rail and base pad.
	var top := TorusMesh.new()
	top.inner_radius = r - 0.07
	top.outer_radius = r + 0.07
	top.rings = 64
	top.ring_segments = 8
	_mesh(top, Vector3(0, FENCE_HEIGHT, 0), _mat(Color(0.04, 0.04, 0.05), 0.6))
	var base := TorusMesh.new()
	base.inner_radius = r - 0.1
	base.outer_radius = r + 0.1
	base.rings = 64
	base.ring_segments = 8
	var bm := _mesh(base, Vector3(0, 0.08, 0), _mat(Arena.BRAND_DARK, 0.6))
	bm.scale = Vector3(1, 1.6, 1)

## One diamond cell of chain link: two diagonal wires on a transparent background.
func _chain_link_texture() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var d1 := absi(x - y)
			var d2 := absi(x + y - (n - 1))
			var d := mini(mini(d1, n - d1), mini(d2, n - d2))
			if d <= 1:
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 if d == 0 else 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
