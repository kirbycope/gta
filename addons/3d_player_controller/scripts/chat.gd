class_name ChatWindow
extends Window
## World of Warcraft style chat: a floating, movable and resizable embedded [Window] that starts bottom-left,
## fades when idle and remembers its rect in [PlayerSettingsResource].
##
## Messages travel by RPC through the Godot multiplayer API, so ENet and the SteamMultiplayerPeer both carry
## them. Every peer holds a copy of the sender's Player, and this node with it, so [method _receive_message]
## runs on that copy and relays to the one chat this peer owns. Lines starting with "/" are local commands
## and are never sent. The window stays [member Window.unfocusable] except while the input row is open, so a
## click or scroll on the history never takes the keyboard away from the game.

signal typing_changed(is_typing: bool) ## The input row opened (true) or closed (false); the Player gates gameplay input on it.

const DEFAULT_SIZE: Vector2i = Vector2i(420, 220)
const SCREEN_MARGIN: int = 16
const MAX_MESSAGE_LENGTH: int = 500 ## Longer messages from a peer are cut here.

@export var player: Player
@export var idle_seconds: float = 8.0 ## Seconds without a new message before the window fades.
@export var idle_alpha: float = 0.0 ## Alpha the window fades to when idle; it still catches the mouse.
@export var fade_seconds: float = 1.0 ## How long the fade out takes.
@export var fade_in_seconds: float = 0.2 ## How long coming back takes.
@export var name_color: Color = Color(1.0, 0.82, 0.3) ## Sender names in the history.
@export var system_color: Color = Color(0.75, 0.75, 0.75) ## Local command output in the history.

@onready var content: Control = $Content ## Everything visible; its modulate is what fades.
@onready var history: RichTextLabel = $Content/Frame/VBox/History
@onready var input_row: HBoxContainer = $Content/Frame/VBox/InputRow
@onready var input: LineEdit = $Content/Frame/VBox/InputRow/Input
@onready var idle_timer: Timer = $IdleTimer
@onready var save_timer: Timer = $SaveTimer

## Commands typed as "/name args": name -> [Callable(args: PackedStringArray), help line]. Adding one is one line.
@onready var commands: Dictionary[String, Array] = {
	"help": [_command_help, "/help: lists the commands"],
	"teleport": [_command_teleport, "/teleport x y z: moves you to that position"],
}

var settings_res: PlayerSettingsResource
var is_hovered: bool = false ## The mouse is over the window, which keeps it visible so the history can be scrolled.
var _fade_tween: Tween


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if player == null and get_parent() is Player:
		player = get_parent() as Player
	# A remote Player's copy only relays RPCs; it never shows
	if not is_multiplayer_authority():
		return
	idle_timer.wait_time = idle_seconds
	var settings: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	var rect: Rect2 = settings.chat_rect
	if rect.size == Vector2.ZERO:
		var screen: Vector2 = get_parent().get_viewport().get_visible_rect().size
		rect = Rect2(Vector2(SCREEN_MARGIN, screen.y - DEFAULT_SIZE.y - SCREEN_MARGIN), Vector2(DEFAULT_SIZE))
	size = Vector2i(rect.size)
	position = Vector2i(rect.position)
	show()
	idle_timer.start()
	settings_res = settings # Set last: applying the saved rect above must not arm a save of its own


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_POSITION_CHANGED:
		_on_rect_changed()


## Shows the input row and takes the keyboard; Enter or Send submits, Escape cancels.
func open_input() -> void:
	if not visible or input_row.visible:
		return
	unfocusable = false
	grab_focus()
	input_row.show()
	input.clear()
	input.grab_focus()
	idle_timer.stop()
	_fade_to(1.0, fade_in_seconds)
	typing_changed.emit(true)


## Hides the input row and hands the keyboard back to the game.
func close_input() -> void:
	if not input_row.visible:
		return
	input_row.hide()
	input.release_focus()
	unfocusable = true
	grab_focus() # An unfocusable window cannot take focus, so this releases the embedded focus instead
	idle_timer.start()
	typing_changed.emit(false)


## Sends [param text] to every peer, or runs it locally when it is a "/" command; empty text does nothing.
func send(text: String) -> void:
	var line: String = text.strip_edges()
	if line.is_empty():
		return
	if line.begins_with("/"):
		_run_command(line.substr(1))
		return
	_receive_message.rpc(get_display_name(), line)


## The Steam persona name while Steam is running, else "Player <peer id>".
func get_display_name() -> String:
	var steamworks: Node = get_node_or_null("/root/Steamworks")
	if steamworks and steamworks.get("steam_id") != 0:
		return str(steamworks.get("username"))
	return "Player %d" % multiplayer.get_unique_id()


