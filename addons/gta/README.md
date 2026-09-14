![Preview](./assets/gta.png)

# Godot Tim's Automobile (GTA) for Godot 4.8+

Driving for the [3D Player Controller](../3d_player_controller/README.md): one rideable chassis and three
cars built on it, each with handling of its own.

`Vehicle` is the chassis, and it is deliberately small. It holds the wheels, the rideable contract the
controller's `Riding` state expects, and the multiplayer hand-off that moves a car to whoever is driving it.
It holds no handling model at all, because how a car feels is the whole of what makes it that car.

| Car | Scene | What it drives like |
|---|---|---|
| `GtaCar` | `scenes/honda_crv.tscn` | A road car. Five-gear transmission, traction curve, drive and brake bias, handbrake slides, counter-steer assist, drag, downforce, anti-roll bars, RPM-driven engine audio, flip / burn / explode damage, first-person look and a speedometer. |
| `RocketCar` | `scenes/rocket_car.tscn` | A Rocket League battle car. Boost, jumps, flips, aerials, wall driving and demolitions, every figure taken from a published source. |
| `Tm2Car` | `scenes/tm2_car.tscn` | A Twisted Metal 2 car. Arcade throttle to the car's published top speed, turbo to its published turbo speed, and a wreck state when its armour runs out. |

The Player lends its body and its input through the controller's `Riding` state, which plays the enter and
exit clips a car names, makes its camera current and turns the driver's collision off for the seat. No car
touches Player flags or Player UI.

