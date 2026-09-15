# Rocket League

A Rocket League battle car with boost, jumps, flips, aerials, wall driving and demolitions,
on a full size soccar pitch with AI opponents and goal replays. Every figure is taken from a
published source rather than tuned by feel.

Part of [Godot Tim's Automobile](../README.md), which holds the shared `Vehicle`
chassis this is built on.

---

A second demo built on the same `Vehicle` chassis, and a much bigger departure from it than the
Twisted Metal one. Open **`res://addons/gta/rl/scenes/demo.tscn`**: a three a side match
on a full size soccar pitch, five AI cars, a five minute clock, goal replays and overtime.

There is no `Player` in this demo, the same as the Twisted Metal one. You are a `HumanDriver` under
a blue car, filling the same pad the five brains fill, and there is nothing to get out of. The car is
put on its kickoff spot after every goal and you are simply still at its wheel.

## Controls

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

## Ball cam

On by default, the way Rocket League opens every kickoff, and toggled with `Q`. It is not a separate
camera: `VehicleCamera` gained an optional `look_target`, and ball cam is that pointed at the ball.

The trick is that aiming the pivot along the line to the target is what puts the car between the
camera and the ball, because the spring arm hangs off the back of the pivot. So one line decides
where the camera sits and where it looks, and the tilt follows the ball into the air up to a
configurable limit. With `look_target` left null it is the ordinary chase camera it always was, so
the Honda CR-V and Twisted Metal demos are untouched, and anything else that wants a camera locked
onto something can have one.

## The chassis is shared, the handling is not

`RlCar` sits on `Vehicle`, the same chassis the road car and the Twisted Metal car sit on. The
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

## Where the numbers come from

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

What could not be sourced is listed in `RlConst.UNSOURCED` rather than invented: the suspension
figures in Godot's own units, the wheel friction, the match clock, the AI's thresholds and the
camera settings. The field of view is Rocket League's 110; the camera is further back and higher
than the game's, because this is an untextured blockout with nothing to judge distance against.

## The pitch

`RlArena` builds it from those same constants as a `@tool` script, so it is there in the editor
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

## The AI

`RlAi` is built the way `TwAi` is: it never touches the handling model, it fills a virtual
control pad and hands it to `RlCar.set_rocket_input` once a physics frame. It has the same seven
inputs a person has and no others, so it cannot steer harder or see further than the car it is in.

Three roles are shared out among a team every frame on distance rather than fixed: whoever can reach
the ball soonest attacks, whoever is furthest back defends, anyone left over holds the middle and
keeps their tank full. It aims from behind the ball along the line back from the goal, so a hit goes
somewhere rather than wherever the car happened to be pointing, and it leans on `RlBall.predict`
to work out where the ball will be. That prediction steps the ball forward under gravity and drag
and bounces it off six flat planes; it ignores the rounded corners and every car, so it is a guide
rather than a guarantee.

## Replays and resets

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

## Changing the match

Everything worth changing is exported on the `RocketLeague` node: `team_size` (three a side by
default, anything from one to five), `match_minutes`, `ai_skill` from zero to one, and `seat_player`,
which turns the whole thing into an AI match to watch. `RlCar` exports `starts_in_ball_cam` and
every action name, and `VehicleCamera` exports the lock-on's tilt limit.

## Known rough edges

- The cars and the pitch are an untextured blockout. The car is an Octane sized box at the published
  hitbox of 120.507 by 86.6994 by 38.6591 uu, not a model.
- The sound is the addon's own Gravity Sound car effects put to new use: an engine loop pitched by
  speed for boost, an engine start for the jump, a crash for impacts. They are placeholders that
  happen to be licensed and already here. A boost whoosh, a goal horn and a ball hit want real
  sounds.
- Godot's `VehicleWheel3D` has one grip scalar where Rocket League has separate lateral and
  longitudinal friction curves with their own handbrake factors, and it does not report its wheel
  contact normals, so the surface under a car is found with one ray from the chassis instead of
  averaged over four wheels. Both are in `RlConst.UNSOURCED`.
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
