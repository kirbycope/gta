# Godot Tim's Automobile (GTA) for Godot 4.8+

Driving for the [3D Player Controller](../3d_player_controller/README.md): a rideable `Vehicle` with a GTA V style handling model (traction curve, drive and brake bias, handbrake slides, counter-steer assist, drag, downforce, anti-roll bars), a five-gear transmission with RPM-driven engine audio, flip / burn / explode damage, first-person look, the GTA chase camera and a speedometer. The vehicle owns all of it; the Player lends its body and its input through the controller's `Riding` state, which plays the enter and exit clips the vehicle names, makes its camera current and turns the driver's collision off for the seat. The vehicle touches no Player flags and no Player UI.

> [!NOTE]
> Requires `addons/3d_player_controller` (the `Player`, its `Riding` state, `ActionPrompt`, the `EnteringCar` / `Driving` / `ExitingCar` animation clips in `player.tscn`, and `PlayerSettingsResource` for the SFX volume). `Vehicle` and `VehicleCamera` register their class names on their own; enabling the plugin only adds the vehicle to the Create New Node dialog.

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

## How to Use

| Node | Where it goes | Set in the Inspector |
|---|---|---|
| `Vehicle` (instance `scenes/honda_crv.tscn`, or the script on your own `VehicleBody3D`) | In your level, on the ground | The handling exports (`max_acceleration_force`, `drive_bias_front`, `traction_curve_*`, `max_steering_angle`, ...), `wheels`, the drive action exports; children `DriverSeat`, `EnterCar`, optional `ExitCar` markers, `PlayerDetection` area, the engine `AudioStreamPlayer3D`s, `FirstPersonCamera`, `VehicleCamera` (instance `scenes/vehicle_camera.tscn`) and `DrivingUI` (instance `scenes/driving_ui.tscn` with `vehicle` set) |
| Damage effects (optional) | A scene that inherits the car and adds them | Children named `Fire_05` (with a `FireSFX` player) and `VFXGroundExplosion_01` (with an `ExplosionSFX` player); without them the car still flips and locks up but never burns. The host project's `scenes/honda_crv.tscn` is that inherited scene. |

Standing in `PlayerDetection` shows the prompt (`ActionPrompt.show_for(player, "Get In")`); Action calls `Player.mount(vehicle)`. The `Riding` state calls back `mount(player)`, which puts the Player at `EnterCar` and starts the chase camera, then plays `mount_animation` (`EnteringCar`) and, once it ends, calls `ride(player, delta)` every physics frame: the car seats the Player on `DriverSeat`, reads accelerate / brake / handbrake / steer from its own action exports (resolved for the `input_type` the state keeps current) and feeds its drivetrain. `camera` is the `VehicleCamera` (a spring arm behind the car that follows the direction of travel once it moves, or the facing at rest, with manual look that holds for a moment); the state makes it current and hands the Player's own back on dismount. The exit action in `ride_input` calls `player.dismount()`: at rest the state plays `dismount_animation` (`ExitingCar`) first, above `BAIL_OUT_SPEED` the car calls `dismount(true)` and the Player is straight out. `blocks_hands` holsters weapons and hides the crosshair, `disables_collision` turns the driver's collision shape off inside the body, and `get_contextual_controls(input_type)` names the labels (`"joypad_button_0": "Exit"`).

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
