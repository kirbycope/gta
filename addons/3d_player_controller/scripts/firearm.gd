class_name Firearm
extends Equipment
## A gun: while shoot is held it launches [member projectile_scene] along the Player's projectile ray,
## level with [member muzzle], so every round flies exactly through the crosshair, and shows
## [member laser_sight] from the muzzle to the aim point while aiming or shooting.
## It carries [member magazine_size] rounds; the "reload" action or an empty trigger pull takes one unit of
## ammunition ([AmmoItem], see [method get_ammo]) from the Player's inventory after [member reload_time] and refills
## the magazine, and the rounds of that kind fly until the next reload. [member reserve_rounds] is what the
## inventory holds. Every shot kicks the pad and a reload pulses it, through [method Controls.rumble].
##
## Shoot and focus are held inputs with no signal, so the equipped copy polls them each physics frame. Only the
## Player's multiplayer authority selects, reloads and draws from the inventory; peers get the rounds through the
## [ProjectileSpawner], the same scene the authority fired.

signal fired(projectile: Projectile) ## Emitted for every round that leaves the muzzle (null on clients, whose copy arrives through the spawner).
signal ammo_changed(rounds: int, reserve_rounds: int) ## Emitted when a round leaves, a reload lands or the carried ammunition changes.
signal ammo_selected(ammo: AmmoItem) ## Emitted when Use on an [AmmoItem] for this weapon picks the kind the next reload takes.

const RAY_MISS_DISTANCE: float = 100.0 ## Aim point distance when the projectile ray hits nothing.

@export var projectile_scene: PackedScene ## The [Projectile] scene to spawn per shot, unless the loaded ammunition names its own.
@export var automatic: bool = true ## Keep firing every [member fire_interval] while shoot is held.
@export var fire_interval: float = 0.12 ## Seconds between rounds.
@export var magazine_size: int = 12 ## Rounds per magazine.
@export var reserve_rounds: int = 48: ## Rounds carried outside the magazine. On a Player it reads from the inventory (units of [method get_ammo] times the rounds each holds); the value set here only serves a gun with no Player to draw from.
	get:
		if player and player.inventory:
			var ammo: AmmoItem = get_ammo()
			return player.inventory.count_of(ammo) * unit_rounds(ammo) if ammo else 0
		return reserve_rounds
@export var reload_time: float = 1.5 ## Seconds a reload blocks the trigger.
@export var muzzle: Marker3D ## Where rounds spawn; its -Z is the barrel direction.
@export var fire_timer: Timer ## One-shot timer that spaces rounds and times reloads (child of the weapon).
@export var laser_sight: LaserSight ## Optional pointer shown while aiming.
@export var fire_sfx: AudioStreamPlayer3D ## Optional shot sound.
@export var reload_sfx: AudioStreamPlayer3D ## Optional reload sound.

var rounds: int = 0: ## Rounds left in the magazine.
	set(value):
		rounds = value
		ammo_changed.emit(rounds, reserve_rounds)
var selected_ammo: AmmoItem ## The kind Use picked for this weapon; null takes the plain kind.
var loaded_ammo: AmmoItem ## The kind the last reload put in the magazine; null is the weapon's own round.
var is_reloading: bool = false
var _trigger_was_held: bool = false


func _ready() -> void:
	set_physics_process(false)
	set_process_unhandled_input(false)
	rounds = magazine_size
	if laser_sight:
		laser_sight.hide()
	if player and player.is_multiplayer_authority():
		player.inventory.equipment_changed.connect(_on_equipment_changed)
		player.inventory.item_used.connect(_on_item_used)
		player.inventory.items_changed.connect(_on_items_changed)
		ammo_changed.connect(player.controls.set_ammo)


## Only the equipped copy aims, fires, reloads and owns the HUD's ammo counter.
func _on_equipment_changed() -> void:
	var equipped: bool = player.inventory.equipment.has(self)
	set_physics_process(equipped)
	set_process_unhandled_input(equipped)
	if equipped:
		player.controls.set_ammo(rounds, reserve_rounds)
	elif not player.has_firearm_equipped:
		player.controls.hide_ammo()
	if not equipped and laser_sight:
		laser_sight.hide()


## Use on an [AmmoItem] for this weapon selects it; the next reload takes that kind.
func _on_item_used(item: Item, _count: int) -> void:
	var ammo: AmmoItem = item as AmmoItem
	if ammo == null or ammo.weapon_type != equipment_type:
		return
	selected_ammo = ammo
	ammo_selected.emit(ammo)
	_on_items_changed()


