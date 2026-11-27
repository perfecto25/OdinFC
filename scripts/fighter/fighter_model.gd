class_name FighterModel
extends Node3D
## The rigged character for a Fighter: Mixamo "Beta" mesh + one shared library of clips (Mixamo motion
## capture where it exists, generated clips from tools/gen_anims.gd for the Muay Thai techniques).
##
## Purely visual. Fighter calls update() once per 60 Hz tick; the AnimationPlayer runs in MANUAL mode and
## is advanced by exactly one frame per tick, so animation stays locked to the simulation.
## Strikes are time-warped: the clip's impact moment lands on the move's first active frame (after fatigue
## scaling), and the rest of the clip is fitted into active + recovery.

const CHARACTER := "res://assets/mixamo/character.fbx"
const MIXAMO := "res://assets/mixamo/src/%s.fbx"
const GENERATED := "res://assets/anim/generated/%s.res"
const BLEND := 0.08        ## seconds of cross-fade between clips
const ATTACK_BLEND := 0.04

## name -> [source, start, end, impact, loop, keep_drift]. source "gen:x" = generated; impact -1 = from the
## clip's meta. start/end cut a section out of a longer Mixamo take (end -1 = to the end). keep_drift (optional):
## keep the take's travel (falls land where they land) instead of removing it.
const CLIPS := {
	"idle": ["gen:idle", 0.0, -1.0, -1.0, true],
	"guard": ["gen:guard", 0.0, -1.0, -1.0, false],
	"block_hit": ["gen:block_hit", 0.0, -1.0, -1.0, false],
	"jab": ["jab_cross", 0.0, 0.62, 0.40, false],
	"cross": ["jab_cross", 0.45, 1.95, 0.63, false],
	"lead_hook": ["hook_3", 0.0, 1.98, 0.50, false],
	"rear_hook": ["hook_2", 0.35, 1.25, 0.90, false],
	"uppercut": ["uppercut_jab", 0.95, 1.95, 1.40, false],
	"teep": ["gen:teep", 0.0, -1.0, -1.0, false],
	"side_kick": ["gen:side_kick", 0.0, -1.0, -1.0, false],
	"round_kick_low": ["gen:round_kick_low", 0.0, -1.0, -1.0, false],
	"round_kick_body": ["gen:round_kick_body", 0.0, -1.0, -1.0, false],
	"round_kick_high": ["gen:round_kick_high", 0.0, -1.0, -1.0, false],
	"knee": ["gen:knee", 0.0, -1.0, -1.0, false],
	"check": ["gen:check", 0.0, -1.0, -1.0, false],
	"clinch": ["gen:clinch", 0.0, -1.0, -1.0, true],
	"clinch_knee": ["gen:clinch_knee", 0.0, -1.0, -1.0, false],
	"sweep": ["leg_sweep", 0.0, -1.0, 0.7, false],
	"hit_head": ["medium_hit_to_head", 0.0, -1.0, 0.0, false],
	"hit_body": ["stomach_hit", 0.0, -1.0, 0.0, false],
	"stagger": ["big_hit_to_head", 0.0, -1.0, 0.0, false],
	# One Mixamo take holds both halves: down to the knees by 0.7 s, back up from 1.5 s.
	"knockdown": ["livershot_knockdown", 0.0, 1.2, 0.0, false],
	"rise": ["livershot_knockdown", 1.4, -1.0, 0.0, false],
	# Fights that end on the canvas: flat on the back from head shots, folding forward from body shots.
	"ko_back": ["falling_back_death", 0.0, -1.0, 0.0, false, true],
	"ko_forward": ["dying", 0.0, -1.0, 0.0, false, true],
	# Swept: dumped on the back, then up from the canvas.
	"swept": ["falling_back_death_2", 0.0, 1.6, 0.0, false, true],
	"get_up_back": ["getting_up_2", 0.0, -1.0, 0.0, false],
	# Fight-stance footwork: continuous walk cycles where we have them, a step-drag going forward.
	"step_f": ["short_step_forward", 0.0, -1.0, 0.0, true],
	"step_b": ["walking_backwards", 0.0, -1.0, 0.0, true],
	"step_l": ["walking_2", 0.0, -1.0, 0.0, true],
	"step_r": ["walking", 0.0, -1.0, 0.0, true],
	"victory": ["victory", 0.0, -1.0, 0.0, true],
	"defeat": ["defeat", 0.0, -1.0, 0.0, false],
}
## Fighter move id -> clip (moves without an entry use the clip of the same name).
const MOVE_CLIP := {&"clinch": "jab", &"clinch_knee": "clinch_knee", &"clinch_knee_body": "clinch_knee",
	&"clinch_knee_head": "clinch_knee"}

static var _library: AnimationLibrary
static var _impacts := {}
static var _travel := {}    ## metres per second the clip's hips travel (footwork playback-speed matching)

