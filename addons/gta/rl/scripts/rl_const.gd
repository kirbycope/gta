class_name RlConst
extends RefCounted
## Rocket League's own physics constants, converted from Unreal units to metres.
##
## Every number here is copied from a published source rather than tuned by
## feel. The bulk of it is [url=https://github.com/ZealanL/RocketSim]RocketSim[/url]'s
## [code]src/RLConst.h[/code], the reference reimplementation of Rocket League's
## simulation, cross-checked against the
## [url=https://wiki.rlbot.org/v4/botmaking/useful-game-values/]RLBot wiki's
## game values[/url] and its
## [url=https://wiki.rlbot.org/v4/botmaking/jumping-physics/]jumping physics[/url]
## page. The car hitboxes come from RocketSim's [code]CarConfig.cpp[/code].
##
## Rocket League works in Unreal units where 1 uu is 1 cm, so every length below
## is the published figure divided by 100 and every acceleration likewise. The
## comment on each line carries the original value so it can be checked against
## the source without doing the arithmetic backwards.
##
## Mass is left in the game's own arbitrary units: a car is 180 and the ball 30,
## a six to one ratio, and since the whole scene is simulated in these units the
## ratio is all that matters.
##
## Values that could not be sourced are listed in [constant UNSOURCED] rather
## than invented, the same way [TwRoster] handles its gaps.

## What is not taken from a published source, and is a judgement call instead.
const UNSOURCED: PackedStringArray = [
	"wheel grip: Godot's VehicleWheel3D caps the lateral impulse at the suspension force times wheel_friction_slip where RocketSim damps it uncapped, so the slip figure is set to reproduce the turning radii Chip measured rather than read from a file",
	"the match clock, which is a game rule rather than a physics constant",
	"AI decision thresholds, which have no equivalent in the real game",
	"the camera: no published source states the game's defaults, so the settings the professional guides agree on are used, and how fast it swings behind the car is a judgement",
	"the order the car and ball extra impulse is combined in, which is read off RocketSim rather than stated",
]

## Unreal units to metres: Rocket League's 1 uu is 1 cm.
const UU: float = 0.01

# ---------------------------------------------------------------- world -----

const GRAVITY: float = 6.5 ## GRAVITY_Z 650 uu/s^2, a third under Earth's.
const ARENA_EXTENT_X: float = 40.96 ## ARENA_EXTENT_X 4096 uu, so 81.92 m wall to wall.
const ARENA_EXTENT_Y: float = 51.20 ## ARENA_EXTENT_Y 5120 uu, not counting the goal mouths.
const ARENA_HEIGHT: float = 20.48 ## ARENA_HEIGHT 2048 uu to the ceiling.
const SIDE_WALL_LENGTH: float = 79.36 ## 7936 uu of flat side wall, the rest is corner.
const BACK_WALL_LENGTH: float = 58.88 ## 5888 uu of flat back wall.
const CORNER_WALL_LENGTH: float = 16.29174 ## 1629.174 uu across each of the four corners.
const GOAL_HEIGHT: float = 6.42775 ## 642.775 uu to the crossbar.
const GOAL_HALF_WIDTH: float = 8.92755 ## 892.755 uu from centre to post.
const GOAL_DEPTH: float = 8.80 ## 880 uu back from the goal line.
## SOCCAR_GOAL_SCORE_BASE_THRESHOLD_Y 5124.25 uu: the ball has scored once its
## centre is wholly past this, which is a shade beyond the wall at 5120.
const GOAL_LINE_Y: float = 51.2425
const WORLD_FRICTION: float = 0.3 ## CARWORLD_COLLISION_FRICTION.
const WORLD_RESTITUTION: float = 0.3 ## CARWORLD_COLLISION_RESTITUTION.

# ----------------------------------------------------------------- ball -----

