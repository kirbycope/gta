# The four demos against their sources

A review of the `gta` addon's four cars against the source each one claims, made in October 2026 the way
the skateboard's `docs/feel_review.md` was made for `tcps`: read the reference, read the port, list where they
part. The references were taken from the two lists given for the job and spidered one level down:

- `SubmitGame/awesome-decomp-games` (1,432 projects, and its `data/games.json`): Mario Kart 64 has
  `n64decomp/mk64` (the decompilation) and `HarbourMasters/SpaghettiKart` (a PC port of it). Grand Theft Auto
  has only browser ports of III, V and Vice City (no source) and a binary recompilation of IV. Nothing for
  Twisted Metal. Nothing for Rocket League.
- The "Non-AI Decomps and Recomps" document: `n64decomp/mk64` again, and `re3` (`Cai1Hsu/re3`, the
  reversed source of GTA III on `master` and Vice City on `miami`). Nothing for GTA V, Twisted Metal or
  Rocket League.

So one of the four demos has its game's own code to read (Mario Kart 64), one has the nearest ancestor's
(GTA V's handling descends from III and Vice City, whose code is re3), one has a community reimplementation
(Rocket League, through RocketSim, which the port already cites), and one has nothing at all (Twisted
Metal 2). The review is proportioned the same way. Line numbers are in `src/player_controller.c` of
`n64decomp/mk64` and `src/vehicles/*.cpp` of re3 unless another file is named.

## Mario Kart 64: the model is not the game's

### What the game does

Mario Kart 64's kart is not a vehicle. It is a point with a facing, moved by one line a frame at 30 fps, and
every number the port quotes from `physics.q`-style tables feeds that line. In order, each frame
(`func_8002E594`, the human update, `:2452`):

1. **The throttle fills a number, not a speed.** With A held, `player_accelerate_alternative` (`:3302`, the
   human path; `player_accelerate` with its 3.2 and 2.8 multipliers is the CPU and global path at `:3708`
   and `:3759`) adds the acceleration table's band value to `currentSpeed` once a frame, plus 0.05 per
   degree of slope: a standard kart adds 2.0 a frame through the low bands and 0.4 through the last, so 0 to a
   150cc top of 320 takes 323 frames, nearly eleven seconds, most of it in the last bands. With A released `currentSpeed` loses 1.0 a frame; with
   B held it loses 1.2, rising to 2.5 once `unk_20C` has counted up to 2 (0.02 a frame while the kart is
   actually slowing, `func_800323E4` `:3563`), and 4.0 under 20 km/h. The drive force is
   `currentSpeed * currentSpeed / 25` (`unk_08C`), so 4096 at 320.
2. **The force is cut by the turn, the surface, the slope and the speed** (`func_80030150` `:2990`). A loss
   fraction `var_f0` is built: each tyre on an off-road surface adds its surface table entry (0.38 for
   grass and dirt in `D_800E2E90`, so four wheels on grass is more than the whole force and the kart
   crawls); a slope docks 0.026/3 per degree (0.0126/3 past 17 degrees); under 20 km/h the kart is *given*
   20 percent; every degree of the kart's turn angle `unk_0C0` costs 0.01 plus the character's
   `gKartTurnSpeedReductionTable0` entry while turning, but only 0.004 while drifting, and 0.008 more for the
   first ten frames of a drift pushed to the outside; a star costs 0.25. `unk_104` moves toward that
   fraction at 0.05 (plus a per-character 0.002) a frame and the function returns
   `(1 - unk_104) * (force + miniTurbo + boostPower + cpuCatchUp - airLoss)`. The port's README reads
   this backwards: "a drifting kart keeps 0.004 of its yaw rate as drive force" is a loss, not a gain, and
   the point of it is that a drift costs a third of what a steered turn costs.
3. **The one line.** With that force `F` along the facing, the velocity integrates as
   `v += (F * facing + gravity + lateral - v * 0.12 * 5800) / 6000 / divisor`. The drag term `696 v` and
   the divisor 6000 give a first-order lag of 8.6 frames (0.29 s) between what the facing asks for and what
   the velocity does, and that lag is the whole of the game's grip: turn the facing and the velocity follows
   it a third of a second later, which is the slide; stop turning and it settles. The settled speed is
   `F / 696`, 5.88 units a frame, 70.6 km/h at 320, which the port has right. The divisor is 1 on the
   ground, `5 * unk_20C + 1` while braking (so a brake slide holds its momentum, up to 11), and the response
   is slower again in the air (30 on the CPU path at `:2225`, and the human air path keeps the same shape),
   which is why a kart in the air goes where it was going.
4. **Steering turns the facing, and only the facing** (`func_80033AE0` `:3903`, `func_80037BB4` `:4600`).
   The stick (`-53..53` past the deadzone) is first smoothed toward the previous `steerPosition` through the
   ladder of `update_steering_large` and `_small` calls, which keeps a flick from reaching full lock in a
   frame. Then `var_f2_2 = stick / (8 + currentSpeed / 50)` (`stick / 12` under 25 km/h, `stick / 8` while
   drifting), times `sp44[km/h]` (a per-km/h table from 0.5 to 0.8), times 1.5 when not drifting, and
   `unk_078 = stick * var_f2_2 * gKartHandlingTable[character]` (1.25 Mario, 1.28 Yoshi, 1.15 DK; 0.15 more
   past 45 on the stick). `rotation[1] += unk_078` a frame, in 65536ths of a turn. Full stick at a 150cc
   top speed is about 293 to 328 a frame, 1.6 to 1.8 degrees, 48 to 54 degrees a second: a 23 m circle at
   19.6 m/s, drawn by the velocity lagging the facing, not by a wheel angle. At walking pace it is about
   36 degrees a second. There is no steering lock, no wheel, no Ackermann, and the turn rate *falls* with
   speed through the `8 + currentSpeed / 50` divisor, which the port quotes but then applies to a wheel
   angle, which is the one thing it does not scale.
5. **The turn angle `unk_0C0`** (`func_8002AE38` `:1300`) is the kart's slide: when not drifting and the
   stick is near centre it relaxes toward `9 * unk_078`; otherwise it is measured as twice the angle
   between where the kart went and where it faces, lerped by a twelfth a frame and clamped at 40 degrees,
   and when the stick is held against the slide it is pulled toward `20 * unk_078`. It feeds the force loss
   above, the camera, and the drift state machine. The port has no such quantity.
6. **The hop and the drift** (`kart_hop` `:1192`, `func_8002AAC0` `:1219`, `func_80037CFC` `:4660`). R
   pressed on the ground hops: `kartHopVelocity` starts at 0.93 a frame and its acceleration drops by the
   jerk 0.03 a frame, which tops out at about 0.5 m over 16 frames, with `kartGravity` dropped to 500 for
   the hop. `DRIFTING_EFFECT` holds while R is held, the turn angle is past 6 degrees and the kart is
   over 20 km/h (`cancel_drift_effect` otherwise); it is not a mode you enter by pressing a button with the
   stick over, it is a slide you keep alive. While drifting the stick is remapped so it can only pick a
   point between 40 and 53 on the drift's own side (`var_s1_2`), with `(var_f2_2 + 3 or 3.5) * 0.65` on it,
   or 0.9 when pushed to the outside, so a drifting kart cannot be straightened: inside or outside is all
   the stick chooses.
7. **The mini turbo is charged by the wiggle, not the hold** (`update_drift_state_counter` `:1148`). With
   the kart sliding one way, the counter climbs only while the stick is pushed the *other* way (past 10);
   bringing it back after 18 or more frames bumps `driftState` and leaves the counter at 10. Two such
   wiggles make `driftState` 2, and releasing R then (`func_8002A79C` `:1123`) sets `MINI_TURBO_EFFECT`
   for 31 frames, during which `unk_0E8` is pulled toward 580 at 20 percent a frame (`move_f32_towards`
   is a lerp, `render_player.c:863`): 580 on a force of 4096 is 14 percent more force, so about 80 km/h for
   a second, then it decays at 1 percent a frame. A mushroom (`effects.c:554`) pulls `boostPower` toward
   400 at 50 percent a frame for 80 frames, a tenth more force, and bypasses the loss fraction entirely.
   Holding the counter at 100 (the stick never brought back) costs 4.0 a frame off `currentSpeed`
   (`:2017`) and doubles the integrator's divisor: the game punishes a held drift.
8. **The rest.** B with the stick back under 5 km/h sets `currentSpeed` to 140 in reverse; A and B
   together under 12 km/h is the spin-in-place (`AB_SPIN_EFFECT`); a wall takes 6.0 a frame off
   `currentSpeed` (`:2641`); a tumble is a timer on `unk_0C2` with three severities at 35, 28 and 4 frames
   of air. Gravity is the kart's own 2600 scaled by a per-km/h table on anything but asphalt (`sp104`).

### What the port does

`MkCar` is a `VehicleBody3D`. It carries `currentSpeed` and the acceleration table, then pushes the wheels
with an invented 5200 N (`drive_force`, listed in `UNSOURCED`) until Godot's raycast vehicle reaches a speed
ceiling derived from `currentSpeed`; it steers the front wheels to a 30 degree lock (`steering_lock`, a
judgement) scaled by the game's divisor; a drift is a flag set when the drift button is held with the stick
over, which scales the lock by 1.7 and charges a mini turbo by frames held (20 a state); a boost is a 1.25
multiplier on the ceiling. The lateral behaviour is Bullet's wheel friction, the hop is a one-off impulse,
and there is no turn angle, no force loss, no brake slide and no wiggle.

The numbers it reads are right (the top speed derivation, the tables, the frame counts), with two
exceptions: the acceleration is the CPU path's 3.2 and 2.8 scaling rather than the human's unscaled table,
so a kart reaches top speed in under four seconds instead of eleven, and `BOOST_SPEED_SCALE` 1.25 stands in
for figures that are in the source after all (a mini turbo is 14 percent more force, a mushroom 10, because
`move_f32_towards` is a lerp and `unk_0E8` and `boostPower` are added to the force).

### Why it plays badly

Every one of the things listed under "what the game does" is what the game *feels* like: the third-of-a-
second lag between facing and travel, the facing turning at a flat 50 degrees a second whatever the wheel
could do, the drift that can only be steered inside or outside, the wiggle that charges the turbo, the brake
that slides. A raycast car with a steering lock has none of them and cannot be tuned into them, because the
game has no wheels to tune. The honest fix is the one `tcps` had: rewrite the kart's movement on the game's
own integrator (a `CharacterBody3D` or a `RigidBody3D` whose velocity is set rather than pushed), keep the
items, the race, the AI, the course and the network hand-off, and read the unit scale and tables the port
already has. The whole model above is about 300 lines of C, and nothing in it needs a wheel.

### The camera

The port uses the shared `VehicleCamera` spring arm. The game's one-player race camera (`camera.c`
`func_8001E45C` `:689`, offsets at `:105`) sits 38.5 units behind and 11.6 above (4.3 m and 1.3 m) and
looks at a point 19.2 units (2.1 m) ahead of the kart, and its yaw does not follow the kart's: it is pulled
toward the kart's yaw by `adjust_angle` at a capped step, 500 units (2.7 degrees) a frame when the stick is
centred, `0xA5 + |unk_078| / 2` while steering, and through a drift it leads the kart by 12 degrees on the
drift side (`camera->unk_B0`, eased at a tenth a frame). That lag is why the kart visibly turns across the
screen before the view comes round. Worth porting with the kart.

