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

## Twisted Metal 2: the wrong level, and nothing to check it against

Two things the first read of this section missed, and both came from going and playing it.

**The arena is not Los Angeles.** The extractor's table maps the disc's `ROOF` database to
"los_angeles", and the README calls it "the Quake Zone Rumble rooftop arena". The game's own level
table, read out of the executable by the TwistedMetal2Recomp project (`docs/LEVELS.md`), says `01
FREEWAY` is Los Angeles: Quake Zone Rumble and `05 ROOF` is New York: The Big Leap. The Prima guide's
Los Angeles chapter describes a flat course "with no hidden areas", five first-aid kits, a fire pit below
grass level, two tunnels each with "a rooftop level to drive on and a ramp to get you up there", a warp
pad, the Hollywood sign and a generator; the manual says you are "no longer restricted to the freeway".
New York is the level the GameFAQs guide warns has "a lot of edges" and where "turbo is a big no-no".
So the demo has been a fragment of New York's rooftops with Los Angeles's name on it, and every
complaint about it is a complaint about driving New York with no walls.

**Measured in the demo**, fourteen seconds from the lights, logged every half second:

| What | Measured | Why |
| --- | --- | --- |
| Opponents | Six of seven at 0 m/s for the whole run; two perched on two or three wheels | Every one has `accelerate=false, steer=±1`: the edge feeler sees a drop ahead and to both sides from where they spawn, so they sit turning the wheels, and the stuck timer reverses them for a second into the same answer |
| Player, full throttle from spawn | 16.6 m/s at 2.5 s, over the roof edge at 3.0 s, rolled to 165 degrees, landed a tier down at 5.5 s, wedged at 0 m/s on full throttle from 8 s on | No wall at any edge, no auto-right, and a fall is the end of the run |
| Camera | Inside the geometry for the last four seconds | The spring arm pivots on a car lying against a wall |
| Rendering | 1 mesh, 0 materials, 0 textures, 9440 vertices, flat vertex colour on a flat sky | The `.TPC` texture banks are not decoded; 76 of the 325 mesh blocks fail to parse and are dropped, which is the holes in the aerial view |

The README's known rough edges already say most of this. They are not rough edges; together they are
why it cannot be played.

**What the game actually does**, from the manual, the Prima guide and the speedrun.com stat guide
(no code exists: the decomp lists carry Twisted Metal 1, Black and Harbor City, not 2; the only TM2
project is a static recompilation of the executable with a RAM map and no handling constants):

- Pad: Square or D-pad up accelerates, Circle brakes and reverses, Triangle is turbo, Cross with the
  D-pad is a hard turn, L1 and R1 cycle the pickups, L2 fires the pickup, R2 fires the machine guns and
  is meant to be held ("hold the Machine Gun button down at all times"), and the Advanced Attacks are
  D-pad sequences on an energy bar: freeze L R U, napalm R L U, jump U U L, shield U U R, mines R L D,
  rear attack L R D, invisibility R D L U, Minion's attack U D U U fire. The demo has accelerate,
  brake, turbo, fire and nothing else, on Space, Shift, Q and T.
- Turbo: "instant acceleration to top speed for as long as you hold the Turbo button", rationed, and
  "once you tap the turbo button you're at top speed". The demo ramps toward a higher ceiling.
- Speeds and health: the speedrun guide's table (Roadkill 117/156, Twister 140/178, Minion 126/168
  and so on, HP 85 to 230) is what `TwRoster` already carries; the executable keeps health on a 0 to
  120 scale (`0x78` full), which no source reconciles with the per-car table.
- Handling: Prima rates each car Sluggish, Intermediate, Tight or Ultra Tight and says nothing
  numeric. Cars do not roll over in the game; a car that goes over an edge in New York dies.

**What would make it a game.** Extract `FREEWAY` and call it Los Angeles (and `ROOF` New York). The
disc image had to be rebuilt first: the only copy on this machine was
`D:\Games\Sony (PSX) Playstation\ROMs\Sony - PlayStation (NTSC-U)\Twisted Metal 2.pkg`, a PS3 PSN
package (`UP0001-SCUS94306`) holding a PSOne Classic `EBOOT.PBP`, which psxtract on the Mac turned
back into a MODE2 `.bin`; and the PS1 disc keeps its levels as `/DMD/*.DMD` with `/TMS/*.TMS`
texture banks rather than the PC release's `/LEVELDB/*.DPC`, so the extractor needed a PS1 reader,
which is also where the textures came from. Find the dropped blocks (they were gouraud and
untextured records the old reader refused). Give the car the game's pad and turbo. Keep it on its
wheels. Los Angeles is flat, so the edge feeler stops mattering there.

## Rocket League: the constants are right and the car is wrong

The first read checked `RlConst` against `RLConst.h` and found it matching, which it does. It did
not check what the car does with them. Measured in the demo with the pad scripted, against RocketSim's
`Car.cpp` and `btVehicleRL.cpp` and Chip's notes (the smish.dev pages, via the Wayback Machine):

