extends SceneTree
## Turn a static T-pose character mesh (.glb) into a playable fighter on the game's own Mixamo skeleton.
##   godot --headless --path . -s tools/import_fighter.gd -- --id=<id> --model=<file.glb>
## Optional: --name="HUD name" --height=178 --weight=68 (only used when data/fighters/<id>.tres is new),
##           --tris=40000 --subdivide=1 (each pass rounds the surface and quadruples the triangles)
##           --tex=4096 --detail=0.3 (local contrast on the colour map: muscle tone, creases)
##           --pores=1.0 --sweat=1.0 --scatter=0.25 (skin grain, sheen and light under the surface)
##           --iris=x,y,z;x,y,z (dye the irises dark brown; centres in metres on the finished mesh)
##           --yaw=<degrees, overrides facing detection>
##           --thighs=1.0 --calves=1.0 (leg thickness, e.g. thighs 0.78 for a lanky build; pass on every re-import)
##           --proportions=from:to,... (move body heights, as fractions floor 0 .. crown 1, e.g. knee
##                        0.265:0.29 for longer legs; a lower chin-to-crown share also narrows the head)
##
## Writes assets/fighters/<id>/<id>.scn and points data/fighters/<id>.tres at it. The skeleton and skin
## are copied unchanged from the stock character, so every animation applies as it is. The mesh is scaled
## and bent to the stock proportions, takes its bone weights from the stock mesh and is then subdivided.
## Skin is told apart from cloth by colour and gets its own surface treatment.

const CHARACTER := "res://assets/mixamo/character.fbx"
const SHOULDER_X := 0.19   ## metres from the centre line where the arm correction starts
const HIP_Y := 0.85        ## metres above the floor where the leg correction starts
const CELL := 0.08
const NEIGHBOURS := 6
const SMOOTH_PASSES := 12
const SHOULDER_SMOOTH_PASSES := 10
const SHOULDER_IN := 0.12     ## metres inside the shoulder joint where its own weighting starts
const SHOULDER_OUT := 0.17    ## ...and how far down the upper arm it reaches
const CREASE_SLOPE := 0.9     ## how far outward the arm's edge moves for each metre below the joint
const RELAX_PASSES := 40      ## smoothing steps on the armpit as it lies in the guard pose
const NORMAL_STRENGTH := 1.6
const ROUGHNESS_FLOOR := 0.4  ## roughness map values are squeezed into [this, 1]
const CURVE := 0.7            ## how far subdivision bows new points out onto the curved surface (0..1)
const SKIN_ROUGHNESS := 0.52  ## a light sweat: skin roughness is pulled toward this
const PORE_STRENGTH := 14.0   ## tilt of the normal map (0..255 units) at a pore's edge
const MASK_SIZE := 1024
const IRIS_RADIUS := 0.0066
const IRIS_TINT := Color(0.40, 0.23, 0.13)  ## multiplied over the generator's iris
const CHECK_CLIPS := ["idle", "jab", "rear_hook", "round_kick_high", "knee", "knockdown"]

var _args := {}

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var code := _run()
	quit(code)

func _fail(msg: String) -> int:
	printerr("ERROR: " + msg)
	return 1

func _run() -> int:
	var id: String = _args.get("id", "")
	var model: String = _args.get("model", "")
	if id == "" or not id.is_valid_ascii_identifier() or id != id.to_lower():
		return _fail("--id=<lower_case_id> is required (letters, digits, underscores)")
	if not FileAccess.file_exists(model):
		return _fail("--model=<file.glb> not found: " + model)

	var src := _read_model(model)
	if src.is_empty():
		return _fail("no triangle mesh in " + model)
	var donor := _read_donor()
	var verts: PackedVector3Array = src.verts

	var err := _orient(verts, src.normals)
	if err != "":
		return _fail(err)
	err = _reproportion(verts, _args.get("proportions", ""))
	if err != "":
		return _fail(err)
	err = _fit(verts, donor)
	if err != "":
		return _fail(err)
	src.verts = verts

	var before: int = src.indices.size() / 3
	_simplify(src, int(_args.get("tris", "40000")))
	print("triangles: %d -> %d" % [before, src.indices.size() / 3])

	var skin := _weights(src, donor)
	_shape_legs(src, skin, donor, float(_args.get("thighs", "1.0")), float(_args.get("calves", "1.0")))
	_relax_armpits(src, skin, donor)
	_smooth_normals(src)
	_check_deformation(src, skin, donor)  # before subdividing: same shape, far fewer points to pose
	for i in int(_args.get("subdivide", "1")):
		_subdivide(src, skin)
		_smooth_normals(src)
	print("final triangles: %d" % (src.indices.size() / 3))
	var mesh := _build_mesh(src, skin, int(_args.get("tex", "4096")))

	var root := Node3D.new()
	root.name = "character"
	var skel: Skeleton3D = (donor.skeleton as Skeleton3D).duplicate()
	for c in skel.get_children():
		skel.remove_child(c)
		c.free()
	skel.name = "Skeleton3D"
	root.add_child(skel)
	skel.owner = root
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	mi.skin = donor.skin
	skel.add_child(mi)
	mi.owner = root
	mi.skeleton = NodePath("..")

	var dir := "res://assets/fighters/%s" % id
	DirAccess.make_dir_recursive_absolute(dir)
	var packed := PackedScene.new()
	packed.pack(root)
	var out := "%s/%s.scn" % [dir, id]
	if ResourceSaver.save(packed, out, ResourceSaver.FLAG_COMPRESS) != OK:
		return _fail("could not save " + out)
	print("saved " + out)

	root.free()
	return _write_data(id, out)

# --- input ---

func _read_model(path: String) -> Dictionary:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return {}
	var scene := doc.generate_scene(state)
	var out := {"verts": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array(),
		"indices": PackedInt32Array(), "material": null}
	_collect(scene, Transform3D.IDENTITY, out)
	scene.free()
	return out if not out.indices.is_empty() else {}

