class_name MkHazard
extends Area3D
## A dropped item lying on the track, waiting to spin somebody out.
##
## The other half of [MkProjectile]: that one flies, this one sits. A hazard
## dropped behind a kart stays where it lands until something drives into it, so
## it needs no flight, no target and no lifetime beyond an optional one for a
## course that would otherwise silt up over three laps.
##
## It cannot catch whoever dropped it for a moment after landing, or dropping one
## at speed would spin the dropper out on their own item.

signal triggered(kart: MkCar) ## Somebody drove into it.

@export var spin_seconds: float = 1.5 ## How long whoever hits it is spun out for.
## How long the kart that dropped it is immune. Long enough to drive clear of
## its own item and no longer; a judgement, named in
## [constant MkConst.UNSOURCED].
@export var owner_immunity_seconds: float = 0.6
## Seconds before it disappears on its own. Zero leaves it there for the whole
## race, which is what the game does.
@export var lifetime: float = 0.0

var owner_kart: MkCar ## Who dropped it.

var _age: float = 0.0


func _ready() -> void:
	add_to_group(&"mk_hazards")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_age += delta
	if lifetime > 0.0 and _age >= lifetime:
		queue_free()


## Drop it behind [param from_kart].
func drop(from_kart: MkCar) -> void:
	owner_kart = from_kart


func _on_body_entered(body: Node3D) -> void:
	var kart: MkCar = body as MkCar
	if kart == null:
		return
	if kart == owner_kart and _age < owner_immunity_seconds:
		return
	kart.spin_out(spin_seconds)
	triggered.emit(kart)
	queue_free()
