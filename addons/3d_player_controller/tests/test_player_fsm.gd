extends GutTest

## Purpose: To test the state transitions of the Player FSM.

class FsmTestBase:
	extends IntegrationTestBase

	var PlayerScene = load("res://addons/3d_player_controller/scenes/player.tscn")
	var root: Node3D
	var player: Player
	var floor_body: StaticBody3D
	var wall: StaticBody3D
	
	func before_each() -> void:
		root = Node3D.new()
		add_child_autofree(root)
		
		# Create floor
		floor_body = StaticBody3D.new()
		var floor_shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(100, 1, 100)
		floor_shape.shape = box
		floor_body.add_child(floor_shape)
		floor_body.position = Vector3(0, -0.5, 0)
		root.add_child(floor_body)
		
		# Create walls for climbing (surrounding player closely so 1m raycast hits)
		for dir in [Vector3(0, 0, -1.2), Vector3(0, 0, 1.2), Vector3(-1.2, 0, 0), Vector3(1.2, 0, 0)]:
			var w = StaticBody3D.new()
			var w_shape = CollisionShape3D.new()
			var w_box = BoxShape3D.new()
			if dir.z != 0:
				w_box.size = Vector3(10, 10, 1)
			else:
				w_box.size = Vector3(1, 10, 10)
			w_shape.shape = w_box
			w.add_child(w_shape)
			w.position = dir + Vector3(0, 5, 0)
			root.add_child(w)
		
		# Instantiate Player
		player = PlayerScene.instantiate()
		root.add_child(player)
		player.position = Vector3(0, 0.1, 0) # Slightly above floor to snap down
		
		# Await physics frames so state machine can boot
		await wait_physics_frames(2)

	func after_each() -> void:
		Input.action_release("jump")
		Input.action_release("sprint")
		Input.action_release("crouch")
		Input.action_release("attack")
		Input.action_release("move_up")
		Input.action_release("ui_down")
		Input.action_release("whistle")
		if is_instance_valid(root):
			root.free()
			root = null
			player = null

