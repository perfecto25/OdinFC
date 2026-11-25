class_name RingArena
extends Arena
## Muay Thai ring: raised square platform, four corner posts with pads (red / blue diagonal,
## neutral white), four ropes per side. The ropes are the boundary (ArenaBounds square).

const ROPE_HEIGHTS := [0.45, 0.8, 1.15, 1.5]
const ROPE_COLORS := [Color(0.75, 0.1, 0.1), Color(0.95, 0.95, 0.95), Color(0.1, 0.25, 0.75), Color(0.95, 0.95, 0.95)]
const ROPE_INSET := 0.45   ## ropes sit this far outside the fighters' limit (≈ body radius + rope give)
const APRON := 0.9         ## canvas beyond the ropes

func _build_enclosure() -> void:
	bounds = ArenaBounds.ring()
	var h: float = bounds.size + ROPE_INSET
	var plat: float = h + APRON
	var depth := -Arena.VENUE_FLOOR
	# Platform + canvas + skirt.
	_box(Vector3(plat * 2, 0.06, plat * 2), Vector3(0, -0.03, 0), Arena.CANVAS_COLOR)
	_box(Vector3(plat * 2 + 0.02, depth - 0.06, plat * 2 + 0.02), Vector3(0, -0.06 - (depth - 0.06) * 0.5, 0), Arena.BRAND_DARK)
	for d in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		_brand_text("OdinFC", -d * (plat + 0.02) + Vector3(0, -0.5, 0), -d, 72)
	# Corner posts and pads: red corner far-left, blue near-right, the other two neutral.
	var corners := {Vector2(-1, -1): Color(0.8, 0.1, 0.1), Vector2(1, 1): Color(0.1, 0.25, 0.8),
			Vector2(1, -1): Color(0.92, 0.92, 0.92), Vector2(-1, 1): Color(0.92, 0.92, 0.92)}
	for c in corners:
		var p := Vector3(c.x * h, 0, c.y * h)
		_cylinder(0.06, 1.75, p + Vector3(0, 0.875, 0), Color(0.15, 0.15, 0.16), 8)
		_box(Vector3(0.24, 1.3, 0.24), p + Vector3(0, 0.95, 0) - Vector3(c.x, 0, c.y) * 0.08, corners[c])
	# Ropes: four sides, each a long thin cylinder lying along the side.
	for i in ROPE_HEIGHTS.size():
		var y: float = ROPE_HEIGHTS[i]
		var col: Color = ROPE_COLORS[i]
		for side in [[Vector3(0, y, -h), true], [Vector3(0, y, h), true], [Vector3(-h, y, 0), false], [Vector3(h, y, 0), false]]:
			var r := _cylinder(0.028, h * 2, side[0], col, 8)
			r.rotation_degrees = Vector3(0, 0, 90) if side[1] else Vector3(90, 0, 0)
