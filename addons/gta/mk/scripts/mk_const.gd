class_name MkConst
extends RefCounted
## Mario Kart 64's own kart physics, converted from game units to metres.
##
## Every number here is read out of the
## [url=https://github.com/n64decomp/mk64]mk64 decompilation[/url] rather than
## tuned by feel, the same way [RlConst] is read out of RocketSim. The file
## references below are paths in that repository, so each line can be checked
## against the source without trusting this one.
##
## [b]The unit scale, and why it is not a guess.[/b] The decomp works in game
## units per frame at 30 fps, and two independent lines pin that to metres.
## [code]src/player_controller.c[/code]'s [code]func_80030150[/code] converts a
## kart's speed for the speedometer with [code](speed / 18.0f) * 216.0f[/code],
## which is speed times 12, and the speedometer reads km/h. So one unit per
## frame is 12 km/h, which at 30 fps makes one game unit
## [constant UNIT] of a metre. The check is the kart's own collision size:
## [code]gKartBoundingBoxSizeTable[/code] is 5.5 units, which comes out 1.22 m
## across, a real go-kart. Course geometry agrees too, putting Luigi Raceway's
## footprint at roughly 229 by 590 m.
##
## [b]The drive model.[/b] Velocity is integrated in
## [code]player_controller.c[/code] as
## [code]v += ((force - v * 0.12 * kartFriction) / 6000) / divisor[/code], so a
## kart settles where drive force balances drag, at
## [code]force / (0.12 * kartFriction)[/code]. The force itself is
## [code]topSpeed * topSpeed / 25[/code], which is how
## [constant TOP_SPEED_KMH] below is arrived at. That this is the real
## relationship is not inference: the decomp's own precomputed force table in
## [code]src/data/kart_attributes.c[/code] holds 3364, 3844, 4096 and 2401,
## which are exactly 290, 310, 320 and 245 squared over 25.
##
## Values that could not be sourced are listed in [constant UNSOURCED] rather
## than invented, the same way [RlConst] and [TwRoster] handle their gaps.

## What is not taken from the decompilation, and is a judgement call instead.
const UNSOURCED: PackedStringArray = [
	"the item probability curves, which live in the ROM as 100 byte per rank tables rather than in"
		+ " the decomp source; tools/extract_mk64.py reads them out of your own copy, and the demo"
		+ " falls back to an even spread that is clearly marked as not the real odds",
	"suspension stiffness, damping and travel, because mk64 has no suspension: it casts four tyre"
		+ " points at a heightmap where Godot's VehicleBody3D has real springs",
	"wheel friction slip, for the same reason: mk64's grip is a per surface table, not a slip curve",
	"the steering lock in radians, which mk64 stores as an angular velocity applied to the kart's"
		+ " facing rather than as a wheel angle",
	"how far a shell homes and how fast it closes, which is actor code this port has not read",
	"how much faster a boost actually makes a kart, and how much the CPU catch-up adds; the"
		+ " decomp's 580 and 380 figures for both are in an accumulator whose conversion to"
		+ " topSpeed units it never states, so BOOST_SPEED_SCALE is a judgement instead",
	"when the CPU catch-up effect is switched on, which is a rubber banding rule rather than a number",
	"the camera behaviour, which is its own subsystem in the game",
]

## One game unit in metres: a ninth, from the speedometer conversion above.
const UNIT: float = 1.0 / 9.0
const FPS: float = 30.0 ## The frame rate every per frame figure below is quoted at.
## Units per frame to km/h, from [code]func_80030150[/code]'s [code](speed / 18) * 216[/code].
const UNITS_PER_FRAME_TO_KMH: float = 12.0

# ---------------------------------------------------------------- drive -----

## [code]gKartFrictionTable[/code], the same for every character.
const KART_FRICTION: float = 5800.0
## The drag coefficient the integrator multiplies friction by, so drag is
## [code]v * 696[/code] and a kart settles at [code]force / 696[/code].
const DRAG_FACTOR: float = 0.12
## [code]gKartGravityTable[/code]. Not Earth's: it is the game's own downforce.
const KART_GRAVITY: float = 2600.0
## [code]gKartBoundingBoxSizeTable[/code]: 5.5 units, 6.0 for the heavy karts.
const BOUNDING_BOX: float = 5.5
const BOUNDING_BOX_HEAVY: float = 6.0

