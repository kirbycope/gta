extends GutTest

## Purpose: the billboard kart picks the frame the game would. Mario Kart 64 has
## no kart models, only half rings of pre-rendered frames in nine pitch poses,
## picked by the angle the camera sees the kart from and mirrored for the other
## side, and this is the rule that does the picking, from func_8002934C and
## func_80029200 in the decompilation. The frames themselves come out of a ROM
## and are not here, so the tests use blank textures and check the arithmetic.

var sprite: MkSpriteKart


func before_each() -> void:
	sprite = MkSpriteKart.new()
	add_child_autofree(sprite)


func _blank(count: int) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for i: int in count:
		var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
		out.append(ImageTexture.create_from_image(image))
	return out


func test_the_ring_is_fine_near_the_rear_and_coarse_toward_the_front() -> void:
	# twenty frames 2.856 degrees apart out to 56.95 degrees, then nine degrees apart to head on
	assert_eq(sprite.frame_for_angle(0.0), {"index": 0, "flipped": false}, "Straight behind")
	assert_eq(sprite.frame_for_angle(2.9)["index"], 1)
	assert_eq(sprite.frame_for_angle(56.0)["index"], 19, "The last fine frame")
	assert_eq(sprite.frame_for_angle(57.0)["index"], 21, "Frame 20 is never chosen; the coarse run starts at 21")
	assert_eq(sprite.frame_for_angle(90.0)["index"], 25)
	assert_eq(sprite.frame_for_angle(180.0)["index"], 34, "Head on is the last frame")


func test_the_right_side_is_the_left_side_mirrored() -> void:
	# the game stored the camera on the kart's left; past 180.7 degrees it flips the frame
	assert_eq(sprite.frame_for_angle(270.0), {"index": 25, "flipped": true})
	assert_eq(sprite.frame_for_angle(357.0), {"index": 1, "flipped": true})
	assert_eq(sprite.frame_for_angle(180.5)["flipped"], false, "Just short of the fold")


func test_a_spin_out_uses_the_nine_degree_ring_and_flashes_the_rear_frame_head_on() -> void:
	assert_eq(sprite.frame_for_angle(0.0, true)["index"], 0)
	assert_eq(sprite.frame_for_angle(90.0, true)["index"], 10)
	assert_eq(sprite.frame_for_angle(179.0, true)["index"], 19)
	assert_eq(sprite.frame_for_angle(180.0, true)["index"], 0, "Twenty folds to the rear frame, as the game's table does")


func test_the_pose_is_the_slope_under_the_kart() -> void:
	sprite.level = _blank(35)
	sprite.nose_up_10 = _blank(35)
	sprite.nose_down_2 = _blank(35)
	sprite.nose_down_7 = _blank(35)
	assert_eq(sprite._frames_for_pitch(0.0), sprite.level)
	assert_eq(sprite._frames_for_pitch(1.9), sprite.level, "Within two degrees is level")
	assert_eq(sprite._frames_for_pitch(2.5), sprite.nose_down_2)
	assert_eq(sprite._frames_for_pitch(8.0), sprite.nose_down_7)
	assert_eq(sprite._frames_for_pitch(-12.0), sprite.nose_up_10)
	assert_eq(sprite._frames_for_pitch(-5.0), sprite.level, "A pose with no frames stands in as level")


func test_the_view_angle_counts_the_kart_s_slide_and_defaults_to_behind() -> void:
	var kart: MkCar = (load("res://addons/gta/mk/scenes/mk_kart.tscn") as PackedScene).instantiate() as MkCar
	(kart.get_node(^"MkAi") as MkAi).enabled = false
	add_child_autofree(kart)
	sprite.get_parent().remove_child(sprite)
	kart.add_child(sprite)
	kart.turn_angle = 0.0
	assert_almost_eq(sprite.view_angle_degrees(null), 0.0, 0.001, "No camera: seen from behind")
	kart.turn_angle = deg_to_rad(20.0)
	assert_almost_eq(sprite.view_angle_degrees(null), 20.0, 0.001, "A slide to the right turns the drawn kart that far")
	# a camera straight behind the kart, then off its left
	var camera: Camera3D = Camera3D.new()
	add_child_autofree(camera)
	kart.turn_angle = 0.0
	kart.yaw = 0.0
	kart.global_position = Vector3.ZERO
	camera.global_position = -kart.forward() * 5.0
	assert_almost_eq(sprite.view_angle_degrees(camera), 0.0, 0.5)
	camera.global_position = Vector3.UP.cross(kart.forward()) * 5.0
	assert_almost_eq(sprite.view_angle_degrees(camera), 90.0, 0.5, "The kart's left is the stored half")


func test_without_frames_it_draws_nothing_and_says_so_once() -> void:
	sprite._process(0.016)
	sprite._process(0.016)
	assert_null(sprite.texture)
	assert_true(sprite._said_empty)