const BALL_RADIUS: float = 0.9125 ## BALL_COLLISION_RADIUS_SOCCAR 91.25 uu.
const BALL_REST_HEIGHT: float = 0.9315 ## BALL_REST_Z 93.15 uu, above the radius by the mesh collision margin.
const BALL_MASS: float = 30.0 ## BALL_MASS_BT, which is CAR_MASS_BT / 6.
const BALL_DRAG: float = 0.03 ## BALL_DRAG, a multiplier on net velocity per second.
const BALL_FRICTION: float = 0.35 ## BALL_FRICTION.
const BALL_RESTITUTION: float = 0.6 ## BALL_RESTITUTION, the 60 percent bounce.
const BALL_MAX_SPEED: float = 60.0 ## BALL_MAX_SPEED 6000 uu/s.
const BALL_MAX_ANGULAR: float = 6.0 ## BALL_MAX_ANG_SPEED, in radians per second.

## The extra kick a car puts through the ball on top of the rigid body
## response, which is what makes a Rocket League hit carry. Straight from
## RocketSim's BALL_CAR_EXTRA_IMPULSE_* family.
const BALL_CAR_IMPULSE_Z_SCALE: float = 0.35 ## BALL_CAR_EXTRA_IMPULSE_Z_SCALE.
const BALL_CAR_IMPULSE_FORWARD_SCALE: float = 0.65 ## BALL_CAR_EXTRA_IMPULSE_FORWARD_SCALE.
const BALL_CAR_IMPULSE_MAX_DELTA: float = 46.0 ## BALL_CAR_EXTRA_IMPULSE_MAXDELTAVEL_UU 4600 uu/s.
## BALL_CAR_EXTRA_IMPULSE_FACTOR_CURVE, as speed in m/s against a scale factor.
const BALL_CAR_IMPULSE_CURVE: Array[Vector2] = [
	Vector2(0.0, 0.65), Vector2(5.0, 0.65), Vector2(23.0, 0.55), Vector2(46.0, 0.30),
]

# ------------------------------------------------------------------ car -----

const CAR_MASS: float = 180.0 ## CAR_MASS_BT.
const CAR_MAX_SPEED: float = 23.0 ## CAR_MAX_SPEED 2300 uu/s, reachable only on boost.
const CAR_MAX_DRIVE_SPEED: float = 14.10 ## The throttle curve reaches zero at 1410 uu/s.
const CAR_MAX_ANGULAR: float = 5.5 ## CAR_MAX_ANG_SPEED, in radians per second.
const SUPERSONIC_START: float = 22.0 ## SUPERSONIC_START_SPEED 2200 uu/s.
const SUPERSONIC_MAINTAIN: float = 21.0 ## SUPERSONIC_MAINTAIN_MIN_SPEED, 100 uu/s under the start.
const SUPERSONIC_MAINTAIN_TIME: float = 1.0 ## SUPERSONIC_MAINTAIN_MAX_TIME.
const BRAKE_ACCEL: float = 35.0 ## BRAKE_TORQUE_AMOUNT works out to 3500 uu/s^2 of braking.
const COAST_ACCEL: float = 5.25 ## COASTING_BRAKE_FACTOR 0.15 of the brake, so 525 uu/s^2.
const STOPPING_SPEED: float = 0.25 ## STOPPING_FORWARD_VEL 25 uu/s, under which a coast becomes a full brake.
const THROTTLE_DEADZONE: float = 0.001 ## THROTTLE_DEADZONE.
const CAR_REST_HEIGHT: float = 0.17 ## CAR_SPAWN_REST_Z 17 uu, an Octane sitting on its wheels.
const CAR_RESPAWN_HEIGHT: float = 0.36 ## CAR_RESPAWN_Z 36 uu, dropped in slightly high.

## DRIVE_SPEED_TORQUE_FACTOR_CURVE, as forward speed in m/s against the
## fraction of full drive torque still available. This is why a Rocket League
## car cannot throttle past 14.1 m/s without boost.
const DRIVE_TORQUE_CURVE: Array[Vector2] = [
	Vector2(0.0, 1.0), Vector2(14.0, 0.1), Vector2(14.1, 0.0),
]
## THROTTLE_TORQUE_AMOUNT is CAR_MASS_BT * 400, and [code]Car.cpp[/code] sets
## that whole force on each of the four wheels rather than sharing it out, so
## full torque on four wheels is 1600 uu/s^2, which is the figure Chip measured
## in the game. Reading the 400 as the car's acceleration gave it a quarter of
## its engine.
const THROTTLE_ACCEL: float = 16.0
## With fewer than three wheels down the drive is quartered (Car.cpp:406), and
## only the wheels touching push, so two wheels on a wall give an eighth.
const PARTIAL_CONTACT_DRIVE_SCALE: float = 0.25

