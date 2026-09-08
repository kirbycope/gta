extends GutTest

## Purpose: The skate park scene mounts the Player on the board, its ramps are ridable wood, and the
## Skateboard rides a half pipe transition like Tony Hawk: up the wall, off the lip with the
## outward speed dropped, and back down into the pipe facing the way it rolls.

const PARK_SCENE: PackedScene = preload("res://addons/tcps/scenes/skate_park.tscn")


func test_vert_launch_direction_only_off_steep_walls() -> void:
	var up: Vector3 = Vector3.UP
	var wall: Vector3 = Vector3(-sin(deg_to_rad(75.0)), cos(deg_to_rad(75.0)), 0.0) # face points left, so the deck is to the right
	var out: Vector3 = Skateboard.vert_launch_direction(wall, up)
	assert_almost_eq(out, Vector3.RIGHT, Vector3.ONE * 0.001, "A 75 degree wall's launch direction to drop is the one over its deck")
	var slope: Vector3 = Vector3(-sin(deg_to_rad(30.0)), cos(deg_to_rad(30.0)), 0.0)
	assert_eq(Skateboard.vert_launch_direction(slope, up), Vector3.ZERO, "A 30 degree bank is not vert")
	assert_eq(Skateboard.vert_launch_direction(up, up), Vector3.ZERO, "Flat ground is not vert")


func test_vert_launch_rotates_the_speed_into_the_wall_plane() -> void:
	var launched: Vector3 = Skateboard.vert_launch_velocity(Vector3(-4.0, 7.0, 1.0), Vector3.RIGHT)
	assert_almost_eq(launched.x, 0.0, 0.001, "Nothing is left heading out of the wall's plane")
	assert_almost_eq(launched.length(), Vector3(-4.0, 7.0, 1.0).length(), 0.001, "But the speed is kept, as THUG's RotateToPlane keeps it")
	assert_gt(launched.y, 7.0, "So the deck-ward speed became climb")
	assert_almost_eq(launched.z / launched.y, 1.0 / 7.0, 0.001, "Along the lip and up keep their proportion")


func test_park_ramps_are_ridable_wood() -> void:
	var park: Node3D = PARK_SCENE.instantiate()
	add_child_autofree(park)
	for path: String in ["HalfPipe/LeftTransition", "HalfPipe/RightTransition", "QuarterPipe", "Funbox"]:
		var ramp: CSGPolygon3D = park.get_node(path) as CSGPolygon3D
		assert_not_null(ramp, path + " is a CSGPolygon3D")
		assert_true(ramp.use_collision, path + " has collision")
		assert_true(ramp.is_in_group("WOOD"), path + " rolls like wood")
	assert_true(park.get_node("Ground").is_in_group("CONCRETE"), "The ground rolls like concrete")


## Puts the Player on the board, aims at the left wall from the flat, pushes across the flat, lets go of push on
## the transition the way a THPS player does for vert (holding it would break vert and fly over the deck, unless
## [param hold_forward]), and waits for the landing; with [param ollie] the jump fires as the wall goes past 70
## degrees. Returns what happened.
func _ride_the_left_wall(ollie: bool, hold_forward: bool = false) -> Dictionary:
	var park: Node3D = PARK_SCENE.instantiate()
	add_child_autofree(park)
	var player: Player = park.get_node("Player")
	await wait_seconds(0.6)
	assert_true(player.is_riding, "The MountTimer put the Player on the board")
	var state: Skateboard = player.riding as Skateboard
	player.warp_to(Transform3D(Basis(), Vector3(1.0, 0.1, -10.0)))
	player.rotate_model_to_direction(Vector3.LEFT)
	await wait_physics_frames(3)
	var ride: Dictionary = {"top": 0.0, "launched": false, "launch_x": 0.0, "shallowest_air_lean": PI, "ollied": false, "camera_travel_in_air": 0.0, "max_plane_drift": 0.0, "camera_below_skater_at_peak": false}
	var launch_pos: Vector3 = Vector3.ZERO
	var camera_at_launch: Vector3 = Vector3.ZERO
	var air_frames: int = 0
	var frames: int = 0
	while frames < 400 and not (player.is_on_floor() and (ride.launched or (hold_forward and ride.top > 3.5))):
		# The InputSynchronizer rewrites motion from the real input every physics frame, so keep feeding it
		var on_transition: bool = player.get_floor_normal().y < 0.7
		var pushing: bool = (hold_forward and air_frames < 10) or (not ride.launched and player.is_on_floor() and not on_transition)
		player.player_input.motion = Vector2(0.0, 1.0) if pushing else Vector2.ZERO
		if ollie and not ride.ollied and player.is_on_floor() and player.get_floor_normal().y < 0.35:
			player.is_jumping = true
			player.is_jump_queued = true
			state._ollie()
			ride.ollied = true
		await get_tree().physics_frame
		frames += 1
		ride.top = maxf(ride.top, player.global_position.y)
		air_frames = 0 if player.is_on_floor() else air_frames + 1
		if state.vert_out != Vector3.ZERO and air_frames >= 5:
			if not ride.launched:
				ride.launch_x = player.global_position.x
				launch_pos = player.global_position
				camera_at_launch = state.camera.global_position
			ride.launched = true
			ride.shallowest_air_lean = minf(ride.shallowest_air_lean, absf(player.model_pitch))
			var camera_offset: Vector3 = state.camera.global_position - camera_at_launch
			ride.camera_travel_in_air = maxf(ride.camera_travel_in_air, Vector2(camera_offset.x, camera_offset.z).length())
			ride.max_plane_drift = maxf(ride.max_plane_drift, absf((player.global_position - launch_pos).dot(state.vert_normal)))
			if absf(player.velocity.y) < 0.5 and state.camera.global_position.y < player.global_position.y - 1.0:
				ride.camera_below_skater_at_peak = true
	ride.player = player
	return ride


