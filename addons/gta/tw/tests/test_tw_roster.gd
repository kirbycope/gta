extends GutTest

## Purpose: the Twisted Metal 2 stat table is data taken from the published
## community figures, so these lock the values in and make sure the gaps that
## could not be sourced stay declared rather than quietly invented.


func test_every_car_has_a_complete_stat_block() -> void:
	assert_eq(TwRoster.CARS.size(), 14, "The Twisted Metal 2 roster is fourteen cars")
	for car: StringName in TwRoster.CARS:
		var stats: Dictionary = TwRoster.stats(car)
		for key: String in ["health", "top_mph", "turbo_mph", "special_s", "specials"]:
			assert_true(stats.has(key), "%s has %s" % [car, key])
		assert_gt(float(stats["health"]), 0.0, "%s has health" % car)
		assert_gt(float(stats["turbo_mph"]), float(stats["top_mph"]),
			"%s turbos faster than it drives" % car)


func test_the_published_outliers_are_what_the_tables_say() -> void:
	# these are the numbers the roster is worth checking against: Minion is the
	# armoured boss, Mr. Grimm the glass cannon, Twister the fastest
	assert_eq(float(TwRoster.stats(&"minion")["health"]), 230.0)
	assert_eq(float(TwRoster.stats(&"mr_grimm")["health"]), 85.0)
	assert_eq(float(TwRoster.stats(&"twister")["top_mph"]), 140.0)
	assert_eq(float(TwRoster.stats(&"roadkill")["health"]), 120.0)


func test_top_speed_converts_the_published_mph_to_metres_per_second() -> void:
	assert_almost_eq(TwRoster.top_speed(&"roadkill"), 117.0 * 0.44704, 0.001)
	assert_almost_eq(TwRoster.top_speed(&"roadkill", true), 156.0 * 0.44704, 0.001)
	assert_gt(TwRoster.top_speed(&"twister"), TwRoster.top_speed(&"sweet_tooth"),
		"Twister is the quicker car")


func test_an_unknown_car_reports_nothing_rather_than_a_made_up_number() -> void:
	assert_eq(TwRoster.stats(&"not_a_car"), {})
	assert_eq(TwRoster.top_speed(&"not_a_car"), 0.0)


func test_weapon_damage_matches_the_published_figures() -> void:
	assert_eq(float(TwRoster.WEAPONS[&"fire_missile"]["damage"]), 7.0)
	assert_eq(float(TwRoster.WEAPONS[&"homing_missile"]["damage"]), 10.0)
	assert_eq(float(TwRoster.WEAPONS[&"power_missile"]["damage"]), 15.0)
	assert_eq(float(TwRoster.WEAPONS[&"remote_bomb"]["damage"]), 25.0)
	# the ricochet is the one weapon that grows as it bounces
	assert_gt(float(TwRoster.WEAPONS[&"ricochet"]["max_damage"]),
		float(TwRoster.WEAPONS[&"ricochet"]["damage"]))


func test_the_numbers_that_could_not_be_sourced_are_listed() -> void:
	assert_gt(TwRoster.UNSOURCED.size(), 0,
		"Anything that could not be sourced is declared, not invented")