## STEER_ANGLE_FROM_SPEED_CURVE, as forward speed in m/s against the steering
## lock in radians. A standing car turns 30.6 degrees, one at 15 m/s only 6.
const STEER_CURVE: Array[Vector2] = [
	Vector2(0.0, 0.53356), Vector2(5.0, 0.31930), Vector2(10.0, 0.18203),
	Vector2(15.0, 0.10570), Vector2(17.5, 0.08507), Vector2(30.0, 0.03454),
]
## POWERSLIDE_STEER_ANGLE_FROM_SPEED_CURVE: the wider lock while sliding.
const POWERSLIDE_STEER_CURVE: Array[Vector2] = [
	Vector2(0.0, 0.39235), Vector2(25.0, 0.12610),
]
const POWERSLIDE_RISE_RATE: float = 5.0 ## POWERSLIDE_RISE_RATE, per second: the slide is analogue, not a switch.
const POWERSLIDE_FALL_RATE: float = 2.0 ## POWERSLIDE_FALL_RATE, per second.
const HANDBRAKE_LAT_FRICTION: float = 0.1 ## HANDBRAKE_LAT_FRICTION_FACTOR_CURVE, a single point: a tenth of the grip across.
## HANDBRAKE_LONG_FRICTION_FACTOR_CURVE: the drive and the brake along the car
## through a powerslide, by how much of the wheel's motion is sideways.
const HANDBRAKE_LONG_FRICTION_CURVE: Array[Vector2] = [
	Vector2(0.0, 0.5), Vector2(1.0, 0.9),
]
## LAT_FRICTION_CURVE: the grip across the car, by the same slip fraction; a
## wheel rolling straight keeps all of it and one sliding sideways a fifth.
const LAT_FRICTION_CURVE: Array[Vector2] = [
	Vector2(0.0, 1.0), Vector2(1.0, 0.2),
]
## The slip fraction is the sideways speed over the sideways plus the forward,
## and counts as nothing under 5 uu/s sideways (Car.cpp:449).
const LAT_SLIP_MIN: float = 0.05
## The brake saturates once the wheel moves 23.1 uu/s against it
## (BRAKE_TORQUE_AMOUNT over the 113.74 rolling friction scale) and is
## proportional below that, which is what stops a braked car creeping.
const BRAKE_SATURATION_SPEED: float = 0.231

# ----------------------------------------------------------- suspension -----

## RocketSim's spring (btVehicleRL.cpp updateSuspension): the force on a wheel
## is [code](rest - length) * SUSPENSION_STIFFNESS - damping * v[/code], times a
## per-wheel SUSPENSION_FORCE_SCALE of 35.75 in front and 54.265 behind, which
## sum to the car's 180, and never pulls downward. Godot's VehicleWheel3D runs
## the same Bullet formula with the chassis mass in place of that scale, and
## uses its damping figure raw ([code]force -= damping * v[/code]), so each
## wheel's numbers carry over divided by the mass and multiplied by its own
## scale. Stiffness is per unit length and damping per unit time, so the unit
## of length cancels and nothing else converts. [method wheel_stiffness] and the
## two damping methods give what the scene's wheels carry, and the car test
## holds the scene to them. The old guess (220 and 0.55) was two percent of
## critical damping, and the car bounced on its springs at rest.
const SUSPENSION_STIFFNESS: float = 500.0 ## BTVehicle::SUSPENSION_STIFFNESS.
const SUSPENSION_DAMPING_COMPRESSION: float = 25.0 ## BTVehicle::WHEELS_DAMPING_COMPRESSION.
const SUSPENSION_DAMPING_RELAXATION: float = 40.0 ## BTVehicle::WHEELS_DAMPING_RELAXATION.
const SUSPENSION_FORCE_SCALE_FRONT: float = 35.75 ## BTVehicle::SUSPENSION_FORCE_SCALE_FRONT, 36 - 1/4.
const SUSPENSION_FORCE_SCALE_BACK: float = 54.265 ## BTVehicle::SUSPENSION_FORCE_SCALE_BACK, 54 + 1/4 + 1.5/100.
const SUSPENSION_TRAVEL: float = 0.12 ## BTVehicle::MAX_SUSPENSION_TRAVEL 12 uu, either side of rest.
## Car.cpp takes the travel off the config's rest length before handing it to
## Bullet, so the Octane's spring rests at 38.755 - 12 uu in front and
## 37.055 - 12 behind, measured from the wheel's attachment at OCTANE_OFFSET_UP.
const OCTANE_SPRING_REST_FRONT: float = 0.26755
const OCTANE_SPRING_REST_BACK: float = 0.25055

