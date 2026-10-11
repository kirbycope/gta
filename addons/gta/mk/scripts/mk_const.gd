class_name MkConst
extends RefCounted
## Mario Kart 64's own kart physics, converted from game units to metres.
##
## Every number here is read out of the
## [url=https://github.com/n64decomp/mk64]mk64 decompilation[/url] rather than
## tuned by feel. The file references below are paths in that repository, so
## each line can be checked against the source without trusting this one;
## [code]:1234[/code] is a line in [code]src/player_controller.c[/code].
##
## [b]The unit scale, and why it is not a guess.[/b] The decomp works in game
## units per frame at 30 fps, and two independent lines pin that to metres.
## [code]func_80030150[/code] converts a kart's speed for the speedometer with
## [code](speed / 18.0f) * 216.0f[/code], which is speed times 12, and the
## speedometer reads km/h. So one unit per frame is 12 km/h, which at 30 fps
## makes one game unit [constant UNIT] of a metre. The check is the kart's own
## collision size: [code]gKartBoundingBoxSizeTable[/code] is 5.5 units, which
## comes out 1.22 m across, a real go-kart.
##
## [b]The model.[/b] A kart is a point with a facing. With A held,
## [code]player_accelerate_alternative[/code] adds the character's acceleration
## table to [code]currentSpeed[/code] once a frame; the drive force is
## [code]currentSpeed * currentSpeed / 25[/code]; [code]func_80030150[/code] cuts
## it by a loss fraction built from the turn, the surface, the slope and the
## speed; and [code]func_8002D268[/code] integrates
## [code]v += (force * facing + gravity + lateral - v * 0.12 * 5800) / 6000[/code],
## which settles at [code]force / 696[/code] and lags the facing by 8.6 frames.
## That lag is the whole of the game's grip. [MkCar] is that model, and the
## names below are the game's wherever it has one.

## What is not taken from the decompilation, and is a judgement call instead.
const UNSOURCED: PackedStringArray = [
	"the item probability curves, which live in the ROM as 100 byte per rank tables rather than in"
		+ " the decomp source; tools/extract_mk64.py reads them out of your own copy, and the demo"
		+ " falls back to an even spread that is clearly marked as not the real odds",
	"how far a shell homes and how fast it closes, which is actor code this port has not read",
	"the computer drivers' own update path (control_cpu_movement, apply_cpu_turn), which steers"
		+ " along a baked path; they drive the human model here, with the CPU acceleration scaling"
		+ " and the CPU catch-up force the game gives them",
	"which way the game's lateral kick points: the decomp applies it along the kart's own X with a"
		+ " sign that depends on the game's matrix handedness, and it is taken here as toward the"
		+ " outside of the turn, which is the reading that keeps a drift sliding; inward, the"
		+ " velocity caught the nose up in a second and the drift cancelled itself",
	"the wall response beyond the speed it costs: the game resolves a wall through its own terrain"
		+ " collision, and here the body stops at it and loses the same 6 units a frame",
	"the landing tumble, which is an animation on a timer rather than physics",
]

## One game unit in metres: a ninth, from the speedometer conversion above.
const UNIT: float = 1.0 / 9.0
const FPS: float = 30.0 ## The frame rate every per frame figure below is quoted at.
## Units per frame to km/h, from [code]func_80030150[/code]'s [code](speed / 18) * 216[/code].
const UNITS_PER_FRAME_TO_KMH: float = 12.0
## The game keeps angles in 65536ths of a turn; [code]DEGREES(1)[/code] is 182.04.
const ANGLE_UNITS_PER_TURN: float = 65536.0
const STICK_MAX: float = 53.0 ## [code]get_clamped_stickX_with_deadzone[/code] gives -53..53 past the deadzone.

# ---------------------------------------------------------------- drive -----