func _collect(n: Node, parent: Transform3D, out: Dictionary) -> void:
	var xf := parent
	if n is Node3D:
		xf = parent * (n as Node3D).transform
	var mesh: Mesh = null
	if n is MeshInstance3D:
		mesh = (n as MeshInstance3D).mesh
	elif n is ImporterMeshInstance3D:
		mesh = (n as ImporterMeshInstance3D).mesh.get_mesh()
	if mesh:
		for s in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var base: int = out.verts.size()
			var nb := xf.basis.inverse().transposed()
			for i in v.size():
				out.verts.append(xf * v[i])
				out.normals.append((nb * a[Mesh.ARRAY_NORMAL][i]).normalized())
				out.uvs.append(a[Mesh.ARRAY_TEX_UV][i] if a[Mesh.ARRAY_TEX_UV] != null else Vector2.ZERO)
			var idx = a[Mesh.ARRAY_INDEX]
			if idx == null or idx.is_empty():
				for i in v.size():
					out.indices.append(base + i)
			else:
				for i in idx:
					out.indices.append(base + i)
			if out.material == null:
				out.material = mesh.surface_get_material(s)
			else:
				if mesh.surface_get_material(s) != out.material:
					push_warning("several materials: only the first one's textures are used")
	for c in n.get_children():
		_collect(c, xf, out)

## Stock character: skeleton, skin, and every mesh vertex with its weights as skin bind indices.
func _read_donor() -> Dictionary:
	var ch: Node3D = load(CHARACTER).instantiate()
	var skel: Skeleton3D = ch.get_node("Skeleton3D")
	var surface: MeshInstance3D = skel.get_node("Beta_Surface")
	var skin: Skin = surface.skin
	var bind_of := {}  ## bone name -> bind index in the kept skin
	for i in skin.get_bind_count():
		bind_of[_bind_bone_name(skin, i, skel)] = i
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var weights: Array[Dictionary] = []
	for mi in skel.get_children():
		if not mi is MeshInstance3D:
			continue
		var own: Skin = (mi as MeshInstance3D).skin
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var w: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / v.size()
			for i in v.size():
				var d := {}
				for k in per:
					if w[i * per + k] <= 0.0:
						continue
					var bname := _merge_bone(_bind_bone_name(own, bones[i * per + k], skel))
					if bind_of.has(bname):
						var b: int = bind_of[bname]
						d[b] = d.get(b, 0.0) + w[i * per + k]
				verts.append(v[i])
				normals.append(a[Mesh.ARRAY_NORMAL][i])
				weights.append(d)
	var names := {}
	for bname in bind_of:
		names[bind_of[bname]] = bname
	return {"root": ch, "skeleton": skel, "skin": skin, "verts": verts, "normals": normals, "weights": weights,
		"names": names}

func _bind_bone_name(skin: Skin, i: int, skel: Skeleton3D) -> String:
	var n := String(skin.get_bind_name(i))
	return n if n != "" else skel.get_bone_name(skin.get_bind_bone(i))

## Fingers move as one with the hand (generated hands never line up with the stock fingers, and the game
## covers them with gloves); end bones fold into their parent.
func _merge_bone(n: String) -> String:
	for side in ["Left", "Right"]:
		var hand := "mixamorig_%sHand" % side
		if n.begins_with(hand):
			return hand
		if n.begins_with("mixamorig_%sToe" % side):
			return "mixamorig_%sToeBase" % side
	if n.begins_with("mixamorig_HeadTop"):
		return "mixamorig_Head"
	return n

# --- shape ---

static func _bounds(v: PackedVector3Array) -> AABB:
	var box := AABB(v[0], Vector3.ZERO)
	for p in v:
		box = box.expand(p)
	return box

static func _rotate_y(v: PackedVector3Array, n: PackedVector3Array, angle: float) -> void:
	var b := Basis(Vector3.UP, angle)
	for i in v.size():
		v[i] = b * v[i]
		n[i] = b * n[i]

## Arms along X, toes toward +Z (the way Mixamo characters face).
func _orient(v: PackedVector3Array, n: PackedVector3Array) -> String:
	var box := _bounds(v)
	if box.size.y < box.size.z * 0.8 and box.size.y < box.size.x * 0.8:
		return "model is not upright (Y up expected), size %s" % box.size
	if _args.has("yaw"):
		_rotate_y(v, n, deg_to_rad(float(_args.yaw)))
		return ""
	if box.size.z > box.size.x:
		_rotate_y(v, n, PI / 2)
		box = _bounds(v)
	var h := box.size.y
	var foot := Vector2.ZERO  # x = sum of z, y = count
	var ankle := Vector2.ZERO
	for p in v:
		var y := (p.y - box.position.y) / h
		if y < 0.025:
			foot += Vector2(p.z, 1)
		elif y > 0.06 and y < 0.11:
			ankle += Vector2(p.z, 1)
	if foot.y == 0 or ankle.y == 0:
		return "could not find the feet; pass --yaw"
	var forward := (foot.x / foot.y - ankle.x / ankle.y) / h
	if forward < 0.0:
		_rotate_y(v, n, PI)
	print("facing: toe offset %.3f of height%s" % [absf(forward), ", turned around" if forward < 0.0 else ""])
	return ""

## Median of the `axis` coordinate in bins along `along`, over vertices accepted by `keep`.
static func _profile(v: PackedVector3Array, keep: Callable, along: Callable, axis: int, from: float, step: float,
		count: int) -> PackedFloat32Array:
	var bins: Array = []
	for i in count:
		bins.append(PackedFloat32Array())
	for p in v:
		if not keep.call(p):
			continue
		var i := int(floor((along.call(p) - from) / step))
		if i >= 0 and i < count:
			bins[i].append(p[axis])
	var out := PackedFloat32Array()
	for b: PackedFloat32Array in bins:
		if b.is_empty():
			out.append(NAN)
		else:
			# middle of the cross-section: unlike the median it ignores how densely each side is meshed
			b.sort()
			out.append((b[int(b.size() * 0.05)] + b[int((b.size() - 1) * 0.95)]) * 0.5)
	return out

## Piecewise-linear lookup of (source - target) between bin centres, ignoring empty bins.
static func _delta(src: PackedFloat32Array, dst: PackedFloat32Array, from: float, step: float, t: float) -> float:
	var pts: Array[Vector2] = []
	for i in src.size():
		if not is_nan(src[i]) and not is_nan(dst[i]):
			pts.append(Vector2(from + (i + 0.5) * step, dst[i] - src[i]))
	if pts.is_empty():
		return 0.0
	if t <= pts[0].x:
		return pts[0].y
	for i in range(1, pts.size()):
		if t <= pts[i].x:
			return lerpf(pts[i - 1].y, pts[i].y, (t - pts[i - 1].x) / (pts[i].x - pts[i - 1].x))
	return pts[-1].y

