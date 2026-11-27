class_name Crowd
extends Node3D
## The audience: one MultiMesh (a single draw call) of low-poly seated people - torso, head, hair, two
## jointed arms and a phone - animated entirely in a vertex shader. Each person has a behaviour
## (idle / cheering / filming on a phone with the odd flash / waving / clapping), a phase and a skin and
## hair tone. `react()` raises crowd excitement (called on big hits), which makes idle people jump up.

enum Mode { IDLE, CHEER, PHOTO, WAVE, CLAP }
const MODE_WEIGHTS := [0.52, 0.16, 0.16, 0.08, 0.08]

const SHADER := """
shader_type spatial;
render_mode cull_back;
uniform float excite = 0.0;
varying float v_part;
varying vec3 v_shirt;
varying float v_skin;
varying float v_hair;
varying float v_phase;

const vec3 SKIN[6] = vec3[](vec3(0.93, 0.76, 0.64), vec3(0.85, 0.62, 0.47), vec3(0.72, 0.5, 0.35),
		vec3(0.55, 0.36, 0.24), vec3(0.36, 0.23, 0.15), vec3(0.96, 0.82, 0.72));
const vec3 HAIR[6] = vec3[](vec3(0.05, 0.04, 0.03), vec3(0.18, 0.1, 0.05), vec3(0.4, 0.26, 0.1),
		vec3(0.75, 0.6, 0.3), vec3(0.45, 0.45, 0.47), vec3(0.02, 0.02, 0.02));

mat3 rot_x(float a) { float c = cos(a), s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_y(float a) { float c = cos(a), s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }
mat3 rot_z(float a) { float c = cos(a), s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }

void vertex() {
	float part = UV.x;          // 0 torso, 1 head, 2 hair, 3 upper arm, 4 forearm, 5 phone, 6 phone screen
	float side = UV.y;          // -1 left arm, +1 right arm, 0 not an arm
	float phase = INSTANCE_CUSTOM.x;
	int mode = int(INSTANCE_CUSTOM.y + 0.5);
	v_part = part;
	v_shirt = COLOR.rgb;
	v_skin = INSTANCE_CUSTOM.z;
	v_hair = INSTANCE_CUSTOM.w;
	v_phase = phase;
	float spd = 0.85 + 0.35 * fract(phase * 3.7);
	float t = TIME * spd + phase * 6.2831;
	// Idle people join in when the crowd is excited (each has their own threshold).
	float thresh = fract(phase * 9.1);
	if (mode == 0 && excite > 0.25 + 0.7 * thresh) mode = 1;
	float amp = mode == 1 ? 0.6 + 0.8 * excite : 1.0;

	// Per-limb target pose.
	float pitch_l = 0.05, pitch_r = 0.05, roll_l = 0.04, roll_r = 0.04, bend_l = 0.15, bend_r = 0.15;
	float bounce = 0.0, head_yaw = 0.0, head_pitch = 0.0, lean = 0.0;
	float breath = sin(t * 1.3) * 0.006;
	if (mode == 0) {
		head_yaw = sin(t * 0.35) * 0.35;
		head_pitch = sin(t * 0.5 + 1.0) * 0.06;
		lean = sin(t * 0.7) * 0.025;
		float fidget = step(0.8, fract(phase * 5.3)) * (0.5 + 0.5 * sin(t * 0.9));  // some rest a hand up
		pitch_r = 0.15 + 0.9 * fidget; bend_r = 0.3 + 1.4 * fidget;
	} else if (mode == 1) {
		float s1 = sin(t * 7.0 * amp), s2 = sin(t * 7.0 * amp + 1.7);
		pitch_l = 0.25; pitch_r = 0.25;
		roll_l = 2.55 + 0.35 * s1; roll_r = 2.55 + 0.35 * s2;
		bend_l = 0.2; bend_r = 0.2;
		bounce = abs(sin(t * 3.5 * amp)) * 0.07 * amp;
		head_pitch = -0.2 + 0.1 * s1;
		lean = sin(t * 3.5) * 0.04;
	} else if (mode == 2) {
		// Both hands up holding a phone in front of the face, tiny hand shake.
		float sh = sin(t * 11.0) * 0.015;
		pitch_l = 0.95 + sh; pitch_r = 0.95 - sh;
		roll_l = -0.12; roll_r = 0.12;
		bend_l = 1.55; bend_r = 1.55;
		head_pitch = -0.05; lean = 0.0;
	} else if (mode == 3) {
		float w = sin(t * 6.0);
		pitch_r = 0.1; roll_r = 2.35 + 0.28 * w; bend_r = 0.55 + 0.45 * w;
		head_yaw = sin(t * 0.8) * 0.2;
		bounce = abs(sin(t * 2.0)) * 0.025;
	} else {
		float c = 0.5 + 0.5 * sin(t * 8.0);
		pitch_l = 1.0; pitch_r = 1.0;
		roll_l = -0.05 - 0.35 * c; roll_r = 0.05 + 0.35 * c;
		bend_l = 1.35; bend_r = 1.35;
		bounce = abs(sin(t * 4.0)) * 0.03;
		head_pitch = 0.04 * sin(t * 8.0);
	}

	vec3 p = VERTEX;
	vec3 n = NORMAL;
	if (side != 0.0 && part >= 3.0) {
		vec3 shoulder = vec3(side * 0.25, 0.62, 0.0);
		vec3 elbow = shoulder + vec3(0.0, -0.28, 0.0);
		float pitch = side < 0.0 ? pitch_l : pitch_r;
		float roll = (side < 0.0 ? roll_l : roll_r) * side;
		float bend = side < 0.0 ? bend_l : bend_r;
		if (part >= 4.0) {
			mat3 b = rot_x(bend);
			p = elbow + b * (p - elbow);
			n = b * n;
		}
		mat3 m = rot_z(roll) * rot_x(pitch);
		p = shoulder + m * (p - shoulder);
		n = m * n;
		// The phone only exists while filming, and only in one hand.
		if (part >= 5.0 && (mode != 2 || side < 0.0)) p = shoulder;
	} else if (part == 1.0 || part == 2.0) {
		vec3 neck = vec3(0.0, 0.7, 0.0);
		mat3 h = rot_y(head_yaw) * rot_x(head_pitch);
		p = neck + h * (p - neck);
		n = h * n;
	}
	if (part < 0.5 || (part < 3.0 && part > 0.5) || side != 0.0) {
		// Whole-body sway/bounce (everything is seated at y = 0).
		mat3 l = rot_z(lean);
		p = l * p;
		n = l * n;
		p.y += bounce + breath;
	}
	VERTEX = p;
	NORMAL = n;
}

void fragment() {
	vec3 col = v_shirt;
	float em = 0.0;
	int part = int(v_part + 0.5);
	if (part == 1 || part == 4) col = SKIN[int(v_skin + 0.5)];
	else if (part == 2) col = HAIR[int(v_hair + 0.5)];
	else if (part == 5) col = vec3(0.03);
	else if (part == 6) {
		col = vec3(0.05, 0.07, 0.1);
		em = 0.25;
		// Occasional camera flash, a few frames long, at a per-person rhythm.
		float f = fract(TIME * (0.08 + 0.05 * fract(v_phase * 13.0)) + v_phase * 7.0);
		em += step(0.985, f) * 12.0;
	}
	ALBEDO = col;
	EMISSION = vec3(0.6, 0.75, 1.0) * em;
	ROUGHNESS = 0.9;
}
"""

