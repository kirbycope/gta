extends GutTest

## Purpose: the chase camera's lock-on. With nothing to lock onto it follows the
## vehicle the way it always has; with a target it swings round to keep that
## target in view and the vehicle between itself and it, which is what Rocket
## League's ball cam is.
##
## The yaw convention is the thing worth pinning down. The arm hangs off the
## back of the pivot, so aiming the pivot along the line to the target is what
## puts the camera behind the vehicle rather than in front of it, and getting
## that sign wrong looks almost right until the target is off to one side.

const VEHICLE_CAMERA: PackedScene = preload("res://addons/gta/scenes/vehicle_camera.tscn")

var chase: VehicleCamera
var vehicle: RigidBody3D
var target: Node3D


func before_each() -> void:
	chase = VEHICLE_CAMERA.instantiate()
	add_child_autofree(chase)
	vehicle = RigidBody3D.new()
	add_child_autofree(vehicle)
	target = Node3D.new()
	add_child_autofree(target)
	await wait_physics_frames(2)
	chase.vehicle = vehicle
	chase.follow_timer.stop()


## Settle the camera by running its own step enough times for the smoothing to
## arrive, rather than asserting against a single frame of a lerp.
func _settle() -> void:
	for _i: int in 200:
		chase._physics_process(1.0 / 60.0)


func test_with_no_target_it_follows_where_the_vehicle_points() -> void:
	vehicle.global_position = Vector3.ZERO
	vehicle.global_rotation = Vector3.ZERO
	chase.look_target = null
	_settle()
	# the vehicle's own forward is positive z, and the camera looks along it
	assert_almost_eq(chase.global_basis.z.z, -1.0, 0.05,
		"The camera should sit behind the vehicle looking the way it faces")


func test_a_target_swings_the_camera_round_to_face_it() -> void:
	vehicle.global_position = Vector3.ZERO
	vehicle.global_rotation = Vector3.ZERO
	target.global_position = Vector3(30.0, 0.0, 0.0)
	chase.look_target = target
	_settle()
	var looking: Vector3 = -chase.global_basis.z
	assert_almost_eq(looking.x, 1.0, 0.05, "It should be looking at the target, not down the bonnet")


func test_the_camera_ends_up_on_the_far_side_of_the_vehicle_from_the_target() -> void:
	# this is the whole point of a ball cam: the vehicle stays in frame between
	# the camera and the thing being watched
	vehicle.global_position = Vector3.ZERO
	target.global_position = Vector3(0.0, 0.0, -40.0)
	chase.look_target = target
	_settle()
	var camera_at: Vector3 = chase.camera.global_position
	assert_gt(camera_at.z, vehicle.global_position.z,
		"With the target at negative z the camera belongs at positive z")


func test_it_tilts_up_at_a_target_overhead() -> void:
	vehicle.global_position = Vector3.ZERO
	target.global_position = Vector3(0.0, 20.0, -20.0)
	chase.look_target = target
	_settle()
	assert_gt(-chase.global_basis.z.y, 0.1, "A ball in the air is looked up at")


func test_it_tilts_down_at_a_target_below() -> void:
	vehicle.global_position = Vector3(0.0, 30.0, 0.0)
	target.global_position = Vector3(0.0, 0.0, -20.0)
	chase.look_target = target
	_settle()
	assert_lt(-chase.global_basis.z.y, 0.0, "And a ball below is looked down at")


func test_the_tilt_is_capped() -> void:
	vehicle.global_position = Vector3.ZERO
	target.global_position = Vector3(0.0, 400.0, 0.1)
	chase.look_target = target
	_settle()
	assert_lte(absf(chase.rotation.x), chase.target_pitch_limit + 0.01,
		"Straight overhead must not flip the camera over the top")


func test_a_target_on_top_of_the_vehicle_holds_the_view_instead_of_spinning() -> void:
	vehicle.global_position = Vector3.ZERO
	vehicle.global_rotation = Vector3.ZERO
	chase.look_target = null
	_settle()
	var held: float = chase.rotation.y
	# all but on the pivot itself, which is where the direction is measured
	# from and so where it stops meaning anything
	target.global_position = chase.global_position + Vector3(0.002, 0.0, 0.002)
	chase.look_target = target
	_settle()
	assert_almost_eq(chase.rotation.y, held, 0.01,
		"Too close to read a direction, so the angle is kept rather than thrashed")


func test_dropping_the_target_goes_back_to_following_the_vehicle() -> void:
	vehicle.global_position = Vector3.ZERO
	vehicle.global_rotation = Vector3.ZERO
	target.global_position = Vector3(40.0, 0.0, 0.0)
	chase.look_target = target
	_settle()
	chase.look_target = null
	_settle()
	assert_almost_eq(chase.global_basis.z.z, -1.0, 0.05)


func test_a_freed_target_does_not_take_the_camera_with_it() -> void:
	vehicle.global_position = Vector3.ZERO
	vehicle.global_rotation = Vector3.ZERO
	var doomed: Node3D = Node3D.new()
	add_child(doomed)
	doomed.global_position = Vector3(0.0, 0.0, 40.0)
	chase.look_target = doomed
	_settle()
	doomed.free()
	_settle()
	assert_almost_eq(chase.global_basis.z.z, -1.0, 0.05,
		"A target that has gone falls back to the ordinary chase camera")


func test_ending_a_drive_lets_go_of_the_target() -> void:
	chase.look_target = target
	chase.end()
	assert_null(chase.look_target, "The next driver starts without the last one's lock")
