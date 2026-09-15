extends Node3D
## The Mario Kart demo: eight karts, three laps of Sunset Circuit, and items.
##
## The third of the addon's battle demos, and put together the same way. There is
## no [Player] here: a [HumanDriver] under your kart fills the same virtual pad
## the seven [MkAi] brains fill, and there is nothing to get out of.
##
## [b]What is a node and what is not.[/b] The course, the karts, the start grid
## and every item box are nodes in this scene, placed where they will be, so all
## of them can be selected and moved in the editor. That is deliberate and it is
## the opposite of how the Twisted Metal demo has to work: that one finds its
## spawn points by dropping rays onto a level whose collision only exists once
## the game is running, where this course is the addon's own and its grid is
## known at author time. Nothing here is built in code.
##
## The one thing this script does own is the wiring that cannot be saved in a
## scene file: telling the HUD which of the eight karts is yours, and saying so
## when the item odds are the stand in ones rather than the real tables.
##
## [b]The course[/b] is [code]scenes/mk/sunset_circuit.tscn[/code], an original
## circuit rather than a converted one, and it is one [Path3D] with the road
## extruded along it. Drag a point of that path in the editor and the road, the
## racing line the AI drives and the lap counting all move together.
## [code]tools/extract_mk64.py[/code] converts a course out of your own copy of
## Mario Kart 64 if you would rather race one of those; see the addon README.

@export var player_kart: NodePath = ^"Karts/Kart1" ## Which kart you drive.

@onready var ui: MkUi = get_node_or_null(^"MkUi")
@onready var race: MkRace = get_node_or_null(^"MkRace")
@onready var hint: Label = get_node_or_null(^"HUD/Hint")


func _ready() -> void:
	var kart: MkCar = get_node_or_null(player_kart) as MkCar
	if kart == null:
		if hint != null:
			hint.text = "The demo's player kart is missing from the scene."
		return
	# deferred so the race has collected the field and the HUD is listening
	# before the kart starts talking about laps and items
	_begin.call_deferred(kart)


func _begin(kart: MkCar) -> void:
	_hand_over_the_wheel(kart)
	if ui != null and race != null:
		ui.watch(kart, race)
	if hint != null:
		hint.text = "Accelerate with Space, drift with Q, use an item with T."


## Put a person at the player kart's pad, the way the other two battle demos do.
## The brain that would otherwise drive it is switched off first, and the item
## button is wired here because a [HumanDriver] reads holds rather than presses.
func _hand_over_the_wheel(kart: MkCar) -> void:
	if kart.get_node_or_null(^"HumanDriver") != null:
		return
	var brain: Node = kart.get_node_or_null(^"MkAi")
	if brain != null:
		brain.set(&"enabled", false)
	var driver: HumanDriver = HumanDriver.new()
	driver.name = "HumanDriver"
	driver.controls = get_node_or_null(^"Controls") as Controls
	kart.add_child(driver)
	kart.take_the_wheel()
	kart.item_used.connect(_on_item_used.bind(kart))


## The item button came up on the player's kart. [MkCar] only reports the
## press; what to do about it is the slot's business, and the slot is what knows
## whether there is anything in it.
func _on_item_used(_item: int, kart: MkCar) -> void:
	var slot: MkItemSlot = kart.get_node_or_null(^"ItemSlot") as MkItemSlot
	if slot != null:
		slot.use()
