class_name FighterData
extends Resource
## One roster fighter: bio, body measurements, attributes, signature moves, AI style and CPU rating.
## Lives in res://data/fighters/<id>.tres (loaded by Roster). A fighter without data (tests, sims) is
## neutral: every attribute at 50 and 178 cm / 178 cm reach / 68 kg gives exactly the base game numbers.
##
## Attributes are 1..100 with 50 = average. Each one moves gameplay a bounded amount (see the *_SWING
## constants), so a 90-rated stat is an edge, not a different game.

enum Stance { ORTHODOX, SOUTHPAW }

const BASE_HEIGHT_CM := 178.0  ## height at which the character model is drawn at scale 1
const BASE_REACH_CM := 178.0   ## reach at which move reaches are as authored in data/moves
const BASE_WEIGHT_KG := 68.0
const REACH_SWING := 0.6       ## fraction of the relative reach difference applied to move reach
const POWER_SWING := 0.15      ## power 100 -> +15% impact, 1 -> about -15%
const SPEED_SWING := 0.12      ## speed 100 -> startup/recovery x0.88
const FOOT_SWING := 0.08       ## speed 100 -> footwork +8%
const CHIN_SWING := 0.35       ## chin 100 -> knockdown chance x0.65
const CARDIO_REGEN_SWING := 0.2
const CARDIO_COST_SWING := 0.1
const CLINCH_SWING := 0.25

# --- bio (display only) ---
@export var id: StringName
@export var display_name := ""       ## shown on the HUD / name plates
@export var full_name := ""
@export var nickname := ""
@export var country := ""
@export var gym := ""
@export var fighting_out_of := ""   ## e.g. "Surin, Thailand"
@export var record := ""             ## e.g. "240-24-14"
@export var ranking := 0             ## roster ranking (1 = top); 0 = unranked
@export var age := 0                 ## years; 0 = unknown
@export var weight_class := ""       ## e.g. "Lightweight"; setting it gives the fighter a pre-fight page
@export_multiline var bio := ""

# --- model ---
## Own character scene made by tools/import_fighter.gd; empty = the tinted stock mannequin.
@export_file("*.scn") var model_path := ""
## Stance and technique clips in assets/anim/generated/<anim_set>/ replacing the shared ones, e.g. "muay_thai".
@export var anim_set := ""

# --- body ---
@export var height_cm := BASE_HEIGHT_CM
@export var reach_cm := 0.0          ## 0 = same as height
@export var weight_kg := BASE_WEIGHT_KG
@export var stance: Stance = Stance.ORTHODOX  ## not mirrored yet (the rig is orthodox); kept for later

# --- attributes (1..100, 50 = average) ---
@export_range(1, 100) var power := 50
@export_range(1, 100) var speed := 50
@export_range(1, 100) var chin := 50
@export_range(1, 100) var cardio := 50
@export_range(1, 100) var clinch := 50

## Signature techniques: move id -> {"damage": mult, "speed": mult on startup/recovery, "ai": mult on how
## often the CPU picks it}. Missing keys default to 1. Real specials (input sequence + meter) come later.
@export var signatures: Dictionary = {}

# --- CPU ---
@export_range(1, 5) var difficulty := 3   ## 1 = Easy .. 3 = Medium .. 5 = Hard (AI skill when the CPU plays them)
@export var punch_bias := 1.0
@export var kick_bias := 1.0
@export var knee_bias := 1.0
@export var clinch_bias := 1.0
@export var preferred_range := 1.45       ## metres, centre to centre

# --- look (from reference photos in assets/reference/fighters/<id>/; the art pass reads these) ---
@export var skin_tone := Color(0.85, 0.85, 0.85)  ## tints the body (applied now)
@export var hair_color := Color(0.05, 0.04, 0.04)
@export var hair_style := ""                      ## free text for the art pass
@export var shorts_color := Color(0.1, 0.1, 0.1)
@export var shorts_trim := Color(0.85, 0.65, 0.1)
@export var ankle_color := Color(0.1, 0.1, 0.1)   ## ankle supports
@export var armbands := false                     ## prajioud on the upper arms
@export var headband := false                     ## mongkol for the walk-out
@export_multiline var look_notes := ""

static func _d(attr: int) -> float:
	return (clampf(attr, 1, 100) - 50.0) / 50.0

func reach_factor() -> float:
	var r := reach_cm if reach_cm > 0.0 else height_cm
	return 1.0 + REACH_SWING * (r - BASE_REACH_CM) / BASE_REACH_CM

func power_factor() -> float:
	return 1.0 + POWER_SWING * _d(power)

func frame_factor() -> float:
	return 1.0 - SPEED_SWING * _d(speed)

func foot_factor() -> float:
	return 1.0 + FOOT_SWING * _d(speed)

func chin_factor() -> float:
	return 1.0 - CHIN_SWING * _d(chin)

func regen_factor() -> float:
	return 1.0 + CARDIO_REGEN_SWING * _d(cardio)

func cost_factor() -> float:
	return 1.0 - CARDIO_COST_SWING * _d(cardio)

## Clinch strength: technique x a mild weight term (sqrt, so 5 kg is a few percent, not a rout).
func clinch_strength() -> float:
	return (1.0 + CLINCH_SWING * _d(clinch)) * sqrt(weight_kg / BASE_WEIGHT_KG)

func model_scale() -> float:
	return height_cm / BASE_HEIGHT_CM

func signature(move_id: StringName, key: String) -> float:
	return float(signatures.get(move_id, {}).get(key, 1.0))

## This fighter's own copy of the move set: reach, impact, frame data and stamina cost scaled.
## The shared MoveLibrary resources are never modified.
func build_moves(base: Dictionary) -> Dictionary:
	var out := {}
	for mid in base:
		var m: MoveData = (base[mid] as MoveData).duplicate()
		var frames := frame_factor() * signature(mid, "speed")
		m.startup = maxi(1, roundi(m.startup * frames))
		m.recovery = maxi(1, roundi(m.recovery * frames))
		m.damage *= power_factor() * signature(mid, "damage")
		m.stamina_cost *= cost_factor()
		m.reach *= reach_factor()
		out[mid] = m
	return out

func has_profile() -> bool:
	return weight_class != ""

func weight_lbs() -> float:
	return weight_kg / 0.45359237

## e.g. 5'10"
func height_ft_in() -> String:
	var inches := roundi(height_cm / 2.54)
	return "%d'%d\"" % [floori(inches / 12.0), inches % 12]

## e.g. "175 cm · 72 kg · Orthodox"
func tale_of_the_tape() -> String:
	return "%d cm · %d kg · %s" % [roundi(height_cm), roundi(weight_kg), ["Orthodox", "Southpaw"][stance]]
