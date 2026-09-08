@tool
class_name ActionPrompt
extends Node3D
## World-space "Press [button] to ..." prompt with one child per input type (KeyboardMouse, Microsoft, Nintendo, Sony).

var _message_begin: String = "Press"
var _message_end: String = "to interact"

@export var message_begin: String = "Press":
	set(value):
		_message_begin = value
		update_text()
	get:
		return _message_begin

@export var message_end: String = "to interact":
	set(value):
		_message_end = value
		update_text()
	get:
		return _message_end

@onready var label_3d_1: Label3D = $KeyboardMouse/Label3D
@onready var label_3d_2: Label3D = $Microsoft/Label3D
@onready var label_3d_3: Label3D = $Nintendo/Label3D
@onready var label_3d_4: Label3D = $Sony/Label3D

@onready var label_3d_2_1: Label3D = $KeyboardMouse/Label3D2
@onready var label_3d_2_2: Label3D = $Microsoft/Label3D2
@onready var label_3d_2_3: Label3D = $Nintendo/Label3D2
@onready var label_3d_2_4: Label3D = $Sony/Label3D2


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if not Engine.is_editor_hint():
		hide()
	update_text()


## Shows only the sub-prompt matching the player's current input type (child names mirror `Controls.InputType` keys in PascalCase).
## [param action_label] names the Action button on the player's controls while the prompt is up ("Get In").
func show_for(player: Player, action_label: String = "") -> void:
	var type_name: String = String(player.controls.InputType.keys()[player.controls.current_input_type]).to_pascal_case()
	for child: Node3D in get_children():
		child.visible = child.name == type_name
	if action_label != "" and player.controls.joypad_button_0_label:
		player.controls.joypad_button_0_label.text = action_label
	show()


## Hides the prompt and gives the player's state its Action label back.
func hide_for(player: Player) -> void:
	hide()
	if is_instance_valid(player):
		player.refresh_contextual_controls()


## Hides the prompt and every sub-prompt.
func hide_all() -> void:
	for child: Node3D in get_children():
		child.hide()
	hide()


func update_text() -> void:
	if not is_node_ready():
		return

	label_3d_1.text = message_begin
	label_3d_2.text = message_begin
	label_3d_3.text = message_begin
	label_3d_4.text = message_begin
	label_3d_2_1.text = message_end
	label_3d_2_2.text = message_end
	label_3d_2_3.text = message_end
	label_3d_2_4.text = message_end
