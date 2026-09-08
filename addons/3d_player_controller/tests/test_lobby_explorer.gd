extends GutTest

const LOBBY_EXPLORER_SCENE = preload("res://addons/3d_player_controller/scenes/lobby_explorer.tscn")
const LOBBY_EXPLORER_ENTRY_SCENE = preload("res://addons/3d_player_controller/scenes/lobby_explorer_entry.tscn")


func test_lobby_explorer_initial_nodes() -> void:
	var explorer = LOBBY_EXPLORER_SCENE.instantiate()
	add_child_autofree(explorer)

	assert_not_null(explorer.host_button, "Host button should exist")
	assert_not_null(explorer.refresh_button, "Refresh button should exist")
	assert_not_null(explorer.back_button, "Back button should exist")
	assert_not_null(explorer.status_label, "StatusLabel should exist")
	assert_not_null(explorer.lobby_list, "LobbyList should exist")
	assert_not_null(explorer.distance_option, "DistanceOption should exist")
	assert_not_null(explorer.label_version, "Label_Version should exist")
	assert_not_null(explorer.label_copyright, "Label_Copyright should exist")
	assert_eq(explorer.distance_option.item_count, 4, "Distance options come from the scene")
	assert_eq(explorer.world_scene, "", "The addon scene should not hard-code a project world scene")
	assert_eq(explorer.title_scene, "", "The addon scene should not hard-code a project title scene")


func test_lobby_explorer_version_and_footer_format() -> void:
	var explorer = LOBBY_EXPLORER_SCENE.instantiate()
	explorer.footer_text = "© Test"
	add_child_autofree(explorer)

	var version: String = ProjectSettings.get_setting("application/config/version", "")
	var expected_version: String = version if version.begins_with("v") else "v" + version
	assert_eq(explorer.label_version.text, expected_version, "Version label should match app config")

	var current_year: int = Time.get_date_dict_from_system().year
	assert_eq(explorer.label_copyright.text, "© Test %d" % current_year, "Footer label should append the current year")


func test_lobby_explorer_empty_footer_hides_text() -> void:
	var explorer = LOBBY_EXPLORER_SCENE.instantiate()
	add_child_autofree(explorer)
	assert_eq(explorer.label_copyright.text, "", "Empty footer_text should leave the label empty")


func test_lobby_explorer_entry_initial_state_and_signal() -> void:
	var entry = LOBBY_EXPLORER_ENTRY_SCENE.instantiate()
	add_child_autofree(entry)
	watch_signals(entry)

	entry.set_lobby_id(123456789)
	assert_eq(entry.lobby_id, 123456789, "Lobby ID should be stored")
	assert_eq(entry.name_label.text, "Lobby 123456789", "Without Steam the entry shows the lobby id")

	entry.join_button.pressed.emit()
	assert_signal_emitted_with_parameters(entry, "join_requested", [123456789], 0)
