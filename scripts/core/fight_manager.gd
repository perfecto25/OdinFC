class_name FightManager
extends Node3D
## Builds the arena (ring or cage), two fighters, camera and HUD, then drives FightFlow at 60 Hz.

const HELP := "W forward  S back  A/D sidestep (double-tap W = superman punch, S = leap back) | J jab  K cross  U lead hook  I rear hook  O uppercut\nL teep  ; side kick  Y high kick  H round kick (hold W = high, S = low)  N knee\nSpace guard (tap = parry)  Q slip (+A/D side)  E check  C clinch | in clinch: L or walk away = escape  C pummel  N knee (+W head)  H sweep  Space frame\nEsc pause | Backspace freeze frame | Tab camera | F1 opponent: %s | F2 end round (debug) | F3 arena: %s | F4 hide help | F5 debug labels\nPad: D-pad move (double-tap Up/Down = lunge), R guard, Start pause, Select camera\n%s"
const CPU_FOOT_SPEED := 0.9  ## the opponent's footwork, relative to its fighter's own speed
## Moves the player's fighter throws twice as fast. Not the CPU: given a half-length uppercut it threw
## little else (about 120 a fight instead of 13).
const PLAYER_FAST_MOVES: Array[StringName] = [&"uppercut"]
## F1 cycles through these: the CPU fighter's own rating, the three AI levels, then the training-dummy modes.
const OPPONENTS := ["AI Fighter rating", "AI Easy", "AI Medium", "AI Hard", "Dummy IDLE", "Dummy GUARD", "Dummy PARRY_SPAM",
		"Dummy JAB_SPAM", "Dummy CHECK", "Dummy CLINCHER"]

var flow: FightFlow
var _dummy: DummyController
var _ai: AIController
var _cpu: Fighter
var _player: PlayerController
var _opponent := 1
var _seed := 0
var _hud: FightHud
var _arena: Arena
var _cam: FightCamera
var _pause: PauseMenu
var _hitstop := 0  ## frames the simulation is frozen for impact weight (cosmetic; sims never see it)

func _ready() -> void:
	InputSetup.register()
	_arena = Arena.create(GameState.arena)
	add_child(_arena)
	var ca: Dictionary = GameState.CORNERS[GameState.player_corner]
	var cb: Dictionary = GameState.CORNERS[GameState.opponent_corner()]
	var fa := _make_fighter(ca.name, ca.color, Vector3(-1.6, 0, 0), GameState.player_data())
	var fb := _make_fighter(cb.name, cb.color, Vector3(1.6, 0, 0), GameState.opponent_data())
	fa.opponent = fb
	fb.opponent = fa
	var pc := PlayerController.new()
	add_child(pc)
	_player = pc
	pc.me = fa
	fa.controller = pc
	_cpu = fb
	fb.foot_speed *= CPU_FOOT_SPEED
	for id in PLAYER_FAST_MOVES:
		fa.double_move_speed(id)
	_dummy = DummyController.new()
	_dummy.me = fb
	add_child(_dummy)

	var cfg := GameState.fight_config()
	_seed = cfg.seed
	_opponent = GameState.opponent_index if GameState.opponent_index >= 0 \
			else {"rating": 0, "easy": 1, "medium": 2, "hard": 3, "dummy": 4}.get(GameState.cpu, 0)
	_apply_opponent()
	flow = FightFlow.new(fa, fb, cfg)
	flow.fight_ended.connect(_on_fight_ended)
	print("Fight seed: ", cfg.seed)

	_hud = FightHud.new()
	add_child(_hud)
	_hud.setup(flow)

	for f in [fa, fb]:
		f.move_resolved.connect(_on_move_resolved)
		f.attack_started.connect(func(_a, _m): Sfx.play(&"whoosh", 0.35))
	flow.phase_changed.connect(_on_phase)
	_on_phase(flow.phase)
	Sfx.set_crowd(true)
	_pause = PauseMenu.new()
	add_child(_pause)
	add_child(FreezeFrame.new())

	var cam := FightCamera.new()
	_cam = cam
	cam.a = fa
	cam.b = fb
	cam.flow = flow
	cam.base_height = _arena.camera_height
	add_child(cam)
	cam.current = true
	print("Renderer: ", RenderingServer.get_video_adapter_name(), " | ",
		RenderingServer.get_current_rendering_driver_name())

func _exit_tree() -> void:
	Sfx.set_crowd(false)

func _physics_process(_delta: float) -> void:
	if _hitstop > 0:
		_hitstop -= 1
	else:
		flow.tick()
	_player.pad_layout = Settings.pad_layout  # it can be rebound from the pause menu
	_hud.help_text = HELP % [OPPONENTS[_opponent], GameState.arena,
			PadLayout.help(Settings.pad_layout, PadLayout.connected_names())]

