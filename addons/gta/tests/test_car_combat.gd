extends GutTest

## Purpose: a car in the Twisted Metal demo takes its health from the roster,
## loses it to hits, carries and spends pickup weapons, and reports the health
## tier its AI driver reads to decide whether to press an attack.

const TM2_CAR: PackedScene = preload("res://addons/gta/scenes/tm2_car.tscn")

var car: Tm2Car
var combat: CarCombat


func before_each() -> void:
	car = TM2_CAR.instantiate()
	# set before the car enters the tree: CarCombat reads the roster in _ready
	car.car = &"sweet_tooth"
	(car.get_node(^"CarCombat") as CarCombat).car = &"sweet_tooth"
	(car.get_node(^"AiDriver") as AiDriver).enabled = false
	add_child_autofree(car)
	combat = car.get_node(^"CarCombat")
	await wait_physics_frames(2)


func test_a_twisted_metal_car_hides_its_driver() -> void:
	# the ripped PlayStation cars have no cabin to seat anyone in, so the
	# driver's model is hidden rather than left sitting on the roof
	assert_true(car.hides_driver_model, "tm2_car.tscn hides the driver")
	# and with nobody aboard it is simply a no-op rather than an error
	car._set_driver_model_visible(false)
	assert_null(car.player)


func test_health_comes_from_the_roster_not_the_scene_default() -> void:
	assert_eq(combat.max_health, 140.0, "Sweet Tooth has 140 health")
	assert_eq(combat.health, combat.max_health, "It starts undamaged")


func test_taking_a_hit_lowers_health_and_reports_it() -> void:
	watch_signals(combat)
	combat.take_hit(40.0)
	assert_eq(combat.health, 100.0)
	assert_signal_emitted(combat, "health_changed")
	assert_false(combat.is_dead)


func test_health_runs_out_once_and_names_the_killer() -> void:
	watch_signals(combat)
	var killer: Node3D = Node3D.new()
	add_child_autofree(killer)
	combat.take_hit(1000.0, killer)
	assert_true(combat.is_dead)
	assert_eq(combat.health, 0.0, "Health floors at zero rather than going negative")
	assert_signal_emitted_with_parameters(combat, "died", [killer])
	# a dead car cannot be killed twice
	combat.take_hit(10.0)
	assert_signal_emit_count(combat, "died", 1)


func test_the_health_tier_the_ai_reads_climbs_as_the_car_is_hurt() -> void:
	assert_eq(combat.health_tier(), 0, "A healthy car is tier zero")
	combat.take_hit(combat.max_health * 0.5)
	assert_eq(combat.health_tier(), 1)
	combat.take_hit(combat.max_health * 0.4)
	assert_eq(combat.health_tier(), CarCombat.HEALTH_TIERS - 1, "Nearly dead is the top tier")


func test_repair_stops_at_full_health() -> void:
	combat.take_hit(50.0)
	combat.repair(1000.0)
	assert_eq(combat.health, combat.max_health)


func test_picking_up_a_weapon_selects_it_and_counts_it() -> void:
	watch_signals(combat)
	combat.pick_up(&"homing_missile", 3)
	assert_eq(combat.selected, &"homing_missile")
	assert_eq(int(combat.inventory[&"homing_missile"]), 3)
	assert_signal_emitted(combat, "weapon_changed")


func test_an_unknown_weapon_is_refused() -> void:
	combat.pick_up(&"bfg", 5)
	assert_eq(combat.inventory.size(), 0)
	assert_eq(combat.selected, &"")


func test_firing_spends_a_round_and_drops_the_weapon_when_it_runs_out() -> void:
	combat.pick_up(&"fire_missile", 2)
	assert_true(combat.fire_forward())
	assert_eq(int(combat.inventory[&"fire_missile"]), 1)
	assert_true(combat.fire_forward())
	assert_false(combat.inventory.has(&"fire_missile"), "The empty weapon is gone")
	assert_eq(combat.selected, &"", "Nothing is selected once the last one is spent")


func test_the_machine_gun_fires_when_there_is_no_pickup_selected() -> void:
	watch_signals(combat)
	assert_true(combat.fire_forward(), "The gun always has something to give")
	assert_signal_emitted_with_parameters(combat, "fired", [&"machine_gun", true])
	assert_false(combat.fire_forward(), "It is on a cooldown between rounds")


func test_cycling_steps_to_a_weapon_that_still_has_ammunition() -> void:
	combat.pick_up(&"fire_missile", 1)
	combat.pick_up(&"napalm", 1)
	combat.selected = &"fire_missile"
	combat.cycle_weapon()
	assert_eq(combat.selected, &"napalm")


func test_a_special_only_fires_once_it_has_charged() -> void:
	assert_false(combat.fire_special(), "There is no special at the start of a round")
	combat.specials = 1
	assert_true(combat.fire_special())
	assert_eq(combat.specials, 0)


func test_a_dead_car_stops_shooting() -> void:
	combat.pick_up(&"power_missile", 5)
	combat.take_hit(1000.0)
	assert_false(combat.fire_forward())
	assert_false(combat.fire_rear())
	assert_false(combat.fire_special())


## Each muzzle is turned the way its own shot should travel, so a shot simply takes the muzzle's
## transform. Getting this wrong fires the forward weapon out of the back of the car, which is what
## the scene did before the car was its own: the markers sat on the wrong ends.
func test_a_shot_leaves_the_car_the_way_it_was_aimed() -> void:
	var muzzle_forward: Node3D = car.get_node(^"MuzzleForward")
	var muzzle_rear: Node3D = car.get_node(^"MuzzleRear")
	var nose: Vector3 = car.forward()
	assert_gt((-muzzle_forward.global_basis.z).dot(nose), 0.9,
		"The forward muzzle fires along the nose")
	assert_lt((-muzzle_rear.global_basis.z).dot(nose), -0.9,
		"and the rear one fires out of the back")
	assert_gt(muzzle_forward.position.z, 0.0, "The forward muzzle sits on the nose end")
	assert_lt(muzzle_rear.position.z, 0.0, "and the rear one on the tail end")


func test_a_fired_shot_flies_away_from_the_nose() -> void:
	# earlier tests in this file fire too, and a shot is parented to the car's own parent,
	# so the new one is found by difference rather than by counting
	var before: Array = []
	for child: Node in car.get_parent().get_children():
		if child is Tm2Projectile:
			before.append(child)
	combat.pick_up(&"fire_missile", 1)
	combat.fire_forward()
	await wait_physics_frames(1)
	var shot: Tm2Projectile = null
	for child: Node in car.get_parent().get_children():
		if child is Tm2Projectile and not before.has(child):
			shot = child as Tm2Projectile
			break
	assert_not_null(shot, "One shot left the car")
	if shot == null:
		return
	var start: Vector3 = shot.global_position
	await wait_physics_frames(4)
	if not is_instance_valid(shot):
		pass_test("The shot hit something straight away, which is still away from the car")
		return
	var travelled: Vector3 = shot.global_position - start
	assert_gt(travelled.normalized().dot(car.forward()), 0.9,
		"A forward shot travels along the nose, not out of the back")
	shot.queue_free()
