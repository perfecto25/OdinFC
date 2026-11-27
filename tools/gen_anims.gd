extends SceneTree
## Generates the Muay Thai techniques Mixamo doesn't have (round kicks, teep, side kick, check) as
## Animation resources on the Mixamo skeleton, from the fight stance.
##   godot --headless --path . -s tools/gen_anims.gd            -> assets/anim/generated/<name>.res
##                                                  and the upright set assets/anim/generated/muay_thai/<name>.res
## The muay_thai set (FighterData.anim_set) is the same techniques solved from a tall stance with the hands
## high, plus its own footwork, and the Mixamo punches / hit reactions re-seated on that stance.
##
## Angles: hips_rot.y is the turn ADDED to the stance, which is already bladed ~45 deg (hips face front-right,
## toward -X+Z); +y turns the right hip forward. Knee/elbow poles are in the hips' frame (+Z = belly).
## Each technique is a few timed KEY POSES (hip yaw/lean, spine twist, foot/hand targets, knee/elbow
## directions). Parameters are interpolated along smooth curves and the legs/arms are solved with
## two-bone IK every frame, then baked at 60 fps. Positions are in metres relative to the stance's
## ground point under the hips; the fighter faces +Z, its left is +X (orthodox: left foot leads).
## Every clip stores meta "impact" = seconds at which the strike connects (the game time-warps the clip
## so that moment lands on the move's first active frame).

const SRC_STANCE := "res://assets/mixamo/src/standing_idle_to_fight_idle.fbx"
const OUT_DIR := "res://assets/anim/generated/"
## Mixamo clips (as cut in FighterModel.CLIPS) that get the Muay Thai stance under and around them.
const RESEAT := ["jab", "cross", "lead_hook", "hit_head", "hit_body", "stagger"]
const FPS := 60.0
## Where a swinging arm hangs, off straight down (+Z toward the opponent, +X the fighter's left).
const SWING_DRIFT := {"Left": Vector3(0.4, 0, 0.45), "Right": Vector3(-0.4, 0, 0.45)}
const FOOT_POINT_ANGLE := 6.0    ## degrees a fully pointed foot still sits off the line of the shin
const SKEL_PATH := "Skeleton3D"

var sk: Skeleton3D
var stance_local: Array = []     ## [Quaternion rot, Vector3 pos] per bone
var stance_global: Array = []    ## Transform3D per bone (skeleton space)
var C := Vector3.ZERO            ## ground point under the stance hips
var S := {}                      ## stance targets (C-relative): lfoot, rfoot, lhand, rhand, poles
var B := {}                      ## bone indices by short name
var guard_l := Vector3(0.07, 1.47, 0.27)    ## high-guard wrist positions
var guard_r := Vector3(-0.1, 1.46, 0.16)
var guard_crouch := 0.035
var rise_scale := 1.0            ## how much of a technique's upward hip travel the stance has room for

func _initialize() -> void:
	_run.call_deferred()

func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null

func _run() -> void:
	var scn: Node3D = load(SRC_STANCE).instantiate()
	root.add_child(scn)
	var ap: AnimationPlayer = _find(scn, "AnimationPlayer")
	sk = _find(scn, "Skeleton3D")
	var an := ap.get_animation_list()[0]
	ap.play(an)
	ap.seek(ap.get_animation(an).length, true)
	ap.stop(true)  # keep the pose, stop driving the skeleton
	for b in sk.get_bone_count():
		B[sk.get_bone_name(b).trim_prefix("mixamorig_")] = b
	_capture_stance()
	_generate(_techniques(), OUT_DIR)
	_muay_thai_stance()
	var set_dir := OUT_DIR + "muay_thai/"
	var techniques := _techniques()
	techniques.merge({"step_f": _step(Vector3(0, 0, 1), 0.15), "step_b": _step(Vector3(0, 0, -1), 0.15),
		"step_l": _step(Vector3(1, 0, 0), 0.08), "step_r": _step(Vector3(-1, 0, 0), 0.08)})
	_generate(techniques, set_dir)
	for name in RESEAT:
		_save(_reseat(name), set_dir, name)
	quit()

## Take the skeleton's current pose as the stance every technique starts and ends in.
func _capture_stance() -> void:
	stance_local.clear()
	stance_global.clear()
	for b in sk.get_bone_count():
		stance_local.append([sk.get_bone_pose_rotation(b), sk.get_bone_pose_position(b)])
	sk.force_update_all_bone_transforms()
	for b in sk.get_bone_count():
		stance_global.append(sk.get_bone_global_pose(b))
	var hp := _g("Hips").origin
	C = Vector3(hp.x, 0, hp.z)
	for side in ["Left", "Right"]:
		var k: String = side.left(1).to_lower()
		S[k + "foot"] = _g(side + "Foot").origin - C
		S[k + "hand"] = _g(side + "Hand").origin - C
		S[k + "pole"] = _bend_dir(side + "UpLeg", side + "Leg", side + "Foot")
		S[k + "elbow"] = _bend_dir(side + "Arm", side + "ForeArm", side + "Hand")

func _techniques() -> Dictionary:
	return {
		"round_kick_body": _round_kick(1.0, 0.0),
		"round_kick_high": _high_kick(),
		"round_kick_low": _round_kick(0.48, -1.0),
		"teep": _teep(),
		"side_kick": _side_kick(),
		"check": _check(),
		"superman_punch": _superman_punch(),
		"dash_back": _dash_back(),
		"uppercut": _uppercut(),
		"rear_hook": _rear_hook(),
		"idle": _idle(),
		"guard": _guard(),
		"block_hit": _block_hit(),
		"knee": _knee(),
		"clinch": _clinch_hold(),
		"clinch_knee": _clinch_knee(),
	}

func _generate(techniques: Dictionary, dir: String) -> void:
	for name in techniques:
		var keys: Array = techniques[name]
		var anim := _bake(keys)
		var impact := 0.0
		for k in keys:
			if k.get("impact", false):
				impact = k.t
		anim.set_meta("impact", impact)
		if keys[0].has("travel"):
			anim.set_meta("travel", keys[0].travel)
		_save(anim, dir, name)