## [code]gKartFrictionTable[/code], the same for every character.
const KART_FRICTION: float = 5800.0
## The drag coefficient the integrator multiplies friction by, so drag is
## [code]v * 696[/code] and a kart settles at [code]force / 696[/code].
const DRAG_FACTOR: float = 0.12
const INTEGRATOR_DIVISOR: float = 6000.0 ## [code]:2216[/code]: the whole numerator is divided by this each frame.
const FORCE_DIVISOR: float = 25.0 ## [code]unk_08C = currentSpeed * currentSpeed / 25[/code].
## [code]gKartGravityTable[/code]. Not Earth's: it is the game's own downforce.
const KART_GRAVITY: float = 2600.0
const GROUND_GRAVITY_SCALE: float = 0.925 ## [code]:2184[/code]: the slope's share of gravity on asphalt.
## [code]sp104[/code] at [code]:2112[/code]: the slope's share of gravity on any other surface, by tens of km/h.
const GROUND_GRAVITY_BY_SPEED: PackedFloat32Array = [0.825, 0.8, 0.725, 0.625, 0.425, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3]
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

## [code]player_accelerate[/code] ([code]:3708[/code]), the computer drivers'
## path, scales the table by 3.2 for the first seven bands and 2.8 for the last
## three; [code]player_accelerate_alternative[/code] ([code]:3302[/code]), the
## human path, adds the table as it is. That gap is the game's rubber band.
const CPU_ACCELERATION_SCALE_LOW: float = 3.2
const CPU_ACCELERATION_SCALE_HIGH: float = 2.8
const CPU_ACCELERATION_SCALE_SPLIT: int = 7
const SLOPE_ACCELERATION: float = 0.05 ## [code]:3308[/code]: per degree of slope, added to each band (downhill helps).
const COAST_DECELERATION: float = 1.0 ## [code]:4680[/code]: off currentSpeed each frame with A released.
const BRAKE_DECELERATION: float = 1.2 ## [code]func_800323E4[/code] [code]:3627[/code]: with B held.
const BRAKE_DECELERATION_SETTLED: float = 2.5 ## [code]:3625[/code]: once the brake slide has counted up to its cap.
const BRAKE_DECELERATION_SLOW: float = 4.0 ## [code]:3622[/code]: on top, under 20 km/h.
const BRAKE_SLOW_KMH: float = 20.0
const BRAKE_SLIDE_RATE: float = 0.02 ## [code]:3609[/code]: unk_20C counts up this much a frame while braking and slowing...
const BRAKE_SLIDE_CAP: float = 2.0 ## [code]:3611[/code]: ...to this.
const BRAKE_SLIDE_DIVISOR: float = 0.6 ## [code]:2218[/code]: the integrator is divided by [code]unk_20C * 0.6 + 1[/code] under a hard steer.
const BRAKE_HARD_STEER: float = 40.0 ## [code]:2213[/code]: the stick reading past which the brake slide divisor applies.
const HELD_DRIFT_DIVISOR: float = 2.0 ## [code]:2144[/code]: a drift held to the outside at its counter cap adds this to the divisor...
const HELD_DRIFT_DECELERATION: float = 4.0 ## [code]:2017[/code]: ...and costs this off currentSpeed a frame.
const BRAKE_REVERSE_PUSH: float = 4500.0 ## [code]:2200[/code]: braking with no force, the kart's backward creep is pushed back by this per unit.
const MOVE_BACKWARDS_UNITS: float = 0.1 ## [code]:2192[/code]: moving back more than this a frame is "moving backwards".
const REVERSE_SPEED_UNITS: float = 140.0 ## [code]:4697[/code]: B with the stick back under 5 km/h reverses at this currentSpeed.
const REVERSE_STICK: float = 49.0 ## [code]0x31[/code]: the stick has to be this far back to reverse...
const REVERSE_RELEASE_STICK: float = 29.0 ## [code]0x1D[/code]: ...and back past this to keep reversing.
const REVERSE_MAX_KMH: float = 5.0
const SPIN_IN_PLACE_KMH: float = 12.0 ## [code]:4661[/code]: A and B together under this is the spin in place.
const WALL_DECELERATION: float = 6.0 ## [code]:2641[/code]: a wall takes this off currentSpeed each frame it is touched.

