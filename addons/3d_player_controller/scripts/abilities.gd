class_name Abilities
extends CanvasLayer
## World of Warcraft style ability caster: tap "ability" to cast the picked ability, hold it to pick another from the wheel.
##
## Timed casts fill the cast bar; movement input, state and locomotion changes interrupt them unless the
## ability sets [member Ability.channel_while_moving], and attacks always do. Walking has no signal (the
## standing blend space absorbs it), so movement input is polled only while such a cast runs. Abilities with a
## [member Ability.projectile_speed] send their casting VFX/SFX flying as a [SpellProjectile] and land the
## impact on arrival, so nothing depends on physics contacts. Toggles (Stealth)
## stay on until cast again or, with [member Ability.ends_on_attack], until the Player attacks or fires.
## Cooldowns are stored as end times (toggles start theirs when they end), so nothing polls. Only the authority reads input;
## each phase's VFX/SFX is played on every peer through an RPC, and effects that must be seen by
## other peers (like [member Player.is_stealthed]) are replicated by the Player.

signal ability_activated(ability: Ability) ## Emitted when an ability's effect lands.
signal ability_deactivated(ability: Ability) ## Emitted when a toggle ends.
signal cast_started(ability: Ability) ## Emitted when a timed cast begins.
signal cast_interrupted(ability: Ability) ## Emitted when a timed cast breaks before landing.

const PROJECTILE_HEIGHT: float = 1.2 ## Bolts leave the caster at chest height.

@export var player: Player
@export var fx_root: Node3D ## Under the Player; phase VFX are instanced here.
@export var hand_anchor: Node3D ## The casting hand (a bone attachment): channeling VFX ride it and bolts leave from it. Without one they sit at the caster's feet and chest.
@export var channeling_audio: AudioStreamPlayer3D
@export var casting_audio: AudioStreamPlayer3D
@export var impact_audio: AudioStreamPlayer3D
@export var abilities: Array[Ability] = [] ## Abilities on the wheel; the first is picked at start.
@export var active_ability: Ability: ## The ability a tap of "ability" casts; the wheel changes it.
	set(value):
		active_ability = value
		if player and player.controls:
			_update_label()

var casting: Ability ## The ability whose cast time is running, if any.
var active_toggles: Array[Ability] = []
var _cooldown_ends: Dictionary[Ability, int] = {} ## Ability -> Time.get_ticks_msec() when it is ready again.
var _cast_tween: Tween
var _channeling_vfx: Node3D

@onready var hold_timer: Timer = $HoldTimer ## Separates a tap (cast) from a hold (wheel).
@onready var cast_timer: Timer = $CastTimer ## Runs an ability's cast time; its timeout lands the effect.
@onready var radial_menu: RadialMenu = $RadialMenu


func _ready() -> void:
	set_physics_process(false)
	set_process_unhandled_input(is_multiplayer_authority())
	if not is_multiplayer_authority():
		return
	radial_menu.custom_item_provider = get_wheel_items
	radial_menu.custom_item_selected = _on_wheel_item_selected
	radial_menu.custom_item_is_equipped = _is_wheel_item_active
	if active_ability == null and not abilities.is_empty():
		active_ability = abilities[0]
	# The Player's Controls exist once the Player itself is ready
	player.ready.connect(_update_label, CONNECT_ONE_SHOT)


func _unhandled_input(event: InputEvent) -> void:
	if player == null or player.riding_blocks_hands() or player.held_object.is_holding_object():
		hold_timer.stop()
		return

	if event.is_action_pressed("ability"):
		hold_timer.start()
	elif event.is_action_released("ability"):
		# A release while the timer still runs is a tap; a timeout already opened the wheel.
		if hold_timer.is_stopped():
			return
		hold_timer.stop()
		cast(active_ability)


