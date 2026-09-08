@icon("res://addons/garp/assets/icons/materials.svg")
class_name Inventory
extends CanvasLayer
## GARP, the Godot Action Role Play Inventory: everything the Player carries.
##
## Equipment is the live [Equipment] attached to the Player's skeleton plus the stowed "backpack" attachments;
## each [BoneAttachment3D] holds exactly one [Equipment], stowed attachments live hidden under this node until
## re-equipped, tapping next/last weapon cycles and holding opens the [RadialMenu]. Everything else is stacks
## of [Item] in fixed-size tabs (materials, food, key items) that the [InventoryScreen] shows as a grid.
##
## Spells are GARP's too: the child [Spellbook] holds the unlocked spells, the skill points and the wheel loadout,
## and is saved with the items. Equipment is capped at [member max_equipment] pieces, BOTW style.
##
## GARP only signals when an item is used; the game applies the effect. With [member persist] on, the whole
## inventory is written to [member save_path] after every change and read back on ready.

signal equipment_changed ## Emitted after the set of equipped items changes.
signal items_changed ## Emitted after a stack is added, removed, moved, used or dropped.
signal item_used(item: Item, count: int) ## Use on a stack; consumables lose the count, the effect is the game's.
signal item_dropped(item: Item, count: int, pickup: Node3D) ## A stack (or part of one) is back in the world.

const ITEM_PICKUP_SCENE: PackedScene = preload("res://addons/garp/scenes/item_pickup.tscn")
const ITEM_TABS: Array[Item.Category] = [Item.Category.MATERIALS, Item.Category.FOOD, Item.Category.KEY_ITEMS]

@export var player: Player
@export_range(1, 100) var slots_per_tab: int = 20 ## Slots on each item tab; the grid shows them all.
@export_range(1, 100) var max_equipment: int = 8 ## Weapons and tools carried at once, equipped and stowed together; more are refused.
@export var persist: bool = false ## Load [member save_path] on ready and write it after every change.
@export var save_path: String = "user://garp_inventory.tres"

static var persistence_enabled: bool = true ## Off, no inventory loads or saves whatever [member persist] says; the test suite's pre-run hook turns it off so tests never touch a real save.

var equipment: Array[Equipment] = [] ## Items currently attached to the skeleton.
var equipment_by_type: Dictionary[Equipment.EquipmentType, Equipment] = {}
var can_player_attack: bool = true ## Does the currently equipped item allow the Player to attack?
var can_player_shoot: bool = false ## Does the currently equipped item allow the Player to shoot?
var custom_cycle_handler: Callable = Callable() ## Replaces weapon cycling (e.g. radio stations while driving).
var _tabs: Dictionary[int, Array] = {} ## Category to its slots: [ItemSlot] or null per index.
var _loading: bool = false ## True while a save is applied, so the changes it makes are not written back.

@onready var radial_menu: RadialMenu = $RadialMenu
@onready var hold_timer: Timer = $HoldTimer ## Runs while next/last weapon is held; its timeout opens the radial menu.
@onready var spellbook: Spellbook = get_node_or_null("Spellbook") as Spellbook ## The spells; optional.


func _ready() -> void:
	set_process_unhandled_input(is_multiplayer_authority())
	for category: Item.Category in ITEM_TABS:
		_tabs[category] = _empty_tab()
	if persist and persistence_enabled and is_multiplayer_authority():
		load_save()


func _unhandled_input(event: InputEvent) -> void:
	if player == null or player.held_object.is_holding_object():
		hold_timer.stop()
		return

	if event.is_action_pressed("next_weapon") or event.is_action_pressed("last_weapon"):
		hold_timer.start()
	elif event.is_action_released("next_weapon") or event.is_action_released("last_weapon"):
		# A release while the timer still runs is a tap; a timeout already opened the radial menu.
		if hold_timer.is_stopped():
			return
		hold_timer.stop()
		cycle_weapon(1 if event.is_action_released("next_weapon") else -1)


# --- Items -----------------------------------------------------------------------------------------------------

