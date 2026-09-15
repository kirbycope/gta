extends GutTest

## Purpose: the roster's three classes carry Mario Kart 64's three acceleration
## curves intact, and the addon's own drivers are spread across all three.
##
## The drivers here are this addon's, but the curves are not, so what these
## tests check is that the port of the curves is faithful and that the cast
## actually exercises them.


func test_there_are_exactly_three_curves_because_the_game_has_three() -> void:
	# gKartAccelerationTables holds eight rows that resolve to three distinct
	# ones, which is the whole handling difference between the characters
	assert_eq(MkRoster.CURVES.size(), 3, "light, standard and heavy")
	var rows: Array = []
	for key: StringName in MkRoster.CURVES:
		rows.append(str(MkRoster.CURVES[key]))
	assert_eq(rows.size(), rows.duplicate().size(), "and no two of them are the same")
	for key: StringName in MkRoster.CURVES:
		assert_eq((MkRoster.CURVES[key] as Array).size(), MkRoster.CURVE_BANDS,
			"every curve is ten bands across the kart's top speed")


func test_the_curves_are_the_decomps_own_numbers() -> void:
	assert_eq(str(MkRoster.CURVES[&"standard"]), str([2.0, 2.0, 2.0, 1.6, 1.4, 1.2, 1.0, 0.8, 0.6, 0.4]),
		"the standard row, from gKartAccelerationTables")
	assert_eq(str(MkRoster.CURVES[&"light"]), str([2.0, 2.0, 2.5, 2.6, 2.6, 2.0, 1.5, 0.8, 0.8, 0.8]),
		"the light row, which pulls hardest through the midrange")
	assert_eq(str(MkRoster.CURVES[&"heavy"]), str([2.0, 2.0, 2.0, 1.6, 1.0, 1.0, 1.0, 1.8, 1.8, 1.2]),
		"the heavy row, dead in the middle and strong at the top")


func test_the_bands_are_scaled_the_way_player_accelerate_scales_them() -> void:
	# player_accelerate multiplies the first seven bands by 3.2 and the last
	# three by 2.8
	assert_almost_eq(MkRoster.acceleration_fraction(&"rook", 0.0), 2.0 * 3.2, 0.0001,
		"band 0 of the standard curve, scaled by 3.2")
	assert_almost_eq(MkRoster.acceleration_fraction(&"rook", 0.65), 1.0 * 3.2, 0.0001,
		"band 6 is the last one on the high scale")
	assert_almost_eq(MkRoster.acceleration_fraction(&"rook", 0.75), 0.8 * 2.8, 0.0001,
		"band 7 drops to 2.8")
	assert_almost_eq(MkRoster.acceleration_fraction(&"rook", 0.95), 0.4 * 2.8, 0.0001,
		"band 9, the last one before top speed")


func test_the_speed_fraction_is_clamped_at_both_ends() -> void:
	assert_almost_eq(MkRoster.acceleration_fraction(&"rook", -1.0),
		MkRoster.acceleration_fraction(&"rook", 0.0), 0.0001, "under nought reads as band 0")
	assert_almost_eq(MkRoster.acceleration_fraction(&"rook", 2.0),
		MkRoster.acceleration_fraction(&"rook", 0.95), 0.0001, "over one reads as band 9")


func test_a_heavy_kart_is_slower_through_the_midrange_and_stronger_at_the_top() -> void:
	var mid_standard: float = MkRoster.acceleration_fraction(&"rook", 0.45)
	var mid_heavy: float = MkRoster.acceleration_fraction(&"dozer", 0.45)
	assert_lt(mid_heavy, mid_standard, "a heavy kart is dead through the middle")
	var top_standard: float = MkRoster.acceleration_fraction(&"rook", 0.85)
	var top_heavy: float = MkRoster.acceleration_fraction(&"dozer", 0.85)
	assert_gt(top_heavy, top_standard, "and comes back strong near the top")


func test_a_light_kart_gets_the_higher_ceiling() -> void:
	assert_true(MkRoster.is_light(&"pip"), "Pip is a light kart")
	assert_false(MkRoster.is_light(&"rook"), "Rook is a standard one")
	assert_gt(MkRoster.top_speed(&"pip"), MkRoster.top_speed(&"rook"),
		"gTopSpeedTable gives the light karts 324 against 320 at 150cc")


func test_every_driver_is_in_one_of_the_three_classes() -> void:
	assert_eq(MkRoster.DRIVERS.size(), MkConst.RACERS,
		"a full grid of eight, the way the game fields eight")
	var seen: Dictionary = {}
	for driver: StringName in MkRoster.drivers():
		var kart_class: StringName = MkRoster.kart_class(driver)
		assert_true(MkRoster.CURVES.has(kart_class),
			"%s drives one of the three classes" % driver)
		seen[kart_class] = true
		assert_ne(MkRoster.display_name(driver), "", "%s has a name for the HUD" % driver)
		assert_gt(MkRoster.kart_width(driver), 0.0, "%s has a collision size" % driver)
	assert_eq(seen.size(), 3, "and all three classes are actually on the grid")


func test_an_unknown_driver_gives_nothing_rather_than_a_default_kart() -> void:
	assert_true(MkRoster.stats(&"nobody").is_empty(), "no stat block")
	assert_almost_eq(MkRoster.top_speed(&"nobody"), 0.0, 0.0001, "no top speed")
	assert_almost_eq(MkRoster.acceleration_fraction(&"nobody", 0.5), 0.0, 0.0001,
		"and no acceleration, rather than quietly driving like a standard kart")
