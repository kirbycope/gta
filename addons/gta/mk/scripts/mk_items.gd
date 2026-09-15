class_name MkItems
extends RefCounted
## The item set, and the roulette that hands one out.
##
## Mario Kart 64 carries sixteen item slots, and the
## [url=https://github.com/n64decomp/mk64]mk64 decompilation[/url] names them in
## [code]include/defines.h[/code]'s [code]ITEM_[/code] enum. The mechanics of
## those sixteen are what this file reproduces; the names are the addon's own,
## the way [MkRoster]'s drivers are. Slot for slot they line up, so a course
## converted out of a ROM can hand its item ids straight over.
##
## [b]How the roulette really works.[/b] It is not a weighted random draw.
## [code]gen_random_item[/code] in [code]src/update_objects.c[/code] keeps a
## rolling index into a flat hundred entry table, one table per finishing
## position, and simply reads the item sitting at that index:
##
## [codeblock]
## sRandomItemIndex = (rand + sRandomItemIndex + gControllerRandom + gRaceFrameCounter) % 100
## randomItem = curve[rank * 100 + sRandomItemIndex]
## [/codeblock]
##
## So the odds are a property of how many times each item appears in that
## hundred, the rolling index makes consecutive draws non independent, and the
## race frame counter stirs it. [method draw] reproduces all three.
##
## [b]The one thing this cannot ship.[/b] Those tables are not in the decomp
## source. They are ROM data reached through a segment pointer, which is why the
## decomp only ever names the symbol. [code]tools/extract_mk64.py[/code] reads
## them out of your own copy of the game into
## [code]item_curves.tres[/code]. Without that file the roulette falls back to
## [constant FALLBACK_CURVE], an even spread that is deliberately not the real
## odds and says so through [method has_real_odds], so a demo runs on a fresh
## clone without quietly pretending to be accurate.

## Slot numbers, matching the decomp's [code]ITEM_[/code] enum one for one so a
## converted course's item ids need no translation.
enum Item {
	NONE = 0, ## ITEM_NONE
	HAZARD = 1, ## ITEM_BANANA: dropped behind, spins out whoever touches it.
	HAZARD_BUNCH = 2, ## ITEM_BANANA_BUNCH: five of them, dropped one at a time.
	SHOT = 3, ## ITEM_GREEN_SHELL: fired straight, bounces off walls.
	TRIPLE_SHOT = 4, ## ITEM_TRIPLE_GREEN_SHELL: three, orbiting until fired.
	HOMING_SHOT = 5, ## ITEM_RED_SHELL: seeks the kart ahead.
	TRIPLE_HOMING_SHOT = 6, ## ITEM_TRIPLE_RED_SHELL.
	LEADER_SHOT = 7, ## ITEM_BLUE_SPINY_SHELL: goes for whoever is leading.
	JOLT = 8, ## ITEM_THUNDERBOLT: shrinks and slows the whole field.
	DECOY = 9, ## ITEM_FAKE_ITEM_BOX: looks like a box, is not.
	INVINCIBILITY = 10, ## ITEM_STAR: untouchable, and faster, but see the force penalty.
	PHANTOM = 11, ## ITEM_BOO: steals an item and passes through hazards.
	BOOST = 12, ## ITEM_MUSHROOM.
	DOUBLE_BOOST = 13, ## ITEM_DOUBLE_MUSHROOM.
	TRIPLE_BOOST = 14, ## ITEM_TRIPLE_MUSHROOM.
	SUPER_BOOST = 15, ## ITEM_SUPER_MUSHROOM: boost on tap for a while.
}

## How long a super boost lasts. [code]consume_item[/code] sets its timer to
## 0x258, so 600 frames, which is 20 s at the game's 30 fps.
const SUPER_BOOST_FRAMES: int = 600

## How many uses an item hands over, for the ones that give more than one.
const USES: Dictionary = {
	Item.HAZARD_BUNCH: 5,
	Item.TRIPLE_SHOT: 3,
	Item.TRIPLE_HOMING_SHOT: 3,
	Item.DOUBLE_BOOST: 2,
	Item.TRIPLE_BOOST: 3,
}