func test_player_is_put_on_the_board_and_rides_the_half_pipe() -> void:
	var ride: Dictionary = await _ride_the_left_wall(false)
	var player: Player = ride.player
	assert_true(ride.launched, "Speed carried the board off the vert wall")
	assert_gt(ride.top, 3.0, "The skater cleared the lip")
	assert_gt(ride.shallowest_air_lean, deg_to_rad(45.0), "Momentum keeps the wall's lean through vert air instead of snapping upright")
	assert_true(player.is_on_floor(), "And came back down")
	assert_gt(player.global_position.x, -6.0, "Landing back in the pipe, not over the deck")
	await wait_physics_frames(5) # the landing turn happens on the physics frame after the touchdown
	var facing: float = player.orientation.basis.z.dot(player.velocity.normalized()) if player.velocity.length() > 1.0 else 1.0
	assert_gt(facing, 0.0, "Facing the way the board rolls after the landing")


func test_an_ollie_at_the_lip_pops_straight_up_and_lands_back_in_the_pipe() -> void:
	var ride: Dictionary = await _ride_the_left_wall(true)
	var player: Player = ride.player
	assert_true(ride.ollied, "The ollie fired on the wall")
	assert_true(ride.launched, "And the launch was still vert")
	assert_gt(ride.top, 6.0, "The pop adds height over the plain launch")
	assert_true(player.is_on_floor(), "The skater came back down")
	assert_almost_eq(player.global_position.x, ride.launch_x, 1.0, "Onto the wall they left, not out over the pipe or the deck")
	assert_lt(ride.max_plane_drift, 0.05, "Vert tracking holds the skater in the wall's plane the whole flight")
	assert_lt(ride.camera_travel_in_air, 3.0, "The camera swings out into the pipe and then stays parked at the ramp instead of chasing")
	assert_true(ride.camera_below_skater_at_peak, "And watches the peak from below")


func test_the_camera_settles_in_behind_the_way_the_board_travels() -> void:
	var park: Node3D = PARK_SCENE.instantiate()
	add_child_autofree(park)
	var player: Player = park.get_node("Player")
	await wait_seconds(0.6)
	assert_true(player.is_riding, "The MountTimer put the Player on the board")
	player.warp_to(Transform3D(Basis(), Vector3(0.0, 0.1, 5.0)))
	player.rotate_model_to_direction(Vector3.LEFT)
	for i in 90:
		player.player_input.motion = Vector2(0.0, 1.0)
		await get_tree().physics_frame
	var travel: Vector3 = player.velocity.normalized()
	assert_gt(player.velocity.length(), 2.0, "The board is rolling")
	var camera: Camera3D = (player.riding as Skateboard).camera
	var looking: Vector3 = -camera.global_basis.z
	assert_gt(looking.slide(Vector3.UP).normalized().dot(travel), 0.9, "The camera looks along the way the board travels")
	assert_lt(camera.global_position.dot(travel), player.global_position.dot(travel), "From behind the skater")
	assert_true(camera.current, "And it is the view while riding")


func test_holding_forward_at_the_lip_breaks_vert_and_flies_over_the_deck() -> void:
	var ride: Dictionary = await _ride_the_left_wall(false, true)
	var player: Player = ride.player
	assert_false(ride.launched, "Holding forward at the lip is not a vert air")
	assert_gt(ride.top, 3.5, "But the skater still flew")
	assert_true(player.is_on_floor(), "And came down")
	assert_lt(player.global_position.x, -8.0, "Beyond the deck, out the back of the half pipe")
