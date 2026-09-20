# Twisted Metal

A Twisted Metal 2 car with arcade handling, a turbo and a wreck state, fighting a field of
opponents around that game's own Los Angeles arena converted from the disc.

Part of [Godot Tim's Automobile](../README.md), which holds the shared `Vehicle`
chassis this is built on.

---

`TwCar` is a car of its own on the shared chassis, with a combat layer beside it, and a demo built on
Twisted Metal 2's own Los Angeles arena. Open **`res://addons/gta/tw/scenes/demo.tscn`**: the
level loads with you already at the wheel of Roadkill and six opponents driving the arena and
fighting each other as well as you. There is no `Player` in this demo and nothing to get out of.

| Node | What it is |
|---|---|
| `TwCar` (`scenes/tm2_car.tscn`) | The car: arcade handling, a turbo and a wreck state. `car` is a [`TwRoster`](scripts/tm2_roster.gd) key, which is where its top and turbo speeds come from. |
| `scenes/tm2/<car>.tscn` | One scene per ripped car, inheriting `tm2_car.tscn`: its mesh under `Model/Mesh` and a material per surface embedded in the scene. Open one to change how that car looks. |
| `Arena` (in each demo scene) | The level, an instance of its glTF placed as a node so it can be seen and selected in the editor. The demo script prepares it; it does not build it. |
| `TwCombat` (child of a `TwCar`) | Health, the weapon inventory and firing. Its own `car` key is where its health and special timing come from. |
| `TwAi` (child of a `TwCar`) | The opponent. Set `waypoints` and `aggression`; `enabled` off leaves the car to a human. |
| `HumanDriver` (child of a `TwCar`) | You. Fills the same pad from the keyboard or a joypad; the demo puts one under Roadkill. |
| `CarControls` (`scenes/car_controls.tscn`) | The on-screen controls, and only the car's. Registers the actions the car reads; shown or hidden by the player's HUD setting, so a desktop draws none. |
| `TwUi` (`scenes/tm2_ui.tscn`) | Armour, the selected weapon and the turbo meter. It reads nothing: every number arrives on a signal. |
| `TwWaypoints` (resource) | The arena's own AI path, read off the disc. |
| `TwProjectile` | One shot in flight. Damage, speed and homing come from the roster. |

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Accelerate | `Space` | Right Trigger |
| Brake, then reverse | `Shift` | Left Trigger |
| Steer | `A` / `D` | Left Stick |
| Turbo | `Q` | Left Bumper |
| Get out | Action | A |

Twisted Metal 2 puts turbo on Triangle. This addon's action set has no Triangle and brake already has
shift, so turbo sits on the spare `ability` action instead.

## How it drives

Twisted Metal is not a driving game with weapons bolted on, it is a shooter where the floor moves. Its cars
turn as hard flat out as they do at a crawl and reach their top speed almost at once, so `TwCar` has no
gearbox, no traction curve and no speed-sensitive steering. What it has is a constant drive force, a
ceiling, and a turbo that raises the ceiling.

Both ceilings are published: `TwRoster` carries every car's real top speed and turbo speed off the
community stat tables, so Minion out-runs Roadkill here because it does in the game. Everything else, the
force that gets a car there, the brake, the reverse speed, the steering lock and both turbo rates, has no
published figure anywhere. Each one is an export with a comment saying so, and each is named in
`TwRoster.UNSOURCED` rather than dressed up as a fact.

The turbo meter refills on its own over time, which is what the real one does; the real game also drops
turbo pickups in its arenas, and this demo has no pickups of any kind, so that half is missing rather than
wrong.

When `TwCombat` runs a car's armour out, its `died` signal is wired in the scene to `TwCar.on_died` and
the car stops answering the controls and rolls to a stop. There is no fire and no explosion: that was the
road car's damage model and it does not come with the chassis.

## Which way is forward

This chassis drives along **+Z**, not Godot's usual -Z, and that was measured rather than assumed: an
opponent rolling on four wheels in the arena travels along its own `basis.z` with a mean dot product of
0.99 over fifty samples. `TwCar.forward()` is the single place it is written down, and the model, the
seat, the camera, the AI's edge feelers, its firing cone and both muzzles all read it from there.

Getting that wrong is quiet rather than loud, and it had been wrong. The forward muzzle sat on the tail of
the car and fired out of the back, the rear muzzle sat on the nose, and the AI felt for the edge of the roof
behind itself and steered to put its waypoint over its shoulder. Fixing the sign is most of why the
opponents now drive the arena instead of falling off it.

The `TwAi` still never touches the handling model. It fills in a virtual control pad and hands it to
`TwCar.set_drive_input`, which is how Twisted Metal's own `AICarUpdateControlPad` works. It has the same
four inputs a person has and no others.

## Where the behaviour comes from

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
sourced is listed in `TwRoster.UNSOURCED` rather than invented.

## Building the assets

The converted level and cars are committed under `addons/gta/tw/assets/`. The material is
Sony's and SingleTrac's, so it is here on the understanding that it is not ours to license; only the
raw files pulled off the disc are git-ignored, because the extractor rebuilds those on demand. To
build them again, or to add another level, point it at your own copy of the game:

```powershell
python tools/extract_tm2.py "Twisted Metal 2 (USA) (Track 01).bin"
python tools/extract_tm2.py tm2.iso --all          # every level on the disc
```

It reads the ISO9660 filesystem off the disc image, decodes the `.DPC` model database into a glTF
with the game's own vertex colours, and turns the level's `.PTS` terrain file into the `TwWaypoints`
the opponents drive along. The demo scene loads all of it at run time and says so on screen if it is
missing, so the project still opens in a checkout that has none of it. The level itself is a node in
each demo scene, `Arena`, an instance of the glTF at its scale, so it is there to look at in the editor;
the script only strips the painted backdrop, adds collision to a level that has none, and measures where
out of the world is. The cars are spawned in the game rather than placed, because their spawn points are
found by dropping rays onto the arena's collision, but each is spawned from its own scene under
`scenes/tm2/`, which is where its model and materials live.

Twelve levels are on the disc. `ROOF` is Los Angeles, the "Quake Zone Rumble" rooftop arena;
`SROOF` is the cut-down split-screen copy of it, as `HKONG` is of `HONGKONG`.

The car models are a separate job: `tools/tm2/cars.py` rescales the ripped `.obj` models, which come
at wildly different sizes, to a common 4.5 m length and sits them on the ground.

## What the format turned out to be

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

## Known rough edges

- The ripped car models are wound mostly inside out: between 64 and 86 percent of each car's
  triangles face into the car, measured across the seven in the demo. With back-face culling that
  reads as transparency, and it takes Sweet Tooth's clown head off the roof entirely. Each car's
  scene under `scenes/tm2/` carries a material per surface with culling off, so both sides draw; the
  material is yours to change in the inspector if a car wants something else.
- Outlaw and Shadow are in the roster with no ripped model in the assets, so they have no scene. The
  demo does not use them; asking for one spawns the bare chassis and says so.
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
