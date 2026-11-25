extends SceneTree
## Visual check: runs the fight scene with a real renderer and saves screenshots of each camera shot /
## HUD state (intro, broadcast, over-the-shoulder, clinch, knockdown, round break, result).
##   godot --path . -s tools/capture.gd -- --arena=cage --out=/some/dir
## Needs a display (not --headless). Forces game states directly, so it's a look-test, not a fight sim.

var _out := "user://captures"
var _fight: Node

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.split("=")[1]
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()

func _run() -> void:
	var gs := root.get_node("GameState")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena="):
			gs.arena = arg.split("=")[1]
	gs.cpu = "dummy"
	gs.seed = 3
	_fight = load("res://scenes/fight.tscn").instantiate()
	root.add_child(_fight)
	var flow: FightFlow = _fight.flow
	var cam: FightCamera = root.get_viewport().get_camera_3d()
	var red := flow.fighters[0]
	var blue := flow.fighters[1]
	await _frames(30)
	await _shot("1_intro_wide")
	await _frames(80)
	red.body.hp[MoveData.Zone.HEAD] = 62.0
	red.body.hp[MoveData.Zone.LEGS] = 81.0
	blue.body.hp[MoveData.Zone.BODY] = 44.0
	blue.body.hp[MoveData.Zone.HEAD] = 23.0
	blue.body.cut = 1.2
	blue.stam.value = 40.0
	red.global_position = Vector3(-0.9, 0, 1.2)
	blue.global_position = Vector3(0.6, 0, -0.4)
	await _frames(70)
	await _shot("2_broadcast")
	cam.over_shoulder = true
	cam._cut(FightCamera.Shot.OVER_SHOULDER)
	await _frames(20)
	await _shot("3_over_shoulder")
	cam.over_shoulder = false
	cam._cut(FightCamera.Shot.BROADCAST)
	# Knockdown on Blue.
	blue.body.knockdowns_round += 1
	blue.body.knockdowns_total += 1
	blue._enter(Fighter.State.KNOCKDOWN)
	flow._pending_kd = blue
	await _frames(100)
	await _shot("4_knockdown")
	# End of round 1.
	flow.rise_at = 2
	await _frames(400)
	flow.clock = 1
	await _frames(10)
	await _shot("5_round_break")
	# Fast-forward to the final bell.
	while flow.phase != FightFlow.Phase.OVER:
		flow.skip_break()
		await _frames(100)
		flow.clock = 1
		await _frames(10)
	await _frames(80)
	await _shot("6_result")
	quit()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := _out.path_join(name + ".png")
	img.save_png(path)
	print("saved ", path)
