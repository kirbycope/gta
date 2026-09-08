extends PlayerMenuLayer

@onready var dialog_slider: HSlider = $Panel/VBoxContainer/Dialog/VolumeSlider
@onready var menu_slider: HSlider = $Panel/VBoxContainer/Menu/VolumeSlider
@onready var music_slider: HSlider = $Panel/VBoxContainer/Music/VolumeSlider
@onready var sfx_slider: HSlider = $Panel/VBoxContainer/SFX/VolumeSlider
@onready var voice_settings: VBoxContainer = $Panel/VBoxContainer/VoiceSettings ## Steam voice chat rows; shown only when Steam is loaded.
@onready var voice_slider: HSlider = $Panel/VBoxContainer/VoiceSettings/Voice/VolumeSlider
@onready var mute_voice: CheckButton = $Panel/VBoxContainer/VoiceSettings/MuteVoice

var settings_res: PlayerSettingsResource


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	settings_res = PlayerSettingsResource.load_or_create()
	dialog_slider.set_value_no_signal(settings_res.dialog_volume)
	menu_slider.set_value_no_signal(settings_res.menu_volume)
	music_slider.set_value_no_signal(settings_res.music_volume)
	sfx_slider.set_value_no_signal(settings_res.sfx_volume)
	voice_slider.set_value_no_signal(settings_res.voice_volume)
	mute_voice.set_pressed_no_signal(settings_res.voice_muted)
	voice_settings.visible = is_steam_loaded()


## Voice chat runs on Steam only, so its rows show only with the Steam singleton; a test overrides this to see both layouts.
func is_steam_loaded() -> bool:
	return Engine.has_singleton("Steam")


## Mutes or unmutes the Voice bus on this machine only and saves at once (a toggle has no drag to end).
func _on_mute_voice_toggled(toggled_on: bool) -> void:
	settings_res.voice_muted = toggled_on
	PlayerSettingsResource.set_bus_mute(&"Voice", toggled_on)
	settings_res.save()


func _on_mute_voice_touch_screen_button_pressed() -> void:
	mute_voice.button_pressed = not mute_voice.button_pressed # Emits toggled


## Applies a slider value to its bus (bound in the scene) without saving.
func _on_volume_slider_value_changed(value: float, bus: StringName) -> void:
	PlayerSettingsResource.set_bus_volume(bus, value)
	settings_res.set(bus.to_lower() + "_volume", value) # dialog_volume, menu_volume, music_volume, sfx_volume
	if player and bus == &"Music":
		player.update_music_volume(value)
	elif player and bus == &"SFX":
		player.update_sfx_volume(value)


## Saves once the slider is released instead of on every value tick.
func _on_volume_slider_drag_ended(_value_changed: bool) -> void:
	settings_res.save()


## Steps a slider (bound in the scene) down by 5; the slider clamps and emits value_changed.
func _on_volume_minus_pressed(slider: NodePath) -> void:
	(get_node(slider) as HSlider).value -= 5.0


## Steps a slider (bound in the scene) up by 5; the slider clamps and emits value_changed.
func _on_volume_plus_pressed(slider: NodePath) -> void:
	(get_node(slider) as HSlider).value += 5.0


## Saves when the menu closes by any route (BACK button or "start").
func _on_visibility_changed() -> void:
	if not visible and settings_res:
		settings_res.save()


func _on_dialog_volume_minus_touch_screen_button_pressed() -> void:
	_on_volume_minus_pressed(dialog_slider.get_path())


func _on_dialog_volume_plus_touch_screen_button_pressed() -> void:
	_on_volume_plus_pressed(dialog_slider.get_path())


func _on_menu_volume_minus_touch_screen_button_pressed() -> void:
	_on_volume_minus_pressed(menu_slider.get_path())


func _on_menu_volume_plus_touch_screen_button_pressed() -> void:
	_on_volume_plus_pressed(menu_slider.get_path())


func _on_music_volume_minus_touch_screen_button_pressed() -> void:
	_on_volume_minus_pressed(music_slider.get_path())


func _on_music_volume_plus_touch_screen_button_pressed() -> void:
	_on_volume_plus_pressed(music_slider.get_path())


func _on_sfx_volume_minus_touch_screen_button_pressed() -> void:
	_on_volume_minus_pressed(sfx_slider.get_path())


func _on_sfx_volume_plus_touch_screen_button_pressed() -> void:
	_on_volume_plus_pressed(sfx_slider.get_path())


func _on_voice_volume_minus_touch_screen_button_pressed() -> void:
	_on_volume_minus_pressed(voice_slider.get_path())


func _on_voice_volume_plus_touch_screen_button_pressed() -> void:
	_on_volume_plus_pressed(voice_slider.get_path())


## Return to main settings menu.
func _on_back_pressed() -> void:
	if player == null:
		return
	hide()
	player.settings.show_menu()


func _on_back_touch_screen_button_pressed() -> void:
	_on_back_pressed()