func _save(anim: Animation, dir: String, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	if name in ["idle", "clinch"] or name.begins_with("step_"):
		anim.loop_mode = Animation.LOOP_LINEAR
	var path := dir + name + ".res"
	ResourceSaver.save(anim, path)
	print("saved %s  length %.2fs  impact %.2fs" % [path, anim.length, anim.get_meta("impact", 0.0)])

# --- muay thai stance -------------------------------------------------------------------------------

## Re-pose the boxing stance into a Muay Thai one and make it the base: tall with soft knees, hips nearly
## square, lead foot well forward and pointing at the opponent, rear foot turned out, hands high.
func _muay_thai_stance() -> void:
	const HIP_HEIGHT := 0.995     # legs straight would put the hips at about 1.02
	const HIP_YAW := -22.0        # degrees, negative = right side back
	const TORSO_LEAN := 3.0       # degrees forward
	var fwd: Vector3 = stance_global[B.Hips].basis.z
	var torso: Vector3 = stance_global[B.Neck].origin - stance_global[B.Hips].origin
	var ankle: float = 0.5 * (S.lfoot.y + S.rfoot.y)
	var p := _base()
	p.hips_off = Vector3(0, HIP_HEIGHT - stance_global[B.Hips].origin.y, 0)
	p.hips_rot = Vector3(0, HIP_YAW - rad_to_deg(atan2(fwd.x, fwd.z)), 0)
	torso = _rot(Vector3(0, p.hips_rot.y, 0)) * torso  # where the lean points once the hips have turned
	p.spine_rot = Vector3(TORSO_LEAN - rad_to_deg(atan2(torso.z, torso.y)), 0, rad_to_deg(atan2(torso.x, torso.y)))
	p.lfoot = Vector3(0.11, ankle, 0.25)
	p.rfoot = Vector3(-0.14, ankle, -0.23)
	var turned := _rot(Vector3(0, p.hips_rot.y, 0)).inverse()
	p.lpole = turned * Vector3(0.05, 0, 1)
	p.rpole = turned * Vector3(-0.6, 0, 0.8)
	for side in [["Left", "lpivot", -6.0], ["Right", "rpivot", -48.0]]:
		var toe: Vector3 = stance_global[B[side[0] + "ToeBase"]].origin - stance_global[B[side[0] + "Foot"]].origin
		p[side[1]] = side[2] - rad_to_deg(atan2(toe.x, toe.z))
	_solve(_full(p))
	# Hands go where the head ended up: wrists at cheek height so the gloves reach the brow, lead hand
	# further out, elbows under them.
	var head := _g("Head").origin - C
	p.lhand = head + Vector3(0.14, -0.09, 0.34)
	p.rhand = head + Vector3(-0.13, -0.09, 0.18)
	p.lelbow = turned * Vector3(0.35, -1, 0.0)
	p.relbow = turned * Vector3(-0.35, -1, 0.0)
	_solve(_full(p))
	for side in ["Left", "Right"]:  # straight wrists behind the gloves
		sk.set_bone_pose_rotation(B[side + "Hand"], sk.get_bone_rest(B[side + "Hand"]).basis.get_rotation_quaternion())
	sk.force_update_all_bone_transforms()
	_capture_stance()
	guard_l = S.lhand + Vector3(-0.04, 0.04, -0.05)
	guard_r = S.rhand + Vector3(0.02, 0.05, -0.01)
	guard_crouch = 0.015
	rise_scale = 0.3

## One key's values in the form _solve() takes (every parameter a Vector3).
func _full(k: Dictionary) -> Dictionary:
	var d := {}
	for p in PARAMS:
		var v = k.get(p, DEFAULTS.get(p, S.get(p)))
		d[p] = v if v is Vector3 else Vector3(v, 0, 0)
	return d

## In-place step-drag footwork (loops): each foot slides back under the body while planted, then skips
## forward again; the feet alternate, so the stance never crosses or closes up much.
func _step(dir: Vector3, reach: float) -> Array:
	const LENGTH := 0.4
	const PLANTED := 0.55   # share of the cycle each foot spends on the canvas
	var frames := int(round(LENGTH * FPS))
	var keys: Array = []
	for f in frames + 1:
		var k := _merge(_base(), {"t": f / FPS, "travel": 2.0 * reach / (PLANTED * LENGTH),
			"hips_off": Vector3(0, -0.012 * absf(sin(TAU * f / frames)), 0)})
		for foot in [["lfoot", 0.0], ["rfoot", 0.5]]:
			var u := fposmod(float(f) / frames + foot[1], 1.0)
			var swing := clampf((u - PLANTED) / (1.0 - PLANTED), 0.0, 1.0)
			var along := 1.0 - 2.0 * u / PLANTED if u < PLANTED else -1.0 + 2.0 * smoothstep(0.0, 1.0, swing)
			k[foot[0]] = S[foot[0]] + dir * reach * along + Vector3.UP * 0.05 * sin(PI * swing)
		keys.append(k)
	return keys

## A Mixamo punch or hit reaction on the Muay Thai base: starts and ends in the stance, follows the take's
## upper body in between, and keeps the stance's feet (the take's own crouched legs are replaced).
func _reseat(name: String) -> Animation:
	var src: Animation = FighterModel.library().get_animation(name)
	var impact: float = FighterModel._impacts.get(name, 0.0)
	var tracks := {}  ## bone -> source rotation track
	var hips_track := -1
	for i in src.get_track_count():
		var b := sk.find_bone(String(src.track_get_path(i)).get_slice(":", 1))
		if b < 0:
			continue
		if src.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			tracks[b] = i
		elif b == B.Hips:
			hips_track = i
	var legs: Array[int] = []
	for side in ["Left", "Right"]:
		for part in ["UpLeg", "Leg", "Foot", "ToeBase"]:
			legs.append(B[side + part])
	var anim := Animation.new()
	anim.length = src.length
	anim.step = 1.0 / FPS
	anim.set_meta("impact", impact)
	var out := {}
	for b in sk.get_bone_count():
		out[b] = anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(out[b], NodePath(SKEL_PATH + ":" + sk.get_bone_name(b)))
	var hip_out := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hip_out, NodePath(SKEL_PATH + ":" + sk.get_bone_name(B.Hips)))
	var start := src.position_track_interpolate(hips_track, 0.0)
	var n := int(ceil(src.length * FPS))
	for f in n + 1:
		var t := minf(f / FPS, src.length)
		# share of the take: eases in towards the impact (hit reactions: at once), eases out to the stance
		var w := smoothstep(0.0, maxf(impact * 0.6, 0.1), t) \
				* (1.0 - smoothstep(impact + 0.4 * (src.length - impact), src.length, t))
		for b in sk.get_bone_count():
			var q: Quaternion = stance_local[b][0]
			if tracks.has(b) and not legs.has(b):
				q = q.slerp(src.rotation_track_interpolate(tracks[b], t), w)
			sk.set_bone_pose_rotation(b, q)
			sk.set_bone_pose_position(b, stance_local[b][1])
		var move := src.position_track_interpolate(hips_track, t) - start
		sk.set_bone_pose_position(B.Hips, stance_local[B.Hips][1] + Vector3(move.x * 0.6, -0.03, move.z * 0.6) * w)
		sk.force_update_all_bone_transforms()
		for side in ["Left", "Right"]:
			var k: String = side.left(1).to_lower()
			_two_bone(B[side + "UpLeg"], B[side + "Leg"], B[side + "Foot"], C + S[k + "foot"], S[k + "pole"])
			_set_global_basis(B[side + "Foot"], stance_global[B[side + "Foot"]].basis)
		for b in sk.get_bone_count():
			anim.rotation_track_insert_key(out[b], t, sk.get_bone_pose_rotation(b))
		anim.position_track_insert_key(hip_out, t, sk.get_bone_pose_position(B.Hips))
	return anim

