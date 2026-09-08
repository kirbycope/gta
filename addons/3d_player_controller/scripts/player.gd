class_name Player
extends CharacterBody3D

signal state_changed(from_state: int, to_state: int) ## Emitted when [member current_state] changes.
signal ride_started(rideable: Node3D) ## Emitted when the Player gets on a rideable.
signal ride_ended(rideable: Node3D) ## Emitted when the Player gets off it.
signal locomotion_node_changed(state_path: String) ## Emitted when the locomotion path ("Group/Node" or "Node") changes; on puppets this follows replication.
signal exhausted_changed(is_exhausted: bool) ## Emitted when [member is_exhausted] changes.
signal navigating_changed(is_navigating: bool) ## Emitted when click-to-move navigation starts or stops.
signal paused_changed(is_paused: bool) ## Emitted when [member is_paused] changes (a menu opened or closed).
signal whistled(player: Player) ## Emitted on the authority when the `whistle` action is pressed on foot (not while riding); the world decides who answers.

const EMOTE_STATE_PLAYBACK_PATH: String = "parameters/EmoteStateMachine/playback"
const CAST_CHANNEL_EMOTE: StringName = &"ReadyToCastSpell" ## Upper-body pose held while an unarmed cast channels.
const LOCOMOTION_STATE_PLAYBACK_PATH: String = "parameters/LocomotionStateMachine/playback"
const ARCHERY_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/Bow/ArcheryLocomotion/blend_position"
const BOW_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/Bow/BowLocomotion/blend_position"
const BOXING_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/Boxing/BoxingLocomotion/blend_position"
const BRACED_HANG_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/BracedHangLocomotion/blend_position"
const CLIMBING_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/ClimbingLocomotion/blend_position"
const CROUCHING_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/CrouchingLocomotion/blend_position"
const FREE_HANGING_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/FreeHangingLocomotion/blend_position"
const FLYING_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/FlyingLocomotion/blend_position"
const GREATSWORD_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/GreatSword/GreatSwordLocomotion/blend_position"
const PISTOL_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/Pistol/PistolLocomotion/blend_position"
const RIFLE_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/Rifle/RifleLocomotion/blend_position"
const SHIELD_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/Shield/ShieldLocomotion/blend_position"
const STANDING_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/StandingLocomotion/blend_position"
const SWIMMING_LOCOMOTION_BLEND_POSITION_PATH: String = "parameters/LocomotionStateMachine/SwimmingLocomotion/blend_position"
const LOCOMOTION_GROUPS: Array[String] = ["Bow", "Boxing", "GreatSword", "Pistol", "Rifle", "Shield"] ## Grouped sub-state machines inside the LocomotionStateMachine.

@export var animation_tree: AnimationTree
@export var motion_interpolate_speed: float = 10.0
@export var rotation_interpolate_speed: float = 10.0
@export var swimming_root_motion_multiplier: float = 2.0

@export_category("Enable Settings")
@export var enable_flying: bool = false
@export var enable_paraglider: bool = false
@export var enable_ragdoll: bool = false
@export var enable_stamina: bool = false
@export_category("Optional Gadgets & Gear")
@export var paraglider_scene: PackedScene
@export_category("Optional Interaction")
@export var push_force: float = 1.0
@export var mass: float = 80.0

var current_state: int = -1: ## The current state of the Player (from the Node/Code [NodeStateMachine], not the AnimationTree NodeStateMachine).
	set(value):
		if value == current_state:
			return
		var previous_state: int = current_state
		current_state = value
		# Spawn-state replication assigns this while the puppet's children are still entering the tree (not ready yet)
		if is_node_ready():
			state_changed.emit(previous_state, value)
var locomotion_state: ## Gets the [NodeStateMachine] "LocomotionStateMachine"
	get:
		return animation_tree.get(LOCOMOTION_STATE_PLAYBACK_PATH)
var active_locomotion_playback: ## Playback of the active grouped locomotion machine, or the root LocomotionStateMachine playback.
	get:
		var root_playback: AnimationNodeStateMachinePlayback = animation_tree.get(LOCOMOTION_STATE_PLAYBACK_PATH)
		if root_playback == null:
			return null
		var root_node: String = String(root_playback.get_current_node())
		if root_node in LOCOMOTION_GROUPS:
			return animation_tree.get("parameters/LocomotionStateMachine/" + root_node + "/playback")
		return root_playback
var current_locomotion_node: String: ## The deepest current locomotion state name (resolves grouped state machines).
	get:
		if animation_tree == null:
			return ""
		var playback: AnimationNodeStateMachinePlayback = active_locomotion_playback
		if playback == null:
			return ""
		return String(playback.get_current_node())
var current_locomotion_path: String: ## The current locomotion state path ("Group/Node" or "Node"), as accepted by [method travel_locomotion].
	get:
		if animation_tree == null:
			return ""
		var root_playback: AnimationNodeStateMachinePlayback = locomotion_state
		if root_playback == null:
			return ""
		var root_node: String = String(root_playback.get_current_node())
		if root_node in LOCOMOTION_GROUPS:
			return root_node + "/" + current_locomotion_node
		return root_node
var equipped_axe_1h: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.AXE_1H)
var equipped_axe_2h: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.AXE_2H)
var equipped_bow: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.BOW)
var equipped_dagger: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.DAGGER)
var equipped_fishing_rod: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.FISHING_ROD)
var equipped_pistol: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.PISTOL)
var equipped_rifle: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.RIFLE)
var equipped_shield: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.SWORD_AND_SHIELD)
var equipped_staff: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.STAFF)
var equipped_sword_1h: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.SWORD_1H)
var equipped_sword_2h: bool:
	get:
		return inventory != null and inventory.has_equipment(Equipment.EquipmentType.SWORD_2H)
var has_move_input: bool:
	get:
		return player_input != null and player_input.motion.length_squared() > 0.001
var uses_equipment_jump_variants: bool:
	get:
		return equipped_axe_1h \
			or equipped_axe_2h \
			or equipped_bow \
			or equipped_dagger \
			or equipped_fishing_rod \
			or equipped_pistol \
			or equipped_rifle \
			or equipped_shield \
			or equipped_staff \
			or equipped_sword_1h \
			or equipped_sword_2h
var is_boxing: bool = false

# Attack Sequence
var attack_sequence: int = 0
var is_attacking: bool = false
var is_attacking_1: bool: # Attack Sequence: 1 of n
	get: return current_locomotion_node in ["GreatSwordDownwardSlash", "ShieldDownwardSlash", "ShortHeadJab"] if is_multiplayer_authority() and animation_tree else false
var is_attacking_2: bool: # Attack Sequence: 2 of n
	get: return current_locomotion_node in ["GreatSwordLowSlash", "ShieldCrossSlash", "BackHandCross"] if is_multiplayer_authority() and animation_tree else false
var is_attacking_3: bool: # Attack Sequence: 3 of n
	get: return current_locomotion_node in ["GreatSwordPowerSlash", "ShieldPowerSlash"] if is_multiplayer_authority() and animation_tree else false
# Bow and Arrow
var is_aiming_bow: bool:
	get:
		if held_object and (held_object.is_holding_object() or held_object.is_charging_throw or held_object.is_throwing):
			return false
		return current_locomotion_node == "ArcheryLocomotion" if is_multiplayer_authority() and equipped_bow else false
var is_drawing_arrow: bool:
	get:
		if held_object and (held_object.is_holding_object() or held_object.is_charging_throw or held_object.is_throwing):
			return false
		return current_locomotion_node == "BowDrawArrow" if is_multiplayer_authority() and equipped_bow else false
var is_firing_arrow: bool:
	get:
		if held_object and (held_object.is_holding_object() or held_object.is_charging_throw or held_object.is_throwing):
			return false
		return current_locomotion_node == "BowFireArrow" if is_multiplayer_authority() and equipped_bow else false
# Climbing
var is_climbing: bool = false ## Is the Player currently climbing?
var is_climbing_on: bool = false ## Is the Player currently climbing on to a ledge?
var climbing_on_target: Vector3 ## The target position the Player is climbing on to (from ledge detection).
var is_climbing_hopping_left: bool = false ## Is the Player currently hopping left while climbing?
var is_climbing_hopping_right: bool = false ## Is the Player currently hopping right while climbing?
var is_climbing_hopping_up: bool = false ## Is the Player currently hopping up while climbing?
var is_hopping_from_climbing: bool = false ## Is the Player currently hopping while climbing?
# Riding
var is_riding: bool = false ## Riding something (a board, a vehicle, a mount); [member riding] moves the Player.
var riding: Node3D = null ## What is being ridden; it follows the rideable contract described in [Riding].
var is_mounting: bool = false ## Playing the get-on animation; the rideable does not move the Player yet.
var is_dismounting: bool = false ## Playing the get-off animation.
# Hanging
var is_hanging_braced: bool = false ## Is the Player currently hanging (braced)?
var is_hanging_free: bool = false ## Is the Player currently hanging (free)?

