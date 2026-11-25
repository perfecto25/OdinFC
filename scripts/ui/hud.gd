class_name FightHud
extends CanvasLayer
## Broadcast-style HUD.
##   Top:     per-fighter zone health (HEAD / BODY / LEGS, with a trailing "damage ghost") and stamina,
##            KD / CUT badges; clinch meter and short call-outs in the middle.
##   Bottom:  broadcast bar: portraits, names, round, clock (rest countdown in the break), round dots.
##   Centre:  referee banner (ROUND n / FIGHT! / KNOCKDOWN + count / DOCTOR CHECK).
##   Panel:   between-round stats + scorecards; end-of-fight result, fight totals + scorecards.
## Read-only view of FightFlow; built in code (no theme resource yet - fonts/theme come with milestone 7).

const NAVY := Color(0.04, 0.05, 0.09, 0.88)
const NAVY_SOLID := Color(0.05, 0.06, 0.11)
const GOLD := Color(0.95, 0.72, 0.2)
const DIM := Color(0.65, 0.68, 0.75)
const HP_FULL := Color(0.92, 0.95, 0.92)
const HP_MID := Color(1.0, 0.7, 0.2)
const HP_LOW := Color(0.9, 0.15, 0.1)
const STAM := Color(0.35, 0.8, 1.0)
const GHOST := Color(1.0, 1.0, 1.0, 0.55)
const GHOST_HOLD := 0.5      ## seconds the damage ghost waits before draining
const GHOST_DRAIN := 40.0    ## hp per second
const BAR_W := 300.0
const ZONES := [["HEAD", MoveData.Zone.HEAD], ["BODY", MoveData.Zone.BODY], ["LEGS", MoveData.Zone.LEGS]]

var flow: FightFlow
var help_text := ""
var help_visible := true

var _sides: Array = []          ## per fighter: {bars: {zone: {main, ghost, hold}}, stam, kd, cut, name}
var _clock: Label
var _round_label: Label
var _dots: Array[Panel] = []
var _dot_styles := {}
var _banner: PanelContainer
var _banner_big: Label
var _banner_small: Label
var _callout: Label
var _clinch_box: VBoxContainer
var _clinch_bar: ProgressBar
var _clinch_label: Label
var _clinch_hint: Label
var _stats_panel: PanelContainer
var _stats_body: VBoxContainer
var _stats_footer: Label
var _help: Label

func setup(f: FightFlow) -> void:
	flow = f
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	for i in 2:
		_sides.append(_make_top_panel(root, i == 1))
	_make_bottom_bar(root)
	_make_center(root)
	_make_clinch(root)
	_make_stats_panel(root)
	_help = _label(12, DIM)
	root.add_child(_help)
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.offset_left = 14
	_help.offset_bottom = -104
	flow.phase_changed.connect(_on_phase)

# --- building blocks ---

