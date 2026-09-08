@tool
extends EditorPlugin
## GARP registers no types at enable time: [Inventory], [InventoryScreen], [ItemPickup], [Item] and the save
## resources carry class_name and icons of their own. Enabling the plugin adds the Spell Tree bottom panel, a
## [SpellTreeEditor] that opens whenever a [SpellTree] resource is selected, the way AnimationTree opens its own.

const SPELL_TREE_EDITOR: GDScript = preload("res://addons/garp/editor/spell_tree_editor.gd")

var editor: SpellTreeEditor
var panel_button: Button
var save_dialog: EditorFileDialog


func _enter_tree() -> void:
	editor = SPELL_TREE_EDITOR.new()
	editor.undo_redo = get_undo_redo()
	editor.ui_scale = EditorInterface.get_editor_scale()
	editor.save_as_requested.connect(_on_save_as_requested)
	editor.saved.connect(_on_saved)
	panel_button = add_control_to_bottom_panel(editor, "Spell Tree")
	panel_button.hide()
	save_dialog = EditorFileDialog.new()
	save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	save_dialog.filters = PackedStringArray(["*.tres ; Spell Tree"])
	save_dialog.title = "Save Spell Tree As"
	save_dialog.file_selected.connect(editor.save_to)
	EditorInterface.get_base_control().add_child(save_dialog)


func _exit_tree() -> void:
	remove_control_from_bottom_panel(editor)
	editor.queue_free()
	save_dialog.queue_free()


func _handles(object: Object) -> bool:
	return object is SpellTree


func _edit(object: Object) -> void:
	editor.set_tree(object as SpellTree)


func _make_visible(visible: bool) -> void:
	if visible:
		panel_button.show()
		editor.ensure_palette()
		make_bottom_panel_item_visible(editor)
	else:
		if editor.visible:
			hide_bottom_panel()
		panel_button.hide()


func _on_save_as_requested(_tree: SpellTree) -> void:
	save_dialog.current_dir = "res://resources/spells" if DirAccess.dir_exists_absolute("res://resources/spells") else "res://"
	save_dialog.popup_file_dialog()


func _on_saved(path: String) -> void:
	EditorInterface.get_resource_filesystem().update_file(path)