## Move body heights to new fractions of the total height (generated figures often come out short in the
## leg with a large head). The head keeps its shape: its width follows its new height. The T-pose arms
## are only carried up or down with the shoulders, so they keep their thickness.
func _reproportion(v: PackedVector3Array, spec: String) -> String:
	if spec == "":
		return ""
	var from := PackedFloat32Array([0.0])
	var to := PackedFloat32Array([0.0])
	for pair in spec.split(",", false):
		var kv := pair.split(":")
		if kv.size() != 2 or kv[0].to_float() <= from[-1] or kv[1].to_float() <= to[-1] or kv[0].to_float() >= 1.0 \
				or kv[1].to_float() >= 1.0:
			return "--proportions wants rising from:to pairs between 0 and 1, got " + spec
		from.append(kv[0].to_float())
		to.append(kv[1].to_float())
	from.append(1.0)
	to.append(1.0)
	var line := func(t: float) -> float:
		for i in range(1, from.size()):
			if t <= from[i] or i == from.size() - 1:
				return lerpf(to[i - 1], to[i], (t - from[i - 1]) / (from[i] - from[i - 1]))
		return t
	var remap := func(t: float) -> float:  # corners rounded off
		var sum := 0.0
		for k in range(-4, 5):
			sum += line.call(t + k * 0.006)
		return sum / 9.0
	var box := _bounds(v)
	var h := box.size.y
	var mid := box.get_center().x
	var chin := from[-2]
	var head_scale := (1.0 - to[-2]) / (1.0 - chin) if chin > 0.82 else 1.0
	var head_z := Vector2.ZERO
	for p in v:
		if (p.y - box.position.y) / h > chin:
			head_z += Vector2(p.z, 1)
	var zc := head_z.x / maxf(head_z.y, 1.0)
	var shoulder_shift: float = remap.call(0.81) - 0.81
	for i in v.size():
		var p := v[i]
		var t := (p.y - box.position.y) / h
		var arm := smoothstep(0.11, 0.17, absf(p.x - mid) / h) * smoothstep(0.7, 0.75, t)
		var y := lerpf(remap.call(t), t + shoulder_shift, arm)
		var narrow := lerpf(1.0, head_scale, smoothstep(chin - 0.03, chin + 0.015, t) * (1.0 - arm))
		v[i] = Vector3(mid + (p.x - mid) * narrow, box.position.y + y * h, zc + (p.z - zc) * narrow)
	print("proportions %s, head width x%.3f" % [spec, head_scale])
	return ""

## Scale to the stock height, then move arms and legs onto the stock limbs so the joints sit inside them.
func _fit(v: PackedVector3Array, donor: Dictionary) -> String:
	var d: PackedVector3Array = donor.verts
	var dbox := _bounds(d)
	var box := _bounds(v)
	var ratio := box.size.x / box.size.y
	if ratio < 0.8 or ratio > 1.25:
		return "not a T-pose: arm span / height = %.2f (expected about 1.0)" % ratio
	var s := dbox.size.y / box.size.y
	var torso := func(p: Vector3) -> bool: return absf(p.x) < 0.2 and p.y > 1.05 and p.y < 1.35
	var mid_x := box.get_center().x
	for i in v.size():
		v[i] = Vector3((v[i].x - mid_x) * s, (v[i].y - box.position.y) * s + dbox.position.y, v[i].z * s)
	var zmid := func(pts: PackedVector3Array) -> float:
		var one := _profile(pts, torso, func(p: Vector3) -> float: return 0.0, 2, -0.5, 1.0, 1)
		return one[0]
	var dz: float = zmid.call(d) - zmid.call(v)
	if is_nan(dz):
		return "could not find the torso"
	for i in v.size():
		v[i].z += dz

	var tip_d := maxf(dbox.end.x, -dbox.position.x)
	for side: float in [1.0, -1.0]:
		var tip := 0.0
		for p in v:
			tip = maxf(tip, p.x * side)
		if tip < 0.55:
			return "could not find an outstretched arm"
		# length
		for i in v.size():
			var x := v[i].x * side
			if x > SHOULDER_X and v[i].y > 1.0:
				v[i].x = side * (SHOULDER_X + (x - SHOULDER_X) * (tip_d - SHOULDER_X) / (tip - SHOULDER_X))
		# height and depth of the arm axis
		var arm := func(p: Vector3) -> bool: return p.x * side > 0.3 and p.y > 1.0
		var along := func(p: Vector3) -> float: return p.x * side
		var sy := _profile(v, arm, along, 1, 0.3, 0.1, 5)
		var ty := _profile(d, arm, along, 1, 0.3, 0.1, 5)
		var sz := _profile(v, arm, along, 2, 0.3, 0.1, 5)
		var tz := _profile(d, arm, along, 2, 0.3, 0.1, 5)
		print("arm %s: height off by %.3f m at the elbow" % ["+x" if side > 0 else "-x", _delta(sy, ty, 0.3, 0.1, 0.45)])
		for i in v.size():
			var x := v[i].x * side
			if x > SHOULDER_X and v[i].y > 1.0:
				var w := smoothstep(SHOULDER_X, 0.38, x)
				v[i].y += w * _delta(sy, ty, 0.3, 0.1, x)
				v[i].z += w * _delta(sz, tz, 0.3, 0.1, x)
		# legs: sideways and depth, by height
		var leg := func(p: Vector3) -> bool: return p.x * side > 0.005 and absf(p.x) < 0.4 and p.y < 0.75
		var up := func(p: Vector3) -> float: return p.y
		var lx := _profile(v, leg, up, 0, 0.05, 0.1, 7)
		var dx := _profile(d, leg, up, 0, 0.05, 0.1, 7)
		var lz := _profile(v, leg, up, 2, 0.15, 0.1, 6)
		var tz2 := _profile(d, leg, up, 2, 0.15, 0.1, 6)
		for i in v.size():
			if v[i].x * side > 0.0 and absf(v[i].x) < 0.4 and v[i].y < HIP_Y:
				var w := 1.0 - smoothstep(0.65, HIP_Y, v[i].y)
				w *= smoothstep(0.0, 0.03, v[i].x * side)
				var y := v[i].y
				v[i].x += w * _delta(lx, dx, 0.05, 0.1, y)
				v[i].z += w * _delta(lz, tz2, 0.15, 0.1, y)
	return ""

