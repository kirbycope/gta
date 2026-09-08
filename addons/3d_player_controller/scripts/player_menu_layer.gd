class_name PlayerMenuLayer
extends CanvasLayer
## Base for the pause, settings and lobby menus: pauses the [Player] while shown and closes on the "start" action.

@export var player: Player
@export var focus_on_show: Control ## Control that receives focus when the menu opens.


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_process_input(is_multiplayer_authority())
	fit_touch_buttons(self)


## Sizes every [TouchScreenButton] under [param root] to the [Control] it sits on, now and whenever that control is
## laid out again, so a button a container stretches keeps a touch target to match.
static func fit_touch_buttons(root: Node) -> void:
	for found: Node in root.find_children("*", "TouchScreenButton", true, false):
		var touch: TouchScreenButton = found as TouchScreenButton
		var host: Control = touch.get_parent() as Control
		if host == null or not (touch.shape is RectangleShape2D):
			continue
		touch.shape = touch.shape.duplicate() # A scene shares one shape between its buttons
		_fit_touch_button(touch, host)
		host.resized.connect(_fit_touch_button.bind(touch, host))


static func _fit_touch_button(touch: TouchScreenButton, host: Control) -> void:
	(touch.shape as RectangleShape2D).size = host.size
	touch.position = host.size * 0.5


## Called when there is an input event.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("start") and visible:
		hide_menu()
		get_viewport().set_input_as_handled()


func show_menu() -> void:
	show()
	if player:
		player.is_paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if focus_on_show:
		focus_on_show.grab_focus()


func hide_menu() -> void:
	hide()
	if player:
		player.is_paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