# ---------------------------------------------------------------- boost -----

const BOOST_MAX: float = 100.0 ## BOOST_MAX.
const BOOST_START: float = 33.33 ## BOOST_SPAWN_AMOUNT, which is a third of full, given at every kickoff.
const BOOST_PER_SECOND: float = 33.33 ## BOOST_USED_PER_SECOND, so a full tank lasts three seconds.
const BOOST_MIN_TIME: float = 0.1 ## BOOST_MIN_TIME: a tap still burns a tenth of a second.
const BOOST_ACCEL_GROUND: float = 9.9166 ## BOOST_ACCEL_GROUND 2975/3 uu/s^2.
const BOOST_ACCEL_AIR: float = 10.5833 ## BOOST_ACCEL_AIR 3175/3 uu/s^2.
const PAD_BOOST_BIG: float = 100.0 ## BOOST_AMOUNT_BIG: a big pad fills the tank.
const PAD_BOOST_SMALL: float = 12.0 ## BOOST_AMOUNT_SMALL.
const PAD_COOLDOWN_BIG: float = 10.0 ## COOLDOWN_BIG.
const PAD_COOLDOWN_SMALL: float = 4.0 ## COOLDOWN_SMALL.
const PAD_RADIUS_BIG: float = 2.08 ## CYL_RAD_BIG 208 uu.
const PAD_RADIUS_SMALL: float = 1.44 ## CYL_RAD_SMALL 144 uu.
const PAD_HEIGHT: float = 0.95 ## CYL_HEIGHT 95 uu: the pickup is a cylinder, not a disc on the floor.

# ------------------------------------------------------- jump and flip -----