class TestStandingTransitions:
	extends FsmTestBase
	
	func test_standing_to_jumping():
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should start in STANDING state.")
		
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("jump")
		await wait_physics_frames(2)
		sender.action_up("jump")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.JUMPING, "Player should transition to JUMPING state after jump action.")

	func test_exhausted_player_can_jump():
		player.enable_stamina = true
		var stamina: Node = player.get_node("Stamina")
		stamina.set("stamina", 0.0)
		player.is_exhausted = true
		await wait_physics_frames(15)
		assert_eq(player.current_locomotion_node, "HeavyBreathing")

		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("jump")
		await wait_physics_frames(2)
		sender.action_up("jump")
		await wait_physics_frames(45)

		assert_ne(player.current_locomotion_node, "HeavyBreathing")
		assert_false(
				player.is_jump_queued,
				"Jump queue should execute from %s." % player.current_locomotion_node,
		)
		assert_false(
				player.is_on_floor(),
				"Player should leave floor from %s." % player.current_locomotion_node,
		)
		
	func test_standing_to_sprinting():
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should start in STANDING state.")
		
		player.smoothed_motion = Vector2(0, 1.0)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("move_up")
		sender.action_down("sprint")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.SPRINTING, "Player should transition to SPRINTING state while holding sprint.")
		
		sender.action_up("sprint")
		sender.action_up("move_up")
		player.smoothed_motion = Vector2.ZERO
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should transition back to STANDING after releasing sprint.")
		
	func test_standing_to_crouching():
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should start in STANDING state.")
		
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("crouch")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.CROUCHING, "Player should transition to CROUCHING state while holding crouch.")
		
		sender.action_up("crouch")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should transition back to STANDING after releasing crouch.")
		
	func test_standing_to_attacking():
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should start in STANDING state.")
		
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("attack")
		await wait_physics_frames(2)
		sender.action_up("attack")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.ATTACKING, "Player should transition to ATTACKING state after attack action.")

	## Drains the stamina bar so exhaustion sticks (it clears again only once the bar has refilled).
	func _exhaust() -> void:
		player.enable_stamina = true
		player.get_node("Stamina").set("stamina", 0.0)
		player.is_exhausted = true
		await wait_physics_frames(15)

	func test_exhausted_player_cannot_attack():
		# Catching their breath: HeavyBreathing has no way into the attack animations, so the press is ignored
		await _exhaust()
		assert_eq(player.current_locomotion_node, "HeavyBreathing")
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("attack")
		await wait_physics_frames(2)
		sender.action_up("attack")
		await wait_physics_frames(2)

		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "An exhausted Player stays standing.")
		assert_false(player.is_attacking, "And is never flagged as attacking.")

	func test_exhausted_crouching_player_cannot_attack():
		await _exhaust()
		player.state_machine.travel(NodeStateMachine.States.STANDING, NodeStateMachine.States.CROUCHING)
		await wait_physics_frames(2)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("attack")
		await wait_physics_frames(2)
		sender.action_up("attack")
		await wait_physics_frames(2)

		assert_eq(player.current_state, NodeStateMachine.States.CROUCHING, "An exhausted crouching Player stays crouching.")
		assert_false(player.is_attacking)

	func test_attack_that_never_reaches_an_animation_times_out_to_standing():
		# The 2H axe while exhausted: the state was entered but HeavyBreathing never travels to a slash
		var axe: Equipment = Equipment.new()
		axe.equipment_type = Equipment.EquipmentType.AXE_2H
		root.add_child(axe)
		player.inventory.add_equipment(axe)
		await _exhaust()
		assert_eq(player.current_locomotion_node, "HeavyBreathing")
		var attacking: Attacking = player.state_machine.get_node("Attacking")
		attacking.attack_timeout = 0.3
		player.state_machine.travel(NodeStateMachine.States.STANDING, NodeStateMachine.States.ATTACKING)
		assert_eq(player.current_state, NodeStateMachine.States.ATTACKING)
		assert_true(player.is_attacking)
		assert_false(attacking.attack_timeout_timer.is_stopped(), "The safety timer runs until an attack animation starts.")

		await wait_seconds(0.5)
		await wait_physics_frames(2)

		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "No attack animation within the timeout returns to standing.")
		assert_false(player.is_attacking, "The attacking flag is cleared with the state.")
		assert_eq(player.current_locomotion_node, "HeavyBreathing", "Still catching their breath, not stuck mid-swing.")

class TestSprintingTransitions:
	extends FsmTestBase
	
	func test_sprinting_to_sliding():
		player.smoothed_motion = Vector2(0, 1.0)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("move_up")
		sender.action_down("sprint")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.SPRINTING, "Player should be in SPRINTING state.")
		
		sender.action_down("crouch")
		await wait_physics_frames(2)
		sender.action_up("crouch")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.SLIDING, "Player should transition to SLIDING from sprint when crouch is pressed.")
		
		sender.action_up("sprint")
		sender.action_up("move_up")
		player.smoothed_motion = Vector2.ZERO

class TestPushingTransitions:
	extends FsmTestBase

	func test_standing_to_pushing_and_back():
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should start in STANDING state.")

		player.smoothed_motion = Vector2(0, 1.0)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("move_up")

		# Walk forward until the player presses into the surrounding wall
		var frames_waited: int = 0
		while player.current_state != NodeStateMachine.States.PUSHING and frames_waited < 180:
			await wait_physics_frames(5)
			frames_waited += 5

		assert_eq(player.current_state, NodeStateMachine.States.PUSHING, "Player should transition to PUSHING when moving into a wall.")
		assert_true(player.is_pushing, "Player should be flagged as pushing.")

		await wait_physics_frames(30)
		assert_true(player.current_locomotion_node in ["PushingStart", "Pushing"], "Pushing animation should become active, got %s." % player.current_locomotion_node)

		sender.action_up("move_up")
		player.smoothed_motion = Vector2.ZERO
		await wait_physics_frames(5)

		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should transition back to STANDING when input stops.")
		assert_false(player.is_pushing, "Player should not be flagged as pushing.")