## Replace the triangle list with the engine's simplification closest to (not far above) the target.
func _simplify(src: Dictionary, target: int) -> void:
	if src.indices.size() / 3 <= target:
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = src.verts
	arrays[Mesh.ARRAY_NORMAL] = src.normals
	arrays[Mesh.ARRAY_TEX_UV] = src.uvs
	arrays[Mesh.ARRAY_INDEX] = src.indices
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(25.0, 60.0, [])
	var best: PackedInt32Array = src.indices
	for l in im.get_surface_lod_count(0):
		var idx := im.get_surface_lod_indices(0, l)
		var n := idx.size() / 3
		if n >= target * 0.5 and absi(n - target) < absi(best.size() / 3 - target):
			best = idx
	# keep only the vertices still in use
	var remap := {}
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var uv := PackedVector2Array()
	var out := PackedInt32Array()
	for i in best:
		if not remap.has(i):
			remap[i] = v.size()
			v.append(src.verts[i])
			nn.append(src.normals[i])
			uv.append(src.uvs[i])
		out.append(remap[i])
	src.verts = v
	src.normals = nn
	src.uvs = uv
	src.indices = out

# --- skinning ---

## Per vertex {bind index: weight}: blend of the nearest stock vertices, smoothed over the surface.
func _weights(src: Dictionary, donor: Dictionary) -> Array[Dictionary]:
	var grid := {}
	var d: PackedVector3Array = donor.verts
	for i in d.size():
		var key := Vector3i((d[i] / CELL).floor())
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		grid[key].append(i)
	# vertices split by UV seams share one entry
	var weld := {}
	var point := PackedInt32Array()  ## vertex -> welded point
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	for i in src.verts.size():
		var key := Vector3i((src.verts[i] * 10000.0).round())
		if not weld.has(key):
			weld[key] = pos.size()
			pos.append(src.verts[i])
			nrm.append(Vector3.ZERO)
		point.append(weld[key])
		nrm[weld[key]] += src.normals[i]
	var w: Array[Dictionary] = []
	for i in pos.size():
		w.append(_soften_crotch(pos[i], _nearest_weights(pos[i], nrm[i].normalized(), donor, grid), donor))
	var links: Array[Dictionary] = []
	for i in pos.size():
		links.append({})
	for t in src.indices.size() / 3:
		for k in 3:
			var a := point[src.indices[t * 3 + k]]
			var b := point[src.indices[t * 3 + (k + 1) % 3]]
			if a != b:
				links[a][b] = true
				links[b][a] = true
	w = _smooth(w, links, SMOOTH_PASSES)
	var shoulders := _shape_shoulders(pos, w, donor)
	w = _smooth(w, links, SHOULDER_SMOOTH_PASSES, shoulders)
	var out: Array[Dictionary] = []
	for i in src.verts.size():
		out.append(_top4(w[point[i]]))
	return out

## Average points' weights with their neighbours', `passes` times: every point, or only the `only` ones.
func _smooth(w: Array[Dictionary], links: Array[Dictionary], passes: int, only := {}) -> Array[Dictionary]:
	for pass_i in passes:
		var next: Array[Dictionary] = []
		for i in w.size():
			if links[i].is_empty() or (not only.is_empty() and not only.has(i)):
				next.append(w[i])
				continue
			var m := {}
			for b: int in w[i]:
				m[b] = w[i][b] * 0.5
			for j: int in links[i]:
				for b: int in w[j]:
					m[b] = m.get(b, 0.0) + w[j][b] * 0.5 / links[i].size()
			next.append(m)
		w = next
	return w

## The generator's armpit never lines up with the stock body's, and borrowed weights then let the upper arm
## drag skin far down the ribs, which folds into a flap when the arm comes in to guard. Around each shoulder
## the upper arm's share is set from the geometry instead: it takes over just outside the joint on top, and
## further out the lower a point sits, so the dividing line runs down into the armpit like a real crease.
## Returns the points it touched.
func _shape_shoulders(pos: PackedVector3Array, w: Array[Dictionary], donor: Dictionary) -> Dictionary:
	var touched := {}
	var binds: Skin = donor.skin
	var bind := {}
	for b: int in donor.names:
		bind[donor.names[b]] = b
	for side: String in ["Left", "Right"]:
		var arm: int = bind["mixamorig_%sArm" % side]
		var girdle: int = bind["mixamorig_%sShoulder" % side]
		var joint := binds.get_bind_pose(arm).affine_inverse().origin
		var out := signf(joint.x)
		var chest: int = bind["mixamorig_Spine2"]
		for i in pos.size():
			var p := pos[i]
			var along := (p.x - joint.x) * out  # + = down the arm from the joint
			if along < -SHOULDER_IN or along > SHOULDER_OUT or p.y < joint.y - 0.3:
				continue
			var below := joint.y - p.y
			var share := smoothstep(-0.07, 0.12, along - CREASE_SLOPE * maxf(below - 0.02, 0.0))
			var rest := {}
			var rest_total := 0.0
			for b: int in w[i]:
				if b != arm:
					rest[b] = w[i][b]
					rest_total += w[i][b]
			if rest_total < 0.001:
				# it had nothing but the arm: hang what the arm gives up on the shoulder girdle or chest
				rest = {girdle if below < 0.04 else chest: 1.0}
				rest_total = 1.0
			var m := {arm: share}
			for b: int in rest:
				m[b] = rest[b] / rest_total * (1.0 - share)
			# fade the change in at the edges of the region
			var fade := smoothstep(-SHOULDER_IN, -SHOULDER_IN + 0.05, along) \
					* (1.0 - smoothstep(SHOULDER_OUT - 0.05, SHOULDER_OUT, along))
			var mixed := {}
			for b: int in w[i]:
				mixed[b] = w[i][b] * (1.0 - fade)
			for b: int in m:
				mixed[b] = mixed.get(b, 0.0) + m[b] * fade
			w[i] = mixed
			touched[i] = true
	return touched