## Casts [param ability] now, starts its cast bar, or ends it when it is an active toggle.
func cast(ability: Ability) -> void:
	if ability == null:
		return
	if active_toggles.has(ability):
		deactivate(ability)
		return
	if casting or not is_ready(ability):
		return
	if player.health.energy < ability.energy_cost or not ability.can_cast(player):
		return
	if ability.cast_time <= 0.0:
		_activate(ability)
		return
	casting = ability
	cast_timer.start(ability.cast_time)
	set_physics_process(not ability.channel_while_moving)
	var cast_bar: ProgressBar = player.controls.cast_bar
	player.controls.cast_label.text = ability.display_name
	cast_bar.value = 0.0
	cast_bar.show()
	_cast_tween = create_tween()
	_cast_tween.tween_property(cast_bar, "value", cast_bar.max_value, ability.cast_time)
	_play(ability, Ability.Phase.CHANNELING, _hand_position())
	cast_started.emit(ability)


func is_ready(ability: Ability) -> bool:
	return Time.get_ticks_msec() >= _cooldown_ends.get(ability, 0)


## Seconds left on [param ability]'s cooldown; 0 when it is ready.
func get_cooldown_remaining(ability: Ability) -> float:
	return maxf(0.0, (_cooldown_ends.get(ability, 0) - Time.get_ticks_msec()) / 1000.0)


func interrupt_cast() -> void:
	if casting == null:
		return
	var ability: Ability = casting
	casting = null
	set_physics_process(false)
	cast_timer.stop()
	_hide_cast_bar()
	_stop_channeling.rpc()
	cast_interrupted.emit(ability)


## Ends an active toggle; its cooldown runs from here, like leaving Stealth.
func deactivate(ability: Ability) -> void:
	if not active_toggles.has(ability):
		return
	active_toggles.erase(ability)
	_cooldown_ends[ability] = Time.get_ticks_msec() + int(ability.cooldown * 1000.0)
	ability.deactivate(player)
	ability_deactivated.emit(ability)


func get_wheel_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for ability: Ability in abilities:
		items.append({"display_name": ability.display_name, "icon": ability.icon, "icon_color": ability.icon_color, "item": ability})
	return items


## Lands the effect; false when the ability refused (nothing to aim at, full health), spending nothing.
func _activate(ability: Ability) -> bool:
	if not ability.activate(player):
		return false
	player.health.spend_energy(ability.energy_cost)
	if ability.is_toggle:
		active_toggles.append(ability)
	else:
		_cooldown_ends[ability] = Time.get_ticks_msec() + int(ability.cooldown * 1000.0)
	var target: Node3D = ability.get_target(player)
	var target_path: NodePath = target.get_path() if is_instance_valid(target) else NodePath()
	if ability.projectile_speed > 0.0:
		# The bolt carries the casting phase; the authority's copy lands the impact when it arrives
		_play(ability, Ability.Phase.CASTING, _bolt_origin(), target_path, ability.get_impact_position(player))
	else:
		_play(ability, Ability.Phase.CASTING, player.global_position)
		_land(ability, target, ability.get_impact_position(player))
	ability_activated.emit(ability)
	return true


## Where channeling VFX sit: the casting hand, or the caster's feet without one.
func _hand_position() -> Vector3:
	return hand_anchor.global_position if is_instance_valid(hand_anchor) else player.global_position


## Where a bolt leaves: the casting hand, or chest height without one.
func _bolt_origin() -> Vector3:
	return hand_anchor.global_position if is_instance_valid(hand_anchor) else player.global_position + player.up_direction * PROJECTILE_HEIGHT


## The impact phase: the ability's effect on the target, then its impact VFX/SFX. An ability that reports
## `hit_anything` (a melee swing) plays no impact when it whiffed: no sound, no elements at the caster's feet.
func _land(ability: Ability, target: Node3D, at: Vector3) -> void:
	ability.impact(player, target)
	if ability.get(&"hit_anything") == false:
		return
	_play(ability, Ability.Phase.IMPACT, at)


func _hide_cast_bar() -> void:
	if _cast_tween:
		_cast_tween.kill()
	player.controls.cast_bar.hide()


