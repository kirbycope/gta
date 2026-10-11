# Twisted Metal

A Twisted Metal 2 car with arcade handling, a turbo, the game's own pad and a wreck state, fighting a
field of opponents around that game's own Los Angeles arena, textured, converted from the PlayStation
disc. New York is on the disc too and has a scene of its own.

Part of [Godot Tim's Automobile](../README.md), which holds the shared `Vehicle`
chassis this is built on.

---

`TwCar` is a car of its own on the shared chassis, with a combat layer beside it, and a demo built on
Twisted Metal 2's own Los Angeles arena, "Quake Zone Rumble": the flat street course with the Hollywood
sign, the fire pit, the two tunnels with ramps onto their roofs and the generator. Open
**`res://addons/gta/tw/scenes/demo.tscn`**: the level loads with you already at the wheel of Roadkill
and six opponents driving the arena and fighting each other as well as you. There is no `Player` in
this demo and nothing to get out of. **`scenes/new_york.tscn`** is the same demo on New York, "The Big
Leap", the rooftop level with the edges; until October 2026 that level was in here under Los Angeles's
name, untextured, with a fifth of its geometry missing, and it was what made the demo unplayable.

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

| Action | Keyboard | Gamepad | Twisted Metal 2 |
|---|---|---|---|
| Accelerate | `Space` | X | Square, or D-pad up |
| Brake, then reverse | `Shift` | B | Circle |
| Steer | `A` / `D` | Left Stick | D-pad |
| Hard turn, with the stick | `Ctrl` | A | Cross with the D-pad |
| Turbo | `Q` | Y | Triangle |
| Machine gun, held | Left click | Right Trigger | R2 |
| Fire the pickup | Right click | Left Trigger | L2 |
| Next pickup | `T` | Right Bumper, Left Bumper | R1, L1 |
| Get out (a seated Player only) | `E` | D-pad down | |

The pad is the game's own standard layout, from the manual and the Prima guide, button for button
by position: the PlayStation's left face button is X, its right is B, top is Y, bottom is A. The
Advanced Attacks, D-pad sequences on an energy bar (freeze, napalm, jump, shield, mines, rear fire,
invisibility), are not here.

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

The turbo is the manual's: "instant acceleration to top speed for as long as you hold the Turbo button",
so the button puts a car under its top speed at its top speed at once, and holding it pushes on to the
published turbo speed whether or not the throttle is down. The meter refills on its own over time, which
is what the real one does; the real game also drops turbo pickups in its arenas, and this demo has no
pickups of any kind, so that half is missing rather than wrong.

Twisted Metal's cars come down on their wheels. With fewer than four wheels down the car is turned back
toward level, and one on its roof is rolled over about its nose; the rate is a judgement and is listed
with the other ones.

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
python tools/extract_tm2.py "Twisted Metal 2 (USA) (SCUS-94306).iso" --level FREEWAY   # Los Angeles
python tools/extract_tm2.py "Twisted Metal 2 (USA) (SCUS-94306).iso" --level ROOF      # New York
python tools/extract_tm2.py tm2.iso --all                                              # every level
python tools/extract_tm2.py tm2.iso --level FREEWAY --pages pages/                     # and its texture pages as PNGs
```

It reads the ISO9660 filesystem off the disc image (a 2048-byte `.iso`, or a raw 2352-byte `.bin` in
MODE1 or MODE2 form 1), decodes the level's `.DMD` model database and its `.TMS` texture bank into a
glTF with the textures embedded and the game's own vertex colours on top, and turns the level's `.PTS`
terrain file into the `TwWaypoints` the opponents drive along. The PC release keeps the same data as
`/LEVELDB/*.DPC` with no texture bank beside it, and that path still works, untextured. The demo scene
loads all of it at run time and says so on screen if it is missing, so the project still opens in a
checkout that has none of it. The level itself is a node in each demo scene, `Arena`, an instance of
the glTF at its scale, so it is there to look at in the editor; the script only strips the painted
backdrop, adds collision to a level that has none, and measures where out of the world is. The cars
are spawned in the game rather than placed, because their spawn points are found by dropping rays onto
the arena's collision and passing over any point with something standing on it, but each is spawned
from its own scene under `scenes/tm2/`, which is where its model and materials live.

The disc's level keys, against the game's own level table (read out of the executable by the
TwistedMetal2Recomp project): `FREEWAY` is Los Angeles: Quake Zone Rumble, `ROOF` is New York: The
Big Leap, `SROOF` Los Angeles: Roof Tops (the split-screen level), `BURB` Los Angeles: Cyburbia, `DISH`
Moscow, `PARIS` Paris, `ISLANDS` Amazonia, `GLACIER` Antarctica, `DEN` Holland, `HKONG` Hong Kong and
`SWAMP` the Jet Moto track the game hides in its ninth slot. The extractor used to map `ROOF` to
"los_angeles", which is how New York came to be driven under the wrong name.

The glTF is dealt out across meshes of two hundred materials, because Godot caps a mesh at 256
surfaces and silently drops the rest on import. The drawn chunks carry no collision of their own.
What a car drives on is two collision-only nodes beside them (Godot's `-colonly` hint): the level's
drivable faces, which is every face a car can stand on or run into (mostly-level faces over a square
metre, walls over eight, no slivers, and nothing from the small free-standing meshes that are the
pickups, signs and debris, which in the game are not solid), and a set of skirts, a vertical wall
dropped from every edge of a raised flat face that no other face shares, down to four metres below
the streets. The skirts are there because the drawn Los Angeles has gaps round the plateau where its
kerbs would be: the original game's ground is a height lookup from the level's TERRAIN tables (below),
not the drawn polygons, so its cars never fell through them, and the lookup does not land on the drawn
surface closely enough to be used here. The demo adds an invisible floor at street level under
everything for the same reason. All of that is extraction policy, named as such in
`tools/extract_tm2.py`, and none of it is the game's.

The car models are a separate job: `tools/tm2/cars.py` rescales the ripped `.obj` models, which come
at wildly different sizes, to a common 4.5 m length and sits them on the ground.

## What the format turned out to be

Documented in `tools/tm2/dmd.py` and `tools/tm2/tms.py`, reverse engineered from the retail data
against the Twisted Metal 1 decompilation's `db.h` node structs (TM1 and TM2 are the same SingleTrac
engine) and the Unity viewer in aybe's Twisted repository.

A `.DMD` (`DXSP`, version 0x43) is the PC `.DPC` (`DCPMC`) under another magic: a tree of nodes with
absolute pointers based at `0x80019c40`, the PlayStation address the database loads at. The header
names a root table (six roots in Los Angeles, eight in New York) and every node's first byte is an
opcode choosing its layout: plain lists of children, a translation node, a matrix node, and a TM2-only
opcode 12 that is a flat list of distinct objects. Two of the layouts differ from TM1 by sixteen
bytes. Meshes under a translation or matrix node are local to it, so the rotation (a PlayStation
`MATRIX`, nine `int16`s over 4096) and the summed translation are applied, and the tree instances
geometry: one ground tile is referenced from ten placement nodes across Los Angeles, so the walk is
keyed by node and transform rather than by node, or the floor is written once and the rest of the
arena is a hole, which is what the first read of this format did. A mesh node is keyed `0x0000ff00`
and is only genuine when its polygon pointer equals its own address plus `0x2c`, and whole sub-trees
are not reachable from the root table at all (the game finds them from code), so a signature scan
picks those up as well; among them are the frames of animated billboards, slivers with one corner on
their own origin and another thousands of units away whose real corners the game writes at run time,
and those are left out. Vertices are PlayStation `SVECTOR`s, three `int16`s and two bytes of padding,
Z up where Godot is Y up.

A polygon record is `kind, colour count, size in dwords, GPU primitive size`, four vertex indices,
then the colours with the PlayStation GPU command code in the fourth byte (`0x24` to `0x3c`: bit 3
quad, bit 4 gouraud, bit 2 textured), then for a textured face a `u, v, clut or tpage` word per vertex
exactly as `POLY_FT4` lays them out, then an optional texture-window word. The old reader accepted
only flat textured faces and dropped the whole block the moment it met a gouraud or an untextured
record, which is where the missing fifth of the geometry went; decoding by the command code parses
every block of both levels. Quads are in PlayStation strip order (0 1 / 2 3), which the UVs prove.

A `.TMS` (`TXSP`) is a bank of standard TIMs with a table of ids in front. They are blitted into a
1024 by 512 halfword VRAM and the faces address it the GPU's way: the tpage word gives the page's
column, row and bit depth, the clut word the palette's position, 15-bit BGR with zero transparent, and
the texture window word repeats a region. A page spans many TIMs with different palettes, so each
material is one page, palette and window, cropped to the texels its faces use; Los Angeles has 369 of
them in 420 KB.

The `TERRAIN` files beside the waypoints are the same size for every level, so they are fixed tables
the game queries by position rather than a mesh. `.GRP` is thirty-five axis-aligned rectangles with a
height each (Los Angeles fills twenty, at 0, 3.75 and 5.25 m: the street, the plateau and its upper
step, the last one the whole level at a default); `.RMP` is up to 225 patches of 28 bytes, a corner,
a size, a direction and four corner heights, the inner arena's drivable patches with their slopes.
They give the original a hole-free ground function, but checked against the drawn level the patch
heights land within a quarter of a metre at fewer than half the corners, with no constant offset, so
they are read (`tools/tm2/terrain.py`) and not used.

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
- Props the game places from code (pickups, debris, the frames of animated things) are not in the
  level tree; the ones found within 500 units of the origin and under 1200 across are left out rather
  than piled at the arena's centre, and a few sprite strips still stand where their data put them.
  The fire pit's flames are among the animated billboards left out, so the pit does not burn. Faces
  the game draws semi-transparent are drawn opaque or cut out. The level's materials are lit, though
  the vertex colours already carry the game's baked lighting.
- There are no pickups to collect, so the weapon bay fills only from what the AI never drops; the
  machine gun is the whole of the player's armament until pickups exist.
- The arena's outer fence is not in the drawn data. A car further than 120 m from the AI path is
  treated as having left the arena and put back on it, which is the port's fence.
- New York is two tiers, rooftops and the street far below. Opponents feel for the edge with
  raycasts and turn away, but they still go over sometimes, and a car that ends up on the wrong tier
  has no route back. Anything that leaves the world entirely is put back on the roof.
- The opponents are not good drivers. On Los Angeles a field of six averages four to five metres a
  second over a minute and a half with a quarter of its time stopped against a kerb or a wall,
  measured with every car under its brain; a car that asks for speed and gets none for six seconds
  is put back on the course the way a car that fell out is, which is what keeps the round moving.
  Their waypoint ring is the game's own and runs out onto the streets round the plateau, where the
  drawn kerbs are steps and the slopes between tiers are missing on three sides, so that is where
  they wedge. On New York they also drop to a tier they cannot climb out of.
- The chassis collision is a box the length of the wheelbase, raised so that a bottomed suspension
  cannot put the belly on the ground: a car that landed from the plateau's edge used to beach itself
  on the street and sit there on four wheels at full throttle.
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