var is_crouching: bool = false ## Is the Player currently crouching?
var is_emoting: bool = false ## Is the Player currently emoting?
var has_started_emoting: bool = false ## Has the player's emote animation transitioned away from Idle yet?
var is_exhausted: bool = false: ## Is the Player currently exhausted?
	set(value):
		if value != is_exhausted:
			is_exhausted = value
			exhausted_changed.emit(value)
var is_falling: bool = false ## Is the Player currently falling?
var is_fishing: bool = false ## Is the Player currently fishing (has a rod equipped)?
var is_casting_line: bool = false ## Is the Player currently casting a fishing line?
var is_reeling_line: bool = false ## Is the Player currently casting a fishing line?
var is_flying: bool = false ## Is the Player currently flying?
var is_focusing: bool: ## Is the Player currently focusing (forward or on a target)?
	get:
		if not is_multiplayer_authority() or is_typing or riding_blocks_hands():
			return false
		if held_object and held_object.is_holding_object():
			return false
		# While the cursor is visible, right-click is reserved for camera rotation.
		if DisplayServer.get_name() != "headless" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			return false
		# Also suppressed during the temporary right-click capture used for camera rotation.
		if camera is Camera and (camera as Camera).is_temporarily_captured:
			return false
		return Input.is_action_pressed("focus")
var is_jumping: bool = false ## Is the Player currently jumping?
var is_jump_queued: bool = false ## Is the Player currently queued to jump?
var is_front_flipping: bool = false ## Is the Player currently front flipping?
var is_back_flipping: bool = false ## Is the Player currently back flipping?
var is_flipping: bool: ## Is the Player currently front or back flipping?
	get:
		if not is_multiplayer_authority() or animation_tree == null:
			return false
		return is_front_flipping or is_back_flipping \
				or current_locomotion_node in ["Backflip", "FowardFlip"]
var is_throwing: bool: ## Is the Player currently in a throw wind-up? (Delegates to [HeldObject].)
	get:
		return held_object != null and held_object.is_throwing
	set(value):
		if held_object:
			held_object.is_throwing = value
var held_rigidbody: RigidBody3D: ## The [RigidBody3D] currently carried, if any. (Delegates to [HeldObject].)
	get:
		return held_object.held_rigidbody if held_object else null
var current_focus_target: Node3D: ## The body currently locked on to, if any. (Delegates to [Focus].)
	get:
		return focus.current_focus_target if focus else null


## Returns the 3D focus target position (resolving Marker3D_FocusTarget on the target body if present).
func get_focus_target_position() -> Vector3:
	if not is_instance_valid(current_focus_target):
		return global_position
	return Focus.get_focus_target_position(current_focus_target)

var has_firearm_equipped: bool: ## Is a firearm (Pistol, Rifle) currently equipped?
	get:
		return inventory != null and inventory.has_firearm_equipped()

var has_bow_equipped: bool: ## Is a bow currently equipped?
	get:
		return inventory != null and inventory.has_bow_equipped()

var is_aiming_firearm: bool: ## Is the Player currently aiming with a firearm (Pistol, Rifle)?
	get:
		if not is_multiplayer_authority() or riding_blocks_hands() or inventory == null:
			return false
		if held_object and (held_object.is_holding_object() or held_object.is_charging_throw or held_object.is_throwing):
			return false
		return is_focusing and has_firearm_equipped

var is_mining: bool: ## Is the Player currently mining?
	get:
		if not is_multiplayer_authority() or animation_tree == null:
			return false
		return is_locomotion_state_active_or_queued("Mining")
var is_logging: bool: ## Is the Player currently logging?
	get:
		if not is_multiplayer_authority() or animation_tree == null:
			return false
		return is_locomotion_state_active_or_queued("Logging")
var is_navigating: bool = false: ## Is the Player currently navigating (click to move)?
	set(value):
		if value != is_navigating:
			is_navigating = value
			navigating_changed.emit(value)
var is_paragliding: bool = false ## Is the Player currently paragliding?
var is_paused: bool = false: ## Is the Player currently paused?
	set(value):
		if value != is_paused:
			is_paused = value
			paused_changed.emit(value)
var is_typing: bool = false ## Is the local Player typing in the chat window? Gameplay input is blocked while true.
var is_pushing: bool = false ## Is the Player currently pushing?
var is_ragdolling: bool = false ## Is the Player currently ragdolling?
var requires_shoot_release_after_throw: bool = false ## Set during a throw to require releasing the shoot button before shooting weapons.
var selected_throwable: Item = null ## The throwable [Item] the seeker wheel picked; "throw" throws it when the equipped equipment is not throwable (see [HeldObject]).
var is_shooting: bool: ## Is the Player currently shooting?
	get:
		if not is_multiplayer_authority() or is_typing or riding_blocks_hands() or inventory == null:
			return false
		if is_throwing:
			return false
		if held_object:
			if held_object.is_holding_object() or held_object.is_charging_throw or held_object.is_throw_queued or held_object.is_throwing:
				return false
		if requires_shoot_release_after_throw:
			if Input.is_action_pressed("shoot"):
				return false
			else:
				requires_shoot_release_after_throw = false
		return Input.is_action_pressed("shoot") and inventory.can_player_shoot
var is_sitting: bool = false ## Is the Player currently sitting?
var is_sliding: bool = false ## Is the Player currently sliding?
var is_sprinting: bool = false ## Is the Player currently sprinting?
var is_standing: bool = false ## Is the Player currently standing?
var last_safe_shore_position: Vector3 = Vector3.ZERO ## Last known grounded position on dry land.
var is_stealthed: bool = false: ## Is the Player hidden by Stealth? Replicated, so puppets fade too and followers ignore them.
	set(value):
		is_stealthed = value
		if skeleton and is_inside_tree():
			_apply_stealth_look(is_stealthed)
var is_swimming: bool = false ## Is the Player currently swimming?
var is_diving: bool = false ## Is the Player currently diving underwater (submerged swimming)?
var swim_vertical_speed: float = 0.0 ## Vertical swim speed (m/s along up_direction) applied while swimming/diving.
var model_pitch: float = 0.0 ## Local pitch (radians) applied to the player model, used while diving.
@export var model_pitch_pivot_height: float = 0.9 ## Height (m) above the model origin the dive pitch pivots around (hips), so the body doesn't sweep through walls.
var drawn_weapon_group: String = "" ## Locomotion group whose draw animation already played; its Start skips the redraw.
var last_fall_speed: float = 0.0 ## The downward vertical fall speed right before movement update.
var initial_collision_shape_height: float
var initial_collision_shape_position: Vector3
var orientation := Transform3D()
var root_motion := Transform3D()
var smoothed_motion: Vector2 = Vector2.ZERO
var paraglider: Node3D

@onready var attack_sequence_timer: Timer = $AttackSequenceTimer
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var initial_collision_shape_transform: Transform3D = collision_shape.transform
@onready var separation_ray_shape: CollisionShape3D = $SeparationRayShape3D
@onready var initial_separation_ray_transform: Transform3D = separation_ray_shape.transform
@onready var controls: CanvasLayer = $Controls
@onready var chat: ChatWindow = get_node_or_null("Chat") as ChatWindow ## The local chat window; puppets keep a hidden copy that relays RPCs.
@onready var crosshair: TextureRect = $Crosshair
@onready var debug: Debug = $Debug
@onready var inventory: Inventory = $Inventory
@onready var abilities: Abilities = $Abilities
@onready var weapon_audio: WeaponAudio = get_node_or_null("WeaponAudio") as WeaponAudio ## The weapon one-shots (draw, stow, swing, hit); optional.
@onready var radial_menu: RadialMenu = $Inventory/RadialMenu
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var pause: PlayerMenuLayer = $Pause
@onready var settings: PlayerMenuLayer = $Settings
@onready var audio_settings: PlayerMenuLayer = $AudioSettings
@onready var video_settings: PlayerMenuLayer = $VideoSettings
@onready var lobby_manager: PlayerMenuLayer = get_node_or_null("LobbyManager") as PlayerMenuLayer
@onready var stamina: TextureProgressBar = $Stamina
@onready var health: Health = $Health
@onready var respawn_timer: Timer = $RespawnTimer ## Runs after death; its timeout is wired to [method respawn].
var _ragdoll_was_enabled: bool = true ## enable_ragdoll before death forced it on.
@onready var initial_transform: Transform3D = global_transform
@onready var falling_raycast: RayCast3D = $FallingRaycast
@onready var player_model: Node3D = $PlayerModel
@onready var ledge_detection_horizontal: RayCast3D = $PlayerModel/LedgeDetectionHorizontal
@onready var ledge_detection_vertical: RayCast3D = $PlayerModel/LedgeDetectionHorizontal/LedgeDetectionVertical
@onready var ledge_detection_marker: MeshInstance3D = $PlayerModel/LedgeDetectionHorizontal/LedgeDetectionVertical/LedgeDetectionMarker
@onready var hanging_braced_detection: RayCast3D = $PlayerModel/HangingBracedDetection
@onready var look_at_target: Marker3D = $CameraMount/ProjectileRaycast/LookAtTarget
@onready var camera_mount: Node3D = $CameraMount
@onready var item_spring_arm: SpringArm3D = $CameraMount/ItemSpringArm
@onready var player_input: InputSynchronizer = $InputSynchronizer
@onready var focus: Focus = $Focus
@onready var held_object: HeldObject = $HeldObject
@onready var seeker_wheel: SeekerWheel = get_node_or_null("SeekerWheel") as SeekerWheel ## The ammunition and throwable picker, held open with "seeker".
@onready var initial_player_model_transform: Transform3D = player_model.transform
@onready var paraglider_raycast: RayCast3D = $ParagliderRaycast
@onready var projectile_raycast: RayCast3D = $CameraMount/ProjectileRaycast
@onready var skeleton: Skeleton3D = $PlayerModel/Armature/GeneralSkeleton
@onready var look_at_modifier = $PlayerModel/Armature/GeneralSkeleton/LookAtModifier3D
@onready var right_hand_ik: TwoBoneIK3D = $PlayerModel/Armature/GeneralSkeleton/RightHandIK
@onready var physical_bone_simulator: PhysicalBoneSimulator3D = $PlayerModel/Armature/GeneralSkeleton/PhysicalBoneSimulator3D
@onready var spring_arm: SpringArm3D = $CameraMount/CameraSpringArm
@onready var camera: Camera3D = $CameraMount/CameraSpringArm/Camera3D
@onready var toon_filter: ToonFilter = $CameraMount/CameraSpringArm/Camera3D/ToonFilter ## Screen-space toon shading; a local video setting.
@onready var state_machine: NodeStateMachine = $NodeStateMachine ## Enables/Disables the scripts that run when various States are entered/exited.
@onready var audio: Audio = $Audio
@onready var steam_persona_name: Label3D = $SteamPersonaName
@onready var voice_chat_indicator: MeshInstance3D = get_node_or_null("VoiceChatIndicator") as MeshInstance3D
@onready var voice_audio_player: AudioStreamPlayer3D = get_node_or_null("VoiceAudioPlayer") as AudioStreamPlayer3D
@onready var player_synchronizer: MultiplayerSynchronizer = get_node_or_null("PlayerSynchronizer") as MultiplayerSynchronizer

