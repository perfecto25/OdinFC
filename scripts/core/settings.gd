extends Node
## Autoload "Settings": player preferences, persisted to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

var master_volume := 0.8   ## 0..1
var crowd_volume := 0.6    ## 0..1, the ambience bed
var camera_shake := true
var hit_stop := true
var fullscreen := false
var pad_layout: Dictionary = PadLayout.default_map()  ## gamepad face-button slots -> actions

func _ready() -> void:
	load_settings()
	apply()

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	master_volume = clampf(cf.get_value("audio", "master", master_volume), 0.0, 1.0)
	crowd_volume = clampf(cf.get_value("audio", "crowd", crowd_volume), 0.0, 1.0)
	camera_shake = cf.get_value("feel", "camera_shake", camera_shake)
	hit_stop = cf.get_value("feel", "hit_stop", hit_stop)
	fullscreen = cf.get_value("video", "fullscreen", fullscreen)
	var m = cf.get_value("controls", "pad_layout", null)
	if m is Dictionary:
		m = PadLayout.upgrade(m)
		if PadLayout.is_valid(m):
			pad_layout = m

func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", master_volume)
	cf.set_value("audio", "crowd", crowd_volume)
	cf.set_value("feel", "camera_shake", camera_shake)
	cf.set_value("feel", "hit_stop", hit_stop)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("controls", "pad_layout", pad_layout)
	cf.save(PATH)

## Push the current values to the engine and notify listeners (Sfx, menus).
func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
				else DisplayServer.WINDOW_MODE_WINDOWED)
	changed.emit()
