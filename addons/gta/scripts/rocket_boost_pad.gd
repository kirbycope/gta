class_name RocketBoostPad
extends Area3D
## One pad of boost on the floor of the arena.
##
## Rocket League has two kinds and they are not just different sizes: a big pad
## fills the tank outright and takes ten seconds to come back, a small one gives
## twelve boost and returns in four. Both are cylinders standing almost a metre
## off the floor rather than flat discs, so a car in the air can still clip one.
## Every number is in [RocketConst].
##
## The pad does not search for cars. Its own [signal Area3D.body_entered] is
## connected in [code]boost_pad.tscn[/code] and the body that arrives is asked
## whether it is a [RocketCar], which keeps the whole thing to one branch.

signal collected(by: RocketCar, amount: float) ## Picked up, for the HUD and the AI's map of the floor.

@export var is_big: bool = false: set = _set_is_big

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _cooldown: Timer = $Cooldown

var is_available: bool = true


func _ready() -> void:
	add_to_group(&"rocket_boost_pads")
	_apply_size()


## How much this pad is worth, which is also what the AI weighs a detour by.
func amount() -> float:
	return RocketConst.PAD_BOOST_BIG if is_big else RocketConst.PAD_BOOST_SMALL


## Put every pad back, which a kickoff does.
func reset_pad() -> void:
	_cooldown.stop()
	is_available = true
	_mesh.visible = true


## Connected in the scene to this area's own body_entered.
func _on_body_entered(body: Node3D) -> void:
	if not is_available:
		return
	var car: RocketCar = body as RocketCar
	if car == null or car.is_demolished:
		return
	if is_equal_approx(car.boost, RocketConst.BOOST_MAX):
		return # a full car drives over a pad without taking it
	car.collect_boost(amount())
	is_available = false
	_mesh.visible = false
	_cooldown.start(RocketConst.PAD_COOLDOWN_BIG if is_big else RocketConst.PAD_COOLDOWN_SMALL)
	collected.emit(car, amount())


## Connected in the scene to the Cooldown timer's timeout.
func _on_cooldown_timeout() -> void:
	is_available = true
	_mesh.visible = true


func _set_is_big(value: bool) -> void:
	is_big = value
	if is_inside_tree():
		_apply_size()


## The pickup volume is the published cylinder; the mesh is drawn a little
## flatter so the floor stays readable from the chase camera.
func _apply_size() -> void:
	var radius: float = RocketConst.PAD_RADIUS_BIG if is_big else RocketConst.PAD_RADIUS_SMALL
	var cylinder: CylinderShape3D = _shape.shape as CylinderShape3D
	if cylinder != null:
		cylinder.radius = radius
		cylinder.height = RocketConst.PAD_HEIGHT
	_shape.position.y = RocketConst.PAD_HEIGHT * 0.5
	var drawn: CylinderMesh = _mesh.mesh as CylinderMesh
	if drawn != null:
		drawn.top_radius = radius * 0.85
		drawn.bottom_radius = radius
		drawn.height = 0.18
	_mesh.position.y = 0.09
