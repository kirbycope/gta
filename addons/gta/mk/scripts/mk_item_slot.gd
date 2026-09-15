class_name MkItemSlot
extends Node
## The one item a kart is holding, and what happens when it is used.
##
## A node under a [MkCar] rather than part of the kart itself, for the same
## reason [TwCombat] is a node under a [TwCar]: a kart in a time trial has no
## item slot at all, and a demo that wants one adds the node. The kart stays a
## kart.
##
## [b]The roulette.[/b] Drawing is [MkItems.draw], which reproduces the game's
## rolling index rather than rolling a fresh die each time, so this node carries
## the index between draws the way [code]sRandomItemIndex[/code] does. What rank
## to draw for comes from the race, because Mario Kart's odds are a function of
## where you are lying and nothing else; a slot with no race above it draws as
## though it were leading, which is the stingiest row and so the safe default.
##
## [b]Over the network[/b] the server draws and every peer is told, because two
## peers rolling their own die for the same box would disagree about what came
## out of it. Using an item is the reverse: the owner decides and tells everyone,
## because the owner is the one holding the button.

signal item_changed(item: int, uses_left: int) ## The slot's contents moved, for the HUD.
signal item_fired(item: int, forward: bool) ## An item was actually used; the race spawns it.
signal roulette_started() ## A box was hit and the slot is spinning.

## How long the slot spins before settling. The game spins the item window while
## the roulette sound plays; the duration is presentation rather than physics and
## is named in [constant MkConst.UNSOURCED].
@export var roulette_seconds: float = 0.9

var item: int = MkItems.Item.NONE ## What is held, or NONE.
var uses_left: int = 0 ## How many are left of a triple.
var is_spinning: bool = false ## A box has been hit and the slot has not settled.

## The game's [code]sRandomItemIndex[/code], carried between draws so successive
## items are not independent, exactly as the real roulette is not.
var rolling_index: int = 0

var _spin_seconds: float = 0.0
var _kart: MkCar


func _ready() -> void:
	_kart = get_parent() as MkCar


## Whether there is anything to use.
func has_item() -> bool:
	return item != MkItems.Item.NONE and uses_left > 0


## Hit an item box. Does nothing when the slot is already full or already
## spinning, which is how the game stops one box filling a held slot.
## [param rank] is the kart's position, zero based.
func collect(rank: int) -> void:
	if has_item() or is_spinning:
		return
	if not multiplayer.get_peers().is_empty() and not multiplayer.is_server():
		return
	var drawn: Dictionary = MkItems.draw(rank, rolling_index, Engine.get_physics_frames())
	_begin.rpc(int(drawn["item"]), int(drawn["rolling_index"]))


## Use whatever is held. The owner decides and every peer is told.
func use() -> void:
	if not has_item() or is_spinning:
		return
	_use.rpc(item)


## Put an item in the slot directly, for a test or a demo that wants to hand one
## over without a box.
func give(new_item: int) -> void:
	item = new_item
	uses_left = MkItems.uses(new_item)
	is_spinning = false
	_spin_seconds = 0.0
	item_changed.emit(item, uses_left)


func _process(delta: float) -> void:
	if not is_spinning:
		return
	_spin_seconds -= delta
	if _spin_seconds <= 0.0:
		is_spinning = false
		item_changed.emit(item, uses_left)


## The server drew; every peer starts the same spin and lands on the same item.
@rpc("authority", "call_local", "reliable")
func _begin(drawn: int, index: int) -> void:
	rolling_index = index
	item = drawn
	uses_left = MkItems.uses(drawn)
	is_spinning = true
	_spin_seconds = roulette_seconds
	roulette_started.emit()


## The holder used it. Boosts are applied here because they act on the kart
## itself; everything else is handed to the race, which owns the world the
## projectile has to live in.
@rpc("any_peer", "call_local", "reliable")
func _use(used: int) -> void:
	if MkItems.is_boost(used):
		if is_instance_valid(_kart):
			_kart.boost(MkConst.frames(MkConst.BOOST_FRAMES))
	else:
		item_fired.emit(used, not MkItems.is_dropped(used))
	uses_left -= 1
	if uses_left <= 0:
		item = MkItems.Item.NONE
		uses_left = 0
	item_changed.emit(item, uses_left)