func _unhandled_input(event: InputEvent) -> void:
	var pad_skip: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A \
			and (flow.phase == FightFlow.Phase.ROUND_BREAK or flow.phase == FightFlow.Phase.OVER)
	if event.is_action_pressed("skip") or pad_skip:  # Enter / pad bottom button
		if flow.phase == FightFlow.Phase.ROUND_BREAK:
			flow.skip_break()
		elif flow.phase == FightFlow.Phase.OVER:
			get_tree().reload_current_scene()
	elif event.is_action_pressed("dummy_cycle"):
		_opponent = (_opponent + 1) % OPPONENTS.size()
		GameState.opponent_index = _opponent
		_apply_opponent()
	elif event.is_action_pressed("arena_cycle"):
		GameState.arena = "cage" if GameState.arena == "ring" else "ring"
		get_tree().reload_current_scene()  # restarts the fight in the other arena
	elif event.is_action_pressed("debug_labels"):
		for f in flow.fighters:
			f.show_debug_label = not f.show_debug_label
	elif event.is_action_pressed("help_toggle"):
		_hud.help_visible = not _hud.help_visible
	elif event.is_action_pressed("debug_end_round") and flow.phase == FightFlow.Phase.FIGHTING:
		flow.clock = 1

func _on_move_resolved(_att: Fighter, _def: Fighter, m: MoveData, res: Dictionary) -> void:
	var kind := &"punch"
	match m.strike_type:
		MoveData.StrikeType.KICK, MoveData.StrikeType.TEEP: kind = &"kick"
		MoveData.StrikeType.KNEE: kind = &"knee"
	var stop := 0
	var trauma := 0.0
	match res.outcome:
		CombatResolver.Outcome.HIT:
			var power := clampf(res.damage / 10.0, 0.0, 1.5)
			Sfx.play(kind, 0.6 + 0.4 * minf(power, 1.0))
			stop = 2 + int(power * 3.0)
			trauma = 0.12 + 0.25 * power
			if res.counter:
				stop += 2
				trauma += 0.1
			if res.knockdown:
				stop = 10
				trauma = 0.9
				Sfx.play(&"knockdown")
		CombatResolver.Outcome.BLOCK:
			Sfx.play(&"block", 0.7)
			stop = 1
			trauma = 0.05
		CombatResolver.Outcome.CHECKED:
			Sfx.play(&"check")
			stop = 4
			trauma = 0.3
		CombatResolver.Outcome.PARRY:
			Sfx.play(&"parry", 0.6)
			stop = 3
	if Settings.hit_stop:
		_hitstop = maxi(_hitstop, stop)
	_arena.crowd_react(trauma * 0.6 + (0.5 if res.knockdown else 0.0))
	if _cam:
		_cam.shake_enabled = Settings.camera_shake
		_cam.shake(trauma)

func _on_phase(p: FightFlow.Phase) -> void:
	if p == FightFlow.Phase.INTRO or p == FightFlow.Phase.ROUND_BREAK or p == FightFlow.Phase.OVER:
		Sfx.play(&"bell", 0.9, 0.0)

## Swap the CPU's controller to OPPONENTS[_opponent]. The dummy's own mode follows the list index.
func _apply_opponent() -> void:
	if _ai:
		_ai.queue_free()
		_ai = null
	if _opponent < 4:
		var p: AIController.Profile
		if _opponent == 0:
			p = AIController.Profile.for_rating(_cpu.data.difficulty if _cpu.data else 3)
		else:
			p = AIController.Profile.for_difficulty((_opponent - 1) as AIController.Difficulty)
		_ai = AIController.new(p.apply_style(_cpu.data), _seed + 1)
		_ai.me = _cpu
		add_child(_ai)
		_cpu.controller = _ai
	else:
		_dummy.mode = (_opponent - 4) as DummyController.Mode
		_cpu.controller = _dummy

func _on_fight_ended(r: Dictionary) -> void:
	if r.winner:
		r.winner.model.override_clip = "victory"
		flow.other(r.winner).model.override_clip = "defeat"
	print("Result: %s, winner %s, round %d, cards %s" % [r.method, r.winner.display_name if r.winner else "-", r.round, str(r.totals)])

func _make_fighter(n: String, color: Color, pos: Vector3, data: FighterData) -> Fighter:
	var f: Fighter = load("res://scenes/fighter.tscn").instantiate()
	f.name = n
	f.display_name = n
	add_child(f)
	f.setup(color, pos, true)
	f.apply_data(data)
	f.bounds = _arena.bounds
	return f
