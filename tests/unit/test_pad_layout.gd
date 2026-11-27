extends GutTest

func test_default_is_valid():
	assert_true(PadLayout.is_valid(PadLayout.default_map()))

func test_every_action_has_one_slot():
	var m := PadLayout.default_map()
	for a in PadLayout.ACTIONS:
		assert_ne(PadLayout.slot_of(m, a), "", str(a))

func test_assign_swaps_with_displaced_action():
	var m := PadLayout.assign(PadLayout.default_map(), &"cross", "-:S")  # jab's slot
	assert_eq(m["-:S"], &"cross")
	assert_eq(m["-:E"], &"jab")
	assert_true(PadLayout.is_valid(m))

func test_assign_same_slot_is_noop():
	var m := PadLayout.default_map()
	assert_eq(PadLayout.assign(m, &"jab", "-:S"), m)

func test_slot_for_layers():
	assert_eq(PadLayout.slot_for("S", false, false), "-:S")
	assert_eq(PadLayout.slot_for("E", true, false), "L:E")
	assert_eq(PadLayout.slot_for("W", false, true), "R:W")
	assert_eq(PadLayout.slot_for("N", true, true), "")

func test_invalid_maps_rejected():
	var m := PadLayout.default_map()
	m.erase("-:S")
	assert_false(PadLayout.is_valid(m))
	m = PadLayout.default_map()
	m["X:S"] = m["-:S"]
	m.erase("-:S")
	assert_false(PadLayout.is_valid(m))
