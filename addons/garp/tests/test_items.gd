extends GutTest

## Purpose: GARP keeps stacks of Items in fixed tabs: they stack to their limit, move, merge and swap, using only
## signals, dropping puts a pickup in the world, equipment items go onto the skeleton, and the whole inventory
## survives a save and a load.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const APPLE: Item = preload("res://addons/garp/resources/items/apple.tres")
const ORE: Item = preload("res://addons/garp/resources/items/iron_ore.tres")
const KEY: Item = preload("res://addons/garp/resources/items/old_key.tres")
const SWORD: Item = preload("res://addons/garp/resources/items/wooden_sword.tres")
const TEST_SAVE: String = "user://garp_test_inventory.tres"
const ContractActions: GDScript = preload("res://addons/garp/tests/contract_actions.gd")

var root: Node3D
var player: Player
var inventory: Inventory
var actions: RefCounted = ContractActions.new()
var _persistence_was_enabled: bool


func before_all() -> void:
	actions.add_missing()


func after_all() -> void:
	actions.remove_added()


func before_each() -> void:
	_persistence_was_enabled = Inventory.persistence_enabled
	Inventory.persistence_enabled = true # the suite's pre-run hook turns it off; these tests write a file of their own
	root = Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(20.0, 1.0, 20.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	player = _spawn_player()
	inventory = player.inventory
	await wait_physics_frames(3)


func after_each() -> void:
	Inventory.persistence_enabled = _persistence_was_enabled
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


func _spawn_player() -> Player:
	var spawned: Player = PLAYER_SCENE.instantiate()
	spawned.get_node("Inventory").save_path = TEST_SAVE
	root.add_child(spawned)
	return spawned


func test_items_stack_to_their_limit_and_spill_into_new_slots() -> void:
	assert_eq(inventory.add_item(APPLE, 5), 0, "Five apples fit")
	assert_eq(inventory.count_of(APPLE), 5)
	assert_eq(inventory.get_slot(Item.Category.FOOD, 0).count, 5, "One stack in the first food slot")
	assert_eq(inventory.add_item(ORE, 2000), 0, "Ore stacks to 999, so 2000 spread over three slots")
	assert_eq(inventory.get_slot(Item.Category.MATERIALS, 0).count, 999)
	assert_eq(inventory.get_slot(Item.Category.MATERIALS, 1).count, 999)
	assert_eq(inventory.get_slot(Item.Category.MATERIALS, 2).count, 2)
	assert_null(inventory.get_slot(Item.Category.MATERIALS, 3))


func test_a_full_tab_reports_what_did_not_fit() -> void:
	var left: int = inventory.add_item(KEY, inventory.slots_per_tab + 3)
	assert_eq(left, 3, "Key items do not stack, so three are left over once every slot holds one")
	assert_eq(inventory.count_of(KEY), inventory.slots_per_tab)


func test_remove_takes_from_the_last_stacks_first() -> void:
	inventory.add_item(ORE, 1500)
	assert_eq(inventory.remove_item(ORE, 600), 600)
	assert_eq(inventory.count_of(ORE), 900)
	assert_null(inventory.get_slot(Item.Category.MATERIALS, 1), "The partial second stack went first")
	assert_eq(inventory.get_slot(Item.Category.MATERIALS, 0).count, 900)
	assert_eq(inventory.remove_item(ORE, 5000), 900, "Asking for more than there is takes what there is")
	assert_false(inventory.has_item(ORE))


func test_move_swaps_merges_and_moves() -> void:
	inventory.add_item(APPLE, 5)
	var mushroom: Item = load("res://addons/garp/resources/items/mushroom.tres")
	inventory.add_item(mushroom, 2)
	watch_signals(inventory)
	inventory.move_slot(Item.Category.FOOD, 0, 1)
	assert_eq(inventory.get_slot(Item.Category.FOOD, 0).item, mushroom, "Different items swap")
	assert_eq(inventory.get_slot(Item.Category.FOOD, 1).item, APPLE)
	inventory.move_slot(Item.Category.FOOD, 1, 4)
	assert_null(inventory.get_slot(Item.Category.FOOD, 1), "Onto an empty slot it moves")
	assert_eq(inventory.get_slot(Item.Category.FOOD, 4).count, 5)
	inventory.get_slots(Item.Category.FOOD)[2] = ItemSlot.make(APPLE, 96)
	inventory.move_slot(Item.Category.FOOD, 4, 2)
	assert_eq(inventory.get_slot(Item.Category.FOOD, 2).count, 99, "Onto the same item it merges up to the limit")
	assert_eq(inventory.get_slot(Item.Category.FOOD, 4).count, 2, "And the rest stays behind")
	assert_signal_emit_count(inventory, "items_changed", 3, "Swap, move and merge each signal once; the direct slot write does not")


func test_use_only_signals_and_consumes_consumables() -> void:
	inventory.add_item(APPLE, 3)
	inventory.add_item(ORE, 3)
	watch_signals(inventory)
	inventory.use_slot(Item.Category.FOOD, 0)
	assert_signal_emitted_with_parameters(inventory, "item_used", [APPLE, 1])
	assert_eq(inventory.count_of(APPLE), 2, "Food is consumable")
	inventory.use_slot(Item.Category.MATERIALS, 0)
	assert_signal_emit_count(inventory, "item_used", 2)
	assert_eq(inventory.count_of(ORE), 3, "Ore is not")


func test_drop_puts_a_pickup_in_front_of_the_player() -> void:
	inventory.add_item(APPLE, 3)
	watch_signals(inventory)
	var pickup: Node3D = inventory.drop_slot(Item.Category.FOOD, 0)
	assert_true(pickup is ItemPickup, "A pickup is spawned")
	assert_eq(pickup.get_parent(), root, "Beside the Player in the world")
	assert_lt(pickup.global_position.distance_to(player.global_position), 2.0)
	assert_eq(pickup.item, APPLE)
	assert_eq(pickup.count, 1, "One at a time")
	assert_eq(inventory.count_of(APPLE), 2)
	assert_signal_emitted_with_parameters(inventory, "item_dropped", [APPLE, 1, pickup])


func test_an_equipment_item_goes_onto_the_skeleton() -> void:
	assert_eq(inventory.add_item(SWORD), 0)
	assert_true(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "The sword is in hand")
	assert_eq(inventory.add_item(SWORD), 1, "A second of the same type on the same bone is refused")
	var sword: Equipment = inventory.get_equipment_by_type(Equipment.EquipmentType.SWORD_1H)
	assert_eq(sword.scene_file_path, "res://addons/garp/scenes/demo/wooden_sword.tscn", "The copy remembers its scene")
	assert_eq(sword.player, player, "and its Player")
	var attachment: BoneAttachment3D = sword.get_parent() as BoneAttachment3D
	assert_not_null(attachment, "The copy hangs off a BoneAttachment3D")
	assert_eq(attachment.bone_name, "RightHand", "on the bone the scene names")
	assert_eq(attachment.get_parent(), player.skeleton, "under the Player's skeleton")
	assert_eq(sword.position, sword.position_offset, "It was in the tree while it equipped, so the hand offsets reached the copy")
	assert_almost_eq(sword.rotation_degrees.y, sword.rotation_offset_degrees.y, 0.01, "rotation included")
	assert_eq(sword.scale, sword.scale_offset, "and scale")
	assert_true((sword.get_node("PlayerDetection/CollisionShape3D") as CollisionShape3D).disabled, "The copy is no pickup")
	assert_false((sword.get_node("Hitbox/CollisionShape3D") as CollisionShape3D).disabled, "but its hitbox still counts")
	assert_false((sword.get_node("WeaponBody/CollisionShape3D") as CollisionShape3D).disabled, "and its weapon body still shoves")
	var dropped: Node3D = inventory.drop_equipment(sword)
	assert_true(dropped is Equipment, "Dropping equipment puts its scene back in the world")
	assert_false(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H))
	await wait_physics_frames(2)
	assert_eq(inventory.get_all_weapons().size(), 0, "Standing on the dropped sword does not take it straight back")
	assert_eq(dropped.get_meta("dropped_by"), player, "Until the Player steps away")
	player.warp_to(Transform3D(Basis(), player.global_position + Vector3(6.0, 0.0, 0.0)))
	await wait_physics_frames(2)
	assert_false(dropped.has_meta("dropped_by"), "Stepping away re-arms the pickup; walking back over it is the real addon's pickup, see tests/integration")


