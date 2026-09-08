@icon("res://addons/garp/assets/icons/materials.svg")
class_name ItemPickup
extends Node3D
## An [Item] lying in the world, Zelda style: walk up and the [ActionPrompt] appears with the Action button read
## as "Pick Up"; Action puts [member count] of [member item] in the Player's [Inventory] and the pickup is gone.
## Without a mesh child of your own the item's icon floats over the spot.

signal picked_up(player: Player, count: int) ## Emitted with how many the Player took.

@export var item: Item:
	set(value):
		item = value
		_refresh()
@export_range(1, 999) var count: int = 1
@export var show_icon: bool = true ## Float the item's icon as a billboard; turn off when the pickup has its own mesh.

var player: Player ## The Player in range, shown the prompt.

@onready var player_detection: Area3D = $PlayerDetection
@onready var action_prompt: ActionPrompt = $ActionPrompt
@onready var icon: Sprite3D = $Icon


func _ready() -> void:
	_refresh()


func _input(event: InputEvent) -> void:
	if player == null or item == null or player.is_paused or not event.is_action_pressed("action"):
		return
	take()
	get_viewport().set_input_as_handled()


## Puts what fits in the Player's inventory; the pickup frees itself once it is empty.
func take() -> void:
	if player == null or item == null:
		return
	var left: int = player.inventory.add_item(item, count)
	var taken: int = count - left
	if taken <= 0:
		return
	count = left
	picked_up.emit(player, taken)
	if count == 0:
		action_prompt.hide_for(player)
		player = null
		queue_free()


## Wired to PlayerDetection.body_entered: the Player who walked up gets the prompt, with the Action button read as
## "Pick Up" (the scene sets the prompt's message_end; the prompt's own ready put it on the labels).
func _on_player_detection_body_entered(body: Node3D) -> void:
	if body is Player and body.is_multiplayer_authority() and not (body as Player).is_riding:
		player = body
		action_prompt.show_for(player, "Pick Up")


## Wired to PlayerDetection.body_exited: walking away takes the prompt and the label with it.
func _on_player_detection_body_exited(body: Node3D) -> void:
	if body == player:
		action_prompt.hide_for(player)
		player = null


func _refresh() -> void:
	if not is_node_ready():
		return
	icon.visible = show_icon and item != null and item.icon != null
	icon.texture = item.icon if item else null
