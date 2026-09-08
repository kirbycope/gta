extends GutTest

## Purpose: Physical bones must not collide until the ragdoll simulation starts; the scene sets this, not a deferred lambda.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")


func test_physical_bones_start_with_collision_disabled() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var bones: Array[Node] = player.physical_bone_simulator.find_children("*", "PhysicalBone3D", true, false)
	assert_gt(bones.size(), 0, "Player should have physical bones")
	for bone: PhysicalBone3D in bones:
		assert_eq(bone.collision_layer, 0, "%s layer" % bone.name)
		assert_eq(bone.collision_mask, 0, "%s mask" % bone.name)
