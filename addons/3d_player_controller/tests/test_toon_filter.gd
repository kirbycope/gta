extends IntegrationTestBase

## Purpose: the ToonFilter's quad shader compiles, the filter starts off, the toggle_toon action and its [F6] key cycle
## Off, Newspaper, Cel (Cel skipped off Forward+), Newspaper shows the quad while Cel puts a CelCompositorEffect on the
## camera and takes it off again, the Video settings option and the key stay in step, the choice is saved in
## user://settings.tres (backed up and restored here), and the CelCompositorEffect stays inert without a RenderingDevice.

const TOON_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/toon_filter.tscn")
const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const VIDEO_SETTINGS_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/video_settings.tscn")

var _backup: PackedByteArray
var _had_file: bool


## A filter that believes it runs on the given renderer, so both cycles are covered headless.
class RendererFilter:
	extends ToonFilter

	var renderer: String

	func _init(rendering_method: String) -> void:
		renderer = rendering_method

	func _rendering_method() -> String:
		return renderer


func before_each() -> void:
	_had_file = FileAccess.file_exists(PlayerSettingsResource.SAVE_PATH)
	if _had_file:
		_backup = FileAccess.get_file_as_bytes(PlayerSettingsResource.SAVE_PATH)
	DirAccess.remove_absolute(PlayerSettingsResource.SAVE_PATH)
	PlayerSettingsResource._cached = null


func after_each() -> void:
	if _had_file:
		var file: FileAccess = FileAccess.open(PlayerSettingsResource.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(_backup)
		file.close()
		ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_REPLACE)
	else:
		DirAccess.remove_absolute(PlayerSettingsResource.SAVE_PATH)
	PlayerSettingsResource._cached = null