@export var sync_locomotion_node: String = "":
	set(value):
		if value == sync_locomotion_node:
			return
		sync_locomotion_node = value
		if not is_multiplayer_authority() and animation_tree and is_node_ready():
			_apply_synced_locomotion_node(value)
		locomotion_node_changed.emit(value)

@export var sync_blend_position: Vector2 = Vector2.ZERO:
	set(value):
		sync_blend_position = value
		if not is_multiplayer_authority() and animation_tree and is_node_ready():
			_apply_synced_blend_position(value)

var voice_playback: AudioStreamGeneratorPlayback = null
var is_broadcasting: bool = false
var current_water_area: Area3D = null


## Spawned players are named by their peer id (see [PlayerSpawner]); that peer owns this copy.
func _enter_tree() -> void:
	if str(name).is_valid_int():
		set_multiplayer_authority(str(name).to_int())


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Ensure AnimationTree is active so animations render on authority and puppets
	if animation_tree:
		animation_tree.active = true
		animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS

	# Do nothing if not the authority
	if not is_multiplayer_authority():
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return


	# Pre-initialize orientation transform.
	orientation = player_model.global_transform
	orientation.origin = Vector3()

	# Apply persistent user settings
	PlayerSettingsResource.load_or_create().apply_all(get_viewport(), self)

	# Record the initial collision shape height and position for crouching and sliding.
	initial_collision_shape_height = collision_shape.shape.height
	initial_collision_shape_position = collision_shape.position


	# Improve traction on spheres/slopes
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(60.0)
	floor_constant_speed = true

	# Ensure the projectile RayCast3D doesn't collide with the player
	projectile_raycast.add_exception(self)

	# Ensure PhysicalBone3D nodes never collide with the player CharacterBody3D
	if physical_bone_simulator:
		for child in physical_bone_simulator.get_children():
			if child is PhysicalBone3D:
				child.add_collision_exception_with(self)
				add_collision_exception_with(child)

	# Set the Player's initial state
	if state_machine:
		state_machine.travel(-1, NodeStateMachine.States.STANDING)
	else:
		current_state = NodeStateMachine.States.STANDING

	# Initialize optional gadget scenes if assigned
	if not paraglider:
		paraglider = get_node_or_null("PlayerModel/Armature/GeneralSkeleton/ParagliderBoneAttachment/Paraglider")
	if paraglider_scene and not paraglider:
		var bone_attachment = get_node_or_null("PlayerModel/Armature/GeneralSkeleton/ParagliderBoneAttachment")
		var paraglider_instance = paraglider_scene.instantiate() as Node3D
		if paraglider_instance:
			if bone_attachment:
				bone_attachment.add_child(paraglider_instance)
			else:
				player_model.add_child(paraglider_instance)
			paraglider = paraglider_instance
			if "player" in paraglider:
				paraglider.set("player", self)
			paraglider.hide()

	# Update Steam persona name if Steam is enabled
	var steamworks: Node = get_node_or_null("/root/Steamworks")
	if steamworks and steamworks.get("steam_id") != 0 and Engine.has_singleton("Steam"):
		var steam_singleton: Object = Engine.get_singleton("Steam")
		var lobby_update_callback: Callable = _on_steam_lobby_chat_update
		if not steam_singleton.is_connected("lobby_chat_update", lobby_update_callback):
			steam_singleton.connect("lobby_chat_update", lobby_update_callback)
		_update_steam_persona_name()

	# Initialize voice audio player playback
	if voice_audio_player:
		var generator: AudioStreamGenerator = voice_audio_player.stream as AudioStreamGenerator
		var steam: Object = _get_steam_running()
		if generator and steam:
			var optimal_rate: int = steam.getVoiceOptimalSampleRate()
			if optimal_rate > 0:
				generator.mix_rate = float(optimal_rate)
		if not voice_audio_player.playing:
			voice_audio_player.play()
		voice_playback = voice_audio_player.get_stream_playback() as AudioStreamGeneratorPlayback

	_setup_updraft_vfx()


## Called when there is an unhandled input event.
func _unhandled_input(event: InputEvent) -> void:
	# Do nothing while paused, typing in the chat, or ragdolling
	if is_paused or is_typing or is_ragdolling: return

	# Chat; handled here rather than in _input so a menu that consumes Enter through the GUI wins
	if event.is_action_pressed("chat") and chat:
		chat.open_input()
		get_viewport().set_input_as_handled()
		return


	# Toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		# Check if the mouse is currently captured
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			# Set the mouse mode to visible to show the mouse cursor
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# The mouse must not be currently captured
		else:
			# Set the mouse mode to captured to hide the mouse cursor
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# [Left Mouse Button] pressed while the cursor is visible -> Start "navigating"
	if event is InputEventMouse \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		# Find out where the click lands on the player's movement plane
		var mouse_event: InputEventMouse = event
		var from: Vector3 = camera.project_ray_origin(mouse_event.position)
		var to: Vector3 = from + camera.project_ray_normal(mouse_event.position) * 10000.0
		var movement_plane := Plane(up_direction, global_position.dot(up_direction))
		var cursor_position: Variant = movement_plane.intersects_ray(from, to)
		if cursor_position != null:
			navigation_agent.target_position = cursor_position
			is_navigating = true
			if debug.visible:
				debug.draw_navigation_marker(cursor_position)

	# Whistle (action="whistle", key="K", D-Pad Down): the horse and whoever else listens answer; a rideable takes it first
	if event.is_action_pressed("whistle") and not event.is_echo() and not is_riding:
		whistled.emit(self)

	# Push-to-talk voice broadcasting (action="broadcast", key="V")
	if event.is_action_pressed("broadcast"):
		start_broadcasting()
	elif event.is_action_released("broadcast"):
		stop_broadcasting()


## Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	var steam: Object = _get_steam_running() if is_multiplayer_authority() and is_broadcasting else null
	if steam:
		var available_voice: Dictionary = steam.getAvailableVoice()
		if available_voice.get("result") == STEAM_VOICE_RESULT_OK and available_voice.get("written", 0) > 0:
			var voice_data: Dictionary = steam.getVoice()
			if voice_data.get("result") == STEAM_VOICE_RESULT_OK:
				var buffer: PackedByteArray = voice_data.get("buffer", PackedByteArray())
				if not buffer.is_empty() and multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
					_receive_voice_packet.rpc(buffer)


