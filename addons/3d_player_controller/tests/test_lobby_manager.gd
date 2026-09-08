extends GutTest

const LOBBY_MANAGER_SCENE = preload("res://addons/3d_player_controller/scenes/lobby_manager.tscn")
const LOBBY_PLAYER_ITEM_SCENE = preload("res://addons/3d_player_controller/scenes/lobby_player_item.tscn")


func test_lobby_manager_initial_state() -> void:
	var lobby_manager = LOBBY_MANAGER_SCENE.instantiate()
	add_child_autofree(lobby_manager)

	assert_not_null(lobby_manager.panel, "Panel should exist")
	assert_not_null(lobby_manager.info_label, "InfoLabel should exist")
	assert_not_null(lobby_manager.player_list, "PlayerList container should exist")
	assert_not_null(lobby_manager.invite_button, "Invite button should exist")
	assert_not_null(lobby_manager.leave_button, "Leave button should exist")
	assert_not_null(lobby_manager.back_button, "BACK button should exist")


func test_lobby_manager_show_and_hide() -> void:
	var lobby_manager = LOBBY_MANAGER_SCENE.instantiate()
	add_child_autofree(lobby_manager)

	lobby_manager.show_menu()
	assert_true(lobby_manager.visible, "show_menu should make lobby manager visible")
	assert_true(lobby_manager.invite_button.disabled, "Invite should be disabled without an active lobby")

	lobby_manager.hide_menu()
	assert_false(lobby_manager.visible, "hide_menu should make lobby manager hidden")


func test_lobby_player_item_nodes_and_default_avatar() -> void:
	var item: LobbyPlayerItem = LOBBY_PLAYER_ITEM_SCENE.instantiate()
	add_child_autofree(item)

	assert_not_null(item.avatar, "Avatar node should exist")
	assert_not_null(item.host_icon, "HostIcon node should exist")
	assert_not_null(item.username_label, "Username label should exist")
	assert_not_null(item.actions_container, "ActionsContainer should exist")
	assert_not_null(item.options_button, "OptionsButton should exist")
	assert_not_null(item.profile_button, "ProfileButton should exist")
	assert_not_null(item.achievements_button, "AchievementsButton should exist")
	assert_not_null(item.promote_button, "PromoteButton should exist")
	assert_not_null(item.kick_button, "KickButton should exist")

	item.steam_id = 123
	assert_true(item.avatar.texture.resource_path.ends_with("profile.png"), "The avatar should show the default icon until Steam delivers one")
	assert_false(item.host_icon.visible, "Without a lobby nobody is host")
	assert_false(item.kick_button.visible, "Without a lobby nobody can be kicked")


func test_lobby_player_item_options_toggle() -> void:
	var item = LOBBY_PLAYER_ITEM_SCENE.instantiate()
	add_child_autofree(item)

	assert_false(item.actions_container.visible, "ActionsContainer should start hidden")
	assert_true(item.username_label.visible, "Username should start visible")

	item.options_button.button_pressed = true
	assert_true(item.actions_container.visible, "ActionsContainer should become visible when toggled")
	assert_false(item.username_label.visible, "Username should become hidden when options are toggled")

	item.options_button.button_pressed = false
	assert_false(item.actions_container.visible, "ActionsContainer should hide when untoggled")
	assert_true(item.username_label.visible, "Username should become visible when options are untoggled")