func _label(size: int, color := Color.WHITE, outline := 4) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _style(bg: Color, radius := 4, margin := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb

func _panel(bg: Color, radius := 4, margin := 10.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(bg, radius, margin))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _bar(color: Color, w: float, h: float, mirror: bool, bg := Color(0, 0, 0, 0.55)) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	b.max_value = 100
	b.step = 0.1
	b.fill_mode = ProgressBar.FILL_END_TO_BEGIN if mirror else ProgressBar.FILL_BEGIN_TO_END
	b.add_theme_stylebox_override("fill", _style(color, 2))
	b.add_theme_stylebox_override("background", _style(bg, 2))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

## A zone bar with a damage ghost: a light bar behind the main one that lags, so hits read clearly.
func _ghost_bar(w: float, h: float, mirror: bool) -> Dictionary:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(w, h)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ghost := _bar(GHOST, w, h, mirror)
	var main := _bar(HP_FULL, w, h, mirror, Color(0, 0, 0, 0))
	for b in [ghost, main]:
		holder.add_child(b)
		b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return {"holder": holder, "main": main, "ghost": ghost, "hold": 0.0}

func _make_top_panel(root: Control, right: bool) -> Dictionary:
	var panel := _panel(NAVY, 6, 10)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT if right else Control.PRESET_TOP_LEFT)
	if right:
		panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		panel.offset_right = -14
	else:
		panel.offset_left = 14
	panel.offset_top = 12
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var f: Fighter = flow.fighters[1 if right else 0]
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(6, 22)
	chip.add_theme_stylebox_override("panel", _style(f.base_color(), 1))
	var nm := _label(18)
	nm.text = f.display_name.to_upper()
	var kd := _badge("KD")
	var cut := _badge("CUT", HP_LOW)
	var items: Array = [chip, nm, kd, cut]
	if right:
		items.reverse()
	for c in items:
		head.add_child(c)
	var side := {"bars": {}, "kd": kd, "cut": cut}
	for z in ZONES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var l := _label(11, DIM, 0)
		l.text = z[0]
		l.custom_minimum_size.x = 34
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
		var gb := _ghost_bar(BAR_W, 10 if z[1] == MoveData.Zone.HEAD else 7, right)
		if right:
			row.add_child(gb.holder)
			row.add_child(l)
		else:
			row.add_child(l)
			row.add_child(gb.holder)
		box.add_child(row)
		side.bars[z[1]] = gb
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	var sl := _label(11, DIM, 0)
	sl.text = "STAM"
	sl.custom_minimum_size.x = 34
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	var stam := _bar(STAM, BAR_W, 5, right)
	if right:
		srow.add_child(stam)
		srow.add_child(sl)
	else:
		srow.add_child(sl)
		srow.add_child(stam)
	box.add_child(srow)
	side.stam = stam
	return side

func _badge(text: String, color := GOLD) -> PanelContainer:
	var p := _panel(color, 3, 0)
	(p.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 6
	(p.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 6
	var l := _label(12, NAVY_SOLID, 0)
	l.text = text
	p.add_child(l)
	p.set_meta("label", l)
	p.visible = false
	return p

func _make_bottom_bar(root: Control) -> void:
	var bar := _panel(NAVY, 6, 0)
	root.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -16
	bar.custom_minimum_size = Vector2(780, 76)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	for i in 2:
		var f: Fighter = flow.fighters[i]
		var right := i == 1
		var por := _portrait(f)
		var names := VBoxContainer.new()
		names.alignment = BoxContainer.ALIGNMENT_CENTER
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var n := _label(24)
		n.text = f.display_name.to_upper()
		var sub := _label(12, DIM, 0)
		sub.text = "%s CORNER" % ("BLUE" if right else "RED")
		for l in [n, sub]:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
			names.add_child(l)
		if right:
			row.add_child(names)
			row.add_child(por)
		else:
			row.add_child(por)
			row.add_child(names)
			row.add_child(_make_clock_block())

func _portrait(f: Fighter) -> Panel:
	# Placeholder portrait: corner colour + initial. FighterData portraits replace this in milestone 8b.
	var p := Panel.new()
	p.custom_minimum_size = Vector2(76, 76)
	var sb := _style(f.base_color().darkened(0.25), 6)
	sb.border_color = f.base_color().lightened(0.2)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	var l := _label(40, Color.WHITE, 0)
	l.text = f.display_name.left(1).to_upper()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return p

func _make_clock_block() -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size.x = 170
	v.add_theme_constant_override("separation", 2)
	_round_label = _label(12, GOLD, 0)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_round_label)
	_clock = _label(30, Color.WHITE, 0)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_clock)
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 6)
	v.add_child(dots)
	_dot_styles = {
		"done": _style(GOLD, 5),
		"now": _style(Color.WHITE, 5),
		"todo": _style(Color(1, 1, 1, 0.15), 5),
	}
	for r in flow.rounds:
		var d := Panel.new()
		d.custom_minimum_size = Vector2(10, 10)
		dots.add_child(d)
		_dots.append(d)
	return v

func _make_center(root: Control) -> void:
	_banner = _panel(NAVY, 4, 0)
	var sb := _banner.get_theme_stylebox("panel") as StyleBoxFlat
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	sb.border_color = GOLD
	sb.border_width_bottom = 3
	root.add_child(_banner)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = -120
	_banner.offset_bottom = -120
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.add_child(v)
	_banner_big = _label(52, Color.WHITE, 0)
	_banner_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_banner_big)
	_banner_small = _label(16, DIM, 0)
	_banner_small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_banner_small)
	_callout = _label(34, GOLD, 6)
	root.add_child(_callout)
	_callout.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_callout.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callout.offset_top = 150