var override_clip := ""     ## set at the end of the fight (victory / defeat)
var skeleton: Skeleton3D
var _ap: AnimationPlayer
var _clip := ""
var _move: MoveData
var _overlay: StandardMaterial3D
var _flash_frames := 0
var _was_down := false
var _down_clip := ""
var _rising := false
## Head movement: a procedural lean of the spine layered over whatever clip plays, in the fighter's frame
## (x = sideways, + = fighter's right; y = forward), radians of total spine bend. Slips drive it hard;
## idle / footwork / guard weave it gently so the head never sits still on the centre line.
const SPINE := ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Neck"]
const SPINE_SHARE := [0.22, 0.28, 0.3, 0.2]
const SLIP_LEAN := Vector2(0.55, 0.3)
var _weave := Vector2.ZERO
var _weave_t := 0.0
var _weave_seed := 0.0
var _spine_ids: Array[int] = []
var _spine_rest: Array[Quaternion] = []  ## pose before the lean, restored before the next clip frame

func setup(color: Color) -> void:
	var ch: Node3D = load(CHARACTER).instantiate()
	add_child(ch)
	ch.rotation.y = PI  # Mixamo faces +Z; fighters face -Z
	skeleton = ch.get_node("Skeleton3D")
	var old := ch.get_node_or_null("AnimationPlayer")
	if old:
		old.queue_free()
		ch.remove_child(old)
	_ap = AnimationPlayer.new()
	_ap.name = "Anim"
	ch.add_child(_ap)
	_ap.root_node = NodePath("..")
	_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_ap.add_animation_library("", library())
	_dress(color)
	_play("idle", 0.0)
	for n in SPINE:
		_spine_ids.append(skeleton.find_bone(n))
	_weave_seed = color.h * 37.0  # the two corners weave out of phase

## Corner colour on the joint rings + gloves, and a hit-flash overlay on everything.
func _dress(color: Color) -> void:
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.albedo_color = Color(1, 1, 1, 0)
	for mi in skeleton.get_children():
		if mi is MeshInstance3D:
			var m: StandardMaterial3D = (mi as MeshInstance3D).mesh.surface_get_material(0).duplicate()
			if mi.name.contains("Joints"):
				m.albedo_color = color
			m.roughness = 0.6
			mi.set_surface_override_material(0, m)
			mi.material_overlay = _overlay
	for side in ["Left", "Right"]:
		var ba := BoneAttachment3D.new()
		ba.bone_name = "mixamorig_%sHand" % side
		skeleton.add_child(ba)
		var glove := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.075
		s.height = 0.15
		glove.mesh = s
		glove.position = Vector3(0, 0.07, 0.02)
		var gm := StandardMaterial3D.new()
		gm.albedo_color = color
		gm.roughness = 0.35
		glove.material_override = gm
		glove.material_overlay = _overlay
		ba.add_child(glove)

