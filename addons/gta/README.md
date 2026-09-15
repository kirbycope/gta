![Preview](./assets/gta.png)

# Godot Tim's Automobile (GTA) for Godot 4.8+

Driving for the [3D Player Controller](../3d_player_controller/README.md): one rideable chassis and four
cars built on it, each with handling of its own.

`Vehicle` is the chassis, and it is deliberately small. It holds the wheels, the rideable contract the
controller's `Riding` state expects, and the multiplayer hand-off that moves a car to whoever is driving it.
It holds no handling model at all, because how a car feels is the whole of what makes it that car.

| Car | Scene | What it drives like |
|---|---|---|
| `GtaCar` | `gta/scenes/honda_crv.tscn` | A road car. Five-gear transmission, traction curve, drive and brake bias, handbrake slides, counter-steer assist, drag, downforce, anti-roll bars, RPM-driven engine audio, flip / burn / explode damage, first-person look and a speedometer. |
| `RlCar` | `rl/scenes/rl_car.tscn` | A Rocket League battle car. Boost, jumps, flips, aerials, wall driving and demolitions, every figure taken from a published source. |
| `TwCar` | `tw/scenes/tw_car.tscn` | A Twisted Metal 2 car. Arcade throttle to the car's published top speed, turbo to its published turbo speed, and a wreck state when its armour runs out. |
| `MkCar` | `mk/scenes/mk_kart.tscn` | A Mario Kart 64 kart. The game's own ten band acceleration curve, a hop into a drift, the mini turbo it pays out, and items. |

The Player lends its body and its input through the controller's `Riding` state, which plays the enter and
exit clips a car names, makes its camera current and turns the driver's collision off for the seat. No car
touches Player flags or Player UI.

> [!NOTE]
> Requires `addons/3d_player_controller` (the `Player`, its `Riding` state, the `EnteringCar` / `Driving` / `ExitingCar` animation clips in `player.tscn`, and `PlayerSettingsResource` for the SFX volume) and, through it, [`addons/controls`](https://github.com/kirbycope/godot-controls), which is where `ActionPrompt` and the on-screen button hints live. The car scripts and `VehicleCamera` register their class names on their own; enabling the plugin only adds `GtaCar`, `TwCar`, `RlCar` and `MkCar` to the Create New Node dialog. The `Vehicle` base is not registered, because a bare chassis is not a car.

---

---

## The four demos

Each drives like the game it comes from, and each has its own folder and its own README.

| Demo | Folder | Read |
|---|---|---|
| The road car | `gta/` | [gta/README.md](./gta/README.md) |
| Twisted Metal | `tw/` | [tw/README.md](./tw/README.md) |
| Rocket League | `rl/` | [rl/README.md](./rl/README.md) |
| Mario Kart | `mk/` | [mk/README.md](./mk/README.md) |

What stays here is what all four share: the `Vehicle` chassis, `VehicleCamera`, `HumanDriver`,
`CarControls` and `DrivingUi`, in `scripts/` and `scenes/`, with their tests in `tests/`.

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
instant, and both `RlCar` and `TwCar` have one. It is wrong for a car whose get-in clip is authored to
start at the kerb and walk the driver in, because they would play that walk from inside the seat. `GtaCar`
is that car: it has no `Seat` node at all and seats its driver itself in `ride()`.

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
| `test_twisted_metal_demo.gd` | The Twisted Metal demo whole: the arena is a node in the scene with geometry and collision, every roster car with a model has a scene of its own, seven spawn from those scenes with a person on Roadkill, and each car's materials are editable resources drawn on both sides. |

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
| `gta/assets/libertycity/2024_Honda_CRV/` | Honda CR-V model | Not recorded - fill in |
| `gta/assets/cgtrader/honda_crv/` | Wheel | Not recorded - fill in |
| `assets/gravitysound/Car Sound Effects/` | [Gravity Sound](https://gravity-sound.itch.io/car-sound-effects) | Not recorded - fill in |
| `materials/burned.tres` | Made for this addon | CC0 |
| `mk/scenes/mk_kart.tscn`, `mk/scenes/sunset_circuit.tscn` | Made for this addon | CC0 |
| `mk/assets/` | Built from your own ROM by `tools/extract_mk64.py`, git-ignored | Not redistributed |

---

## License

MIT, see the repository LICENSE.