# --- techniques -------------------------------------------------------------------------------------

func _guard_hands(k: Dictionary) -> Dictionary:
	k.lhand = S.lhand
	k.rhand = S.rhand
	return k

## Rear-leg (right) round kick. h = foot height at impact; tier -1 low / 0 body / 1 high.
## Muay Thai shape: lead foot pivots out, hips turn over ~90 deg, shin lands across the target with the
## leg nearly straight, kicking-side arm swings down and back, the other hand guards the face.
func _round_kick(h: float, tier: float) -> Array:
	var yaw := 130.0 + 12.0 * tier         # from bladed stance to turned over: belly faces the side
	var lean := -18.0 - 14.0 * tier        # upper body leans away from the kick
	var rise := 0.05 + 0.03 * tier         # up on the ball of the support foot
	var reach := 0.9 - 0.02 * tier         # aimed past full extension: the leg arrives straight
	var stance := _guard_hands({"t": 0.0, "lfoot": S.lfoot, "rfoot": S.rfoot, "lpole": S.lpole, "rpole": S.rpole,
		"hips_off": Vector3.ZERO, "hips_rot": Vector3.ZERO, "spine_rot": Vector3.ZERO, "lpivot": 0.0, "rpivot": 0.0,
		"rpitch": 0.0, "rplant": 1.0, "lelbow": S.lelbow, "relbow": S.relbow, "rfree": 1.0, "rswing": 0.0, "lcarry": 0.0, "rpoint": 0.0})
	return [
		stance,
		{"t": 0.09, "hips_rot": Vector3(-4, 45, 0), "hips_off": Vector3(0.03, rise * 0.5, 0.04), "spine_rot": Vector3(0, -8, 0),
			"lpivot": 35.0, "rfoot": Vector3(-0.22, 0.32 + 0.1 * tier, -0.12), "rpole": Vector3(0, 0.3, 1), "rplant": 0.0,
			"rpitch": 20.0, "rswing": 0.45, "rpoint": 0.5, "lcarry": 0.25, "lhand": S.lhand + Vector3(0.0, 0.05, 0.05)},
		{"t": 0.2, "hips_rot": Vector3(lean * 0.6, yaw * 0.7, 0), "hips_off": Vector3(0.06, rise, 0.07),
			"spine_rot": Vector3(0, -10, 0), "lpivot": 75.0,
			"rfoot": Vector3(-0.2, h * 0.85, reach * 0.5), "rpole": Vector3(0, 0.4, 1), "rpitch": 35.0,
			"rswing": 0.9, "rpoint": 0.9, "lcarry": 0.85, "lhand": Vector3(0.12, 1.42, 0.3)},
		{"t": 0.3, "impact": true, "hips_rot": Vector3(lean, yaw, 0), "hips_off": Vector3(0.08, rise, 0.08),
			"spine_rot": Vector3(0, -12, 0), "lpivot": 95.0,
			"rfoot": Vector3(0.5, h, reach), "rpole": Vector3(0, 0.4, 1), "rpitch": 40.0,
			"rswing": 1.0, "rpoint": 1.0, "lcarry": 1.0, "lhand": Vector3(0.18, 1.45, 0.32)},
		{"t": 0.42, "hips_rot": Vector3(lean * 0.5, yaw * 0.55, 0), "hips_off": Vector3(0.04, rise * 0.6, 0.04),
			"spine_rot": Vector3(0, -6, 0), "lpivot": 60.0,
			"rfoot": Vector3(-0.15, 0.4 + 0.15 * tier, 0.05), "rpole": Vector3(0, 0.3, 1), "rpitch": 20.0,
			"rswing": 0.55, "rpoint": 0.6, "lcarry": 0.6, "lhand": S.lhand + Vector3(0, 0.05, 0)},
		_merge(stance, {"t": 0.62}),
	]