## Roster look: skin tone on the body surfaces (the joint rings and gloves keep the corner colour).
## Shorts, hair, armbands etc. in FighterData need a real character model (art pass).
func apply_look(d: FighterData) -> void:
	for mi in skeleton.get_children():
		if mi is MeshInstance3D and not mi.name.contains("Joints"):
			var m := (mi as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
			if m:
				m.albedo_color = d.skin_tone

func flash(c: Color) -> void:
	_overlay.albedo_color = Color(c, 0.55)
	_flash_frames = 6

## One 60 Hz tick: pick the clip for the fighter's state, warp strikes onto their frame data, advance.
func update(f: Fighter) -> void:
	if _flash_frames > 0:
		_flash_frames -= 1
		if _flash_frames == 0:
			_overlay.albedo_color = Color(1, 1, 1, 0)
	var speed := 1.0
	var down := f.is_down()
	if _was_down and not down:
		_rising = true  # back on the feet: play the get-up that matches how they went down
		_play("get_up_back" if _down_clip == "swept" else "rise", 0.25 if _down_clip == "swept" else 0.1)
	_was_down = down
	if _rising and (f.state not in [Fighter.State.IDLE, Fighter.State.MOVE] or _clip not in ["rise", "get_up_back"] \
			or _ap.current_animation_position >= _ap.current_animation_length - 0.02):
		_rising = false
	if _rising:
		speed = 1.2
	elif override_clip != "" and not down:
		_play(override_clip, 0.3)
	else:
		match f.state:
			Fighter.State.IDLE:
				_play("idle", BLEND)
			Fighter.State.MOVE:
				_play(_step_clip(f), 0.15)
				# Match the stride to the actual ground speed (within reason) so feet slide less.
				var v := Vector2(f.velocity.x, f.velocity.z).length()
				speed = clampf(v / maxf(_travel.get(_clip, 0.5), 0.1), 0.8, 2.5)
			Fighter.State.GUARD, Fighter.State.SLIP:
				_play("guard", 0.06)
			Fighter.State.ATTACK:
				if f.current_move != _move or f.state_frame <= 1:
					_move = f.current_move
					_play(String(MOVE_CLIP.get(_move.id, String(_move.id))), ATTACK_BLEND, true)
				var tm := f.attack_timing()
				speed = _warp(f.state_frame, tm.x, tm.y + tm.z)
			Fighter.State.CHECK:
				_play("check", ATTACK_BLEND, f.state_frame <= 1)
				speed = _warp(f.state_frame, Fighter.CHECK_STARTUP, Fighter.CHECK_ACTIVE + Fighter.CHECK_RECOVERY)
			Fighter.State.HITSTUN:
				_play("hit_head" if f.last_hit_zone == MoveData.Zone.HEAD else "hit_body", 0.04, f.state_frame <= 1)
				speed = 1.4
			Fighter.State.BLOCKSTUN:
				_play("block_hit", 0.03, f.state_frame <= 1)
			Fighter.State.STAGGER:
				_play("stagger", 0.05, f.state_frame <= 1)
				speed = 1.3
			Fighter.State.CLINCH:
				var act: StringName = f.clinch.current_action(f.clinch.index_of(f)) if f.clinch else &""
				match act:
					&"knee":
						_play("clinch_knee", 0.05)
						speed = 1.2
					&"sweep":
						_play("sweep", 0.05)
						speed = 1.6
					_:
						_play("clinch", 0.15)
			Fighter.State.SWEPT:
				_down_clip = "swept"
				_play("swept", 0.06)
				speed = 1.3
			Fighter.State.KNOCKDOWN, Fighter.State.KO:
				# FightFlow flags a knockdown that won't beat the count one tick after the hit: fall flat.
				if f.stays_down:
					_down_clip = "ko_forward" if f.last_knockdown_zone == MoveData.Zone.BODY else "ko_back"
					_play(_down_clip, 0.12)
				else:
					_down_clip = "knockdown"
					_play("knockdown", 0.1)
					speed = 1.3
	_ap.speed_scale = speed
	for k in _spine_rest.size():
		skeleton.set_bone_pose_rotation(_spine_ids[k], _spine_rest[k])
	_spine_rest.clear()
	_ap.advance(1.0 / 60.0)
	_apply_weave(f)

func _weave_target(f: Fighter) -> Vector2:
	_weave_t += 1.0 / 60.0
	var t := _weave_t + _weave_seed
	var bob := Vector2(0.17 * sin(t * TAU * 0.55) + 0.07 * sin(t * TAU * 1.35 + 1.7),
			0.05 + 0.05 * sin(t * TAU * 0.8 + 0.6))
	match f.state:
		Fighter.State.SLIP:
			var p := f.state_frame
			var w := 1.0
			if p <= Fighter.SLIP_STARTUP:
				w = float(p) / Fighter.SLIP_STARTUP
			elif p > Fighter.SLIP_STARTUP + Fighter.SLIP_ACTIVE:
				w = 1.0 - float(p - Fighter.SLIP_STARTUP - Fighter.SLIP_ACTIVE) / Fighter.SLIP_RECOVERY
			w = smoothstep(0.0, 1.0, clampf(w, 0.0, 1.0))
			return Vector2(SLIP_LEAN.x * f.slip_side, SLIP_LEAN.y) * w
		Fighter.State.IDLE:
			return bob
		Fighter.State.MOVE:
			return bob * 0.8
		Fighter.State.GUARD:
			return Vector2(bob.x * 0.35, 0.12)  # tucked behind the gloves, still swaying a little
	return Vector2.ZERO

## Lean the spine chain toward the target, each bone taking its share, rotating about axes in the
## fighter's frame (converted to skeleton space, then to each bone's parent space).
func _apply_weave(f: Fighter) -> void:
	var target := _weave_target(f)
	var rate := 0.35 if f.state == Fighter.State.SLIP else 0.12
	_weave = _weave.lerp(target, rate)
	if _weave.length() < 0.002 or _spine_ids.has(-1):
		return
	var inv := skeleton.global_basis.orthonormalized().inverse()
	var up := (inv * Vector3.UP).normalized()
	var right := (inv * f.global_basis.x).normalized()
	var fwd := (inv * -f.global_basis.z).normalized()
	var total := Quaternion(up, (up + right * tan(_weave.x) + fwd * tan(_weave.y)).normalized())
	for k in _spine_ids.size():
		var b := _spine_ids[k]
		var local := skeleton.get_bone_pose_rotation(b)
		_spine_rest.append(local)
		var pg := skeleton.get_bone_global_pose(skeleton.get_bone_parent(b)).basis.get_rotation_quaternion()
		var q := Quaternion.IDENTITY.slerp(total, SPINE_SHARE[k])
		skeleton.set_bone_pose_rotation(b, (pg.inverse() * q * pg * local).normalized())

## Playback speed that puts the clip's impact on the first active frame, then fits the rest of the clip
## into the remaining frames.
func _warp(frame: int, startup: int, after: int) -> float:
	var impact: float = _impacts.get(_clip, 0.0)
	var length := _ap.current_animation_length
	if frame <= startup:
		return clampf(impact / (maxi(startup, 1) / 60.0), 0.2, 6.0)
	return clampf((length - impact) / (maxi(after, 1) / 60.0), 0.2, 6.0)

func _step_clip(f: Fighter) -> String:
	var mv := f.get_move_input()
	var local := f.global_basis.inverse() * Vector3(mv.x, 0, mv.y)  # fighter faces -Z
	if absf(local.z) >= absf(local.x):
		return "step_f" if local.z < 0.0 else "step_b"
	return "step_r" if local.x > 0.0 else "step_l"

func _play(name: String, blend: float, restart := false) -> void:
	if name == _clip and not restart:
		return
	_clip = name
	if restart and _ap.current_animation == name:
		_ap.stop(true)
	_ap.play(name, blend)

# --- shared clip library ---

static func library() -> AnimationLibrary:
	if _library:
		return _library
	_library = AnimationLibrary.new()
	for name in CLIPS:
		var spec: Array = CLIPS[name]
		var src: String = spec[0]
		var anim: Animation
		var impact: float = spec[3]
		if src.begins_with("gen:"):
			anim = (load(GENERATED % src.trim_prefix("gen:")) as Animation).duplicate(true)
			if impact < 0.0:
				impact = anim.get_meta("impact", 0.0)
		else:
			var scn: Node = load(MIXAMO % src).instantiate()
			var ap: AnimationPlayer = scn.get_node("AnimationPlayer")
			var names := ap.get_animation_list()
			var a: Animation = ap.get_animation(&"mixamo_com" if names.has(&"mixamo_com") else names[0])
			anim = _section(a, spec[1], a.length if spec[2] < 0.0 else spec[2])
			impact = maxf(impact - spec[1], 0.0)
			scn.free()
		_travel[name] = _hip_travel(anim) / maxf(anim.length, 0.01)
		_ground_root(anim, spec.size() > 5 and spec[5])
		anim.loop_mode = Animation.LOOP_LINEAR if spec[4] else Animation.LOOP_NONE
		_library.add_animation(name, anim)
		_impacts[name] = impact
	return _library

## Copy [start, end] of a clip into a new clip starting at 0.
static func _section(a: Animation, start: float, end: float) -> Animation:
	var out := Animation.new()
	out.length = end - start
	out.step = a.step
	for i in a.get_track_count():
		var ty := a.track_get_type(i)
		if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D:
			continue
		var t := out.add_track(ty)
		out.track_set_path(t, a.track_get_path(i))
		var times := [start]
		for k in a.track_get_key_count(i):
			var kt := a.track_get_key_time(i, k)
			if kt > start + 1e-4 and kt < end - 1e-4:
				times.append(kt)
		times.append(end)
		for kt in times:
			if ty == Animation.TYPE_ROTATION_3D:
				out.rotation_track_insert_key(t, kt - start, a.rotation_track_interpolate(i, kt))
			else:
				out.position_track_insert_key(t, kt - start, a.position_track_interpolate(i, kt))
	return out

static func _hip_travel(anim: Animation) -> float:
	for i in anim.get_track_count():
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D and String(anim.track_get_path(i)).ends_with("Hips"):
			var n := anim.track_get_key_count(i)
			if n < 2:
				return 0.0
			var d: Vector3 = anim.track_get_key_value(i, n - 1) - anim.track_get_key_value(i, 0)
			return Vector2(d.x, d.z).length()
	return 0.0

## Mixamo takes wander (no "In Place" versions): put the hips over the origin at the start and remove the
## net drift across the clip, keeping the motion within it (lunges, weight shifts, falls).
static func _ground_root(anim: Animation, keep_drift := false) -> void:
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D or not String(anim.track_get_path(i)).ends_with("Hips"):
			continue
		var n := anim.track_get_key_count(i)
		if n == 0:
			return
		var first: Vector3 = anim.track_get_key_value(i, 0)
		var last: Vector3 = anim.track_get_key_value(i, n - 1)
		var drift := Vector3.ZERO if keep_drift else Vector3(last.x - first.x, 0, last.z - first.z)
		for k in n:
			var v: Vector3 = anim.track_get_key_value(i, k)
			var w := anim.track_get_key_time(i, k) / maxf(anim.length, 1e-4)
			v.x -= first.x + drift.x * w
			v.z -= first.z + drift.z * w
			anim.track_set_key_value(i, k, v)
		return
