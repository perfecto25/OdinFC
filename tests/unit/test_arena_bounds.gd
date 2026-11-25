extends GutTest
## Arena boundaries: ring (square ropes) and cage (circular fence) clamping and edge steering.

func test_ring_clamps_each_axis():
	var b := ArenaBounds.ring()
	var p := b.clamp_position(Vector3(5, 0.3, -9))
	assert_eq(p, Vector3(ArenaBounds.RING_HALF, 0.3, -ArenaBounds.RING_HALF))

func test_ring_corner_is_reachable():
	var b := ArenaBounds.ring()
	var c := Vector3(ArenaBounds.RING_HALF, 0, ArenaBounds.RING_HALF)
	assert_eq(b.clamp_position(c), c, "fighters can be pinned in a ring corner")

func test_cage_clamps_to_radius():
	var b := ArenaBounds.cage()
	var p := b.clamp_position(Vector3(10, 0, 10))
	assert_almost_eq(Vector2(p.x, p.z).length(), ArenaBounds.CAGE_RADIUS, 0.0001)
	assert_almost_eq(p.x, p.z, 0.0001, "pushed straight back toward the centre")

func test_cage_has_no_corners():
	var b := ArenaBounds.cage()
	var ring_corner := Vector3(ArenaBounds.RING_HALF, 0, ArenaBounds.RING_HALF)
	assert_ne(b.clamp_position(ring_corner), ring_corner, "the ring's corner is outside the cage")

func test_inside_points_unchanged():
	for b in [ArenaBounds.ring(), ArenaBounds.cage()]:
		var p := Vector3(1.0, 0, -2.0)
		assert_eq(b.clamp_position(p), p)

func test_inward_push_zero_away_from_edge():
	for b in [ArenaBounds.ring(), ArenaBounds.cage()]:
		assert_eq(b.inward_push(Vector2(0.5, 0.5), 1.0), Vector2.ZERO)

func test_inward_push_points_to_centre():
	var b := ArenaBounds.cage()
	var p := Vector2(0, ArenaBounds.CAGE_RADIUS - 0.25)
	var push := b.inward_push(p, 1.0)
	assert_almost_eq(push.length(), 0.75, 0.0001)
	assert_lt(push.y, 0.0)

func test_ring_push_matches_old_formula():
	var b := ArenaBounds.ring()
	var p := Vector2(3.0, -3.2)
	var lim := ArenaBounds.RING_HALF - 1.0
	var expected := Vector2(-(3.0 - lim), (3.2 - lim))
	assert_almost_eq(b.inward_push(p, 1.0).x, expected.x, 0.0001)
	assert_almost_eq(b.inward_push(p, 1.0).y, expected.y, 0.0001)

func test_distance_to_edge():
	assert_almost_eq(ArenaBounds.ring().distance_to_edge(Vector2(3.0, 1.0)), ArenaBounds.RING_HALF - 3.0, 0.0001)
	assert_almost_eq(ArenaBounds.cage().distance_to_edge(Vector2(3.0, 0.0)), ArenaBounds.CAGE_RADIUS - 3.0, 0.0001)

func test_fighter_stays_inside_cage():
	var f: Fighter = load("res://scenes/fighter.tscn").instantiate()
	add_child_autofree(f)
	f.set_physics_process(false)
	f.setup(Color.RED, Vector3.ZERO)
	f.bounds = ArenaBounds.cage()
	f.global_position = Vector3(3.0, 0, 3.0)  # inside the ring square, outside the cage circle
	f.tick()
	assert_lte(Vector2(f.global_position.x, f.global_position.z).length(), ArenaBounds.CAGE_RADIUS + 0.0001)