## [code]gTopSpeedTable[/code], in the game's own topSpeed units, indexed by
## engine class. The second figure of each pair is the light karts, which are
## the only ones the table gives a different number to.
const TOP_SPEED_UNITS: Dictionary = {
	&"50cc": {"standard": 290.0, "light": 294.0},
	&"100cc": {"standard": 310.0, "light": 314.0},
	&"150cc": {"standard": 320.0, "light": 324.0},
	&"extra": {"standard": 310.0, "light": 314.0},
	&"battle": {"standard": 245.0, "light": 245.0},
}

## [code]gKartHopInitialVelocityTable[/code]: the hop that starts a drift.
const HOP_VELOCITY: float = 0.93
## [code]gKartHopJerkTable[/code]: how fast the hop's acceleration builds.
const HOP_JERK: float = 0.03
## [code]kart_hop[/code] sets [code]kartGravity[/code] to this for the hop.
const HOP_GRAVITY: float = 500.0

# ---------------------------------------------------------------- drift -----

## [code]update_player_drift_duration[/code] counts up one a frame while
## drifting and back down when not, and clamps here. At 30 fps that is 3.33 s.
const DRIFT_DURATION_CAP: int = 100
## [code]func_8002A79C[/code] pays a mini turbo out once driftState reaches this.
const MINI_TURBO_DRIFT_STATE: int = 2
## The same function ends the mini turbo at 0x1F frames, so 31 at 30 fps.
const MINI_TURBO_FRAMES: int = 31
## [code]func_8002A704[/code] sets boostTimer to 0x50 for a boost item.
const BOOST_FRAMES: int = 80
## The speed a mini turbo pulls a human kart towards, approached at 0.2 a frame.
##
## [b]Read the units before using these.[/b] They are [code]unk_0E8[/code] in
## [code]player_controller.c[/code], which is a separate accumulator from the
## [code]topSpeed[/code] units the acceleration curve works in, and the decomp
## does not name what converts between the two. So these are recorded here
## because they are real figures, but they must not be fed to a kart's speed
## directly: doing so reads 580 as though it were a topSpeed of 580 and makes a
## boost nearly twice a kart's top speed. [constant BOOST_SPEED_SCALE] is what
## the port actually uses, and it is a judgement rather than a reading.
const MINI_TURBO_TARGET: float = 580.0
const MINI_TURBO_RATE: float = 0.2
## What a CPU kart on catch-up pulls towards, at 0.5 a frame. Same units, and so
## the same warning as above.
const CPU_CATCHUP_TARGET: float = 380.0
const CPU_CATCHUP_RATE: float = 0.5

## How far over its own ceiling a boost carries a kart. A judgement, for the
## unit reason above, and named in [constant UNSOURCED].
const BOOST_SPEED_SCALE: float = 1.25

## [code]func_80030150[/code]'s drift bonus: the kart keeps
## [code]0.004[/code] of its yaw rate as drive force while drifting, against
## [code]0.01[/code] plus the per character figure when it is merely turning.
## That difference is the whole reason a drift is faster than a turn.
const DRIFT_TURN_FORCE: float = 0.004
const TURN_FORCE_BASE: float = 0.01
## The extra a kart drifting away from its turn keeps, for its first 10 frames.
const DRIFT_OUTSIDE_FORCE: float = 0.008
const DRIFT_OUTSIDE_FRAMES: int = 10

## [code]func_80030150[/code] docks a kart under 20 km/h this much drive force,
## and this much again while it is under the lightning effect.
const SLOW_PENALTY: float = -0.2
const LIGHTNING_PENALTY: float = -0.55
const SLOW_PENALTY_KMH: float = 20.0
## An invincible kart loses this much force, which is why a star is not a boost.
const STAR_PENALTY: float = -0.25

## The slope term, docked per degree of gradient. The game splits at 0x11
## degrees, using the gentler figure under it.
const SLOPE_FORCE_STEEP: float = 0.0126 / 3.0
const SLOPE_FORCE_SHALLOW: float = 0.026 / 3.0
const SLOPE_SPLIT_DEGREES: float = 17.0