func _make_clinch(root: Control) -> void:
	_clinch_box = VBoxContainer.new()
	root.add_child(_clinch_box)
	_clinch_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_clinch_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_clinch_box.offset_top = 16
	_clinch_label = _label(13, Color.WHITE)
	_clinch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clinch_box.add_child(_clinch_label)
	_clinch_bar = _bar(flow.fighters[0].base_color(), 260, 8, false, flow.fighters[1].base_color())
	_clinch_bar.min_value = -1.0
	_clinch_bar.max_value = 1.0
	_clinch_bar.step = 0.01
	_clinch_box.add_child(_clinch_bar)
	_clinch_hint = _label(12, DIM)
	_clinch_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clinch_box.add_child(_clinch_hint)

func _make_stats_panel(root: Control) -> void:
	_stats_panel = _panel(Color(NAVY_SOLID, 0.94), 8, 22)
	root.add_child(_stats_panel)
	_stats_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_stats_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stats_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_stats_panel.offset_top = -50
	_stats_panel.offset_bottom = -50
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_stats_panel.add_child(v)
	_stats_body = VBoxContainer.new()
	_stats_body.add_theme_constant_override("separation", 10)
	v.add_child(_stats_body)
	_stats_footer = _label(13, DIM, 0)
	_stats_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_stats_footer)
	_stats_panel.visible = false

# --- stats / scorecards (rebuilt when a round ends or the fight is over) ---

func _on_phase(p: FightFlow.Phase) -> void:
	if p == FightFlow.Phase.ROUND_BREAK:
		_fill_stats("END OF ROUND %d" % flow.round, "", [flow.stats[flow.round - 1]])
	elif p == FightFlow.Phase.OVER:
		var r := flow.result
		var title := ("%s WINS" % r.winner.display_name.to_upper()) if r.winner else "DRAW"
		var sub := "%s  ·  Round %d, %d:%02d" % [_method_name(r.method), r.round, r.time / 60, r.time % 60]
		_fill_stats(title, sub, flow.stats)

func _fill_stats(title: String, subtitle: String, rounds: Array) -> void:
	for c in _stats_body.get_children():
		c.queue_free()
	var t := _label(30, Color.WHITE, 0)
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_body.add_child(t)
	if subtitle != "":
		var s := _label(15, GOLD, 0)
		s.text = subtitle
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_stats_body.add_child(s)
	_stats_body.add_child(_stats_grid(rounds))
	var cards := _scorecard_grid()
	if cards:
		_stats_body.add_child(HSeparator.new())
		_stats_body.add_child(cards)

## Rows for each fighter, summed over `rounds` (each = [RoundStats red, RoundStats blue]).
## Defensive rows (blocks, parries) come from the opponent's strikes that this fighter stopped.
static func sum_stats(rounds: Array) -> Array:
	var out := [{}, {}]
	for k in 2:
		var o := 1 - k
		var d := {"landed": 0, "thrown": 0, "damage": 0.0, "kd": 0, "blocks": 0, "parries": 0, "checks": 0,
				"sweeps": 0, "control": 0}
		for rs in rounds:
			var me: Judges.RoundStats = rs[k]
			var them: Judges.RoundStats = rs[o]
			d.landed += me.landed
			d.thrown += me.thrown
			d.damage += me.damage
			d.kd += me.knockdowns_scored
			d.blocks += them.blocked
			d.parries += them.parried
			d.checks += me.checks
			d.sweeps += me.sweeps
			d.control += me.control_frames
		out[k] = d
	return out

