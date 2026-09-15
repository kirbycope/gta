class_name MkProjectile
extends Area3D
## A fired item travelling under its own power: a shot, a homing shot or a
## leader shot.
##
## One script for the three because they differ by two exported numbers rather
## than by behaviour: how hard they steer toward a target, and whether that
## target is the kart in front or the kart in first. A straight shot simply has
## no homing at all, and bounces instead. [TwProjectile] is the same idea for
## the Twisted Metal demo, and this one is deliberately not built on it: that one
## carries damage and a blast radius, where a kart item only ever spins a kart
## out.
##
## [b]What it hits.[/b] A kart, a wall, or nothing until [member lifetime] runs
## out. It cannot hit the kart that fired it, which matters for the straight shot
## because that one bounces off walls and can come back down the track.
##
## [b]Over the network[/b] the server owns the flight and the hit, because a
## projectile that two peers simulate separately arrives in two different places.
## The spawn itself is replicated by whoever owns the race.

signal hit(kart: MkCar) ## It caught somebody.
signal expired() ## Its lifetime ran out, or it ran out of bounces.

@export var speed: float = 28.0 ## Metres per second. Faster than a kart, or it would never catch one.
## How hard it turns toward its target, in radians per second. Zero is a straight
## shot. Neither this nor [member speed] is published: the decomp's item actors
## were not read for this port, so both are named in
## [constant MkConst.UNSOURCED].
@export var homing_strength: float = 0.0
@export var lifetime: float = 8.0 ## Seconds before it gives up.
@export var bounces: int = 5 ## How many walls a non homing shot survives.
@export var spin_seconds: float = 1.5 ## How long whoever it catches is spun out for.
## Aim at whoever is leading rather than at the next kart up the road.
@export var targets_leader: bool = false

var owner_kart: MkCar ## Who fired it, and the one kart it cannot hit.
var velocity: Vector3 = Vector3.ZERO

var _seconds_left: float = 0.0
var _bounces_left: int = 0
var _target: MkCar


func _ready() -> void:
	add_to_group(&"mk_projectiles")
	_seconds_left = lifetime
	_bounces_left = bounces
	body_entered.connect(_on_body_entered)


## Fire it from [param from_kart] along [param direction]. Called by the race,
## which is what owns the spawn.
func launch(from_kart: MkCar, direction: Vector3) -> void:
	owner_kart = from_kart
	velocity = direction.normalized() * speed
	if is_instance_valid(from_kart):
		velocity += from_kart.linear_velocity.project(direction.normalized())


func _physics_process(delta: float) -> void:
	if not multiplayer.get_peers().is_empty() and not multiplayer.is_server():
		return
	_seconds_left -= delta
	if _seconds_left <= 0.0:
		_finish()
		return
	if homing_strength > 0.0:
		_steer_toward_target(delta)
	global_position += velocity * delta
	if not velocity.is_zero_approx():
		look_at(global_position + velocity, Vector3.UP)


## Turn toward whoever this shot is for, picked once and then kept so it cannot
## dither between two karts that keep swapping places.
func _steer_toward_target(delta: float) -> void:
	if not is_instance_valid(_target):
		_target = _pick_target()
	if not is_instance_valid(_target):
		return
	var wanted: Vector3 = (_target.global_position - global_position).normalized()
	velocity = velocity.normalized().slerp(wanted, clampf(homing_strength * delta, 0.0, 1.0)) * speed


## The kart this shot is meant for: whoever is leading, or the next one up the
## road from whoever fired.
func _pick_target() -> MkCar:
	var race: Node = get_tree().get_first_node_in_group(&"mk_race")
	if race == null:
		return null
	if targets_leader and race.has_method(&"leader"):
		return race.call(&"leader") as MkCar
	if race.has_method(&"kart_ahead_of"):
		return race.call(&"kart_ahead_of", owner_kart) as MkCar
	return null


func _on_body_entered(body: Node3D) -> void:
	var kart: MkCar = body as MkCar
	if kart != null:
		if kart == owner_kart:
			return
		kart.spin_out(spin_seconds)
		hit.emit(kart)
		_finish()
		return
	# a wall: a homing shot dies on it, a straight one comes off it
	if homing_strength > 0.0 or _bounces_left <= 0:
		_finish()
		return
	_bounces_left -= 1
	velocity = velocity.bounce(_wall_normal(body))


## Which way the wall faces. Godot's area overlap does not report a normal, so
## one ray is cast along the flight path to find it, the same compromise
## [RlConst] records for the surface under a car.
func _wall_normal(body: Node3D) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position - velocity.normalized(), global_position + velocity.normalized() * 2.0)
	query.collide_with_areas = false
	var result: Dictionary = space.intersect_ray(query)
	if result.has("normal") and result.get("collider") == body:
		return result["normal"] as Vector3
	return Vector3.UP


func _finish() -> void:
	expired.emit()
	queue_free()
