class_name Ability
extends Resource
## A World of Warcraft style ability: the Player casts it from the ability wheel, NPCs through an NPC caster.
##
## Subclass and override [method activate] (and [method deactivate] for toggles, [method impact] for
## effects on a target). Timing, costs and cooldowns are handled by the caster node; the resource only
## applies the effect and says what to play. [method spawn_phase] is the one place phase VFX/SFX and bolts come from.

enum Phase { CHANNELING, CASTING, IMPACT } ## Channeling runs for the cast time, casting fires on the caster when the effect lands, impact lands at [method get_impact_position].
enum Target { SELF, FOCUS } ## SELF lands on the caster; FOCUS lands on the Player's locked-on target (an NPC's `target`), else on whatever the crosshair points at, else where the Player aims.
enum CastStyle { NONE, FORWARD, UPWARD, SWEEPING_SIDEWAYS, SWEEPING_UPWARD, POWER_UP } ## The cast clip played when the effect lands; NONE plays no animation.
enum Element { FIRE = 1, WATER = 2 } ## Bits of [member elements]: what the impact does to the world around it.

const SPELL_PROJECTILE_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/spell_projectile.tscn")
const SPELL_CLIP_GROUPS: Array[String] = ["Shield", "GreatSword"] ## Locomotion groups with their own spell clips: a Spell Casting channel, a Spell Cast and a Power Up.
## The standing one-handed clip for each style; unarmed has no power up clip, so the upward cast stands in.
const STANDING_CAST_STATES: Dictionary = {
	CastStyle.FORWARD: "SpellCastForwards",
	CastStyle.UPWARD: "SpellCastUpwards",
	CastStyle.SWEEPING_SIDEWAYS: "SpellCastSweepingSideways",
	CastStyle.SWEEPING_UPWARD: "SpellCastSweepingUpwards",
	CastStyle.POWER_UP: "SpellCastUpwards",
}

@export var display_name: String = ""
@export var icon: Texture2D
@export var icon_color: Color = Color.WHITE ## Tints [member icon] on the wheel, the spell tree and the loadout (a fire spell orange, frost pale blue).
@export var cooldown: float = 0.0 ## Seconds before the ability can be cast again.
@export var cast_time: float = 0.0 ## Seconds the Player must stand still before the effect lands; 0 is instant.
@export var energy_cost: float = 0.0 ## Mana or energy from the caster's [Health] pool, spent when the effect lands; the cast is refused with less.
@export var channel_while_moving: bool = false ## Keeps a timed cast going while the Player moves; off, any movement interrupts it as in WoW. Attacks always interrupt.
@export var is_toggle: bool = false ## Stays active until cast again or [method deactivate] is called.
@export var ends_on_attack: bool = false ## Active toggles end when the Player attacks or fires a weapon.
@export var fx_lifetime: float = 3.0 ## Seconds a one-shot casting or impact VFX instance stays before it is freed.
@export var target_mode: Target = Target.SELF
@export var cast_range: float = 12.0 ## NPC casters use it only with their target this close.
@export var cast_style: CastStyle = CastStyle.NONE ## The cast clip played when the effect lands, picked per weapon group by [method get_cast_state]; a timed cast holds the group's Spell Casting channel first.
@export_group("Environment", "element")
@export_flags("Fire", "Water") var elements: int = 0 ## What the impact does to the world: Fire lights grass fields and burnable grass within [member element_radius] (as the torch does), Water douses fire there. Pick any mix.
@export var element_radius: float = 2.0 ## Metres around the impact the elements reach.
@export var element_fire_duration: float = 6.0 ## Seconds a lit grass field keeps spreading from the impact.
@export_group("Projectile", "projectile_")
@export var projectile_speed: float = 0.0 ## Metres per second; above 0 the casting VFX/SFX fly to the target as a [SpellProjectile] and impact lands on arrival.
@export var projectile_homing: bool = true ## The bolt follows a moving target and always arrives, WoW style.
@export_group("Channeling", "channeling_")
@export var channeling_vfx: PackedScene ## Kept on the caster for the cast time.
@export var channeling_sfx: AudioStream ## Played for the cast time; loop the stream for long casts.
@export_group("Casting", "casting_")
@export var casting_vfx: PackedScene ## One-shot on the caster when the effect fires.
@export var casting_sfx: AudioStream
@export_group("Impact", "impact_")
@export var impact_vfx: PackedScene ## One-shot at [method get_impact_position] when the effect fires.
@export var impact_sfx: AudioStream


## True when the cast can start at all (something to aim at, a patient who is hurt); a false here is refused
## before the cast bar runs, so the caster never channels for nothing. [method activate] checks again when it lands.
func can_cast(_caster: Node3D) -> bool:
	return true


## Applies the effect; return false to refuse the cast so no cost or cooldown is spent.
func activate(_caster: Node3D) -> bool:
	return true


## Ends an active toggle's effect.
func deactivate(_caster: Node3D) -> void:
	pass


func get_vfx(phase: Phase) -> PackedScene:
	return [channeling_vfx, casting_vfx, impact_vfx][phase]


func get_sfx(phase: Phase) -> AudioStream:
	return [channeling_sfx, casting_sfx, impact_sfx][phase]


