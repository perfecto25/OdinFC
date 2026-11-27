class_name Roster
## Loads every FighterData .tres in res://data/fighters once, ordered by ranking (unranked last), then name.

const DIR := "res://data/fighters"

static var _list: Array[FighterData] = []

static func all() -> Array[FighterData]:
	if _list.is_empty():
		var dir := DirAccess.open(DIR)
		if dir:
			for f in dir.get_files():
				var fname := f.trim_suffix(".remap")
				if fname.ends_with(".tres"):
					var d := load(DIR + "/" + fname) as FighterData
					if d:
						_list.append(d)
		_list.sort_custom(func(a: FighterData, b: FighterData):
			var ra := a.ranking if a.ranking > 0 else 9999
			var rb := b.ranking if b.ranking > 0 else 9999
			return ra < rb if ra != rb else a.display_name < b.display_name)
	return _list

static func get_fighter(id: StringName) -> FighterData:
	for d in all():
		if d.id == id:
			return d
	return null

static func index_of(id: StringName) -> int:
	var l := all()
	for i in l.size():
		if l[i].id == id:
			return i
	return -1
