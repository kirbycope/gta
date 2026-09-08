extends PlayerMenuLayer

@export var lobby_player_item_scene: PackedScene ## Assigned in the scene so it ships as a scene dependency.

## Steam singleton when the GodotSteam extension is present, otherwise null.
var _steam: Object = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null

@onready var panel: Panel = $Panel
@onready var info_label: Label = $Panel/VBoxContainer/InfoLabel
@onready var player_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/PlayerList
@onready var invite_button: Button = $Panel/VBoxContainer/HBoxContainer/Invite
@onready var leave_button: Button = $Panel/VBoxContainer/HBoxContainer/Leave
@onready var back_button: Button = $Panel/VBoxContainer/BACK


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	if _steam == null:
		return
	_steam.connect("lobby_chat_update", _on_lobby_chat_update)
	_steam.connect("lobby_data_update", _on_lobby_data_update)
	_steam.connect("lobby_message", _on_lobby_message)


func show_menu() -> void:
	_update_lobby_ui()
	focus_on_show = back_button if invite_button.disabled else invite_button
	super()


## The lobby the Steamworks autoload has joined, or 0 when there is none.
func _active_lobby_id() -> int:
	var steamworks: Node = get_node_or_null("/root/Steamworks")
	return int(steamworks.get("lobby_id")) if steamworks else 0


func _update_lobby_ui() -> void:
	for child: Node in player_list.get_children():
		child.queue_free()

	var active_lobby_id: int = _active_lobby_id()
	var has_lobby: bool = _steam != null and _steam.isSteamRunning() and active_lobby_id > 0
	invite_button.disabled = not has_lobby
	leave_button.disabled = not has_lobby
	if _steam == null or not _steam.isSteamRunning():
		info_label.text = "Steam unavailable"
		return
	if not has_lobby:
		info_label.text = "No active lobby"
		return

	var owner_id: int = _steam.getLobbyOwner(active_lobby_id)
	var member_count: int = _steam.getNumLobbyMembers(active_lobby_id)
	var max_members: int = _steam.getLobbyMemberLimit(active_lobby_id)
	info_label.text = "Host: %s (%d/%d)" % [_steam.getFriendPersonaName(owner_id), member_count, max_members if max_members > 0 else 4]

	if lobby_player_item_scene == null:
		return
	for i: int in range(member_count):
		var item: LobbyPlayerItem = lobby_player_item_scene.instantiate() as LobbyPlayerItem
		player_list.add_child(item)
		item.lobby_id = active_lobby_id
		item.steam_id = _steam.getLobbyMemberByIndex(active_lobby_id, i)
		item.player_promoted.connect(_on_player_promoted)


func _on_player_promoted(_steam_id: int) -> void:
	_update_lobby_ui()


#region Steam Callbacks
func _on_lobby_chat_update(lobby_id: int, _changed_id: int, _making_change_id: int, _chat_state: int) -> void:
	if _active_lobby_id() == lobby_id and visible:
		_update_lobby_ui()


func _on_lobby_data_update(_success: int, lobby_id: int, _member_id: int) -> void:
	if _active_lobby_id() == lobby_id and visible:
		_update_lobby_ui()


## Leaves the lobby when the owner sends "/kick <our steam id>".
func _on_lobby_message(lobby_id: int, sender: int, message: String, _chat_type: int) -> void:
	if lobby_id != _active_lobby_id() or not message.begins_with("/kick ") or sender != _steam.getLobbyOwner(lobby_id):
		return
	if int(message.get_slice(" ", 1)) == _steam.getSteamID():
		_on_leave_pressed()
#endregion


func _on_invite_pressed() -> void:
	var active_lobby_id: int = _active_lobby_id()
	if _steam != null and active_lobby_id > 0:
		_steam.activateGameOverlayInviteDialog(active_lobby_id)


func _on_invite_touch_screen_button_pressed() -> void:
	_on_invite_pressed()


func _on_leave_pressed() -> void:
	var active_lobby_id: int = _active_lobby_id()
	if _steam == null or active_lobby_id <= 0:
		return
	_steam.leaveLobby(active_lobby_id)
	get_node("/root/Steamworks").set("lobby_id", 0)
	_update_lobby_ui()


func _on_leave_touch_screen_button_pressed() -> void:
	_on_leave_pressed()


## Return to the pause menu.
func _on_back_pressed() -> void:
	if player == null:
		return
	hide()
	player.pause.show_menu()


func _on_back_touch_screen_button_pressed() -> void:
	_on_back_pressed()
