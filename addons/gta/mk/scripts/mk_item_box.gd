class_name MkItemBox
extends Area3D
## A box a kart drives through to fill its item slot.
##
## Placed as a node in the course scene rather than spawned in code, so the boxes
## can be dragged around in the editor and seen where they will be. A row of them
## across the track is a row of these under one parent.
##
## The box does not decide what comes out of it. It tells the kart's
## [MkItemSlot] that it was hit, and the slot draws, because the odds depend on
## where that kart is lying and the box has no idea. What the box owns is only
## whether it is there to be hit: mk64 respawns a collected box after a while,
## and [member respawn_seconds] is that timer.
##
## [b]Over the network[/b] the server decides a box was taken, because two peers
## deciding separately would hand out two items for one box.

signal collected(kart: MkCar) ## Somebody took it.
signal respawned() ## It is back.

## How long a taken box stays gone. mk64 respawns its boxes on a timer; the
## exact number is not published, so this is a judgement named in
## [constant MkConst.UNSOURCED].
@export var respawn_seconds: float = 5.0
@export var spin_degrees_per_second: float = 90.0 ## The box turns on the spot.
## A decoy looks like a box and is not. One placed by a kart sets this, and it
## spins the kart that touches it instead of filling its slot.
@export var is_decoy: bool = false

var is_available: bool = true ## False while it is waiting to come back.

var _seconds_gone: float = 0.0

@onready var mesh: Node3D = get_node_or_null(^"Mesh")


func _ready() -> void:
	add_to_group(&"mk_item_boxes")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if is_instance_valid(mesh) and is_available:
		mesh.rotate_y(deg_to_rad(spin_degrees_per_second) * delta)
	if is_available:
		return
	_seconds_gone -= delta
	if _seconds_gone <= 0.0:
		_set_available.rpc(true)


## A kart drove into it. The server rules on it; a decoy needs no ruling because
## spinning out is the kart's own business either way.
func _on_body_entered(body: Node3D) -> void:
	var kart: MkCar = body as MkCar
	if kart == null or not is_available:
		return
	if is_decoy:
		kart.spin_out()
		_set_available.rpc(false)
		return
	if multiplayer.get_peers().is_empty() or multiplayer.is_server():
		_take.rpc(kart.get_path())


## Every peer takes the box away and tells the kart's slot to draw.
@rpc("authority", "call_local", "reliable")
func _take(kart_path: NodePath) -> void:
	var kart: MkCar = get_node_or_null(kart_path) as MkCar
	if kart == null:
		return
	var slot: MkItemSlot = kart.get_node_or_null(^"ItemSlot") as MkItemSlot
	if slot != null:
		slot.collect(_rank_of(kart))
	_set_available(false)
	collected.emit(kart)


## Where [param kart] is lying, for the odds. The race knows; without one the
## kart is treated as leading, which is the stingiest row.
func _rank_of(kart: MkCar) -> int:
	var race: Node = get_tree().get_first_node_in_group(&"mk_race")
	if race != null and race.has_method(&"rank_of"):
		return int(race.call(&"rank_of", kart))
	return 0


@rpc("authority", "call_local", "reliable")
func _set_available(value: bool) -> void:
	is_available = value
	_seconds_gone = respawn_seconds if not value else 0.0
	# deferred because this is reached from inside body_entered, and Godot
	# refuses to switch an area's monitoring while it is emitting one
	set_deferred(&"monitoring", value)
	if is_instance_valid(mesh):
		mesh.visible = value
	if value:
		respawned.emit()
