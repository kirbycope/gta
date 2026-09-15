extends GutTest

## Purpose: the item set lines up with Mario Kart 64's own sixteen slots, the
## roulette behaves the way gen_random_item behaves, and the stand in odds are
## honest about being stand in odds.


func test_the_slots_match_the_games_item_enum() -> void:
	# the ids are the game's, so a course converted out of a ROM can hand its
	# item numbers straight over without translation
	assert_eq(MkItems.Item.NONE, 0, "ITEM_NONE")
	assert_eq(MkItems.Item.HAZARD, 1, "ITEM_BANANA")
	assert_eq(MkItems.Item.SHOT, 3, "ITEM_GREEN_SHELL")
	assert_eq(MkItems.Item.HOMING_SHOT, 5, "ITEM_RED_SHELL")
	assert_eq(MkItems.Item.LEADER_SHOT, 7, "ITEM_BLUE_SPINY_SHELL")
	assert_eq(MkItems.Item.JOLT, 8, "ITEM_THUNDERBOLT")
	assert_eq(MkItems.Item.INVINCIBILITY, 10, "ITEM_STAR")
	assert_eq(MkItems.Item.BOOST, 12, "ITEM_MUSHROOM")
	assert_eq(MkItems.Item.SUPER_BOOST, 15, "ITEM_SUPER_MUSHROOM")
	assert_eq(MkItems.Item.size(), 16, "sixteen slots, as the enum has")


func test_the_triples_hand_over_three_and_the_singles_one() -> void:
	assert_eq(MkItems.uses(MkItems.Item.TRIPLE_SHOT), 3, "a triple is three")
	assert_eq(MkItems.uses(MkItems.Item.TRIPLE_HOMING_SHOT), 3, "and so is the homing one")
	assert_eq(MkItems.uses(MkItems.Item.TRIPLE_BOOST), 3, "three boosts")
	assert_eq(MkItems.uses(MkItems.Item.DOUBLE_BOOST), 2, "two of the double")
	assert_eq(MkItems.uses(MkItems.Item.HAZARD_BUNCH), 5, "a bunch is five")
	assert_eq(MkItems.uses(MkItems.Item.SHOT), 1, "a single shot is one")


func test_dropped_and_fired_items_are_told_apart() -> void:
	assert_true(MkItems.is_dropped(MkItems.Item.HAZARD), "a hazard goes out behind")
	assert_true(MkItems.is_dropped(MkItems.Item.DECOY), "and so does a decoy")
	assert_false(MkItems.is_dropped(MkItems.Item.SHOT), "a shot goes out in front")
	assert_true(MkItems.is_boost(MkItems.Item.BOOST), "a boost acts on the kart itself")
	assert_true(MkItems.is_boost(MkItems.Item.SUPER_BOOST), "so does the super boost")
	assert_false(MkItems.is_boost(MkItems.Item.HOMING_SHOT), "a shot does not")


func test_every_slot_has_a_name_for_the_hud_except_the_empty_one() -> void:
	for item: int in MkItems.Item.values():
		if item == MkItems.Item.NONE:
			assert_eq(MkItems.display_name(item), "", "an empty slot shows nothing")
			continue
		assert_ne(MkItems.display_name(item), "", "slot %d has a name" % item)


func test_the_draw_always_produces_a_real_item() -> void:
	var rolling: int = 0
	for i in range(200):
		var drawn: Dictionary = MkItems.draw(i % MkConst.RACERS, rolling, i)
		var item: int = int(drawn["item"])
		assert_between(item, 0, 15, "whatever comes out is a valid slot")
		rolling = int(drawn["rolling_index"])
		assert_between(rolling, 0, MkItems.CURVE_LENGTH - 1,
			"the rolling index stays inside the hundred, as sRandomItemIndex does")


func test_the_rolling_index_is_carried_rather_than_reset() -> void:
	# gen_random_item folds the previous index, the frame counter and a fresh
	# random into the next one, so successive draws are not independent
	var seen: Dictionary = {}
	var rolling: int = 0
	for frame in range(60):
		var drawn: Dictionary = MkItems.draw(0, rolling, frame)
		rolling = int(drawn["rolling_index"])
		seen[rolling] = true
	assert_gt(seen.size(), 1, "the index actually moves between draws")


func test_the_placeholder_odds_say_they_are_placeholder_odds() -> void:
	# without a ROM extraction there is no real table, and the demo must not
	# pretend otherwise
	if MkItems.has_real_odds():
		var curve: PackedInt32Array = MkItems.curve_for_rank(0)
		assert_eq(curve.size(), MkItems.CURVE_LENGTH,
			"a real table is a hundred entries for the leader")
		return
	assert_eq(MkItems.curve_for_rank(0).size(), 0,
		"with no extracted table there is no curve to hand out")
	assert_gt(MkItems.FALLBACK_CURVE.size(), 0, "but a draw still produces something")


func test_the_super_boost_runs_for_the_games_own_twenty_seconds() -> void:
	assert_eq(MkItems.SUPER_BOOST_FRAMES, 600, "consume_item sets the timer to 0x258")
	assert_almost_eq(MkConst.frames(MkItems.SUPER_BOOST_FRAMES), 20.0, 0.001,
		"600 frames at 30 fps is 20 seconds")
