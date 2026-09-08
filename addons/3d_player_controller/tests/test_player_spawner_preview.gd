extends GutTest
## The PlayerSpawner's editor preview: the Player's model alone, and nothing of it in the game.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")


func test_the_preview_is_the_player_model_without_the_player() -> void:
	var spawner: PlayerSpawner = PlayerSpawner.new()
	spawner.player_scene = PLAYER_SCENE
	autofree(spawner)
	var preview: Node3D = spawner.make_preview()
	assert_not_null(preview)
	assert_eq(preview.name, "PlayerPreview")
	assert_false(preview is Player, "Only the model, not a second Player")
	assert_gt(preview.find_children("*", "MeshInstance3D", true, false).size(), 0, "It carries the mesh")
	assert_eq(preview.find_children("*", "Camera3D", true, false).size(), 0, "No camera")
	assert_eq(preview.find_children("*", "CanvasLayer", true, false).size(), 0, "No HUD")
	assert_eq(preview.find_children("*", "CollisionShape3D", false, false).size(), 0, "No body collision")
	preview.free()


func test_nothing_is_added_outside_the_editor() -> void:
	var container: Node3D = Node3D.new()
	container.name = "Players"
	add_child_autofree(container)
	var spawner: PlayerSpawner = PlayerSpawner.new()
	spawner.spawn_path = NodePath("../Players")
	spawner.player_scene = PLAYER_SCENE
	add_child_autofree(spawner)
	spawner.refresh_preview()
	var children: Array[Node] = container.get_children(true)
	assert_eq(children.filter(func(node: Node) -> bool: return node.name == "PlayerPreview").size(), 0, "The preview is editor only")
