class_name Bow
extends Equipment
## Fires arrows and plays draw/fire feedback from the Player's archery locomotion nodes.
##
## Every shot takes one arrow ([AmmoItem] for [constant Equipment.EquipmentType.BOW]) from the Player's inventory:
## the kind Use selected while any is carried, else regular arrows, and with none carried nothing flies. An arrow
## with its own [member AmmoItem.projectile_scene] flies as that scene, the rest as [member arrow_scene].
## The arrow leaves on the Player's projectile ray, level with the template arrow, on the arc that carries it through
## the crosshair's aim point ([method arc_direction]), so it lands where the crosshair is, give or take
## [member Equipment.accuracy].
## Expects a template [Arrow] child named "Arrow" and optional "BowDrawArrow"/"BowFireArrow"
## audio players; without a "BowFireArrow" the shot plays [member Equipment.attack_sfx] (the TomMusic bow attack) through
## the Player's [WeaponAudio], and drawing and stowing the bow play its take-out and put-away there too.
## While a kind with its own scene is what [method get_ammo] names, a frozen template copy of that
## scene sits on the string in its place ([member nocked_arrow]), so a fire arrow burns and an ice arrow frosts
## while drawing. Only the equipped copy on the Player's multiplayer authority (with [member player] set) reacts;
## peers get the arrow through the [ProjectileSpawner]. The nocked copy is cosmetic and local: the other peers'
## copies of a Player carry no equipment.

signal ammo_selected(ammo: AmmoItem) ## Emitted when Use on an [AmmoItem] for the bow picks the arrows it fires.

const RAY_MISS_DISTANCE: float = 40.0 ## Aim point distance when the projectile ray hits nothing.
const TAKE_OUT_SFX: AudioStream = preload("res://addons/3d_player_controller/assets/tommusic/fantasy_sfx/Attacks/Bow Attacks Hits and Blocks/Bow Take Out 1.ogg")
const PUT_AWAY_SFX: AudioStream = preload("res://addons/3d_player_controller/assets/tommusic/fantasy_sfx/Attacks/Bow Attacks Hits and Blocks/Bow Put Away 1.ogg")
const ATTACK_SFX: AudioStream = preload("res://addons/3d_player_controller/resources/audio/bow_attack.tres")

@export var arrow_scene: PackedScene ## Fired arrow scene; falls back to duplicating the template "Arrow" child when empty.

var selected_ammo: AmmoItem ## The arrows Use picked; null fires the plain kind.
var nocked_arrow: Projectile ## A template copy of the selected kind's own scene shown on the string in place of [member arrow_node]; null while regular arrows are nocked.
var nocked_scene: PackedScene ## The scene [member nocked_arrow] is a copy of; null while regular arrows are nocked.

@onready var arrow_node: Arrow = get_node_or_null("Arrow") as Arrow ## Template duplicated for every shot.
@onready var draw_sfx: AudioStreamPlayer3D = get_node_or_null("BowDrawArrow") as AudioStreamPlayer3D
@onready var fire_sfx: AudioStreamPlayer3D = get_node_or_null("BowFireArrow") as AudioStreamPlayer3D


## The bow's own sounds stand in for the sword defaults; a scene that sets others keeps them.
func _init() -> void:
	equip_sfx = TAKE_OUT_SFX
	stow_sfx = PUT_AWAY_SFX
	attack_sfx = ATTACK_SFX


func _ready() -> void:
	if player and player.is_multiplayer_authority():
		player.locomotion_node_changed.connect(_on_locomotion_node_changed)
		player.inventory.item_used.connect(_on_item_used)
		player.inventory.items_changed.connect(_on_items_changed)
		_on_items_changed()


func _on_locomotion_node_changed(state_path: String) -> void:
	if not player.inventory.equipment.has(self) or player.held_object.is_holding_object() or player.is_throwing:
		return
	var is_aiming: bool = state_path == "Bow/ArcheryLocomotion"
	player.set_look_at_target(player.look_at_target if is_aiming else null)
	var shown: Projectile = get_nocked_arrow()
	if shown:
		shown.visible = is_aiming
	match state_path:
		"Bow/BowDrawArrow":
			if draw_sfx:
				draw_sfx.play()
			player.controls.rumble(0.0, 0.2, 0.5)
		"Bow/BowFireArrow":
			if fire_arrow():
				if fire_sfx:
					fire_sfx.play() # the scene's own release sound stands in for attack_sfx
				elif player.weapon_audio:
					player.weapon_audio.play_attack(attack_sfx)
				player.controls.rumble(0.4, 0.0, 0.5)


## Use on an [AmmoItem] for the bow selects it; the next shots take that kind while any is carried.
func _on_item_used(item: Item, _count: int) -> void:
	var ammo: AmmoItem = item as AmmoItem
	if ammo == null or ammo.weapon_type != equipment_type:
		return
	selected_ammo = ammo
	ammo_selected.emit(ammo)
	_on_items_changed()


## The carried arrows changed (a selection, a kind running out): the string shows the kind the next shot takes.
func _on_items_changed() -> void:
	var ammo: AmmoItem = get_ammo()
	nock(ammo.projectile_scene if ammo else null)