class TestAirborneTransitions:
	extends FsmTestBase
	
	func test_falling_to_standing_on_floor():
		player.state_machine.travel(player.current_state, NodeStateMachine.States.FALLING)
		await wait_physics_frames(2)
		
		# Position player slightly above ground so they quickly land
		player.global_position = Vector3(0, 0.2, 0)
		await wait_physics_frames(10)
		
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should transition to STANDING after landing on floor.")

	func test_jumping_to_climbing():
		# Start on floor
		player.global_position = Vector3(0, 0.1, 0)
		await wait_physics_frames(2)
		
		# Jump 1: STANDING -> JUMPING
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("jump")
		await wait_physics_frames(2)
		sender.action_up("jump")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.JUMPING, "Player should be jumping.")
		
		# Teleport player into air near walls while in JUMPING state
		player.global_position = Vector3(0, 2.0, 0)
		player.ledge_detection_horizontal.force_raycast_update()
		await wait_physics_frames(2)
		
		# Jump 2: JUMPING -> CLIMBING
		sender.action_down("jump")
		await wait_physics_frames(2)
		sender.action_up("jump")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.CLIMBING, "Player should transition to CLIMBING when jumping near wall while in air.")

class TestAttackingTransitions:
	extends FsmTestBase
	
	func test_attacking_timeout():
		player.state_machine.get_node("Attacking").boxing_inactivity_delay = 0.5
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("attack")
		await wait_physics_frames(2)
		sender.action_up("attack")
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.ATTACKING, "Player should be in ATTACKING state.")
		
		assert_true(player.is_boxing, "Unarmed attack should enter the boxing stance.")
		
		await wait_seconds(0.8)
		await wait_physics_frames(2)
		
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should return to STANDING after attack timeout.")

class TestEquipmentInteractionTransitions:
	extends FsmTestBase

	func test_greatsword_logging_animation():
		var greatsword: Equipment = Equipment.new()
		greatsword.equipment_type = Equipment.EquipmentType.SWORD_2H
		greatsword.can_log = true
		root.add_child(greatsword)
		player.inventory.add_equipment(greatsword)

		player.locomotion_state.start("GreatSword")
		var greatsword_playback: AnimationNodeStateMachinePlayback = player.animation_tree.get(
				"parameters/LocomotionStateMachine/GreatSword/playback",
		)
		greatsword_playback.start("GreatSwordLocomotion")
		player.travel_locomotion("GreatSword/Logging")
		await wait_physics_frames(2)

		assert_true(player.is_logging, "GreatSword logging animation should become active.")

class TestEnableSettings:
	extends FsmTestBase

	func test_disabled_special_states_block_entry():
		var special_states: Array[NodeStateMachine.States] = [
			NodeStateMachine.States.FLYING,
			NodeStateMachine.States.PARAGLIDING,
			NodeStateMachine.States.RAGDOLLING,
		]
		for state: NodeStateMachine.States in special_states:
			player.state_machine.travel(player.current_state, state)
			assert_eq(
					player.current_state,
					NodeStateMachine.States.STANDING,
					"Disabled special state should not be entered.",
			)

	func test_enabled_flying_allows_entry():
		player.enable_flying = true
		player.state_machine.travel(player.current_state, NodeStateMachine.States.FLYING)
		assert_eq(player.current_state, NodeStateMachine.States.FLYING)

	func test_enabled_paraglider_allows_entry():
		player.enable_paraglider = true
		player.state_machine.travel(player.current_state, NodeStateMachine.States.PARAGLIDING)
		assert_eq(player.current_state, NodeStateMachine.States.PARAGLIDING)

	func test_enabled_ragdoll_allows_entry():
		player.enable_ragdoll = true
		player.state_machine.travel(player.current_state, NodeStateMachine.States.RAGDOLLING)
		assert_eq(player.current_state, NodeStateMachine.States.RAGDOLLING)