## [code]update_steering_large[/code] divides the stick by
## [code]8 + speed / 50[/code], which is why a fast kart turns less for the
## same stick. Quoted as the divisor's two terms.
const STEER_DIVISOR_BASE: float = 8.0
const STEER_DIVISOR_SPEED: float = 50.0
## The stick reading a kart has to pass for the game to treat it as a hard turn.
const HARD_STEER: int = 40

# -------------------------------------------------------------- surfaces -----

## The surface types, from [code]docs/courses/surfacetypes.md[/code] and the
## [code]SURFACE_TYPE[/code] enum. The ids are the game's own, so a course
## converted out of a ROM keeps them.
const SURFACE_SOLID: int = 1
const SURFACE_DIRT: int = 2
const SURFACE_SAND: int = 3
const SURFACE_CEMENT: int = 4
const SURFACE_SNOW: int = 5
const SURFACE_BRIDGE: int = 6
const SURFACE_DIRT_OFF_ROAD: int = 7
const SURFACE_GRASS: int = 8
const SURFACE_ICE: int = 9
const SURFACE_WET_SAND: int = 10
const SURFACE_SNOW_OFF_ROAD: int = 11
const SURFACE_ROCK_WALL: int = 12
const SURFACE_DIRT_OFF_ROAD_2: int = 13
const SURFACE_TRACK_BALLAST: int = 14
const SURFACE_CAVE: int = 15
const SURFACE_ROPE_BRIDGE: int = 16
const SURFACE_WOOD_BRIDGE: int = 17
const SURFACE_BOOST_RAMP: int = 252
const SURFACE_OUT_OF_BOUNDS: int = 253
const SURFACE_GRAVITY_RAMP: int = 254
const SURFACE_WALL: int = 255

## Which surfaces slow a kart down. The game does this with a per surface force
## table rather than a flag, but the set is what the surface type doc lists as
## off road.
const OFF_ROAD_SURFACES: PackedInt32Array = [
	SURFACE_DIRT, SURFACE_SAND, SURFACE_SNOW, SURFACE_DIRT_OFF_ROAD, SURFACE_GRASS,
	SURFACE_WET_SAND, SURFACE_SNOW_OFF_ROAD, SURFACE_DIRT_OFF_ROAD_2, SURFACE_TRACK_BALLAST,
]

# ----------------------------------------------------------------- race -----

const RACERS: int = 8 ## [code]NUM_PLAYERS[/code] in [code]include/defines.h[/code].
## [code]src/racing/race_logic.c[/code] ends a race when lapCount reaches 3.
const LAPS: int = 3


## Top speed in metres per second for [param engine_class], [param light] for a
## light kart. Derived rather than tabulated: the game's topSpeed figure squared
## over 25 is the drive force, and the kart settles where that balances drag.
static func top_speed(engine_class: StringName, light: bool = false) -> float:
	var row: Dictionary = TOP_SPEED_UNITS.get(engine_class, {})
	if row.is_empty():
		return 0.0
	return units_to_ms(top_speed_units_per_frame(float(row["light" if light else "standard"])))


## The settled speed in units per frame for a kart whose topSpeed figure is
## [param top_speed_units], from the integrator's balance point.
static func top_speed_units_per_frame(top_speed_units: float) -> float:
	return drive_force(top_speed_units) / (DRAG_FACTOR * KART_FRICTION)


## The drive force a kart with [param top_speed_units] pushes with, which the
## game precomputes as the square over 25.
static func drive_force(top_speed_units: float) -> float:
	return (top_speed_units * top_speed_units) / 25.0


## Units per frame to metres per second, through the speedometer's km/h.
static func units_to_ms(units_per_frame: float) -> float:
	return units_per_frame * UNITS_PER_FRAME_TO_KMH / 3.6


## Metres per second to the km/h a speedometer would show.
static func ms_to_kmh(speed: float) -> float:
	return speed * 3.6


## Frames at the game's 30 fps as seconds, so the timings above can be used
## directly without scattering the same division through the port.
static func frames(count: int) -> float:
	return float(count) / FPS


## Whether [param surface] is one of the off road types.
static func is_off_road(surface: int) -> bool:
	return OFF_ROAD_SURFACES.has(surface)
