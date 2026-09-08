# Godot Action Role Play Inventory (GARP) for Godot 4.8+

The inventory and the spells of the [3D Player Controller](../3d_player_controller/README.md): the weapons and tools on the Player's skeleton (eight at most) with the radial quick-select, Breath of the Wild style tabs of stacked items shown in a grid that works with a pad, the keyboard, the mouse and touch alike, Zelda style pickups that wait for Action, a spell tree unlocked with skill points and a loadout of up to eight spells for the ability wheel, and a plain `.tres` save in `user://` that you are welcome to edit.

> [!NOTE]
> Requires `addons/3d_player_controller`, and the player controller requires GARP: `player.tscn` instances `scenes/inventory.tscn` as its `Inventory` node, so the two addons ship together. What GARP uses of the player controller is written down in `CONTRACT.md`, and the garp repo carries a contract stub at `addons/3d_player_controller` that implements exactly that surface (a Player that does not move, the menu layers, an `Equipment` with its fields and walk-over handler, the two ability resources and the icons), so the addon is developed and tested there without the real addon. The tests come in two tiers: `tests/` is the contract tier and passes against the stub and the real addon alike; `tests/integration/` needs the real player controller (its state machine, skeleton, pause menu and ability wheel) and runs only in the player controller project. `Inventory`, `Spellbook`, `SpellTree`, `SpellNode`, `InventoryScreen`, `SpellsScreen`, `ItemPickup`, `Item`, `ItemSlot`, `EquipmentEntry` and `InventorySave` register their class names on their own; enabling the plugin adds the Spell Tree editor panel.

---

## Interactive Demo Scene

Open and run **`res://addons/garp/scenes/demo/demo.tscn`**: a yard with apples, a mushroom, iron ore, wood logs, an old key and a wooden sword lying about, and the Player. Walk up to one and press Action to pick it up. Pause (Esc / Start), then Inventory: Q and T (or the bumpers) switch tabs, Confirm lifts a stack and drops it on another slot, Use and Drop act on the stack under the cursor, Back returns to Pause. The demo turns `persist` on, so what you carry is in `user://garp_inventory.tres` next time.

The demo plays only in the player controller project. In the garp repo the scene opens on the contract stub's Player, which does not move, so nothing can be walked up to; that repo is for developing and contract-testing the addon, not for playing it.

| Node | What it is |
|---|---|
| `Ground`, `Pedestal` (`CSGBox3D`) | The yard. |
| `Apples`, `Mushroom`, `IronOre`, `WoodLogs`, `OldKey`, `WoodenSword` | `item_pickup.tscn` with an `Item` and a `count`; the sword's item carries `equipment_scene`, so picking it up puts it in the Player's hand. |
| `Player` | `player.tscn`; `demo.gd` points the Spellbook at `resources/spell_tree_demo.tres` (Stealth, then Heal behind it), grants 3 skill points, sets `player.inventory.persist = true` and loads the save. Pause, Spells: unlock on the Tree page, arrange the wheel on the Loadout page. |
| `HUD/Hint` | Shows `item_used` and `item_dropped` as they fire; GARP only signals, the game applies the effect. |

---

## How to Use