func _saved_mode() -> int:
	var loaded: PlayerSettingsResource = ResourceLoader.load(PlayerSettingsResource.SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	return loaded.toon_mode


## A Camera3D with the filter from the scene under it, the way the Player carries it.
func _camera_with_filter() -> Camera3D:
	var camera: Camera3D = Camera3D.new()
	add_child_autofree(camera)
	camera.add_child(TOON_SCENE.instantiate())
	return camera


func test_the_shader_compiles_with_its_dials() -> void:
	var filter: ToonFilter = TOON_SCENE.instantiate()
	add_child_autofree(filter)
	var material: ShaderMaterial = filter.mesh.surface_get_material(0)
	var names: Array[String] = []
	for parameter: Dictionary in RenderingServer.get_shader_parameter_list(material.shader.get_rid()):
		names.append(parameter.name)
	# A shader that failed to compile lists no uniforms at all
	for uniform: String in ["bands", "softness", "outline_color", "outline_threshold", "outline_thickness", "strength"]:
		assert_has(names, uniform, "The toon shader compiled and exposes " + uniform)
	assert_eq(material.render_priority, Material.RENDER_PRIORITY_MIN, "Drawn first among the transparents, so water and VFX draw over it")
	assert_false(filter.visible, "Off by default")
	assert_eq(filter.mode, ToonFilter.Mode.OFF)
	assert_false(filter.enabled)


func test_the_key_cycles_off_newspaper_cel_on_forward_plus() -> void:
	var filter: ToonFilter = RendererFilter.new("forward_plus")
	add_child_autofree(filter)
	watch_signals(filter)
	assert_true(filter.is_cel_available())
	filter.cycle()
	assert_eq(filter.mode, ToonFilter.Mode.NEWSPAPER, "Off goes to Newspaper")
	assert_signal_emitted_with_parameters(filter, "mode_changed", [ToonFilter.Mode.NEWSPAPER])
	assert_signal_emitted_with_parameters(filter, "toggled", [true])
	assert_eq(_saved_mode(), ToonFilter.Mode.NEWSPAPER, "The choice is saved with the other video settings")
	filter.cycle()
	assert_eq(filter.mode, ToonFilter.Mode.CEL, "Newspaper goes to Cel")
	assert_eq(_saved_mode(), ToonFilter.Mode.CEL)
	filter.cycle()
	assert_eq(filter.mode, ToonFilter.Mode.OFF, "Cel goes back to Off")
	assert_signal_emitted_with_parameters(filter, "toggled", [false])
	assert_eq(_saved_mode(), ToonFilter.Mode.OFF)
	var second: ToonFilter = TOON_SCENE.instantiate()
	add_child_autofree(second)
	assert_eq(second.mode, ToonFilter.Mode.OFF, "A new filter starts from the saved setting")


func test_the_key_skips_cel_off_forward_plus() -> void:
	var filter: ToonFilter = RendererFilter.new("gl_compatibility")
	add_child_autofree(filter)
	assert_false(filter.is_cel_available())
	filter.cycle()
	assert_eq(filter.mode, ToonFilter.Mode.NEWSPAPER, "Off goes to Newspaper")
	filter.cycle()
	assert_eq(filter.mode, ToonFilter.Mode.OFF, "Newspaper goes straight back to Off; no Cel without Forward+")
	assert_eq(_saved_mode(), ToonFilter.Mode.OFF)
	filter.set_mode(ToonFilter.Mode.CEL)
	assert_eq(filter.mode, ToonFilter.Mode.NEWSPAPER, "A saved Cel opened on Compatibility falls back to Newspaper")
	var mobile: ToonFilter = RendererFilter.new("mobile")
	add_child_autofree(mobile)
	assert_false(mobile.is_cel_available(), "Mobile has no compositor effects either")


func test_newspaper_shows_the_quad_and_cel_puts_the_effect_on_the_camera() -> void:
	var camera: Camera3D = _camera_with_filter()
	var filter: ToonFilter = camera.get_child(0)
	assert_null(camera.compositor, "No compositor while off")
	filter.set_mode(ToonFilter.Mode.NEWSPAPER)
	assert_true(filter.visible, "Newspaper shows the quad")
	assert_null(camera.compositor, "and needs no compositor")
	filter.set_mode(ToonFilter.Mode.CEL)
	assert_false(filter.visible, "Cel hides the quad")
	assert_not_null(camera.compositor, "Cel puts a compositor on the camera")
	assert_eq(camera.compositor.compositor_effects.size(), 1, "with one effect")
	assert_true(camera.compositor.compositor_effects[0] is CelCompositorEffect, "the CelCompositorEffect")
	assert_same(camera.compositor, filter.compositor)
	filter.set_mode(ToonFilter.Mode.NEWSPAPER)
	assert_null(camera.compositor, "Leaving Cel takes the compositor off the camera")
	assert_null(filter.compositor, "and drops it")
	assert_true(filter.visible)
	filter.set_mode(ToonFilter.Mode.CEL)
	filter.set_mode(ToonFilter.Mode.OFF)
	assert_null(camera.compositor, "Off takes it off too")
	assert_false(filter.visible)


func test_cel_keeps_the_world_environments_effects() -> void:
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.compositor = Compositor.new()
	var clouds: CompositorEffect = CompositorEffect.new() # Stands in for the SunshineClouds effect
	environment.compositor.compositor_effects = [clouds]
	add_child_autofree(environment)
	var camera: Camera3D = _camera_with_filter()
	var filter: ToonFilter = camera.get_child(0)
	filter.set_mode(ToonFilter.Mode.CEL)
	assert_eq(camera.compositor.compositor_effects.size(), 2, "A camera compositor replaces the WorldEnvironment's, so its effects are carried over")
	assert_same(camera.compositor.compositor_effects[0], clouds, "the world's effect first")
	assert_true(camera.compositor.compositor_effects[1] is CelCompositorEffect, "then the cel effect")
	assert_eq(environment.compositor.compositor_effects.size(), 1, "Copied, not moved")
	filter.set_mode(ToonFilter.Mode.OFF)
	assert_null(camera.compositor, "Off hands the view back to the WorldEnvironment's compositor")
	assert_same(environment.compositor.compositor_effects[0], clouds, "which still has its effect")
	filter.set_mode(ToonFilter.Mode.CEL)
	assert_eq(camera.compositor.compositor_effects.size(), 2, "and Cel picks it up again")
	filter.set_mode(ToonFilter.Mode.NEWSPAPER)
	assert_null(camera.compositor)


func test_the_cel_effect_is_inert_without_a_rendering_device() -> void:
	assert_null(RenderingServer.get_rendering_device(), "Headless has no RenderingDevice, so the GLSL is never compiled here")
	var effect: CelCompositorEffect = CelCompositorEffect.new()
	assert_eq(effect.effect_callback_type, CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT)
	assert_true(effect.needs_normal_roughness, "Asks Forward+ for the normal buffer the creases are inked from")
	assert_true(effect.access_resolved_color)
	assert_true(effect.access_resolved_depth)
	assert_false(effect.shader.is_valid(), "No shader without a device")
	assert_false(effect.pipeline.is_valid())
	effect._render_callback(CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT, null)
	pass_test("The render callback is a no-op without a pipeline")
	assert_eq(effect.bands, 3)
	assert_eq(effect.outline_thickness, 2.0)
	assert_gt(effect.depth_threshold, 0.0)
	assert_gt(effect.normal_threshold, 0.0)
	assert_gt(effect.saturation_boost, 0.0)
	assert_eq(effect.outline_color.a, 1.0)
	var bytes: PackedByteArray = effect._push_constant(Projection.IDENTITY, Vector2i(1920, 1080), true)
	assert_eq(bytes.size(), 112, "The Params block is 112 bytes, a multiple of 16")
	assert_eq(bytes.decode_float(64), 1920.0, "raster_size follows the 64 byte matrix")
	assert_eq(bytes.decode_float(72), 3.0, "then bands")
	assert_eq(bytes.decode_float(92), 1.0, "has_normals")
	for uniform: String in ["bands", "outline_thickness", "depth_threshold", "normal_threshold", "saturation_boost", "outline_color", "has_normals"]:
		assert_true(CelCompositorEffect.GLSL.contains(uniform), "The GLSL reads " + uniform)
	assert_true(CelCompositorEffect.GLSL.contains("normal_texture"), "and the normal buffer")


func test_the_cel_option_is_greyed_off_forward_plus() -> void:
	var video: PlayerMenuLayer = VIDEO_SETTINGS_SCENE.instantiate() as PlayerMenuLayer
	add_child_autofree(video)
	var option: OptionButton = video.toon_button
	assert_eq(option.item_count, 3, "Off, Newspaper, Cel")
	assert_eq(option.get_item_text(ToonFilter.Mode.NEWSPAPER), "Newspaper")
	assert_eq(option.get_item_text(ToonFilter.Mode.CEL), "Cel")
	assert_false(option.is_item_disabled(ToonFilter.Mode.CEL), "Headless reports forward_plus, so Cel is offered")
	video.update_cel_availability(false)
	assert_true(option.is_item_disabled(ToonFilter.Mode.CEL), "Off Forward+ the Cel option is greyed")
	assert_true(option.get_item_tooltip(ToonFilter.Mode.CEL).contains("Forward+"), "with the reason as its tooltip")
	assert_false(option.is_item_disabled(ToonFilter.Mode.NEWSPAPER), "Newspaper stays available everywhere")
	option.selected = ToonFilter.Mode.NEWSPAPER
	video._on_toon_shading_touch_screen_button_pressed()
	assert_eq(option.selected, ToonFilter.Mode.OFF, "The touch button skips the greyed Cel")
	assert_eq(_saved_mode(), ToonFilter.Mode.OFF)


func test_the_option_and_the_key_drive_the_players_filter_under_the_hud() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var player: Player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await wait_physics_frames(2)
	var filter: ToonFilter = player.toon_filter
	assert_eq(filter.get_parent(), player.camera, "Under the camera, so only the current camera draws it")
	assert_true(filter is VisualInstance3D, "Drawn in the 3D pass, before every CanvasLayer, so the HUD sits above it")
	assert_true(player.controls is CanvasLayer, "The HUD is a CanvasLayer")
	assert_true(InputMap.has_action("toggle_toon"), "Controls registers the action")
	assert_true(InputMap.action_has_event("toggle_toon", _f6()), "Bound to F6")
	assert_eq(filter.mode, ToonFilter.Mode.OFF, "Off until asked")
	var video: PlayerMenuLayer = player.video_settings
	video._on_toon_shading_item_selected(ToonFilter.Mode.NEWSPAPER)
	assert_eq(filter.mode, ToonFilter.Mode.NEWSPAPER, "The Video settings option picks the look")
	assert_true(filter.visible)
	assert_eq(_saved_mode(), ToonFilter.Mode.NEWSPAPER)
	await send_key(KEY_F6)
	assert_eq(filter.mode, ToonFilter.Mode.CEL, "F6 steps on to Cel")
	assert_eq(video.toon_button.selected, ToonFilter.Mode.CEL, "The option follows the key")
	assert_not_null(player.camera.compositor, "and the camera got its compositor")
	await send_key(KEY_F6)
	assert_eq(filter.mode, ToonFilter.Mode.OFF, "F6 turns it off again")
	assert_eq(video.toon_button.selected, ToonFilter.Mode.OFF)
	assert_null(player.camera.compositor)
	assert_eq(_saved_mode(), ToonFilter.Mode.OFF)


func _f6() -> InputEventKey:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_F6
	return key
