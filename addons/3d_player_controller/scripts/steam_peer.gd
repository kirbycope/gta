class_name SteamPeer
extends Node
## Turns the current Steam lobby into a high-level multiplayer session.
##
## The lobby owner hosts (peer id 1) and everyone else connects to the owner. Steam is reached only
## through the singleton and [code]/root/Steamworks[/code], so the node is inert on web exports and
## whenever no lobby is active. Call [method host] once a lobby has been created locally, or rely on
## [method _ready] when the world loads after joining a lobby.

signal network_ready(is_host: bool) ## Emitted once [member MultiplayerAPI.multiplayer_peer] is set.

@export var virtual_port: int = 0 ## Steam networking virtual port shared by host and clients.


func _ready() -> void:
	var lobby_id: int = _lobby_id()
	if lobby_id != 0 and not multiplayer.has_multiplayer_peer():
		connect_to_lobby(lobby_id)


## True when Steam is running and this build ships the Steam multiplayer peer.
func is_available() -> bool:
	return Engine.has_singleton("Steam") and ClassDB.class_exists(&"SteamMultiplayerPeer") \
			and get_node_or_null("/root/Steamworks") != null


## Hosts the session; the caller has already created the lobby.
func host() -> void:
	if not is_available() or multiplayer.has_multiplayer_peer():
		return
	var peer: MultiplayerPeer = ClassDB.instantiate(&"SteamMultiplayerPeer")
	peer.call("create_host", virtual_port)
	multiplayer.multiplayer_peer = peer
	network_ready.emit(true)


## Hosts when we own [param lobby_id], otherwise connects to its owner.
func connect_to_lobby(lobby_id: int) -> void:
	if not is_available() or multiplayer.has_multiplayer_peer():
		return
	var steam: Object = Engine.get_singleton("Steam")
	var owner_id: int = steam.call("getLobbyOwner", lobby_id)
	if owner_id == int(get_node("/root/Steamworks").get("steam_id")):
		host()
		return
	var peer: MultiplayerPeer = ClassDB.instantiate(&"SteamMultiplayerPeer")
	peer.call("create_client", owner_id, virtual_port)
	multiplayer.multiplayer_peer = peer
	network_ready.emit(false)


func _lobby_id() -> int:
	var steamworks: Node = get_node_or_null("/root/Steamworks")
	return int(steamworks.get("lobby_id")) if steamworks else 0