var _mat: ShaderMaterial
var excitement := 0.0

## xforms/colors: one per person (seat transform incl. facing, shirt colour).
func build(xforms: Array[Transform3D], colors: Array[Color], rng: RandomNumberGenerator) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _person_mesh()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
		var r := rng.randf()
		var mode := 0
		var acc := 0.0
		for k in MODE_WEIGHTS.size():
			acc += MODE_WEIGHTS[k]
			if r <= acc:
				mode = k
				break
		var skin := float(rng.randi_range(0, 5))
		var hair := float(rng.randi_range(0, 5))
		mm.set_instance_custom_data(i, Color(rng.randf(), float(mode), skin, hair))
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader moves vertices, so give the culling box some slack (people jump / raise arms).
	mmi.extra_cull_margin = 2.0
	add_child(mmi)

## Bump crowd excitement (0..1 scale); it decays on its own.
func react(amount: float) -> void:
	excitement = minf(excitement + amount, 1.0)

func _process(delta: float) -> void:
	if _mat:
		excitement = maxf(excitement - delta * 0.18, 0.0)
		_mat.set_shader_parameter("excite", excitement)

# --- the person mesh (local origin at the seat, facing -Z) ---

func _person_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	# torso (shirt)
	var torso := CapsuleMesh.new()
	torso.radius = 0.2
	torso.height = 0.72
	torso.radial_segments = 8
	torso.rings = 2
	_add(v, nrm, uv, idx, torso, Transform3D(Basis.from_scale(Vector3(1.05, 1.0, 0.7)), Vector3(0, 0.38, 0)), 0.0, 0.0)
	# head + hair
	var head := SphereMesh.new()
	head.radius = 0.115
	head.height = 0.24
	head.radial_segments = 10
	head.rings = 6
	_add(v, nrm, uv, idx, head, Transform3D(Basis.from_scale(Vector3(0.92, 1.05, 1.0)), Vector3(0, 0.84, 0)), 1.0, 0.0)
	var hair := SphereMesh.new()
	hair.radius = 0.122
	hair.height = 0.2
	hair.radial_segments = 10
	hair.rings = 5
	_add(v, nrm, uv, idx, hair, Transform3D(Basis.from_scale(Vector3(0.95, 1.0, 1.0)), Vector3(0, 0.875, 0.025)), 2.0, 0.0)
	# arms, modelled hanging down from the shoulder (the shader poses them)
	for side in [-1.0, 1.0]:
		var sx: float = side * 0.25
		var up := CapsuleMesh.new()
		up.radius = 0.052
		up.height = 0.32
		up.radial_segments = 6
		up.rings = 1
		_add(v, nrm, uv, idx, up, Transform3D(Basis.IDENTITY, Vector3(sx, 0.62 - 0.14, 0)), 3.0, side)
		var fore := CapsuleMesh.new()
		fore.radius = 0.043
		fore.height = 0.3
		fore.radial_segments = 6
		fore.rings = 1
		_add(v, nrm, uv, idx, fore, Transform3D(Basis.IDENTITY, Vector3(sx, 0.34 - 0.13, 0)), 4.0, side)
		if side > 0.0:
			var phone := BoxMesh.new()
			phone.size = Vector3(0.1, 0.17, 0.012)
			_add(v, nrm, uv, idx, phone, Transform3D(Basis.IDENTITY, Vector3(sx, 0.07, -0.02)), 5.0, side)
			var screen := BoxMesh.new()
			screen.size = Vector3(0.085, 0.15, 0.004)
			_add(v, nrm, uv, idx, screen, Transform3D(Basis.IDENTITY, Vector3(sx, 0.07, -0.028)), 6.0, side)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am

func _add(v: PackedVector3Array, nrm: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array,
		mesh: Mesh, xf: Transform3D, part: float, side: float) -> void:
	var a: Array = mesh.get_mesh_arrays()
	var base := v.size()
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		v.append(xf * verts[i])
		nrm.append((xf.basis * norms[i]).normalized())
		uv.append(Vector2(part, side))
	for i in a[Mesh.ARRAY_INDEX]:
		idx.append(base + i)