| What | Measured | The game | Where it goes wrong |
| --- | --- | --- | --- |
| Full throttle from rest | 5 m/s at 2.3 s, 9.4 m/s at 5.8 s, never 10 in six seconds | 1410 uu/s (14.1 m/s) in 2.4 s: 1600 uu/s^2 at rest, 160 at 1400 | `THROTTLE_ACCEL` is 4.0 and its comment reads `THROTTLE_TORQUE_AMOUNT = CAR_MASS_BT * 400` as 400 uu/s^2. `Car.cpp:409-414` sets that same force on every one of the four wheels; the port splits 4 m/s^2 across them. The car has a quarter of its engine |
| Boost from rest | 23 m/s at 2.4 s | about 1.7 s | the same quarter engine under the boost |
| Turn radius, full lock | 3.8 m at 9.3 m/s; 1.8 to 2.9 m from 2 to 6.6 m/s | Chip's curvature table: 3.9 m at 930 uu/s, 1.75 to 2.9 m over that range | nothing: the steering curve and Godot's wheels reproduce the game's radii |
| At rest | `wheels_down` reads 0 every other tenth of a second; the body moves through 11 cm | sits still | Godot's `damping_compression` is used raw (`force -= damping * vel`, `vehicle_body_3d.cpp:573`), so 0.55 against a stiffness of 220 is two percent of critical. The car bounces on its springs for ever |
| After a jump landing | bounces for 1.5 s, `on_ground` flickering; a jump press in that window is lost | lands and stays | the same springs. This is the wobble, and it is why jumps and flips feel eaten |
| Air pitch to the 5.5 rad/s cap | 0.04 s | 0.44 s (12.46 rad/s^2, RLBot wiki) | `_air_control` adds `AIR_CONTROL_TORQUE` 130/95/400 straight to angular velocity as rad/s^2. `Car.cpp:677` multiplies the torque by the inertia tensor and by `CAR_TORQUE_SCALE` 0.0959, so the real angular accelerations are 12.46, 9.11 and 38.35 and the damping rates 2.88, 1.92 and 4.79. Every air axis, the dodge torques 224/260, the auto-flip 50 and the auto-roll 80 are 10.4 times too strong |
| Powerslide at 6 m/s | slip 138 degrees and 6 to 0.25 m/s in one second, on full throttle | lateral grip to a tenth, longitudinal to a half, the car keeps driving | Godot has one `wheel_friction_slip` that caps the lateral and the drive impulse together; cutting it to 0.1 cuts the drive to nothing |
| Jump, first 25 ms | full `JUMP_ACCEL` | 0.62 of it (`JUMP_PRE_MIN_ACCEL_SCALE`, `Car.cpp:586`) | small, and known from the first read |

Two of `UNSOURCED`'s entries are wrong. The suspension figures do transfer: RocketSim's spring is
`(rest - length) * 500 - 25 * v` compression, `40` relaxation, times a per-wheel scale of 35.75
front and 54.265 back (which sum to the car's 180), with no chassis mass in it; Godot's is the same
Bullet formula with `* chassis_mass` in place of the scale. Stiffness and damping are per unit length
and per unit time, so the unit of length cancels and they carry straight over as `500 * 35.75 / 180 =
99.3` front and `150.7` back, damping `4.97 / 7.94` front and `7.54 / 12.06` back, rest length
`38.755 - 12 = 26.755` uu front and `25.055` back, travel 12 uu, no force limit. And the surface
normal is not unreported: Godot's wheels carry it as `get_contact_normal()` since 4.3.

The friction model is the one real gap. RocketSim's lateral impulse is `-0.2 * v_axle / jacDiag *
latFriction * 60 * dt` per wheel with no cap, where `latFriction` runs from 1.0 rolling to 0.2 sliding
on the slip fraction and the handbrake multiplies it by 0.1; Godot's is the same bilateral `-0.2 *
rel_vel`, capped by `suspension_force * dt * wheel_friction_slip`, with the drive impulse under the
same cap. The radii above say the cap is not biting in a steered turn; the powerslide says it bites
in a slide. Driving the throttle as a central force along the nose, which is what RocketSim's
per-wheel engine impulses add up to, takes the drive out from under the cap and leaves
`wheel_friction_slip` as the lateral grip alone, which the handbrake can then cut to a tenth.

The camera: no source states the game's defaults. The RLBot page and RocketSim carry no camera
figure, and the pro settings guides report 110 FOV, 270 distance, 90 to 110 height, -3 angle, 0.4 to
0.5 stiffness and 5 to 7 swivel as what is played with. The demo's 4.0 m back and 1.55 up and the
spring-arm follow that lags five per second and swings to the direction of travel are the addon's road
car camera, not the game's, and ball cam is that camera pointed at the ball.

Brake 3500, coasting 525, the stopping threshold, the boost figures, the jump and dodge constants, the
bump curves and the sticky force check out against `Car.cpp` line by line.

## The pad shows nothing on a controller

`HumanDriver._apply_hud_visibility` sets `controls.visible` from
`PlayerSettingsResource.hud_shown`, whose default answers true only for a touchscreen. So in all
three battle demos a joypad gets no HUD at all, and the labels the cars write ("Jump" on A, "Boost"
on B, "Accelerate" on RT) are never drawn. The player controller's own `Player.apply_hud_visibility`
keeps the node visible and sets `controls.contextual_only = not shown`, which draws only the slots a
label was written on; every slot the cars write is contextual, because the HUD scene's resting labels
are blank. The driver has to do what the Player does.

## Recommendation, in order

1. Rocket League: the engine to 1600, the suspension to RocketSim's, the air torques through
   `CAR_TORQUE_SCALE`, the throttle as a central force so the powerslide keeps its drive, the jump
   pre-minimum scale. All five are the source's own numbers. Then the camera, which is a judgement.
2. The pad: `HumanDriver` draws the HUD the way the Player does.
3. Twisted Metal: extract the right level. Textures and the dropped blocks after that, and the game's
   pad, turbo and no-roll; none of it has a source beyond the manual and the Prima guide.
4. GTA: decide whether it is a port (then port re3 and get a handling line) or a car of its own (then
   say so). The road car's springs have the same two percent damping, 0.7 against 18.