## The slots of an item tab: [ItemSlot] or null per index, [member slots_per_tab] long. Not for equipment, see
## [method get_all_weapons].
func get_slots(category: Item.Category) -> Array:
	return _tabs.get(category, [])


## The stack at [param index] of [param category], or null.
func get_slot(category: Item.Category, index: int) -> ItemSlot:
	var slots: Array = get_slots(category)
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


## Adds [param count] of [param item]: onto stacks of the same item first, then into empty slots. Equipment items
## are picked up through their [member Item.equipment_scene] instead. Returns how many did not fit.
func add_item(item: Item, count: int = 1) -> int:
	if item == null or count <= 0:
		return count
	if item.category == Item.Category.EQUIPMENT:
		return count if not _add_equipment_item(item) else 0
	var slots: Array = get_slots(item.category)
	var left: int = count
	for slot: ItemSlot in slots:
		if left == 0:
			break
		if slot and slot.item.is_same(item) and slot.count < item.max_stack:
			var room: int = item.max_stack - slot.count
			var taken: int = mini(room, left)
			slot.count += taken
			left -= taken
	for i: int in slots.size():
		if left == 0:
			break
		if slots[i] == null:
			var taken: int = mini(item.max_stack, left)
			slots[i] = ItemSlot.make(item, taken)
			left -= taken
	if left != count:
		_items_changed()
	return left


## Takes [param count] of [param item] from the stacks that hold it. Returns how many were taken.
func remove_item(item: Item, count: int = 1) -> int:
	if item == null or count <= 0:
		return 0
	var slots: Array = get_slots(item.category)
	var left: int = count
	for i: int in range(slots.size() - 1, -1, -1):
		if left == 0:
			break
		var slot: ItemSlot = slots[i]
		if slot and slot.item.is_same(item):
			var taken: int = mini(slot.count, left)
			slot.count -= taken
			left -= taken
			if slot.count == 0:
				slots[i] = null
	if left != count:
		_items_changed()
	return count - left


## How many of [param item] are carried.
func count_of(item: Item) -> int:
	if item == null:
		return 0
	var total: int = 0
	for slot: ItemSlot in get_slots(item.category):
		if slot and slot.item.is_same(item):
			total += slot.count
	return total


func has_item(item: Item, count: int = 1) -> bool:
	return count_of(item) >= count


## Moves the stack at [param from_index] onto [param to_index] of the same tab: onto an empty slot it moves, onto
## the same item it merges up to the stack limit, onto anything else it swaps.
func move_slot(category: Item.Category, from_index: int, to_index: int) -> void:
	var slots: Array = get_slots(category)
	if from_index == to_index or from_index < 0 or to_index < 0 or from_index >= slots.size() or to_index >= slots.size():
		return
	var moving: ItemSlot = slots[from_index]
	if moving == null:
		return
	var target: ItemSlot = slots[to_index]
	if target and target.item.is_same(moving.item) and target.count < moving.item.max_stack:
		var taken: int = mini(moving.item.max_stack - target.count, moving.count)
		target.count += taken
		moving.count -= taken
		if moving.count == 0:
			slots[from_index] = null
	else:
		slots[to_index] = moving
		slots[from_index] = target
	_items_changed()


## Uses [param count] from the stack at [param index]: emits [signal item_used] and, for a consumable, takes them.
func use_slot(category: Item.Category, index: int, count: int = 1) -> void:
	var slot: ItemSlot = get_slot(category, index)
	if slot == null:
		return
	var used: int = mini(count, slot.count)
	var item: Item = slot.item
	if item.consumable:
		slot.count -= used
		if slot.count == 0:
			get_slots(category)[index] = null
		_items_changed()
	item_used.emit(item, used)


## Uses [param count] of [param item] from the first stack that holds it, as [method use_slot] does.
func use_item(item: Item, count: int = 1) -> void:
	if item == null:
		return
	var slots: Array = get_slots(item.category)
	for i: int in slots.size():
		if slots[i] and slots[i].item.is_same(item):
			use_slot(item.category, i, count)
			return