## Called every physics frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	# Track which weapon group has finished its draw so re-entering it skips the redraw.
	var root_locomotion_node: String = String(locomotion_state.get_current_node())
	if root_locomotion_node in LOCOMOTION_GROUPS:
		var inner_node: String = current_locomotion_node
		# Skip Start/End so the flag isn't set before the entry edge picks draw vs skip.
		if not inner_node.ends_with("Draw") and inner_node not in ["Start", "End", ""]:
			drawn_weapon_group = root_locomotion_node
	elif drawn_weapon_group != "" and not is_group_equipment_equipped(drawn_weapon_group):
		drawn_weapon_group = ""

	# Apply player input to control the character and update the animation state.
	apply_input(delta)

	# Treat "jumping" as queued jump or upward airborne movement.
	is_jumping = is_jump_queued or (not is_on_floor() and current_locomotion_node.contains("Jump"))

	# Stop emote state when the animation finishes and reset the blend amount.
	if is_emoting:
		if animation_tree.get(EMOTE_STATE_PLAYBACK_PATH).get_current_node() != "Idle":
			has_started_emoting = true
		elif has_started_emoting:
			animation_tree.set("parameters/EmoteSpineBlend2/blend_amount", 0.0)
			is_emoting = false
			has_started_emoting = false
			is_throwing = false

	# Update network animation sync properties on authority
	if is_multiplayer_authority():
		var curr_loco: String = current_locomotion_path
		if curr_loco != sync_locomotion_node and not curr_loco.is_empty():
			sync_locomotion_node = curr_loco
		var blend_to_sync := Vector2(0.0, smoothed_motion.length())
		if is_focusing or is_shooting or is_boxing:
			blend_to_sync = smoothed_motion
		if blend_to_sync != sync_blend_position:
			sync_blend_position = blend_to_sync

# https://github.com/godotengine/tps-demo/blob/master/player/gd#L86
func apply_input(delta: float) -> void:
	# Get the target motion from the synchronized input.
	var target_motion: Vector2 = player_input.motion

	# Block player movement control if paused, typing or ragdolling.
	if is_paused or is_typing or is_ragdolling:
		target_motion = Vector2.ZERO
		smoothed_motion = Vector2.ZERO
		is_sprinting = false

	# If the player is mining, logging, or flipping, block regular locomotion transitions by setting the `target_motion` to zero.
	if is_mining or is_logging or is_flipping:
		target_motion = Vector2.ZERO

	# Smoothly interpolate the target_motion for more gradual changes in animation blending and rotation.
	var motion_weight: float = clampf(motion_interpolate_speed * delta, 0.0, 1.0)
	smoothed_motion = smoothed_motion.lerp(target_motion, motion_weight)
	target_motion = smoothed_motion

	# While riding, paragliding, flying, or ragdolling, block regular locomotion.
	# Riding.gd / Paragliding.gd / Flying.gd / Ragdolling.gd will handle movement.
	if (is_riding and not is_mounting and not is_dismounting) or is_paragliding or is_flying or is_ragdolling or is_sitting:
		return

	# Sprint logic
	if is_sprinting:
		if is_focusing:
			var forward_amount: float = clampf(absf(target_motion.y), 0.0, 1.0)
			target_motion.y *= 1.5
			# Favor the forward blend only on diagonal sprints; pure strafing keeps full speed.
			target_motion.x *= lerpf(1.0, 0.5, forward_amount)
		else:
			target_motion *= 1.5

	# A slow scales the wish, so the blend walks where it would run
	target_motion *= movement_scale

	var is_first_person: bool = camera is Camera and (camera as Camera).perspective == Camera.Perspective.FIRST_PERSON
	# Handle movement is strafing
	if not is_riding and (is_shooting or is_focusing or is_first_person):
		# Rotate to face the target, or the camera direction when shooting or in first person
		if not is_firing_arrow and not is_hanging_braced and not is_hanging_free and not is_climbing:
			var look_dir: Vector3 = Vector3.ZERO
			
			if is_focusing and is_instance_valid(current_focus_target):
				look_dir = (get_focus_target_position() - global_position).slide(up_direction)
			else:
				var camera_basis := spring_arm.global_transform.basis
				look_dir = - camera_basis.z
				look_dir = look_dir.slide(up_direction)
				
			if look_dir.length_squared() > 0.001:
				look_dir = look_dir.normalized()
				var q_from: Quaternion = orientation.basis.get_rotation_quaternion()
				var q_to: Quaternion = Basis.looking_at(-look_dir, up_direction).get_rotation_quaternion()
				if is_focusing and is_instance_valid(current_focus_target):
					# Catch up quickly on lock-on, then track the target exactly (lag causes orbit wobble).
					var focus_weight: float = clampf(delta * rotation_interpolate_speed * 2.0, 0.0, 1.0)
					if q_from.angle_to(q_to) < 0.05:
						focus_weight = 1.0
					orientation.basis = Basis(q_from.slerp(q_to, focus_weight))
				else:
					var rotate_speed: float = rotation_interpolate_speed * 2.0 if is_aiming_firearm else rotation_interpolate_speed
					var rotate_weight: float = clampf(delta * rotate_speed, 0.0, 1.0)
					orientation.basis = Basis(q_from.slerp(q_to, rotate_weight))

		if is_crouching:
			animation_tree.set(CROUCHING_LOCOMOTION_BLEND_POSITION_PATH, target_motion)
		else:
			if inventory.has_equipment(Equipment.EquipmentType.BOW):
				if is_shooting:
					animation_tree.set(ARCHERY_LOCOMOTION_BLEND_POSITION_PATH, target_motion)
				else:
					animation_tree.set(BOW_LOCOMOTION_BLEND_POSITION_PATH, target_motion)
			elif inventory.has_one_handed_or_shield_equipped():
				animation_tree.set(SHIELD_LOCOMOTION_BLEND_POSITION_PATH, target_motion)
			elif inventory.has_heavy_weapon_equipped():
				animation_tree.set(GREATSWORD_LOCOMOTION_BLEND_POSITION_PATH, target_motion)
			elif inventory.has_equipment(Equipment.EquipmentType.PISTOL):
				animation_tree.set(PISTOL_LOCOMOTION_BLEND_POSITION_PATH, target_motion)
			elif inventory.has_equipment(Equipment.EquipmentType.RIFLE):
				animation_tree.set(RIFLE_LOCOMOTION_BLEND_POSITION_PATH, target_motion)
			elif inventory.is_unarmed() and is_boxing:
				animation_tree.set(BOXING_LOCOMOTION_BLEND_POSITION_PATH, target_motion)
			else:
				animation_tree.set(STANDING_LOCOMOTION_BLEND_POSITION_PATH, target_motion)

	# Handle movement when not strafing
	elif not is_riding:
		# Use camera-relative direction for target_motion direction
		var camera_basis := spring_arm.global_transform.basis
		var target_dir := camera_basis * Vector3(target_motion.x, 0.0, -target_motion.y)
		target_dir = target_dir.slide(up_direction)
		if target_dir.length_squared() > 0.001 and not is_firing_arrow and not is_hanging_braced and not is_hanging_free and not is_climbing:
			target_dir = target_dir.normalized()
			var q_from: Quaternion = orientation.basis.get_rotation_quaternion()
			var q_to: Quaternion = Basis.looking_at(-target_dir, up_direction).get_rotation_quaternion()
			orientation.basis = Basis(q_from.slerp(q_to, delta * rotation_interpolate_speed))

		var anim_blend := Vector2(0.0, target_motion.length())
		if is_crouching:
			animation_tree.set(CROUCHING_LOCOMOTION_BLEND_POSITION_PATH, anim_blend)
		if inventory.has_equipment(Equipment.EquipmentType.BOW):
			if is_shooting:
				animation_tree.set(ARCHERY_LOCOMOTION_BLEND_POSITION_PATH, anim_blend)
			else:
				animation_tree.set(BOW_LOCOMOTION_BLEND_POSITION_PATH, anim_blend)
		elif inventory.has_one_handed_or_shield_equipped():
			animation_tree.set(SHIELD_LOCOMOTION_BLEND_POSITION_PATH, anim_blend)
		elif inventory.has_heavy_weapon_equipped():
			animation_tree.set(GREATSWORD_LOCOMOTION_BLEND_POSITION_PATH, anim_blend)
		elif inventory.has_equipment(Equipment.EquipmentType.PISTOL):
			animation_tree.set(PISTOL_LOCOMOTION_BLEND_POSITION_PATH, anim_blend)
		elif inventory.has_equipment(Equipment.EquipmentType.RIFLE):
			animation_tree.set(RIFLE_LOCOMOTION_BLEND_POSITION_PATH, anim_blend)
		elif inventory.is_unarmed() and is_boxing:
			animation_tree.set(BOXING_LOCOMOTION_BLEND_POSITION_PATH, anim_blend)
		else:
			animation_tree.set(STANDING_LOCOMOTION_BLEND_POSITION_PATH, anim_blend)

	var root_motion_position := animation_tree.get_root_motion_position()
	if is_swimming and not is_climbing_on:
		root_motion_position *= swimming_root_motion_multiplier

	root_motion = Transform3D(animation_tree.get_root_motion_rotation(), root_motion_position)

	orientation *= root_motion

	var h_velocity: Vector3 = orientation.origin / delta
	
	# Override h_velocity when targeting so tangential root motion follows an exact circular arc.
	if is_focusing and is_instance_valid(current_focus_target):
		var to_target: Vector3 = (get_focus_target_position() - global_position).slide(up_direction)
		var orbit_radius: float = to_target.length()
		if orbit_radius > 0.1:
			var target_dir: Vector3 = to_target / orbit_radius
			# Strafe distance becomes rotation about the target; forward/back changes the radius.
			var arc_angle: float = - root_motion_position.x / orbit_radius
			var new_radius: float = maxf(orbit_radius - root_motion_position.z, 0.1)
			var new_offset: Vector3 = (-target_dir * new_radius).rotated(up_direction, arc_angle)
			h_velocity = (to_target + new_offset) / delta

	# Influence of root motion is removed when in the air, and movement is instead based on the input direction to allow for more player control while jumping and falling.
	# Flips stay root-motion driven so held move input doesn't push the player around.
	if (is_jumping or is_falling) and not is_flipping:
		var camera_basis := spring_arm.global_transform.basis
		var target_dir := camera_basis * Vector3(target_motion.x, 0.0, -target_motion.y)
		target_dir = target_dir.slide(up_direction)
		
		var current_h_vel := velocity.slide(up_direction)
		var current_speed := current_h_vel.length()
		var air_speed_cap := max(current_speed, 5.0)
		var target_h_vel = target_dir * air_speed_cap
		
		# Slowly lerp to target air speed to preserve momentum
		h_velocity = current_h_vel.lerp(target_h_vel, 3.0 * delta)

	var vertical_speed := velocity.dot(up_direction)
	if is_climbing or is_climbing_on or is_climbing_hopping_left or is_climbing_hopping_right or is_climbing_hopping_up:
		vertical_speed = h_velocity.dot(up_direction)
	elif is_hanging_braced or is_hanging_free:
		vertical_speed = 0.0
	elif is_riding:
		# While riding, vertical movement is driven by root motion/input, not gravity.
		vertical_speed = h_velocity.dot(up_direction)
	elif is_swimming:
		# While swimming, vertical movement is driven by root motion/input, not gravity.
		vertical_speed = h_velocity.dot(up_direction) + swim_vertical_speed
	else:
		vertical_speed += get_gravity().dot(up_direction) * 1.5 * delta
	velocity = h_velocity.slide(up_direction) + (up_direction * vertical_speed)
	last_fall_speed = - vertical_speed
	update_movement_and_rotation(delta)


