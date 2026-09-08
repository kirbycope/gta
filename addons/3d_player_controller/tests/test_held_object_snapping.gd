extends GutTest

## Purpose: To test held object rotation snapping, hit detection delivery and the water splash lifetime.

const PLAYER_SCENE = preload("res://addons/3d_player_controller/scenes/player.tscn")
const CONTROLS_SCENE = preload("res://addons/3d_player_controller/scenes/controls.tscn")
const SPLASH_SCENE = preload("res://addons/3d_player_controller/scenes/water_splash.tscn")


class HitTarget extends StaticBody3D:
	var hits: int = 0

	func register_weapon_hit(_equipment: Node, _hit_node: Node) -> void:
		hits += 1


func test_held_object_45_degree_rotation_snapping() -> void:
	add_child_autofree(CONTROLS_SCENE.instantiate())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	var held_object: HeldObject = player.held_object as HeldObject
	assert_not_null(held_object, "HeldObject node should exist")
	assert_not_null(held_object.throw_charge_bar, "The throw charge bar comes from controls.tscn")
	assert_false(held_object.throw_charge_bar.visible, "The throw charge bar starts hidden")

	var rb = RigidBody3D.new()
	var col = CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	rb.add_child(col)
	add_child_autofree(rb)
	rb.global_position = player.global_position + Vector3(0, 0, -2)

	held_object._pickup_rigidbody(rb)
	assert_true(held_object.is_holding_rigidbody(), "Should be holding rigidbody")
	assert_eq(player.controls.joypad_button_0_label.text, "Drop", "Holding pushes the held-object control labels")

	held_object._is_held_rotation_mode = true
	held_object.use_discrete_rotation_snap = true
	held_object.rotation_snap_angle = 45.0
	var initial_rot = rb.rotation_degrees

	var event = InputEventAction.new()
	event.action = "next_weapon"
	event.pressed = true
	held_object._input(event)
	assert_almost_eq(abs(rb.rotation_degrees.y - initial_rot.y), 45.0, 1.0, "D-pad press in rotation mode should snap rotation by 45 degrees")

	held_object.drop_held_rigidbody()
	assert_false(held_object.is_holding_object(), "Dropping releases the body")
	assert_eq(rb.get_parent(), player.get_parent(), "Dropped bodies return to the player's parent")
	assert_ne(player.controls.joypad_button_0_label.text, "Drop", "Dropping hands the labels back to the state")


func test_hit_detection_registers_once_per_swing_via_hitbox() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var hit_detection: HitDetection = player.get_node("HitDetection")

	var weapon = Equipment.new()
	weapon.can_attack = true
	weapon.equipment_type = Equipment.EquipmentType.SWORD_1H
	var hitbox = Area3D.new()
	hitbox.name = "Hitbox"
	var shape = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	hitbox.add_child(shape)
	weapon.add_child(hitbox)
	add_child_autofree(weapon)
	player.inventory.add_equipment(weapon)
	assert_true(hitbox.body_entered.is_connected(hit_detection._on_hitbox_body_entered.bind(hitbox, weapon)), "Equipping connects the weapon Hitbox")
	assert_false(hitbox.monitoring, "Hitboxes only monitor during swings")

	var target = HitTarget.new()
	add_child_autofree(target)
	hit_detection._on_locomotion_node_changed("Shield/ShieldDownwardSlash")
	hit_detection._on_hitbox_body_entered(target, hitbox, weapon)
	hit_detection._on_hitbox_body_entered(target, hitbox, weapon)
	assert_eq(target.hits, 1, "A target is notified once per swing")

	hit_detection._on_locomotion_node_changed("Shield/ShieldCrossSlash")
	hit_detection._on_hitbox_body_entered(target, hitbox, weapon)
	assert_eq(target.hits, 2, "A new swing may hit the same target again")

	player.inventory.remove_equipment(weapon)
	assert_true(hit_detection._hitboxes.has(hit_detection.left_hand_hitbox), "Unarmed falls back to the hand hitboxes")


func test_water_splash_frees_once_emitters_finish() -> void:
	var splash: WaterSplash = SPLASH_SCENE.instantiate()
	splash.impact_speed = 6.0
	add_child_autofree(splash)
	assert_eq(splash.emitters.size(), 2, "Both emitters are exported from the scene")
	for emitter in splash.emitters:
		assert_true(emitter.emitting, "Emitters start on ready")

	splash.emitters[0].emitting = false
	splash._on_emitter_finished()
	assert_false(splash.is_queued_for_deletion(), "The splash waits for every emitter")
	splash.emitters[1].emitting = false
	splash._on_emitter_finished()
	assert_true(splash.is_queued_for_deletion(), "The splash frees once all emitters finished")