func _stats_grid(rounds: Array) -> Control:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 36)
	g.add_theme_constant_override("v_separation", 3)
	var s := sum_stats(rounds)
	var rows := [
		["", flow.fighters[0].display_name.to_upper(), flow.fighters[1].display_name.to_upper()],
		["Strikes landed", "%d / %d" % [s[0].landed, s[0].thrown], "%d / %d" % [s[1].landed, s[1].thrown]],
		["Accuracy", _pct(s[0].landed, s[0].thrown), _pct(s[1].landed, s[1].thrown)],
		["Damage dealt", "%.0f" % s[0].damage, "%.0f" % s[1].damage],
		["Knockdowns", str(s[0].kd), str(s[1].kd)],
		["Blocks", str(s[0].blocks), str(s[1].blocks)],
		["Parries", str(s[0].parries), str(s[1].parries)],
		["Leg kicks checked", str(s[0].checks), str(s[1].checks)],
		["Sweeps", str(s[0].sweeps), str(s[1].sweeps)],
		["Clinch control", "%ds" % (s[0].control / 60), "%ds" % (s[1].control / 60)],
	]
	for i in rows.size():
		var r: Array = rows[i]
		var header := i == 0
		var cells := [r[1], r[0], r[2]]  # red value | stat name | blue value
		for c in 3:
			var color := Color.WHITE
			if c == 1:
				color = DIM
			elif header:
				color = flow.fighters[0 if c == 0 else 1].base_color().lightened(0.35)
			var l := _label(15 if header else 14, color, 0)
			l.text = cells[c]
			l.horizontal_alignment = [HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_LEFT][c]
			l.custom_minimum_size.x = 150 if c == 1 else 90
			g.add_child(l)
	return _center_wrap(g)

func _center_wrap(c: Control) -> CenterContainer:
	var w := CenterContainer.new()
	w.add_child(c)
	return w

func _scorecard_grid() -> Control:
	if flow.judges.cards[0].is_empty():
		return null
	var n: int = flow.judges.cards[0].size()
	var g := GridContainer.new()
	g.columns = n + 2
	g.add_theme_constant_override("h_separation", 22)
	g.add_theme_constant_override("v_separation", 3)
	var head := ["SCORECARDS"]
	for r in n:
		head.append("R%d" % (r + 1))
	head.append("TOTAL")
	for h in head:
		var l := _label(12, GOLD, 0)
		l.text = h
		g.add_child(l)
	var totals := flow.judges.totals()
	for j in flow.judges.cards.size():
		var jl := _label(13, DIM, 0)
		jl.text = "Judge %d" % (j + 1)
		g.add_child(jl)
		for r in flow.judges.cards[j]:
			var l := _label(13, Color.WHITE, 0)
			l.text = "%d-%d" % [r[0], r[1]]
			g.add_child(l)
		var tl := _label(13, Color.WHITE, 0)
		tl.text = "%d-%d" % [totals[j][0], totals[j][1]]
		g.add_child(tl)
	return _center_wrap(g)

func _pct(a: int, b: int) -> String:
	return "-" if b == 0 else "%d%%" % roundi(100.0 * a / b)

# --- per-frame update ---

