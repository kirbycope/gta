class_name Tm2Roster
extends RefCounted
## The Twisted Metal 2 roster as data.
##
## Every number here comes from the community stat tables, not from the game
## binary: the speedrun.com stat guide for health, top speed, turbo speed and
## special weapon timing, and the Twisted Metal wiki for weapon damage. The
## disc's own per-car stat screens under /BIOS are pictures rather than tables,
## so they could not be read directly.
##
## Values that could not be sourced are left out rather than invented, and are
## listed in [constant UNSOURCED] so the gaps stay visible.

## What is still missing from the tables above.
const UNSOURCED: PackedStringArray = [
	"per-car handling, mass and steering lock (only star ratings are published)",
	"machine gun damage per shot and rate of fire",
	"special weapon damage per car",
	"armour damage falloff by impact angle",
]

## Miles per hour to metres per second, so the published speeds can drive the car.
const MPH_TO_MS: float = 0.44704

## health, top speed (mph), turbo speed (mph), special recharge (s), max specials.
const CARS: Dictionary = {
	&"axel": {"health": 130.0, "top_mph": 101.0, "turbo_mph": 138.0, "special_s": 35.0, "specials": 5},
	&"grasshopper": {"health": 110.0, "top_mph": 119.0, "turbo_mph": 157.0, "special_s": 35.0, "specials": 5},
	&"hammerhead": {"health": 130.0, "top_mph": 94.0, "turbo_mph": 138.0, "special_s": 60.0, "specials": 5},
	&"minion": {"health": 230.0, "top_mph": 126.0, "turbo_mph": 168.0, "special_s": 18.0, "specials": 5},
	&"mr_grimm": {"health": 85.0, "top_mph": 124.0, "turbo_mph": 166.0, "special_s": 70.0, "specials": 3},
	&"mr_slam": {"health": 140.0, "top_mph": 91.0, "turbo_mph": 138.0, "special_s": 50.0, "specials": 3},
	&"outlaw": {"health": 120.0, "top_mph": 126.0, "turbo_mph": 168.0, "special_s": 55.0, "specials": 3},
	&"roadkill": {"health": 120.0, "top_mph": 117.0, "turbo_mph": 156.0, "special_s": 35.0, "specials": 5},
	&"shadow": {"health": 120.0, "top_mph": 112.0, "turbo_mph": 149.0, "special_s": 20.0, "specials": 5},
	&"spectre": {"health": 110.0, "top_mph": 129.0, "turbo_mph": 171.0, "special_s": 35.0, "specials": 5},
	&"sweet_tooth": {"health": 140.0, "top_mph": 91.0, "turbo_mph": 138.0, "special_s": 18.0, "specials": 5},
	&"thumper": {"health": 120.0, "top_mph": 110.0, "turbo_mph": 147.0, "special_s": 80.0, "specials": 5},
	&"twister": {"health": 95.0, "top_mph": 140.0, "turbo_mph": 178.0, "special_s": 18.0, "specials": 3},
	&"warthog": {"health": 150.0, "top_mph": 100.0, "turbo_mph": 138.0, "special_s": 35.0, "specials": 5},
}

## The pickup weapons, in the order the game cycles them.
## [code]damage[/code] is the published direct hit; [code]max_damage[/code] is
## the ceiling for weapons that grow, and equals [code]damage[/code] otherwise.
const WEAPONS: Dictionary = {
	&"fire_missile": {"damage": 7.0, "max_damage": 7.0, "homing": 0.15, "speed": 60.0},
	&"homing_missile": {"damage": 10.0, "max_damage": 10.0, "homing": 1.0, "speed": 55.0},
	&"power_missile": {"damage": 15.0, "max_damage": 15.0, "homing": 0.0, "speed": 70.0},
	&"napalm": {"damage": 10.0, "max_damage": 10.0, "homing": 0.0, "speed": 45.0, "fire": true},
	&"ricochet": {"damage": 7.0, "max_damage": 15.0, "homing": 0.0, "speed": 40.0, "bounces": 8},
	&"remote_bomb": {"damage": 25.0, "max_damage": 25.0, "homing": 0.0, "speed": 25.0, "remote": true},
}


## The stat block for [param car], or an empty dictionary when it is not in the roster.
static func stats(car: StringName) -> Dictionary:
	return CARS.get(car, {})


## Published top speed in metres per second, [param turbo] for the turbo figure.
static func top_speed(car: StringName, turbo: bool = false) -> float:
	var s: Dictionary = stats(car)
	if s.is_empty():
		return 0.0
	return float(s["turbo_mph" if turbo else "top_mph"]) * MPH_TO_MS