## Detect if the player is in front of a ledge and can hang from it and/or climb on to it.
func detect_ledge() -> bool:
	# Ledge detection [Raycast]
	var ledge_detected := false
	if not is_on_floor() and ledge_detection_horizontal and ledge_detection_horizontal.is_colliding():
		var forward_direction := -ledge_detection_horizontal.global_transform.basis.z.normalized()
		ledge_detection_vertical.global_position = ledge_detection_horizontal.get_collision_point() + (forward_direction * 0.05) + up_direction
		ledge_detection_vertical.force_raycast_update()
		if ledge_detection_vertical.is_colliding():
			ledge_detection_marker.global_position = ledge_detection_vertical.get_collision_point() + (ledge_detection_vertical.get_collision_normal() * 0.02)
			ledge_detected = true

	# Show/hide ledge detection gizmos.
	if ledge_detected:
		climbing_on_target = ledge_detection_marker.global_position
		ledge_detection_horizontal.show()
		ledge_detection_marker.show()
	else:
		clear_ledge_visuals()

	return ledge_detected


## Called by the animation(s) using "Call Method Track" to execute the jump logic at the right time. 
func execute_jump() -> void:
	if not is_jump_queued:
		return
	# A rideable applies its own jump on the press; here the keyframe only clears the queue
	if not is_riding:
		velocity = velocity.slide(up_direction) + (up_direction * 5.0)
	is_jump_queued = false
	is_jumping = true
	# Flip flags are only needed to enter the flip animation state, so clear them here.
	is_front_flipping = false
	is_back_flipping = false


## Snaps the model orientation to face the given direction on the movement plane.
func rotate_model_to_direction(dir: Vector3) -> void:
	var horizontal_dir: Vector3 = dir.slide(up_direction)
	if horizontal_dir.length_squared() > 0.001:
		horizontal_dir = horizontal_dir.normalized()
		var q_from: Quaternion = orientation.basis.get_rotation_quaternion()
		var q_to: Quaternion = Basis.looking_at(-horizontal_dir, up_direction).get_rotation_quaternion()
		orientation.basis = Basis(q_from.slerp(q_to, 1.0))
		player_model.global_transform.basis = orientation.basis


## Smoothly turns the model orientation toward the given direction on the movement plane.
func turn_model_toward_direction(dir: Vector3, delta: float) -> void:
	var horizontal_dir: Vector3 = dir.slide(up_direction)
	if horizontal_dir.length_squared() > 0.001:
		horizontal_dir = horizontal_dir.normalized()
		var q_from: Quaternion = orientation.basis.get_rotation_quaternion()
		var q_to: Quaternion = Basis.looking_at(-horizontal_dir, up_direction).get_rotation_quaternion()
		var rotate_weight: float = clampf(delta * rotation_interpolate_speed, 0.0, 1.0)
		orientation.basis = Basis(q_from.slerp(q_to, rotate_weight))
		player_model.global_transform.basis = orientation.basis


## Starts charging a throw when the shoot button is pressed. (Delegates to [HeldObject].)
func start_charging_throw() -> void:
	if held_object:
		held_object.start_charging_throw()


## Called when the shoot button is released while charging a throw. (Delegates to [HeldObject].)
func release_charging_throw() -> void:
	if held_object:
		held_object.release_charging_throw()


## Updates the Steam persona label for the current lobby size.
func _update_steam_persona_name() -> void:
	steam_persona_name.hide()
	if OS.has_feature("web") or not Engine.has_singleton("Steam"):
		return
	var steamworks: Node = get_node_or_null("/root/Steamworks")
	if steamworks == null or steamworks.get("steam_id") == 0:
		return
	var steam_singleton: Object = Engine.get_singleton("Steam")
	var lobby_id: int = steamworks.get("lobby_id")
	if lobby_id == 0 or steam_singleton.getNumLobbyMembers(lobby_id) <= 1:
		return
	var persona_name: String = steam_singleton.getPersonaName()
	if not persona_name.is_empty():
		steam_persona_name.text = persona_name
		steam_persona_name.show()


## Refreshes the Steam persona label when a lobby member joins or leaves.
func _on_steam_lobby_chat_update(
		lobby_id: int,
		_changed_id: int,
		_making_change_id: int,
		_chat_state: int,
) -> void:
	var steamworks: Node = get_node_or_null("/root/Steamworks")
	if steamworks == null or steamworks.get("lobby_id") != lobby_id:
		return
	_update_steam_persona_name()


## Called by throw animation(s) using "Call Method Track" to throw the held object at the right frame.
func execute_throw() -> void:
	if held_object:
		held_object.execute_throw()



## Gets the grounded locomotion state that matches the current equipment and intent.
## Grouped states use "Group/State" travel paths.
func get_grounded_locomotion_state() -> StringName:
	if is_exhausted and is_on_floor() and not has_move_input:
		return &"HeavyBreathing"
	if is_crouching:
		return &"CrouchingLocomotion"
	if equipped_axe_2h or equipped_fishing_rod or equipped_staff or equipped_sword_2h:
		return &"GreatSword/GreatSwordLocomotion"
	if equipped_bow:
		if is_shooting:
			return &"Bow/ArcheryLocomotion"
		return &"Bow/BowLocomotion"
	if equipped_axe_1h or equipped_dagger or equipped_shield or equipped_sword_1h:
		return &"Shield/ShieldLocomotion"
	if equipped_pistol:
		return &"Pistol/PistolLocomotion"
	if equipped_rifle:
		return &"Rifle/RifleLocomotion"
	if is_boxing:
		return &"Boxing/BoxingLocomotion"
	return &"StandingLocomotion"


## True if the state is the deepest current locomotion node or queued in a travel path.
func is_locomotion_state_active_or_queued(state_name: String) -> bool:
	var root_playback: AnimationNodeStateMachinePlayback = locomotion_state
	if root_playback == null:
		return false
	var playback: AnimationNodeStateMachinePlayback = active_locomotion_playback
	if String(playback.get_current_node()) == state_name:
		return true
	if StringName(state_name) in playback.get_travel_path():
		return true
	return StringName(state_name) in root_playback.get_travel_path()


## Travels the locomotion state machine; supports "Group/State" paths into nested machines.
func travel_locomotion(state_path: String) -> void:
	var root_playback: AnimationNodeStateMachinePlayback = locomotion_state
	if root_playback == null:
		return
	var parts: PackedStringArray = state_path.split("/")
	var entering_group: bool = parts[0] in LOCOMOTION_GROUPS \
			and String(root_playback.get_current_node()) != parts[0]
	root_playback.travel(parts[0])
	if parts.size() > 1:
		# On fresh entry of an undrawn group, let the Start edges route through the draw.
		if entering_group and drawn_weapon_group != parts[0] and parts[1].ends_with("Locomotion"):
			return
		var group_playback: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/LocomotionStateMachine/" + parts[0] + "/playback")
		if group_playback:
			group_playback.travel(parts[1])


## Wired to Abilities.cast_started: holds the weapon group's Spell Casting channel for the cast time; unarmed,
## where no such clip exists, the Ready To Cast Spell emote holds the upper body instead.
func _on_abilities_cast_started(ability: Ability) -> void:
	var state_path: String = ability.get_cast_state(get_spell_group(), true)
	if not state_path.is_empty():
		_travel_spell_state(state_path)
	elif is_standing and ability.cast_style != Ability.CastStyle.NONE and get_spell_group().is_empty():
		_start_channel_emote()