func _process(delta: float) -> void:
	if flow == null:
		return
	for i in 2:
		var f: Fighter = flow.fighters[i]
		var side: Dictionary = _sides[i]
		for z in side.bars:
			var gb: Dictionary = side.bars[z]
			var hp: float = f.body.hp[z]
			gb.main.value = hp
			(gb.main.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = _hp_color(hp / 100.0)
			if gb.ghost.value <= hp:
				gb.ghost.value = hp
				gb.hold = GHOST_HOLD
			elif gb.hold > 0.0:
				gb.hold -= delta
			else:
				gb.ghost.value = maxf(hp, gb.ghost.value - GHOST_DRAIN * delta)
		side.stam.value = f.stam.value
		side.kd.visible = f.body.knockdowns_total > 0
		(side.kd.get_meta("label") as Label).text = "KD %d" % f.body.knockdowns_total
		side.cut.visible = f.body.cut > 0.0
	_update_clock()
	_update_banner()
	_update_clinch()
	_stats_panel.visible = flow.phase == FightFlow.Phase.ROUND_BREAK or flow.phase == FightFlow.Phase.OVER
	if flow.phase == FightFlow.Phase.ROUND_BREAK:
		var rest := ceili(float(flow.rest_frames - flow.phase_frame) / FightFlow.FPS)
		_stats_footer.text = "Round %d starts in %d:%02d   ·   [Enter] skip" % [flow.round + 1, rest / 60, rest % 60]
	elif flow.phase == FightFlow.Phase.OVER:
		_stats_footer.text = "[Enter] fight again"
	_help.visible = help_visible
	_help.text = help_text

func _hp_color(r: float) -> Color:
	return HP_MID.lerp(HP_FULL, clampf((r - 0.5) * 2.0, 0, 1)) if r >= 0.5 else HP_LOW.lerp(HP_MID, clampf(r * 2.0, 0, 1))

func _update_clock() -> void:
	var secs := ceili(float(flow.clock) / FightFlow.FPS)
	_round_label.text = "ROUND %d OF %d" % [flow.round, flow.rounds]
	if flow.phase == FightFlow.Phase.ROUND_BREAK:
		var rest := ceili(float(flow.rest_frames - flow.phase_frame) / FightFlow.FPS)
		_round_label.text = "BREAK"
		secs = rest
	_clock.text = "%d:%02d" % [secs / 60, secs % 60]
	_clock.modulate = Color(1, 0.4, 0.3) if flow.phase == FightFlow.Phase.FIGHTING and secs <= 10 else Color.WHITE
	for r in _dots.size():
		var done := r < flow.round - 1 or (r == flow.round - 1 and flow.phase in [FightFlow.Phase.ROUND_BREAK, FightFlow.Phase.OVER])
		var key := "done" if done else ("now" if r == flow.round - 1 else "todo")
		_dots[r].add_theme_stylebox_override("panel", _dot_styles[key])

func _update_banner() -> void:
	var big := ""
	var small := ""
	match flow.phase:
		FightFlow.Phase.INTRO:
			big = "ROUND %d" % flow.round if flow.phase_frame < 50 else "FIGHT!"
		FightFlow.Phase.KNOCKDOWN:
			big = "KNOCKDOWN!" if flow.count == 0 else str(flow.count)
			small = "%s is up" % flow.downed.display_name if flow.downed.state == Fighter.State.IDLE \
					else "%s is down" % flow.downed.display_name
		FightFlow.Phase.DOCTOR:
			big = "DOCTOR CHECK"
			small = "%s's cut is being examined" % flow.doctor_for.display_name
	_banner_big.text = big
	_banner_small.text = small
	_banner_small.visible = small != ""
	_banner.visible = big != ""
	_callout.text = flow.event_text if flow.phase == FightFlow.Phase.FIGHTING and flow.event_frames > 0 else ""

func _update_clinch() -> void:
	_clinch_box.visible = flow.in_clinch()
	if not flow.in_clinch():
		return
	# Fill = how far toward Red's side the position is (flow.fighters[0] is Red).
	var adv := flow.clinch.advantage if flow.clinch.fighters[0] == flow.fighters[0] else -flow.clinch.advantage
	_clinch_bar.value = adv
	var red_pos := flow.clinch.position_of(flow.clinch.index_of(flow.fighters[0]))
	_clinch_label.text = "CLINCH  ·  " + ["neutral", "%s dominant" % flow.fighters[0].display_name,
		"%s dominant" % flow.fighters[1].display_name][red_pos]
	# Controls for the player (Red): how to get out comes first.
	var out := "L: escape (easy)" if red_pos == Clinch.Pos.DOMINANT else "L or walk away: escape"
	var knee := "N knee (+W head)" if red_pos == Clinch.Pos.DOMINANT else ("N knee" if red_pos == Clinch.Pos.NEUTRAL else "")
	var hint := [out, "C pummel", "Space frame"]
	if knee != "":
		hint.insert(2, knee)
	if red_pos != Clinch.Pos.CONTROLLED:
		hint.insert(3, "H sweep")
	var left := ceili(float(Clinch.MAX_FRAMES - flow.clinch.frames) / FightFlow.FPS)
	_clinch_hint.text = "  ·  ".join(hint) + "     ref breaks in %ds" % left

func _method_name(m: String) -> String:
	match m:
		"UD": return "Unanimous Decision"
		"SD": return "Split Decision"
		"MD": return "Majority Decision"
		"DRAW": return "Draw"
		"TKO": return "TKO (3 knockdowns)"
		"TKO (doctor)": return "TKO (doctor stoppage)"
	return m