## Every carried [Item] with [member Item.throwable] set, in tab and slot order, each kind once.
func get_throwable_items() -> Array[Item]:
	var found: Array[Item] = []
	for category: Item.Category in ITEM_TABS:
		for slot: ItemSlot in get_slots(category):
			if slot and slot.item.throwable and not found.any(func(item: Item) -> bool: return item.is_same(slot.item)):
				found.append(slot.item)
	return found


## Drops [param count] from the stack at [param index] on the ground in front of the Player as an [ItemPickup].
func drop_slot(category: Item.Category, index: int, count: int = 1) -> Node3D:
	var slot: ItemSlot = get_slot(category, index)
	if slot == null or player == null:
		return null
	var dropped: int = mini(count, slot.count)
	var item: Item = slot.item
	slot.count -= dropped
	if slot.count == 0:
		get_slots(category)[index] = null
	var pickup: Node3D = _spawn_pickup(item, dropped)
	_items_changed()
	item_dropped.emit(item, dropped, pickup)
	return pickup


## Drops an equipped or stowed [Equipment] back into the world (its scene, in front of the Player) and forgets it.
## Equipment that was not instanced from a scene cannot be dropped; it stays.
func drop_equipment(item: Equipment) -> Node3D:
	if player == null:
		return null
	var scene_path: String = forget_equipment(item)
	if scene_path.is_empty():
		return null
	var pickup: Node3D = (load(scene_path) as PackedScene).instantiate() as Node3D
	_place_in_front(pickup)
	# A walk-over pickup lands inside its own reach; it ignores the Player who dropped it until they step away
	pickup.set_meta("dropped_by", player)
	var detection: Area3D = pickup.get_node_or_null("PlayerDetection") as Area3D
	if detection:
		detection.body_exited.connect(_on_dropped_equipment_body_exited.bind(pickup))
	return pickup


## Forgets an equipped or stowed [Equipment] without putting anything in the world (it was thrown, it broke) and
## returns the scene path it can be re-created from. Empty, and nothing happens, for equipment that was not
## instanced from a scene.
func forget_equipment(item: Equipment) -> String:
	if item == null or not _is_scene_path(item.scene_file_path):
		return ""
	var scene_path: String = item.scene_file_path
	var attachment: BoneAttachment3D = item.get_parent() as BoneAttachment3D
	if equipment.has(item):
		_stow_attachment(attachment)
	var gone: Node = attachment if attachment else item
	if gone.get_parent():
		gone.get_parent().remove_child(gone) # out of the backpack now, freed at the end of the frame
	gone.queue_free()
	_items_changed()
	return scene_path


## Equips a fresh instance of [param scene] (an [Equipment] scene) as walking over it would; returns the copy on
## the skeleton, or null when the equip was refused. An equipment [Item] comes through here when it is added.
func add_equipment_scene(scene: PackedScene) -> Equipment:
	if scene == null or player == null:
		return null
	var pickup: Equipment = scene.instantiate() as Equipment
	if pickup == null:
		return null
	return _equip_instance(pickup)


## Puts [param item] back in the backpack without dropping it.
func stow_equipment(item: Equipment) -> void:
	if item == null or not equipment.has(item):
		return
	_stow_attachment(item.get_parent() as BoneAttachment3D)


# --- Saving ----------------------------------------------------------------------------------------------------

## Writes every stack and every piece of equipment to [member save_path].
func save() -> Error:
	var data: InventorySave = InventorySave.new()
	for category: Item.Category in ITEM_TABS:
		var slots: Array = get_slots(category)
		for i: int in slots.size():
			var slot: ItemSlot = slots[i]
			if slot == null:
				continue
			var saved: ItemSlot = ItemSlot.make(slot.item, slot.count)
			saved.category = category
			saved.index = i
			data.slots.append(saved)
	for item: Equipment in get_all_weapons():
		if not _is_scene_path(item.scene_file_path):
			continue # placed inline in a level; it cannot be re-created, so it is not saved
		var entry: EquipmentEntry = EquipmentEntry.new()
		entry.scene_path = item.scene_file_path
		entry.equipped = equipment.has(item)
		data.equipment.append(entry)
	if spellbook:
		spellbook.write_save(data)
	return ResourceSaver.save(data, save_path)


