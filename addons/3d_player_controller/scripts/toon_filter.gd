class_name ToonFilter
extends MeshInstance3D
## Screen-space toon shading under the Player's camera, in two looks. NEWSPAPER is this full-screen quad with a spatial
## post-process shader that posterises the opaque scene into a few luminance bands and inks outlines where the depth
## buffer jumps; it reads only the screen and depth textures, so it runs in every renderer, and it is drawn in the 3D
## pass, so every CanvasLayer (the HUD, the menus) sits above it. CEL is a [CelCompositorEffect] on the camera's
## [member Camera3D.compositor]: hard light bands and bold ink from depth and normal discontinuities, Forward+ only.
## Purely local: a video setting kept in [PlayerSettingsResource], never replicated. A camera compositor replaces the
## [WorldEnvironment]'s, so CEL copies that one's effects (the volumetric clouds) in ahead of its own and hands the
## view back to it when it leaves. The "toggle_toon" action ([F6]) cycles Off, Newspaper, Cel (Cel skipped off
## Forward+); the Video settings' "Toon shading" option picks one directly.

signal toggled(enabled: bool) ## The filter went on or off, by the key or the setting.
signal mode_changed(mode: Mode) ## The look changed, by the key or the setting.

enum Mode { OFF, NEWSPAPER, CEL }

const FORWARD_PLUS: String = "forward_plus"

@export var mode: Mode = Mode.OFF: ## The current look; the saved setting overrides this at start.
	set = set_mode

var enabled: bool: ## True in any mode but OFF; setting it picks NEWSPAPER or OFF.
	get:
		return mode != Mode.OFF
	set(value):
		set_mode(Mode.NEWSPAPER if value else Mode.OFF)

var compositor: Compositor ## The compositor CEL puts on the camera, the world's effects plus the cel one; null in the other modes.


func _ready() -> void:
	set_process_unhandled_input(is_multiplayer_authority())
	set_mode(PlayerSettingsResource.load_or_create().toon_mode as Mode)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_toon"):
		cycle()
		get_viewport().set_input_as_handled()


## The renderer in use; overridden by tests to cover both cycles headless.
func _rendering_method() -> String:
	return RenderingServer.get_current_rendering_method()


## CEL needs the Forward+ compositor's normal-roughness buffer.
func is_cel_available() -> bool:
	return _rendering_method() == FORWARD_PLUS


## Shows the quad for NEWSPAPER, puts the [CelCompositorEffect] on the camera for CEL and takes it off otherwise. Asking
## for CEL where it is not available gives NEWSPAPER. Does not save; see [method cycle] and the Video settings.
func set_mode(value: Mode) -> void:
	if value == Mode.CEL and not is_cel_available():
		value = Mode.NEWSPAPER
	mode = value
	visible = mode == Mode.NEWSPAPER
	_apply_compositor()
	toggled.emit(enabled)
	mode_changed.emit(mode)


## Steps to the next look, skipping CEL off Forward+, and saves the choice with the other video settings.
func cycle() -> void:
	var next: Mode = ((mode + 1) % Mode.size()) as Mode
	if next == Mode.CEL and not is_cel_available():
		next = Mode.OFF
	set_mode(next)
	var settings: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	settings.toon_mode = mode
	settings.save()


## Flips between OFF and NEWSPAPER and saves; kept for callers of the old two-state filter.
func toggle() -> void:
	set_mode(Mode.OFF if enabled else Mode.NEWSPAPER)
	var settings: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	settings.toon_mode = mode
	settings.save()


func _apply_compositor() -> void:
	var camera: Camera3D = get_parent() as Camera3D
	if not is_instance_valid(camera):
		return
	if mode == Mode.CEL:
		if compositor == null:
			compositor = Compositor.new()
			var effects: Array[CompositorEffect] = _world_effects()
			effects.append(CelCompositorEffect.new())
			compositor.compositor_effects = effects
		camera.compositor = compositor
	elif compositor != null:
		if camera.compositor == compositor:
			camera.compositor = null
		compositor = null # Drops the cel effect, which frees its shader; the world's effects live on in its compositor


## The effects of the first [WorldEnvironment]'s compositor (the volumetric clouds on Forward+), which a camera
## compositor would otherwise replace. Copied, not moved: the WorldEnvironment keeps its own.
func _world_effects() -> Array[CompositorEffect]:
	var effects: Array[CompositorEffect] = []
	if not is_inside_tree():
		return effects
	var environments: Array[Node] = get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if environments.is_empty():
		return effects
	var environment: WorldEnvironment = environments[0] as WorldEnvironment
	if environment.compositor != null:
		effects.append_array(environment.compositor.compositor_effects)
	return effects
