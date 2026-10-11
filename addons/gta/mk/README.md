# Mario Kart

A kart with Mario Kart 64's own ten band acceleration curve, its hop into a drift and the
mini turbo it pays out, racing three laps against seven computer drivers who brake for the
corners and throw things at each other.

Part of [Godot Tim's Automobile](../README.md), which holds the shared `Vehicle`
chassis this is built on.

---

The third battle demo, and the only racing one. Eight karts, three laps, item boxes, drifting for a
mini turbo, and seven computer drivers who brake for the corners and throw things at each other.

Open `addons/gta/mk/scenes/demo.tscn` and press play.

## Controls

| Action | Keyboard | Pad |
|---|---|---|
| Steer | A / D | Left stick |
| Accelerate | Space | Right trigger |
| Brake, and with S held at a standstill, reverse | Shift | Left trigger |
| Hop, and over 20 km/h a drift | Q | Left bumper |
| Use the item you are holding | T | Right bumper |
| Camera | Mouse | Right stick |

## How it drives

A kart is not a car with the gearbox taken out, and `MkCar` is not built on a wheel of any kind.
Mario Kart 64's kart is a point with a facing, moved by one line a frame, and that line is what
`mk_car.gd` runs, in the game's own thirtieths of a second:

```
v += (force * facing + gravity + lateral - v * 0.12 * 5800) / 6000
```

Everything the game feels like is in that line. The drag term and the divisor give the velocity an
8.6 frame lag behind the facing: turn the nose and the kart goes on the way it was going for a third
of a second, which is the slide; stop turning and it settles. The kart settles where the force
balances the drag, 70.6 km/h at 150cc, and every number that decides the force and the facing is in
`MkConst` with the line of the decompilation it came from.

**The throttle fills a number.** With A held, `player_accelerate_alternative` adds the character's
ten band table to `currentSpeed` once a frame, 2.0 a frame for a standard kart through the low bands
and 0.4 through the last, so 0 to a 150cc top of 320 takes 323 frames, nearly eleven seconds, most of
it in the last bands; the force is `currentSpeed` squared over 25. A computer's kart runs the CPU path, `player_accelerate`, which scales the table by 3.2, and that
gap is the game's rubber band. Off the throttle the number loses 1.0 a frame; B takes 1.2, 2.5 once the
brake slide has counted up, and 4.0 under 20 km/h.

**The force is cut by the turn, the surface and the slope** (`func_80030150`). Every degree the kart
slides costs a hundredth of the force while steering and only 0.004 while drifting, which is why a
drift is faster than a steered corner; each tyre on grass costs 0.09 (0.03 for one of them), so four
on grass is thirty percent gone; a slope costs 0.026 over 3 per degree; under 20 km/h the kart is given
a fifth more.

**Steering turns the facing, and only the facing** (`func_80033AE0`). The stick is smoothed through the
game's steering ladder, divided by `8 + currentSpeed / 50`, scaled by a per km/h table and the
character's handling figure, and that is the yaw rate: about 50 degrees a second at top speed with a
full stick, drawn by the velocity lagging the nose, not by a wheel. There is no steering lock.

**The hop is the drift.** R hops the kart (`kart_hop`: 0.93 units a frame with a jerk of 0.03, about
half a metre), and over 20 km/h the hop is a drift at once. The drift lasts while R is held and the
kart is sliding more than six degrees; while it does, the stick can only pick a point between 40 and
53 on the drift's own side, inside or outside, and cannot straighten it.

**The mini turbo is charged by the wiggle, not the hold** (`update_drift_state_counter`). With the
kart sliding one way, the charge counter climbs only while the stick is pushed the other way;
bringing it back after 18 or more frames bumps the charge. Two wiggles and letting go of R pays the
turbo: 580 of force on top of the kart's 4096 for 31 frames, fourteen percent, about 80 km/h. A
mushroom is 400 for 80 frames and goes past the loss. A drift held to the outside at its counter cap
costs 4.0 a frame and halves the integrator's response: the game punishes a held drift.

**Items by rank.** Item boxes fill the slot, and what comes out depends on where you are lying. See
the item odds below for the part of this that could not be shipped.

**The camera is the game's too** (`mk_camera.gd`): 38.5 units behind, 11.6 above, looking 19.2 ahead,
and its yaw chases the kart's by a capped step, 500 units a frame with the stick centred and less
while steering, so the kart turns across the screen before the view comes round; through a drift it
leads the kart by twelve degrees.

## Where the numbers come from

`MkConst` and `MkRoster` are read out of the [mk64
decompilation](https://github.com/n64decomp/mk64) rather than tuned by feel, the same way
`RlConst` is read out of RocketSim. Each constant names the file and symbol it came from, and
`docs/source_review.md` in this repository is the read of the kart code the port was rewritten from.

The unit scale is derived rather than guessed, and it is worth setting out because everything else
rests on it. `func_80030150` converts a kart's speed for the speedometer with `(speed / 18) * 216`,
which is speed times twelve, and the speedometer reads km/h. So one game unit per frame is 12 km/h,
and at the game's 30 fps that makes one game unit a ninth of a metre. Two independent checks agree:
the kart's own collision size of 5.5 units comes out 1.22 m across, which is a real go-kart, and the
game's courses come out the size of real circuits.

What could not be read out of the decompilation is listed in `MkConst.UNSOURCED` rather than
invented, the same way `TwRoster` handles its gaps.

## The item odds

This is the one thing the demo cannot ship, and it says so on screen rather than quietly pretending.

Mario Kart 64 does not roll weighted dice. It keeps a flat hundred entry table for each finishing
position and reads whatever sits at the index its rolling counter lands on, so the odds for a
position are that table. `MkItems.draw` reproduces that exactly, rolling index and all. The tables
themselves are not in the decompilation: it names the symbol
`common_grand_prix_human_item_curve` but never defines it, because the data is reached through a
segment pointer and lives in the ROM.

`tools/extract_mk64.py` reads them out of a ROM you own:

```powershell
python tools/extract_mk64.py "Mario Kart 64 (U) [!].z64"
```

It verifies the ROM against the three builds the decompilation supports, searches for the tables both
in the clear and inside every MIO0 block, and writes `addons/gta/mk/assets/item_curves.tres`
if it finds them. On the US ROM it does not: the tables are not stored in the clear, and matching the
decomp's own published course vertices against the ROM the same way also finds nothing, so both sit
behind the game's segment scheme rather than being addressable directly. The script reports that and
writes nothing rather than inventing a table. Until it finds one, the demo draws from a clearly
marked even spread and the HUD says so.

## The course is one path

`addons/gta/mk/scenes/sunset_circuit.tscn` is the addon's own circuit, not a converted one. It is a
919 m lap built around a single `Path3D`: the road, kerbs and walls are one `CSGPolygon3D` extruded
along it, and that same path is the racing line the computer drivers follow and the ruler the lap
counting measures against. Drag a point of it in the editor and all three move together.

Two things about it are load bearing rather than decorative, and both were learned the hard way:

- **The minimum curve radius is 37 m against a 7 m road half width.** A polygon extruded along a path
  folds itself inside out wherever the path bends tighter than the profile is wide, and the resulting
  collision throws anything resting on it. A hand placed hairpin here once came to an 8.2 m radius and
  launched the entire grid on the first physics frame. The course is generated from a parametric
  centre line with the radius checked, rather than placed by eye.
- **A CSG road does not have its collision on the first frame.** `MkRace` holds the karts frozen
  until a ray through the grid finds ground. Karts released into that window fall into the road slab
  and are flung out of it when the collision appears.

The karts, the start grid and every item box are nodes placed in the demo scene, so all of them can
be selected and moved in the editor, and each kart's livery is a material on the kart you can edit in
the inspector.

## The computer drivers

`MkAi` fills the same virtual pad a person does, the way `RlAi` and `TwAi` do. It follows
the racing line by aiming a little way up it, and the lookahead grows with speed. It also brakes for
corners: it measures the tightest radius within the next 45 m and holds itself to `sqrt(grip * r)`.
Without that it arrived at a 37 m bend needing more than a gravity of lateral grip and slid into the
wall, where it wedged for the rest of the race. Pure pursuit steers the line; it does not slow for it.

A trailing kart is pulled toward its ceiling faster, which is the game's catch up. The magnitude is
not ported: the decomp's figure for it lives in an accumulator whose conversion to the units a kart's
speed is kept in is never stated, so only the shape is reproduced and the gap is named.

## Getting stuck, and getting picked up

The real game has Lakitu to fish a kart out of trouble. There is none here, but the need is the same,
so `MkRace` puts back any kart that has been overturned, well off the course, or wedged for a couple
of seconds. The wedge is the one worth knowing about: a kart that slides into a wall at an angle sits
there upright, on the road, inside the course, with its drive force pushing straight into the barrier.
Nothing about where it is says anything is wrong. What gives it away is the kart asking for speed and
not getting any, and that is what is tested for.

## Using your own karts, drivers and sounds

The karts here are the addon's own simple shapes. If you would rather race something else, drop it in
and it is picked up the next time the scene runs; take it away and the primitives come back. Nothing
is required, nothing is fetched for you, and nothing you put here is committed: the folder is
git-ignored, the same way the Twisted Metal demo treats the files it builds off your own disc.

```
addons/gta/mk/assets/
  karts/rook.glb          replaces one driver's whole kart, roster key for a name
  karts/default.glb       replaces every kart that has no file of its own
  drivers/rook.glb        replaces just the figure in the seat
  drivers/default.glb
  sounds/engine.ogg       the engine loop
  sounds/boost.ogg        a boost or a mini turbo firing
  sounds/drift.ogg        the drift
```

Every entry is optional and any format Godot imports will do, so a `.glb`, a `.obj` or a `.tscn` are
all fine. The roster keys are `pip`, `fennec`, `sprig`, `rook`, `vesper`, `dozer`, `brack` and `tusk`;
see `MkRoster`.

A replacement kart stands in for the whole stock body, so the boxes and the capsule are hidden rather
than left inside it. A replacement driver stands in for the figure alone, because a kart model that
already has somebody sitting in it does not want a second one.

Two things to know. This chassis drives along **+Z**, so a kart model is expected nose along +Z too;
anything authored the other way round is turned with the kart's `model_yaw_degrees` export rather
than by editing the file. And nothing checks scale or licence: a model that arrives ten times too big
will look ten times too big, and whatever you put in this folder carries whatever terms it came with,
which is the other reason it is not part of the repository.

## Known rough edges

- The item odds are a stand in until a ROM extraction finds the real tables. See above.
- Items are implemented as mechanics rather than as the game's own set piece behaviours: the leader
  shot flies at whoever is winning instead of arcing over the field, and the jolt has no shrinking.
- There is one course, one engine class in practice, and no grand prix around it: no points, no cups
  and no results table between races.
- The computer drivers run the human kart model with the CPU acceleration scaling and the catch-up
  force; the game's own CPU path (`control_cpu_movement`) steers along a baked path and is not ported.
- Walls stop the kart and cost the game's 6 units a frame; the game's own terrain response is not
  ported, and nor is the landing tumble. Another kart is not a wall: a bump between karts is left to
  the physics bodies, because charging the wall deceleration for it stalled the whole field at the
  first corner, and the game's own kart-to-kart response is not ported either.
- No split screen, and nothing here has been driven over a network. The `Vehicle` authority handling
  underneath is intact and the item slot and boxes are written for it, but it has not been played
  with two Steam clients.
- The karts and their drivers are the addon's own simple shapes rather than anything ripped, so this
  looks like a kart racer rather than like Mario Kart. Drop your own models in if you would rather it
  did not; see above.

---