const JUMP_IMMEDIATE: float = 2.9166 ## JUMP_IMMEDIATE_FORCE 875/3 uu/s, applied the instant jump is pressed.
const JUMP_ACCEL: float = 14.5833 ## JUMP_ACCEL 4375/3 uu/s^2, added for as long as jump is held.
const JUMP_MIN_TIME: float = 0.025 ## JUMP_MIN_TIME: the shortest a jump can be held for.
const JUMP_PRE_MIN_ACCEL_SCALE: float = 0.62 ## JUMP_PRE_MIN_ACCEL_SCALE: the held acceleration is 0.62 of itself through those first 25 ms.
const JUMP_MAX_TIME: float = 0.2 ## JUMP_MAX_TIME: holding longer than this adds nothing.
const DOUBLE_JUMP_MAX_DELAY: float = 1.25 ## DOUBLEJUMP_MAX_DELAY after the first jump finishes.
const FLIP_TORQUE_TIME: float = 0.65 ## FLIP_TORQUE_TIME: how long a dodge keeps torquing.
const FLIP_TORQUE_MIN_TIME: float = 0.41 ## FLIP_TORQUE_MIN_TIME before it can be cancelled.
const FLIP_TORQUE_PITCH: float = 224.0 ## FLIP_TORQUE_Y, the forward and backward dodge.
const FLIP_TORQUE_ROLL: float = 260.0 ## FLIP_TORQUE_X, the sideways dodge.
const FLIP_INITIAL_VEL: float = 5.0 ## FLIP_INITIAL_VEL_SCALE 500 uu/s of impulse into the dodge.
const FLIP_FORWARD_MAX_SCALE: float = 1.0 ## FLIP_FORWARD_IMPULSE_MAX_SPEED_SCALE.
const FLIP_SIDE_MAX_SCALE: float = 1.9 ## FLIP_SIDE_IMPULSE_MAX_SPEED_SCALE.
const FLIP_BACKWARD_MAX_SCALE: float = 2.5 ## FLIP_BACKWARD_IMPULSE_MAX_SPEED_SCALE.
const FLIP_BACKWARD_SCALE_X: float = 1.06666 ## FLIP_BACKWARD_IMPULSE_SCALE_X, 16/15, on top of the rest.
## The three scales above are not applied flat. Rocket League interpolates each
## from one at a standstill to its full value at [constant CAR_MAX_SPEED], as
## [code]((scale - 1) * speedRatio) + 1[/code], so a dodge from rest is worth
## exactly [constant FLIP_INITIAL_VEL] whichever way it is thrown and only a
## dodge at speed earns the bonus.
const FLIP_DEADZONE_IS_A_SUM: bool = true ## |yaw| + |pitch| + |roll| is what the deadzone tests.
## FLIP_Z_DAMP_120: from FLIP_Z_DAMP_START until the torque ends, the vertical
## speed is multiplied by 1 - 0.35 every 120 Hz tick while it is downward, and
## whichever way it points until FLIP_Z_DAMP_END. It is what keeps a dodge in
## the air; the old reading killed the downward speed for 60 ms and let the car
## drop onto its roof half way round.
const FLIP_Z_DAMP_120: float = 0.35
const FLIP_Z_DAMP_START: float = 0.15 ## FLIP_Z_DAMP_START.
const FLIP_Z_DAMP_END: float = 0.21 ## FLIP_Z_DAMP_END.
const FLIP_PITCHLOCK_TIME: float = 1.0 ## FLIP_PITCHLOCK_TIME: pitch is held through the dodge.
const FLIP_DEADZONE: float = 0.5 ## Stick past this on either axis turns the second jump into a dodge.

# --------------------------------------------- staying on a surface -----

## A car counts as on the ground with three wheels down, not one. RocketSim's
## [code]isOnGround = numWheelsInContact >= 3[/code]. On one or two wheels the
## game treats you as airborne, which is why a car tipped onto its side in a
## corner can still flip out of it.
const WHEELS_FOR_GROUND: int = 3

## The sticky force, which is the whole reason Rocket League can be played on
## the walls and the ceiling. RocketSim presses a car into whatever surface its
## wheels are on with
## [code]upDir * scale * GRAVITY_Z * CAR_MASS[/code], and since gravity is
## negative that is a force into the surface rather than away from it.
##
## The scale is [constant STICKY_FORCE_BASE] on its own, and gains
## [code]1 - abs(upDir.y)[/code] while the car is driving or rolling faster than
## [constant STOPPING_SPEED]. Flat ground therefore gets half a gravity of extra
## downforce and a vertical wall gets one and a half, which is what holds a car
## on it against its own weight.
const STICKY_FORCE_BASE: float = 0.5
## NON_STICKY_FRICTION_FACTOR_CURVE, read off the surface normal's vertical
## part: a car coasting with no throttle keeps only a tenth of its grip on a
## wall, which is why letting go of the throttle up there drops you off.
const NON_STICKY_FRICTION_CURVE: Array[Vector2] = [
	Vector2(0.0, 0.1), Vector2(0.7075, 0.5), Vector2(1.0, 1.0),
]

## CAR_AUTOROLL_FORCE and CAR_AUTOROLL_TORQUE: while the throttle is down and
## the car is only partly in contact, it is pulled onto the surface and turned
## to line up with it. This is what settles a car back onto its wheels after a
## landing, and what keeps it against a wall through a corner.
const AUTOROLL_FORCE: float = 1.0 ## 100 uu/s^2.
const AUTOROLL_TORQUE: float = 80.0 ## In Rocket League's own torque units, as an angular acceleration.

