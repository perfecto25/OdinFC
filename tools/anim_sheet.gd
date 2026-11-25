extends SceneTree
## Contact sheet of an animation drawn on a capsule mannequin built from the Mixamo skeleton.
##   godot --path . -s tools/anim_sheet.gd -- --clip=res://assets/mixamo/src/kicking.fbx --out=/dir/sheet.png
##   --clip may also be a generated Animation resource (.res/.tres); it plays on the base skeleton.
## Options: --frames=8 (columns), --views=side,front (one row per view). Needs a display (not --headless).

const BASE := "res://assets/mixamo/src/standing_idle.fbx"
const CELL := Vector2i(260, 340)
const SKIP := ["Thumb", "Index", "Middle", "Ring", "Pinky", "_End", "ToeBase"]

var _skel: Skeleton3D
var _limbs: Array = []   ## [bone, child_bone, MeshInstance3D]

func _initialize() -> void:
	_run.call_deferred()

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.split("=", true, 1)[1]
	return d

func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null

func _run() -> void:
	var clip := _arg("clip", BASE)
	var out := _arg("out", "user://sheet.png")
	var cols := _arg("frames", "8").to_int()
	var views := _arg("views", "side,front").split(",")
	root.size = CELL
	var anim: Animation
	var scn: Node3D
	if clip.ends_with(".fbx") or clip.ends_with(".glb"):
		scn = load(clip).instantiate()
		var ap: AnimationPlayer = _find(scn, "AnimationPlayer")
		anim = ap.get_animation(ap.get_animation_list()[0])
	else:
		scn = load(BASE).instantiate()
		anim = load(clip)
	root.add_child(scn)
	var ap2: AnimationPlayer = _find(scn, "AnimationPlayer")
	ap2.stop()
	_skel = _find(scn, "Skeleton3D")
	_build_mannequin()
	_env()
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 40
	var sheet := Image.create(CELL.x * cols, CELL.y * views.size(), false, Image.FORMAT_RGBA8)
	for v in views.size():
		for c in cols:
			var t := anim.length * c / maxf(cols - 1, 1)
			_pose(anim, t)
			var hips := _skel.global_transform * _skel.get_bone_global_pose(0).origin
			var focus := Vector3(hips.x, 0.95, hips.z)
			match views[v]:
				"side": cam.position = focus + Vector3(4.2, 0.2, 0)
				"front": cam.position = focus + Vector3(0, 0.2, 4.2)
				"back": cam.position = focus + Vector3(0, 0.2, -4.2)
				"top": cam.position = focus + Vector3(0.01, 4.5, 0)
			cam.look_at(focus)
			await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(c * CELL.x, v * CELL.y))
			_label_cell(sheet, c * CELL.x, v * CELL.y, t)
	sheet.save_png(out)
	print("saved ", out, "  length ", anim.length)
	quit()

## Apply an animation's bone tracks at time t (rest pose for untracked bones).
func _pose(anim: Animation, t: float) -> void:
	_skel.reset_bone_poses()
	for i in anim.get_track_count():
		var path := String(anim.track_get_path(i))
		var bone := path.get_slice(":", 1)
		var b := _skel.find_bone(bone)
		if b < 0:
			continue
		match anim.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				_skel.set_bone_pose_rotation(b, anim.rotation_track_interpolate(i, t))
			Animation.TYPE_POSITION_3D:
				_skel.set_bone_pose_position(b, anim.position_track_interpolate(i, t))
	_skel.force_update_all_bone_transforms()
	for l in _limbs:
		var a: Vector3 = _skel.global_transform * _skel.get_bone_global_pose(l[0]).origin
		var b: Vector3 = _skel.global_transform * _skel.get_bone_global_pose(l[1]).origin
		var mi: MeshInstance3D = l[2]
		var len := a.distance_to(b)
		(mi.mesh as CapsuleMesh).height = maxf(len + 0.08, 0.17)
		mi.global_position = (a + b) * 0.5
		var up := (b - a).normalized() if len > 0.001 else Vector3.UP
		var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		mi.global_basis = Basis(side, up, side.cross(up)).orthonormalized()

func _build_mannequin() -> void:
	for b in _skel.get_bone_count():
		var p := _skel.get_bone_parent(b)
		var n := _skel.get_bone_name(b)
		if p < 0 or SKIP.any(func(s): return n.contains(s)):
			continue
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.06 if (n.contains("Leg") or n.contains("Spine")) else 0.045
		if n.contains("Head"):
			cap.radius = 0.1
		mi.mesh = cap
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.3, 0.25) if n.contains("Left") else (Color(0.25, 0.45, 0.9) if n.contains("Right") else Color(0.8, 0.8, 0.8))
		mi.material_override = m
		root.add_child(mi)
		_limbs.append([p, b, mi])

func _env() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.93, 0.93, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	we.environment = e
	root.add_child(we)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-50, 40, 0)
	root.add_child(l)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.7, 0.72, 0.7)
	floor.material_override = fm
	root.add_child(floor)

## Time stamp in the cell corner, drawn as small blocks (no font rendering into Images).
func _label_cell(img: Image, x: int, y: int, t: float) -> void:
	var w := int(clampf(t * 60.0, 0, 250))
	img.fill_rect(Rect2i(x + 4, y + 4, w, 4), Color(0.1, 0.1, 0.1))
	img.fill_rect(Rect2i(x, y, 1, CELL.y), Color(0.5, 0.5, 0.5))
