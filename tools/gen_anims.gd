extends SceneTree
## Generates the Muay Thai techniques Mixamo doesn't have (round kicks, teep, side kick, check) as
## Animation resources on the Mixamo skeleton, from the fight stance.
##   godot --headless --path . -s tools/gen_anims.gd            -> assets/anim/generated/<name>.res
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
const FPS := 60.0
const SKEL_PATH := "Skeleton3D"

var sk: Skeleton3D
var stance_local: Array = []     ## [Quaternion rot, Vector3 pos] per bone
var stance_global: Array = []    ## Transform3D per bone (skeleton space)
var C := Vector3.ZERO            ## ground point under the stance hips
var S := {}                      ## stance targets (C-relative): lfoot, rfoot, lhand, rhand, poles
var B := {}                      ## bone indices by short name

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
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var techniques := {
		"round_kick_body": _round_kick(1.0, 0.0),
		"round_kick_high": _round_kick(1.42, 1.0),
		"round_kick_low": _round_kick(0.48, -1.0),
		"teep": _teep(),
		"side_kick": _side_kick(),
		"check": _check(),
		"idle": _idle(),
		"guard": _guard(),
		"block_hit": _block_hit(),
		"knee": _knee(),
		"clinch": _clinch_hold(),
		"clinch_knee": _clinch_knee(),
	}
	for name in techniques:
		var keys: Array = techniques[name]
		var anim := _bake(keys)
		var impact := 0.0
		for k in keys:
			if k.get("impact", false):
				impact = k.t
		anim.set_meta("impact", impact)
		if name in ["idle", "clinch"]:
			anim.loop_mode = Animation.LOOP_LINEAR
		var path: String = OUT_DIR + name + ".res"
		ResourceSaver.save(anim, path)
		print("saved %s  length %.2fs  impact %.2fs" % [path, anim.length, impact])
	quit()

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
		"rpitch": 0.0, "rplant": 1.0, "lelbow": S.lelbow, "relbow": S.relbow})
	return [
		stance,
		{"t": 0.09, "hips_rot": Vector3(-4, 45, 0), "hips_off": Vector3(0.03, rise * 0.5, 0.04), "spine_rot": Vector3(0, -8, 0),
			"lpivot": 35.0, "rfoot": Vector3(-0.22, 0.32 + 0.1 * tier, -0.12), "rpole": Vector3(0, 0.3, 1), "rplant": 0.0,
			"rpitch": 20.0, "rhand": Vector3(-0.22, 1.05, 0.05), "lhand": S.lhand + Vector3(0.0, 0.05, 0.05)},
		{"t": 0.2, "hips_rot": Vector3(lean * 0.6, yaw * 0.7, 0), "hips_off": Vector3(0.06, rise, 0.07),
			"spine_rot": Vector3(0, -10, 0), "lpivot": 75.0,
			"rfoot": Vector3(-0.2, h * 0.85, reach * 0.5), "rpole": Vector3(0, 0.4, 1), "rpitch": 35.0,
			"rhand": Vector3(-0.3, 0.85, -0.2), "lhand": Vector3(0.12, 1.42, 0.3)},
		{"t": 0.3, "impact": true, "hips_rot": Vector3(lean, yaw, 0), "hips_off": Vector3(0.08, rise, 0.08),
			"spine_rot": Vector3(0, -12, 0), "lpivot": 95.0,
			"rfoot": Vector3(0.5, h, reach), "rpole": Vector3(0, 0.4, 1), "rpitch": 40.0,
			"rhand": Vector3(-0.28, 0.8, -0.38), "lhand": Vector3(0.18, 1.45, 0.32), "relbow": Vector3(-0.3, 0, -1)},
		{"t": 0.42, "hips_rot": Vector3(lean * 0.5, yaw * 0.55, 0), "hips_off": Vector3(0.04, rise * 0.6, 0.04),
			"spine_rot": Vector3(0, -6, 0), "lpivot": 60.0,
			"rfoot": Vector3(-0.15, 0.4 + 0.15 * tier, 0.05), "rpole": Vector3(0, 0.3, 1), "rpitch": 20.0,
			"rhand": Vector3(-0.2, 1.05, 0.05), "lhand": S.lhand + Vector3(0, 0.05, 0), "relbow": S.relbow},
		_merge(stance, {"t": 0.62}),
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

const GUARD_L := Vector3(0.07, 1.47, 0.27)
const GUARD_R := Vector3(-0.1, 1.46, 0.16)

## High guard (held): gloves to the forehead, elbows tucked, chin down, slight crouch.
func _guard() -> Array:
	var g := _merge(_base(), {"hips_off": Vector3(0, -0.035, 0), "spine_rot": Vector3(6, 0, 0),
		"lhand": GUARD_L, "rhand": GUARD_R, "lelbow": Vector3(0.3, -1, 0.2), "relbow": Vector3(-0.3, -1, 0.2)})
	return [_merge(_base(), {"t": 0.0}), _merge(g, {"t": 0.1}), _merge(g, {"t": 0.5})]

## A strike landing on the guard: knocked back a touch, then reset.
func _block_hit() -> Array:
	var g := _merge(_base(), {"hips_off": Vector3(0, -0.035, 0), "spine_rot": Vector3(6, 0, 0),
		"lhand": GUARD_L, "rhand": GUARD_R, "lelbow": Vector3(0.3, -1, 0.2), "relbow": Vector3(-0.3, -1, 0.2)})
	return [_merge(g, {"t": 0.0}),
		_merge(g, {"t": 0.06, "impact": true, "hips_off": Vector3(0, -0.05, -0.07), "spine_rot": Vector3(-6, 0, 0),
			"lhand": GUARD_L + Vector3(0, 0, -0.06), "rhand": GUARD_R + Vector3(0, 0, -0.06)}),
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
	"lelbow", "relbow", "lpivot", "rpivot", "lpitch", "rpitch", "lplant", "rplant"]
const DEFAULTS := {"hips_off": Vector3.ZERO, "hips_rot": Vector3.ZERO, "spine_rot": Vector3.ZERO,
	"lpivot": 0.0, "rpivot": 0.0, "lpitch": 0.0, "rpitch": 0.0, "lplant": 1.0, "rplant": 1.0}

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
	sk.set_bone_pose_position(B.Hips, hs.origin + P.hips_off)
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
		var plant := clampf(P[k + "plant"].x, 0.0, 1.0)
		var q: Quaternion = free.get_rotation_quaternion().slerp(planted.get_rotation_quaternion(), plant)
		_set_global_basis(foot, Basis(q))
	sk.force_update_all_bone_transforms()
	# Arms.
	for side in ["Left", "Right"]:
		var k: String = side.left(1).to_lower()
		_two_bone(B[side + "Arm"], B[side + "ForeArm"], B[side + "Hand"], C + P[k + "hand"], hr * P[k + "elbow"])
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
