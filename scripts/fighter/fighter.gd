class_name Fighter
extends CharacterBody3D
## Greybox fighter. All logic advances one frame per tick() at 60 Hz (deterministic, testable).
## FightFlow calls tick(); damage lives in BodyDamage, stamina in Stamina, outcomes in CombatResolver.
## While clinched the fighter only forwards its inputs (take_clinch_intent); the Clinch object runs the exchange.

enum State { IDLE, MOVE, ATTACK, GUARD, CHECK, HITSTUN, BLOCKSTUN, STAGGER, CLINCH, SWEPT, KNOCKDOWN, KO, SLIP }

const FRAME := 1.0 / 60.0
const SPEED := 2.7
const BODY_RADIUS := 0.3     ## fighters can't get closer than two radii (except in the clinch)
const GUARD_SPEED := 1.08
const RING_HALF := ArenaBounds.RING_HALF  ## default (ring) boundary; the arena may swap in a cage
const BUFFER_FRAMES := 8
const CHECK_STARTUP := 3    ## frames before the shin is up
const CHECK_ACTIVE := 20    ## frames a leg kick gets checked
const CHECK_RECOVERY := 12  ## leg coming down: a whiffed check is punishable
const CHECK_COST := 3.0
const SWEPT_FRAMES := 70    ## time on the canvas after a sweep (not a knockdown: no count)
const SWEPT_STAMINA := 5.0
const SLIP_STARTUP := 3     ## frames before the head is off the line
const SLIP_ACTIVE := 12     ## frames head punches miss (uppercuts still catch a slip)
const SLIP_RECOVERY := 8    ## coming back to centre: hittable, but a strike can be thrown out of it
const SLIP_COST := 2.5
const SLIP_COUNTER_FRAMES := 30  ## after slipping a punch, the next strike in this window is a counter

signal move_resolved(attacker: Fighter, defender: Fighter, move: MoveData, result: Dictionary)
signal attack_started(attacker: Fighter, move: MoveData)
signal clinch_requested(attacker: Fighter)

var display_name := "Fighter"
var strength := 1.0  ## clinch power; comes from FighterData in milestone 8b
var status_note := ""  ## short debug text shown over the fighter (set by Clinch)
var opponent: Fighter
var bounds := ArenaBounds.ring()  ## the ropes / cage fence; set by the arena
var clinch: Clinch  ## set by Clinch while this fighter is tied up (the AI reads its position from it)
var controller: Node  ## get_move() -> Vector2, is_guard_held() -> bool, poll_attack() -> StringName
var controls_enabled := true
var rng := RandomNumberGenerator.new()
var moves: Dictionary = {}
var body := BodyDamage.new()
var stam := Stamina.new()
var state := State.IDLE
var state_frame := 0
var current_move: MoveData
var move_has_hit := false
var guard_frames := 0
var stun_frames := 0
var last_knockdown_zone: MoveData.Zone = MoveData.Zone.HEAD
var last_hit_zone: MoveData.Zone = MoveData.Zone.HEAD
var stays_down := false  ## set by FightFlow when a knockdown will end the fight (the model plays a KO fall)
var model: FighterModel  ## rigged character (null = greybox capsule: tests, sims)
var show_debug_label := false
var slip_side := 1.0      ## +1 = slipping to the fighter's right, -1 = left (the model leans that way)
var slip_counter := 0     ## frames left in which a strike counts as a counter (just slipped a punch)

var _eff_startup := 0   ## frame data for the current attack after fatigue scaling
var _eff_active := 0
var _eff_recovery := 0
var _buffered: StringName = &""
var _buffer_age := 0
var _move_input := Vector2.ZERO
var _guard_held := false
var _clinch_intent: StringName = &""
var _body: MeshInstance3D
var _nose: MeshInstance3D
var _limb: MeshInstance3D
var _guard_vis: MeshInstance3D
var _label: Label3D
var _base_color := Color.WHITE
var _flash_color := Color.WHITE
var _flash_frames := 0