## CAR_AUTOFLIP_*: jump while upside down on the ground and the car throws
## itself back over. Without it a car that lands on its roof is stuck there.
const AUTOFLIP_IMPULSE: float = 2.0 ## CAR_AUTOFLIP_IMPULSE 200 uu/s, downward through the roof.
const AUTOFLIP_TORQUE: float = 50.0 ## CAR_AUTOFLIP_TORQUE, about the car's own nose.
const AUTOFLIP_TIME: float = 0.4 ## CAR_AUTOFLIP_TIME, scaled by how far over the car is.
const AUTOFLIP_NORMAL_MIN: float = 0.70710678 ## CAR_AUTOFLIP_NORMZ_THRESH, one over root two.
const AUTOFLIP_ROLL_MIN: float = 2.8 ## CAR_AUTOFLIP_ROLL_THRESH, in radians: well past on its side.

# ------------------------------------------------------------ air play -----

## CAR_TORQUE_SCALE, 2 pi / 65536 * 1000. Car.cpp applies the air control
## torques as [code]inertia * (torque - damping) * CAR_TORQUE_SCALE[/code], and
## the inertia cancels Bullet's division by it, so each published torque is an
## angular acceleration in radians per second squared once it is multiplied by
## this: 12.46 pitch, 9.11 yaw, 38.35 roll, the figures the RLBot wiki lists.
## Adding them to the angular velocity unscaled, as this car used to, made
## every air axis ten times too strong. The dodge (Car.cpp:631), the auto-flip
## (827) and the auto-roll (867) go through the inertia without this scale,
## so their figures are angular accelerations as published, which is why a
## dodge is at the 5.5 rad/s cap inside 25 ms.
const CAR_TORQUE_SCALE: float = 2.0 * PI / 65536.0 * 1000.0
## CAR_AIR_CONTROL_TORQUE, in pitch, yaw, roll order. Roll is by far the
## strongest axis, which is why air roll is the fast way to turn a car over.
const AIR_CONTROL_TORQUE: Vector3 = Vector3(130.0, 95.0, 400.0)
## CAR_AIR_CONTROL_DAMPING, same order: the resistance that stops an input
## spinning the car up without limit. Pitch and yaw damping fade as the stick
## is pushed; roll damping is always on (Car.cpp:670).
const AIR_CONTROL_DAMPING: Vector3 = Vector3(30.0, 20.0, 50.0)
const AIR_THROTTLE_ACCEL: float = 0.6666 ## THROTTLE_AIR_ACCEL 200/3 uu/s^2, barely anything without boost.

# ------------------------------------------------------- bump and demo -----

const BUMP_COOLDOWN: float = 0.25 ## BUMP_COOLDOWN_TIME between two bumps of the same car.
const BUMP_MIN_FORWARD_DIST: float = 0.645 ## BUMP_MIN_FORWARD_DIST 64.5 uu: a bump has to land ahead of the car.
const DEMO_RESPAWN_TIME: float = 3.0 ## DEMO_RESPAWN_TIME.
## BUMP_VEL_AMOUNT_GROUND_CURVE, as bumper speed in m/s against the velocity
## handed to the car being hit.
const BUMP_GROUND_CURVE: Array[Vector2] = [
	Vector2(0.0, 0.8333), Vector2(14.0, 11.0), Vector2(22.0, 15.30),
]
## BUMP_VEL_AMOUNT_AIR_CURVE, the same thing with both cars off the ground.
const BUMP_AIR_CURVE: Array[Vector2] = [
	Vector2(0.0, 0.8333), Vector2(14.0, 13.90), Vector2(22.0, 19.45),
]
## BUMP_UPWARD_VEL_AMOUNT_CURVE: how much of the bump goes straight up.
const BUMP_UP_CURVE: Array[Vector2] = [
	Vector2(0.0, 0.3333), Vector2(14.0, 2.78), Vector2(22.0, 4.17),
]

# --------------------------------------------------------------- hitbox -----