## Display names for the HUD, since the enum names are not what a player reads.
const NAMES: Dictionary = {
	Item.NONE: "",
	Item.HAZARD: "Hazard",
	Item.HAZARD_BUNCH: "Hazard Bunch",
	Item.SHOT: "Shot",
	Item.TRIPLE_SHOT: "Triple Shot",
	Item.HOMING_SHOT: "Homing Shot",
	Item.TRIPLE_HOMING_SHOT: "Triple Homing Shot",
	Item.LEADER_SHOT: "Leader Shot",
	Item.JOLT: "Jolt",
	Item.DECOY: "Decoy",
	Item.INVINCIBILITY: "Invincibility",
	Item.PHANTOM: "Phantom",
	Item.BOOST: "Boost",
	Item.DOUBLE_BOOST: "Double Boost",
	Item.TRIPLE_BOOST: "Triple Boost",
	Item.SUPER_BOOST: "Super Boost",
}

## Items that are dropped behind the kart rather than fired ahead of it.
const DROPPED: PackedInt32Array = [Item.HAZARD, Item.HAZARD_BUNCH, Item.DECOY]
## Items that boost rather than attack.
const BOOSTS: PackedInt32Array = [
	Item.BOOST, Item.DOUBLE_BOOST, Item.TRIPLE_BOOST, Item.SUPER_BOOST,
]

const CURVE_LENGTH: int = 100 ## Entries per finishing position, from the decomp.

## Where [code]tools/extract_mk64.py[/code] writes the real tables.
const CURVES_PATH: String = "res://addons/gta/mk/assets/item_curves.tres"

## What the roulette uses when the real tables have not been extracted. Every
## item once, so something comes out of every box, and plainly not the real
## odds: the game never gives eighth place the same chance of a hazard as first.
const FALLBACK_CURVE: PackedInt32Array = [
	Item.HAZARD, Item.SHOT, Item.BOOST, Item.HOMING_SHOT,
	Item.HAZARD_BUNCH, Item.TRIPLE_SHOT, Item.DOUBLE_BOOST, Item.TRIPLE_HOMING_SHOT,
	Item.INVINCIBILITY, Item.TRIPLE_BOOST, Item.DECOY, Item.JOLT,
	Item.PHANTOM, Item.LEADER_SHOT, Item.SUPER_BOOST, Item.SHOT,
]


## Whether the real per position tables have been extracted from a ROM. The HUD
## and the README both ask, so a demo can say out loud that its odds are stand
## in ones rather than leaving it to be discovered.
static func has_real_odds() -> bool:
	return ResourceLoader.exists(CURVES_PATH)


## The hundred entry table for [param rank], zero based, or an empty array when
## the real tables are not present.
static func curve_for_rank(rank: int) -> PackedInt32Array:
	if not has_real_odds():
		return PackedInt32Array()
	var curves: Resource = load(CURVES_PATH)
	if curves == null or not curves.has_method(&"curve_for_rank"):
		return PackedInt32Array()
	return curves.call(&"curve_for_rank", rank) as PackedInt32Array


## Draw an item for a kart lying [param rank] (zero based, so 0 is the leader).
##
## [param rolling_index] is the game's [code]sRandomItemIndex[/code], carried
## between draws by the caller, and [param frame] its
## [code]gRaceFrameCounter[/code]. Both are part of the real selection and are
## passed in rather than kept here so a test can drive the sequence. Returns the
## item and the rolling index to keep for next time.
static func draw(rank: int, rolling_index: int, frame: int) -> Dictionary:
	var curve: PackedInt32Array = curve_for_rank(rank)
	if curve.is_empty():
		curve = FALLBACK_CURVE
	var next: int = posmod(randi_range(0, CURVE_LENGTH - 1) + rolling_index + frame, CURVE_LENGTH)
	return {"item": curve[next % curve.size()], "rolling_index": next}


## How many times [param item] can be used once drawn.
static func uses(item: int) -> int:
	return int(USES.get(item, 1))


## The HUD's name for [param item].
static func display_name(item: int) -> String:
	return String(NAMES.get(item, ""))


## Whether [param item] is dropped behind rather than fired ahead.
static func is_dropped(item: int) -> bool:
	return DROPPED.has(item)


## Whether [param item] is one of the boosts.
static func is_boost(item: int) -> bool:
	return BOOSTS.has(item)