## Rear-leg head kick, in three shapes: (1) a long step out and forward on the lead foot, toes turned out,
## rear leg trailing; (2) the knee swings up and through ahead of the foot, up on the ball of the support
## foot, kicking-side arm dropping back; (3) hips fully turned over, leg straight at head height, torso
## laid away from the kick on a straight support leg with its heel toward the target.
func _high_kick() -> Array:
	var stance := _merge(_base(), {"rfree": 1.0, "rswing": 0.0, "lcarry": 0.0, "rpoint": 0.0})
	var up := 1.0 / rise_scale  # the kick needs its full rise on either stance
	var plant: Vector3 = S.lfoot + Vector3(0.2, 0.0, 0.26)     # where the lead foot steps to
	var toe := plant + Vector3(0, 0.05, 0)                     # ...and up on the ball of that foot
	# knee directions are given in the world and turned into the hips' frame at that key
	var knee := func(yaw: float, dir: Vector3) -> Vector3: return _rot(Vector3(0, yaw, 0)).inverse() * dir
	var chamber := {"hips_rot": Vector3(-12, 85, 0), "hips_off": Vector3(0.18, 0.04 * up, 0.22),
		"spine_rot": Vector3(-2, -6, 0), "lfoot": toe, "lpivot": 105.0, "lplant": 0.7, "lpitch": 22.0,
		"lpole": knee.call(85.0, Vector3(0.7, 0, 0.7)), "rplant": 0.0, "rfoot": Vector3(-0.42, 0.8, 0.3),
		"rpole": knee.call(85.0, Vector3(0.1, 0.35, 1)), "rpitch": 30.0,
		"lhand": Vector3(0.16, 1.5, 0.66), "rswing": 0.85, "rpoint": 0.8, "lcarry": 0.75, "lelbow": Vector3(0.3, -1, 0.2)}
	return [
		stance,
		{"t": 0.05, "hips_off": Vector3(0.07, 0.0, 0.1), "lplant": 0.4, "lfoot": S.lfoot.lerp(plant, 0.55) + Vector3(0, 0.09, 0),
			"lpivot": 25.0, "rswing": 0.1},
		{"t": 0.11, "hips_rot": Vector3(0, 28, 0), "hips_off": Vector3(0.16, -0.02, 0.24), "spine_rot": Vector3(3, -10, 0),
			"lplant": 1.0, "lfoot": plant, "lpivot": 55.0, "lpole": knee.call(28.0, Vector3(0.5, 0, 0.85)),
			"rplant": 0.0, "rfoot": S.rfoot + Vector3(-0.02, 0.1, -0.02), "rpitch": 45.0, "rpole": knee.call(28.0, Vector3(-0.2, -0.2, 1)),
			"lhand": S.lhand + Vector3(0.14, 0.0, 0.34), "rswing": 0.4, "rpoint": 0.25},
		_merge(chamber, {"t": 0.2}),
		{"t": 0.3, "impact": true, "hips_rot": Vector3(-36, 138, 0), "hips_off": Vector3(0.2, 0.06 * up, 0.18),
			"spine_rot": Vector3(-8, -14, 0), "lfoot": toe, "lpivot": 150.0, "lplant": 0.7, "lpitch": 22.0,
			"lpole": knee.call(138.0, Vector3(0.8, 0, -0.1)), "rplant": 0.0, "rfoot": Vector3(0.28, 1.58, 1.12),
			"rpole": Vector3(0, 0.4, 1), "rpitch": 45.0, "lhand": Vector3(0.28, 1.42, 0.42),
			"rswing": 1.0, "rpoint": 1.0, "lcarry": 1.0, "lelbow": Vector3(0.5, -1, 0.1)},
		_merge(chamber, {"t": 0.43, "hips_rot": Vector3(-10, 75, 0), "rswing": 0.65}),
		{"t": 0.55, "hips_rot": Vector3(0, 22, 0), "hips_off": Vector3(0.08, -0.01, 0.11), "spine_rot": Vector3.ZERO,
			"lplant": 0.6, "lfoot": S.lfoot.lerp(plant, 0.5) + Vector3(0, 0.07, 0), "lpivot": 22.0, "lpitch": 0.0,
			"lpole": S.lpole, "rplant": 1.0, "rfoot": S.rfoot, "rpole": S.rpole, "rpitch": 0.0,
			"lhand": S.lhand, "lelbow": S.lelbow, "rswing": 0.18, "rpoint": 0.0, "lcarry": 0.15},
		_merge(stance, {"t": 0.68}),
	]

## Lead-leg (left) teep: knee up to the chest, drive the sole straight into the target, hips push forward
## while the shoulders lean back, recoil to the chamber, step back down.
func _teep() -> Array:
	var stance := _guard_hands({"t": 0.0, "lfoot": S.lfoot, "rfoot": S.rfoot, "lpole": S.lpole, "rpole": S.rpole,
		"hips_off": Vector3.ZERO, "hips_rot": Vector3.ZERO, "spine_rot": Vector3.ZERO, "lpivot": 0.0, "rpivot": 0.0,
		"lpitch": 0.0, "lplant": 1.0, "lelbow": S.lelbow, "relbow": S.relbow})
	return [
		stance,
		{"t": 0.12, "hips_rot": Vector3(-8, 5, 0), "hips_off": Vector3(0.0, 0.03, -0.02), "lplant": 0.0,
			"lfoot": Vector3(0.12, 0.5, 0.18), "lpole": Vector3(0, 0.6, 1), "lpitch": -25.0, "rpivot": -10.0},
		{"t": 0.24, "impact": true, "hips_rot": Vector3(-20, 10, 0), "hips_off": Vector3(0.0, 0.05, 0.15),
			"spine_rot": Vector3(-6, 0, 0),
			"lfoot": Vector3(0.1, 0.95, 1.12), "lpole": Vector3(0, 1, 0.3), "lpitch": -55.0,
			"lhand": S.lhand + Vector3(0.0, 0.02, -0.06), "rhand": S.rhand + Vector3(0.0, 0.0, -0.08)},
		{"t": 0.36, "hips_rot": Vector3(-8, 5, 0), "hips_off": Vector3(0, 0.03, 0.02),
			"lfoot": Vector3(0.14, 0.48, 0.2), "lpole": Vector3(0, 0.6, 1), "lpitch": -20.0,
			"lhand": S.lhand, "rhand": S.rhand},
		_merge(stance, {"t": 0.55}),
	]

## Lead-leg (left) side kick: turn the hips side-on, chamber the knee across, drive the heel out with
## the torso leaning well away, re-chamber, set down.
func _side_kick() -> Array:
	var stance := _guard_hands({"t": 0.0, "lfoot": S.lfoot, "rfoot": S.rfoot, "lpole": S.lpole, "rpole": S.rpole,
		"hips_off": Vector3.ZERO, "hips_rot": Vector3.ZERO, "spine_rot": Vector3.ZERO, "lpivot": 0.0, "rpivot": 0.0,
		"lpitch": 0.0, "lplant": 1.0, "lelbow": S.lelbow, "relbow": S.relbow})
	return [
		stance,
		{"t": 0.13, "hips_rot": Vector3(-6, -30, 0), "hips_off": Vector3(-0.02, 0.03, -0.04), "spine_rot": Vector3(0, 15, 0),
			"rpivot": -45.0, "lplant": 0.0, "lfoot": Vector3(0.05, 0.55, 0.1), "lpole": Vector3(0, 0.5, 1),
			"lpitch": -20.0},
		{"t": 0.27, "impact": true, "hips_rot": Vector3(-30, -50, 0), "hips_off": Vector3(-0.08, 0.05, 0.02),
			"spine_rot": Vector3(0, 10, 0), "rpivot": -70.0,
			"lfoot": Vector3(0.1, 1.0, 1.0), "lpole": Vector3(0, 0.2, 1), "lpitch": -35.0,
			"lhand": Vector3(0.12, 1.35, 0.35), "rhand": Vector3(-0.05, 1.3, 0.12)},
		{"t": 0.4, "hips_rot": Vector3(-6, -30, 0), "hips_off": Vector3(-0.02, 0.03, -0.02),
			"spine_rot": Vector3(0, 6, 0), "rpivot": -40.0,
			"lfoot": Vector3(0.06, 0.55, 0.14), "lpole": Vector3(0, 0.5, 1), "lpitch": -15.0,
			"lhand": S.lhand, "rhand": S.rhand},
		_merge(stance, {"t": 0.6}),
	]

