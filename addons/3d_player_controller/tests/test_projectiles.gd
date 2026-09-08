extends GutTest

## Purpose: Projectiles sweep a ray between physics steps so fast rounds hit small targets,
## deliver hits through register_projectile_hit / impulses, and Firearms fire from the muzzle
## along the Player's projectile ray while showing the laser sight.

const BULLET_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/bullet.tscn")
const LASER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/laser_sight.tscn")
const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const FIREARM_SCRIPT: Script = preload("res://addons/3d_player_controller/scripts/firearm.gd")


## A balloon-like target: an Area3D child and a parent that accepts projectile hits.
class HitTarget extends Node3D:
	var hits: int = 0
	var last_point: Vector3
	func register_projectile_hit(_projectile: Projectile, point: Vector3, _normal: Vector3) -> void:
		hits += 1
		last_point = point


var root: Node3D


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)


func _make_area_target(at: Vector3, radius: float = 0.3) -> HitTarget:
	var target := HitTarget.new()
	target.position = at
	root.add_child(target)
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	(shape.shape as SphereShape3D).radius = radius
	area.add_child(shape)
	target.add_child(area)
	return target


func _shoot(from: Vector3, direction: Vector3, speed: float) -> Projectile:
	var bullet: Projectile = BULLET_SCENE.instantiate()
	root.add_child(bullet)
	bullet.launch(Transform3D(Basis.IDENTITY, from), direction, speed, null)
	return bullet


func test_fast_bullet_hits_small_area_target_via_sweep() -> void:
	# 300 m/s moves 5 m per physics step: pure contact detection would tunnel straight through a 0.3 m balloon.
	var target := _make_area_target(Vector3(0, 0, -6))
	var bullet := _shoot(Vector3.ZERO, Vector3.FORWARD, 300.0)
	watch_signals(bullet)
	await wait_physics_frames(4)
	assert_eq(target.hits, 1, "The swept ray must register exactly one hit on the balloon-sized area")
	assert_almost_eq(target.last_point.z, -5.7, 0.2, "The hit lands on the near surface of the sphere")
	assert_false(is_instance_valid(bullet) and bullet.is_inside_tree(), "Bullets free themselves after hitting")


func test_bullet_skips_areas_without_a_hit_handler() -> void:
	# A water/weather style area in front of the balloon must not swallow the round.
	var zone := Area3D.new()
	var zone_shape := CollisionShape3D.new()
	zone_shape.shape = BoxShape3D.new()
	(zone_shape.shape as BoxShape3D).size = Vector3(4, 4, 4)
	zone.add_child(zone_shape)
	zone.position = Vector3(0, 0, -3)
	root.add_child(zone)
	var target := _make_area_target(Vector3(0, 0, -6))
	_shoot(Vector3.ZERO, Vector3.FORWARD, 300.0)
	await wait_physics_frames(4)
	assert_eq(target.hits, 1, "Areas with no handler are skipped by the sweep")


func test_bullet_pushes_rigid_body_target() -> void:
	var ball := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	(shape.shape as SphereShape3D).radius = 0.5
	ball.add_child(shape)
	ball.position = Vector3(0, 0, -4)
	ball.gravity_scale = 0.0
	root.add_child(ball)
	_shoot(Vector3.ZERO, Vector3.FORWARD, 200.0)
	await wait_physics_frames(6)
	assert_lt(ball.linear_velocity.z, -0.5, "A bullet impact pushes a rigid body along its flight direction")


func test_laser_sight_spans_muzzle_to_aim_point() -> void:
	var laser: LaserSight = LASER_SCENE.instantiate()
	root.add_child(laser)
	laser.aim(Vector3(1, 1, 1), Vector3(1, 1, -9))
	assert_almost_eq(laser.beam.scale.z, 10.0, 0.001, "Beam length equals the aim distance")
	assert_almost_eq(laser.dot.global_position.z, -9.0, 0.001, "The dot sits on the aim point")
	assert_almost_eq(laser.global_position.x, 1.0, 0.001)


func test_firearm_fires_along_the_projectile_ray_level_with_the_muzzle() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	var gun: Firearm = FIREARM_SCRIPT.new()
	gun.player = player
	gun.projectile_scene = BULLET_SCENE
	gun.projectile_speed = 120.0
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0.3, 1.2, -0.4)
	gun.add_child(muzzle)
	gun.muzzle = muzzle
	var timer := Timer.new()
	timer.one_shot = true
	gun.add_child(timer)
	gun.fire_timer = timer
	root.add_child(gun)
	await wait_physics_frames(1)

	watch_signals(gun)
	var bullet: Projectile = gun.fire()
	assert_not_null(bullet, "fire() spawns a projectile")
	assert_signal_emitted(gun, "fired")
	var ray: RayCast3D = player.projectile_raycast
	var along: Vector3 = -ray.global_basis.z
	var off_line: float = (bullet.global_position - ray.global_position).cross(along).length()
	assert_almost_eq(off_line, 0.0, 0.01, "Rounds leave on the crosshair line")
	assert_almost_eq((bullet.global_position - ray.global_position).dot(along), (muzzle.global_position - ray.global_position).dot(along), 0.01, "Level with the muzzle")
	assert_almost_eq(bullet.linear_velocity.normalized().dot(along), 1.0, 0.01, "Rounds fly straight down the projectile ray")
	assert_almost_eq(bullet.linear_velocity.length(), 120.0, 0.01, "Round speed is the weapon's projectile_speed")
	assert_eq(bullet.shooter, player)
	assert_eq(bullet.weapon, gun)
	bullet.free()


