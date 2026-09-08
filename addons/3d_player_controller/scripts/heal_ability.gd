class_name HealAbility
extends Ability
## Heals through the target's `heal(amount) -> bool` method. A Player heals the fellow Player they have locked
## on to, otherwise themselves; an NPC always heals itself. The cast is refused when the target is already full.

@export var amount: float = 50.0


## A locked-on Player is the patient; anyone else heals themselves.
func get_target(caster: Node3D) -> Node3D:
	if caster is Player and (caster as Player).current_focus_target is Player:
		return (caster as Player).current_focus_target
	return caster


## Refused when the patient has no health to restore.
func can_cast(caster: Node3D) -> bool:
	var target: Node3D = get_target(caster)
	if not target.has_method("heal"):
		return false
	return target.call("can_heal") if target.has_method("can_heal") else true


func activate(caster: Node3D) -> bool:
	return can_cast(caster)


func impact(_caster: Node3D, target: Node3D) -> void:
	if is_instance_valid(target) and target.has_method("heal"):
		target.call("heal", amount)


## Heals land on the caster itself or a locked-on Player, never at the aim point.
func get_impact_position(caster: Node3D) -> Vector3:
	return get_target(caster).global_position