## [code]gKartHopInitialVelocityTable[/code]: the hop that starts a drift.
const HOP_VELOCITY: float = 0.93
## [code]gKartHopJerkTable[/code]: how fast the hop's acceleration builds.
const HOP_JERK: float = 0.03
const HOP_ACCELERATION_CAP: float = 9.0 ## [code]func_8002AAC0[/code].
const HOP_VELOCITY_CAP: float = 15.0
## [code]kart_hop[/code] sets [code]kartGravity[/code] to this for the hop...
const HOP_GRAVITY: float = 500.0
const HOP_VERTICAL_DIVISOR: float = 3.0 ## ...and [code]unk_DAC[/code], the vertical integrator's divisor, to this.
const VERTICAL_DIVISOR_RELAX: float = 0.07 ## [code]func_8002AB70[/code]: unk_DAC lerps back to 1 by this a frame...
const GRAVITY_RELAX_GROUND: float = 0.1 ## ...and kartGravity to the table by this on the ground...
const GRAVITY_RELAX_AIR: float = 0.02 ## ...and this in the air.
const DOWNHILL_GRAVITY: float = 500.0 ## [code]:1249[/code]: rolling downhill over 20 km/h lightens the kart to this...
const DOWNHILL_VERTICAL_DIVISOR: float = 3.0 ## ...with the vertical divisor pulled to this (at 0.05 a frame).
const DOWNHILL_GRAVITY_RELAX: float = 1.0
const DOWNHILL_DIVISOR_RELAX: float = 0.05
const AIR_FORCE_LOSS: float = 0.04 ## [code]:3077[/code]: in the air unk_0A0 climbs toward this share of the force (lerp 0.15)...
const AIR_FORCE_LOSS_LERP: float = 0.15
const AIR_FORCE_LOSS_RECOVER: float = 0.1 ## ...and back to nothing on the ground (lerp 0.1).
const AIR_FORCE_SCALE: float = 1.1 ## [code]func_8002FE84[/code]: the force is pushed 1.1 times itself in the air.
const BONK_DIVISOR: float = 30.0 ## [code]:2225[/code]: for a few frames after a bonk the velocity barely answers.
const GROUND_PULL: float = 0.02 ## [code]:2278[/code]: the kart is pulled down this much a frame, which is how it finds the ground.

# ----------------------------------------------------------------- loss -----

## The share of the drive force the kart does not get, built in [code]func_80030150[/code].
const LOSS_RATE: float = 0.05 ## [code]:3110[/code]: unk_104 moves toward the frame's loss by this (plus the class figure).
## [code]gKartTurnSpeedReductionTable0[/code] and [code]...Table1[/code] by class:
## light 0.002, standard 0, heavy -0.002. The first is added to the per degree
## turn loss, the second to the loss rate.
const CLASS_TURN_LOSS: Dictionary = {&"light": 0.002, &"standard": 0.0, &"heavy": -0.002}
## [code]func_80030150[/code]'s turn loss: every degree of the turn angle costs
## 0.01 (plus the class figure) of the force while steering, 0.004 while
## drifting, and 0.008 more for the first ten frames of a drift pushed to the
## outside. That difference is the whole reason a drift is faster than a turn.
const TURN_FORCE_BASE: float = 0.01
const DRIFT_TURN_FORCE: float = 0.004
const DRIFT_OUTSIDE_FORCE: float = 0.008
const DRIFT_OUTSIDE_FRAMES: int = 10
## Under 20 km/h the loss is negative: the kart is given a fifth more force,
## and this much again while it is under the lightning effect.
const SLOW_PENALTY: float = -0.2
const LIGHTNING_PENALTY: float = -0.55
const SLOW_PENALTY_KMH: float = 20.0
const LOSS_MIN_KMH: float = 8.0 ## Under this the turn and surface losses are not counted at all...
const STALL_UPHILL_GAIN: float = -0.85 ## ...and facing uphill the kart is given most of the force again.
## An invincible kart loses this much force, which is why a star is not a boost.
const STAR_PENALTY: float = -0.25
## The slope term, docked per degree of gradient. The game splits at 0x11
## degrees, using the gentler figure under it.
const SLOPE_FORCE_STEEP: float = 0.0126 / 3.0
const SLOPE_FORCE_SHALLOW: float = 0.026 / 3.0
const SLOPE_SPLIT_DEGREES: float = 17.0