## Shorts are one piece of cloth across both legs, unlike the stock body: hand over gradually from hips
## to thighs and from one thigh to the other, or the cloth tears apart on kicks.
func _soften_crotch(p: Vector3, w: Dictionary, donor: Dictionary) -> Dictionary:
	var blend := (1.0 - smoothstep(0.08, 0.24, absf(p.x))) * smoothstep(0.4, 0.75, p.y) \
			* (1.0 - smoothstep(0.98, 1.1, p.y))
	if blend <= 0.0:
		return w
	var bind := {}
	for b: int in donor.names:
		bind[donor.names[b]] = b
	var hips := lerpf(0.2, 0.85, smoothstep(0.65, 0.98, p.y))
	var left := smoothstep(-0.12, 0.12, p.x)
	var goal := {bind["mixamorig_Hips"]: hips, bind["mixamorig_LeftUpLeg"]: (1.0 - hips) * left,
		bind["mixamorig_RightUpLeg"]: (1.0 - hips) * (1.0 - left)}
	var out := {}
	for b: int in w:
		out[b] = w[b] * (1.0 - blend)
	for b: int in goal:
		out[b] = out.get(b, 0.0) + goal[b] * blend
	return _top4(out)

func _nearest_weights(p: Vector3, n: Vector3, donor: Dictionary, grid: Dictionary) -> Dictionary:
	var d: PackedVector3Array = donor.verts
	var c := Vector3i((p / CELL).floor())
	var found: Array[Vector2] = []  ## x = penalised distance, y = donor vertex
	var r := 1
	while found.size() < NEIGHBOURS and r <= 14:
		found.clear()
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				for z in range(-r, r + 1):
					for i: int in grid.get(c + Vector3i(x, y, z), PackedInt32Array()):
						# a left-side vertex never follows a right-side limb
						if absf(p.x) > 0.03 and absf(d[i].x) > 0.03 and signf(p.x) != signf(d[i].x):
							continue
						var facing := 1.0 - n.dot(donor.normals[i])  # 0 same way .. 2 opposite
						found.append(Vector2(p.distance_to(d[i]) * (1.0 + facing), i))
		r += 1 if r < 3 else 3
	if found.is_empty():
		return {0: 1.0}
	found.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var out := {}
	for k in mini(NEIGHBOURS, found.size()):
		var share := 1.0 / pow(found[k].x + 0.005, 2)
		var dw: Dictionary = donor.weights[int(found[k].y)]
		for b: int in dw:
			out[b] = out.get(b, 0.0) + dw[b] * share
	return _top4(out)

static func _top4(w: Dictionary) -> Dictionary:
	var keys := w.keys()
	keys.sort_custom(func(a, b) -> bool: return w[a] > w[b])
	var total := 0.0
	for k in keys.slice(0, 4):
		total += w[k]
	var out := {}
	for k in keys.slice(0, 4):
		out[k] = w[k] / total
	return out

## Narrow or thicken thighs (with the shorts) and calves around the leg bones, blending across the knee.
## Only widths change: height, joints and weights stay, so the animations are unaffected. Fades out at the
## waistband and into the feet.
func _shape_legs(src: Dictionary, skin: Array[Dictionary], donor: Dictionary, thighs: float, calves: float) -> void:
	if is_equal_approx(thighs, 1.0) and is_equal_approx(calves, 1.0):
		return
	var binds: Skin = donor.skin
	var joint := {}  ## bone name -> joint position in vertex space
	var bind := {}
	for b: int in donor.names:
		joint[donor.names[b]] = binds.get_bind_pose(b).affine_inverse().origin
		bind[donor.names[b]] = b
	var verts: PackedVector3Array = src.verts
	var normals: PackedVector3Array = src.normals
	for i in verts.size():
		var p := verts[i]
		var shift := Vector3.ZERO
		var total := 0.0
		var scale := 0.0
		for side: String in ["Left", "Right"]:
			var hip: Vector3 = joint["mixamorig_%sUpLeg" % side]
			var knee: Vector3 = joint["mixamorig_%sLeg" % side]
			var ankle: Vector3 = joint["mixamorig_%sFoot" % side]
			var w: float = skin[i].get(bind["mixamorig_%sUpLeg" % side], 0.0) \
					+ skin[i].get(bind["mixamorig_%sLeg" % side], 0.0)
			# the hips carry much of the shorts: hand their share to the leg on this side, below the waist
			if (p.x > 0.0) == (hip.x > 0.0):
				w += skin[i].get(bind["mixamorig_Hips"], 0.0) * (1.0 - smoothstep(hip.y - 0.08, hip.y + 0.06, p.y))
			if w <= 0.0:
				continue
			var axis := knee.lerp(hip, clampf(inverse_lerp(knee.y, hip.y, p.y), 0.0, 1.0)) if p.y > knee.y \
					else ankle.lerp(knee, clampf(inverse_lerp(ankle.y, knee.y, p.y), 0.0, 1.0))
			w *= 1.0 - smoothstep(hip.y - 0.02, hip.y + 0.12, p.y)
			var thickness := lerpf(calves, thighs, smoothstep(knee.y - 0.08, knee.y + 0.17, p.y))
			shift += Vector3(p.x - axis.x, 0.0, p.z - axis.z) * (thickness - 1.0) * w
			total += w
			scale += (thickness - 1.0) * w
		if total <= 0.0:
			continue
		verts[i] = p + shift
		var k := 1.0 + scale / maxf(total, 1.0)
		normals[i] = Vector3(normals[i].x / k, normals[i].y, normals[i].z / k).normalized()
	src.verts = verts
	src.normals = normals