class TestPauseTransitions:
	extends FsmTestBase
	
	func test_no_ragdoll_when_pause_visible():
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Player should start in STANDING state.")
		player.enable_ragdoll = true
		player.pause.show_menu()
		assert_true(player.is_paused, "Player should be paused.")
		assert_true(player.pause.visible, "Pause CanvasLayer should be visible.")
		
		player.state_machine.travel(player.current_state, NodeStateMachine.States.RAGDOLLING)
		await wait_physics_frames(2)
		
		assert_ne(player.current_state, NodeStateMachine.States.RAGDOLLING, "Player should not transition to RAGDOLLING when Pause CanvasLayer is visible.")

class TestRidingTransitions:
	extends FsmTestBase

	## A rideable that only records what the Riding state does to it and asks for one animation.
	class MockRideable:
		extends Node3D
		signal locomotion_requested(state_path: String, immediate: bool)
		signal jump_requested
		var blocks_hands: bool = false
		var disables_collision: bool = false
		var mount_animation: String = ""
		var dismount_animation: String = ""
		var input_type: int = -1
		var seat: Node3D
		var camera: Camera3D
		var mounted_by: Player
		var dismounted: bool = false
		var rides: int = 0

		func _ready() -> void:
			camera = Camera3D.new()
			add_child(camera)

		func mount(p: Player) -> void:
			mounted_by = p
			locomotion_requested.emit("StandingLocomotion", true)

		func dismount(_p: Player) -> void:
			dismounted = true

		func ride(_p: Player, _delta: float) -> void:
			rides += 1

		func ride_input(p: Player, event: InputEvent) -> void:
			if event.is_action_pressed("whistle"):
				p.dismount()

		func get_contextual_controls(_input_type: int) -> Dictionary:
			return {"key_k": "Dismount", "joypad_button_1": "Fast Push", "no_such": "Dropped"}

	var rideable: MockRideable

	func before_each() -> void:
		super.before_each()
		rideable = MockRideable.new()
		root.add_child(rideable)

	func test_mount_enters_riding_and_hands_the_rideable_the_player():
		player.mount(rideable)
		await wait_physics_frames(3)
		assert_eq(player.current_state, NodeStateMachine.States.RIDING, "mount() enters the RIDING state")
		assert_true(player.is_riding)
		assert_eq(player.riding, rideable)
		assert_eq(rideable.mounted_by, player, "The rideable was given the Player")
		assert_gt(rideable.rides, 0, "And is ridden every physics frame")

	func test_dismount_returns_to_standing_and_tells_the_rideable():
		player.mount(rideable)
		await wait_physics_frames(2)
		player.dismount()
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.STANDING)
		assert_false(player.is_riding)
		assert_null(player.riding)
		assert_true(rideable.dismounted)

	func test_rideable_input_can_dismount():
		player.mount(rideable)
		await wait_physics_frames(2)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("whistle")
		await wait_physics_frames(2)
		sender.action_up("whistle")
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "The rideable's ride_input dismounted on whistle")

	func test_held_object_reserves_dpad_down_while_riding():
		player.mount(rideable)
		await wait_physics_frames(2)
		var held_body: RigidBody3D = RigidBody3D.new()
		root.add_child(held_body)
		player.held_object._pickup_rigidbody(held_body)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("whistle")
		await wait_physics_frames(2)
		sender.action_up("whistle")
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.RIDING, "Held object controls reserve D-pad Down from the rideable")
		player.held_object.drop_held_rigidbody()

	func test_riding_contextual_controls_come_from_the_rideable_by_label_name():
		player.mount(rideable)
		await wait_physics_frames(2)
		var riding_node: Riding = player.state_machine.get_node("Riding") as Riding
		var kb_controls = riding_node.get_contextual_controls(0)
		assert_eq(kb_controls.get(player.controls.key_k_label), "Dismount", "\"key_k\" lands on the Controls' key_k_label")
		assert_eq(kb_controls.get(player.controls.joypad_button_1_label), "Fast Push")
		assert_eq(kb_controls.size(), 2, "A name with no label on the Controls is dropped")

	func test_riding_keeps_the_rideables_input_type_current():
		player.controls.current_input_type = Controls.InputType.SONY
		player.mount(rideable)
		await wait_physics_frames(2)
		assert_eq(rideable.input_type, Controls.InputType.SONY, "Handed the Player's device on mount")
		player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
		assert_eq(rideable.input_type, Controls.InputType.KEYBOARD_MOUSE, "And every change after")

	func test_riding_makes_the_rideables_camera_current_and_gives_the_view_back():
		assert_true(player.camera.current)
		player.mount(rideable)
		await wait_physics_frames(2)
		assert_true(rideable.camera.current, "The rideable's camera is the view while ridden")
		assert_false(player.camera.current)
		player.dismount()
		await wait_physics_frames(2)
		assert_true(player.camera.current, "The Player's own camera returns on dismount")
		assert_false(rideable.camera.current)

	func test_riding_handles_collision_crosshair_and_step_up_ray():
		rideable.disables_collision = true
		rideable.blocks_hands = true
		player.mount(rideable)
		await wait_physics_frames(2)
		assert_true(player.collision_shape.disabled, "disables_collision turns the Player's shape off")
		assert_true(player.separation_ray_shape.disabled, "The step-up ray is off for every ride")
		assert_false(player.crosshair.visible, "blocks_hands hides the crosshair")
		player.dismount()
		await wait_physics_frames(2)
		assert_false(player.collision_shape.disabled)
		assert_false(player.separation_ray_shape.disabled)
		assert_true(player.crosshair.visible)

	func test_a_seat_pins_the_player_to_the_rideable_every_frame():
		var seat: Node3D = Node3D.new()
		rideable.add_child(seat)
		rideable.set("seat", seat)
		rideable.global_position = Vector3(4.0, 0.0, 0.0)
		player.mount(rideable)
		await wait_physics_frames(2)
		assert_eq(player.get_parent(), root, "The Player stays where it is in the tree")
		assert_almost_eq(player.global_position, seat.global_position, Vector3.ONE * 0.01, "But sits on the seat")
		rideable.rotate_y(1.0)
		rideable.global_position += Vector3(0.0, 0.0, 2.0)
		await wait_physics_frames(1)
		assert_almost_eq(player.global_basis.z.dot(rideable.global_basis.z), 1.0, 0.01, "Turning the rideable turns the Player with it")
		assert_almost_eq(player.global_position, seat.global_position, Vector3.ONE * 0.01, "And moving it moves them")
		var facing: Vector3 = player.player_model.global_basis.z
		assert_almost_eq(facing.dot(-seat.global_basis.z), 1.0, 0.01, "The rider faces along the seat's -Z, Godot's forward")
		assert_almost_eq(player.orientation.basis.z.dot(facing), 1.0, 0.01, "And orientation agrees with the model")
		player.dismount()
		await wait_physics_frames(2)
		assert_almost_eq(player.global_basis.y, Vector3.UP, Vector3.ONE * 0.01, "Upright again on dismount")
		assert_almost_eq(player.orientation.basis.z.dot(facing), 1.0, 0.05, "Still facing the way they sat, no spin on the way off")

	func test_mount_animation_plays_before_the_ride_and_ends_with_the_clip():
		rideable.mount_animation = "EnteringCar"
		player.mount(rideable)
		await wait_physics_frames(3)
		assert_true(player.is_mounting, "The get-on clip plays first")
		assert_eq(player.current_locomotion_node, "EnteringCar")
		assert_eq(rideable.rides, 0, "The rideable is not ridden while it plays")
		var riding_node: Riding = player.state_machine.get_node("Riding") as Riding
		riding_node._on_locomotion_node_changed("StandingLocomotion")
		await wait_physics_frames(2)
		assert_false(player.is_mounting, "The clip ending seats the rider")
		assert_gt(rideable.rides, 0, "And the ride begins")

	func test_dismount_animation_plays_before_the_dismount_unless_immediate():
		rideable.dismount_animation = "ExitingCar"
		player.mount(rideable)
		await wait_physics_frames(2)
		player.dismount()
		await wait_physics_frames(2)
		assert_true(player.is_dismounting, "The get-off clip plays first")
		assert_eq(player.current_locomotion_node, "ExitingCar")
		assert_eq(player.current_state, NodeStateMachine.States.RIDING, "Still riding until it ends")
		assert_false(rideable.dismounted)
		var riding_node: Riding = player.state_machine.get_node("Riding") as Riding
		riding_node._on_locomotion_node_changed("StandingLocomotion")
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "The clip ending finishes the dismount")
		assert_true(rideable.dismounted)
		player.mount(rideable)
		await wait_physics_frames(2)
		player.dismount(true)
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "An immediate dismount skips the clip")

	func test_jump_requested_queues_the_players_jump():
		player.mount(rideable)
		await wait_physics_frames(2)
		rideable.jump_requested.emit()
		assert_true(player.is_jump_queued, "The rideable's jump request queues the Player's jump animation")

	func test_blocks_hands_holsters_equipment():
		rideable.blocks_hands = true
		player.mount(rideable)
		await wait_physics_frames(2)
		assert_true(player.riding_blocks_hands())
		player.dismount()
		await wait_physics_frames(2)
		assert_false(player.riding_blocks_hands())