func _update_label() -> void:
	player.controls.joypad_button_9_label.text = active_ability.display_name if active_ability else ""


## Only runs during a cast that movement may break.
func _physics_process(_delta: float) -> void:
	if player.player_input.motion.length() > 0.0:
		interrupt_cast()


func _on_cast_timer_timeout() -> void:
	var ability: Ability = casting
	casting = null
	set_physics_process(false)
	_hide_cast_bar()
	_stop_channeling.rpc()
	if not _activate(ability):
		cast_interrupted.emit(ability) # Fizzled at the end of the cast: the channel pose has to drop


## Plays a phase's VFX/SFX on every peer; abilities not on the wheel play nothing.
func _play(ability: Ability, phase: Ability.Phase, at: Vector3, target_path: NodePath = NodePath(), destination: Vector3 = Vector3.ZERO) -> void:
	var index: int = abilities.find(ability)
	if index != -1:
		_play_phase.rpc(index, phase, at, target_path, destination)


@rpc("authority", "call_local", "reliable")
func _play_phase(ability_index: int, phase: Ability.Phase, at: Vector3, target_path: NodePath = NodePath(), destination: Vector3 = Vector3.ZERO) -> void:
	var ability: Ability = abilities[ability_index]
	var audio: AudioStreamPlayer3D = [channeling_audio, casting_audio, impact_audio][phase]
	# Channeling VFX are parented to the hand so they follow it through the cast
	var parent: Node3D = hand_anchor if phase == Ability.Phase.CHANNELING and is_instance_valid(hand_anchor) else fx_root
	var node: Node3D = ability.spawn_phase(phase, at, parent, audio, get_node_or_null(target_path), destination)
	if phase == Ability.Phase.CASTING and node is SpellProjectile and is_multiplayer_authority():
		# Only the caster's copy lands the impact
		(node as SpellProjectile).arrived.connect(_on_bolt_arrived.bind(ability_index, target_path))
	elif phase == Ability.Phase.CHANNELING:
		_channeling_vfx = node


func _on_bolt_arrived(at: Vector3, ability_index: int, target_path: NodePath) -> void:
	_land(abilities[ability_index], get_node_or_null(target_path), at)


@rpc("authority", "call_local", "reliable")
func _stop_channeling() -> void:
	if channeling_audio:
		channeling_audio.stop()
	if is_instance_valid(_channeling_vfx):
		_channeling_vfx.queue_free()
	_channeling_vfx = null


func _on_wheel_item_selected(item: Dictionary, _index: int) -> void:
	active_ability = item["item"]


func _is_wheel_item_active(item: Dictionary, _index: int) -> bool:
	return item["item"] == active_ability


## Wired to the Player's state_changed; movement breaks a cast unless the ability channels while moving.
func _on_state_changed(_from_state: int, _to_state: int) -> void:
	if casting and not casting.channel_while_moving:
		interrupt_cast()


## Wired to the Player's locomotion_node_changed; attacks always interrupt and end toggles that end on attack.
func _on_locomotion_node_changed(state_path: String) -> void:
	var node_name: String = state_path.get_file()
	if node_name.contains("SpellCast") or node_name.ends_with("PowerUp"):
		return # The cast's own clips
	var is_attack: bool = node_name in Attacking.ATTACK_NODES or node_name == "BowFireArrow"
	if casting and (is_attack or not casting.channel_while_moving):
		interrupt_cast()
	if is_attack:
		_end_attack_toggles()


## Wired to the Inventory's equipment_changed; firearms report shots through their fired signal.
func _on_equipment_changed() -> void:
	for item: Equipment in player.inventory.equipment:
		if item is Firearm and not item.fired.is_connected(_on_weapon_fired):
			item.fired.connect(_on_weapon_fired)


func _on_weapon_fired(_projectile: Projectile) -> void:
	_end_attack_toggles()


func _end_attack_toggles() -> void:
	for ability: Ability in active_toggles.duplicate():
		if ability.ends_on_attack:
			deactivate(ability)