func test_save_and_load_round_trip() -> void:
	inventory.add_item(APPLE, 5)
	inventory.add_item(ORE, 1200)
	inventory.add_item(KEY)
	inventory.add_item(SWORD)
	inventory.move_slot(Item.Category.FOOD, 0, 3)
	assert_eq(inventory.save(), OK)
	assert_true(FileAccess.file_exists(TEST_SAVE))

	var loaded: Player = _spawn_player()
	await wait_physics_frames(2)
	assert_true(loaded.inventory.load_save(), "The save is read")
	assert_eq(loaded.inventory.count_of(APPLE), 5)
	assert_eq(loaded.inventory.get_slot(Item.Category.FOOD, 3).count, 5, "In the slot it was moved to")
	assert_eq(loaded.inventory.get_slot(Item.Category.MATERIALS, 0).count, 999)
	assert_eq(loaded.inventory.get_slot(Item.Category.MATERIALS, 1).count, 201)
	assert_true(loaded.inventory.has_item(KEY))
	assert_true(loaded.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "The sword is back in hand")

	inventory.unequip_all()
	inventory.save()
	var stowed: Player = _spawn_player()
	await wait_physics_frames(2)
	stowed.inventory.load_save()
	assert_false(stowed.inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "Stowed on save, stowed on load")
	assert_eq(stowed.inventory.get_all_weapons().size(), 1, "But still owned")


func test_persist_writes_the_file_on_every_change_and_reads_it_on_ready() -> void:
	inventory.persist = true
	inventory.add_item(APPLE, 2)
	assert_true(FileAccess.file_exists(TEST_SAVE), "Adding saved")
	var reloaded: Player = PLAYER_SCENE.instantiate()
	reloaded.get_node("Inventory").save_path = TEST_SAVE
	reloaded.get_node("Inventory").persist = true
	root.add_child(reloaded)
	await wait_physics_frames(2)
	assert_eq(reloaded.inventory.count_of(APPLE), 2, "Loaded on ready")


