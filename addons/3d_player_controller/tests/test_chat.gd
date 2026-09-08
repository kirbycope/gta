extends IntegrationTestBase

## Purpose: the chat window opens on the "chat" action, submits or cancels back to the game, runs "/" commands
## locally, fades when idle and comes back on hover, remembers its rect in PlayerSettingsResource, and blocks
## gameplay input while typing. Settings are backed up so the developer's user://settings.tres is left alone.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const CHAT_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/chat.tscn")


## Sits in the main viewport and records the action presses that reach it; none should while the chat has the keyboard.
class InputProbe:
	extends Node
	var action_presses: int = 0
	func _input(event: InputEvent) -> void:
		if event.is_action_pressed("action"):
			action_presses += 1


var _backup: PackedByteArray
var _had_file: bool
var root: Node3D
var player: Player
var chat: ChatWindow


func before_each() -> void:
	_had_file = FileAccess.file_exists(PlayerSettingsResource.SAVE_PATH)
	if _had_file:
		_backup = FileAccess.get_file_as_bytes(PlayerSettingsResource.SAVE_PATH)
	PlayerSettingsResource._cached = PlayerSettingsResource.new() # Defaults, whatever is on disk
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	player = PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	chat = player.chat
	await wait_physics_frames(3)


func after_each() -> void:
	if is_instance_valid(root):
		root.free()
	if _had_file:
		var file: FileAccess = FileAccess.open(PlayerSettingsResource.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(_backup)
		file.close()
		ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_REPLACE)
	else:
		DirAccess.remove_absolute(PlayerSettingsResource.SAVE_PATH)
	PlayerSettingsResource._cached = null


func _submit(text: String) -> void:
	chat.input.text = text
	chat.input.text_submitted.emit(text)


func _push_key_to_chat(keycode: Key) -> void:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = keycode
	key.physical_keycode = keycode
	key.pressed = true
	chat.push_input(key)


## Types a key the way the OS delivers it, unicode included, through Input so the root window routes it.
func _type_key(keycode: Key, unicode: int) -> void:
	var down: InputEventKey = InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.unicode = unicode
	down.pressed = true
	var up: InputEventKey = down.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await wait_physics_frames(1)
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await wait_physics_frames(1)


func test_chat_is_an_embedded_window_that_starts_bottom_left() -> void:
	assert_true(get_viewport().gui_embed_subwindows, "The root viewport embeds subwindows, so the chat floats inside the game window")
	assert_true(chat.is_embedded(), "The chat is an embedded Window")
	assert_true(chat.visible, "The local Player's chat shows on ready")
	assert_true(chat.unfocusable, "Until the input opens the window never takes the keyboard from the game")
	assert_false(chat.input_row.visible, "The input row is hidden until the chat is opened")
	assert_eq(chat.size, ChatWindow.DEFAULT_SIZE, "Default size")
	var screen: Vector2 = get_viewport().get_visible_rect().size
	assert_eq(chat.position, Vector2i(ChatWindow.SCREEN_MARGIN, int(screen.y) - ChatWindow.DEFAULT_SIZE.y - ChatWindow.SCREEN_MARGIN), "Anchored bottom-left on first show")
	assert_true(chat.is_in_group(&"ChatWindow"), "Grouped so a received RPC can find the chat this peer owns")


func test_chat_action_opens_the_input_and_a_submit_appends_and_closes() -> void:
	await perform_action("chat")
	assert_true(chat.input_row.visible, "Enter opens the input row")
	assert_true(player.is_typing, "The Player is typing while the input row is open")
	assert_true(chat.has_focus(), "The window took the embedded focus so keys go to the field")
	assert_true(chat.input.has_focus(), "The field has the caret")

	_submit("hello there")
	assert_false(chat.input_row.visible, "Submitting hides the input row")
	assert_false(player.is_typing, "And the Player is no longer typing")
	assert_false(chat.has_focus(), "The embedded focus went back to the game")
	assert_true(chat.unfocusable, "The window is unfocusable again")
	assert_string_contains(chat.history.get_parsed_text(), chat.get_display_name() + ": hello there", "The message shows with the sender's name (Steam persona, else the peer id)")
	assert_eq(chat.get_display_name(), Steamworks.username if Steamworks.steam_id != 0 else "Player 1", "The name is the Steam persona while Steam runs, else Player <peer id>")


func test_escape_cancels_and_an_empty_submit_just_closes() -> void:
	await perform_action("chat")
	chat.input.text = "never sent"
	_push_key_to_chat(KEY_ESCAPE)
	assert_false(chat.input_row.visible, "Escape closes the input row")
	assert_false(player.is_typing, "Escape hands input back to the game")
	assert_eq(chat.history.get_parsed_text(), "", "Nothing was sent")

	await perform_action("chat")
	_submit("   ")
	assert_false(chat.input_row.visible, "An empty submit closes the row")
	assert_eq(chat.history.get_parsed_text(), "", "And sends nothing")


func test_user_text_cannot_inject_bbcode() -> void:
	chat.send("[color=red]x[/color]")
	assert_string_contains(chat.history.get_parsed_text(), "[color=red]x[/color]", "Brackets render literally")


func test_help_and_unknown_commands_print_locally_and_are_not_sent() -> void:
	chat.send("/help")
	var text: String = chat.history.get_parsed_text()
	assert_string_contains(text, "/help: lists the commands", "help lists itself")
	assert_string_contains(text, "/teleport x y z", "and teleport")
	chat.send("/nope 1 2")
	assert_string_contains(chat.history.get_parsed_text(), "Unknown command: /nope, try /help", "Unknown commands say so")
	assert_false(chat.history.get_parsed_text().contains(chat.get_display_name() + ":"), "Commands never go out as messages (call_local would have echoed one)")


