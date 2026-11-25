class_name FightCamera
extends Camera3D
## Broadcast side cam (default) and over-the-shoulder, toggled with camera_toggle (Tab / touchpad).
## Broadcast: stays side-on to the fighters' line (orbiting as they circle), zooms to keep both framed,
## with a slight handheld sway. Auto-cuts (hard cuts, no blend) for the referee phases:
##   INTRO wide establishing crane -> FIGHTING chosen mode -> KNOCKDOWN low shot on the downed fighter
##   -> DOCTOR close-up on the cut -> ROUND_BREAK slow wide orbit -> OVER slow orbit on the winner.
## Purely visual: reads fighter positions and FightFlow, never feeds back into the simulation.

enum Shot { BROADCAST, OVER_SHOULDER, WIDE, KNOCKDOWN, DOCTOR, WINNER }

const FOV_BROADCAST := 40.0
const FOV_SHOULDER := 55.0
const MIN_DIST := 7.5         ## broadcast distance from the fighters' midpoint
const MAX_DIST := 11.0
const MAX_RADIUS := 11.5      ## the camera rail: never further than this from the canvas centre (crowd)
const FRAME_MARGIN := 2.4     ## metres of framing around the fighters
const YAW_SPEED := 1.2        ## rad/s the broadcast cam can orbit to stay side-on
const SWAY_POS := 0.035       ## handheld sway amplitude (m)
const SWAY_ROT := 0.004       ## handheld sway amplitude (rad)

var a: Fighter                ## the player's fighter (over-the-shoulder sits behind this one)
var b: Fighter
var flow: FightFlow
var base_height := 2.3        ## broadcast height (the arena's camera_height)
var over_shoulder := false
var shot := Shot.WIDE

var _side := Vector3.BACK     ## unit vector from the fighters' midpoint toward the broadcast camera
var _snap := true             ## next frame jumps instead of easing (a cut)
var _t := 0.0
var _shot_t := 0.0            ## seconds since the last cut

func _ready() -> void:
	if flow:
		flow.phase_changed.connect(_on_phase)
		_on_phase(flow.phase)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_toggle"):
		over_shoulder = not over_shoulder
		if shot == Shot.BROADCAST or shot == Shot.OVER_SHOULDER:
			_cut(Shot.OVER_SHOULDER if over_shoulder else Shot.BROADCAST)

func _on_phase(p: FightFlow.Phase) -> void:
	match p:
		FightFlow.Phase.INTRO:
			_cut(Shot.WIDE)
		FightFlow.Phase.FIGHTING:
			_cut(Shot.OVER_SHOULDER if over_shoulder else Shot.BROADCAST)
		FightFlow.Phase.KNOCKDOWN:
			_cut(Shot.KNOCKDOWN)
		FightFlow.Phase.DOCTOR:
			_cut(Shot.DOCTOR)
		FightFlow.Phase.ROUND_BREAK:
			_cut(Shot.WIDE)
		FightFlow.Phase.OVER:
			_cut(Shot.WINNER)

func _cut(s: Shot) -> void:
	shot = s
	_snap = true
	_shot_t = 0.0