class TestCrouchingTransitions:
	extends FsmTestBase

	func test_crouching_to_falling_when_airborne():
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("crouch")
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.CROUCHING, "Player should be crouching.")

		player.global_position = Vector3(0, 6.0, 0)
		await wait_physics_frames(3)
		assert_eq(player.current_state, NodeStateMachine.States.FALLING, "Crouching player leaving the floor should fall.")
		sender.action_up("crouch")

class TestSlidingTransitions:
	extends FsmTestBase

	func test_sliding_auto_exits_to_standing():
		player.smoothed_motion = Vector2(0, 1.0)
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("move_up")
		sender.action_down("sprint")
		await wait_physics_frames(2)
		sender.action_down("crouch")
		await wait_physics_frames(2)
		sender.action_up("crouch")
		sender.action_up("sprint")
		sender.action_up("move_up")
		assert_eq(player.current_state, NodeStateMachine.States.SLIDING, "Player should be sliding.")

		var frames_waited: int = 0
		while player.current_state == NodeStateMachine.States.SLIDING and frames_waited < 300:
			await wait_physics_frames(5)
			frames_waited += 5
		assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Sliding should end in STANDING once RunningSlide finishes.")

class TestHangingTransitions:
	extends FsmTestBase

	func test_drop_blocked_while_climbing_on_and_cleared_on_exit():
		player.global_position = Vector3(0, 2.0, 0)
		player.state_machine.travel(player.current_state, NodeStateMachine.States.HANGING)
		await wait_physics_frames(2)
		assert_eq(player.current_state, NodeStateMachine.States.HANGING, "Player should be hanging.")

		player.is_climbing_on = true
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)
		sender.action_down("crouch")
		await wait_physics_frames(2)
		sender.action_up("crouch")
		assert_eq(player.current_state, NodeStateMachine.States.HANGING, "Drop must be ignored while climbing on to the ledge.")

		player.state_machine.travel(player.current_state, NodeStateMachine.States.FALLING)
		assert_false(player.is_climbing_on, "Leaving HANGING must clear is_climbing_on.")

class TestStandingLocomotion:
	extends FsmTestBase

	func test_equipment_changed_rederives_grounded_locomotion():
		var greatsword: Equipment = Equipment.new()
		greatsword.equipment_type = Equipment.EquipmentType.SWORD_2H
		root.add_child(greatsword)
		player.inventory.add_equipment(greatsword)
		await wait_physics_frames(2)

		assert_true(
			player.current_locomotion_path.begins_with("GreatSword"),
			"Equipping a greatsword while standing should travel to the GreatSword locomotion, got %s." % player.current_locomotion_path,
		)