## HITBOX_SIZES[OCTANE] 120.507 x 86.6994 x 38.6591 uu, in Rocket League's
## length, width, height order. RocketSim's comment is worth repeating: the
## numbers the game reports through GetLocalCollisionExtent are slightly larger
## than the ones it actually simulates, and these are the simulated ones.
const OCTANE_LENGTH: float = 1.20507
const OCTANE_WIDTH: float = 0.866994
const OCTANE_HEIGHT: float = 0.386591
## HITBOX_OFFSETS[OCTANE] 13.8757, 0, 20.755 uu from the centre of mass.
const OCTANE_OFFSET_FORWARD: float = 0.138757
const OCTANE_OFFSET_UP: float = 0.20755
const OCTANE_WHEEL_RADIUS_FRONT: float = 0.125 ## FRONT_WHEEL_RADS[OCTANE] 12.5 uu.
const OCTANE_WHEEL_RADIUS_BACK: float = 0.150 ## BACK_WHEEL_RADS[OCTANE] 15 uu.
## FRONT_WHEELS_OFFSET[OCTANE] 51.25, 25.90, 20.755 uu, in Rocket League's
## forward, right, up order. The chassis in [code]rocket_car.tscn[/code] is
## built nose along positive z, so the forward figure is the wheel's z there
## and the sideways figure its x.
const OCTANE_WHEEL_FRONT: Vector3 = Vector3(0.5125, 0.2590, 0.20755)
## BACK_WHEELS_OFFSET[OCTANE] -33.75, 29.50, 20.755 uu, same order. The rear
## wheels sit a little wider than the front, which is why the two differ.
const OCTANE_WHEEL_BACK: Vector3 = Vector3(-0.3375, 0.2950, 0.20755)
const OCTANE_SUSPENSION_FRONT: float = 0.38755 ## FRONT_WHEEL_SUS_REST[OCTANE] 38.755 uu.
const OCTANE_SUSPENSION_BACK: float = 0.37055 ## BACK_WHEEL_SUS_REST[OCTANE] 37.055 uu.

# ----------------------------------------------------------- the camera -----

## Rocket League's camera is a big part of why the game reads the way it does.
## No published source states what the game ships with: RocketSim carries no
## camera figure and nor does the RLBot wiki. What the professional settings
## guides agree on is a 110 degree field of view, 270 uu back, 90 to 110 uu up
## and 3 degrees down, and that is what is used, low and tight on a car only
## 1.2 metres long. The old 4.0 m back and 1.55 up was the road car's framing
## and was the first thing anyone who knew the game noticed.
##
## How fast the view swings round behind the car is a judgement; the game's own
## stiffness and swivel settings have no published mapping onto a spring arm.
## All of this is in [constant UNSOURCED].
const CAMERA_FOV: float = 110.0 ## FOV 110.
const CAMERA_DISTANCE: float = 2.70 ## Distance 270 uu.
const CAMERA_HEIGHT: float = 1.00 ## Height 100 uu.
const CAMERA_ANGLE: float = -3.0 ## Angle, in degrees below level.
const CAMERA_FOLLOW_SPEED: float = 10.0 ## Per-second rate the view settles behind the car; a judgement.

# ------------------------------------------------------------- spawning -----

## CAR_SPAWN_LOCATIONS_SOCCAR, the five kickoff spots, as x and y in metres
## with the yaw in radians. These are the blue team's; orange mirrors them.
## In a three a side match the first three are used, which is the diagonal
## pair and one of the near-centre spots.
const KICKOFF_SPOTS: Array[Vector3] = [
	Vector3(-20.48, -25.60, PI * 0.25), Vector3(20.48, -25.60, PI * 0.75),
	Vector3(-2.56, -38.40, PI * 0.5), Vector3(2.56, -38.40, PI * 0.5),
	Vector3(0.0, -46.08, PI * 0.5),
]
## CAR_RESPAWN_LOCATIONS_SOCCAR: where a demolished car comes back, along its
## own back wall. Same format, same mirroring.
const RESPAWN_SPOTS: Array[Vector3] = [
	Vector3(-23.04, -46.08, PI * 0.5), Vector3(-26.88, -46.08, PI * 0.5),
	Vector3(23.04, -46.08, PI * 0.5), Vector3(26.88, -46.08, PI * 0.5),
]