## Weights alone leave a hard-edged fold behind the armpit once the arms come in to guard, where fighters
## spend the fight. So: pose the mesh in the guard stance, iron that patch smooth (Taubin smoothing, which
## keeps its volume), and carry the corrected points back to the T-pose through the same bone blend.
func _relax_armpits(src: Dictionary, skin: Array[Dictionary], donor: Dictionary) -> void:
	var skel: Skeleton3D = donor.skeleton
	var binds: Skin = donor.skin
	var anim := FighterModel.set_library("muay_thai").get_animation("idle")
	_pose(skel, anim, 0.0)
	var mats := {}
	var bind := {}
	for b: int in donor.names:
		mats[b] = _global_pose(skel, skel.find_bone(donor.names[b])) * binds.get_bind_pose(b)
		bind[donor.names[b]] = b
	skel.reset_bone_poses()

	var verts: PackedVector3Array = src.verts
	var weld := {}
	var point := PackedInt32Array()
	var rest := PackedVector3Array()
	var blend: Array[Transform3D] = []
	var posed := PackedVector3Array()
	var amount := PackedFloat32Array()
	for i in verts.size():
		var key := Vector3i((verts[i] * 10000.0).round())
		if not weld.has(key):
			weld[key] = rest.size()
			var p := verts[i]
			var m := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
			for b: int in skin[i]:
				var t: Transform3D = mats[b]
				var w: float = skin[i][b]
				m.basis.x += t.basis.x * w
				m.basis.y += t.basis.y * w
				m.basis.z += t.basis.z * w
				m.origin += t.origin * w
			var a := 0.0
			for side: String in ["Left", "Right"]:
				var joint := binds.get_bind_pose(bind["mixamorig_%sArm" % side]).affine_inverse().origin
				var along := (p.x - joint.x) * signf(joint.x)
				# under and behind the joint, stopping short of the upper arm (and anything worn on it)
				a = maxf(a, (1.0 - smoothstep(0.16, 0.25, p.distance_to(joint)))
						* (1.0 - smoothstep(0.04, 0.09, along)) * smoothstep(-0.05, 0.02, joint.y - p.y))
			rest.append(p)
			blend.append(m)
			posed.append(m * p)
			amount.append(a)
		point.append(weld[key])
	var links: Array[Dictionary] = []
	for i in rest.size():
		links.append({})
	var idx: PackedInt32Array = src.indices
	for t in idx.size() / 3:
		for k in 3:
			var a := point[idx[t * 3 + k]]
			var b := point[idx[t * 3 + (k + 1) % 3]]
			if a != b:
				links[a][b] = true
				links[b][a] = true
	var moved := posed.duplicate()
	for step in RELAX_PASSES * 2:
		var strength := 0.6 if step % 2 == 0 else -0.45  # shrink, then swell most of the way back
		var next := moved.duplicate()
		for i in rest.size():
			if amount[i] <= 0.0 or links[i].is_empty():
				continue
			var mean := Vector3.ZERO
			for j: int in links[i]:
				mean += moved[j]
			next[i] = moved[i] + (mean / links[i].size() - moved[i]) * strength * amount[i]
		moved = next
	var worst := 0.0
	for i in rest.size():
		if amount[i] > 0.0 and absf(blend[i].basis.determinant()) > 0.05:
			var fixed := blend[i].affine_inverse() * moved[i]
			worst = maxf(worst, fixed.distance_to(rest[i]))
			rest[i] = fixed
	for i in verts.size():
		verts[i] = rest[point[i]]
	src.verts = verts
	print("armpits relaxed: largest move %.1f cm" % (worst * 100.0))

## Normals from the final geometry (the limbs have been moved and reshaped since the generator made its
## own), shared across texture seams so the surface shades without facets.
func _smooth_normals(src: Dictionary) -> void:
	var verts: PackedVector3Array = src.verts
	var idx: PackedInt32Array = src.indices
	var keys: Array[Vector3i] = []
	for v in verts:
		keys.append(Vector3i((v * 10000.0).round()))
	var sum := {}
	for t in idx.size() / 3:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		var face := (verts[c] - verts[a]).cross(verts[b] - verts[a]).normalized()  # clockwise winding
		for k in 3:
			# weighted by the corner angle, so long slivers don't drag the shading around
			var i: int = [a, b, c][k]
			var j: int = [b, c, a][k]
			var l: int = [c, a, b][k]
			var angle := (verts[j] - verts[i]).angle_to(verts[l] - verts[i])
			sum[keys[i]] = sum.get(keys[i], Vector3.ZERO) + face * angle
	var normals: PackedVector3Array = src.normals
	for i in verts.size():
		var n: Vector3 = sum.get(keys[i], Vector3.ZERO)
		if n.length_squared() > 1e-18:
			# keep the generator's side of the surface should a triangle be wound the other way
			normals[i] = n.normalized() if n.dot(normals[i]) >= 0.0 else -n.normalized()
	src.normals = normals