## The locomotion state the caster travels to for this ability: [param group]'s Spell Casting channel while
## [param channeling], its Spell Cast (or Power Up) when the effect lands, or the standing one-handed clip for
## [member cast_style] with no weapon group (""). Empty when there is nothing to play: no style, a weapon group
## without spell clips (bow, guns, boxing), or a channel while unarmed.
func get_cast_state(group: String, channeling: bool) -> String:
	if cast_style == CastStyle.NONE:
		return ""
	if group in SPELL_CLIP_GROUPS:
		if channeling:
			return group + "/" + group + "SpellCasting"
		return group + "/" + group + ("PowerUp" if cast_style == CastStyle.POWER_UP else "SpellCast")
	if channeling or not group.is_empty():
		return ""
	return STANDING_CAST_STATES[cast_style]


## Applies the effect to [param target] when the impact lands (on arrival for projectiles); null when nothing was aimed at.
func impact(_caster: Node3D, _target: Node3D) -> void:
	pass


## Lets the impact's [member elements] loose on the world at [param at]: Fire lights every grass field and burnable
## grass within [member element_radius], Water douses them. Runs on every peer with the impact VFX, so all see it.
func apply_elements(tree: SceneTree, at: Vector3) -> void:
	if elements == 0 or tree == null:
		return
	if elements & Element.FIRE:
		ignite_grass(tree, at, element_radius, element_fire_duration)
	if elements & Element.WATER:
		tree.call_group(&"GrassField", &"douse_at", at, element_radius)
		for patch: Node in tree.get_nodes_in_group(&"BurnableGrass"):
			if patch is Node3D and patch.has_method(&"extinguish") and (patch as Node3D).global_position.distance_to(at) <= element_radius:
				patch.call(&"extinguish")


## Lights every grass field and burnable grass within [param radius] of [param at] for [param duration] seconds, the
## way a torch does: through the GrassField and BurnableGrass groups, duck-typed, and never in the rain (no force).
## Fire spells and burning projectiles (a fire arrow, an incendiary round) all light the world through here.
static func ignite_grass(tree: SceneTree, at: Vector3, radius: float, duration: float) -> void:
	tree.call_group(&"GrassField", &"ignite_at", at, radius, duration)
	for patch: Node in tree.get_nodes_in_group(&"BurnableGrass"):
		if patch is Node3D and patch.has_method(&"ignite") and (patch as Node3D).global_position.distance_to(at) <= radius:
			patch.call(&"ignite")


## The node the impact lands on: the caster itself, the Player's focus target (or, with nothing locked on, whatever
## the crosshair ray points at that can take a hit, so a spell fires forward like a projectile), or an NPC's `target`.
func get_target(caster: Node3D) -> Node3D:
	if target_mode == Target.SELF:
		return caster
	if caster is Player:
		var player: Player = caster as Player
		if is_instance_valid(player.current_focus_target):
			return player.current_focus_target
		return get_aimed_target(player)
	return caster.get("target") as Node3D


## Whatever the Player's crosshair ray points at that has `take_hit`, walking up from the collider; null otherwise.
static func get_aimed_target(player: Player) -> Node3D:
	var ray: RayCast3D = player.projectile_raycast
	ray.force_raycast_update()
	var node: Node = ray.get_collider() as Node if ray.is_colliding() else null
	while node and not node.has_method("take_hit"):
		node = node.get_parent()
	return node as Node3D


## Where the impact lands: the caster, the target, the Player's aim point, or straight ahead of an NPC.
func get_impact_position(caster: Node3D) -> Vector3:
	var target: Node3D = get_target(caster)
	if target == caster:
		return caster.global_position
	if is_instance_valid(target):
		return Focus.get_focus_target_position(target)
	if caster is Player:
		var ray: RayCast3D = (caster as Player).projectile_raycast
		ray.force_raycast_update()
		return ray.get_collision_point() if ray.is_colliding() else ray.global_position - ray.global_basis.z * Firearm.RAY_MISS_DISTANCE
	return caster.global_position - caster.global_basis.z * cast_range


## Plays [param phase] for a caster on this peer: SFX on [param audio], one-shot VFX under [param fx_root], or a
## [SpellProjectile] carrying the casting VFX/SFX when the ability has a projectile. Returns the channeling VFX or
## the bolt so the caller can stop or watch it; one-shot VFX free themselves after [member fx_lifetime].
func spawn_phase(phase: Phase, at: Vector3, fx_root: Node3D, audio: AudioStreamPlayer3D, target: Node3D, destination: Vector3) -> Node3D:
	if fx_root == null:
		return null
	if phase == Phase.IMPACT:
		apply_elements(fx_root.get_tree(), at)
	if phase == Phase.CASTING and projectile_speed > 0.0:
		var bolt: SpellProjectile = SPELL_PROJECTILE_SCENE.instantiate()
		bolt.speed = projectile_speed
		bolt.homing = projectile_homing
		bolt.target = target
		bolt.destination = destination
		if casting_vfx:
			bolt.add_child(casting_vfx.instantiate())
		fx_root.add_child(bolt)
		bolt.global_position = at
		if casting_sfx:
			bolt.audio.stream = casting_sfx
			bolt.audio.play()
		return bolt
	if audio and get_sfx(phase):
		audio.stream = get_sfx(phase)
		audio.global_position = at
		audio.play()
	var scene: PackedScene = get_vfx(phase)
	if scene == null:
		return null
	var vfx: Node3D = scene.instantiate()
	fx_root.add_child(vfx)
	vfx.global_position = at
	if phase != Phase.CHANNELING:
		fx_root.get_tree().create_timer(fx_lifetime).timeout.connect(vfx.queue_free)
	return vfx