## Replaces the inventory with what [member save_path] holds; nothing happens when there is no file.
func load_save() -> bool:
	if not ResourceLoader.exists(save_path):
		return false
	var data: InventorySave = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as InventorySave
	if data == null:
		return false
	apply_save(data)
	return true


## Replaces the inventory with [param data].
func apply_save(data: InventorySave) -> void:
	_loading = true
	for category: Item.Category in ITEM_TABS:
		_tabs[category] = _empty_tab()
	for saved: ItemSlot in data.slots:
		if saved.item == null or saved.index < 0 or saved.index >= slots_per_tab:
			continue
		get_slots(saved.category)[saved.index] = ItemSlot.make(saved.item, saved.count)
	if player and player.skeleton:
		for item: Equipment in get_all_weapons():
			var attachment: BoneAttachment3D = item.get_parent() as BoneAttachment3D
			if equipment.has(item):
				_stow_attachment(attachment)
			if attachment:
				attachment.free()
		var instances: Array[Equipment] = []
		for entry: EquipmentEntry in data.equipment:
			var scene: PackedScene = load(entry.scene_path) as PackedScene if _is_scene_path(entry.scene_path) else null
			if scene == null:
				continue
			var pickup: Equipment = scene.instantiate() as Equipment
			if pickup == null:
				continue
			var instance: Equipment = _equip_instance(pickup)
			if instance:
				instances.append(instance)
		unequip_all()
		for i: int in instances.size():
			if i < data.equipment.size() and data.equipment[i].equipped:
				equip_weapon(instances[i])
	if spellbook:
		spellbook.read_save(data)
	_loading = false
	_items_changed()


## Writes the save if [member persist] is on; the [Spellbook] calls it after its own changes.
func request_save() -> void:
	_autosave()


func _autosave() -> void:
	if persist and persistence_enabled and not _loading and is_inside_tree() and is_multiplayer_authority():
		save()


func _items_changed() -> void:
	items_changed.emit()
	_autosave()


# --- Equipment -------------------------------------------------------------------------------------------------

## Equips the next (+1) or previous (-1) item; the slot before the first item is "unarmed".
func cycle_weapon(direction: int) -> void:
	if custom_cycle_handler.is_valid():
		custom_cycle_handler.call(direction)
		return

	var all_weapons: Array[Equipment] = get_all_weapons()
	if all_weapons.is_empty():
		return
	var current_index: int = -1
	for i: int in all_weapons.size():
		if equipment.has(all_weapons[i]):
			current_index = i
			break
	var new_index: int = posmod(current_index + 1 + direction, all_weapons.size() + 1) - 1
	if new_index == -1:
		unequip_all()
	else:
		equip_weapon(all_weapons[new_index])


func add_equipment(item: Equipment) -> void:
	if item == null or equipment.has(item):
		return
	equipment.append(item)
	rebuild_equipment_cache()


func remove_equipment(item: Equipment) -> void:
	if item == null or not equipment.has(item):
		return
	equipment.erase(item)
	rebuild_equipment_cache()


func rebuild_equipment_cache() -> void:
	equipment_by_type.clear()
	can_player_attack = equipment.is_empty()
	can_player_shoot = false
	for item: Equipment in equipment:
		equipment_by_type[item.equipment_type] = item
		can_player_attack = can_player_attack or item.can_attack
		can_player_shoot = can_player_shoot or item.can_shoot
	if player and player.controls:
		player.controls.reset_labels()
	equipment_changed.emit()
	_autosave()


func set_equipment_visibility(is_visible: bool) -> void:
	for item: Equipment in equipment:
		item.visible = is_visible


func get_equipment_by_type(type: Equipment.EquipmentType) -> Equipment:
	return equipment_by_type.get(type)


func has_equipment(type: Equipment.EquipmentType) -> bool:
	return equipment_by_type.has(type)


