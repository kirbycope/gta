@tool
class_name PlayerSpawner
extends MultiplayerSpawner
## Spawns one [member player_scene] per peer under [member MultiplayerSpawner.spawn_path], named by peer id.
##
## The server (also the case offline, where the local id is 1) spawns itself on ready and every peer
## that connects; the scene replicates to clients through the spawner. [Player] reads its authority from
## its node name in [code]_enter_tree[/code], so each copy runs input only on the peer that owns it.
##
## In the editor it shows the Player's model where they will spawn (an internal child of the spawn point
## or container, never saved and never present in the game), so a map can be built around them.

signal local_player_spawned(player: Player) ## The player this peer controls has entered the tree.

@export var player_scene: PackedScene: ## Must be the Player scene (or one inheriting it).
	set(value):
		player_scene = value
		refresh_preview()
@export var spawn_point: Node3D: ## Optional; players appear here instead of at the container origin.
	set(value):
		spawn_point = value
		refresh_preview()

var _preview: Node3D


func _ready() -> void:
	if Engine.is_editor_hint():
		refresh_preview()
		return
	if player_scene:
		add_spawnable_scene(player_scene.resource_path)
	spawned.connect(_on_spawned)
	multiplayer.peer_connected.connect(spawn_player)
	multiplayer.peer_disconnected.connect(despawn_player)
	if multiplayer.is_server():
		spawn_player(multiplayer.get_unique_id())


## Server only: adds the player node for [param peer_id]; the spawner replicates it.
func spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server() or player_scene == null:
		return
	var container: Node = get_node(spawn_path)
	if container.has_node(str(peer_id)):
		return
	var player: Player = player_scene.instantiate()
	player.name = str(peer_id)
	if spawn_point:
		player.position = spawn_point.global_position
	container.add_child(player)
	_on_spawned(player)


func despawn_player(peer_id: int) -> void:
	var player: Node = get_node(spawn_path).get_node_or_null(str(peer_id))
	if player:
		player.queue_free()


## The player controlled by this peer, or null before it spawns.
func get_local_player() -> Player:
	return get_node(spawn_path).get_node_or_null(str(multiplayer.get_unique_id())) as Player


func _on_spawned(node: Node) -> void:
	if node is Player and node.is_multiplayer_authority():
		local_player_spawned.emit(node)


## Editor only: rebuilds the model shown at the spawn point.
func refresh_preview() -> void:
	if is_instance_valid(_preview):
		_preview.get_parent().remove_child(_preview)
		_preview.free()
	_preview = null
	if not Engine.is_editor_hint() or not is_inside_tree() or player_scene == null:
		return
	var parent: Node = spawn_point if spawn_point else get_node_or_null(spawn_path)
	if parent == null:
		return
	_preview = make_preview()
	if _preview:
		parent.add_child(_preview, false, Node.INTERNAL_MODE_FRONT)


## The Player's visual model on its own (no script, camera, HUD or physics) for the editor preview;
## null when [member player_scene] has no PlayerModel child.
func make_preview() -> Node3D:
	var player: Node = player_scene.instantiate()
	var model: Node3D = player.get_node_or_null("PlayerModel") as Node3D
	if model:
		player.remove_child(model)
		model.name = "PlayerPreview"
	player.free()
	return model
