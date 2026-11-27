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
	assert_eq(PadLayout.slot_for("N", true, true), "LR:N")

func test_labels_use_the_printed_button_names():
	var snes := PadLayout.button_names("SNES Controller")
	assert_eq(PadLayout.slot_label("-:S", snes), "B")
	assert_eq(PadLayout.slot_label("-:W", snes), "Y")
	assert_eq(PadLayout.slot_label("L:E", snes), "L + A")
	assert_eq(PadLayout.slot_label("LR:N", snes), "L + R + X")
	assert_eq(PadLayout.slot_label("-:S", PadLayout.button_names("Xbox Series Controller")), "A")
	assert_eq(PadLayout.slot_label("-:W", PadLayout.button_names("PS5 Controller")), "Square")

func test_default_puts_high_kick_on_y_and_uppercut_on_x():
	var snes := PadLayout.button_names("SNES Controller")
	var m := PadLayout.default_map()
	assert_eq(PadLayout.slot_label(PadLayout.slot_of(m, &"round_kick_high"), snes), "Y")
	assert_eq(PadLayout.slot_label(PadLayout.slot_of(m, &"uppercut"), snes), "X")

func test_old_layout_is_upgraded_keeping_custom_binds():
	var old := {"-:S": &"jab", "-:E": &"cross", "-:W": &"lead_hook", "-:N": &"rear_hook",
		"L:S": &"round_kick", "L:E": &"knee", "L:W": &"teep", "L:N": &"side_kick",
		"R:S": &"uppercut", "R:E": &"check", "R:W": &"slip", "R:N": &"clinch"}
	var m := PadLayout.upgrade(old)
	assert_true(PadLayout.is_valid(m))
	assert_eq(m["-:W"], &"round_kick_high")
	assert_eq(m["LR:W"], &"lead_hook")
	assert_eq(m["-:N"], &"uppercut")
	assert_eq(m["R:S"], &"rear_hook")
	assert_eq(m["L:S"], &"round_kick", "custom binds stay")
	assert_eq(PadLayout.upgrade(m), m, "upgrading twice changes nothing")

func test_invalid_maps_rejected():
	var m := PadLayout.default_map()
	m.erase("-:S")
	assert_false(PadLayout.is_valid(m))
	m = PadLayout.default_map()
	m["X:S"] = m["-:S"]
	m.erase("-:S")
	assert_false(PadLayout.is_valid(m))
