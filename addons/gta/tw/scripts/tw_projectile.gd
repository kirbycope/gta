class_name TwProjectile
extends Area3D
## One Twisted Metal shot in flight: a missile, a bomb or a machine gun round.
##
## Damage, speed and homing strength come from [TwRoster.WEAPONS], so the
## published Twisted Metal 2 numbers are the only place these are set.

signal detonated(where: Vector3)

const LIFETIME: float = 8.0
const RICOCHET_GAIN: float = 1.0 ## Damage added per bounce, up to the weapon's ceiling.

var weapon: StringName = &"fire_missile"
var damage: float = 7.0
var max_damage: float = 7.0
var speed: float = 60.0
var homing: float = 0.0
var bounces_left: int = 0
var shooter: Node3D
var target: Node3D

var _age: float = 0.0


## Set up the shot before it is added to the tree.
func configure(weapon_key: StringName, from: Node3D, at: Node3D, gun_damage: float) -> void:
	weapon = weapon_key
	shooter = from
	target = at
	var stats: Dictionary = TwRoster.WEAPONS.get(weapon_key, {})
	if stats.is_empty():
		damage = gun_damage
		max_damage = gun_damage
		speed = 120.0
		return
	damage = float(stats["damage"])
	max_damage = float(stats["max_damage"])
	speed = float(stats["speed"])
	homing = float(stats.get("homing", 0.0))
	bounces_left = int(stats.get("bounces", 0))


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	monitoring = true


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		_detonate()
		return
	if homing > 0.0 and is_instance_valid(target) and target.is_inside_tree():
		var to_target: Vector3 = (target.global_position - global_position).normalized()
		var steered: Vector3 = (-global_transform.basis.z).lerp(to_target, homing * delta * 4.0)
		if steered.length_squared() > 0.0001:
			look_at(global_position + steered, Vector3.UP)
	global_position += -global_transform.basis.z * speed * delta


func _on_body_entered(body: Node3D) -> void:
	if body == shooter:
		return
	var combat: TwCombat = _combat_of(body)
	if combat != null:
		combat.take_hit(damage, shooter)
		_detonate()
		return
	if bounces_left > 0:
		# a ricochet gets angrier every time it comes off the scenery
		bounces_left -= 1
		damage = minf(max_damage, damage + RICOCHET_GAIN)
		rotate_y(PI * 0.5)
		return
	_detonate()


func _combat_of(body: Node3D) -> TwCombat:
	if not is_instance_valid(body):
		return null
	for child: Node in body.get_children():
		if child is TwCombat:
			return child as TwCombat
	return null


func _detonate() -> void:
	detonated.emit(global_position)
	queue_free()
