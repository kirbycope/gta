extends PlayerMenuLayer

@export_file("*.tscn") var inventory_screen_scene: String = "" ## A GARP InventoryScreen scene; when set, the Inventory button shows and opens it.
@export_file("*.tscn") var spells_screen_scene: String = "" ## A GARP SpellsScreen scene; when set, the Spells button shows and opens it.
@export_file("*.tscn") var extra_screen_scene: String = "" ## Any PlayerMenuLayer scene of the game's (a journal, a fish index); when set, the Extra button shows and opens it.
@export var extra_screen_label: String = "Journal" ## What the Extra button says.

var inventory_screen: PlayerMenuLayer ## The instanced inventory screen, a sibling of this menu on the Player.
var spells_screen: PlayerMenuLayer ## The instanced spells screen, a sibling of this menu on the Player.
var extra_screen: PlayerMenuLayer ## The instanced extra screen, a sibling of this menu on the Player.

@onready var lobby: Button = $Panel/VBoxContainer/Lobby
@onready var inventory_button: Button = $Panel/VBoxContainer/Inventory
@onready var spells_button: Button = $Panel/VBoxContainer/Spells
@onready var extra_button: Button = $Panel/VBoxContainer/Extra


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	var rendering_method: String = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	var lobby_unavailable: bool = rendering_method not in ["forward_plus", "mobile"] \
		or OS.has_feature("gl_compatibility") \
		or OS.has_feature("web") \
		or not Engine.has_singleton("Steam")
	lobby.disabled = lobby_unavailable
	inventory_screen = _instance_screen(inventory_screen_scene, inventory_button)
	spells_screen = _instance_screen(spells_screen_scene, spells_button)
	extra_button.text = extra_screen_label
	extra_screen = _instance_screen(extra_screen_scene, extra_button)


## Instances a menu scene beside this one on the Player and shows its button; an empty or bad path hides the button.
func _instance_screen(scene_path: String, button: Button) -> PlayerMenuLayer:
	button.visible = not scene_path.is_empty()
	if not button.visible or player == null or not is_multiplayer_authority():
		return null
	var scene: PackedScene = load(scene_path) as PackedScene
	var screen: PlayerMenuLayer = scene.instantiate() as PlayerMenuLayer if scene else null
	if screen == null:
		button.hide()
		return null
	screen.player = player
	player.add_child.call_deferred(screen)
	return screen


## Called when there is an input event; "start" toggles the pause menu.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("start"):
		return
	if visible:
		hide_menu()
	elif player and not player.is_paused:
		show_menu()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_lobby_pressed() -> void:
	if player == null or lobby.disabled or player.lobby_manager == null:
		return
	hide()
	player.lobby_manager.show_menu()


func _on_lobby_touch_screen_button_pressed() -> void:
	_on_lobby_pressed()


func _on_resume_pressed() -> void:
	hide_menu()


func _on_resume_touch_screen_button_pressed() -> void:
	_on_resume_pressed()


func _on_inventory_pressed() -> void:
	if inventory_screen == null:
		return
	hide()
	inventory_screen.show_menu()


func _on_inventory_touch_screen_button_pressed() -> void:
	_on_inventory_pressed()


func _on_spells_pressed() -> void:
	if spells_screen == null:
		return
	hide()
	spells_screen.show_menu()


func _on_extra_pressed() -> void:
	if extra_screen == null:
		return
	hide()
	extra_screen.show_menu()


func _on_extra_touch_screen_button_pressed() -> void:
	_on_extra_pressed()


func _on_spells_touch_screen_button_pressed() -> void:
	_on_spells_pressed()


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


func _on_restart_touch_screen_button_pressed() -> void:
	_on_restart_pressed()


func _on_settings_pressed() -> void:
	if player == null:
		return
	hide()
	player.settings.show_menu()


func _on_settings_touch_screen_button_pressed() -> void:
	_on_settings_pressed()


func _on_unstuck_pressed() -> void:
	if player == null:
		return
	player.global_transform = player.initial_transform
	player.velocity = Vector3.ZERO
	player.up_direction = player.initial_transform.basis.y.normalized()
	player.orientation = Transform3D(player.initial_transform.basis, Vector3.ZERO)
	player.player_model.transform = player.initial_player_model_transform
	player.collision_shape.transform = player.initial_collision_shape_transform


func _on_unstuck_touch_screen_button_pressed() -> void:
	_on_unstuck_pressed()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_quit_touch_screen_button_pressed() -> void:
	_on_quit_pressed()
