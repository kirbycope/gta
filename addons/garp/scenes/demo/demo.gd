extends Node3D
## GARP demo: a yard of pickups and the Player, whose inventory is saved to user:// between runs. Using an item
## only signals, so the demo shows the signal on the hint label; a game would apply the effect there.

const DEMO_TREE: SpellTree = preload("res://addons/garp/resources/spell_tree_demo.tres")

@onready var player: Player = $Player
@onready var hint: Label = $HUD/Hint
@onready var hint_timer: Timer = $HUD/HintTimer

var _hint_text: String = ""


func _ready() -> void:
	_hint_text = hint.text
	player.inventory.spellbook.tree = DEMO_TREE
	player.inventory.spellbook.skill_points = 3
	player.inventory.persist = true
	player.inventory.load_save()


## Wired to Player/Inventory.item_used.
func _on_item_used(item: Item, count: int) -> void:
	hint.text = "Used %d x %s (item_used signal; the game applies the effect)" % [count, item.get_display_name()]
	hint_timer.start()


## Wired to Player/Inventory.item_dropped.
func _on_item_dropped(item: Item, count: int, _pickup: Node3D) -> void:
	hint.text = "Dropped %d x %s" % [count, item.get_display_name()]
	hint_timer.start()


## Wired to HUD/HintTimer.timeout.
func _on_hint_timer_timeout() -> void:
	hint.text = _hint_text
