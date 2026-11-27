extends Control
## Main menu -> fight setup (fighters, CPU control, arena, corner colour, rounds) -> pre-fight fighter page (if
## either fighter has one) -> fight scene; plus settings.
## Choices are stored in GameState, which FightManager reads when the fight scene loads.

var _home: VBoxContainer
var _setup: PanelContainer
var _profile: FighterProfile
var _settings: SettingsPanel

func _ready() -> void:
	InputSetup.register()
	if GameState.direct_launch:  # started with --cpu/--arena/...: straight into the fight (once)
		GameState.direct_launch = false
		get_tree().change_scene_to_file.call_deferred("res://scenes/fight.tscn")
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_home = VBoxContainer.new()
	_home.add_theme_constant_override("separation", 14)
	var logo := TextureRect.new()
	logo.texture = Branding.logo(MenuKit.GOLD)
	logo.custom_minimum_size = Vector2(300, 300)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_home.add_child(logo)
	_home.add_child(MenuKit.label("MUAY THAI KICKBOXING", 22, MenuKit.DIM))
	_home.get_child(-1).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_home.add_child(MenuKit.button("Fight", func(): _show(_setup)))
	_home.add_child(MenuKit.button("Settings", func(): _show(_settings)))
	_home.add_child(MenuKit.button("Quit", func(): get_tree().quit()))
	center.add_child(_home)

	_setup = _build_setup()
	center.add_child(_setup)
	_profile = FighterProfile.new()
	_profile.confirmed.connect(_start_fight)
	_profile.closed.connect(func(): _show(_setup))
	center.add_child(_profile)
	_settings = SettingsPanel.new()
	_settings.closed.connect(func(): _show(_home))
	center.add_child(_settings)
	_show(_home)
	Sfx.set_crowd(false)

func _show(c: Control) -> void:
	for n in [_home, _setup, _profile, _settings]:
		n.visible = n == c
	for b in c.find_children("*", "Button", true, false):
		b.grab_focus()
		break

func _build_setup() -> PanelContainer:
	var p := MenuKit.panel(660.0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(MenuKit.label("FIGHT SETUP", 32, MenuKit.GOLD))
	var roster := Roster.all()
	if not roster.is_empty():
		var fnames: Array = roster.map(func(d: FighterData): return d.display_name)
		var you := MenuKit.label("", 16, MenuKit.DIM)
		var them := MenuKit.label("", 16, MenuKit.DIM)
		GameState.opponent_fighter = GameState.opponent_data().id  # stays put if "Your fighter" changes
		var pick := func(i: int, cpu: bool, info: Label):
			var d := roster[i]
			if cpu:
				GameState.opponent_fighter = d.id
			else:
				GameState.player_fighter = d.id
			info.text = _tape(d)
		v.add_child(MenuKit.row("Your fighter", MenuKit.option(fnames, Roster.index_of(GameState.player_data().id),
				func(i): pick.call(i, false, you))))
		v.add_child(you)
		v.add_child(MenuKit.row("Opponent", MenuKit.option(fnames, Roster.index_of(GameState.opponent_data().id),
				func(i): pick.call(i, true, them))))
		v.add_child(them)
		you.text = _tape(GameState.player_data())
		them.text = _tape(GameState.opponent_data())
	v.add_child(MenuKit.row("CPU", MenuKit.option(FightManager.OPPONENTS, maxi(GameState.opponent_index, 0),
			func(i): GameState.opponent_index = i)))
	v.add_child(MenuKit.row("Arena", MenuKit.option(["Ring", "Cage"], 1 if GameState.arena == "cage" else 0,
			func(i): GameState.arena = "cage" if i == 1 else "ring")))
	var names: Array = GameState.CORNERS.map(func(c): return c.name)
	v.add_child(MenuKit.row("Your corner", MenuKit.option(names, GameState.player_corner,
			func(i): GameState.player_corner = i)))
	v.add_child(MenuKit.row("Rounds", MenuKit.option([1, 3, 5], [1, 3, 5].find(GameState.rounds),
			func(i): GameState.rounds = [1, 3, 5][i])))
	var mins := [1, 2, 3]
	v.add_child(MenuKit.row("Round length", MenuKit.option(["1 min", "2 min", "3 min"],
			clampi(int(GameState.round_seconds / 60.0) - 1, 0, 2), func(i): GameState.round_seconds = mins[i] * 60.0)))
	v.add_child(MenuKit.button("Start fight", _show_profile_or_fight))
	v.add_child(MenuKit.button("Back", func(): _show(_home)))
	return p

## The player's page if they have one, else the opponent's; straight to the fight if neither does.
func _show_profile_or_fight() -> void:
	var sides := [[GameState.player_data(), GameState.player_corner],
			[GameState.opponent_data(), GameState.opponent_corner()]]
	for side in sides:
		var d: FighterData = side[0]
		if d and d.has_profile():
			_profile.show_fighter(d, GameState.CORNERS[side[1]].color)
			_show(_profile)
			return
	_start_fight()

func _start_fight() -> void:
	GameState.seed = -1
	get_tree().change_scene_to_file("res://scenes/fight.tscn")

## One-line tale of the tape: "#2 · "The White Lotus" · Thailand · 175 cm · 71 kg · Orthodox · CPU ★★★★★"
func _tape(d: FighterData) -> String:
	var bits: Array[String] = []
	if d.ranking > 0:
		bits.append("#%d" % d.ranking)
	if d.nickname != "":
		bits.append("\"%s\"" % d.nickname)
	if d.country != "":
		bits.append(d.country)
	bits.append(d.tale_of_the_tape())
	bits.append("CPU " + "★".repeat(d.difficulty) + "☆".repeat(5 - d.difficulty))
	return "   " + " · ".join(bits)

func _unhandled_input(event: InputEvent) -> void:
	if (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")) and not _home.visible:
		if _settings.visible:
			_settings.closed.emit()
		elif _profile.visible:
			_profile.closed.emit()
		else:
			_show(_home)