func test_teleport_moves_the_player_and_validates_its_arguments() -> void:
	var before: Vector3 = player.global_position
	chat.send("/teleport 1 x 3")
	assert_string_contains(chat.history.get_parsed_text(), "Usage: /teleport x y z", "Bad floats print the usage")
	assert_eq(player.global_position, before, "and do not move the Player")
	chat.send("/teleport 10 2 -5")
	assert_almost_eq(player.global_position, Vector3(10.0, 2.0, -5.0), Vector3.ONE * 0.001, "Valid floats warp the Player there")
	assert_eq(player.velocity, Vector3.ZERO, "warp_to clears motion")


func test_idle_fade_lowers_alpha_and_hover_restores_it() -> void:
	chat.fade_seconds = 0.05
	chat.fade_in_seconds = 0.05
	assert_true(chat.idle_timer.time_left > 0.0, "The idle timer runs from the start")
	chat.idle_timer.start(0.05)
	await wait_seconds(0.4)
	assert_almost_eq(chat.content.modulate.a, chat.idle_alpha, 0.01, "Idle fades the content to idle_alpha")
	assert_true(chat.visible, "The window itself stays visible to catch the hover")

	chat.mouse_entered.emit()
	await wait_seconds(0.3)
	assert_almost_eq(chat.content.modulate.a, 1.0, 0.01, "Hover brings it back")
	assert_true(chat.idle_timer.is_stopped(), "and holds it while hovered")
	chat._on_idle_timer_timeout()
	await wait_seconds(0.3)
	assert_almost_eq(chat.content.modulate.a, 1.0, 0.01, "A timeout while hovered does not fade")

	chat.mouse_exited.emit()
	assert_false(chat.idle_timer.is_stopped(), "Leaving restarts the idle timer")


func test_an_open_input_row_keeps_the_window_visible() -> void:
	chat.fade_seconds = 0.05
	await perform_action("chat")
	assert_true(chat.idle_timer.is_stopped(), "Opening the input stops the idle timer")
	chat._on_idle_timer_timeout()
	await wait_seconds(0.2)
	assert_almost_eq(chat.content.modulate.a, 1.0, 0.01, "No fade while typing")
	_submit("")
	assert_false(chat.idle_timer.is_stopped(), "Closing restarts it")


func test_rect_persists_through_player_settings_resource() -> void:
	chat.size = Vector2i(300, 150)
	chat.position = Vector2i(40, 50)
	chat.notification(NOTIFICATION_WM_POSITION_CHANGED) # What the embedder sends after a drag
	assert_false(chat.save_timer.is_stopped(), "A rect change arms the save timer")
	chat.save_timer.timeout.emit()
	assert_eq(PlayerSettingsResource.load_or_create().chat_rect, Rect2(40.0, 50.0, 300.0, 150.0), "The shared settings hold the rect")
	var loaded: PlayerSettingsResource = ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(loaded.chat_rect, Rect2(40.0, 50.0, 300.0, 150.0), "and it reached disk")

	var restored: ChatWindow = CHAT_SCENE.instantiate() as ChatWindow
	root.add_child(restored)
	assert_eq(restored.position, Vector2i(40, 50), "A new chat opens where the last one was left")
	assert_eq(restored.size, Vector2i(300, 150), "at the same size")
	assert_true(restored.save_timer.is_stopped(), "Applying the saved rect does not save it again")


func test_typing_blocks_jump_and_action() -> void:
	var probe: InputProbe = InputProbe.new()
	root.add_child(probe)
	await perform_action("chat")
	assert_true(player.is_typing, "Typing")

	await _type_key(KEY_SPACE, 32)
	await wait_physics_frames(2)
	assert_eq(chat.input.text, " ", "Space went into the field")
	assert_ne(player.current_state, NodeStateMachine.States.JUMPING, "and did not make the Player jump")
	assert_false(player.is_jumping, "is_jumping stays false")

	await _type_key(KEY_E, 101)
	assert_eq(chat.input.text, " e", "E went into the field")
	assert_eq(probe.action_presses, 0, "The action never reached the game's viewport")

	_push_key_to_chat(KEY_ESCAPE)
	assert_false(player.is_typing, "Escape closed the chat")
	await _type_key(KEY_SPACE, 32)
	await wait_physics_frames(2)
	assert_true(player.is_jumping or player.current_state == NodeStateMachine.States.JUMPING, "With the chat closed Space jumps again")


func test_a_remote_players_copy_keeps_its_chat_hidden() -> void:
	var remote: Player = PLAYER_SCENE.instantiate() as Player
	remote.name = "2" # Owned by peer 2, so not this peer's
	root.add_child(remote)
	await wait_physics_frames(1)
	assert_false(remote.is_multiplayer_authority(), "The copy belongs to another peer")
	assert_false(remote.chat.visible, "so its chat never shows here")
	assert_true(remote.chat.is_in_group(&"ChatWindow"), "but it still exists to relay RPCs")


func test_chat_hides_while_paused_so_menus_stay_clickable_and_ignores_the_action() -> void:
	player.is_paused = true
	assert_false(chat.visible, "The embedded window draws above CanvasLayers, so it hides behind a menu")
	await perform_action("chat")
	assert_false(chat.input_row.visible, "The chat action is ignored while paused")
	assert_false(player.is_typing, "and nobody is typing")
	player.is_paused = false
	assert_true(chat.visible, "Unpausing shows it again")