| Node | Where it goes | Set in the Inspector |
|---|---|---|
| `Inventory` (`scenes/inventory.tscn`, already inside `player.tscn`) | Child of the Player | `slots_per_tab` (20), `persist` (off by default so tests and bare Players leave the disk alone; turn it on in your game scene), `save_path` (`user://garp_inventory.tres`) |
| `InventoryScreen` (`scenes/inventory_screen.tscn`) | Nothing to add: the Player's `Pause` menu has `inventory_screen_scene` set to it and instances it beside itself; clear the path to drop the Inventory button | `columns` (5), `previous_tab_action` / `next_tab_action` (`ability` / `throw`: Q and T, the bumpers) |
| `Spellbook` (inside `inventory.tscn`) | Nothing to add | `tree` (a `SpellTree`), `skill_points` (the game grants them), `max_active` (8) |
| `SpellTree` (`.tres` with `scripts/spell_tree.gd`) | `resources/spells/` in your project | `display_name` and `nodes`: each `SpellNode` names its `ability`, `cost`, `requires` (abilities unlocked first) and its `row` and `column` on the grid. The grid is `SpellTree.CELL` pixels per cell (112×120) and a prerequisite is a straight line between the two spells' edges with an arrow pointing at the later one (`SpellTree.draw_connection`), on the Spells screen and in the editor alike, so the two are the same picture; edit the tree with the Spell Tree panel below |
| `SpellsScreen` (`scenes/spells_screen.tscn`) | Nothing to add: `Pause` has `spells_screen_scene` set to it, like the inventory screen | `previous_page_action` / `next_page_action` |
| `Item` (`.tres` with `scripts/item.gd`) | `resources/items/` in your project | `id`, `display_name`, `description`, `icon`, `icon_color` (tints the icon in the grid, so one icon serves many variants; a subclass can override `get_icon_color()`), `category` (Equipment, Materials, Food, Key Items), `max_stack`, `consumable`, and for Equipment the `equipment_scene`. Extend the script for items with more to say: the host project's `Fish` extends `Item` with hours, rain, lures and a model. `model_scene` is a 3D scene the inventory screen turns in the details panel instead of the icon; `get_model_scene()` can fall back to a placeholder, `prepare_model(model)` dresses the instanced model (a tint, say), and `get_details(owner)` returns extra lines printed under the description, with the Player passed as `owner`, and `get_badge(owner)` returns a short word the grid prints in the cell's top-right corner (the player controller's ammunition answers "Loaded" or "Default"); empty, the default, draws nothing. `throwable` marks a kind the game may throw (GARP only flags it; `Inventory.get_throwable_items()` lists them and `use_item(item)` uses the first stack of a kind), with `throw_damage` for what a thrown one does; `forget_equipment(item)` unequips a piece of equipment without a pickup and returns its scene path, and `add_equipment_scene(scene)` equips a fresh copy from one |
| `ItemPickup` (`scenes/item_pickup.tscn`) | In your level, on the ground | `item`, `count`, `show_icon` (the icon floats over the spot; add your own mesh and turn it off) |
| `Equipment` walk-over pickups | Unchanged: an `Equipment` scene with its `PlayerDetection` area is taken on contact and appears on the Equipment tab | Make it a `.tscn` so the save can bring it back; equipment placed inline in a level cannot be re-created and is not saved |

**Grid.** Every tab is `slots_per_tab` cells; Materials stack to their item's `max_stack` (999 for the demo ore), Key Items to 1. Confirm on a stack lifts it onto the cursor (it follows the mouse, or the focused cell on a pad or keyboard); Confirm on an empty cell moves it there, on the same item merges up to the limit, on anything else swaps. Cancel (B / Esc) puts a held stack back, or goes Back. Use emits `item_used(item, count)` and takes one from a consumable; Drop takes one and spawns an `ItemPickup` a metre in front of the Player, emitting `item_dropped(item, count, pickup)`. The Equipment tab lists what is on the skeleton and in the backpack: Confirm (or the Equip button) equips a stowed weapon or stows an equipped one, Drop puts its scene back in the world. `items_changed` fires after every stack change, `equipment_changed` after every equip.

**Pickups.** Standing in a pickup's `PlayerDetection` shows the `ActionPrompt` and reads the Action button as "Pick Up"; Action puts what fits in the inventory and frees the pickup once it is empty. Equipment items are picked up by instancing their `equipment_scene` and handing it to `equip_pickup`, exactly as a walk-over pickup does: the attach is GARP's (a `BoneAttachment3D` on the named bone holding a copy with the scene's hand offsets, world collision off, `Hitbox` kept; the instance is in the tree for the moment it equips so the offsets reach the copy; a save re-equips the same way); a second of the same type on the same bone is refused, so it stays on the ground.

**Quick select.** Unchanged from the player controller: tapping `last_weapon` / `next_weapon` (J / L, D-pad) cycles the owned weapons, holding opens the `RadialMenu`, and `custom_cycle_handler` / `custom_item_provider` still let a vehicle radio borrow both. The wheel draws `max_items` (8) wedges at most, plus the Unarmed wedge on the weapon wheel; `Inventory.max_equipment` (8) refuses a ninth weapon or tool until one is dropped, and the Equipment tab shows only those slots.

**Spells.** The `Spellbook` under the Inventory owns them. Whatever the Player's `Abilities.abilities` lists at start counts as unlocked and fills the first wheel slots, so a Player without a tree works as before. With a `tree` set, the Spells screen's Tree page draws every `SpellNode` at its cell (`SpellTree.cell_position`, in a tree area of fixed size: a small tree is centred in it, a large one scrolls and follows focus, and nodes scrolled out of view cannot be tapped) with an arrowed line from each prerequisite, the same picture as the editor's Spell Tree panel: dim while locked, plain while unlockable, marked once unlocked. Confirm (or Unlock) on an unlockable node spends its `cost` in `skill_points` (`unlock(ability)`, `can_unlock`, `spell_unlocked`), and the new spell takes the first free wheel slot. The Loadout page lists the unlocked spells on the left and the eight wheel slots on the right: Confirm on a spell lifts it, Confirm on a slot puts it there (a spell already on the wheel moves), Confirm on a filled slot with nothing held clears it, Clear empties the focused slot (`set_active(slot, ability)`, `clear_active(slot)`, `loadout_changed`). The wheel slots become the Player's `Abilities.abilities`, so the ability wheel and the Q tap follow the loadout; the picked spell falls back to the first slot when it leaves the wheel. Skill points, unlocked spells and the loadout save with the inventory.

**Spell Tree editor.** With the plugin enabled, selecting a `SpellTree` `.tres` in the FileSystem dock opens the Spell Tree bottom panel (`editor/spell_tree_editor.gd`), laid out like the AnimationTree editor's state machine. Every `SpellNode` is the very `SpellNodeButton` the Spells screen draws (scaled with the editor's display scale, so a HiDPI editor shows the same picture). Drag a spell to move it: it snaps to the nearest free cell (`column` and `row`, one `SpellTree.CELL` each) and slides back when that cell is taken. Turn on Connect and drag from the spell to unlock first onto the spell it unlocks: a line with an arrow joins them (links that would loop are refused). Click a spell or a line to select it; the toolbar's Cost spinner sets the selected spell's price and Remove (or Delete) takes the selected spell (out of every `requires` too) or line off the tree. The screen shows exactly what the panel shows, in a scrolling area that follows the focused node. The Abilities palette on the left lists every `.tres` whose script class extends `Ability` (found through the editor's file index, which knows a script-backed `.tres` by its `Resource` type, so only those few headers are read and the project's materials and meshes are never opened; Refresh rescans after you add one); double-click, Add to tree or drag one onto the graph to place it. Tree name edits `display_name`, every edit goes through the editor's undo history, and Save writes the file (a new tree, or one built into another resource, asks where and keeps that file from then on). Make one with New Resource, SpellTree, or open `addons/garp/resources/spell_tree_demo.tres`.

**Saving.** `save()` writes an `InventorySave` (every stack with its tab and slot, every scene-based weapon with whether it was equipped) to `save_path`; `load_save()` reads it back and re-equips. With `persist` on, `save()` runs after every change and `load_save()` on ready. The file is a readable `.tres`: change a count in a text editor and it is so.

**API.** `add_item(item, count) -> leftover`, `remove_item(item, count) -> taken`, `count_of(item)`, `has_item(item, count)`, `get_slots(category)`, `get_slot(category, index)`, `move_slot(category, from, to)`, `use_slot(category, index)`, `drop_slot(category, index)`, `equip_pickup(equipment) -> Equipment` (the copy on the skeleton, or null when refused), `drop_equipment(equipment)`, `stow_equipment(equipment)`, `save()`, `load_save()`, `apply_save(data)`.

---

## Example resources

Everything under `addons/garp/resources/` is an example for the demo scene and the tests, not game content. The rule: a resource in this folder references only `addons/garp` and `addons/3d_player_controller` (the declared dependency), never `res://resources/...` or `res://scenes/...` of a host project, so the addon loads in its own repo. The demo tree once pointed at the host's Shadowstep ability and broke the addon on its own; it now carries only the player controller's Stealth and Heal. A game's own trees and items go in the project's `resources/` (see the [project README](../../README.md#example-resources)); the two abilities the demo tree uses are described in the [player controller README](../3d_player_controller/README.md#example-resources).

| File | Class | What it is | Used by | Tests that load it |
|---|---|---|---|---|
| `resources/spell_tree_demo.tres` | `SpellTree` | "Demo Spells": Stealth, then Heal (cost 2) behind it | `scenes/demo/demo.gd` sets it as the Spellbook's `tree` | `tests/test_spellbook.gd`, `test_spells_screen.gd`, `test_spell_tree_editor.gd`, `tests/integration/test_ability_wheel_loadout.gd`, `test_pause_menu_flow.gd` |
| `resources/items/apple.tres`, `mushroom.tres` | `Item` | Food, consumable | The demo yard's pickups (`scenes/demo/demo.tscn`) | `tests/test_items.gd`, `test_inventory_screen.gd`, `test_item_pickup.gd`, `tests/integration/test_real_player_pickup.gd` |
| `resources/items/iron_ore.tres`, `wood_log.tres` | `Item` | Materials (the ore stacks to 999) | The demo yard | `test_items.gd`, `test_inventory_screen.gd` |
| `resources/items/old_key.tres` | `Item` | A key item, stack of 1 | The demo yard | `test_items.gd` |
| `resources/items/wooden_sword.tres` | `Item` | Equipment: `equipment_scene` is `scenes/demo/wooden_sword.tscn`, the icon is the player controller's `gladius.svg` | The demo yard | `test_items.gd`, `test_inventory_screen.gd`, `tests/integration/test_real_equipment.gd` |

Adding more examples here:

- A tree: New Resource, `SpellTree`, saved under `resources/`; select it in the FileSystem dock to edit it in the Spell Tree panel. Its abilities must come from `addons/3d_player_controller/resources/abilities/`, since GARP ships no abilities of its own.
- An item: New Resource, `Item`, saved under `resources/items/`, with an icon from `assets/icons/` (or the player controller's game icons) and, for equipment, an `equipment_scene` under `scenes/demo/`. Put it in the yard with an `item_pickup.tscn` in `demo.tscn`.
- The tests above preload the examples by file name, so renaming or removing one means updating them.

---

## Tests

The contract tier, in either project (the garp repo's `.gutconfig.json` runs exactly this):

```powershell
& 'C:\Godot\godot.exe' --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://addons/garp/tests -gexit
```

Both tiers, in the player controller project:

```powershell
& 'C:\Godot\godot.exe' --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://addons/garp/tests,res://addons/garp/tests/integration -gexit
```

Every file under `tests/integration/` starts with a comment saying it needs the real player controller. A contract test may use only what `CONTRACT.md` lists, and adds the InputMap actions it presses itself through `tests/contract_actions.gd` (`before_all` / `after_all`), since the stub registers none; when GARP needs more, widen the contract and the stub first.

---

## Assets

| Folder | Source | License |
|---|---|---|
| `assets/icons/` (`materials.svg`, `food.svg`, `key.svg`, `apple.svg`, `mushroom.svg`, `ore.svg`, `wood.svg`) | Drawn for this addon | CC0 |
| The Equipment tab and the wooden sword use `gladius.svg` from the player controller | [game-icons.net](https://game-icons.net/) | CC BY 3.0 |

---

## License

MIT, see the repository LICENSE.