## Wired to Chat.typing_changed: gameplay input stays blocked while the chat input row is open.
func _on_chat_typing_changed(typing: bool) -> void:
	is_typing = typing


## Wired to Abilities.ability_activated: plays the cast (or power up) clip for the ability's cast style.
func _on_abilities_ability_activated(ability: Ability) -> void:
	_end_channel_emote()
	_travel_spell_state(ability.get_cast_state(get_spell_group(), false))


## Wired to Abilities.cast_interrupted: drops the channel pose.
func _on_abilities_cast_interrupted(_ability: Ability) -> void:
	_end_channel_emote()
	if not is_standing or not current_locomotion_node.ends_with("SpellCasting"):
		return
	var stance: String = String(get_grounded_locomotion_state())
	if active_locomotion_playback.get_fading_from_node() != &"":
		# A travel is dropped while the channel is still fading in, so snap back to the stance
		active_locomotion_playback.start(stance.get_file())
	else:
		travel_locomotion(stance)


## The locomotion group spell clips are picked for ("Shield", "GreatSword", ...), or "" unarmed.
func get_spell_group() -> String:
	var node: String = String(locomotion_state.get_current_node()) if locomotion_state else ""
	return node if node in LOCOMOTION_GROUPS else ""


## Spell clips only exist for standing on the ground; anywhere else the cast plays no pose.
func _travel_spell_state(state_path: String) -> void:
	if is_standing and not state_path.is_empty():
		travel_locomotion(state_path)


## Holds the Ready To Cast Spell pose on the emote layer, the way a carried object does.
func _start_channel_emote() -> void:
	var emote_state: AnimationNodeStateMachinePlayback = animation_tree.get(EMOTE_STATE_PLAYBACK_PATH)
	if emote_state == null or (held_object and held_object.is_holding_object()):
		return
	animation_tree.set("parameters/EmoteSpineBlend2/blend_amount", 1.0)
	emote_state.start(CAST_CHANNEL_EMOTE)
	is_emoting = true
	has_started_emoting = false


## Lets go of the channel pose, if it is the one showing.
func _end_channel_emote() -> void:
	var emote_state: AnimationNodeStateMachinePlayback = animation_tree.get(EMOTE_STATE_PLAYBACK_PATH)
	if emote_state and emote_state.get_current_node() == CAST_CHANNEL_EMOTE and not (held_object and held_object.is_holding_object()):
		emote_state.start("Idle")
		animation_tree.set("parameters/EmoteSpineBlend2/blend_amount", 0.0)
		is_emoting = false
		has_started_emoting = false


## True if the equipment matching the given locomotion group is currently equipped.
func is_group_equipment_equipped(group_name: String) -> bool:
	match group_name:
		"Bow":
			return equipped_bow
		"Boxing":
			return is_boxing
		"GreatSword":
			return equipped_axe_2h or equipped_fishing_rod or equipped_staff or equipped_sword_2h
		"Pistol":
			return equipped_pistol
		"Rifle":
			return equipped_rifle
		"Shield":
			return equipped_axe_1h or equipped_dagger or equipped_shield or equipped_sword_1h
	return false


static var _weather_fx_script: Script = null
static var _weather_fx_checked: bool = false

## Soft WeatherFX interop: returns the global precipitation strength, or 0.0 when the addon is absent.
func get_precipitation_strength() -> float:
	if not _weather_fx_checked:
		_weather_fx_checked = true
		var weather_fx_path := "res://addons/weather_fx/scripts/weather_fx.gd"
		if ResourceLoader.exists(weather_fx_path):
			_weather_fx_script = load(weather_fx_path) as Script
	if _weather_fx_script:
		return _weather_fx_script.get_precipitation_strength()
	return 0.0


## Returns true if the player is currently inside an updraft or thermal air column.
func is_in_updraft() -> bool:
	if not is_inside_tree():
		return false
	var tree := get_tree()
	if tree == null:
		return false

	var pool: Array[Node] = []
	pool.append_array(tree.get_nodes_in_group("Updraft"))
	pool.append_array(tree.get_nodes_in_group("Thermal"))

	for node in pool:
		if node is Area3D:
			var area := node as Area3D
			# Skip burned-out/disabled thermals so ghost updrafts never grant lift
			if not area.monitoring:
				continue
			if area.overlaps_body(self):
				return true
			var col_shape: CollisionShape3D = area.find_child("CollisionShape3D", true, false) as CollisionShape3D
			if col_shape and col_shape.shape:
				var local_p := area.to_local(global_position)
				if col_shape.shape is BoxShape3D:
					var box := col_shape.shape as BoxShape3D
					var half := box.size * 0.5
					if abs(local_p.x) <= half.x and abs(local_p.y) <= half.y and abs(local_p.z) <= half.z:
						return true
				elif col_shape.shape is CylinderShape3D:
					var cyl := col_shape.shape as CylinderShape3D
					var half_h := cyl.height * 0.5
					var horiz_d := Vector2(local_p.x, local_p.z).length()
					if abs(local_p.y) <= half_h and horiz_d <= cyl.radius:
						return true
				elif col_shape.shape is CapsuleShape3D:
					var cap := col_shape.shape as CapsuleShape3D
					var half_h := cap.height * 0.5
					var horiz_d := Vector2(local_p.x, local_p.z).length()
					if abs(local_p.y) <= half_h and horiz_d <= cap.radius:
						return true
			elif area.global_position.distance_to(global_position) < 8.0:
				return true
	return false


## Returns the distance in meters to the nearest active updraft or thermal air source.
func get_nearest_updraft_distance() -> float:
	if not is_inside_tree():
		return 999.0
	var tree := get_tree()
	if tree == null:
		return 999.0

	var min_d: float = 999.0
	var pool: Array[Node] = []
	pool.append_array(tree.get_nodes_in_group("Updraft"))
	pool.append_array(tree.get_nodes_in_group("Thermal"))

	for node in pool:
		if node is Area3D:
			var area := node as Area3D
			if area.monitoring or area.monitorable:
				var d := area.global_position.distance_to(global_position)
				if d < min_d:
					min_d = d
	return min_d


var updraft_aura_vfx: Node3D = null

func _setup_updraft_vfx() -> void:
	var vfx_scene_path := "res://addons/weather_fx/assets/vfx/wind/Scenes/VFX_AirFlowUP.tscn"
	if ResourceLoader.exists(vfx_scene_path):
		var scene := load(vfx_scene_path) as PackedScene
		if scene:
			updraft_aura_vfx = scene.instantiate() as Node3D
			updraft_aura_vfx.name = "UpdraftAuraVFX"
			updraft_aura_vfx.visible = false
			updraft_aura_vfx.scale = Vector3(1.2, 1.6, 1.2)
			add_child(updraft_aura_vfx)
			for p in updraft_aura_vfx.find_children("*", "GPUParticles3D", true, false):
				if p is GPUParticles3D:
					p.emitting = false


func _update_updraft_vfx() -> void:
	if not is_instance_valid(updraft_aura_vfx):
		return

	var should_show: bool = is_in_updraft() or get_nearest_updraft_distance() <= 5.0
	if updraft_aura_vfx.visible != should_show:
		updraft_aura_vfx.visible = should_show
		for p in updraft_aura_vfx.find_children("*", "GPUParticles3D", true, false):
			if p is GPUParticles3D:
				p.emitting = should_show


## Gets the player's forward direction projected onto the movement plane.
func get_facing_direction() -> Vector3:
	var facing_direction := -player_model.global_transform.basis.z
	facing_direction = facing_direction.slide(up_direction)
	if facing_direction.length_squared() <= 0.001:
		return Vector3.ZERO
	return facing_direction.normalized()


## Called by the animation(s) using "Call Method Track" to play footstep sound effects at the right time.
func sfx_footsteps_play():
	if is_on_floor() and paraglider_raycast.is_colliding() and not is_ragdolling:
		var collider := paraglider_raycast.get_collider() as Node3D
		if audio:
			audio.play_footstep(collider)


## Called by the animation(s) using "Call Method Track" to play sliding footstep sound effects at the right time.
func sfx_footsteps_slide_play():
	if is_on_floor() and paraglider_raycast.is_colliding():
		var collider := paraglider_raycast.get_collider() as Node3D
		if audio:
			audio.play_slide(collider)


## Reset the attack sequence when the attack sequence timer times out.
func _on_attack_sequence_timer_timeout() -> void:
	attack_sequence = 0