## Leg-kick check: lift the lead shin, knee turned out to meet the kick, hold, set down.
func _check() -> Array:
	var stance := _guard_hands({"t": 0.0, "lfoot": S.lfoot, "rfoot": S.rfoot, "lpole": S.lpole, "rpole": S.rpole,
		"hips_off": Vector3.ZERO, "hips_rot": Vector3.ZERO, "spine_rot": Vector3.ZERO, "lpivot": 0.0, "rpivot": 0.0,
		"lpitch": 0.0, "lplant": 1.0, "lelbow": S.lelbow, "relbow": S.relbow})
	var up := {"hips_rot": Vector3(-4, -8, 4), "hips_off": Vector3(-0.03, 0.02, -0.03), "lplant": 0.0,
		"lfoot": Vector3(0.26, 0.4, 0.12), "lpole": Vector3(0.8, 0.6, 0.6), "lpitch": -15.0,
		"lhand": S.lhand + Vector3(0, 0.03, 0), "rhand": S.rhand + Vector3(0, 0.03, 0)}
	return [
		stance,
		_merge(up, {"t": 0.07, "impact": true}),
		_merge(up, {"t": 0.38}),
		_merge(stance, {"t": 0.55}),
	]

func _base() -> Dictionary:
	return _guard_hands({"t": 0.0, "lfoot": S.lfoot, "rfoot": S.rfoot, "lpole": S.lpole, "rpole": S.rpole,
		"hips_off": Vector3.ZERO, "hips_rot": Vector3.ZERO, "spine_rot": Vector3.ZERO, "lpivot": 0.0, "rpivot": 0.0,
		"lpitch": 0.0, "rpitch": 0.0, "lplant": 1.0, "rplant": 1.0, "lelbow": S.lelbow, "relbow": S.relbow})

## Breathing fight stance (loops): a small bounce in the knees, hands bobbing with it.
func _idle() -> Array:
	var b := _base()
	var down := {"hips_off": Vector3(0, -0.025, 0), "lhand": S.lhand + Vector3(0, -0.015, 0),
		"rhand": S.rhand + Vector3(0, -0.02, 0), "spine_rot": Vector3(2, 0, 0)}
	return [b, _merge(b, _merge(down, {"t": 0.32})), _merge(b, {"t": 0.64})]

## High guard (held): gloves to the forehead, elbows tucked, chin down, slight crouch.
func _guard() -> Array:
	var g := _merge(_base(), {"hips_off": Vector3(0, -guard_crouch, 0), "spine_rot": Vector3(6, 0, 0),
		"lhand": guard_l, "rhand": guard_r, "lelbow": Vector3(0.3, -1, 0.2), "relbow": Vector3(-0.3, -1, 0.2)})
	return [_merge(_base(), {"t": 0.0}), _merge(g, {"t": 0.1}), _merge(g, {"t": 0.5})]

## A strike landing on the guard: knocked back a touch, then reset.
func _block_hit() -> Array:
	var g := _merge(_base(), {"hips_off": Vector3(0, -guard_crouch, 0), "spine_rot": Vector3(6, 0, 0),
		"lhand": guard_l, "rhand": guard_r, "lelbow": Vector3(0.3, -1, 0.2), "relbow": Vector3(-0.3, -1, 0.2)})
	return [_merge(g, {"t": 0.0}),
		_merge(g, {"t": 0.06, "impact": true, "hips_off": Vector3(0, -guard_crouch - 0.015, -0.07), "spine_rot": Vector3(-6, 0, 0),
			"lhand": guard_l + Vector3(0, 0, -0.06), "rhand": guard_r + Vector3(0, 0, -0.06)}),
		_merge(g, {"t": 0.3})]

## Straight rear knee: reach up as if grabbing, drive the right knee up and through while the hips push
## forward and the shoulders lean back, hands pulling down.
func _knee() -> Array:
	var b := _base()
	return [b,
		{"t": 0.11, "hips_rot": Vector3(-4, 40, 0), "hips_off": Vector3(0.0, 0.03, 0.08), "rplant": 0.0, "lpivot": 25.0,
			"rfoot": Vector3(-0.12, 0.3, -0.08), "rpole": Vector3(0, 0.4, 1), "rpitch": 30.0,
			"lhand": Vector3(0.14, 1.5, 0.5), "rhand": Vector3(-0.1, 1.5, 0.45)},
		{"t": 0.22, "impact": true, "hips_rot": Vector3(-16, 55, 0), "hips_off": Vector3(0.0, 0.07, 0.2), "lpivot": 40.0,
			"rfoot": Vector3(-0.02, 0.5, 0.18), "rpole": Vector3(0, 0.3, 1), "rpitch": 45.0,
			"lhand": Vector3(0.12, 1.25, 0.42), "rhand": Vector3(-0.08, 1.22, 0.38)},
		{"t": 0.34, "hips_rot": Vector3(-4, 25, 0), "hips_off": Vector3(0, 0.02, 0.06), "lpivot": 15.0,
			"rfoot": Vector3(-0.12, 0.3, -0.1), "rpole": Vector3(0, 0.4, 1), "rpitch": 20.0, "lhand": S.lhand, "rhand": S.rhand},
		_merge(b, {"t": 0.5})]

