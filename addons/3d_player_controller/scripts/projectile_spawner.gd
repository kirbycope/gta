class_name ProjectileSpawner
extends MultiplayerSpawner
## Spawns projectiles on every peer from one launch description, and lands what they leave behind.
##
## [method fire] runs on the server (or offline) directly and asks the server over RPC otherwise; the
## server spawns through [member MultiplayerSpawner.spawn_function] with the same data on all peers,
## so each peer simulates an identical round and resolves its hits locally. Only the round's authority
## (the server's copy) decides what a hit leaves in the world: [method place] spawns a scene at a point on
## every peer (an ice block), [method ignite] lights the grass on every peer. Add the node to the
## [code]ProjectileSpawner[/code] group so weapons can find it; without one, weapons fire locally.


func _ready() -> void:
	spawn_function = _spawn_scene


## The spawner of [param node]'s multiplayer session (the one sharing its [member Node.multiplayer]), found
## through the ProjectileSpawner group; null without one, and things then happen locally.
static func find_for(node: Node) -> ProjectileSpawner:
	if node == null or not node.is_inside_tree():
		return null
	for candidate: Node in node.get_tree().get_nodes_in_group(&"ProjectileSpawner"):
		if candidate is ProjectileSpawner and candidate.multiplayer == node.multiplayer:
			return candidate
	return null


## Launches [param scene] from [param origin] along [param direction]; returns the local copy on the
## server and null on clients (their copy arrives through the spawner). [param extra] rides along in the launch
## data for scenes that read more than a [Projectile] does (a [ThrownItem] reads which item it is).
func fire(scene: PackedScene, origin: Transform3D, direction: Vector3, speed: float, shooter: Node3D, weapon: Node = null, extra: Dictionary = {}) -> Node:
	var data: Dictionary = {
		"scene": scene.resource_path,
		"origin": origin,
		"direction": direction,
		"speed": speed,
		"shooter": String(shooter.get_path()) if shooter else "",
		"weapon": String(weapon.get_path()) if weapon else "",
	}
	data.merge(extra)
	return _spawn_everywhere(data)


## Puts [param scene] down at world [param position] on every peer (an ice block where an arrow landed); returns the
## local copy on the server and null on clients. [param extra] may carry "properties" (name to value, set on the
## node) and "resources" (name to resource path, loaded and set), so a placed [ItemPickup] knows its item.
func place(scene: PackedScene, position: Vector3, extra: Dictionary = {}) -> Node3D:
	var data: Dictionary = {"scene": scene.resource_path, "position": position}
	data.merge(extra)
	return _spawn_everywhere(data) as Node3D


## Lights the grass around [param position] on every peer, as a fire spell's impact does. Rounds belong to the
## server, so only the server's call does anything; the peers receive.
func ignite(position: Vector3, radius: float, duration: float) -> void:
	if multiplayer.is_server():
		_ignite.rpc(position, radius, duration)


func _spawn_everywhere(data: Dictionary) -> Node:
	if multiplayer.is_server():
		return spawn(data)
	_request_spawn.rpc_id(1, data)
	return null


@rpc("any_peer", "call_remote", "reliable")
func _request_spawn(data: Dictionary) -> void:
	if multiplayer.is_server():
		spawn(data)


@rpc("authority", "call_local", "reliable")
func _ignite(position: Vector3, radius: float, duration: float) -> void:
	Ability.ignite_grass(get_tree(), position, radius, duration)


## Runs on every peer: builds the scene. A projectile (or anything else with a [code]pending_launch[/code], a
## [ThrownItem]) launches itself once it enters the tree; anything else is put down at the data's position,
## relative to the spawn path's node, with the data's "properties" and "resources" set on it.
func _spawn_scene(data: Dictionary) -> Node:
	var node: Node = (load(data["scene"]) as PackedScene).instantiate()
	if "pending_launch" in node:
		node.set("pending_launch", data)
	elif node is Node3D and data.has("position"):
		var parent: Node3D = get_node_or_null(spawn_path) as Node3D
		(node as Node3D).position = parent.to_local(data["position"]) if parent else data["position"]
	var properties: Dictionary = data.get("properties", {})
	for property: String in properties:
		node.set(property, properties[property])
	var resources: Dictionary = data.get("resources", {})
	for property: String in resources:
		node.set(property, load(resources[property]))
	return node