func _process(delta: float) -> void:
	if a == null or b == null:
		return
	_t += delta
	_shot_t += delta
	var pos: Vector3
	var look: Vector3
	var fov_target := FOV_BROADCAST
	var blend_rate := 4.0
	match shot:
		Shot.BROADCAST:
			var r := _broadcast(delta)
			pos = r[0]
			look = r[1]
		Shot.OVER_SHOULDER:
			var dir := _flat(b.global_position - a.global_position).normalized()
			var side := dir.cross(Vector3.UP)
			pos = a.global_position - dir * 2.7 + side * 1.05 + Vector3(0, 2.4, 0)
			look = b.global_position + Vector3(0, 1.1, 0)
			fov_target = FOV_SHOULDER
		Shot.WIDE:
			# Slow orbit from high in the stands.
			var ang := 0.35 + _shot_t * 0.06
			pos = Vector3(sin(ang) * 10.5, 6.0, cos(ang) * 10.5)
			look = Vector3(0, 0.6, 0)
			fov_target = 45.0
			blend_rate = 0.0
		Shot.KNOCKDOWN:
			# Low, from beyond the downed fighter: them in the foreground, the standing one behind.
			var down := flow.downed if flow and flow.downed else b
			var up := a if down == b else b
			var axis := _flat(down.global_position - up.global_position).normalized()
			var perp := axis.cross(Vector3.UP)
			if perp.dot(_side) < 0.0:
				perp = -perp
			pos = down.global_position + axis * 3.2 + perp * 1.6 + Vector3(0, 1.0, 0)
			look = down.global_position.lerp(up.global_position, 0.35) + Vector3(0, 0.7, 0)
			fov_target = 50.0
			blend_rate = 0.0
		Shot.DOCTOR:
			var f := flow.doctor_for if flow and flow.doctor_for else b
			var facing := -f.global_transform.basis.z
			facing.y = 0
			var side := facing.normalized().cross(Vector3.UP)
			pos = f.global_position + facing.normalized() * 1.5 + side * 0.5 + Vector3(0, 1.6, 0)
			look = f.global_position + Vector3(0, 1.5, 0)
			fov_target = 35.0
			blend_rate = 0.0
		Shot.WINNER:
			var w: Fighter = flow.result.get("winner") if flow and flow.result else null
			if w == null:
				var ang2 := _shot_t * 0.08
				pos = Vector3(sin(ang2) * 8.0, 4.0, cos(ang2) * 8.0)
				look = Vector3(0, 1.0, 0)
			else:
				var ang3 := atan2(_side.x, _side.z) + _shot_t * 0.15
				pos = w.global_position + Vector3(sin(ang3) * 3.2, 1.7, cos(ang3) * 3.2)
				look = w.global_position + Vector3(0, 1.3, 0)
			fov_target = 42.0
			blend_rate = 0.0
	pos += _sway()
	if _snap or blend_rate <= 0.0:
		global_position = pos
		fov = fov_target
		_snap = false
	else:
		var k := clampf(delta * blend_rate, 0.0, 1.0)
		global_position = global_position.lerp(pos, k)
		fov = lerpf(fov, fov_target, k)
	if not global_position.is_equal_approx(look):
		look_at(look)
	rotate_object_local(Vector3.FORWARD, sin(_t * 0.9) * SWAY_ROT)

## Side-on to the fighters' line, on whichever side the camera is already on, turning at a limited rate
## so circling fighters make the camera orbit instead of flipping. Distance zooms to keep both framed.
func _broadcast(delta: float) -> Array:
	var mid := (a.global_position + b.global_position) * 0.5
	var axis := _flat(b.global_position - a.global_position)
	var dist := axis.length()
	if dist > 0.05:
		var perp := axis.normalized().cross(Vector3.UP)  # one of the two side-on directions
		if perp.dot(_side) < 0.0:
			perp = -perp
		if _snap:
			_side = perp
		else:
			var ang := _side.signed_angle_to(perp, Vector3.UP)
			var step := clampf(ang, -YAW_SPEED * delta, YAW_SPEED * delta)
			_side = _side.rotated(Vector3.UP, step).normalized()
	# Fit the fighters plus a margin into the horizontal field of view.
	var aspect := get_viewport().get_visible_rect().size.aspect() if get_viewport() else 16.0 / 9.0
	var half_h := atan(tan(deg_to_rad(FOV_BROADCAST) * 0.5) * aspect)
	var d := clampf((dist + FRAME_MARGIN) * 0.5 / tan(half_h) + 1.5, MIN_DIST, MAX_DIST)
	var pos := mid + _side * d
	pos.y = base_height + d * 0.1
	# Stay on the camera rail (out of the crowd).
	var flat := Vector2(pos.x, pos.z)
	if flat.length() > MAX_RADIUS:
		flat = flat.normalized() * MAX_RADIUS
		pos = Vector3(flat.x, pos.y, flat.y)
	return [pos, mid + Vector3(0, 1.1, 0)]

func _sway() -> Vector3:
	return Vector3(sin(_t * 0.7) + 0.5 * sin(_t * 1.9 + 1.3),
			0.6 * sin(_t * 1.1 + 0.4) + 0.3 * sin(_t * 2.3),
			0.5 * sin(_t * 0.5 + 2.0)) * SWAY_POS

func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