## Superman punch: drive the rear knee up, spring off the lead foot and, airborne, kick that leg back
## while the rear hand shoots straight out. (The game moves the fighter forward.)
func _superman_punch() -> Array:
	var b := _base()
	var up := 1.0 / rise_scale  # a leap needs its full height on either stance
	return [b,
		{"t": 0.11, "hips_off": Vector3(0, 0.07 * up, 0.06), "hips_rot": Vector3(0, -10, 0), "rplant": 0.0,
			"rfoot": Vector3(-0.12, 0.45, 0.14), "rpole": Vector3(0, 0.3, 1), "rpitch": 20.0,
			"lhand": S.lhand + Vector3(0, 0, 0.1), "rhand": Vector3(-0.22, 1.42, 0.0)},
		{"t": 0.24, "impact": true, "hips_off": Vector3(0, 0.14 * up, 0.12), "hips_rot": Vector3(10, 40, 0),
			"spine_rot": Vector3(6, 12, 0), "lplant": 0.0, "lfoot": Vector3(0.12, 0.26, 0.1), "lpole": Vector3(0, 0.3, 1),
			"lpitch": 20.0, "rfoot": Vector3(-0.2, 0.45, -0.65), "rpole": Vector3(0, -0.4, 1), "rpitch": 45.0,
			"lhand": Vector3(0.2, 1.38, 0.18), "rhand": Vector3(0.04, 1.62, 0.9), "relbow": Vector3(-1, -0.3, 0)},
		{"t": 0.37, "hips_off": Vector3(0, -0.05, 0.06), "hips_rot": Vector3(4, 15, 0), "spine_rot": Vector3(3, 4, 0),
			"lplant": 1.0, "lfoot": S.lfoot, "lpole": S.lpole, "lpitch": 0.0, "rplant": 1.0, "rfoot": S.rfoot,
			"rpole": S.rpole, "rpitch": 0.0, "lhand": S.lhand, "rhand": Vector3(-0.08, 1.45, 0.4), "relbow": S.relbow},
		_merge(b, {"t": 0.55})]

## A hop straight back out of range, hands staying up.
func _dash_back() -> Array:
	var b := _base()
	return [b,
		_merge(b, {"t": 0.12, "hips_off": Vector3(0, 0.05 / rise_scale, -0.07), "spine_rot": Vector3(-6, 0, 0),
			"lplant": 0.0, "rplant": 0.0, "lfoot": S.lfoot + Vector3(0, 0.14, 0.06), "rfoot": S.rfoot + Vector3(0, 0.07, -0.12)}),
		_merge(b, {"t": 0.26, "hips_off": Vector3(0, -0.04, -0.03)}),
		_merge(b, {"t": 0.4})]

## Rear uppercut: dip and drop the right hand to the ribs, then drive it up under the chin with the hip,
## elbow staying underneath. Short, so it still reads at twice the speed of the other power punches.
func _uppercut() -> Array:
	var b := _base()
	return [b,
		{"t": 0.06, "hips_off": Vector3(0, -0.05, 0.02), "hips_rot": Vector3(4, -12, 0), "spine_rot": Vector3(10, -12, 0),
			"rhand": S.rhand + Vector3(-0.08, -0.42, 0.04), "relbow": Vector3(-0.4, -1, -0.5)},
		{"t": 0.12, "impact": true, "hips_off": Vector3(0, 0.03, 0.07), "hips_rot": Vector3(-4, 30, 0), "rpivot": 25.0,
			"spine_rot": Vector3(-3, 16, 0), "rhand": S.rhand + Vector3(0.09, -0.04, 0.24), "relbow": Vector3(-0.15, -1, 0.35)},
		{"t": 0.18, "rhand": S.rhand + Vector3(0.11, 0.2, 0.2)},
		_merge(b, {"t": 0.32})]

## Rear hook: load the hip, then swing the right fist across at head height, elbow out level with it.
func _rear_hook() -> Array:
	var b := _base()
	return [b,
		{"t": 0.11, "hips_rot": Vector3(0, -12, 0), "spine_rot": Vector3(0, -16, 0),
			"rhand": S.rhand + Vector3(-0.22, 0.0, 0.08), "relbow": Vector3(-1, -0.3, -0.3)},
		{"t": 0.2, "impact": true, "hips_rot": Vector3(0, 38, 0), "hips_off": Vector3(0.02, 0, 0.05), "rpivot": 40.0,
			"spine_rot": Vector3(4, 24, 0), "rhand": S.rhand + Vector3(0.27, 0.0, 0.32), "relbow": Vector3(-1, 0.2, 0.1)},
		{"t": 0.27, "rhand": S.rhand + Vector3(0.44, -0.04, 0.16), "relbow": Vector3(-0.7, 0.1, 0.6)},
		_merge(b, {"t": 0.46})]

const PLUM_L := Vector3(0.1, 1.5, 0.5)
const PLUM_R := Vector3(-0.08, 1.5, 0.48)

func _clinch_base() -> Dictionary:
	return _merge(_base(), {"hips_rot": Vector3(8, 40, 0), "hips_off": Vector3(0, -0.02, 0.06),
		"lhand": PLUM_L, "rhand": PLUM_R, "lelbow": Vector3(0.2, -1, 0.3), "relbow": Vector3(-0.2, -1, 0.3)})

## Clinch (loops): squared up, both hands locked behind the opponent's head, elbows down, swaying.
func _clinch_hold() -> Array:
	var c := _clinch_base()
	return [_merge(c, {"t": 0.0}),
		_merge(c, {"t": 0.5, "hips_rot": Vector3(8, 46, 3), "hips_off": Vector3(0.03, -0.025, 0.06)}),
		_merge(c, {"t": 1.0})]

## Knee from the clinch: pull the head down, drive the rear knee up into the body.
func _clinch_knee() -> Array:
	var c := _clinch_base()
	return [_merge(c, {"t": 0.0}),
		_merge(c, {"t": 0.15, "impact": true, "hips_rot": Vector3(-12, 52, 0), "hips_off": Vector3(0, 0.05, 0.12),
			"rplant": 0.0, "rfoot": Vector3(-0.04, 0.45, 0.12), "rpole": Vector3(0, 0.3, 1), "rpitch": 40.0,
			"lhand": PLUM_L + Vector3(0, -0.18, -0.05), "rhand": PLUM_R + Vector3(0, -0.18, -0.05)}),
		_merge(c, {"t": 0.36})]

func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var d := a.duplicate()
	d.merge(b, true)
	return d

# --- baking ---------------------------------------------------------------------------------------

