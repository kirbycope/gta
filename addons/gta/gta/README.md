# The road car

A Honda CR-V with GTA V style handling: a five-speed box, traction curves, drive and brake
bias, handbrake slides, counter-steer assist, drag, downforce, anti-roll bars, RPM-driven
engine audio, a damage model and a first-person view. The only demo with a `Player` in it:
you walk up to the car and get in.

Part of [Godot Tim's Automobile](../README.md), which holds the shared `Vehicle`
chassis this is built on.

---

## Interactive Demo Scene

Open and run **`res://addons/gta/gta/scenes/demo.tscn`**: an asphalt lot with a ramp, the Honda CR-V and the Player. Walk to the car and press Action to get in; Space accelerates, Shift brakes, the throw button is the handbrake, F5 goes first-person, Action gets out (straight out at speed, through the door at rest).

| Node | What it is |
|---|---|
| `Lot` (`CSGBox3D`, group `CONCRETE`) | The floor. |
| `Ramp` (`CSGPolygon3D`) | A wedge to jump. |
| `HondaCRV` | `honda_crv.tscn`, nothing to set. |
| `Player` | `player.tscn`, nothing to set. |

---