## Applies the current velocity, moves the player, and updates the orientation to match the up_direction.
func update_movement_and_rotation(delta: float) -> void:
	var current_body_up := global_basis.y
	if not current_body_up.is_equal_approx(up_direction):
		var q_align_body := Quaternion(current_body_up, up_direction)
		global_basis = Basis(q_align_body) * global_basis

	var pre_velocity := velocity
	move_and_slide()

	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_collider() is RigidBody3D:
			var rb := c.get_collider() as RigidBody3D
			if rb != held_rigidbody:
				var push_dir := -c.get_normal()
				var velocity_proj := pre_velocity.dot(push_dir)
				var rb_velocity_proj := rb.linear_velocity.dot(push_dir)
				var relative_velocity_proj := velocity_proj - rb_velocity_proj
				if relative_velocity_proj > 0.0:
					var effective_mass := (mass * rb.mass) / (mass + rb.mass)
					rb.apply_impulse(push_dir * relative_velocity_proj * effective_mass * push_force, c.get_position() - rb.global_position)

	if is_on_floor() and not is_swimming and not is_falling:
		last_safe_shore_position = global_position


	orientation.origin = Vector3() # Clear accumulated root motion displacement (was applied to speed).
	orientation = orientation.orthonormalized() # Orthonormalize orientation.

	# Smoothly align character body and model orientation Y-axis with up_direction
	var current_up := orientation.basis.y
	if not current_up.is_equal_approx(up_direction):
		var next_up := current_up.slerp(up_direction, delta * 10.0).normalized()
		var q_align := Quaternion(current_up, next_up)
		orientation.basis = Basis(q_align) * orientation.basis


	# Rotate the Player Model (unless entering/exiting a vehicle or ragdolling)
	if not (is_riding and (is_mounting or is_dismounting)) and not is_ragdolling:
		if is_zero_approx(model_pitch):
			player_model.global_transform.basis = orientation.basis
			player_model.transform.origin = initial_player_model_transform.origin
		else:
			# Pitch about a hip-height pivot so the body doesn't sweep around the feet like a ball
			var pitched_basis: Basis = orientation.basis * Basis(Vector3.RIGHT, model_pitch)
			var pivot_local := Vector3(0.0, model_pitch_pivot_height, 0.0)
			var base_origin: Vector3 = to_global(initial_player_model_transform.origin)
			var pivot_global: Vector3 = base_origin + (orientation.basis * pivot_local)
			player_model.global_transform = Transform3D(pitched_basis, pivot_global - (pitched_basis * pivot_local))
		var model_facing_basis: Basis = orientation.basis.rotated(up_direction, PI)
		var rotated_basis: Basis = model_facing_basis * initial_separation_ray_transform.basis
		var rotated_origin: Vector3 = global_position + (model_facing_basis * initial_separation_ray_transform.origin)
		separation_ray_shape.global_transform = Transform3D(rotated_basis, rotated_origin)


## Called by a water Area3D when the player enters water.
func enter_water(water_area: Area3D = null) -> void:
	current_water_area = water_area
	if not is_swimming and not is_riding and not is_ragdolling:
		if state_machine:
			state_machine.travel(current_state, NodeStateMachine.States.SWIMMING)


## Called by a water Area3D when the player exits water.
func exit_water(water_area: Area3D = null) -> void:
	if water_area == null or water_area == current_water_area:
		current_water_area = null
		if is_swimming:
			is_swimming = false
			if state_machine:
				state_machine.travel(NodeStateMachine.States.SWIMMING, NodeStateMachine.States.STANDING if is_on_floor() else NodeStateMachine.States.FALLING)


## Update volume on all SFX footstep AudioStreamPlayer3D nodes under player.
func update_sfx_volume(value: float) -> void:
	if audio:
		audio.set_sfx_volume(value)


## Update volume on RadiOtPlayer3D node under player.
func update_music_volume(value: float) -> void:
	if audio:
		audio.set_music_volume(value)


const STEAM_VOICE_RESULT_OK: int = 0 ## Mirrors Steam.VOICE_RESULT_OK (Steam class is absent on web exports).


## Returns the Steam singleton when present and running, otherwise null.
func _get_steam_running() -> Object:
	if not Engine.has_singleton("Steam"):
		return null
	var steam: Object = Engine.get_singleton("Steam")
	return steam if steam.isSteamRunning() else null


## Start push-to-talk voice broadcasting
func start_broadcasting() -> void:
	is_broadcasting = true
	if voice_chat_indicator:
		voice_chat_indicator.show()
	var steam: Object = _get_steam_running()
	if steam:
		steam.startVoiceRecording()
		var my_id: int = steam.getSteamID()
		if my_id > 0:
			steam.setInGameVoiceSpeaking(my_id, true)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_set_voice_indicator.rpc(true)


## Stop push-to-talk voice broadcasting
func stop_broadcasting() -> void:
	is_broadcasting = false
	if voice_chat_indicator:
		voice_chat_indicator.hide()
	var steam: Object = _get_steam_running()
	if steam:
		steam.stopVoiceRecording()
		var my_id: int = steam.getSteamID()
		if my_id > 0:
			steam.setInGameVoiceSpeaking(my_id, false)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_set_voice_indicator.rpc(false)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_voice_packet(compressed_buffer: PackedByteArray) -> void:
	var steam: Object = _get_steam_running()
	if steam == null or compressed_buffer.is_empty():
		return
	var sample_rate: int = steam.getVoiceOptimalSampleRate()
	if sample_rate <= 0:
		sample_rate = 48000
	var decompressed: Dictionary = steam.decompressVoice(compressed_buffer, sample_rate)
	if decompressed.get("result") == STEAM_VOICE_RESULT_OK:
		var uncompressed: PackedByteArray = decompressed.get("uncompressed", PackedByteArray())
		if uncompressed.is_empty():
			return
		if voice_playback == null and voice_audio_player:
			if not voice_audio_player.playing:
				voice_audio_player.play()
			voice_playback = voice_audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
		if voice_playback:
			var sample_count: int = uncompressed.size() / 2
			var frames = PackedVector2Array()
			frames.resize(sample_count)
			for i in range(sample_count):
				var sample_val: float = float(uncompressed.decode_s16(i * 2)) / 32768.0
				frames[i] = Vector2(sample_val, sample_val)
			var frames_available: int = voice_playback.get_frames_available()
			if frames.size() > frames_available:
				frames = frames.slice(0, frames_available)
			if not frames.is_empty():
				voice_playback.push_buffer(frames)


@rpc("any_peer", "call_remote", "reliable")
func _set_voice_indicator(is_speaking: bool) -> void:
	if voice_chat_indicator:
		voice_chat_indicator.visible = is_speaking


## Applies the synchronized locomotion path ("Group/Node" or "Node") to a puppet's AnimationTree.
func _apply_synced_locomotion_node(state_path: String) -> void:
	var root_playback: AnimationNodeStateMachinePlayback = locomotion_state
	if state_path.is_empty() or root_playback == null:
		return
	var parts: PackedStringArray = state_path.split("/")
	if String(root_playback.get_current_node()) != parts[0]:
		root_playback.travel(parts[0])
	if parts.size() > 1:
		var group_playback: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/LocomotionStateMachine/" + parts[0] + "/playback")
		if group_playback and String(group_playback.get_current_node()) != parts[1]:
			group_playback.travel(parts[1])


## Applies the synchronized blend position to the puppet's current locomotion blend space (1D spaces take the forward axis).
func _apply_synced_blend_position(blend_pos: Vector2) -> void:
	if sync_locomotion_node.is_empty():
		return
	var path: String = "parameters/LocomotionStateMachine/" + sync_locomotion_node + "/blend_position"
	var current: Variant = animation_tree.get(path)
	if current is Vector2:
		animation_tree.set(path, blend_pos)
	elif current is float:
		animation_tree.set(path, blend_pos.y if blend_pos.y != 0.0 else blend_pos.length())


## Points the spine [LookAtModifier3D] at [param target], or clears it when [param target] is null.
## [HeldObject] (carried body) and [Bow] (crosshair while aiming) are the only callers.
func set_look_at_target(target: Node3D) -> void:
	var modifier: LookAtModifier3D = look_at_modifier as LookAtModifier3D
	if modifier == null:
		return
	modifier.target_node = modifier.get_path_to(target) if target else NodePath("")
	modifier.active = target != null


@export_category("Combat")
@export var skill_level: int = 0 ## Marksmanship: shrinks the spread of ranged equipment per its [Accuracy] resource (0 novice, expert at the resource's expert_level).
@export_category("Traversal")
@export var stealth_transparency: float = 0.7 ## How faded the model is while [member is_stealthed]: 1 is invisible.
@export var stealth_fade_time: float = 1.0 ## Seconds the ghost takes to settle in when stealth starts, and to solidify when it ends.
@export var lethal_fall_speed: float = 15.0 ## Landing at or above this downward speed (m/s) ragdolls the player.
@export var wall_leap_horizontal_speed: float = 5.0 ## Horizontal impulse away from the wall on a climbing/hanging back-eject.
@export var wall_leap_vertical_speed: float = 3.5 ## Vertical impulse on a climbing/hanging back-eject.


## Smoothly turns the model to face the wall hit by the horizontal ledge raycast.
func face_wall(delta: float) -> void:
	if ledge_detection_horizontal.is_colliding():
		turn_model_toward_direction(-ledge_detection_horizontal.get_collision_normal(), delta)


## Launches the player away from the wall they are facing (climbing/hanging back-eject).
func leap_off_wall() -> void:
	var wall_normal: Vector3 = player_model.global_transform.basis.z.slide(up_direction).normalized()
	velocity = (wall_normal * wall_leap_horizontal_speed) + (up_direction * wall_leap_vertical_speed)


## Hides the ledge detection gizmos and resets the vertical probe to its default offset.
func clear_ledge_visuals() -> void:
	ledge_detection_vertical.position = Vector3(0, 0, -1)
	ledge_detection_horizontal.hide()
	ledge_detection_marker.hide()


