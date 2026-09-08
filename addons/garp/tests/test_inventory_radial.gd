extends GutTest

## Purpose: To test weapon cycling, backpack equipping and the radial menu hold timer.

class InventoryTestBase:
	extends GutTest

	const ContractActions: GDScript = preload("res://addons/garp/tests/contract_actions.gd")

	var PlayerScene = load("res://addons/3d_player_controller/scenes/player.tscn")
	var root: Node3D = null
	var player_instance: Player = null
	var actions: RefCounted = ContractActions.new()

	func before_all() -> void:
		actions.add_missing()

	func after_all() -> void:
		actions.remove_added()

	func before_each() -> void:
		root = Node3D.new()
		add_child_autofree(root)
		player_instance = PlayerScene.instantiate() as Player
		root.add_child(player_instance)
		await wait_physics_frames(2)

	func after_each() -> void:
		Input.action_release("last_weapon")
		Input.action_release("next_weapon")
		if is_instance_valid(root):
			root.free()
			root = null
			player_instance = null

	## A world item ready to be equipped onto the given bone.
	func make_equipment(type: Equipment.EquipmentType, bone: String) -> Equipment:
		var item = Equipment.new()
		item.equipment_type = type
		item.bone_attachment_bone_name = bone
		root.add_child(item)
		return item


class TestRadialMenuHold:
	extends InventoryTestBase

	func test_radial_menu_is_menu_held_returns_true_for_last_or_next_weapon():
		var radial_menu = player_instance.radial_menu
		Input.action_press("last_weapon")
		assert_true(radial_menu.is_menu_held(), "is_menu_held should return true when last_weapon is pressed")
		Input.action_release("last_weapon")
		Input.action_press("next_weapon")
		assert_true(radial_menu.is_menu_held(), "is_menu_held should return true when next_weapon is pressed")
		Input.action_release("next_weapon")

	func test_hold_timer_opens_menu_and_tap_cycles():
		var inventory: Inventory = player_instance.inventory
		var radial_menu = player_instance.radial_menu
		var sender = InputSender.new(Input)
		sender.set_auto_flush_input(true)

		sender.action_down("next_weapon")
		await wait_physics_frames(1)
		assert_false(inventory.hold_timer.is_stopped(), "Pressing next_weapon should start the hold timer")
		assert_false(radial_menu.visible, "Menu should stay closed before the hold timer elapses")

		await wait_for_signal(inventory.hold_timer.timeout, inventory.hold_timer.wait_time + 0.5)
		await wait_physics_frames(1)
		assert_true(radial_menu.visible, "Holding next_weapon past the timer should open the radial menu")

		sender.action_up("next_weapon")
		await wait_physics_frames(2)
		assert_false(radial_menu.visible, "Releasing should close the radial menu")


class TestCycleAndBackpack:
	extends InventoryTestBase

	func test_cycle_weapon_and_equip_from_backpack_emit_equipment_changed():
		var inventory: Inventory = player_instance.inventory
		var sword = make_equipment(Equipment.EquipmentType.SWORD_1H, "RightHand")
		var axe = make_equipment(Equipment.EquipmentType.AXE_1H, "RightHand")
		inventory.equip_pickup(sword)
		inventory.equip_pickup(axe)

		# Same bone: the sword was stowed, the axe is equipped
		assert_true(inventory.has_equipment(Equipment.EquipmentType.AXE_1H), "Axe should be equipped")
		assert_false(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "Sword should be stowed")
		assert_eq(inventory.get_all_weapons().size(), 2, "Both items should be in the loadout")

		watch_signals(inventory)
		inventory.cycle_weapon(1)
		assert_signal_emitted(inventory, "equipment_changed", "cycle_weapon should emit equipment_changed")
		assert_true(inventory.has_equipment(Equipment.EquipmentType.SWORD_1H), "Cycling should equip the stowed sword")
		assert_true(inventory.get_equipment_by_type(Equipment.EquipmentType.SWORD_1H) is Equipment, "Lookup returns a typed Equipment")

		inventory.unequip_all()
		assert_true(inventory.is_unarmed(), "unequip_all should leave the player unarmed")
		var attachment: BoneAttachment3D = inventory.get_all_weapons()[0].get_parent() as BoneAttachment3D
		assert_eq(attachment.get_parent(), inventory, "Stowed attachments live under the inventory")

		watch_signals(inventory)
		inventory.equip_from_backpack(attachment)
		assert_signal_emitted(inventory, "equipment_changed", "equip_from_backpack should emit equipment_changed")
		assert_eq(attachment.get_parent(), player_instance.skeleton, "Equipped attachments live under the skeleton")


class TestWheelCap:
	extends InventoryTestBase

	func test_the_wheel_shows_eight_items_at_most():
		var wheel: RadialMenu = player_instance.radial_menu
		assert_eq(wheel.max_items, 8)
		wheel.custom_item_provider = func() -> Array:
			var items: Array = []
			for i in 12:
				items.append({"display_name": "Station %d" % i, "icon": null})
			return items
		wheel.update_items()
		assert_eq(wheel.weapons.size(), 8, "Twelve stations offered, eight wedges drawn")
		wheel.custom_item_provider = Callable()
		for i in 10:
			player_instance.inventory.equip_pickup(make_equipment(Equipment.EquipmentType.values()[i], "RightHand"))
		assert_eq(player_instance.inventory.get_all_weapons().size(), 8, "The inventory itself stops at eight weapons")
		wheel.update_items()
		assert_eq(wheel.weapons.size(), 9, "Eight weapons plus the Unarmed wedge")
