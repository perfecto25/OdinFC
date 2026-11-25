extends Node
## Autoload "GameState": fight settings. Override from the command line, e.g.
##   godot --path . -- --round-seconds=30 --rest-seconds=5 --rounds=3 --seed=42 --cpu=hard --arena=cage
## --cpu: easy | medium | hard (AI difficulty) or dummy (training dummy). --arena: ring | cage.

var rounds := 3
var round_seconds := 180.0
var rest_seconds := 60.0
var seed := -1  ## -1 = random each fight
var cpu := "medium"
var arena := "ring"  ## ring | cage
var opponent_index := -1  ## the F1 opponent choice, kept across scene reloads (-1 = from --cpu)

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"rounds": rounds = kv[1].to_int()
			"round-seconds": round_seconds = kv[1].to_float()
			"rest-seconds": rest_seconds = kv[1].to_float()
			"seed": seed = kv[1].to_int()
			"cpu": cpu = kv[1]
			"arena": arena = kv[1]

func fight_config() -> Dictionary:
	return {
		"rounds": rounds,
		"round_seconds": round_seconds,
		"rest_seconds": rest_seconds,
		"seed": seed if seed >= 0 else randi(),
	}