const PARAMS := ["hips_off", "hips_rot", "spine_rot", "lfoot", "rfoot", "lpole", "rpole", "lhand", "rhand",
	"lelbow", "relbow", "lpivot", "rpivot", "lpitch", "rpitch", "lplant", "rplant", "rfree", "rswing", "lcarry", "lpoint", "rpoint"]
const DEFAULTS := {"hips_off": Vector3.ZERO, "hips_rot": Vector3.ZERO, "spine_rot": Vector3.ZERO,
	"lpivot": 0.0, "rpivot": 0.0, "lpitch": 0.0, "rpitch": 0.0, "lplant": 1.0, "rplant": 1.0,
	"rfree": 0.0, "rswing": 0.0, "lcarry": 0.0, "lpoint": 0.0, "rpoint": 0.0}

func _bake(keys: Array) -> Animation:
	# Fill every parameter on every key (carry the previous key's value forward).
	var full: Array = []
	var prev := {}
	for p in PARAMS:
		prev[p] = DEFAULTS[p] if DEFAULTS.has(p) else S[p]
	for k in keys:
		var d := {"t": k.t}
		for p in PARAMS:
			var v = k.get(p, prev[p])
			d[p] = v if v is Vector3 else Vector3(v, 0, 0)
			prev[p] = k.get(p, prev[p])
		full.append(d)
	var length: float = full[-1].t
	var anim := Animation.new()
	anim.length = length
	anim.step = 1.0 / FPS
	var tracks := {}
	for b in sk.get_bone_count():
		var ti := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(ti, NodePath(SKEL_PATH + ":" + sk.get_bone_name(b)))
		tracks[b] = ti
	var hip_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hip_track, NodePath(SKEL_PATH + ":" + sk.get_bone_name(B.Hips)))
	var n := int(round(length * FPS))
	for f in n + 1:
		var t := minf(f / FPS, length)
		var P := _sample(full, t)
		_solve(P)
		if OS.get_cmdline_user_args().has("--debug") and absf(t - 0.3) < 0.009:
			var hz := sk.get_bone_global_pose(B.Hips).basis.z
			print("  t=%.2f hips fwd %s  Rfoot %s (target %s)  Lfoot %s  hips_rot %s" % [t, hz.snapped(Vector3.ONE * 0.01),
				(_g("RightFoot").origin - C).snapped(Vector3.ONE * 0.01), P.rfoot.snapped(Vector3.ONE * 0.01),
				(_g("LeftFoot").origin - C).snapped(Vector3.ONE * 0.01), P.hips_rot.snapped(Vector3.ONE * 0.1)])
		for b in sk.get_bone_count():
			anim.rotation_track_insert_key(tracks[b], t, sk.get_bone_pose_rotation(b))
		anim.position_track_insert_key(hip_track, t, sk.get_bone_pose_position(B.Hips))
	return anim

## Smooth (Catmull-Rom in time) interpolation of every parameter.
func _sample(keys: Array, t: float) -> Dictionary:
	var i := 0
	while i < keys.size() - 2 and t > keys[i + 1].t:
		i += 1
	var k0: Dictionary = keys[maxi(i - 1, 0)]
	var k1: Dictionary = keys[i]
	var k2: Dictionary = keys[i + 1]
	var k3: Dictionary = keys[mini(i + 2, keys.size() - 1)]
	var w := clampf((t - k1.t) / maxf(k2.t - k1.t, 1e-5), 0.0, 1.0)
	var out := {}
	for p in PARAMS:
		var a: Vector3 = k1[p]
		out[p] = a.cubic_interpolate_in_time(k2[p], k0[p], k3[p], w, k2.t - k1.t,
				minf(k0.t - k1.t, -1e-3), maxf(k3.t - k1.t, k2.t - k1.t + 1e-3))
	return out

# --- pose solve (skeleton space) ------------------------------------------------------------------

func _g(short: String) -> Transform3D:
	return sk.get_bone_global_pose(B[short])

func _set_global_basis(b: int, basis: Basis) -> void:
	var p := sk.get_bone_parent(b)
	var parent := sk.get_bone_global_pose(p).basis if p >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(b, (parent.inverse() * basis).orthonormalized().get_rotation_quaternion())
	sk.force_update_all_bone_transforms()

func _rot(deg: Vector3) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z)), EULER_ORDER_YXZ)

func _bend_dir(a: String, b: String, c: String) -> Vector3:
	var pa := _g(a).origin
	var pb := _g(b).origin
	var pc := _g(c).origin
	var mid := (pa + pc) * 0.5
	return (pb - mid).normalized()

