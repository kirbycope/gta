class_name TwCombat
extends Node
## Twisted Metal style combat bolted onto a [TwCar].
##
## Sits as a child of the car and owns its health, its weapon inventory and its
## firing. The shape follows Twisted Metal's own module layout, whose function
## names survive in the symbol table of the Twisted Metal 1 decompilation:
## [code]carTakeHit[/code], [code]carGetPickup[/code], [code]carDropWeapon[/code],
## [code]FireMissiles[/code], [code]FireSpecials[/code] and
## [code]AICarUpdateHealthTier[/code]. The car itself keeps driving; nothing here
## touches the handling model.

signal health_changed(current: float, maximum: float) ## Fired on every hit and repair.
signal died(killer: Node3D) ## Health reached zero; [param killer] may be null.
signal weapon_changed(weapon: StringName, count: int) ## The selected pickup or its count moved.
signal fired(weapon: StringName, forward: bool) ## A shot left the car, for audio and VFX.

const PROJECTILE: PackedScene = preload("res://addons/gta/tw/scenes/tw_projectile.tscn")
const MACHINE_GUN_DAMAGE: float = 1.0 ## Not published anywhere; see TwRoster.UNSOURCED.
const MACHINE_GUN_INTERVAL: float = 0.1
const HEALTH_TIERS: int = 3 ## AICarUpdateHealthTier splits health into thirds.

@export var car: StringName = &"roadkill" ## Roster key, see [TwRoster].
@export var muzzle_forward_path: NodePath = ^"../MuzzleForward"
@export var muzzle_rear_path: NodePath = ^"../MuzzleRear"

var max_health: float = 120.0
var health: float = 120.0
var is_dead: bool = false
var inventory: Dictionary = {} ## weapon key -> count remaining.
var selected: StringName = &"" ## The pickup the fire button will use, empty for none.
var specials: int = 0

var _vehicle: TwCar
var _gun_cooldown: float = 0.0
var _special_timer: float = 0.0
var _special_recharge: float = 35.0
var _max_specials: int = 5


func _ready() -> void:
	_vehicle = get_parent() as TwCar
	var stats: Dictionary = TwRoster.stats(car)
	if not stats.is_empty():
		max_health = float(stats["health"])
		_special_recharge = float(stats["special_s"])
		_max_specials = int(stats["specials"])
	health = max_health
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_gun_cooldown = maxf(0.0, _gun_cooldown - delta)
	if specials < _max_specials:
		_special_timer += delta
		if _special_timer >= _special_recharge:
			_special_timer = 0.0
			specials += 1


## How hurt the car is, 0 while healthy and [constant HEALTH_TIERS] - 1 at death's door.
## The AI reads this to decide whether to press an attack or break off.
func health_tier() -> int:
	if max_health <= 0.0:
		return 0
	var fraction: float = clampf(health / max_health, 0.0, 1.0)
	return clampi(int((1.0 - fraction) * HEALTH_TIERS), 0, HEALTH_TIERS - 1)


## Apply [param amount] of damage from [param from]. The car's own fire and
## wreck state is left to [TwCar], which listens for [signal died]; this only tracks the number.
func take_hit(amount: float, from: Node3D = null) -> void:
	if is_dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		is_dead = true
		died.emit(from)


## Repair, used by the health pickups that sit around a Twisted Metal arena.
func repair(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)


## Take a weapon off the floor. Mirrors [code]carGetPickup[/code].
func pick_up(weapon: StringName, count: int = 1) -> void:
	if not TwRoster.WEAPONS.has(weapon):
		return
	inventory[weapon] = int(inventory.get(weapon, 0)) + count
	if selected == &"":
		selected = weapon
	weapon_changed.emit(selected, int(inventory.get(selected, 0)))


## Step to the next pickup that still has ammunition.
func cycle_weapon() -> void:
	var keys: Array = TwRoster.WEAPONS.keys()
	var start: int = keys.find(selected)
	for step: int in range(1, keys.size() + 1):
		var candidate: StringName = keys[(start + step) % keys.size()]
		if int(inventory.get(candidate, 0)) > 0:
			selected = candidate
			weapon_changed.emit(selected, int(inventory[selected]))
			return


## Fire the selected pickup forward, or the machine gun when nothing is selected.
## Mirrors [code]FireMissiles[/code].
func fire_forward(target: Node3D = null) -> bool:
	if is_dead:
		return false
	var count: int = int(inventory.get(selected, 0))
	if selected == &"" or count <= 0:
		return _fire_machine_gun()
	inventory[selected] = count - 1
	_spawn(selected, true, target)
	fired.emit(selected, true)
	if inventory[selected] <= 0:
		inventory.erase(selected)
		selected = &""
		cycle_weapon()
	weapon_changed.emit(selected, int(inventory.get(selected, 0)))
	return true


## Drop a weapon out of the back of the car. Mirrors [code]carDropWeapon[/code].
func fire_rear(target: Node3D = null) -> bool:
	if is_dead or selected == &"":
		return false
	var count: int = int(inventory.get(selected, 0))
	if count <= 0:
		return false
	inventory[selected] = count - 1
	_spawn(selected, false, target)
	fired.emit(selected, false)
	if inventory[selected] <= 0:
		inventory.erase(selected)
		selected = &""
		cycle_weapon()
	weapon_changed.emit(selected, int(inventory.get(selected, 0)))
	return true


## Spend one charge of the car's special. Mirrors [code]FireSpecials[/code].
func fire_special(target: Node3D = null) -> bool:
	if is_dead or specials <= 0:
		return false
	specials -= 1
	_spawn(&"power_missile", true, target)
	fired.emit(&"special", true)
	return true


func _fire_machine_gun() -> bool:
	if _gun_cooldown > 0.0:
		return false
	_gun_cooldown = MACHINE_GUN_INTERVAL
	_spawn(&"machine_gun", true, null)
	fired.emit(&"machine_gun", true)
	return true


func _spawn(weapon: StringName, forward: bool, target: Node3D) -> void:
	if not is_instance_valid(_vehicle) or not _vehicle.is_inside_tree():
		return
	var muzzle: Node3D = get_node_or_null(muzzle_forward_path if forward else muzzle_rear_path) as Node3D
	var origin: Transform3D = muzzle.global_transform if muzzle != null else _vehicle.global_transform
	var shot: TwProjectile = PROJECTILE.instantiate() as TwProjectile
	shot.configure(weapon, _vehicle, target, MACHINE_GUN_DAMAGE)
	_vehicle.get_parent().add_child(shot)
	# each muzzle is turned the way its shot should travel, so the shot simply takes the
	# muzzle's transform: a projectile flies along its own -Z
	shot.global_transform = origin