## Returns true if the player has a firearm equipped (Pistol, Rifle).
func has_firearm_equipped() -> bool:
	return has_equipment(Equipment.EquipmentType.PISTOL) or has_equipment(Equipment.EquipmentType.RIFLE)


## Returns true if the player has a bow equipped.
func has_bow_equipped() -> bool:
	return has_equipment(Equipment.EquipmentType.BOW)


## Room for one more weapon or tool under [member max_equipment].
func can_carry_equipment() -> bool:
	return get_all_weapons().size() < max_equipment


## True if an item of this type on this bone is already equipped or stowed.
func has_equipment_in_backpack(type: Equipment.EquipmentType, bone_name: String) -> bool:
	for item: Equipment in get_all_weapons():
		if item.equipment_type == type and item.bone_attachment_bone_name == bone_name:
			return true
	return false


func has_any_equipment(types: Array[Equipment.EquipmentType]) -> bool:
	for type: Equipment.EquipmentType in types:
		if equipment_by_type.has(type):
			return true
	return false


## True if any equipped item has the given boolean capability (e.g. &"can_log").
func has_equipment_with_capability(capability: StringName) -> bool:
	for item: Equipment in equipment:
		if item.get(capability):
			return true
	return false


func has_heavy_weapon_equipped() -> bool:
	return has_any_equipment([
		Equipment.EquipmentType.AXE_2H,
		Equipment.EquipmentType.FISHING_ROD,
		Equipment.EquipmentType.STAFF,
		Equipment.EquipmentType.SWORD_2H,
	])


func has_one_handed_or_shield_equipped() -> bool:
	return has_any_equipment([
		Equipment.EquipmentType.AXE_1H,
		Equipment.EquipmentType.DAGGER,
		Equipment.EquipmentType.SWORD_1H,
		Equipment.EquipmentType.SWORD_AND_SHIELD,
	])


func is_unarmed() -> bool:
	return equipment.is_empty()


## Equipped and stowed items, sorted by type then bone.
func get_all_weapons() -> Array[Equipment]:
	var all_weapons: Array[Equipment] = []
	all_weapons.assign(equipment)
	for child: Node in get_children():
		if child is BoneAttachment3D and child.get_child_count() > 0:
			all_weapons.append(child.get_child(0) as Equipment)
	all_weapons.sort_custom(func(a: Equipment, b: Equipment) -> bool:
		if a.equipment_type != b.equipment_type:
			return a.equipment_type < b.equipment_type
		return a.bone_attachment_bone_name < b.bone_attachment_bone_name
	)
	return all_weapons


func equip_weapon(target_item: Equipment) -> void:
	if equipment.has(target_item):
		return
	var attachment: BoneAttachment3D = target_item.get_parent() as BoneAttachment3D
	if attachment:
		equip_from_backpack(attachment)


## Equips [param pickup], an [Equipment] in the world, on the Player: a duplicate goes onto a new
## [BoneAttachment3D] on the skeleton, on the bone the item names and with the item's offsets, and joins
## [member equipment]; whatever conflicts with it is stowed first. Returns the copy on the skeleton, or null when
## the item names no bone, the Player already carries one of this type on this bone, or the backpack is full.
## [method Equipment.equip] and the walk-over pickups come through here.
func equip_pickup(pickup: Equipment) -> Equipment:
	if pickup == null or player == null or pickup.bone_attachment_bone_name.is_empty() \
			or has_equipment_in_backpack(pickup.equipment_type, pickup.bone_attachment_bone_name) \
			or not can_carry_equipment():
		return null

	stow_conflicting(pickup.bone_attachment_bone_name, pickup.is_exclusive)

	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.bone_name = pickup.bone_attachment_bone_name
	player.skeleton.add_child(attachment)

	var copy: Equipment = pickup.duplicate() as Equipment
	copy.player = player
	copy.scene_file_path = pickup.scene_file_path # so the inventory can save and drop it as its scene
	attachment.add_child(copy)
	# Disable world collision but keep the "Hitbox" and "WeaponBody" shapes so HitDetection can use them.
	for shape: Node in copy.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).disabled = shape.get_parent().name not in ["Hitbox", "WeaponBody"]
	for tree: Node in copy.find_children("*", "AnimationTree", true, false):
		(tree as AnimationTree).active = true
		(tree as AnimationTree).advance_expression_base_node = tree.get_path_to(copy)
	if pickup.is_inside_tree(): # The scene's hand offsets reach the copy from a pickup in the tree, as they always have
		copy.position = pickup.position_offset
		copy.rotation_degrees = pickup.rotation_offset_degrees
		copy.scale = pickup.scale_offset

	add_equipment(copy)
	return copy