func _solve(P: Dictionary) -> void:
	for b in sk.get_bone_count():
		sk.set_bone_pose_rotation(b, stance_local[b][0])
		sk.set_bone_pose_position(b, stance_local[b][1])
	sk.force_update_all_bone_transforms()
	# Hips: lift/shift + rotation about the model axes.
	var hs: Transform3D = stance_global[B.Hips]
	# Yaw first, then lean in WORLD axes (x < 0 leans back, away from the target at +Z; z rolls sideways),
	# so "lean away" means the same thing however far the hips have turned.
	var hr := _rot(Vector3(P.hips_rot.x, 0, P.hips_rot.z)) * _rot(Vector3(0, P.hips_rot.y, 0))
	var off: Vector3 = P.hips_off
	if off.y > 0.0:
		off.y *= rise_scale
	sk.set_bone_pose_position(B.Hips, hs.origin + off)
	sk.set_bone_pose_rotation(B.Hips, (hr * hs.basis).get_rotation_quaternion())
	sk.force_update_all_bone_transforms()
	# Spine twist/lean spread over three vertebrae.
	var part := _rot(P.spine_rot / 3.0)
	for s in ["Spine", "Spine1", "Spine2"]:
		_set_global_basis(B[s], part * _g(s).basis)
	sk.force_update_all_bone_transforms()
	# Keep the eyes on the target: neck/head take back most of the torso's yaw and lean.
	var tot: Vector3 = P.hips_rot + P.spine_rot
	var counter := _rot(Vector3(-tot.x * 0.45, -tot.y * 0.35, -tot.z * 0.5))
	for s in ["Neck", "Head"]:
		_set_global_basis(B[s], counter * _g(s).basis)
	sk.force_update_all_bone_transforms()
	# Legs.
	for side in ["Left", "Right"]:
		var k: String = side.left(1).to_lower()
		var foot: int = B[side + "Foot"]
		var stance_foot: Basis = stance_global[foot].basis
		_two_bone(B[side + "UpLeg"], B[side + "Leg"], foot, C + P[k + "foot"], hr * P[k + "pole"])
		# Foot: planted = flat on the canvas, pivoting on the ball; free = follows the shin + toe point.
		var planted := _rot(Vector3(0, P[k + "pivot"].x, 0)) * stance_foot
		var shin := _g(side + "Leg")
		var free: Basis = shin.basis * stance_global[B[side + "Leg"]].basis.inverse() * stance_foot
		var hinge := (shin.basis.x).normalized()
		free = Basis(hinge, deg_to_rad(P[k + "pitch"].x)) * free
		free = _point_foot(side, clampf(P[k + "point"].x, 0.0, 1.0), free)
		var plant := clampf(P[k + "plant"].x, 0.0, 1.0)
		var q: Quaternion = free.get_rotation_quaternion().slerp(planted.get_rotation_quaternion(), plant)
		_set_global_basis(foot, Basis(q))
	sk.force_update_all_bone_transforms()
	# Arms.
	for side in ["Left", "Right"]:
		var k: String = side.left(1).to_lower()
		if side == "Right" and P.rfree.x > 0.5:
			_swing_arm(side, clampf(P.rswing.x, 0.0, 1.0), hr)
		else:
			_two_bone(B[side + "Arm"], B[side + "ForeArm"], B[side + "Hand"], C + P[k + "hand"], hr * P[k + "elbow"])
	# A guard hand placed in space would have to reach through the chest once the torso has turned over,
	# so there it goes back to the stance guard and turns with the body.
	var carry := clampf(P.lcarry.x, 0.0, 1.0)
	if carry > 0.0:
		for b in [B.LeftArm, B.LeftForeArm]:
			var placed := sk.get_bone_pose_rotation(b)
			sk.set_bone_pose_rotation(b, placed.slerp(stance_local[b][0], carry))
	sk.force_update_all_bone_transforms()

## Turn a free foot so it carries on the line of the shin (toes pointed away from the body), by weight w.
func _point_foot(side: String, w: float, free: Basis) -> Basis:
	if w <= 0.0:
		return free
	var ankle := _g(side + "Foot").origin
	var shin := (ankle - _g(side + "Leg").origin).normalized()
	var stance_foot: Transform3D = stance_global[B[side + "Foot"]]
	var bone: Vector3 = (stance_global[B[side + "ToeBase"]].origin - stance_foot.origin).normalized()
	# The ankle-to-toes bone slopes down inside a flat foot, so lining the bone up with the shin still looks
	# bent: line up a direction halfway between it and the sole.
	var foot_line := (bone + Vector3(bone.x, 0, bone.z).normalized()).normalized()
	var toes := (free * (stance_foot.basis.inverse() * foot_line)).normalized()
	var angle := toes.angle_to(shin)
	var rest := deg_to_rad(FOOT_POINT_ANGLE)
	if angle <= rest:
		return free
	var axis := toes.cross(shin).normalized()
	return Basis(axis, (angle - rest) * w) * free

## A kick's counter-swing: w 0 = the arm stays in the stance guard (carried by the torso), w 1 = it hangs
## down in front, on the kicking leg's side (below the thigh, toward the opponent). Blending the joint
## rotations moves it along one arc; placing the hand in space instead made the elbow flip mid-kick.
func _swing_arm(side: String, w: float, hr: Basis) -> void:
	var arm: int = B[side + "Arm"]
	var fore: int = B[side + "ForeArm"]
	var shoulder := _g(side + "Arm").origin
	var elbow := _g(side + "ForeArm").origin
	var length := shoulder.distance_to(elbow) + elbow.distance_to(_g(side + "Hand").origin)
	var dir: Vector3 = (Vector3.DOWN + SWING_DRIFT[side]).normalized()
	_two_bone(arm, fore, B[side + "Hand"], shoulder + dir * length * 0.95, hr * Vector3(0, 0, -1))
	for b in [arm, fore]:
		var hang := sk.get_bone_pose_rotation(b)
		sk.set_bone_pose_rotation(b, (stance_local[b][0] as Quaternion).slerp(hang, w))
	sk.force_update_all_bone_transforms()

## Two-bone IK. Rotates bone a so the a->b->c chain's bend plane faces `pole`, then bends b (a hinge
## about the plane normal) so c reaches `target`. Bones keep their own twist (no candy-wrapping).
func _two_bone(a: int, b: int, c: int, target: Vector3, pole: Vector3) -> void:
	sk.force_update_all_bone_transforms()
	var pa := sk.get_bone_global_pose(a).origin
	var pb := sk.get_bone_global_pose(b).origin
	var pc := sk.get_bone_global_pose(c).origin
	var l1 := pa.distance_to(pb)
	var l2 := pb.distance_to(pc)
	var d := target - pa
	var dist := clampf(d.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.005)
	var dn := d.normalized()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var pdir := (pole - dn * pole.dot(dn))
	pdir = pdir.normalized() if pdir.length() > 1e-4 else dn.cross(Vector3.RIGHT).normalized()
	var knee := pa + dn * cos_a * l1 + pdir * sin_a * l1
	var end := pa + dn * dist
	var t0 := (pb - pa).normalized()
	var s0 := (pc - pb).normalized()
	var n0 := t0.cross(s0)
	n0 = n0.normalized() if n0.length() > 1e-4 else t0.cross(pdir).normalized()
	var t1 := (knee - pa).normalized()
	var s1 := (end - knee).normalized()
	var n1 := t1.cross(s1)
	n1 = n1.normalized() if n1.length() > 1e-4 else n0
	var f0 := Basis(t0, n0, t0.cross(n0))
	var f1 := Basis(t1, n1, t1.cross(n1))
	var r := f1 * f0.inverse()
	_set_global_basis(a, (r * sk.get_bone_global_pose(a).basis).orthonormalized())
	sk.force_update_all_bone_transforms()
	var pb2 := sk.get_bone_global_pose(b).origin
	var pc2 := sk.get_bone_global_pose(c).origin
	var cur := (pc2 - pb2).normalized()
	var ang := cur.signed_angle_to(s1, n1)
	_set_global_basis(b, (Basis(n1, ang) * sk.get_bone_global_pose(b).basis).orthonormalized())
	sk.force_update_all_bone_transforms()
