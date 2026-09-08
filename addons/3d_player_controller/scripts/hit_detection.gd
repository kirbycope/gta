class_name HitDetection
extends Node
## Delivers [code]register_weapon_hit()[/code] to bodies entering the active attack hitboxes and arms the
## weapon's physical body for the swing.
##
## Unarmed attacks use the hand hitboxes in player.tscn; armed attacks use the equipped weapon's
## child [Area3D] named "Hitbox". Hitboxes only monitor during attack swings, and each target is
## notified once per swing. Hits carry no synthetic knockback: NPCs react through their hit animations,
## and props are shoved by the weapon's [AnimatableBody3D] named "WeaponBody" (see [Equipment]), which
## is only on the Weapons physics layer while a swing is live.

signal weapon_hit(equipment: Node, target: Node) ## A swing landed: [param target] was told once this swing; [param equipment] is the weapon, or the Player when unarmed. [WeaponAudio] plays the impact.

const WEAPONS_LAYER: int = 10 ## The "Weapons" 3D physics layer in project.godot; a WeaponBody is on it only mid-swing.
## The locomotion nodes that are melee swings (the same nodes behind [member Player.is_attacking_1] to 3).
## The path arrives on every peer, so the weapon body also swings on puppets, where the server simulates the props.
const SWING_NODES: Array[String] = [
	"GreatSwordDownwardSlash", "GreatSwordLowSlash", "GreatSwordPowerSlash",
	"ShieldDownwardSlash", "ShieldCrossSlash", "ShieldPowerSlash",
	"ShortHeadJab", "BackHandCross",
]

@export var player: Player
@export var left_hand_hitbox: Area3D
@export var right_hand_hitbox: Area3D

var _hitboxes: Array[Area3D] = [] ## Hitboxes of the current loadout (hands when unarmed).
var _weapon_bodies: Array[AnimatableBody3D] = [] ## WeaponBody nodes of the equipped weapons.
var _swing_hit_targets: Array[Node] = [] ## Targets already notified during the current swing.


func _ready() -> void:
	if player == null or not is_multiplayer_authority():
		return
	left_hand_hitbox.body_entered.connect(_on_hitbox_body_entered.bind(left_hand_hitbox, null))
	right_hand_hitbox.body_entered.connect(_on_hitbox_body_entered.bind(right_hand_hitbox, null))
	_hitboxes.assign([left_hand_hitbox, right_hand_hitbox])


## Every locomotion node change is a new swing; hitboxes monitor and weapon bodies collide only while an
## attack node plays.
func _on_locomotion_node_changed(state_path: String) -> void:
	_swing_hit_targets.clear()
	var is_swinging: bool = player.is_attacking_1 or player.is_attacking_2 or player.is_attacking_3
	for hitbox: Area3D in _hitboxes:
		hitbox.monitoring = is_swinging
	var is_swing_node: bool = state_path.get_file() in SWING_NODES
	for body: AnimatableBody3D in _weapon_bodies:
		body.set_collision_layer_value(WEAPONS_LAYER, is_swing_node)


## Rebuilds the hitbox and weapon body lists from the equipped weapons (hands when unarmed).
func _on_equipment_changed() -> void:
	for hitbox: Area3D in _hitboxes:
		hitbox.monitoring = false
	for body: AnimatableBody3D in _weapon_bodies:
		if is_instance_valid(body):
			body.set_collision_layer_value(WEAPONS_LAYER, false)
	_hitboxes.clear()
	_weapon_bodies.clear()
	if player.inventory.is_unarmed():
		_hitboxes.assign([left_hand_hitbox, right_hand_hitbox])
		return
	for equipment: Equipment in player.inventory.equipment:
		if not equipment.can_attack:
			continue
		if equipment.weapon_body:
			equipment.weapon_body.set_collision_layer_value(WEAPONS_LAYER, false)
			_weapon_bodies.append(equipment.weapon_body)
		var hitbox: Area3D = equipment.get_node_or_null("Hitbox") as Area3D
		if hitbox == null:
			continue
		hitbox.monitoring = false
		if not hitbox.body_entered.is_connected(_on_hitbox_body_entered.bind(hitbox, equipment)):
			hitbox.body_entered.connect(_on_hitbox_body_entered.bind(hitbox, equipment))
		_hitboxes.append(hitbox)


## Notifies the hit target once per swing.
func _on_hitbox_body_entered(body: Node3D, _hitbox: Area3D, equipment: Equipment) -> void:
	if body == player or body.get_parent() == player.physical_bone_simulator:
		return
	_register_weapon_hit(body, equipment if equipment else player)


## Notifies the nearest ancestor that handles weapon hits, once per target per swing.
func _register_weapon_hit(collider: Node, equipment: Node) -> void:
	var node: Node = collider
	while node:
		if node.has_method("register_weapon_hit"):
			if node not in _swing_hit_targets:
				_swing_hit_targets.append(node)
				node.call("register_weapon_hit", equipment, collider)
				weapon_hit.emit(equipment, node)
			return
		node = node.get_parent()