## The arrows the next shot takes: [member selected_ammo] while some is carried, else regular arrows, else null.
func get_ammo() -> AmmoItem:
	return AmmoItem.pick(player.inventory, equipment_type, selected_ammo) if player else null


## The arrow on the string: [member nocked_arrow] while a special kind is nocked, else the template [member arrow_node].
func get_nocked_arrow() -> Projectile:
	return nocked_arrow if is_instance_valid(nocked_arrow) else arrow_node


## Puts a frozen template copy of [param scene] on the string in place of [member arrow_node], at the template's own
## transform and visibility, so its VFX (a flame, a frost) show while drawing; null puts the regular arrow back.
## Nothing changes when that scene is already nocked or the bow has no template arrow.
func nock(scene: PackedScene) -> void:
	if arrow_node == null or scene == nocked_scene:
		return
	var shown: bool = get_nocked_arrow().visible
	if is_instance_valid(nocked_arrow):
		nocked_arrow.queue_free()
	nocked_scene = scene
	nocked_arrow = scene.instantiate() as Projectile if scene else null
	if nocked_arrow:
		nocked_arrow.is_template = true
		nocked_arrow.transform = arrow_node.transform
		for shape: Node in nocked_arrow.find_children("*", "CollisionShape3D", true, false):
			(shape as CollisionShape3D).disabled = true
		add_child(nocked_arrow)
		nocked_arrow.visible = shown
	arrow_node.visible = shown and nocked_arrow == null


## The launch direction at [param speed] that carries a projectile under [param gravity] from [param from] through
## [param to]: the lower of the two arcs, the one closest to a straight shot. With [param to] out of range (or no
## gravity) the straight line, so the shot still flies at the crosshair.
static func arc_direction(from: Vector3, to: Vector3, speed: float, gravity: float) -> Vector3:
	var offset: Vector3 = to - from
	var flat: Vector3 = Vector3(offset.x, 0.0, offset.z)
	var distance: float = flat.length()
	var speed_squared: float = speed * speed
	var discriminant: float = speed_squared * speed_squared - gravity * (gravity * distance * distance + 2.0 * offset.y * speed_squared)
	if gravity <= 0.0 or distance < 0.001 or discriminant < 0.0:
		return offset.normalized()
	var angle: float = atan((speed_squared - sqrt(discriminant)) / (gravity * distance))
	return flat.normalized() * cos(angle) + Vector3.UP * sin(angle)


## Takes one arrow of the kind [method get_ammo] names from the inventory and fires it: its own scene, else
## [member arrow_scene], through the world's [ProjectileSpawner] when present (multiplayer), otherwise a local copy.
## The arrow leaves on the projectile ray, level with the nocked arrow, on the arc through the ray's hit point
## ([method arc_direction]), then [method Equipment.scatter] pushes it off that line for the Player's skill.
## False, and nothing flies, with no arrows carried or off the authority.
func fire_arrow() -> bool:
	var ammo: AmmoItem = get_ammo()
	var scene: PackedScene = (ammo.projectile_scene if ammo.projectile_scene else arrow_scene) if ammo else null
	if ammo == null or (scene == null and arrow_node == null) or not player.is_multiplayer_authority() \
			or player.inventory.remove_item(ammo, 1) == 0:
		return false
	var nocked: Node3D = get_nocked_arrow() if get_nocked_arrow() else self
	var ray: RayCast3D = player.projectile_raycast
	ray.force_raycast_update()
	var aim: Vector3 = ray.get_collision_point() if ray.is_colliding() else ray.global_position - ray.global_basis.z * RAY_MISS_DISTANCE
	var along: Vector3 = -ray.global_basis.z
	var origin: Transform3D = nocked.global_transform
	origin.origin = ray.global_position + along * maxf((nocked.global_position - ray.global_position).dot(along), 0.0)
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * (nocked.gravity_scale if nocked is RigidBody3D else 1.0)
	var direction: Vector3 = scatter(arc_direction(origin.origin, aim, projectile_speed, gravity))
	var spawner: ProjectileSpawner = get_tree().get_first_node_in_group(&"ProjectileSpawner") as ProjectileSpawner
	if scene and spawner:
		spawner.fire(scene, origin, direction, projectile_speed, player, self)
		return true
	var arrow: Projectile = scene.instantiate() as Projectile if scene else arrow_node.duplicate() as Projectile
	arrow.is_template = false
	var world: Node = get_tree().current_scene if get_tree().current_scene else player.get_parent()
	world.add_child(arrow)
	arrow.show()
	for shape: Node in arrow.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).disabled = false
	if not arrow.body_entered.is_connected(arrow._on_body_entered):
		arrow.body_entered.connect(arrow._on_body_entered)
	arrow.launch(origin, direction, projectile_speed, player, self)
	if arrow is Arrow:
		arrow.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
	var swish: AudioStreamPlayer3D = arrow.get_node_or_null("Swish") as AudioStreamPlayer3D
	if swish:
		swish.play()
	return true
