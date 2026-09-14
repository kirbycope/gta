![Preview](./assets/gta.png)

# Godot Tim's Automobile (GTA) for Godot 4.8+

Driving for the [3D Player Controller](../3d_player_controller/README.md): a rideable `Vehicle` with a GTA V style handling model (traction curve, drive and brake bias, handbrake slides, counter-steer assist, drag, downforce, anti-roll bars), a five-gear transmission with RPM-driven engine audio, flip / burn / explode damage, first-person look, the GTA chase camera and a speedometer. The vehicle owns all of it; the Player lends its body and its input through the controller's `Riding` state, which plays the enter and exit clips the vehicle names, makes its camera current and turns the driver's collision off for the seat. The vehicle touches no Player flags and no Player UI.

> [!NOTE]
> Requires `addons/3d_player_controller` (the `Player`, its `Riding` state, the `EnteringCar` / `Driving` / `ExitingCar` animation clips in `player.tscn`, and `PlayerSettingsResource` for the SFX volume) and, through it, [`addons/controls`](https://github.com/kirbycope/godot-controls), which is where `ActionPrompt` and the on-screen button hints live. `Vehicle` and `VehicleCamera` register their class names on their own; enabling the plugin only adds the vehicle to the Create New Node dialog.

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
| `Vehicle` (instance `scenes/honda_crv.tscn`, or the script on your own `VehicleBody3D`) | In your level, on the ground | The handling exports (`max_acceleration_force`, `drive_bias_front`, `traction_curve_*`, `max_steering_angle`, ...), `wheels`, the drive action exports; children `DriverSeat`, `EnterCar`, optional `ExitCar` markers, `PlayerDetection` area, the engine `AudioStreamPlayer3D`s, `FirstPersonCamera`, `VehicleCamera` (instance `scenes/vehicle_camera.tscn`) and `DrivingUI` (instance `scenes/driving_ui.tscn` with `vehicle` set) |
| Damage effects (optional) | A scene that inherits the car and adds them | Children named `Fire_05` (with a `FireSFX` player) and `VFXGroundExplosion_01` (with an `ExplosionSFX` player); without them the car still flips and locks up but never burns. The host project's `scenes/honda_crv.tscn` is that inherited scene. |

Standing in `PlayerDetection` shows the prompt (`ActionPrompt.show_for(player.controls, "Get In")`); Action calls `Player.mount(vehicle)`. The `Riding` state calls back `mount(player)`, which puts the Player at `EnterCar` and starts the chase camera, then plays `mount_animation` (`EnteringCar`) and, once it ends, calls `ride(player, delta)` every physics frame: the car seats the Player on `DriverSeat`, reads accelerate / brake / handbrake / steer from its own action exports (resolved for the `input_type` the state keeps current) and feeds its drivetrain. `camera` is the `VehicleCamera` (a spring arm behind the car that follows the direction of travel once it moves, or the facing at rest, with manual look that holds for a moment); the state makes it current and hands the Player's own back on dismount. The exit action in `ride_input` calls `player.dismount()`: at rest the state plays `dismount_animation` (`ExitingCar`) first, above `BAIL_OUT_SPEED` the car calls `dismount(true)` and the Player is straight out. `blocks_hands` holsters weapons and hides the crosshair, `disables_collision` turns the driver's collision shape off inside the body, and `get_contextual_controls(input_type)` names the labels (`"joypad_button_0": "Exit"`).

### Multiplayer

The body moves on the car's multiplayer authority and `VehicleSynchronizer` carries its transform, velocities, drive state, damage flags, `current_driver_peer_id` and `radio_station` to the other peers. Getting in hands the authority to the driver's peer on every peer (`_set_authority`, an `any_peer` / `call_local` reliable RPC, the shape a rideable hands itself over in) and getting out hands it back to the server; a driver whose peer disconnects hands it back on every peer too. Offline, with no peers, it is a plain `set_multiplayer_authority`. `current_driver_peer_id` is `SERVER_PEER` (1) while nobody drives.

`radio_station` is an `int` the car carries for whatever radio the project gives its riders; the car plays nothing itself. The driver writes it (they hold the authority, so it replicates) and `radio_station_changed(station)` fires on every peer, so each rider's own radio can follow the car's station while they are in it. The host project's `scenes/world.gd` does that with the `radi_ot` addon: the driver's next / previous station actions move the car's station, and every radio in the car tunes to it.

---

## Twisted Metal 2: the Los Angeles level

An optional car combat layer over the same `Vehicle`, and a demo built on Twisted Metal 2's own
Los Angeles arena. Open **`res://addons/gta/scenes/demo/twisted_metal.tscn`**: the level loads with
the Player already at the wheel of Roadkill and six opponents driving the arena and fighting each
other as well as you.

| Node | What it is |
|---|---|
| `CarCombat` (child of a `Vehicle`) | Health, the weapon inventory and firing. `car` is a [`Tm2Roster`](scripts/tm2_roster.gd) key, which is where its health and special timing come from. |
| `AiDriver` (child of a `Vehicle`) | The opponent. Set `waypoints` and `aggression`; `enabled` off leaves the car to a human. |
| `Tm2Waypoints` (resource) | The arena's own AI path, read off the disc. |
| `Tm2Projectile` | One shot in flight. Damage, speed and homing come from the roster. |
| `tm2_car.tscn` | A scene inheriting `honda_crv.tscn` that adds the three above plus fore and aft muzzles. |

The `AiDriver` never touches the handling model. It fills in a virtual control pad and hands it to
`Vehicle.set_drive_input`, which is how Twisted Metal's own `AICarUpdateControlPad` works. The one
change to `vehicle.gd` is `is_ai_driven`: without it the car parks itself, because the drivetrain
only ran for a seated `Player`.

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
- Cars can still flip. The `Vehicle` damage model treats that as a fire and eventually an explosion,
  which is roughly what Twisted Metal does, but it happens more often than it should.
- The fan remake is only half playable. It loads, scales, collides and the cars spawn on it, but the
  sampler finds few waypoints on it and the opponents do not drive it the way they drive the
  extracted arena. It is there for the comparison above rather than as a finished level.


---

## Tests

```powershell
& 'C:\Godot\godot.exe' --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://addons/gta/tests -gexit
```

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