## Lands on every peer's copy of the sender's Player; relays to the chat that peer owns.
@rpc("any_peer", "call_local", "reliable")
func _receive_message(sender: String, text: String) -> void:
	for node: Node in get_tree().get_nodes_in_group(&"ChatWindow"):
		var chat: ChatWindow = node as ChatWindow
		if chat and chat.multiplayer == multiplayer and chat.is_multiplayer_authority():
			chat.append_message(sender, text.left(MAX_MESSAGE_LENGTH))


## Appends "Name: text" with the name coloured; user text is escaped so it cannot inject bbcode.
func append_message(sender: String, text: String) -> void:
	_append_line("[color=%s]%s:[/color] %s" % [name_color.to_html(false), escape_bbcode(sender), escape_bbcode(text)])


## Appends a local line (command output) in the system colour.
func append_system(text: String) -> void:
	_append_line("[color=%s]%s[/color]" % [system_color.to_html(false), escape_bbcode(text)])


## Escapes "[" and "]" so user text renders literally in a [RichTextLabel].
static func escape_bbcode(text: String) -> String:
	var marker: String = char(1) # Never typed, so "[" can be swapped for "[lb]" after "]" has become "[rb]"
	return text.replace("[", marker).replace("]", "[rb]").replace(marker, "[lb]")


func _append_line(bbcode: String) -> void:
	if not history.get_parsed_text().is_empty():
		history.append_text("\n")
	history.append_text(bbcode)
	_fade_to(1.0, fade_in_seconds)
	idle_timer.start()


func _run_command(line: String) -> void:
	var parts: PackedStringArray = line.split(" ", false)
	var command_name: String = parts[0].to_lower() if parts.size() > 0 else ""
	if not commands.has(command_name):
		append_system("Unknown command: /%s, try /help" % command_name)
		return
	(commands[command_name][0] as Callable).call(parts.slice(1))


func _command_help(_args: PackedStringArray) -> void:
	for command_name: String in commands:
		append_system(commands[command_name][1])


func _command_teleport(args: PackedStringArray) -> void:
	if args.size() != 3 or not (args[0].is_valid_float() and args[1].is_valid_float() and args[2].is_valid_float()):
		append_system("Usage: /teleport x y z")
		return
	if not is_instance_valid(player):
		return
	var target: Transform3D = player.global_transform
	target.origin = Vector3(args[0].to_float(), args[1].to_float(), args[2].to_float())
	player.warp_to(target)
	append_system("Teleported to %s" % target.origin)


func _fade_to(alpha: float, seconds: float) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(content, "modulate:a", alpha, seconds)


func _on_idle_timer_timeout() -> void:
	if is_hovered or input_row.visible:
		return
	_fade_to(idle_alpha, fade_seconds)


func _on_mouse_entered() -> void:
	is_hovered = true
	idle_timer.stop()
	_fade_to(1.0, fade_in_seconds)


func _on_mouse_exited() -> void:
	is_hovered = false
	idle_timer.start()


func _on_input_text_submitted(text: String) -> void:
	send(text)
	close_input()


func _on_send_pressed() -> void:
	_on_input_text_submitted(input.text)


## Escape cancels; every other key is consumed by the [LineEdit] inside this focused window and never reaches the game.
func _on_input_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		input.accept_event()
		close_input()


## Dragging the title bar moves the window (the embedder handles the drag itself).
func _on_title_gui_input(event: InputEvent) -> void:
	if _is_left_press(event):
		start_drag()


## Dragging the bottom-right grip resizes the window.
func _on_grip_gui_input(event: InputEvent) -> void:
	if _is_left_press(event):
		start_resize(DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT)


static func _is_left_press(event: InputEvent) -> bool:
	var button: InputEventMouseButton = event as InputEventMouseButton
	return button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT


## Wired to size_changed and reached from the position notification; saves once the rect settles.
func _on_rect_changed() -> void:
	if settings_res and save_timer.is_inside_tree(): # The tree also resizes the window on the way out
		save_timer.start()


func _on_save_timer_timeout() -> void:
	settings_res.chat_rect = Rect2(Vector2(position), Vector2(size))
	settings_res.save()


## The embedded window draws above every CanvasLayer, so it hides while a menu is up to keep the menu clickable.
func _on_player_paused_changed(paused: bool) -> void:
	if not is_multiplayer_authority():
		return
	if paused:
		close_input()
	visible = not paused
