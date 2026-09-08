extends GutTest

const PLAYER_SCENE = preload("res://addons/3d_player_controller/scenes/player.tscn")
const CONTROLS_SCENE = preload("res://addons/3d_player_controller/scenes/controls.tscn")
const AUDIO_SETTINGS_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/audio_settings.tscn")


func test_broadcast_action_in_input_map() -> void:
	var controls = CONTROLS_SCENE.instantiate()
	add_child_autofree(controls)

	assert_true(InputMap.has_action("broadcast"), "InputMap should have 'broadcast' action")

	var events = InputMap.action_get_events("broadcast")
	var has_key_v: bool = false
	var has_key_t: bool = false
	for event in events:
		if event is InputEventKey and event.physical_keycode == KEY_V:
			has_key_v = true
		if event is InputEventKey and event.physical_keycode == KEY_T:
			has_key_t = true
	assert_true(has_key_v, "'broadcast' action should be mapped to physical key V")
	assert_false(has_key_t, "T belongs to throw, not push-to-talk")


func test_player_voice_chat_nodes_and_default_state() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	assert_not_null(player.voice_chat_indicator, "VoiceChatIndicator should exist on Player")
	assert_false(player.voice_chat_indicator.visible, "VoiceChatIndicator should be hidden by default")
	assert_not_null(player.voice_audio_player, "VoiceAudioPlayer should exist on Player")
	assert_eq(player.voice_audio_player.playback_type, AudioServer.PLAYBACK_TYPE_STREAM, "Voice is streamed, so the web build can play it too")
	assert_false(player.is_broadcasting, "is_broadcasting should be false by default")


func test_player_broadcasting_indicator_toggle() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	player.start_broadcasting()
	assert_true(player.is_broadcasting, "Player is_broadcasting should be true after start_broadcasting()")
	assert_true(player.voice_chat_indicator.visible, "VoiceChatIndicator should be visible when broadcasting")

	player.stop_broadcasting()
	assert_false(player.is_broadcasting, "Player is_broadcasting should be false after stop_broadcasting()")
	assert_false(player.voice_chat_indicator.visible, "VoiceChatIndicator should be hidden when not broadcasting")


func test_voice_bus_exists_and_the_voice_player_uses_it() -> void:
	assert_ne(AudioServer.get_bus_index(&"Voice"), -1, "The Voice bus comes from default_bus_layout.tres (and Audio.BUSES creates it for projects without one)")
	assert_true(Audio.BUSES.has(&"Voice"), "Audio creates the Voice bus when a project's layout lacks it")
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	assert_eq(player.voice_audio_player.bus, &"Voice", "Voice playback runs on its own bus so it has its own volume and mute")


func test_voice_settings_show_with_steam_and_hide_without() -> void:
	var with_steam: PlayerMenuLayer = partial_double(AUDIO_SETTINGS_SCENE).instantiate()
	stub(with_steam, "is_steam_loaded").to_return(true)
	add_child_autofree(with_steam)
	assert_true(with_steam.voice_settings.visible, "With Steam the Voice row and mute toggle show")
	assert_not_null(with_steam.get_node_or_null("Panel/VBoxContainer/VoiceSettings/Voice/VolumeSlider"), "The Voice row has a slider like the other rows")
	assert_not_null(with_steam.get_node_or_null("Panel/VBoxContainer/VoiceSettings/MuteVoice/TouchScreenButton"), "The mute toggle has a touch button")

	var without_steam: PlayerMenuLayer = partial_double(AUDIO_SETTINGS_SCENE).instantiate()
	stub(without_steam, "is_steam_loaded").to_return(false)
	add_child_autofree(without_steam)
	assert_false(without_steam.voice_settings.visible, "Without Steam there is no voice chat, so the rows hide")