## BoostPads::LOCS_BIG_SOCCAR, the six full boost pads, in metres.
const BIG_PADS: Array[Vector2] = [
	Vector2(-35.84, 0.0), Vector2(35.84, 0.0),
	Vector2(-30.72, 40.96), Vector2(30.72, 40.96),
	Vector2(-30.72, -40.96), Vector2(30.72, -40.96),
]
## BoostPads::LOCS_SMALL_SOCCAR, all twenty eight of them, in metres.
const SMALL_PADS: Array[Vector2] = [
	Vector2(0.0, -42.40), Vector2(-17.92, -41.84), Vector2(17.92, -41.84),
	Vector2(-9.40, -33.08), Vector2(9.40, -33.08), Vector2(0.0, -28.16),
	Vector2(-35.84, -24.84), Vector2(35.84, -24.84), Vector2(-17.88, -23.00),
	Vector2(17.88, -23.00), Vector2(-20.48, -10.36), Vector2(0.0, -10.24),
	Vector2(20.48, -10.36), Vector2(-10.24, 0.0), Vector2(10.24, 0.0),
	Vector2(-20.48, 10.36), Vector2(0.0, 10.24), Vector2(20.48, 10.36),
	Vector2(-17.88, 23.00), Vector2(17.88, 23.00), Vector2(-35.84, 24.84),
	Vector2(35.84, 24.84), Vector2(0.0, 28.16), Vector2(-9.40, 33.08),
	Vector2(9.40, 33.08), Vector2(-17.92, 41.84), Vector2(17.92, 41.84),
	Vector2(0.0, 42.40),
]


## Rocket League's axes are x across, y along the pitch and z up; Godot's are x
## across, y up and z along. Blue defends negative y in the game, and this puts
## that at positive z in Godot so blue attacks along Godot's own forward.
static func to_godot(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


## The same conversion for a yaw. Rocket League measures from positive x, and
## the addon's chassis noses along Godot's positive z rather than the usual
## negative, so a quarter turn is added rather than taken away. Rocket League's
## positive y becomes Godot's negative z in [method to_godot], and a car facing
## positive y has to come out with its nose on negative z, which this does: a
## yaw of half pi gives a Godot yaw of pi, and a nose on positive z turned by pi
## is on negative z. The old subtraction faced every kickoff away from the ball.
static func to_godot_yaw(yaw: float) -> float:
	return yaw + PI * 0.5


## The spring figure a wheel in [code]rl_car.tscn[/code] carries: RocketSim's
## stiffness times the wheel's force scale, over the chassis mass Godot
## multiplies back in. 99.3 in front, 150.7 behind.
static func wheel_stiffness(front: bool) -> float:
	return SUSPENSION_STIFFNESS * _suspension_scale(front) / CAR_MASS


## The same for the damping while the spring compresses: 4.97 front, 7.54 back.
static func wheel_damping_compression(front: bool) -> float:
	return SUSPENSION_DAMPING_COMPRESSION * _suspension_scale(front) / CAR_MASS


## And while it extends: 7.94 front, 12.06 back.
static func wheel_damping_relaxation(front: bool) -> float:
	return SUSPENSION_DAMPING_RELAXATION * _suspension_scale(front) / CAR_MASS


static func _suspension_scale(front: bool) -> float:
	return SUSPENSION_FORCE_SCALE_FRONT if front else SUSPENSION_FORCE_SCALE_BACK


## Reads one of the piecewise curves above. Rocket League stores these as
## LinearPieceCurve and looks them up with a linear blend between the two
## surrounding points, holding the end values beyond either end.
static func curve(points: Array[Vector2], at: float) -> float:
	if points.is_empty():
		return 0.0
	if at <= points[0].x:
		return points[0].y
	for i: int in range(1, points.size()):
		if at > points[i].x:
			continue
		var previous: Vector2 = points[i - 1]
		var span: float = points[i].x - previous.x
		if span <= 0.0:
			return points[i].y
		return lerpf(previous.y, points[i].y, (at - previous.x) / span)
	return points[points.size() - 1].y
