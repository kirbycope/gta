class_name MkRoster
extends RefCounted
## The kart roster as data: an original cast on Mario Kart 64's own stat classes.
##
## The drivers here are this addon's own, not the game's. What is taken from the
## [url=https://github.com/n64decomp/mk64]mk64 decompilation[/url] is the shape
## of the roster rather than who is in it, and that shape is narrower than the
## eight character select squares suggest. The decomp's
## [code]src/data/kart_attributes.c[/code] gives eight acceleration curves that
## resolve to exactly three distinct rows, and a top speed table that gives two
## distinct numbers. So the game has three kart classes wearing eight faces, and
## an original cast loses nothing by saying so.
##
## The three curves, quoted from [code]gKartAccelerationTables[/code]:
##
## [codeblock]
## light    2.0 2.0 2.5 2.6 2.6 2.0 1.5 0.8 0.8 0.8   and the higher top speed
## standard 2.0 2.0 2.0 1.6 1.4 1.2 1.0 0.8 0.6 0.4
## heavy    2.0 2.0 2.0 1.6 1.0 1.0 1.0 1.8 1.8 1.2   slow midrange, strong top end
## [/codeblock]
##
## Each row is ten bands across the kart's own top speed, and
## [code]player_accelerate[/code] scales the first seven by 3.2 and the last
## three by 2.8. A light kart pulls away hardest in the middle of the rev range
## and keeps the best top speed; a heavy one is dead through the midrange and
## then comes back strong. That is the whole handling difference between the
## game's characters, and it is reproduced exactly.
##
## [constant KART_BOX] is the one place the classes do not line up neatly. The
## decomp's [code]gKartBoundingBoxSizeTable[/code] gives 6.0 to only two of the
## three heavy characters and leaves the third on 5.5 with everyone else, so it
## is carried per kart here rather than per class.

## Ten band acceleration curves, straight from [code]gKartAccelerationTables[/code].
const CURVES: Dictionary = {
	&"light": [2.0, 2.0, 2.5, 2.6, 2.6, 2.0, 1.5, 0.8, 0.8, 0.8],
	&"standard": [2.0, 2.0, 2.0, 1.6, 1.4, 1.2, 1.0, 0.8, 0.6, 0.4],
	&"heavy": [2.0, 2.0, 2.0, 1.6, 1.0, 1.0, 1.0, 1.8, 1.8, 1.2],
}

## [code]player_accelerate[/code] scales the curve by band: 3.2 up to band 6,
## then 2.8 for the last three.
const CURVE_SCALE_LOW: float = 3.2
const CURVE_SCALE_HIGH: float = 2.8
const CURVE_SCALE_SPLIT: int = 7 ## The first band that takes the lower scale.
const CURVE_BANDS: int = 10

## The default collision size, and the one two of the heavy karts carry instead.
const KART_BOX: float = MkConst.BOUNDING_BOX
const KART_BOX_WIDE: float = MkConst.BOUNDING_BOX_HEAVY

## The addon's own drivers. [code]class[/code] picks the curve and the top
## speed, [code]box[/code] is the collision size, [code]colour[/code] is what
## the kart scene tints itself and what the HUD uses for the position board.
const DRIVERS: Dictionary = {
	&"pip": {"name": "Pip", "class": &"light", "box": KART_BOX, "colour": Color(0.95, 0.76, 0.20)},
	&"fennec": {"name": "Fennec", "class": &"light", "box": KART_BOX, "colour": Color(0.90, 0.45, 0.15)},
	&"sprig": {"name": "Sprig", "class": &"light", "box": KART_BOX, "colour": Color(0.40, 0.78, 0.35)},
	&"rook": {"name": "Rook", "class": &"standard", "box": KART_BOX, "colour": Color(0.22, 0.45, 0.85)},
	&"vesper": {"name": "Vesper", "class": &"standard", "box": KART_BOX, "colour": Color(0.75, 0.30, 0.65)},
	&"dozer": {"name": "Dozer", "class": &"heavy", "box": KART_BOX_WIDE, "colour": Color(0.55, 0.30, 0.18)},
	&"brack": {"name": "Brack", "class": &"heavy", "box": KART_BOX_WIDE, "colour": Color(0.30, 0.32, 0.36)},
	&"tusk": {"name": "Tusk", "class": &"heavy", "box": KART_BOX, "colour": Color(0.85, 0.85, 0.80)},
}


## The stat block for [param driver], or an empty dictionary when they are not
## in the roster.
static func stats(driver: StringName) -> Dictionary:
	return DRIVERS.get(driver, {})


## Every driver key, in roster order.
static func drivers() -> Array:
	return DRIVERS.keys()


## Which of the three classes [param driver] drives, empty when unknown.
static func kart_class(driver: StringName) -> StringName:
	var s: Dictionary = stats(driver)
	return s.get("class", &"") as StringName


## Whether [param driver] is in the light class, which is the one the top speed
## table singles out.
static func is_light(driver: StringName) -> bool:
	return kart_class(driver) == &"light"


## [param driver]'s top speed in metres per second for [param engine_class].
static func top_speed(driver: StringName, engine_class: StringName = &"150cc") -> float:
	if stats(driver).is_empty():
		return 0.0
	return MkConst.top_speed(engine_class, is_light(driver))


## How much speed [param driver] gains this frame, as a fraction of their top
## speed per second, at [param speed_fraction] of top speed.
##
## This is [code]player_accelerate[/code] in one expression. The game works in
## its own topSpeed units and adds to them once a frame; dividing by the top
## speed makes the answer a fraction, and multiplying by the frame rate makes it
## per second, so it can drive a Godot kart at any refresh rate.
static func acceleration_fraction(driver: StringName, speed_fraction: float) -> float:
	var curve: Array = CURVES.get(kart_class(driver), [])
	if curve.is_empty():
		return 0.0
	var band: int = clampi(int(speed_fraction * float(CURVE_BANDS)), 0, CURVE_BANDS - 1)
	var scale: float = CURVE_SCALE_LOW if band < CURVE_SCALE_SPLIT else CURVE_SCALE_HIGH
	return float(curve[band]) * scale


## [param driver]'s collision half width in metres, from their bounding box.
static func kart_width(driver: StringName) -> float:
	var s: Dictionary = stats(driver)
	return float(s.get("box", KART_BOX)) * MkConst.UNIT


## [param driver]'s colour, white when they are not in the roster.
static func colour(driver: StringName) -> Color:
	return stats(driver).get("colour", Color.WHITE) as Color


## [param driver]'s display name, the key itself when they are not in the roster.
static func display_name(driver: StringName) -> String:
	return String(stats(driver).get("name", String(driver)))