## with_model: load the rigged character (the game); without it a greybox capsule (tests, sims - fast).
func setup(color: Color, pos: Vector3, with_model := false) -> void:
	position = pos
	_base_color = color
	moves = MoveLibrary.all()
	_label = Label3D.new()
	_label.position = Vector3(0, 2.2, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.005
	_label.no_depth_test = true
	add_child(_label)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	col.shape = shape
	col.position.y = 0.9
	add_child(col)
	if with_model:
		model = FighterModel.new()
		add_child(model)
		model.setup(color)
		return
	_body = _add_mesh(CapsuleMesh.new(), Vector3(0, 0.9, 0), color)
	(_body.mesh as CapsuleMesh).radius = 0.3
	(_body.mesh as CapsuleMesh).height = 1.8
	_nose = _add_mesh(BoxMesh.new(), Vector3(0, 1.5, -0.3), Color(0.1, 0.1, 0.1))
	(_nose.mesh as BoxMesh).size = Vector3(0.15, 0.15, 0.3)
	_limb = _add_mesh(SphereMesh.new(), Vector3(0, 1.5, 0), Color(1, 0.85, 0.2))
	(_limb.mesh as SphereMesh).radius = 0.12
	(_limb.mesh as SphereMesh).height = 0.24
	_limb.visible = false
	_guard_vis = _add_mesh(BoxMesh.new(), Vector3(0, 1.2, -0.45), Color(0.3, 0.7, 1.0, 0.4))
	(_guard_vis.mesh as BoxMesh).size = Vector3(0.7, 1.1, 0.08)
	(_guard_vis.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_guard_vis.visible = false
	show_debug_label = true

## Corner colour (HUD portraits, name plates).
func base_color() -> Color:
	return _base_color

func _add_mesh(mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	add_child(mi)
	return mi

## Advance exactly one 60 Hz frame.
func tick() -> void:
	state_frame += 1
	_buffer_age += 1
	if slip_counter > 0:
		slip_counter -= 1
	_move_input = Vector2.ZERO
	_guard_held = false
	if controller and controls_enabled:
		var id: StringName = controller.poll_attack()
		if id != &"":
			_buffered = id
			_buffer_age = 0
		_move_input = controller.get_move()
		_guard_held = controller.is_guard_held()
	elif not controls_enabled:
		_buffered = &""
	if _buffer_age > BUFFER_FRAMES:
		_buffered = &""
	match state:
		State.ATTACK:
			_tick_attack()
		State.CHECK:
			if state_frame >= CHECK_STARTUP + CHECK_ACTIVE + CHECK_RECOVERY:
				_enter(State.IDLE)
		State.HITSTUN, State.BLOCKSTUN, State.STAGGER, State.SWEPT:
			stun_frames -= 1
			if stun_frames <= 0:
				_enter(State.IDLE)
		State.SLIP:
			if state_frame > SLIP_STARTUP + SLIP_ACTIVE and moves.has(_buffered):
				var id := _buffered
				_buffered = &""
				_start_attack(moves[id])  # slip-counter: throw straight out of the slip
			elif state_frame >= SLIP_STARTUP + SLIP_ACTIVE + SLIP_RECOVERY:
				_enter(State.IDLE)
		State.CLINCH:
			if _buffered == &"slip":
				_buffered = &""
			if _buffered != &"":
				_clinch_intent = _buffered
				_buffered = &""
		State.KNOCKDOWN, State.KO:
			pass  # FightFlow decides when (if) we get up
		_:
			_tick_free()
	match state:
		State.IDLE, State.MOVE:
			stam.regen(Stamina.REGEN_IDLE, body.ratio(MoveData.Zone.BODY))
		State.GUARD:
			stam.regen(Stamina.REGEN_GUARD, body.ratio(MoveData.Zone.BODY))
	_apply_movement()
	if model:
		model.update(self)
		_update_label()
	elif _body:
		_update_visuals()

func _enter(s: State) -> void:
	state = s
	state_frame = 0
	if s != State.ATTACK:
		current_move = null
	if s != State.GUARD:
		guard_frames = 0
	if s != State.CLINCH:
		status_note = ""

func _tick_free() -> void:
	if _buffered != &"":
		var id := _buffered
		_buffered = &""
		if id == &"check":
			_start_check()
			return
		if id == &"slip":
			_start_slip()
			return
		if moves.has(id):
			_start_attack(moves[id])
			return
	if _guard_held:
		if state != State.GUARD:
			_enter(State.GUARD)
		guard_frames += 1
	elif _move_input.length() > 0.1:
		if state != State.MOVE:
			_enter(State.MOVE)
	elif state != State.IDLE:
		_enter(State.IDLE)

func _start_attack(m: MoveData) -> void:
	var scale := stam.frame_scale()
	_enter(State.ATTACK)
	current_move = m
	move_has_hit = false
	_eff_startup = roundi(m.startup * scale)
	_eff_active = m.active
	_eff_recovery = roundi(m.recovery * scale)
	stam.spend(m.stamina_cost)
	attack_started.emit(self, m)

func _start_check() -> void:
	_enter(State.CHECK)
	stam.spend(CHECK_COST)

## Slip side comes from the sideways part of the move input (relative to facing); none = slip right,
## outside the opponent's jab.
func _start_slip() -> void:
	var local := global_basis.inverse() * Vector3(_move_input.x, 0, _move_input.y)
	slip_side = -1.0 if local.x < -0.3 else 1.0
	_enter(State.SLIP)
	stam.spend(SLIP_COST)

func is_slipping() -> bool:
	return state == State.SLIP and state_frame > SLIP_STARTUP and state_frame <= SLIP_STARTUP + SLIP_ACTIVE

func is_checking() -> bool:
	return state == State.CHECK and state_frame > CHECK_STARTUP and state_frame <= CHECK_STARTUP + CHECK_ACTIVE

## Effective (fatigue-scaled) frame data of the current attack: x startup, y active, z recovery.
func attack_timing() -> Vector3i:
	return Vector3i(_eff_startup, _eff_active, _eff_recovery)

func attack_phase() -> StringName:
	if state != State.ATTACK or current_move == null:
		return &""
	if state_frame <= _eff_startup:
		return &"startup"
	if state_frame <= _eff_startup + _eff_active:
		return &"active"
	return &"recovery"

func _tick_attack() -> void:
	if state_frame >= _eff_startup + _eff_active + _eff_recovery:
		_enter(State.IDLE)
		return
	if attack_phase() == &"active" and not move_has_hit:
		if current_move.action == MoveData.Action.CLINCH_ENTRY:
			_try_clinch()
		else:
			_try_hit()

func _try_clinch() -> void:
	if opponent == null or opponent.is_down():
		return
	var d := opponent.global_position - global_position
	d.y = 0
	if d.length() <= current_move.reach:
		move_has_hit = true
		clinch_requested.emit(self)  # FightFlow creates the Clinch, which moves both of us into CLINCH

func _try_hit() -> void:
	if opponent == null or opponent.is_down():
		return
	var d := opponent.global_position - global_position
	d.y = 0
	if d.length() > current_move.reach:
		return
	move_has_hit = true
	var m := current_move
	var res := CombatResolver.resolve(m, snapshot(), opponent.snapshot(), rng)
	slip_counter = 0
	if res.outcome == CombatResolver.Outcome.SLIPPED:
		opponent.slip_counter = SLIP_COUNTER_FRAMES
	opponent.receive(res, m)
	if res.attacker_damage > 0.0:
		body.apply(MoveData.Zone.LEGS, res.attacker_damage)
		_flash(Color(1.0, 0.5, 0.1))
	if res.attacker_stagger > 0:
		stun_frames = res.attacker_stagger
		_enter(State.STAGGER)
	move_resolved.emit(self, opponent, m, res)

func snapshot() -> CombatResolver.Snapshot:
	var s := CombatResolver.Snapshot.new()
	s.guarding = state == State.GUARD or is_framing()
	s.framing = is_framing()
	s.guard_frames = guard_frames if state == State.GUARD else 999  # no parries from inside the clinch
	s.checking = is_checking()
	s.slipping = is_slipping()
	s.counter_ready = slip_counter > 0
	s.mid_attack = is_committed_to_attack()
	s.stamina_ratio = stam.ratio()
	s.fatigue = stam.fatigue()
	s.leg_ratio = body.ratio(MoveData.Zone.LEGS)
	s.zone_hp = body.hp
	s.cut = body.cut
	return s

## Frames until the current attack's hitbox goes live (0 while active, -1 if not attacking / past it).
func frames_to_active() -> int:
	var p := attack_phase()
	if p == &"startup":
		return _eff_startup - state_frame + 1
	return 0 if p == &"active" else -1

## Frames left until the fighter can act again (attack, check, stun). 0 when free.
func frames_until_free() -> int:
	match state:
		State.ATTACK:
			return maxi(0, _eff_startup + _eff_active + _eff_recovery - state_frame)
		State.CHECK:
			return maxi(0, CHECK_STARTUP + CHECK_ACTIVE + CHECK_RECOVERY - state_frame)
		State.SLIP:
			return maxi(0, SLIP_STARTUP + SLIP_ACTIVE + SLIP_RECOVERY - state_frame)
		State.HITSTUN, State.BLOCKSTUN, State.STAGGER, State.SWEPT:
			return maxi(0, stun_frames)
	return 0

func is_committed_to_attack() -> bool:
	var p := attack_phase()
	return p == &"startup" or p == &"active"

func is_down() -> bool:
	return state == State.KNOCKDOWN or state == State.KO or state == State.SWEPT

## Inside the clinch, hits don't knock you out of CLINCH (the Clinch applies its own lockout) unless they drop you.
func receive(res: Dictionary, m: MoveData) -> void:
	var clinched := state == State.CLINCH
	match res.outcome:
		CombatResolver.Outcome.HIT:
			last_hit_zone = m.zone
			body.apply(m.zone, res.damage)
			if res.cut_delta > 0.0:
				body.add_cut(res.cut_delta)
			if res.knockdown:
				last_knockdown_zone = m.zone
				_enter(State.KNOCKDOWN)
			elif not clinched:
				stun_frames = res.stun
				_enter(State.HITSTUN)
			_flash(Color.WHITE)
		CombatResolver.Outcome.BLOCK:
			body.apply(m.zone if res.zone < 0 else res.zone, res.damage)
			stam.spend(res.stamina_loss)
			if not clinched:
				stun_frames = res.stun
				_enter(State.BLOCKSTUN)
			_flash(Color(0.3, 0.8, 1.0))
		CombatResolver.Outcome.PARRY:
			_flash(Color(1, 1, 0.2))
		CombatResolver.Outcome.CHECKED:
			body.apply(MoveData.Zone.LEGS, res.damage)
			_flash(Color(0.3, 1.0, 0.4))

# --- clinch interface (used by Clinch) ---

func enter_clinch() -> void:
	_buffered = &""
	_clinch_intent = &""
	velocity = Vector3.ZERO
	_enter(State.CLINCH)

func exit_clinch() -> void:
	if state == State.CLINCH:
		_enter(State.IDLE)

## The clinch action the player pressed this frame (consumed).
func take_clinch_intent() -> StringName:
	var i := _clinch_intent
	_clinch_intent = &""
	return i

## Guard held inside the clinch = forearms framing: blocks knees, resists pummeling.
func is_framing() -> bool:
	return state == State.CLINCH and _guard_held

func get_move_input() -> Vector2:
	return _move_input

func get_swept() -> void:
	stun_frames = SWEPT_FRAMES
	stam.spend(SWEPT_STAMINA)
	_enter(State.SWEPT)

# --- called by FightFlow ---

func rise() -> void:
	stays_down = false
	body.recover_after_knockdown(last_knockdown_zone)
	_enter(State.IDLE)

## Cancel whatever the fighter is doing (referee stepped in). Downed fighters stay down.
func halt() -> void:
	_buffered = &""
	if not is_down():
		_enter(State.IDLE)

func set_ko() -> void:
	stays_down = true
	_enter(State.KO)

func reset_for_round(pos: Vector3) -> void:
	stays_down = false
	slip_counter = 0
	global_position = pos
	velocity = Vector3.ZERO
	_buffered = &""
	_enter(State.IDLE)

# --- movement + visuals ---

func _flash(c: Color) -> void:
	_flash_color = c
	_flash_frames = 6
	if model:
		model.flash(c)

func _apply_movement() -> void:
	var speed := 0.0
	match state:
		State.IDLE, State.MOVE:
			speed = SPEED * body.speed_factor()
		State.GUARD:
			speed = GUARD_SPEED * body.speed_factor()
	# Own integration instead of move_and_slide(): fighters are the only moving bodies, the ring/cage edge is a
	# clamp, and this stays deterministic no matter when tick() is called (physics step or a test).
	velocity = Vector3(_move_input.x, 0, _move_input.y) * speed
	position += velocity * FRAME
	if opponent and state != State.CLINCH and opponent.state != State.CLINCH:
		var d := global_position - opponent.global_position
		d.y = 0
		var min_d := BODY_RADIUS * 2.0
		if d.length() < min_d:
			var away := d.normalized() if d.length() > 0.001 else Vector3.LEFT
			global_position += away * (min_d - d.length())
	position = bounds.clamp_position(position)
	if opponent and not is_down():
		var to := opponent.global_position - global_position
		to.y = 0
		if to.length() > 0.01:
			rotation.y = atan2(-to.x, -to.z)

func _update_visuals() -> void:
	var mat := _body.material_override as StandardMaterial3D
	if _flash_frames > 0:
		_flash_frames -= 1
		mat.albedo_color = _flash_color
	else:
		mat.albedo_color = _base_color
	var down := is_down()
	_body.rotation_degrees.x = 90.0 if down else 0.0
	_body.position.y = 0.3 if down else 0.9
	_nose.visible = not down
	_guard_vis.visible = state == State.GUARD or is_framing()
	if _guard_vis.visible:
		var c := Color(1, 1, 0.2, 0.5) if guard_frames <= CombatResolver.PARRY_WINDOW else Color(0.3, 0.7, 1.0, 0.4)
		(_guard_vis.material_override as StandardMaterial3D).albedo_color = c
	_limb.visible = (state == State.ATTACK and current_move != null) or state == State.CHECK
	if state == State.CHECK:
		_limb.position = Vector3(0, 0.6, -0.25)
		(_limb.material_override as StandardMaterial3D).albedo_color = Color(0.3, 1, 0.4) if is_checking() else Color(0.5, 0.5, 0.5)
	elif _limb.visible:
		(_limb.material_override as StandardMaterial3D).albedo_color = Color(1, 0.85, 0.2)
	if _limb.visible and state == State.ATTACK:
		var t := 1.0
		if state_frame <= _eff_startup:
			t = float(state_frame) / _eff_startup * 0.8
		elif state_frame > _eff_startup + _eff_active:
			t = 1.0 - float(state_frame - _eff_startup - _eff_active) / _eff_recovery
		var h: float = [1.55, 1.1, 0.5][current_move.zone]
		_limb.position = Vector3(0, h, -current_move.reach * 0.9 * t)
	_update_label()

## Overhead debug text (state, move, clinch position, cut). Always on for the greybox, F5 with the model.
func _update_label() -> void:
	_label.visible = show_debug_label
	if not show_debug_label:
		return
	var txt: String = State.keys()[state]
	if state == State.ATTACK and current_move:
		txt += " " + current_move.display_name
	if status_note != "":
		txt += " " + status_note
	if body.cut > 0.0:
		txt += "  [CUT]"
	_label.text = txt
	# Stagger the two overhead labels when the fighters are close (clinch) so they don't overlap.
	var close := opponent != null and global_position.distance_to(opponent.global_position) < 1.2
	_label.position.y = 2.45 if close and global_position.x > opponent.global_position.x else 2.2
