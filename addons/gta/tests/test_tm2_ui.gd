extends GutTest

## Purpose: the Twisted Metal HUD reads nothing. Every number on it arrives through a signal, so
## these tests fire the signals and look at the labels, and never let the HUD poll a car.

const TM2_UI: PackedScene = preload("res://addons/gta/scenes/tm2_ui.tscn")
const TM2_CAR: PackedScene = preload("res://addons/gta/scenes/tm2_car.tscn")

var ui: Tm2Ui
var car: Tm2Car


func before_each() -> void:
	ui = TM2_UI.instantiate() as Tm2Ui
	add_child_autofree(ui)
	car = TM2_CAR.instantiate() as Tm2Car
	car.car = &"sweet_tooth"
	(car.get_node(^"CarCombat") as CarCombat).car = &"sweet_tooth"
	(car.get_node(^"AiDriver") as AiDriver).enabled = false
	add_child_autofree(car)
	await wait_physics_frames(2)
	ui.watch(car)


func test_watching_a_car_shows_what_it_already_has() -> void:
	assert_eq(ui.health_label.text, "140", "Sweet Tooth's published armour")
	assert_almost_eq(ui.health_bar.max_value, 140.0, 0.01)
	assert_almost_eq(ui.turbo_bar.value, 1.0, 0.01, "A fresh car has a full meter")
	assert_eq(ui.weapon_label.text, "Machine Gun", "Nothing picked up yet")


func test_taking_a_hit_moves_the_armour_bar() -> void:
	(car.get_node(^"CarCombat") as CarCombat).take_hit(40.0)
	assert_eq(ui.health_label.text, "100")
	assert_almost_eq(ui.health_bar.value, 100.0, 0.01)


func test_picking_up_a_weapon_names_it_and_counts_it() -> void:
	(car.get_node(^"CarCombat") as CarCombat).pick_up(&"homing_missile", 3)
	assert_eq(ui.weapon_label.text, "Homing Missile  x3")


func test_spending_turbo_moves_the_meter() -> void:
	car.turbo = 0.4
	assert_almost_eq(ui.turbo_bar.value, 0.4, 0.01)


func test_it_connects_rather_than_polling() -> void:
	# the HUD must have no _process of its own: a bar that moves when the car is hit
	# has no business being read every frame
	assert_false(ui.is_processing(), "The HUD is fed by signals, not by polling")
	assert_true((car.get_node(^"CarCombat") as CarCombat).health_changed.is_connected(ui._on_health_changed))
	assert_true(car.turbo_changed.is_connected(ui._on_turbo_changed))
