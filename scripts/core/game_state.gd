extends Node
## Autoload "GameState": fight settings. Override from the command line, e.g.
##   godot --path . -- --round-seconds=30 --rest-seconds=5 --rounds=3 --seed=42 --cpu=hard --arena=cage
## --cpu: rating (the CPU fighter's own difficulty) | easy | medium | hard | dummy. --arena: ring | cage.
## --p1 / --p2: roster ids (data/fighters/<id>.tres) for the player and the CPU, e.g. --p1=haggerty --p2=superbon.

var rounds := 3
var round_seconds := 180.0
var rest_seconds := 60.0
var seed := -1  ## -1 = random each fight
var cpu := "rating"
var arena := "ring"  ## ring | cage
var opponent_index := -1  ## the F1 opponent choice, kept across scene reloads (-1 = from --cpu)

## Corner colours the player (and, for the leftovers, the CPU) can pick.
const CORNERS := [
	{"name": "Red", "color": Color(0.8, 0.15, 0.15)},
	{"name": "Blue", "color": Color(0.15, 0.3, 0.85)},
	{"name": "Green", "color": Color(0.1, 0.6, 0.25)},
	{"name": "Gold", "color": Color(0.85, 0.65, 0.1)},
	{"name": "Black", "color": Color(0.12, 0.12, 0.14)},
]
var player_corner := 0
var player_fighter: StringName = &"superbon"  ## roster id
var opponent_fighter: StringName = &""        ## roster id ("" = the first fighter the player isn't using)
var direct_launch := false  ## a --cpu/--arena/... flag was given: skip the main menu

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=")
		if kv.size() != 2:
			continue
		direct_launch = true
		match kv[0]:
			"rounds": rounds = kv[1].to_int()
			"round-seconds": round_seconds = kv[1].to_float()
			"rest-seconds": rest_seconds = kv[1].to_float()
			"seed": seed = kv[1].to_int()
			"cpu": cpu = kv[1]
			"arena": arena = kv[1]
			"p1": player_fighter = StringName(kv[1])
			"p2": opponent_fighter = StringName(kv[1])

func opponent_corner() -> int:
	return 1 if player_corner == 0 else 0

## Roster entries for the two sides (null when the roster is empty: generic fighters).
func player_data() -> FighterData:
	var d := Roster.get_fighter(player_fighter)
	if d == null and not Roster.all().is_empty():
		d = Roster.all()[0]
	return d

func opponent_data() -> FighterData:
	var d := Roster.get_fighter(opponent_fighter)
	if d:
		return d
	var you := player_data()
	for other in Roster.all():
		if other != you:
			return other
	return you

func fight_config() -> Dictionary:
	return {
		"rounds": rounds,
		"round_seconds": round_seconds,
		"rest_seconds": rest_seconds,
		"seed": seed if seed >= 0 else randi(),
	}