func test_persist_is_off_by_default_so_bare_players_leave_the_disk_alone() -> void:
	assert_false(inventory.persist)
	inventory.add_item(APPLE)
	assert_false(FileAccess.file_exists(TEST_SAVE))


func test_persistence_can_be_switched_off_for_every_inventory() -> void:
	Inventory.persistence_enabled = false
	inventory.persist = true
	inventory.add_item(APPLE)
	assert_false(FileAccess.file_exists(TEST_SAVE), "The test suite's hook keeps every inventory off the disk")
	Inventory.persistence_enabled = true
	inventory.add_item(APPLE)
	assert_true(FileAccess.file_exists(TEST_SAVE))


func test_throwables_are_listed_and_use_item_uses_the_first_stack() -> void:
	assert_false(Item.new().throwable, "Nothing is throwable unless the resource says so")
	assert_eq(Item.new().throw_damage, 0.0)
	var stone: Item = Item.new()
	stone.id = &"stone"
	stone.throwable = true
	inventory.add_item(APPLE, 3)
	inventory.add_item(ORE, 5)
	inventory.add_item(stone, 4)
	assert_eq(inventory.get_throwable_items(), [stone] as Array[Item], "Only the flagged kind, once")
	watch_signals(inventory)
	inventory.use_item(APPLE)
	assert_signal_emitted_with_parameters(inventory, "item_used", [APPLE, 1]) # use_item finds the stack and uses it as use_slot does
	assert_eq(inventory.count_of(APPLE), 2)
	inventory.use_item(Item.new())
	assert_signal_emit_count(inventory, "item_used", 1, "An item that is not carried uses nothing")


func test_forget_equipment_drops_nothing_and_add_equipment_scene_brings_it_back() -> void:
	assert_eq(inventory.add_item(SWORD), 0)
	var sword: Equipment = inventory.get_equipment_by_type(Equipment.EquipmentType.SWORD_1H)
	var bare: Equipment = Equipment.new()
	bare.equipment_type = Equipment.EquipmentType.DAGGER
	bare.bone_attachment_bone_name = "LeftHand"
	root.add_child(bare)
	var dagger: Equipment = inventory.equip_pickup(bare)
	assert_eq(inventory.forget_equipment(dagger), "", "Equipment from no scene cannot be forgotten: there is nothing to bring it back from")
	assert_true(inventory.equipment.has(dagger), "so it stays")
	watch_signals(inventory)
	var children_before: int = root.get_child_count()
	assert_eq(inventory.forget_equipment(sword), "res://addons/garp/scenes/demo/wooden_sword.tscn", "The scene path the sword can come back from")
	assert_false(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H))
	assert_eq(inventory.get_all_weapons().filter(func(item: Equipment) -> bool: return item.equipment_type == Equipment.EquipmentType.SWORD_1H).size(), 0, "Out of the backpack")
	assert_eq(root.get_child_count(), children_before, "and no pickup in the world")
	assert_signal_emitted(inventory, "items_changed")
	var copy: Equipment = inventory.add_equipment_scene(SWORD.equipment_scene)
	assert_not_null(copy, "add_equipment_scene equips a fresh copy from the scene")
	assert_true(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H))
	assert_eq(copy.scene_file_path, "res://addons/garp/scenes/demo/wooden_sword.tscn")
	assert_eq(copy.position, copy.position_offset, "with the hand offsets, as a walk-over pickup gets them")


func test_the_ninth_weapon_is_refused() -> void:
	assert_eq(inventory.max_equipment, 8, "BOTW's eight weapon slots by default")
	inventory.max_equipment = 2
	assert_eq(inventory.add_item(SWORD), 0)
	var dagger: Equipment = Equipment.new()
	dagger.equipment_type = Equipment.EquipmentType.DAGGER
	dagger.bone_attachment_bone_name = "RightHand"
	root.add_child(dagger)
	assert_not_null(inventory.equip_pickup(dagger), "The second weapon fits")
	assert_false(inventory.can_carry_equipment(), "Two carried, none to spare")
	var axe: Equipment = Equipment.new()
	axe.equipment_type = Equipment.EquipmentType.AXE_1H
	axe.bone_attachment_bone_name = "RightHand"
	root.add_child(axe)
	assert_null(inventory.equip_pickup(axe), "A third is refused until one is dropped")
	assert_eq(inventory.get_all_weapons().size(), 2)
	var sword: Equipment = inventory.get_all_weapons().filter(func(weapon: Equipment) -> bool: return weapon.equipment_type == Equipment.EquipmentType.SWORD_1H)[0]
	assert_not_null(inventory.drop_equipment(sword), "The sword came from a scene, so it can be dropped")
	await wait_physics_frames(1)
	assert_true(inventory.can_carry_equipment())
	assert_not_null(inventory.equip_pickup(axe), "Dropping one makes room")