## Per surface force loss by tyre, [code]D_800E2E90[/code] (the rear tyres and,
## by the game's own slip, the front left) and [code]D_800E2EB0[/code] (the front
## right), by class. Indexed by surface id; the game ignores ids past 14.
const SURFACE_FORCE_LOSS_REAR: Dictionary = {
	&"light": [0.0, 0.0, 0.0, 0.02, 0.0, 0.0, 0.0, 0.08, 0.08, 0.0, 0.0, 0.08, 0.0, 0.08, 0.08],
	&"standard": [0.0, 0.0, 0.0, 0.03, 0.0, 0.0, 0.0, 0.09, 0.09, 0.0, 0.0, 0.09, 0.0, 0.09, 0.09],
	&"heavy": [0.0, 0.0, 0.0, 0.04, 0.0, 0.0, 0.0, 0.1, 0.1, 0.0, 0.0, 0.1, 0.0, 0.1, 0.1],
}
const SURFACE_FORCE_LOSS_FRONT: Dictionary = {
	&"light": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.02, 0.02, 0.0, 0.0, 0.02, 0.0, 0.02, 0.02],
	&"standard": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.03, 0.03, 0.0, 0.0, 0.03, 0.0, 0.03, 0.03],
	&"heavy": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.04, 0.04, 0.0, 0.0, 0.04, 0.0, 0.04, 0.04],
}
## Per surface grip loss, [code]func_8002FCA8[/code]: [code]D_800E2A90[/code]
## for the rear tyres and [code]D_800E2AB0[/code] for the front, the same for
## every class. On grass the four add up past one, so the grip reverses: the
## kart slides.
const SURFACE_GRIP_LOSS_REAR: PackedFloat32Array = [0.0, 0.0, 0.3, 0.3, 0.0, 0.3, 0.0, 0.58, 0.58, 0.0, 0.58, 0.28, 0.0, 0.58, 0.0]
const SURFACE_GRIP_LOSS_FRONT: PackedFloat32Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.38, 0.38, 0.0, 0.38, 0.1, 0.0, 0.38, 0.0]
## Per surface brake loss, [code]D_800E3210[/code] in [code]func_800323E4[/code]: the brake works this much less.
const SURFACE_BRAKE_LOSS: PackedFloat32Array = [0.0, 0.0, 0.2, 0.2, 0.0, 0.4, 0.1, 0.2, 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

# ---------------------------------------------------------------- boost -----

## [code]update_player_drift_duration[/code] counts up one a frame while
## drifting and back down when not, and clamps here. At 30 fps that is 3.33 s.
const DRIFT_DURATION_CAP: int = 100
## [code]func_8002A79C[/code] pays a mini turbo out once driftState reaches this.
const MINI_TURBO_DRIFT_STATE: int = 2
## The same function ends the mini turbo at 0x1F frames, so 31 at 30 fps.
const MINI_TURBO_FRAMES: int = 31
## [code]func_8002A704[/code] sets boostTimer to 0x50 for a boost item.
const BOOST_FRAMES: int = 80
## [code]func_80030150[/code] [code]:3097[/code]: through a mini turbo unk_0E8 is
## lerped toward 580 by a fifth a frame, and 580 is added to the drive force,
## so a 150cc kart's 4096 becomes 4676: fourteen percent more, about 80 km/h.
## ([code]move_f32_towards[/code] is a lerp, [code]render_player.c:863[/code].)
const MINI_TURBO_TARGET: float = 580.0
const MINI_TURBO_RATE: float = 0.2
const MINI_TURBO_DECAY: float = 0.01 ## And back to nothing by a hundredth a frame after.
## [code]effects.c:554[/code]: a mushroom lerps boostPower toward 400 by half a
## frame, a tenth more force, and bypasses the loss fraction altogether.
const MUSHROOM_FORCE: float = 400.0
const MUSHROOM_RATE: float = 0.5
const MUSHROOM_DECAY: float = 0.1
## What a CPU kart on catch-up pulls toward, at half a frame: [code]:3091[/code].
const CPU_CATCHUP_TARGET: float = 380.0
const CPU_CATCHUP_RATE: float = 0.5
const CPU_CATCHUP_DECAY: float = 0.1
const CPU_CATCHUP_MIN_KMH: float = 50.0 ## [code]func_8002BF4C[/code]: no catch-up under this...
const CPU_CATCHUP_TRIGGER_FRAMES: int = 61 ## ...and it needs 0x3D frames with somebody ahead to switch on.
## [code]gKartTripleABoost[/code]: the start boost multiplies the first bands by this, by class.
const CLASS_START_BOOST: Dictionary = {&"light": 3.0, &"standard": 2.0, &"heavy": 1.5}

# ------------------------------------------------------------- steering -----

## [code]gKartHandlingTable[/code] by class: light 1.28, standard 1.25, heavy 1.15.
const CLASS_HANDLING: Dictionary = {&"light": 1.28, &"standard": 1.25, &"heavy": 1.15}
const HARD_STEER_BONUS: float = 0.15 ## [code]:4165[/code]: past 45 on the stick the handling figure gains this.
const HARD_STEER: int = 45
## [code]func_80033AE0[/code] divides the stick by [code]8 + currentSpeed / 50[/code],
## which is why a fast kart turns less for the same stick. Quoted as the
## divisor's two terms.
const STEER_DIVISOR_BASE: float = 8.0
const STEER_DIVISOR_SPEED: float = 50.0
const STEER_DIVISOR_SLOW: float = 12.0 ## Under 25 km/h the stick is divided by this instead...
const STEER_SLOW_KMH: float = 25.0
const STEER_DIVISOR_DRIFT: float = 8.0 ## ...and by this flat while drifting.
const TURN_SCALE: float = 1.5 ## The turn factor is scaled by this when not drifting (and 1.5 again in a spin).
## [code]sp44[/code] at [code]:3918[/code]: the turn factor by km/h, 0 to 155.
const TURN_FACTOR_BY_KMH: PackedFloat32Array = [
	0.0, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.6, 0.6, 0.6, 0.6, 0.6, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7,
	0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6,
	0.5, 0.5, 0.5, 0.5, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.7, 0.7, 0.7, 0.7,
	0.7, 0.7, 0.6, 0.6, 0.6, 0.6, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7,
	0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7,
	0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7,
	0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8,
	0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8,
	0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8,
]
## The yaw rate while braking: the turn factor gains 1.5 from 8 km/h and 1.6 from 65 ([code]:4176[/code]).
const BRAKE_STEER_ADD_MID: float = 1.5
const BRAKE_STEER_ADD_FAST: float = 1.6
const BRAKE_STEER_SLOW_KMH: float = 8.0
const BRAKE_STEER_FAST_KMH: float = 65.0
## In a drift the stick is remapped onto the drift's own side, 40 to 53
## ([code]var_s1_2[/code] at [code]:4195[/code]), gains 2.0 under 8 km/h, 3.0 to 65 and
## 3.5 past, and the whole is scaled by 0.65, or 0.9 when pushed to the outside.
const DRIFT_STICK_MIN: float = 40.0
const DRIFT_STEER_ADD_SLOW: float = 2.0
const DRIFT_STEER_ADD_MID: float = 3.0
const DRIFT_STEER_ADD_FAST: float = 3.5
const DRIFT_STEER_SCALE: float = 0.65
const DRIFT_OUTSIDE_STEER_SCALE: float = 0.9
const DRIFT_OUTSIDE_STICK: float = 40.0 ## [code]:4198[/code]: the stick this far against the drift is an outside drift.
## Through the hop the stick gains 1.5, or 6.0 under 5 km/h ([code]:4235[/code]).
const HOP_STEER_ADD: float = 1.5
const HOP_STEER_ADD_STILL: float = 6.0
const HOP_STEER_STILL_KMH: float = 5.0
const SPIN_STEER_SCALE: float = 5.0 ## [code]:4158[/code]: the spin in place turns at five times the stick.
const SPIN_DRAG: float = 0.1 ## [code]:1315[/code]: and its turn angle bleeds a tenth a frame.
## The steering ladder ([code]:4021[/code] to [code]:4106[/code]): [code]steerPosition[/code]
## is moved toward the stick through fifty nine [code]update_steering_large[/code]
## calls and thirty one [code]update_steering_small[/code] calls, one per
## threshold on the frame's stick change. Each is [threshold, numerator,
## sideways]: a call applies when the change is at least its threshold, moves
## the position by an increment that decays 0x800 a call to a floor of
## [code](numerator << 12) / resistance[/code], and sets the lateral kick
## ([code]unk_090[/code]) to minus its sideways figure (large) or adds it, capped at
## zero (small). The decomp's own comment: the sum of the small figures is 40.15,
## so a stick change past 30 always leaves the kick at -59.85 and anything less
## leaves it at zero.
const STEER_LADDER_LARGE: Array = [
	[90, 120, 450], [89, 118, 440], [88, 116, 430], [87, 114, 420], [86, 112, 410], [85, 88, 400],
	[84, 86, 395], [83, 80, 390], [82, 79, 390], [81, 78, 380], [80, 77, 370], [79, 76, 360],
	[78, 76, 360], [77, 75, 350], [76, 74, 340], [75, 73, 330], [74, 73, 330], [73, 73, 330],
	[72, 72, 320], [71, 71, 315], [70, 71, 315], [69, 70, 305], [68, 70, 305], [67, 69, 280],
	[66, 70, 270], [65, 69, 270], [64, 68, 260], [63, 67, 250], [62, 67, 250], [61, 67, 250],
	[60, 61, 245], [59, 60, 245], [58, 59, 245], [57, 58, 245], [56, 56, 245], [55, 56, 230],
	[54, 56, 230], [53, 56, 230], [52, 56, 230], [51, 56, 230], [50, 50, 220], [49, 50, 220],
	[48, 50, 220], [47, 50, 220], [46, 50, 220], [45, 48, 110], [44, 46, 110], [43, 46, 110],
	[42, 46, 110], [41, 46, 110], [40, 46, 110], [39, 44, 110], [38, 40, 110], [37, 40, 110],
	[36, 36, 110], [35, 36, 110], [34, 34, 110], [32, 32, 100], [31, 32, 100],
]
const STEER_LADDER_SMALL: Array = [
	[30, 31, 0.9], [29, 30, 0.9], [28, 29, 0.9], [27, 28, 0.9], [26, 27, 0.9], [25, 26, 1.0],
	[24, 25, 1.0], [23, 24, 1.0], [22, 23, 1.0], [21, 22, 1.0], [20, 21, 1.05], [19, 20, 1.05],
	[18, 19, 1.05], [17, 18, 1.05], [16, 17, 1.05], [15, 16, 1.2], [14, 15, 1.2], [13, 14, 1.2],
	[12, 13, 1.2], [11, 12, 1.2], [10, 14, 1.6], [9, 13, 1.6], [8, 12, 1.6], [7, 11, 1.6],
	[6, 10, 1.6], [5, 9, 1.9], [4, 8, 1.9], [3, 7, 1.9], [2, 6, 1.9], [1, 5, 1.9], [0, 0, 1.9],
]
const STEER_INCREMENT_DECAY: float = 2048.0 / 65536.0 ## 0x800 in 16.16, in stick units.
const STEER_INCREMENT_SCALE: float = 4096.0 / 65536.0 ## [code](n << 12)[/code] in 16.16, in stick units.
## The ladder's resistance ([code]:3975[/code]): 8 under 15 km/h; otherwise, while
## turning and the stick is still moving the same way (a change of 35 or less),
## 15 for both; turning and changing back, 5 large and 9 small; not turning, 3
## and 6; drifting adds 3 to each; the spin in place is 10.
const STEER_RESISTANCE_SLOW: float = 8.0
const STEER_RESISTANCE_SLOW_KMH: float = 15.0
const STEER_RESISTANCE_TURNING: float = 15.0
const STEER_RESISTANCE_TURNING_CHANGE: float = 35.0
const STEER_RESISTANCE_RETURN_LARGE: float = 5.0
const STEER_RESISTANCE_RETURN_SMALL: float = 9.0
const STEER_RESISTANCE_STRAIGHT_LARGE: float = 3.0
const STEER_RESISTANCE_STRAIGHT_SMALL: float = 6.0
const STEER_RESISTANCE_DRIFT: float = 3.0
const STEER_RESISTANCE_SPIN: float = 10.0
const TURN_FLAG_DEGREES: float = 5.0 ## [code]:3930[/code]: a turn angle past this sets the left or right turn flag.
const SPINOUT_STEER_DELTA: float = 90.0 ## [code]:3950[/code]: a stick change of this in one frame over 40 km/h at 150cc spins the kart out.
const SPINOUT_MIN_KMH: float = 40.0

# ----------------------------------------------------------- turn angle -----

## [code]unk_0C0[/code], the kart's slide ([code]func_8002AE38[/code]): with the
## stick near centre, or under 8 km/h, it relaxes toward nine times the yaw rate
## by a fifteenth a frame; otherwise it is measured as twice the angle between
## where the kart went and where it faces (once, past 16 degrees over a
## currentSpeed of 200), pulled toward twenty times the yaw rate when the stick
## is held against it, and clamped at 0x1C70, which is 40 degrees.
const TURN_ANGLE_CAP_DEGREES: float = 40.0
const TURN_ANGLE_FOLLOW_SCALE: float = 9.0
const TURN_ANGLE_FOLLOW_LERP: float = 1.0 / 15.0
const TURN_ANGLE_SLIP_SCALE: float = 2.0
const TURN_ANGLE_SLIP_LERP: float = 1.0 / 12.0
const TURN_ANGLE_COUNTER_SCALE: float = 20.0
const TURN_ANGLE_SINGLE_DEGREES: float = 16.0
const TURN_ANGLE_SINGLE_SPEED: float = 200.0
const TURN_ANGLE_STILL_KMH: float = 8.0
const TURN_ANGLE_STILL_STICK: float = 5.0

# ---------------------------------------------------------------- drift -----

## [code]func_80036C5C[/code]: a hop over 20 km/h is a drift at once, and
## [code]func_80033AE0[/code] cancels it when R is let go, the kart stops sliding
## more than six degrees, or it drops under 20 km/h.
const DRIFT_MIN_KMH: float = 20.0
const DRIFT_MIN_DEGREES: float = 6.0
## [code]update_drift_state_counter[/code]: the counter climbs while the stick is
## held against the slide (past 10), and bringing it back after 18 or more frames
## bumps driftState and leaves the counter at 10; past 100 it stops counting.
const DRIFT_COUNTER_STICK: float = 10.0
const DRIFT_STATE_FRAMES: int = 18
const DRIFT_COUNTER_HOLD: int = 10
const DRIFT_COUNTER_CAP: int = 100
const DRIFT_STATE_CAP: int = 3

# -------------------------------------------------------------- lateral -----

## The lateral term ([code]func_800371F4[/code], [code]func_80036DB4[/code]):
## [code]unk_088[/code] of 28 less the surface grip loss, less a third of the
## km/h, less a fiftieth of currentSpeed (a twentieth with the stick past 20,
## and the stick's own tenth), less fifty times the brake slide; three times
## the km/h and a tenth of the brake slide in a drift; all times the speed,
## along with the flick's -59.85, and pushed across the kart. Along it, -10
## times the speed, three times that in a drift.
const LATERAL_BASE: float = 28.0
const LATERAL_KMH_DIVISOR: float = 3.0
const LATERAL_SPEED_SCALE: float = 0.02
const LATERAL_SPEED_SCALE_STEERED: float = 0.05
const LATERAL_SPEED_SCALE_HARD: float = 0.15
const LATERAL_STICK_SCALE: float = 0.01
const LATERAL_STICK_SCALE_HARD: float = 0.1
const LATERAL_STICK_SOFT: float = 20.0
const LATERAL_BRAKE_SLIDE_SCALE: float = 50.0
const LATERAL_DRIFT_KMH_SCALE: float = 3.0
const LATERAL_DRIFT_BRAKE_SLIDE_SCALE: float = 10.0
const LATERAL_DRAG: float = -10.0
const LATERAL_DRIFT_DRAG_SCALE: float = 3.0
const LATERAL_SPINOUT_KMH_SCALE: float = 1.5

# --------------------------------------------------------------- camera -----

## The one-player race camera ([code]camera.c:105[/code] and
## [code]func_8001E45C[/code]): 38.5 units behind, 11.6 above, looking 19.2 ahead;
## the position moves 0.4 of the way across the ground each frame
## ([code]D_800DDB30[/code]) and 0.15 vertically, the look point 0.5 vertically;
## a hop at a standstill slows both to 0.01 and 0.02.
const CAMERA_BEHIND: float = 38.5
const CAMERA_ABOVE: float = 11.6
const CAMERA_LOOK_AHEAD: float = 19.2
const CAMERA_XZ_LERP: float = 0.4
const CAMERA_Y_LERP: float = 0.15
const CAMERA_LOOK_Y_LERP: float = 0.5
const CAMERA_HOP_Y_LERP: float = 0.01
const CAMERA_HOP_LOOK_Y_LERP: float = 0.02
const CAMERA_HOP_STILL_KMH: float = 5.0
## The camera's yaw chases the kart's by a step in angle units a frame: 500
## with the stick centred (0x2D8 through a spin in place), 0xA5 plus half the
## kart's yaw rate while it is steering, 0xB4 plus the whole rate once the
## camera is 70 degrees or more behind.
const CAMERA_YAW_STEP_STRAIGHT: float = 500.0
const CAMERA_YAW_STEP_SPIN: float = 728.0
const CAMERA_YAW_STEP_TURN: float = 165.0
const CAMERA_YAW_STEP_FAR: float = 180.0
const CAMERA_YAW_FAR_DEGREES: float = 70.0
## Through a drift the camera leads the kart by 12 degrees on the drift's
## side, 0x0B60 (16 degrees) when it is pushed to the outside, eased a tenth a
## frame in and a twentieth out.
const CAMERA_DRIFT_LEAD: float = deg_to_rad(12.0)
const CAMERA_DRIFT_LEAD_OUTSIDE: float = 2912.0 / 65536.0 * TAU
const CAMERA_DRIFT_LEAD_LERP: float = 0.1
const CAMERA_DRIFT_LEAD_RELEASE: float = 0.05

# -------------------------------------------------------------- surfaces -----

## The surface types, [code]include/mk64.h[/code]'s enum. The ids are the game's own,
## so a course converted out of a ROM keeps them.
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
const SURFACE_TABLE_SIZE: int = 15 ## The tables above stop at id 14; the game ignores anything past.

## Which surfaces slow a kart down: the ones the force loss tables charge for.
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
	return (top_speed_units * top_speed_units) / FORCE_DIVISOR


## Units per frame to metres per second, through the speedometer's km/h.
static func units_to_ms(units_per_frame: float) -> float:
	return units_per_frame * UNITS_PER_FRAME_TO_KMH / 3.6


## Metres per second to units per frame.
static func ms_to_units(speed: float) -> float:
	return speed * 3.6 / UNITS_PER_FRAME_TO_KMH


## Metres per second to the km/h a speedometer would show.
static func ms_to_kmh(speed: float) -> float:
	return speed * 3.6


## Units per frame to the km/h the game shows, [code](speed / 18) * 216[/code].
static func units_to_kmh(units_per_frame: float) -> float:
	return units_per_frame * UNITS_PER_FRAME_TO_KMH


## Frames at the game's 30 fps as seconds, so the timings above can be used
## directly without scattering the same division through the port.
static func frames(count: int) -> float:
	return float(count) / FPS


## The game's angle units to radians.
static func angle_units_to_radians(units: float) -> float:
	return units / ANGLE_UNITS_PER_TURN * TAU


## A per frame lerp fraction [param per_frame] applied over [param frames] frames
## (fractional between physics ticks), so [code]move_f32_towards[/code] lands in
## the same place whatever the tick rate.
static func step_fraction(per_frame: float, frames: float) -> float:
	return 1.0 - pow(1.0 - clampf(per_frame, 0.0, 1.0), frames)


## Whether [param surface] is one of the off road types.
static func is_off_road(surface: int) -> bool:
	return OFF_ROAD_SURFACES.has(surface)


## A per surface table read the way the game reads it: ids past the table are nothing.
static func surface_entry(table: Variant, surface: int) -> float:
	if surface < 0 or surface >= SURFACE_TABLE_SIZE:
		return 0.0
	return float(table[surface])