## Moves a stowed attachment back onto the skeleton, stowing whatever conflicts with it.
func equip_from_backpack(attachment: BoneAttachment3D) -> void:
	var item: Equipment = attachment.get_child(0) as Equipment
	stow_conflicting(item.bone_attachment_bone_name, item.is_exclusive)
	attachment.reparent(player.skeleton, false)
	attachment.show()
	add_equipment(item)


## Stows every equipped item that conflicts with an incoming one: same bone, or either side exclusive.
func stow_conflicting(bone_name: String, is_exclusive: bool) -> void:
	for item: Equipment in equipment.duplicate():
		if item.bone_attachment_bone_name == bone_name or is_exclusive or item.is_exclusive:
			var attachment: BoneAttachment3D = item.get_parent() as BoneAttachment3D
			if attachment:
				_stow_attachment(attachment)
			else:
				remove_equipment(item) # Equipment added without a bone attachment (a bare test fixture) just leaves the set


func unequip_all() -> void:
	stow_conflicting("", true)


## Moves an equipped attachment (and its item) off the skeleton into the hidden backpack. The move happens before
## [signal equipment_changed] fires, so listeners never see the item between the skeleton and the backpack.
func _stow_attachment(attachment: BoneAttachment3D) -> void:
	var item: Equipment = attachment.get_child(0) as Equipment
	attachment.reparent(self, false)
	attachment.hide()
	remove_equipment(item)


# --- Helpers ---------------------------------------------------------------------------------------------------

func _empty_tab() -> Array:
	var tab: Array = []
	tab.resize(slots_per_tab)
	return tab


## An equipment item is picked up by instancing its scene and equipping it, as a walk-over pickup would.
func _add_equipment_item(item: Item) -> bool:
	return add_equipment_scene(item.equipment_scene) != null


## Equips a freshly instanced [param pickup] the way walking over it would: on the Player for the moment it
## equips, since [method equip_pickup] applies the scene's hand offsets only while the pickup is in the tree,
## then freed. Returns the copy on the skeleton, or null when the equip was refused.
func _equip_instance(pickup: Equipment) -> Equipment:
	player.add_child(pickup)
	var instance: Equipment = equip_pickup(pickup)
	player.remove_child(pickup)
	pickup.free()
	return instance


func _spawn_pickup(item: Item, count: int) -> Node3D:
	var pickup: Node3D = ITEM_PICKUP_SCENE.instantiate()
	pickup.set("item", item)
	pickup.set("count", count)
	_place_in_front(pickup)
	return pickup


## Adds [param node] to the Player's parent a metre in front of them.
func _place_in_front(node: Node3D) -> void:
	var facing: Vector3 = player.get_facing_direction()
	if facing == Vector3.ZERO:
		facing = Vector3.FORWARD
	player.get_parent().add_child(node)
	node.global_position = player.global_position + facing.normalized() * 1.0 + player.up_direction * 0.2


## The Player who dropped a piece of equipment has walked off it; it can be picked up again.
func _on_dropped_equipment_body_exited(body: Node3D, pickup: Node3D) -> void:
	if is_instance_valid(pickup) and pickup.has_meta("dropped_by") and body == pickup.get_meta("dropped_by"):
		pickup.remove_meta("dropped_by")


static func _is_scene_path(path: String) -> bool:
	return path.ends_with(".tscn") or path.ends_with(".scn")