func _gun(player: Player) -> Firearm:
	var gun: Firearm = FIREARM_SCRIPT.new()
	gun.player = player
	gun.projectile_scene = BULLET_SCENE
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0.3, 1.2, -0.4)
	gun.add_child(muzzle)
	gun.muzzle = muzzle
	var timer := Timer.new()
	timer.one_shot = true
	gun.add_child(timer)
	gun.fire_timer = timer
	root.add_child(gun)
	return gun


func test_magazine_empties_and_reloads_from_the_inventory() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	var gun: Firearm = _gun(player)
	gun.equipment_type = Equipment.EquipmentType.PISTOL
	gun.magazine_size = 2
	gun.reload_time = 0.2
	gun.rounds = 2
	# The reserve is the inventory: one two-round magazine (an AmmoItem built here, so no .tres is loaded)
	var magazine := AmmoItem.new()
	magazine.id = &"test_pistol_magazine"
	magazine.weapon_type = Equipment.EquipmentType.PISTOL
	player.inventory.add_item(magazine, 1)
	await wait_physics_frames(1)
	watch_signals(gun)
	assert_not_null(gun.fire())
	assert_eq(gun.rounds, 1)
	assert_signal_emitted_with_parameters(gun, "ammo_changed", [1, 2])
	gun.fire_timer.stop()
	assert_not_null(gun.fire())
	assert_eq(gun.rounds, 0)
	gun.fire_timer.stop()
	assert_null(gun.fire(), "An empty magazine fires nothing and starts a reload")
	assert_true(gun.is_reloading)
	assert_false(gun.fire_timer.is_stopped(), "Reloading blocks the trigger")
	await wait_seconds(0.3)
	assert_false(gun.is_reloading)
	assert_eq(gun.rounds, 2, "The magazine refills from the inventory")
	assert_eq(player.inventory.count_of(magazine), 0, "The magazine item is spent")
	assert_eq(gun.reserve_rounds, 0)
	gun.reload()
	assert_false(gun.is_reloading, "A full magazine does not reload")
	player.controls.set_ammo(gun.rounds, gun.reserve_rounds)
	assert_eq(player.controls.ammo_label.text, "2 / 0")
	assert_true(player.controls.ammo_label.visible)
	player.controls.hide_ammo()
	assert_false(player.controls.ammo_label.visible)


func test_the_aim_point_sits_under_the_crosshair_with_the_shoulder_camera() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	var gun: Firearm = _gun(player)
	var camera: Camera3D = player.camera
	camera.h_offset = camera.aim_h_offset
	await wait_physics_frames(3)
	var centre: Vector2 = camera.get_viewport().get_visible_rect().size * 0.5
	var on_screen: Vector2 = camera.unproject_position(gun.get_aim_point())
	assert_almost_eq(on_screen, centre, Vector2.ONE, "The ray follows the camera's centre line, offset shoulder and all")


func test_rumble_only_reaches_a_pad() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await wait_physics_frames(1)
	var controls: Controls = player.controls
	controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	assert_false(controls.rumble(0.0, 0.8, 0.1), "Keyboard players get no rumble")
	controls.current_input_type = Controls.InputType.TOUCH
	assert_false(controls.rumble(0.0, 0.8, 0.1), "Touch players get no rumble")
	controls.current_input_type = Controls.InputType.MICROSOFT
	assert_true(controls.rumble(0.0, 0.8, 0.1), "A pad gets the kick")


func test_a_peers_copy_of_a_round_waits_for_the_spawners_despawn_instead_of_freeing_itself() -> void:
	# A spawner-owned round belongs to the server; a client's copy must not free on its own hit, or the server's
	# despawn arrives for a node the client no longer has (ERR_UNAUTHORIZED in on_despawn_receive).
	var target := _make_area_target(Vector3(0, 0, -6))
	var bullet: Projectile = BULLET_SCENE.instantiate()
	root.add_child(bullet)
	bullet.set_multiplayer_authority(2) # Somebody else's round
	bullet.launch(Transform3D(Basis.IDENTITY, Vector3.ZERO), Vector3.FORWARD, 300.0, null)
	await wait_physics_frames(4)
	assert_eq(target.hits, 1, "The copy still simulates the hit")
	assert_true(is_instance_valid(bullet) and bullet.is_inside_tree(), "but it stays for the spawner's despawn")
	assert_true(bullet.freeze, "stopped where it landed")
	assert_false(bullet.visible, "and out of sight")
	var mine := _shoot(Vector3.ZERO, Vector3.FORWARD, 300.0)
	await wait_physics_frames(4)
	assert_false(is_instance_valid(mine) and mine.is_inside_tree(), "A round this peer owns frees itself as before")