> [!NOTE]
> Requires `addons/3d_player_controller` (the `Player`, its `Riding` state, the `EnteringCar` / `Driving` / `ExitingCar` animation clips in `player.tscn`, and `PlayerSettingsResource` for the SFX volume) and, through it, [`addons/controls`](https://github.com/kirbycope/godot-controls), which is where `ActionPrompt` and the on-screen button hints live. The car scripts and `VehicleCamera` register their class names on their own; enabling the plugin only adds `GtaCar` and `RocketCar` to the Create New Node dialog. The `Vehicle` base is not registered, because a bare chassis is not a car.

---

## Interactive Demo Scene

Open and run **`res://addons/gta/scenes/demo/demo.tscn`**: an asphalt lot with a ramp, the Honda CR-V and the Player. Walk to the car and press Action to get in; Space accelerates, Shift brakes, the throw button is the handbrake, F5 goes first-person, Action gets out (straight out at speed, through the door at rest).

| Node | What it is |
|---|---|
| `Lot` (`CSGBox3D`, group `CONCRETE`) | The floor. |
| `Ramp` (`CSGPolygon3D`) | A wedge to jump. |
| `HondaCRV` | `honda_crv.tscn`, nothing to set. |
| `Player` | `player.tscn`, nothing to set. |

---

## Playing the demo

This repository is the project the demo is built from. It uses the layout the
[Godot Asset Library](https://docs.godotengine.org/en/stable/community/asset_library/submitting_to_assetlib.html)
expects, with the addon at `addons/gta/` and a `project.godot` at the root, so cloning it and
opening it in Godot is all it takes. The addon is edited in place, with nothing copied first.

The player controller and the Controls addon sit under `addons/` beside it. They are not committed
here; `tools/addons.json` lists them and `python tools/pull_addons.py` fetches them, so run that
once after cloning.

---

## How to Use

| Node | Where it goes | Set in the Inspector |
|---|---|---|
| `GtaCar` (instance `scenes/honda_crv.tscn`, or the script on your own `VehicleBody3D`) | In your level, on the ground | The handling exports (`max_acceleration_force`, `drive_bias_front`, `traction_curve_*`, `max_steering_angle`, ...), `wheels`, the drive action exports; children `DriverSeat`, `EnterCar`, optional `ExitCar` markers, `PlayerDetection` area, the engine `AudioStreamPlayer3D`s, `FirstPersonCamera`, `VehicleCamera` (instance `scenes/vehicle_camera.tscn`) and `DrivingUI` (instance `scenes/driving_ui.tscn` with `vehicle` set) |
| Damage effects (optional) | A scene that inherits the car and adds them | Children named `Fire_05` (with a `FireSFX` player) and `VFXGroundExplosion_01` (with an `ExplosionSFX` player); without them the car still flips and locks up but never burns. The host project's `scenes/honda_crv.tscn` is that inherited scene. |

A car is driven one of two ways, and cannot tell them apart. A `Player` who walks up and gets in reaches it through the rideable contract below; that is the road car's way, and the only demo that needs a `Player`. The two battle demos have no `Player` at all: a `HumanDriver` node under the car fills the same virtual pad the AI brains fill, from the keyboard or a joypad, and there is nothing to get out of. Their on-screen controls are `CarControls` (`scenes/car_controls.tscn`), the Controls addon's HUD with only the car's slots mapped; it registers the car actions with the same keys the player controller binds, and the driver labels its buttons with what the car says they do.

Standing in `PlayerDetection` shows the prompt (`ActionPrompt.show_for(player.controls, "Get In")`); Action calls `Player.mount(vehicle)`. The `Riding` state calls back `mount(player)`, which puts the Player at `EnterCar` and starts the chase camera, then plays `mount_animation` (`EnteringCar`) and, once it ends, calls `ride(player, delta)` every physics frame: the car seats the Player on `DriverSeat`, reads accelerate / brake / handbrake / steer from its own action exports (resolved for the `input_type` the state keeps current) and feeds its drivetrain. `camera` is the `VehicleCamera` (a spring arm behind the car that follows the direction of travel once it moves, or the facing at rest, with manual look that holds for a moment); the state makes it current and hands the Player's own back on dismount. Setting its `look_target` locks it onto a node instead, keeping that node in view with the car between the two, which is what the Rocket League demo's ball cam is; left null it behaves exactly as it always has. The exit action in `ride_input` calls `player.dismount()`: at rest the state plays `dismount_animation` (`ExitingCar`) first, above `BAIL_OUT_SPEED` the car calls `dismount(true)` and the Player is straight out. `blocks_hands` holsters weapons and hides the crosshair, `disables_collision` turns the driver's collision shape off inside the body, and `get_contextual_controls(input_type)` names the labels (`"joypad_button_0": "Exit"`).

### Multiplayer

The body moves on the car's multiplayer authority and `VehicleSynchronizer` carries its transform, velocities, drive state, damage flags, `current_driver_peer_id` and `radio_station` to the other peers. Getting in hands the authority to the driver's peer on every peer (`_set_authority`, an `any_peer` / `call_local` reliable RPC, the shape a rideable hands itself over in) and getting out hands it back to the server; a driver whose peer disconnects hands it back on every peer too. Offline, with no peers, it is a plain `set_multiplayer_authority`. `current_driver_peer_id` is `SERVER_PEER` (1) while nobody drives.

`radio_station` is an `int` the car carries for whatever radio the project gives its riders; the car plays nothing itself. The driver writes it (they hold the authority, so it replicates) and `radio_station_changed(station)` fires on every peer, so each rider's own radio can follow the car's station while they are in it. The host project's `scenes/world.gd` does that with the `radi_ot` addon: the driver's next / previous station actions move the car's station, and every radio in the car tunes to it.

### Building your own car on `Vehicle`

The chassis gives a car four things and asks for a handful back.

What it gives: `wheels` and `wheels_in_contact()`, `apply_wheel_forces(drive, brake)` which splits both
across the wheels rather than setting each whole, the whole rideable contract (`mount`, `dismount`,
`ride`, `ride_input`, `get_contextual_controls` and the properties the `Riding` state reads), the
multiplayer hand-off (`set_driver`, `current_driver_peer_id`, `SERVER_PEER`), `set_sfx_volume` wired to
the player controller's audio settings, and membership of the `vehicles` group.

What your scene must add: four `VehicleWheel3D` children listed in `wheels`, a `VehicleCamera` (instance
`scenes/vehicle_camera.tscn`), and `read_controls()`, which reads the buttons and drives. `ride()` for a
seated `Player` calls that after checking the body is not paused; a `HumanDriver` calls it directly. A car
with neither sits there while somebody sits in it. If the car has a press-toggle, the ball cam is one, put
it in `read_toggles(event)` and both routes deliver the event.

One thing is worth knowing before you add a `Seat`. The `Riding` state pins the driver to it the moment
they get on, **before** `mount_animation` plays. That is right for a car with no door, where getting in is
instant, and both `RocketCar` and `Tm2Car` have one. It is wrong for a car whose get-in clip is authored to
start at the kerb and walk the driver in, because they would play that walk from inside the seat. `GtaCar`
is that car: it has no `Seat` node at all and seats its driver itself in `ride()`.

---

## Twisted Metal 2: the Los Angeles level

`Tm2Car` is a car of its own on the shared chassis, with a combat layer beside it, and a demo built on
Twisted Metal 2's own Los Angeles arena. Open **`res://addons/gta/scenes/demo/twisted_metal.tscn`**: the
level loads with you already at the wheel of Roadkill and six opponents driving the arena and
fighting each other as well as you. There is no `Player` in this demo and nothing to get out of.

| Node | What it is |
|---|---|
| `Tm2Car` (`scenes/tm2_car.tscn`) | The car: arcade handling, a turbo and a wreck state. `car` is a [`Tm2Roster`](scripts/tm2_roster.gd) key, which is where its top and turbo speeds come from. |
| `CarCombat` (child of a `Tm2Car`) | Health, the weapon inventory and firing. Its own `car` key is where its health and special timing come from. |
| `AiDriver` (child of a `Tm2Car`) | The opponent. Set `waypoints` and `aggression`; `enabled` off leaves the car to a human. |
| `HumanDriver` (child of a `Tm2Car`) | You. Fills the same pad from the keyboard or a joypad; the demo puts one under Roadkill. |
| `CarControls` (`scenes/car_controls.tscn`) | The on-screen controls, and only the car's. Registers the actions the car reads; shown or hidden by the player's HUD setting, so a desktop draws none. |
| `Tm2Ui` (`scenes/tm2_ui.tscn`) | Armour, the selected weapon and the turbo meter. It reads nothing: every number arrives on a signal. |
| `Tm2Waypoints` (resource) | The arena's own AI path, read off the disc. |
| `Tm2Projectile` | One shot in flight. Damage, speed and homing come from the roster. |

### Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Accelerate | `Space` | Right Trigger |
| Brake, then reverse | `Shift` | Left Trigger |
| Steer | `A` / `D` | Left Stick |
| Turbo | `Q` | Left Bumper |
| Get out | Action | A |

Twisted Metal 2 puts turbo on Triangle. This addon's action set has no Triangle and brake already has
shift, so turbo sits on the spare `ability` action instead.

### How it drives

Twisted Metal is not a driving game with weapons bolted on, it is a shooter where the floor moves. Its cars
turn as hard flat out as they do at a crawl and reach their top speed almost at once, so `Tm2Car` has no
gearbox, no traction curve and no speed-sensitive steering. What it has is a constant drive force, a
ceiling, and a turbo that raises the ceiling.

Both ceilings are published: `Tm2Roster` carries every car's real top speed and turbo speed off the
community stat tables, so Minion out-runs Roadkill here because it does in the game. Everything else, the
force that gets a car there, the brake, the reverse speed, the steering lock and both turbo rates, has no
published figure anywhere. Each one is an export with a comment saying so, and each is named in
`Tm2Roster.UNSOURCED` rather than dressed up as a fact.

The turbo meter refills on its own over time, which is what the real one does; the real game also drops
turbo pickups in its arenas, and this demo has no pickups of any kind, so that half is missing rather than
wrong.

When `CarCombat` runs a car's armour out, its `died` signal is wired in the scene to `Tm2Car.on_died` and
the car stops answering the controls and rolls to a stop. There is no fire and no explosion: that was the
road car's damage model and it does not come with the chassis.

### Which way is forward

This chassis drives along **+Z**, not Godot's usual -Z, and that was measured rather than assumed: an
opponent rolling on four wheels in the arena travels along its own `basis.z` with a mean dot product of
0.99 over fifty samples. `Tm2Car.forward()` is the single place it is written down, and the model, the
seat, the camera, the AI's edge feelers, its firing cone and both muzzles all read it from there.

Getting that wrong is quiet rather than loud, and it had been wrong. The forward muzzle sat on the tail of
the car and fired out of the back, the rear muzzle sat on the nose, and the AI felt for the edge of the roof
behind itself and steered to put its waypoint over its shoulder. Fixing the sign is most of why the
opponents now drive the arena instead of falling off it.

The `AiDriver` still never touches the handling model. It fills in a virtual control pad and hands it to
`Tm2Car.set_drive_input`, which is how Twisted Metal's own `AICarUpdateControlPad` works. It has the same
four inputs a person has and no others.

### Where the behaviour comes from

There is no Twisted Metal 2 source code. The [Twisted Metal 1
decompilation](https://github.com/abelbriggs1/tm1_decomp) has only three files decompiled, and the
[Twisted Metal: Black one](https://github.com/abelbriggs1/tmb_decomp) three more, none of them
gameplay. What tm1_decomp does carry is a splat config with 1,973 named symbols from the retail
binary, and Twisted Metal 2 runs on that same engine. The AI is modelled on those names, and each
step in `ai_driver.gd` says which routine it stands in for: `AICarOutOfBattle` and `AICarInBattle`,
`AICarDriveBetweenPts`, `AICarInitSwerve`, `AICarUpdateHealthTier`, `AIPickAttackWeapon`,
`AICarChooseForeWeapon` and `AICarChooseAftWeapon`.

The numbers are a separate matter. Health, top speed, turbo speed and special recharge come from the
published community stat tables, and weapon damage from the Twisted Metal wiki; the per-car stat
screens on the disc are pictures, not tables, so they could not be read. Anything that could not be
sourced is listed in `Tm2Roster.UNSOURCED` rather than invented.

### Building the assets

The converted level and cars are committed under `addons/gta/assets/twistedmetal2/`. The material is
Sony's and SingleTrac's, so it is here on the understanding that it is not ours to license; only the
raw files pulled off the disc are git-ignored, because the extractor rebuilds those on demand. To
build them again, or to add another level, point it at your own copy of the game:

```powershell
python tools/extract_tm2.py "Twisted Metal 2 (USA) (Track 01).bin"
python tools/extract_tm2.py tm2.iso --all          # every level on the disc
```

It reads the ISO9660 filesystem off the disc image, decodes the `.DPC` model database into a glTF
with the game's own vertex colours, and turns the level's `.PTS` terrain file into the `Tm2Waypoints`
the opponents drive along. The demo scene loads all of it at run time and says so on screen if it is
missing, so the project still opens in a checkout that has none of it.

Twelve levels are on the disc. `ROOF` is Los Angeles, the "Quake Zone Rumble" rooftop arena;
`SROOF` is the cut-down split-screen copy of it, as `HKONG` is of `HONGKONG`.

The car models are a separate job: `tools/tm2/cars.py` rescales the ripped `.obj` models, which come
at wildly different sizes, to a common 4.5 m length and sits them on the ground.

### What the format turned out to be

Documented in `tools/tm2/dpc.py`, reverse engineered from the retail data with no game code involved.
A `.DPC` is a tree of nodes with absolute pointers based at `0x80019c40`. A mesh node is keyed
`0x0000ff00` and is only genuine when its polygon pointer equals its own address plus `0x2c`, which
is what separates it from the same bytes appearing elsewhere. Vertices are PlayStation `SVECTOR`s,
three `int16`s and two bytes of padding, and the game is Z up where Godot is Y up. A polygon record
is `nVerts, 0x01, sizeInDwords, primWords` followed by the vertex indices and a partly prebuilt
PlayStation GPU primitive, whose fourth word carries the colour and the command code: `0x2c` for a
textured quad, `0x3c` for a gouraud one. The indices run round the polygon, so a quad fans from its
first corner rather than pairing up the way a PlayStation strip does.

One number in the pipeline is tuned rather than read: the world scale of 1/64 m per game unit. At
that scale the drivable quads come out about 6 m across, the waypoints about 25 m apart and the
Los Angeles play area 252 x 166 m, which agree with each other, but the game's own constant has not
been found.

### The fan remake, side by side

`twisted_metal_fanmade.tscn` loads Angel V Mendez's Sketchfab remake of the scrapped version of the
same level, so the two can be compared in the same game with the same cars. The comparison:

| | Extracted from the disc | Fan remake |
|---|---|---|
| Geometry | 2,406 verts, 2,586 faces | 16,455 verts, 9,297 tris |
| Surfacing | the game's own vertex colours; textures not decoded yet | 34 textures with normals and UVs |
| Layout | rooftops over a street tier, as shipped | the scrapped street level, tidied up by its author |
| AI path | the level's own 140 `.PTS` waypoints | none, so the drivable surface is sampled instead |
| Scale | already metres, straight out of the extractor | unknown units, measured and fitted to 250 m |

The same script drives both. A level that brings no waypoints has them sampled off its surface, a
level with no collision gets a trimesh built for it, and a level in unknown units is measured rather
than guessed at (`level_scale = 0`). Both maps wrap themselves in huge painted scenery, which is
stripped by size so the engine's own sky shows instead.

### Known rough edges

- About a fifth of the mesh blocks in a level fail to parse and are dropped rather than drawn wrong;
  Los Angeles keeps 249 of 325. Textures are not decoded at all yet, so the level renders with its
  vertex colours and the `.TPC` texture banks are untouched.
- The arena is two tiers, rooftops and the street far below. Opponents feel for the edge with
  raycasts and turn away, but they still go over sometimes, and a car that ends up on the wrong tier
  has no route back. Anything that leaves the world entirely is put back on the roof.
- Opponents drive the arena well enough for the first half minute or so and then tend to settle: they
  wedge against the rooftop geometry, drop to a tier they cannot climb out of, or end up on full throttle
  doing two metres a second against something. On flat ground the same car reaches three quarters of its
  published top speed in seven seconds, so this is the arena rather than the handling.
- A car that goes over a rooftop edge tumbles onto the tier below and stays on its roof; only a car
  that leaves the world entirely is put back. Twisted Metal's own cars do not roll, and there is no
  auto-right here yet, so a hard turn held into an edge at speed ends your run.
- The energy attacks are not implemented at all: no freeze, mine, rear fire, jump, shield or button
  combos. The turbo and the pickup weapons are the whole of what a car can do.
- Every car uses one generic collision box and one set of wheel positions, sized for a 4.5 metre car.
  Sweet Tooth is an ice cream truck and Minion is a tank, and neither of them fits it. The wheel meshes
  are hidden because the ripped models draw their own wheels, so the mismatch shows in the physics rather
  than on screen.
- The engine sound is the addon's own Gravity Sound engine loop pitched by speed, which is a placeholder
  that happens to be licensed and already here. There is no turbo sound at all: `SFXTurbo` is in the scene
  with no stream, waiting for a real one.
- The fan remake is only half playable. It loads, scales, collides and the cars spawn on it, but the
  sampler finds few waypoints on it and the opponents do not drive it the way they drive the
  extracted arena. It is there for the comparison above rather than as a finished level.


---

## Rocket League: soccar

A second demo built on the same `Vehicle` chassis, and a much bigger departure from it than the
Twisted Metal one. Open **`res://addons/gta/scenes/demo/rocket_league.tscn`**: a three a side match
on a full size soccar pitch, five AI cars, a five minute clock, goal replays and overtime.

There is no `Player` in this demo, the same as the Twisted Metal one. You are a `HumanDriver` under
a blue car, filling the same pad the five brains fill, and there is nothing to get out of. The car is
put on its kickoff spot after every goal and you are simply still at its wheel.

### Controls

| Action | Keyboard / Mouse | Gamepad |
|---|---|---|
| Accelerate | `Space` | Right Trigger |
| Reverse | `Shift` | Left Trigger |
| Steer | `A` / `D` | Left Stick |
| Pitch (in the air) | `W` / `S` | Left Stick |
| Boost | `Left Click` | `B` |
| Jump, and again to flip | `Ctrl` | `A` |
| Powerslide, and air roll | `T` | `X` |
| Ball cam | `Q` | Left Bumper |
| Reset the match | `R` | - |

A flip is a second jump with the stick pushed. Pushed forward it is a front flip, sideways a side
flip, back a back flip, and the back one carries furthest.

### Ball cam

On by default, the way Rocket League opens every kickoff, and toggled with `Q`. It is not a separate
camera: `VehicleCamera` gained an optional `look_target`, and ball cam is that pointed at the ball.

The trick is that aiming the pivot along the line to the target is what puts the car between the
camera and the ball, because the spring arm hangs off the back of the pivot. So one line decides
where the camera sits and where it looks, and the tilt follows the ball into the air up to a
configurable limit. With `look_target` left null it is the ordinary chase camera it always was, so
the Honda CR-V and Twisted Metal demos are untouched, and anything else that wants a camera locked
onto something can have one.

### The chassis is shared, the handling is not

`RocketCar` sits on `Vehicle`, the same chassis the road car and the Twisted Metal car sit on. The
chassis is the wheels, the rideable contract and the multiplayer hand-off, and nothing else: no
drivetrain, no gearbox, no HUD. A battle car is thirteen nodes rather than the thirty it had when it
was built on the road car, it carries its own boost, jump and impact sound, and it bounces off the
world at the published 0.3 rather than a road car's 0.

That split was worth making. The battle car used to extend the CR-V to borrow a raycast body, four
wheels and the rideable contract, and inherited a road car's whole apparatus along with them: thirty
five handling exports a battle car never reads, a five speed gearbox, a traction curve, air drag,
downforce, anti-roll bars, a fire and explosion damage model, a first person camera, a speedometer, a
door animation, a radio, an action prompt, seven timers and eleven audio players, per car. One piece
of it was quietly fatal. The road car's engine audio only ever runs for a car driven through its own
`set_drive_input`, which a battle car never calls, so **every battle car was silent**.

Rocket League drives its cars on Bullet's raycast vehicle and Godot's `VehicleBody3D` is a port of
that same raycast vehicle, so the body, wheels and suspension are a fair match; everything above
them is Rocket League's own.

On the ground the throttle follows a torque curve that reaches zero at 14.1 m/s, which is why boost
is the only way past it, and the steering lock shrinks with speed off a second curve. In the air the
wheels are doing nothing, so the car is flown directly: pitch, yaw and roll are angular
accelerations against a damping term that falls away as the stick is pushed.

Gravity on this pitch is 6.5 m/s squared, a third under Earth's, set by an `Area3D` over the whole
arena rather than by changing the project.

The step follows RocketSim's own order: wheels, then air control, then jump, then auto-flip, then
the dodge, then the sticky force, then boost. Four things in it are worth knowing about.

**The sticky force** is why this can be played on the walls. Any car with a wheel on a surface is
pressed into that surface by `upDir * scale * gravity * mass`, where the scale is half on its own
and gains `1 - abs(up.y)` while the throttle is down. Flat ground gets half a gravity of extra
downforce and a vertical wall gets one and a half, which is more than the car's own weight and is
the entire reason it can hold on up there. Let go of the throttle on a wall and the non-sticky
friction curve drops you off it.

**The ground is three wheels, not one.** Rocket League's `isOnGround` is
`numWheelsInContact >= 3`; on one or two it hands you air control and lets you flip, which is how a
car tipped into a corner gets itself out.

**Auto-flip.** Land upside down and a jump pushes through the roof, and the roof is against the
floor, so without this a car is simply stuck. Pressing jump while over on its back throws it back
the right way up.

**Bumps.** A supersonic hit on an opponent wrecks it, but every other hit still throws the car that
was hit, on a published curve of the closing speed with an upward part on top. Teammates can be
bumped but not wrecked, the way the game has it.

Input is eight values, the same eight RocketSim's `CarControls` carries, and yaw and roll are
separate axes rather than one stick with a modifier. A person on the default bindings still drives
one at a time through the air roll button, but an AI or a rebinding can use both at once, which is
what directional air roll is. Stick forward pitches the nose down, as in the real game.

### Where the numbers come from

Every physics figure is copied from a published source into `scripts/rocket_const.gd`, converted
from Unreal units at 1 uu to 1 cm, with the original value in the comment on each line. The bulk of
it is [RocketSim](https://github.com/ZealanL/RocketSim)'s `src/RLConst.h`, the reference
reimplementation of Rocket League's simulation, cross-checked against the
[RLBot wiki's game values](https://wiki.rlbot.org/v4/botmaking/useful-game-values/) and its
[jumping physics](https://wiki.rlbot.org/v4/botmaking/jumping-physics/) page. Car hitboxes and wheel
positions come from RocketSim's `CarConfig.cpp`.

One conversion is the addon's own rather than Rocket League's. The chassis noses along Godot's positive
z, the opposite of Godot's usual convention, so `to_godot_yaw` adds a quarter turn rather than taking one
away. It used to subtract, and every kickoff faced away from the ball: the ball cam then sat in front of
the nose, pressing accelerate drove the car into the camera, and the steering looked mirrored because
you were watching the front of the car. `test_every_car_faces_the_ball_at_kickoff` holds that shut.

That covers the pitch at 81.92 by 102.4 metres, the 2048 uu ceiling, the goal line at 5124.25 uu,
the ball at 91.25 uu across with its 60 percent bounce, a top speed of 2300 uu/s and supersonic at
2200, boost at 33.33 a second for 991.67 uu/s squared on the ground and 1058.33 in the air, the jump
and dodge timings, the air control torques, the five kickoff spots, the four respawn spots and all
thirty four boost pads.

What could not be sourced is listed in `RocketConst.UNSOURCED` rather than invented: the suspension
figures in Godot's own units, the wheel friction, the match clock, the AI's thresholds and the
camera settings. The field of view is Rocket League's 110; the camera is further back and higher
than the game's, because this is an untextured blockout with nothing to judge distance against.

### The pitch

`RocketArena` builds it from those same constants as a `@tool` script, so it is there in the editor
viewport. It is the real shape: a rounded rectangle with a 45 degree chamfer across each corner,
which is what the published 1629.174 uu of corner wall describes once you work out that it cuts
11.52 metres off both axes. The goals are open mouths in the back walls with a box behind rather
than a hole cut out of a solid wall, because three flat panels are cheaper and more predictable than
a constructive solid subtraction.

The boost pads are placed from the published coordinate tables, six big ones worth a full tank on a
ten second cooldown and twenty eight small ones worth twelve on four seconds.

Every wall also gets a quarter pipe along its base, because a floor that meets a wall at a right
angle is a wall you can only hit. RocketSim loads collision meshes ripped from the game and the real
arena curves into its walls; this has to build that curve, and it is a corner block with a cylinder
subtracted from it rather than a cylinder laid in the corner, which would give a convex bump that
stops a car dead. The back wall's is in two pieces either side of the goal, since a ramp across the
mouth would be a ramp over the goal line. The radius is a judgement call, not a published figure.

### The AI

`RocketAi` is built the way `AiDriver` is: it never touches the handling model, it fills a virtual
control pad and hands it to `RocketCar.set_rocket_input` once a physics frame. It has the same seven
inputs a person has and no others, so it cannot steer harder or see further than the car it is in.

Three roles are shared out among a team every frame on distance rather than fixed: whoever can reach
the ball soonest attacks, whoever is furthest back defends, anyone left over holds the middle and
keeps their tank full. It aims from behind the ball along the line back from the goal, so a hit goes
somewhere rather than wherever the car happened to be pointing, and it leans on `RocketBall.predict`
to work out where the ball will be. That prediction steps the ball forward under gravity and drag
and bounces it off six flat planes; it ignores the rounded corners and every car, so it is a guide
rather than a guarantee.

### Replays and resets

The goal replay is a ring buffer, not a file. Every physics frame the transform of every car and the
ball goes into a fixed number of slots, oldest overwritten, so the cost is flat however long the
match runs. A goal plays the last four seconds back at 65 percent speed, taking the bodies out of
the physics world and setting their transforms straight from the buffer, so it shows what actually
happened rather than a re-simulation that drifts.

The camera for it is filmed from the playing side, above and off to one side, looking back at the
goal mouth. Rocket League watches its goals from behind the net because its stadium is open back
there and full of seats; this arena is a closed box, so everything beyond a back wall is either the
inside of the goal or the void outside, and a camera put there films the back of a wall. It hangs
off a spring arm anchored at the goal rather than being placed outright, so anything that does come
between the two pulls it in until it can see, and it turns to follow the ball so a replay that
starts four seconds before the goal is not four seconds of an empty net.

Then the kickoff: ball on the centre spot, everyone on the published spawn spots with a third of a
tank, three second countdown, and the spot the player takes rotates so the same car does not take
every kickoff. `R` resets the whole match. At full time a draw goes to overtime and the next goal
ends it; a shot still in the air when the clock hits zero is still live.

### Changing the match

Everything worth changing is exported on the `RocketLeague` node: `team_size` (three a side by
default, anything from one to five), `match_minutes`, `ai_skill` from zero to one, and `seat_player`,
which turns the whole thing into an AI match to watch. `RocketCar` exports `starts_in_ball_cam` and
every action name, and `VehicleCamera` exports the lock-on's tilt limit.

### Known rough edges

- The cars and the pitch are an untextured blockout. The car is an Octane sized box at the published
  hitbox of 120.507 by 86.6994 by 38.6591 uu, not a model.
- The sound is the addon's own Gravity Sound car effects put to new use: an engine loop pitched by
  speed for boost, an engine start for the jump, a crash for impacts. They are placeholders that
  happen to be licensed and already here. A boost whoosh, a goal horn and a ball hit want real
  sounds.
- Godot's `VehicleWheel3D` has one grip scalar where Rocket League has separate lateral and
  longitudinal friction curves with their own handbrake factors, and it does not report its wheel
  contact normals, so the surface under a car is found with one ray from the chassis instead of
  averaged over four wheels. Both are in `RocketConst.UNSOURCED`.
- A dodge does not quite complete its rotation before the torque window closes, because the
  published 5.5 rad/s angular cap bites first. Auto-flip is what gets you off your roof afterwards.
- Hitting the wall transition at full boost launches the car off it rather than carrying it up in
  contact, because a four metre radius cannot be followed at twenty metres a second. Rolling on at a
  more measured speed drives up properly. The real game behaves much the same way, but its curve is
  a different shape and the speed you can carry onto a wall is not the same.
- The quarter pipes at the base of each wall are an invention. The real arena's transition is a mesh
  ripped from the game, which this project does not have, so the radius is chosen rather than
  measured, and the pieces meet imperfectly at the corners.
- There is no aerial training and no second game mode.
- Single player against AI only. The `Vehicle` multiplayer authority handling underneath is intact
  but nothing in the match rules has been driven over a network.

---

## Tests

```powershell
& 'C:\Godot\godot.exe' --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://addons/gta/tests -gexit
```

One test script per car, plus one for the chassis they share:

| Script | What it covers |
|---|---|
| `test_vehicle.gd` | The chassis: the rideable contract, the wheel helpers, the multiplayer hand-off, the SFX volume, and that no handling model rode along with it. |
| `test_gta_car.gd` | The road car: mounting behind the enter animation, the drivetrain, the door, the speedometer, the action prompt and the radio. |
| `test_rocket_car.gd` | The battle car: boost, the jump and dodge state machine, supersonic and demolitions. |
| `test_tm2_car.gd` | The Twisted Metal car: `forward()` against the way a driven car actually travels, the published speed ceilings, the turbo meter and the wreck. |
| `test_human_driver.gd` | The person's hand on a battle car's pad: keyboard bindings with no joypad, the switch on a pad press, space as the throttle and never the exit. |
| `test_car_controls.gd` | The car-only HUD: it registers every action the cars read and nothing they do not, and every label a car gives sits on a slot that really reads that way on that device. |

Most of them are unit tests over one script at a time and run in seconds.
`test_rocket_league_demo.gd` is different: it loads `rocket_league.tscn` whole and plays it, so an
all-AI match moves the ball and empties boost pads, a car drives off the kickoff and hits the ball,
and a tap-in scores, cuts to the replay and comes back to a kickoff. The driving ones press a real
key, because the `HumanDriver` reads the buttons and that is the only way to prove that path.

Each of those rebuilds the demo and sits through a three second countdown, which is why there are
six of them rather than twenty, and why the suite takes about a minute rather than twenty seconds.
Run just them while working on the demo:

```powershell
& 'C:\Godot\godot.exe' --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://addons/gta/tests -gprefix=test_rocket_league_demo -gexit
```

One thing to know if you write more of them: headless Godot has seen no keyboard, so it reports its
input device as touch and a car resolves the gamepad binding for every action. The tests set
`input_type` to `KEYBOARD_MOUSE` before pressing anything.

### Filming a test run

The demo tests drive a real match, so they are worth watching rather than only reading. Godot's
Movie Maker mode records them, which needs a rendering window and so cannot be combined with
`--headless`:

```powershell
& 'C:\Godot\godot.exe' --path . --write-movie tests.avi -s addons/gut/gut_cmdln.gd `
  -gdir=res://addons/gta/tests -gprefix=test_rocket_league_demo -gcompact_mode -gopacity=80 -gexit
ffmpeg -i tests.avi -c:v libx264 -crf 26 -pix_fmt yuv420p tests.mp4
```

`-gcompact_mode` shrinks the runner to a corner panel, which otherwise covers half the pitch, and
`-gopacity` fades it. Movie Maker fixes the frame rate and advances time a frame at a time rather
than in real time, so the recording is of the simulation and not of how fast the machine happened to
be; the whole file comes out around 48 seconds. The `.avi` it writes is uncompressed-ish and
enormous, about 130 MB for that, which is what the ffmpeg line is for.

---

## Assets

| Folder | Source | License |
|---|---|---|
| `assets/libertycity/2024_Honda_CRV/` | Honda CR-V model | Not recorded - fill in |
| `assets/cgtrader/honda_crv/` | Wheel | Not recorded - fill in |
| `assets/gravitysound/Car Sound Effects/` | [Gravity Sound](https://gravity-sound.itch.io/car-sound-effects) | Not recorded - fill in |
| `materials/burned.tres` | Made for this addon | CC0 |

---

## License

MIT, see the repository LICENSE.
