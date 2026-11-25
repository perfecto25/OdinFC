extends Node3D
## Builds the arena (ring or cage), two fighters, camera and HUD, then drives FightFlow at 60 Hz.

const HELP := "WASD move | J jab  K cross  U lead hook  I rear hook  O uppercut | L teep  ; side kick  H round kick (W=high, S=low)  N knee\nSpace guard (tap = parry)  Q slip (+A/D side)  E check  C clinch | in clinch: L or walk away = escape  C pummel  N knee (+W head)  H sweep  Space frame\nTab camera | F1 opponent: %s | F2 end round (debug) | F3 arena: %s | F4 hide help | F5 debug labels"
## F1 cycles through these: the three AI levels, then the training-dummy modes.
const OPPONENTS := ["AI Easy", "AI Medium", "AI Hard", "Dummy IDLE", "Dummy GUARD", "Dummy PARRY_SPAM",
		"Dummy JAB_SPAM", "Dummy CHECK", "Dummy CLINCHER"]

var flow: FightFlow
var _dummy: DummyController
var _ai: AIController
var _cpu: Fighter
var _opponent := 1
var _seed := 0
var _hud: FightHud
var _arena: Arena

func _ready() -> void:
	InputSetup.register()
	_arena = Arena.create(GameState.arena)
	add_child(_arena)
	var fa := _make_fighter("Red", Color(0.8, 0.15, 0.15), Vector3(-1.6, 0, 0))
	var fb := _make_fighter("Blue", Color(0.15, 0.3, 0.85), Vector3(1.6, 0, 0))
	fa.opponent = fb
	fb.opponent = fa
	var pc := PlayerController.new()
	add_child(pc)
	fa.controller = pc
	_cpu = fb
	_dummy = DummyController.new()
	_dummy.me = fb
	add_child(_dummy)

	var cfg := GameState.fight_config()
	_seed = cfg.seed
	_opponent = GameState.opponent_index if GameState.opponent_index >= 0 \
			else {"easy": 0, "medium": 1, "hard": 2, "dummy": 3}.get(GameState.cpu, 1)
	_apply_opponent()
	flow = FightFlow.new(fa, fb, cfg)
	flow.fight_ended.connect(_on_fight_ended)
	print("Fight seed: ", cfg.seed)

	_hud = FightHud.new()
	add_child(_hud)
	_hud.setup(flow)

	var cam := FightCamera.new()
	cam.a = fa
	cam.b = fb
	cam.flow = flow
	cam.base_height = _arena.camera_height
	add_child(cam)
	cam.current = true
	print("Renderer: ", RenderingServer.get_video_adapter_name(), " | ",
		RenderingServer.get_current_rendering_driver_name())

func _physics_process(_delta: float) -> void:
	flow.tick()
	_hud.help_text = HELP % [OPPONENTS[_opponent], GameState.arena]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("skip"):
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

## Swap the CPU's controller to OPPONENTS[_opponent]. The dummy's own mode follows the list index.
func _apply_opponent() -> void:
	if _ai:
		_ai.queue_free()
		_ai = null
	if _opponent < 3:
		_ai = AIController.create(_opponent as AIController.Difficulty, _seed + 1)
		_ai.me = _cpu
		add_child(_ai)
		_cpu.controller = _ai
	else:
		_dummy.mode = (_opponent - 3) as DummyController.Mode
		_cpu.controller = _dummy

func _on_fight_ended(r: Dictionary) -> void:
	if r.winner:
		r.winner.model.override_clip = "victory"
		flow.other(r.winner).model.override_clip = "defeat"
	print("Result: %s, winner %s, round %d, cards %s" % [r.method, r.winner.display_name if r.winner else "-", r.round, str(r.totals)])

func _make_fighter(n: String, color: Color, pos: Vector3) -> Fighter:
	var f: Fighter = load("res://scenes/fighter.tscn").instantiate()
	f.name = n
	f.display_name = n
	add_child(f)
	f.setup(color, pos, true)
	f.bounds = _arena.bounds
	return f