## The carried ammunition changed; the equipped copy's HUD count follows.
func _on_items_changed() -> void:
	if player.inventory.equipment.has(self):
		ammo_changed.emit(rounds, reserve_rounds)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reload"):
		reload()


func _physics_process(_delta: float) -> void:
	var shooting: bool = player.is_shooting
	if laser_sight:
		laser_sight.visible = shooting or player.is_focusing
		if laser_sight.visible:
			laser_sight.aim(muzzle.global_position, get_aim_point())
	if shooting and fire_timer.is_stopped() and (automatic or not _trigger_was_held):
		fire()
		fire_timer.start(fire_interval)
	_trigger_was_held = shooting


## Where the Player's camera-aligned projectile ray lands, or a point far along it.
func get_aim_point() -> Vector3:
	var ray: RayCast3D = player.projectile_raycast
	ray.force_raycast_update()
	if ray.is_colliding():
		return ray.get_collision_point()
	return ray.global_position - ray.global_basis.z * RAY_MISS_DISTANCE


## The ammunition the next reload takes: [member selected_ammo] while some is carried, else the plain kind for this
## weapon, else null. Null too on a gun with no Player.
func get_ammo() -> AmmoItem:
	return AmmoItem.pick(player.inventory, equipment_type, selected_ammo) if player else null


## Rounds one unit of [param ammo] holds: its own [member AmmoItem.rounds_per_unit], or a full magazine.
func unit_rounds(ammo: AmmoItem) -> int:
	return ammo.rounds_per_unit if ammo and ammo.rounds_per_unit > 0 else magazine_size


## The scene the next round is: the loaded ammunition's own, else [member projectile_scene].
func get_projectile_scene() -> PackedScene:
	return loaded_ammo.projectile_scene if loaded_ammo and loaded_ammo.projectile_scene else projectile_scene


## Launches one projectile on the projectile ray, level with the muzzle, toward the aim point; an empty
## magazine reloads instead. The round rides the crosshair line, so it lands where the crosshair is, give or
## take the spread of [member accuracy] for the Player's skill.
func fire() -> Projectile:
	var scene: PackedScene = get_projectile_scene()
	if scene == null or muzzle == null:
		return null
	if rounds <= 0:
		reload()
		return null
	rounds -= 1
	var ray: RayCast3D = player.projectile_raycast
	var aim: Vector3 = get_aim_point()
	var along: Vector3 = -ray.global_basis.z
	var origin: Transform3D = muzzle.global_transform
	origin.origin = ray.global_position + along * maxf((muzzle.global_position - ray.global_position).dot(along), 0.0)
	var direction: Vector3 = scatter(aim - origin.origin)
	var projectile: Projectile
	var spawner: ProjectileSpawner = get_tree().get_first_node_in_group(&"ProjectileSpawner") as ProjectileSpawner
	if spawner:
		projectile = spawner.fire(scene, origin, direction, projectile_speed, player, self)
	else:
		projectile = scene.instantiate() as Projectile
		var world: Node = get_tree().current_scene if get_tree().current_scene else player.get_parent()
		world.add_child(projectile)
		projectile.launch(origin, direction, projectile_speed, player, self)
	if fire_sfx:
		fire_sfx.play()
	player.controls.rumble(0.0, 0.8, 0.1)
	fired.emit(projectile)
	return projectile


## Refills the magazine once [member reload_time] has passed: one unit of [method get_ammo] leaves the inventory and
## its rounds go in (a gun with no Player draws on [member reserve_rounds] instead). Nothing happens while already
## reloading, full, out of ammunition, or on a copy that is not the Player's multiplayer authority. The fire timer
## doubles as the reload timer.
func reload() -> void:
	if is_reloading or rounds == magazine_size or reserve_rounds <= 0 or (player and not player.is_multiplayer_authority()):
		return
	is_reloading = true
	if reload_sfx:
		reload_sfx.play()
	if player:
		player.controls.rumble(0.3, 0.0, 0.2)
	fire_timer.start(reload_time)
	await fire_timer.timeout
	if player and player.inventory:
		var ammo: AmmoItem = get_ammo()
		if ammo and player.inventory.remove_item(ammo, 1) == 1:
			loaded_ammo = ammo
			rounds = mini(magazine_size, rounds + unit_rounds(ammo))
	else:
		var moved: int = mini(magazine_size - rounds, reserve_rounds)
		reserve_rounds -= moved
		rounds += moved
	is_reloading = false
