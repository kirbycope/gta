class_name PlayerSettingsResource
extends Resource

const SAVE_PATH: String = "user://settings.tres"
const MSAA_VALUES: Array[Viewport.MSAA] = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X] ## Indexed by [member msaa_index].
const SSAA_SCALES: Array[float] = [1.0, 1.5, 2.0] ## Indexed by [member ssaa_index].
const TOON_NEWSPAPER: int = 1 ## ToonFilter.Mode.NEWSPAPER, what an old saved toon_enabled = true meant.

static var _cached: PlayerSettingsResource ## One shared instance so every menu edits and saves the same settings.

# Audio Settings
@export var dialog_volume: float = 50.0
@export var menu_volume: float = 50.0
@export var music_volume: float = 50.0
@export var sfx_volume: float = 50.0
@export var voice_volume: float = 50.0 ## Steam voice chat playback; local like the other volumes.
@export var voice_muted: bool = false ## Mutes the Voice bus on this machine only.

# Video Settings
@export var vsync_enabled: bool = true
@export var msaa_index: int = 0
@export var ssaa_index: int = 0 ## Bilinear supersampling; mutually exclusive with [member fsr_index].
@export var fxaa_enabled: bool = false
@export var ssrl_enabled: bool = false
@export var taa_enabled: bool = false
@export var fsr_index: int = 0 ## [enum Viewport.Scaling3DMode] index; mutually exclusive with [member ssaa_index].
@export var toon_mode: int = 0 ## [enum ToonFilter.Mode] of the [ToonFilter] under the Player's camera; local to this machine like the rest.

# Chat Settings
@export var chat_rect: Rect2 = Rect2() ## Where the [ChatWindow] sits and how big it is; zero size means bottom-left at the default size.


## Migrates a settings file saved before [member toon_mode]: toon_enabled = true was the Newspaper look.
func _set(property: StringName, value: Variant) -> bool:
	if property == &"toon_enabled":
		toon_mode = TOON_NEWSPAPER if value else 0
		return true
	return false


## Returns the shared settings instance, loading it from disk the first time.
static func load_or_create() -> PlayerSettingsResource:
	if _cached == null:
		if ResourceLoader.exists(SAVE_PATH):
			_cached = ResourceLoader.load(SAVE_PATH) as PlayerSettingsResource
		if _cached == null:
			_cached = PlayerSettingsResource.new()
	return _cached


func save() -> void:
	_cached = self
	ResourceSaver.save(self, SAVE_PATH)


func apply_audio_settings(player: Player = null) -> void:
	set_bus_volume(&"Dialog", dialog_volume)
	set_bus_volume(&"Menu", menu_volume)
	set_bus_volume(&"Music", music_volume)
	set_bus_volume(&"SFX", sfx_volume)
	set_bus_volume(&"Voice", voice_volume)
	set_bus_mute(&"Voice", voice_muted)
	if player:
		player.update_sfx_volume(sfx_volume)
		player.update_music_volume(music_volume)


static func set_bus_volume(bus_name: StringName, value: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(value / 100.0) if value > 0.0 else -80.0)


static func set_bus_mute(bus_name: StringName, muted: bool) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		AudioServer.set_bus_mute(bus_index, muted)


func apply_video_settings(viewport: Viewport) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	viewport.msaa_3d = MSAA_VALUES[clampi(msaa_index, 0, MSAA_VALUES.size() - 1)]
	# SSAA and FSR are mutually exclusive: fsr_index 0 is bilinear scaling, which is where the SSAA scale applies.
	viewport.scaling_3d_mode = fsr_index as Viewport.Scaling3DMode
	viewport.scaling_3d_scale = SSAA_SCALES[clampi(ssaa_index, 0, SSAA_SCALES.size() - 1)] if fsr_index == 0 else 1.0
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if fxaa_enabled else Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.screen_space_roughness_limiter_set_active(ssrl_enabled, 0.25, 0.18)
	viewport.use_taa = taa_enabled


func apply_all(viewport: Viewport, player: Player = null) -> void:
	apply_audio_settings(player)
	if viewport:
		apply_video_settings(viewport)
