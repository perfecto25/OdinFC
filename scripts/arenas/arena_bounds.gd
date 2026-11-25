class_name ArenaBounds
extends RefCounted
## The fighting area's edge on the XZ plane: the ring's ropes (square) or the cage fence (circle).
## Pure math, so Fighter, Clinch and the AI can use it headless. `size` is the half-width of the
## square or the radius of the circle, measured to where a fighter's centre stops.

enum Shape { SQUARE, CIRCLE }

const RING_HALF := 3.4    ## Muay Thai ring: centre-to-ropes limit
const CAGE_RADIUS := 3.85 ## circular cage: roughly the same floor area as the ring

var shape := Shape.SQUARE
var size := RING_HALF

static func ring() -> ArenaBounds:
	return ArenaBounds.make(Shape.SQUARE, RING_HALF)

static func cage() -> ArenaBounds:
	return ArenaBounds.make(Shape.CIRCLE, CAGE_RADIUS)

static func make(s: Shape, sz: float) -> ArenaBounds:
	var b := ArenaBounds.new()
	b.shape = s
	b.size = sz
	return b

## Keep a position inside the boundary (y is kept as-is).
func clamp_position(p: Vector3) -> Vector3:
	if shape == Shape.SQUARE:
		return Vector3(clampf(p.x, -size, size), p.y, clampf(p.z, -size, size))
	var flat := Vector2(p.x, p.z)
	if flat.length() > size:
		flat = flat.normalized() * size
	return Vector3(flat.x, p.y, flat.y)

## How far a point (XZ) is inside the band `margin` wide along the edge, as a vector pointing back toward
## the centre. Zero when the point is further in than `margin`. Its length is the depth into the band.
func inward_push(p: Vector2, margin: float) -> Vector2:
	var lim := size - margin
	if shape == Shape.SQUARE:
		return Vector2(
			-signf(p.x) * maxf(0.0, absf(p.x) - lim),
			-signf(p.y) * maxf(0.0, absf(p.y) - lim))
	var r := p.length()
	if r <= lim or r < 0.001:
		return Vector2.ZERO
	return -p / r * (r - lim)

## Distance from a point (XZ) to the nearest edge (negative outside).
func distance_to_edge(p: Vector2) -> float:
	if shape == Shape.SQUARE:
		return size - maxf(absf(p.x), absf(p.y))
	return size - p.length()