## Split every triangle into four, bowing each new edge point onto the surface the end normals describe
## (Phong tessellation). Original points stay put; UVs and bone weights are averaged.
func _subdivide(src: Dictionary, skin: Array[Dictionary]) -> void:
	var v: PackedVector3Array = src.verts
	var n: PackedVector3Array = src.normals
	var uv: PackedVector2Array = src.uvs
	var idx: PackedInt32Array = src.indices
	var mids := {}  ## Vector2i(low, high) vertex pair -> new vertex
	var out := PackedInt32Array()
	for t in idx.size() / 3:
		var c := [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]]
		var m := [0, 0, 0]  ## midpoint of edge k -> k+1
		for k in 3:
			var a: int = c[k]
			var b: int = c[(k + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not mids.has(key):
				mids[key] = v.size()
				var flat := (v[a] + v[b]) * 0.5
				var onto_a := flat - n[a] * (flat - v[a]).dot(n[a])
				var onto_b := flat - n[b] * (flat - v[b]).dot(n[b])
				v.append(flat.lerp((onto_a + onto_b) * 0.5, CURVE))
				n.append((n[a] + n[b]).normalized())
				uv.append((uv[a] + uv[b]) * 0.5)
				var w := {}
				for end: int in [a, b]:
					for bone: int in skin[end]:
						w[bone] = w.get(bone, 0.0) + skin[end][bone] * 0.5
				skin.append(_top4(w))
			m[k] = mids[key]
		out.append_array([c[0], m[0], m[2], m[0], c[1], m[1], m[2], m[1], c[2], m[0], m[1], m[2]])
	src.verts = v
	src.normals = n
	src.uvs = uv
	src.indices = out

# --- output ---

## The texture's pixels, no larger than max_size on a side, or null.
func _image(t: Texture2D, max_size: int) -> Image:
	if t == null:
		return null
	var img := t.get_image()
	if img == null or img.is_empty():
		push_warning("a texture could not be read")
		return null
	if img.is_compressed():
		img.decompress()
	var big := maxi(img.get_width(), img.get_height())
	if big > max_size:
		img.resize(img.get_width() * max_size / big, img.get_height() * max_size / big, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	return img

## GPU-compressed (BPTC, the high-quality format) with mipmaps; is_normal keeps those unit length.
func _texture(img: Image, is_normal := false) -> Texture2D:
	img.generate_mipmaps(is_normal)
	var out := PortableCompressedTexture2D.new()
	out.keep_compressed_buffer = true  # off outside the editor, and then nothing gets saved
	out.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_BPTC, is_normal)
	return out

## Where the colour map shows skin (white) rather than cloth, hair or trim: warm hues of middling
## saturation. Softened so the treatment has no hard edge.
func _skin_mask(albedo: Image) -> Image:
	var small := albedo.duplicate() as Image
	small.resize(MASK_SIZE, MASK_SIZE, Image.INTERPOLATE_BILINEAR)
	var px := small.get_data()
	var mask := PackedByteArray()
	mask.resize(MASK_SIZE * MASK_SIZE)
	for i in mask.size():
		var c := Color8(px[i * 3], px[i * 3 + 1], px[i * 3 + 2])
		var hue := c.h * 360.0
		var w := (1.0 - smoothstep(32.0, 40.0, hue)) if hue < 180.0 else smoothstep(345.0, 355.0, hue)
		w *= smoothstep(0.15, 0.24, c.s) * (1.0 - smoothstep(0.72, 0.8, c.s)) * smoothstep(0.16, 0.28, c.v)
		mask[i] = int(w * 255.0)
	var out := Image.create_from_data(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_L8, mask)
	out.resize(MASK_SIZE / 4, MASK_SIZE / 4, Image.INTERPOLATE_BILINEAR)
	out.resize(MASK_SIZE, MASK_SIZE, Image.INTERPOLATE_CUBIC)
	return out

## Darken the texels that lie within an iris: walk the triangles near each centre in texture space and
## test every texel's position on the surface. Catch-lights stay bright.
func _paint_irises(albedo: Image, src: Dictionary, spec: String) -> void:
	var centres: Array[Vector3] = []
	for part in spec.split(";", false):
		var n := part.split_floats(",")
		if n.size() == 3:
			centres.append(Vector3(n[0], n[1], n[2]))
	var v: PackedVector3Array = src.verts
	var uv: PackedVector2Array = src.uvs
	var idx: PackedInt32Array = src.indices
	var size := Vector2(albedo.get_size())
	var done := {}
	for t in idx.size() / 3:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		for centre in centres:
			if v[a].distance_to(centre) > IRIS_RADIUS + 0.008:
				continue
			var pa := uv[a] * size
			var pb := uv[b] * size
			var pc := uv[c] * size
			var area := (pb - pa).cross(pc - pa)
			if absf(area) < 0.001:
				continue
			var low := pa.min(pb).min(pc).floor()
			var high := pa.max(pb).max(pc).ceil()
			for y in range(int(low.y), int(high.y) + 1):
				for x in range(int(low.x), int(high.x) + 1):
					var q := Vector2(x + 0.5, y + 0.5)
					var wb := (q - pa).cross(pc - pa) / area
					var wc := (pb - pa).cross(q - pa) / area
					var wa := 1.0 - wb - wc
					# a little slack so seams between triangles are covered
					if minf(wa, minf(wb, wc)) < -0.08 or done.has(Vector2i(x, y)) \
							or x < 0 or y < 0 or x >= size.x or y >= size.y:
						continue
					var pos := v[a] * wa + v[b] * wb + v[c] * wc
					var off := Vector2(pos.x - centre.x, pos.y - centre.y).length()
					if off >= IRIS_RADIUS or absf(pos.z - centre.z) > 0.012:
						continue
					done[Vector2i(x, y)] = true
					var col := albedo.get_pixel(x, y)
					var w := (1.0 - smoothstep(IRIS_RADIUS * 0.75, IRIS_RADIUS, off)) \
							* (1.0 - smoothstep(0.93, 1.0, col.get_luminance()))
					albedo.set_pixel(x, y, col.lerp(col * IRIS_TINT, w))
	print("irises painted: %d texels" % done.size())

## Tileable noise as bytes around 128. `scale` = texels per feature.
func _noise(type: FastNoiseLite.NoiseType, scale: float, seed_: int) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.noise_type = type
	noise.frequency = 1.0 / scale
	noise.seed = seed_
	noise.fractal_octaves = 2
	var img := noise.get_seamless_image(MASK_SIZE, MASK_SIZE)
	img.convert(Image.FORMAT_L8)
	return img.get_data()

## Pores: tilt the normal map by the slope of fine cellular noise wherever there is skin.
func _add_pores(normal: Image, mask: Image, amount: float) -> void:
	var w := normal.get_width()
	var h := normal.get_height()
	var m := mask.duplicate() as Image
	m.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var skin := m.get_data()
	var bumps := _noise(FastNoiseLite.TYPE_CELLULAR, 5.0, 11)
	var data := normal.get_data()
	var k := amount * PORE_STRENGTH / 128.0
	var last := MASK_SIZE - 1
	for y in h:
		var row := (y & last) * MASK_SIZE
		var below := ((y + 1) & last) * MASK_SIZE
		for x in w:
			var i := y * w + x
			var s := skin[i]
			if s == 0:
				continue
			var here := bumps[row + (x & last)]
			var f := k * s / 255.0
			data[i * 3] = clampi(data[i * 3] + int((here - bumps[row + ((x + 1) & last)]) * f), 0, 255)
			data[i * 3 + 1] = clampi(data[i * 3 + 1] + int((bumps[below + (x & last)] - here) * f), 0, 255)
	normal.set_data(w, h, false, Image.FORMAT_RGB8, data)

## Roughness (green channel): lift the low end so nothing shines like plastic, then give skin a patchy
## sweat sheen that picks out the muscles under the lights.
func _finish_roughness(rough: Image, mask: Image, sweat: float) -> void:
	var w := rough.get_width()
	var h := rough.get_height()
	var m := mask.duplicate() as Image
	m.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var skin := m.get_data()
	var patches := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 28.0, 5)
	var data := rough.get_data()
	var last := MASK_SIZE - 1
	for y in h:
		var row := (y & last) * MASK_SIZE
		for x in w:
			var i := y * w + x
			var base := ROUGHNESS_FLOOR * 255.0 + (1.0 - ROUGHNESS_FLOOR) * data[i * 3 + 1]
			var s := skin[i] / 255.0 * sweat
			if s > 0.0:
				var wet := SKIN_ROUGHNESS * 255.0 + (patches[row + (x & last)] - 128) * 0.3
				base = lerpf(base, wet, 0.8 * s)
			data[i * 3 + 1] = clampi(int(base), 0, 255)
	rough.set_data(w, h, false, Image.FORMAT_RGB8, data)

## Unsharp mask over a wide radius: push every texel away from its neighbourhood average, which deepens
## soft shading such as the lines between muscles.
func _sharpen_detail(img: Image, amount: float) -> void:
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()
	var soft := img.duplicate() as Image
	soft.resize(w / 24, h / 24, Image.INTERPOLATE_BILINEAR)
	soft.resize(w, h, Image.INTERPOLATE_CUBIC)
	var a := img.get_data()
	var b := soft.get_data()
	for i in a.size():
		# capped, so hard edges (lettering, trim) don't grow halos
		a[i] = clampi(a[i] + int(amount * clampi(a[i] - b[i], -40, 40)), 0, 255)
	img.set_data(w, h, false, Image.FORMAT_RGB8, a)

func _build_mesh(src: Dictionary, skin: Array[Dictionary], tex_size: int) -> ArrayMesh:
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for d in skin:
		var keys := d.keys()
		for k in 4:
			bones.append(keys[k] if k < keys.size() else 0)
			weights.append(d[keys[k]] if k < keys.size() else 0.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = src.verts
	arrays[Mesh.ARRAY_NORMAL] = src.normals
	arrays[Mesh.ARRAY_TEX_UV] = src.uvs
	arrays[Mesh.ARRAY_INDEX] = src.indices
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_tangents()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.7
	mat.metallic_specular = 0.45
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# a soft edge light, as skin has under arena lights
	mat.rim_enabled = true
	mat.rim = 0.2
	mat.rim_tint = 0.7
	var from := src.material as BaseMaterial3D
	if from:
		mat.albedo_color = from.albedo_color
		var albedo := _image(from.albedo_texture, tex_size)
		var mask: Image = null
		if albedo:
			mask = _skin_mask(albedo)
			var detail := float(_args.get("detail", "0.3"))
			if detail > 0.0:
				_sharpen_detail(albedo, detail)
			if _args.has("iris"):
				_paint_irises(albedo, src, _args.iris)
			mat.albedo_texture = _texture(albedo)
		var normal := _image(from.normal_texture, tex_size) if from.normal_enabled else null
		if normal:
			if mask:
				_add_pores(normal, mask, float(_args.get("pores", "1.0")))
			mat.normal_enabled = true
			mat.normal_scale = NORMAL_STRENGTH
			mat.normal_texture = _texture(normal, true)
		# fighters are skin and cloth: the generator's metalness map only adds dull dark patches
		var rough := _image(from.roughness_texture, tex_size)
		if rough:
			if mask:
				_finish_roughness(rough, mask, float(_args.get("sweat", "1.0")))
			mat.roughness = 1.0
			mat.roughness_texture = _texture(rough)
			mat.roughness_texture_channel = from.roughness_texture_channel
		var scatter := float(_args.get("scatter", "0.25"))
		if mask and scatter > 0.0:
			mat.subsurf_scatter_enabled = true
			mat.subsurf_scatter_skin_mode = true
			mat.subsurf_scatter_strength = scatter
			mat.subsurf_scatter_texture = _texture(mask)
	if mat.albedo_texture == null:
		push_warning("the model has no colour texture")
	mesh.surface_set_material(0, mat)
	return mesh

## Pose the skeleton through some fight clips and report how many mesh edges tear (stretch past 2x).
func _check_deformation(src: Dictionary, skin: Array[Dictionary], donor: Dictionary) -> void:
	var skel: Skeleton3D = donor.skeleton
	var binds: Skin = donor.skin
	var bone_of := {}
	for b: int in donor.names:
		bone_of[b] = skel.find_bone(donor.names[b])
	var lib := FighterModel.library()
	var verts: PackedVector3Array = src.verts
	var idx: PackedInt32Array = src.indices
	print("deformation check (share of triangle edges stretched more than 2x, worst frame):")
	for clip: String in CHECK_CLIPS:
		var anim := lib.get_animation(clip)
		var worst := 0.0
		for step in 7:
			_pose(skel, anim, anim.length * step / 6.0)
			var mats := {}
			for b: int in donor.names:
				mats[b] = _global_pose(skel, bone_of[b]) * binds.get_bind_pose(b)
			var moved := PackedVector3Array()
			for i in verts.size():
				var p := Vector3.ZERO
				for b: int in skin[i]:
					p += (mats[b] as Transform3D) * verts[i] * skin[i][b]
				moved.append(p)
			var torn := 0
			for e in idx.size():
				var a := idx[e]
				var b := idx[e - 2 if e % 3 == 2 else e + 1]
				var len0 := verts[a].distance_to(verts[b])
				if len0 > 0.002 and moved[a].distance_to(moved[b]) > len0 * 2.0:
					torn += 1
			worst = maxf(worst, float(torn) / idx.size())
		print("  %-16s %.2f%%" % [clip, worst * 100.0])
	skel.reset_bone_poses()

## Set the skeleton to one moment of a clip.
static func _pose(skel: Skeleton3D, anim: Animation, t: float) -> void:
	skel.reset_bone_poses()
	for tr in anim.get_track_count():
		var b := skel.find_bone(String(anim.track_get_path(tr).get_concatenated_subnames()))
		if b < 0:
			continue
		if anim.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
			skel.set_bone_pose_rotation(b, anim.rotation_track_interpolate(tr, t))
		elif anim.track_get_type(tr) == Animation.TYPE_POSITION_3D:
			skel.set_bone_pose_position(b, anim.position_track_interpolate(tr, t))

static func _global_pose(skel: Skeleton3D, b: int) -> Transform3D:
	var xf := skel.get_bone_pose(b)
	var p := skel.get_bone_parent(b)
	while p >= 0:
		xf = skel.get_bone_pose(p) * xf
		p = skel.get_bone_parent(p)
	return xf

## New roster file with neutral stats, or just the model path on an existing one (everything else is kept).
func _write_data(id: String, model_path: String) -> int:
	var path := "res://data/fighters/%s.tres" % id
	var line := 'model_path = "%s"' % model_path
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path)
		var re := RegEx.create_from_string('(?m)^model_path = .*$')
		text = re.sub(text, line) if re.search(text) else text.strip_edges(false, true) + "\n" + line + "\n"
		FileAccess.open(path, FileAccess.WRITE).store_string(text)
		print("updated " + path)
		return 0
	var d := FighterData.new()
	d.id = id
	d.display_name = _args.get("name", id.capitalize())
	d.full_name = d.display_name
	d.height_cm = float(_args.get("height", str(FighterData.BASE_HEIGHT_CM)))
	d.weight_kg = float(_args.get("weight", str(FighterData.BASE_WEIGHT_KG)))
	d.model_path = model_path
	if ResourceSaver.save(d, path) != OK:
		return _fail("could not save " + path)
	print("created " + path)
	return 0