## Gets on [param rideable] (a skateboard, a vehicle, a mount): it takes over movement and camera through the
## [Riding] state until [method dismount].
func mount(rideable: Node3D) -> void:
	if rideable == null or is_riding or state_machine == null:
		return
	riding = rideable
	state_machine.travel(current_state, NodeStateMachine.States.RIDING)


## Gets off whatever is being ridden, through the rideable's get-off animation when it has one;
## [param immediate] skips it (a bail out at speed).
func dismount(immediate: bool = false) -> void:
	if not is_riding or state_machine == null:
		return
	if not immediate:
		var riding_state: Node = state_machine.get_node_or_null("Riding")
		if riding_state and riding_state.has_method("begin_dismount") and riding_state.call("begin_dismount"):
			return
	state_machine.travel(NodeStateMachine.States.RIDING, NodeStateMachine.States.STANDING)


## Re-applies the current state's contextual control labels (after something else borrowed them).
func refresh_contextual_controls() -> void:
	if controls == null or state_machine == null:
		return
	var state_node: NodeStateMachine = state_machine.get_node_or_null(NodePath(NodeStateMachine.get_state_name(current_state))) as NodeStateMachine
	if state_node:
		state_node._on_input_type_changed(controls.current_input_type)


## Whether the current rideable keeps weapons and items holstered (a car does, a board does not).
func riding_blocks_hands() -> bool:
	return is_riding and riding != null and riding.get("blocks_hands") == true


## Teleports the Player to the given transform, clearing motion and restoring the model and collision poses.
func warp_to(target: Transform3D) -> void:
	global_transform = target
	velocity = Vector3.ZERO
	up_direction = target.basis.y.normalized()
	orientation = Transform3D(target.basis, Vector3.ZERO)
	player_model.transform = initial_player_model_transform
	collision_shape.transform = initial_collision_shape_transform


var movement_scale: float = 1.0 ## Fraction of normal movement speed; [method slow] lowers it for a while.
var _slow_timer: SceneTreeTimer


## Slows movement to [param factor] of normal for [param seconds], as a Frostbolt does; lands on the owning peer like a hit.
@rpc("any_peer", "call_local", "reliable")
func slow(factor: float, seconds: float) -> void:
	if not is_multiplayer_authority():
		slow.rpc_id(get_multiplayer_authority(), factor, seconds)
		return
	movement_scale = clampf(factor, 0.0, 1.0)
	_slow_timer = get_tree().create_timer(seconds)
	_slow_timer.timeout.connect(_end_slow.bind(_slow_timer))


func _end_slow(timer: SceneTreeTimer) -> void:
	if timer == _slow_timer: # A newer slow runs on its own timer
		movement_scale = 1.0


const STEALTH_SHADER: Shader = preload("res://addons/3d_player_controller/assets/shaders/stealth.gdshader")

var _stealth_originals: Dictionary[MeshInstance3D, Array] = {} ## Mesh -> its surface override materials before stealth, restored when it ends.
var _stealth_tween: Tween


## Turns every mesh under the skeleton into its ghost, or back. The ghost is the stealth shader carrying the surface's
## own colour and texture: washed pale, tinted cold, drawn after a depth pre-pass so limbs never show through the body.
## Its alpha tweens over [member stealth_fade_time] each way; the original materials return once the fade out lands.
func _apply_stealth_look(stealthed: bool) -> void:
	if _stealth_tween:
		_stealth_tween.kill()
	_stealth_tween = create_tween().set_parallel(true)
	if stealthed:
		for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D"):
			if mesh.mesh == null or _stealth_originals.has(mesh):
				continue
			var originals: Array[Material] = []
			for surface: int in mesh.mesh.get_surface_count():
				originals.append(mesh.get_surface_override_material(surface))
				mesh.set_surface_override_material(surface, _ghost_of(mesh.get_active_material(surface)))
			_stealth_originals[mesh] = originals
	var target_alpha: float = 1.0 - stealth_transparency if stealthed else 1.0
	for ghost: ShaderMaterial in _stealth_ghosts():
		# A method, not the shader_parameter property: it exists only once the shader is compiled, which a headless run never does
		_stealth_tween.tween_method(_set_ghost_alpha.bind(ghost), float(ghost.get_shader_parameter(&"alpha")), target_alpha, stealth_fade_time)
	if not stealthed:
		_stealth_tween.chain().tween_callback(_restore_stealth_materials)


## The stealth shader wearing [param original]'s colours; anything but a StandardMaterial3D ghosts as plain white.
func _ghost_of(original: Material) -> ShaderMaterial:
	var ghost: ShaderMaterial = ShaderMaterial.new()
	ghost.shader = STEALTH_SHADER
	ghost.set_shader_parameter(&"alpha", 1.0)
	if original is StandardMaterial3D:
		var standard: StandardMaterial3D = original as StandardMaterial3D
		ghost.set_shader_parameter(&"albedo_color", standard.albedo_color)
		if standard.albedo_texture:
			ghost.set_shader_parameter(&"albedo_texture", standard.albedo_texture)
			ghost.set_shader_parameter(&"use_texture", true)
	return ghost


func _set_ghost_alpha(alpha: float, ghost: ShaderMaterial) -> void:
	ghost.set_shader_parameter(&"alpha", alpha)


func _stealth_ghosts() -> Array[ShaderMaterial]:
	var ghosts: Array[ShaderMaterial] = []
	for mesh: MeshInstance3D in _stealth_originals:
		if not is_instance_valid(mesh):
			continue
		for surface: int in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_surface_override_material(surface)
			if material is ShaderMaterial and (material as ShaderMaterial).shader == STEALTH_SHADER:
				ghosts.append(material)
	return ghosts


func _restore_stealth_materials() -> void:
	for mesh: MeshInstance3D in _stealth_originals:
		if not is_instance_valid(mesh):
			continue
		var originals: Array = _stealth_originals[mesh]
		for surface: int in originals.size():
			mesh.set_surface_override_material(surface, originals[surface])
	_stealth_originals.clear()


## Damage lands on the owning peer: it costs health, shoves away from [param from] and rumbles the pad.
## Enemies run on the server, so their hits arrive here through the RPC.
@rpc("any_peer", "call_local", "reliable")
func take_hit(damage: float, from: Vector3) -> void:
	if not is_multiplayer_authority():
		take_hit.rpc_id(get_multiplayer_authority(), damage, from)
		return
	if not health.is_alive():
		return
	health.damage(damage, from)
	var away: Vector3 = (global_position - from).slide(up_direction)
	if away.length_squared() > 0.001:
		velocity += away.normalized() * 4.0 + up_direction * 1.5
	controls.rumble(0.6, 0.8, 0.25)


var hunters: Array[Node] = [] ## Enemies currently targeting this Player; mana regenerates only when it is empty.


## Enemies report starting and stopping their hunt; lands on the owning peer, where mana lives.
@rpc("any_peer", "call_local", "reliable")
func hunted_by(enemy_path: NodePath, hunting: bool) -> void:
	if not is_multiplayer_authority():
		hunted_by.rpc_id(get_multiplayer_authority(), enemy_path, hunting)
		return
	var enemy: Node = get_node_or_null(enemy_path)
	if hunting and enemy and not hunters.has(enemy):
		hunters.append(enemy)
	elif not hunting:
		hunters.erase(enemy)
	for hunter: Node in hunters.duplicate():
		if not is_instance_valid(hunter):
			hunters.erase(hunter)
	health.regen_paused = not hunters.is_empty()


## True while a heal would do something; abilities check it before spending anything.
func can_heal() -> bool:
	return health.can_heal()


## Restores health on the owning peer, so one player can heal another; false only when already full here.
@rpc("any_peer", "call_local", "reliable")
func heal(amount: float) -> bool:
	if not is_multiplayer_authority():
		heal.rpc_id(get_multiplayer_authority(), amount)
		return true
	return health.heal(amount)


## Called by a landing [Projectile]; the Player is a valid target for enemy arrows and bullets.
func register_projectile_hit(projectile: Projectile, point: Vector3, _normal: Vector3) -> void:
	if projectile.shooter == self:
		return
	# A round on the Head hurtbox kills outright
	var headshot: bool = projectile.hit_part != null and projectile.hit_part.name == "Head"
	take_hit(health.max_health if headshot else projectile.damage, point)


## Wired to Health.died: the body drops into the ragdoll and the RespawnTimer brings the Player back.
func _on_health_died() -> void:
	if not is_multiplayer_authority():
		return
	# Death always drops the body, even where falls are set not to ragdoll
	_ragdoll_was_enabled = enable_ragdoll
	enable_ragdoll = true
	state_machine.travel(current_state, NodeStateMachine.States.RAGDOLLING)
	respawn_timer.start()


## Back on your feet at the spawn point with full health.
func respawn() -> void:
	hunters.clear()
	health.regen_paused = false
	health.health = health.max_health
	state_machine.travel(current_state, NodeStateMachine.States.STANDING)
	enable_ragdoll = _ragdoll_was_enabled
	warp_to(initial_transform)