## GTA: the vocabulary is GTA V's, the numbers are nobody's

Grand Theft Auto V has no source anywhere. The nearest thing with code is re3, Vice City's, and GTA V's
`handling.meta` is the same family of fields grown up (`fMass`, `fDriveBiasFront`, `fBrakeBiasFront`,
`fSteeringLock`, `fTractionCurveMax`/`Min`/`Lateral`, `fTractionLossMult`). The port borrows those names
for its exports and sets each by feel; none of its values comes from any car's line in any game.

What re3 actually does per wheel per step (`CVehicle::ProcessWheel`, `Vehicle.cpp:778`):

- Sideways, the wheel asks for the force that cancels its *whole* sideways contact speed this step,
  divided by the wheels on the ground. Forward, a driven wheel asks for the drive thrust; an undriven one
  asks to cancel its forward contact speed, capped by the brake (or, with no pedal, by
  `fWheelFriction / fMass`).
- Both are capped by `adhesion`, which is `0.004 * fTractionMultiplier / 4` per step, times the wheel's
  suspension load. Past it the wheel skids, and both forces are scaled down to `adhesion *
  fTractionLoss`; a wheel that was already skidding stays at the loss. That is the entire grip model.
- The transmission (`Transmission.cpp`) splits `fMaxVelocity` evenly across the gears, shifts up at two
  thirds of a gear's span and down at 0.42, and accelerates at `gas * (target - v) * fEngineAcceleration /
  |target|` per step, where the target in gear `g` is the gear's top times `3 * f^2 + 1` (`f` falling from 1
  in first to 0 in top), so first pulls toward four times its own ceiling.
- Steering is `fSteeringLock * steer^2` with the sign kept (`Automobile.cpp:3183`); it does not shrink with
  speed. Braking is `pedal * fBrakeDeceleration` per step, split `2 * fBrakeBias` front. There is no
  counter-steer assist in III or Vice City; that arrived with IV.

The port instead runs Godot's raycast wheels (slip-based friction, suspension), with a five-gear box of
invented ceilings (7, 13, 20, 30, 45 m/s) and torque multipliers, a slip-angle grip curve
(`traction_curve_lateral` 14 degrees to `traction_curve_min` 0.85), a quadratic drag of 2 N s^2/m^2 that
sets the top speed, a 0.6 counter-steer gain, 0.7 rear grip on the handbrake and a lock that shrinks to 30
percent by 40 m/s. All of it is tuning; it may well feel fine, but nothing in it can be checked, and the
README's "GTA V style" is a style, not a port.

Two ways to make it honest: port re3's model (the wheel routine above, the transmission, and a `handling.cfg`
line for a 4x4 such as `LANDSTAL`; the line itself is game data and is not in the repository, so it has to
come from a copy of the game or the modding wikis), or keep the hand-tuned car and say so in the README the
way the Twisted Metal demo already does.

## Twisted Metal 2: nothing to check against

Neither list has a Twisted Metal project, and a search for a decompilation or reverse-engineering effort
finds none; the PS1 game has never been taken apart in public. `TwRoster` says exactly where its numbers
come from (the speedrun.com stat guide and the wiki) and `UNSOURCED` lists everything else, which is the
right shape for a game with no source. The only review possible is internal: the roster's speeds are
consistent with the tables, the handling exports are judgements and are labelled as such. Nothing to do
here until a source exists.

## Rocket League: sound, with three small gaps

RocketSim is a reimplementation rather than Psyonix's code, but it is the reference everyone uses and the
port cites it. Every constant in `RlConst` that I checked against `RLConst.h` matches: gravity 650, car
mass 180 and ball 30, 2300 and 1410, the steer and powerslide curves point for point, 2975/3 and 3175/3
boost, 875/3 and 4375/3 jump, 0.025 and 0.2 and 1.25, the flip torques 260 and 224, the flip scales 1,
1.9, 2.5 and 16/15, the damping window 0.15 to 0.21, the air control torques (130, 95, 400) and damping
(30, 20, 50), the bump curves, the hitbox and wheel offsets. (The brake figure of 3500 uu/s^2 is the RLBot
wiki's; RocketSim's `BRAKE_TORQUE_AMOUNT` is a wheel torque of 180 x 14.58, a different quantity.)

The step order follows `Car.cpp`, the sticky force and the non-sticky friction curve are there, the dodge
impulse is scaled with speed and thrown flat the way RocketSim does it, the bump curves hand over velocity
rather than force. Against `Car.cpp` three things differ:

1. The first 0.025 s of a jump are at 0.62 of the held acceleration in RocketSim
   (`JUMP_PRE_MIN_ACCEL_SCALE`); the port applies full `JUMP_ACCEL` from the first tick.
2. Holding pitch against a dodge scales the dodge's pitch torque by `1 - |pitch|` (the flip cancel); the port
   locks pitch for `FLIP_PITCHLOCK_TIME` but has no cancel.
3. RocketSim applies air control and dodge torques through the inverse inertia tensor with
   `CAR_TORQUE_SCALE`; the port adds them to angular velocity as accelerations. The published figures are
   torques, so the resulting spin rate is only right if the scale happens to match; the check is how long a
   full-stick pitch from rest takes to reach the 5.5 rad/s cap, which RocketSim can answer and the port can
   be measured against.

The camera is a deliberate deviation (4.0 m back and 1.55 up against the 2.7 and 1.1 everyone plays with,
"for the blockout"), and it is what you will notice first if you know the game.

## Recommendation, in order

1. Rewrite `MkCar`'s movement on the game's integrator, with the human acceleration path, the loss
   fraction, the turn-angle slide, the drift that cannot be straightened, the wiggle-charged mini turbo at
   the source's 14 percent, and the game's own camera. Keep everything around it. This is the one demo that
   is wrong in kind rather than in degree, and the one with the source to fix it from.
2. Rocket League: the two small gaps, and measure the air torque scale.
3. GTA: decide whether it is a port (then port re3 and get a handling line) or a car of its own (then say so).
4. Twisted Metal: nothing.
