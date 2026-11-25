class_name MoveLibrary
## Loads every MoveData .tres in res://data/moves once.

static var _cache: Dictionary = {}

static func all() -> Dictionary:
	if _cache.is_empty():
		var dir := DirAccess.open("res://data/moves")
		if dir:
			for f in dir.get_files():
				var name := f.trim_suffix(".remap")
				if name.ends_with(".tres"):
					var m := load("res://data/moves/" + name) as MoveData
					if m:
						_cache[m.id] = m
	return _cache
