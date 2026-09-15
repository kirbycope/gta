# Plan: one Vehicle base, three cars

Written for: the Claude Code session (Opus 5) that will carry this out in `C:\GitHub\gta`, with
the user watching between phases.

## What is being asked

Today the addon has two chassis. `Vehicle` (`scripts/vehicle.gd`) is the GTA road car and carries
everything: the rideable contract, the multiplayer hand-off, a gearbox, a damage model, a radio.
`RocketVehicle` (`scripts/rocket_vehicle.gd`) is a bare rideable chassis split out of it for the
Rocket League car. The Twisted Metal car is neither: `tm2_car.tscn` inherits `honda_crv.tscn`, so
every opponent in Los Angeles is a Honda CR-V with a gun bolted on.

The end state is one base and three cars built on it, each its own script and its own scene:

| Class | File | Scene | What it is |
|---|---|---|---|
| `Vehicle` | `scripts/vehicle.gd` | none (abstract) | The rideable chassis: wheels, the Player contract, the multiplayer hand-off, SFX volume. No handling model. |
| `GtaCar` | `scripts/gta_car.gd` | `scenes/honda_crv.tscn` | Everything that is in `vehicle.gd` today and is not in the base. |
| `RlCar` | `scripts/rocket_car.gd` | `scenes/rocket_car.tscn` | Unchanged, reparented from `RocketVehicle` to `Vehicle`. |
| `TwCar` | `scripts/tm2_car.gd` | `scenes/tm2_car.tscn` | New. An arcade car with turbo, driven to its roster top speed, carrying `TwCombat` and `TwAi`. |

`RocketVehicle` goes away: the base is what it already is, promoted and given the two things
all three cars need that it lacks (the authority hand-off and `set_sfx_volume`).

Class name `Vehicle` stays on the base on purpose. The host project
`godot-3d-player-controller-v3` refers to `Vehicle.SERVER_PEER` and `Vehicle._set_authority`,
and both of those move into the base, so those references keep resolving without a change there.

## Rules that apply to every phase

These come from `C:\GitHub\CLAUDE.md` and the saved memories. Do not skip them.

- Strict static typing on every variable, parameter and return. No emoji anywhere. No em-dashes.
- KISS: low abstraction, short scripts. Do not introduce interfaces, resources or managers this
  plan does not name.
- Favor nodes over code: wire children and signals in `.tscn` files, not in `_ready()`.
- Before any Godot run, list what is already running (`tasklist | findstr /i godot`) and stop the
  old ones except the user's editor (its command line carries `-e --path`). One run at a time.
- Never discard or revert uncommitted changes you did not make. The working tree already holds
  the whole uncommitted Rocket League demo (see `git status`); leave it as it is and add to it.
- After editing any `@tool` script or any `class_name`, the user's open editor has to be
  restarted to pick it up. Say so when it happens.
- Every phase ends with the addon's own suite green and the in-engine check described. Do not
  report a phase done on a partial run.
- Everything here is under `addons/gta/`, which is this repository itself, not a pulled addon.
  `push_addons.py` does not apply here. It does apply at the very end, from the host project.
- Ask the user for sound effects rather than sourcing any. The Gravity Sound car set already in
  the addon is the only sound to reach for, and it is a placeholder when it is used for anything
  but an engine.
- Show the screen: the Twisted Metal phase is visual work, so it ends with several in-engine
  screenshots sent with `SendUserFile`, from different angles, plus a before-and-after pair.

The test command for this repository, run from `C:\GitHub\gta`:

```powershell
& 'C:\Godot\godot.exe' --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://addons/gta/tests -gexit
```

Add `-gprefix=test_gta_car` (or any other prefix) to run one script while working. The full run is
about 80 seconds and 196 tests pass on it today. Run the full suite at each phase gate; the user has
approved this plan, and that is the agreement the "ask before the full suite" rule wants.

## Facts the executor needs and would otherwise have to rediscover

**The rideable contract is duck typed.** `addons/3d_player_controller/scripts/riding.gd` is the
authority. Read its class comment first. It looks for methods `mount`, `dismount`, `ride`,
`ride_input`, `get_contextual_controls` and properties `seat`, `camera`, `blocks_hands`,
`disables_collision`, `mount_animation`, `dismount_animation`, `input_type`. A missing name is a
silent failure to mount, not an error.

**`seat` pins immediately.** `Riding.start()` reads `seat` once and pins the Player to it before
the mount animation plays. That is right for a car with no door (Rocket League, Twisted Metal,
where the driver is hidden anyway). It is wrong for the CR-V: its `EnteringCar` clip is root motion
authored to start at the `EnterCar` marker and walk into `DriverSeat`, and pinning first would play
the clip from inside the seat. So the base declares `seat` as optional
(`get_node_or_null(^"Seat")`), `GtaCar` leaves it null and keeps its own manual seating in `ride()`
exactly as `vehicle.gd` does now, and the doc comment on `GtaCar.ride` says why.

**Which way is forward.** Godot's `VehicleBody3D` drives along +Z with positive engine force in
this addon's scenes: the CR-V's steered wheels sit at z = +1.22, the GTA drivetrain's heading is
`basis.z`, and `RlCar.nose()` is `basis.z` (verified in engine last session, cars drove at
19.8 m/s nose first). Yet `TwAi` steers and feels for edges with `-basis.z`, and `TwProjectile`
flies along `-basis.z` from a `MuzzleForward` placed at z = -2.4. Whether that cancels out today is
not established. Phase 4 settles it in engine before building the new car, gives `TwCar` one
`forward()` helper, and makes the AI, the muzzles and the projectile use it.

**Class name renames and the editor.** Godot caches `class_name` to path in
`.godot/global_script_class_cache.cfg`. Renaming `vehicle.gd` to a base while a `gta_car.gd`
takes its class is two renames that must land in the same edit before any Godot process runs, or
the cache holds two scripts claiming `Vehicle`. Move each script's `.gd.uid` file with it
(`git mv` style, same base name) so scene references by uid do not break. `honda_crv.tscn`
references `res://addons/gta/scripts/vehicle.gd` by path; if that line is not changed to
`gta_car.gd` the CR-V silently becomes a bare base with no drivetrain.

**Headless input is touch.** A headless run reports its input device as touch, so a car resolves
the gamepad binding for every action. Tests that press keys set `car.input_type` (or
`player.controls.current_input_type`) to `Controls.InputType.KEYBOARD_MOUSE` first. Existing tests
show the pattern.

**The host project consumes this addon.** `C:\GitHub\godot-3d-player-controller-v3` pulls
`addons/gta` from this repository through `tools/pull_addons.py`, and its `scenes/honda_crv.tscn`
inherits the addon's `honda_crv.tscn` to add fire and explosion nodes. Its `world.gd` reads
`car.radio_station` and `car.current_driver_peer_id`; its tests use `Vehicle.SERVER_PEER`,
`car.get_contextual_controls`, `car._set_authority`. Phase 6 goes there and proves nothing broke.

## Phase 1: promote the base

Goal: `Vehicle` is the base, `GtaCar` is the road car, nothing else changes behaviour.

1. Rename `scripts/vehicle.gd` to `scripts/gta_car.gd` (and its `.uid`). Change the header to
   `class_name GtaCar` / `extends Vehicle`.
2. Rename `scripts/rocket_vehicle.gd` to `scripts/vehicle.gd` (and its `.uid`). Change the header
   to `class_name Vehicle` / `extends VehicleBody3D`. Rewrite the class comment: it no longer
   explains a split away from the GTA car, it explains what a base chassis is and lists what is
   deliberately not in it (no handling model, no camera behaviour beyond `VehicleCamera`, no HUD).
3. Move into the base, verbatim from `gta_car.gd`, removing them there:
   - `SERVER_PEER`, `current_driver_peer_id`, `set_driver()`, `_hand_authority_to()`, `_grant()`,
     `_set_authority()`, `_on_peer_disconnected()`, and the `multiplayer.peer_disconnected`
     connection in `_ready()`. `set_driver` loses its two GTA lines (`_play_door_sequence()` and
     the first person camera check); `GtaCar.set_driver` overrides, calls `super`, and does those.
   - `vehicle_synchronizer` becomes `@onready var vehicle_synchronizer: MultiplayerSynchronizer =
     get_node_or_null(^"VehicleSynchronizer")`. The Rocket League and Twisted Metal scenes have
     none; `set_multiplayer_authority` is recursive by default, so a synchronizer that is present
     follows without being named.
   - `set_sfx_volume()`, and the `PlayerSettingsResource.load_or_create().sfx_volume` call in
     `_ready()`. `audio.gd` in the player controller calls this on every member of the `vehicles`
     group, and the base is what joins that group.
   - `hides_driver_model` and `_set_driver_model_visible()` are already in the base; delete the GTA
     copies. Keep the GTA doc comment about a model authored nose down +Z; it belongs on the base
     method now.
   - `player`, `input_type`, `blocks_hands`, `disables_collision`, `mount_animation`,
     `dismount_animation`, `_action()`: delete the GTA copies. `GtaCar` sets `mount_animation =
     "EnteringCar"` and `dismount_animation = "ExitingCar"` in the `honda_crv.tscn` root node
     properties (favor nodes) rather than in code. Note the base declares them `@export`, which is
     what makes that possible.
   - The four driving action export pairs are already in the base with the same names. Delete the
     GTA copies. Check the defaults: the base has `keyboard_exit_action = &"whistle"` and
     `pad_exit_action = &"whistle"` where the GTA car had `&"action"` and `&"jump"`. Set the CR-V's
     values in `honda_crv.tscn`, not by changing the base defaults, so the Rocket League car keeps
     its own.
4. The base `seat` becomes `@onready var seat: Node3D = get_node_or_null(^"Seat")`. `GtaCar`
   keeps `driver_seat`, `enter_car`, and its manual seating in `mount()` and `ride()`. Its
   `mount()` and `dismount()` call `super()` first, then do the GTA part (the enter marker, the
   door, the speedometer). Its `ride()` does not call `super()` (the base one is empty).
5. `GtaCar._ready()` calls `super()` then its own remaining setup. Drop `is_ai_driven` from
   `GtaCar` entirely: it existed only so `TwAi` could drive a CR-V, and after Phase 4 nothing
   does. Its removal takes one line out of `set_drive_input` and the README sentence "The one
   change to `vehicle.gd` is `is_ai_driven`".
6. `scenes/honda_crv.tscn`: change the script ext_resource path to `gta_car.gd`; set the action
   and animation exports named above on the root node. Add nothing else.
7. `plugin.gd`: register `GtaCar` (`preload("scripts/gta_car.gd")`) under the name "GtaCar", and
   `RlCar` and `TwCar` too once they exist. The base is abstract and is not registered.
8. `rocket_car.gd`: `extends Vehicle`. Delete the `rocket_vehicle.gd` mentions from its comment.
9. Fix every other reference: `ai_driver.gd`, `car_combat.gd`, `twisted_metal.gd` and the three
   tests that type a car as `Vehicle` and reach for GTA members (`is_ai_driven`,
   `is_driving_this_car`, `_steer`, `set_drive_input`, `is_any_wheel_on_ground`) must type it as
   `GtaCar` for now. This is temporary; Phase 4 retypes them to `TwCar`. `driving_ui.gd`'s
   comment says `[Vehicle]`; make it `[GtaCar]`.
10. `is_any_wheel_on_ground()` on `GtaCar` becomes a one-line wrapper over the base's
    `wheels_in_contact() > 0`, or its callers switch to that. Prefer the switch.

Tests:
- Rename `tests/test_vehicle.gd` to `tests/test_gta_car.gd`. Change its `car: Vehicle` to
  `car: GtaCar`. Move the four authority tests out of it:
  `test_the_driver_takes_the_car_s_authority_and_hands_it_back`,
  `test_the_hand_off_carries_the_driver_s_peer_to_every_copy`,
  `test_a_driver_who_disconnects_hands_the_car_back_to_the_server` and
  `test_a_clients_hand_off_is_a_request_the_server_grants`. The prompt test and the radio test
  stay: the prompt and the radio are the road car's.
- Rename `tests/test_rocket_vehicle.gd` to `tests/test_vehicle.gd` and make it the base's test.
  It keeps what it has (the contract, the wheel helpers, the split from the road car, now phrased
  as "the base carries no handling"), gains the four authority tests moved above, run against the
  Rocket League car since it is the lighter fixture, and gains one test that
  `set_sfx_volume(0.0)` puts every `AudioStreamPlayer3D` on the car at -80 dB. The one assertion
  in the moved tests that reads `car.vehicle_synchronizer` has nothing to read on a car without
  one; keep that single line in `test_gta_car.gd` as its own small test ("the synchronizer changes
  hands with the car") rather than making the base test depend on a synchronizer.
- The `test_the_plain_car_still_shows_its_driver` test in `test_car_combat.gd` instantiates the
  CR-V; move it to `test_gta_car.gd`.

Gate: full suite green at the same count as before plus the new sfx test. Then, through the Godot
MCP server (`run_project` on `scenes/demo/demo.tscn`), walk to the CR-V, get in, drive, get out,
and confirm with `run_script` that `player.riding is GtaCar`, the door animation played, the
speedometer showed and hid, and `car.get_multiplayer_authority()` went to the Player's peer and
back. Then `run_project` on `rocket_league.tscn` and confirm a car is `RlCar` and `is Vehicle`,
and that a goal still scores within a 50 second all-AI run (set `seat_player = false` in the
script call). Tell the user the editor needs a restart because class names changed.

## Phase 2: tidy the road car

Goal: `gta_car.gd` reads as one thing, the GTA handling model, and nothing in it duplicates the
base.

1. Reorder `gta_car.gd` so the file goes: signals, exports (handling, then the door and damage
   constants), state, `@onready` nodes, `_ready`, the rideable overrides, the input and camera
   code, the drivetrain, the damage model, the audio, the prompt. It is 816 lines today; expect
   about 700 after the moves. Do not change any handling number.
2. `GtaCar.get_contextual_controls` stays. The base gains a minimal default (`"joypad_button_0":
   "Exit"` for keyboard, `"joypad_button_3": "Exit"` for a pad, plus the steer and camera sticks)
   so a car that does not override it still labels the exit. Check `RlCar` overrides it
   already (it does) and `GtaCar` does (it does).
3. `initial_spawn_transform`, `freeze` while parked, the flip and fire timers, first person look,
   the door sequence, the radio station and the `PlayerDetection` prompt all stay on `GtaCar`.

Gate: full suite green. No in-engine check beyond Phase 1's, since nothing moved that a test does
not already cover.

## Phase 3: the Rocket League car on the base

Goal: `RlCar` gains the authority hand-off for free and loses nothing.

1. `RlCar.mount()` already calls `super()`; confirm the base `mount` now calls
   `set_driver(rider)` so the driver's peer takes the car, and that `dismount` hands it back.
   `RlMatch._seat_the_player` and `_stand_the_player_down` go through `Player.mount` and
   `Player.dismount`, so nothing there changes.
2. `README.md` (the addon's): rewrite the "The chassis is its own, not the GTA car" section. It
   currently tells the story of `RocketVehicle`; it now says the Rocket League car sits on the same
   `Vehicle` base as the other two and what that base gives it. Keep the paragraph about Bullet's
   raycast vehicle.
3. Delete `scripts/rocket_vehicle.gd` and its `.uid` if Phase 1 left either behind.

Tests: `test_vehicle.gd` (the base test, formerly the rocket vehicle test) already covers this.
Add one test to `test_rocket_match.gd`: after `_seat_the_player`, `player_car.current_driver_peer_id`
equals the Player's authority, and after `_stand_the_player_down` it is `Vehicle.SERVER_PEER`.

Gate: full suite green, and the six `test_rocket_league_demo` integration tests in particular.

## Phase 4: the Twisted Metal car

Goal: `tm2_car.tscn` is its own scene with its own script, and the Los Angeles demo plays on it.

This is the phase with design in it. Decide these before writing code, and write the decisions
into the class comment.

**Forward axis.** Run `twisted_metal.tscn` through the MCP server first, as it is today, and read
off with `run_script` whether an opponent's `linear_velocity` points along `+basis.z` or
`-basis.z` while it drives, and whether its shots leave the front of the model. Record the answer.
Then build `TwCar` so that `forward()` returns whichever axis the wheels actually drive along
(expect `+basis.z`, matching `RlCar.nose()`), place `MuzzleForward` on that side, and change
`TwAi` and `TwProjectile` to use `forward()` rather than `-basis.z`. If the model then faces
backwards, turn the `Model` node, not the physics.

**Handling.** Twisted Metal's is arcade and no numbers for it are published; `TwRoster.UNSOURCED`
already says so. The design is: a constant drive force that reaches the car's published top speed
(`TwRoster.top_speed(car)`), with turbo raising the ceiling to the published turbo speed while a
meter lasts; brake to a stop then reverse; steering lock that does not shrink with speed, because
the original turns on a dime; no gearbox, no traction curve, no anti-roll bars. Every tunable that
is not one of those two published speeds is an `@export` on `TwCar` with a comment saying it is a
judgement, and `TwRoster.UNSOURCED` gains a line for each: drive force, brake force, steering lock,
turbo meter size, turbo recharge. Do not copy the GTA drivetrain in and trim it; write the short
one.

**Turbo.** One action pair (`keyboard_turbo_action`, `pad_turbo_action`), a meter from 0 to 1 that
drains while held and recharges while not, and a `turbo_changed(amount: float)` signal for the
HUD. The original's meter behaviour (does it recharge continuously, or refill from pickups) is a
fact to look up on the Twisted Metal wiki, not to guess; if the page is not clear, recharge
continuously and say so in `UNSOURCED`.

**Wreck.** `TwCombat.died` is connected in the scene to `TwCar._on_died`, which sets
`is_wrecked = true`, stops taking drive input, and leaves the body as a rolling wreck. No fire and
explosion effect: that was the GTA damage model and it is gone with the CR-V. A wrecked car's
`TwAi` already brakes and stops steering.

**Input.** `set_drive_input(accelerate: bool, brake: bool, turbo: bool, steer: float)` is the whole
virtual pad, with the same signature shape `TwAi` uses today except that the third argument is
turbo rather than handbrake. `ride()` fills it from the action exports for a seated Player;
`TwAi` fills it directly. The drivetrain runs from the stored inputs every physics frame
regardless of who set them, which is what removes the old `is_ai_driven` gate for good.

**Energy attacks** (freeze, mine, rear fire, jump, shield, the button combos) are out of scope.
Say so in the README's rough edges and do not start them.

Scene `scenes/tm2_car.tscn`, standalone, root `VehicleBody3D` with `tm2_car.gd`:

| Node | Type | Notes |
|---|---|---|
| `Collision` | `CollisionShape3D` | A box sized to the 4.5 m the rips are scaled to. |
| `Model` | `Node3D` | Where `twisted_metal.gd` puts the ripped `.obj`. Rotated to face `forward()`. |
| `FrontLeft` etc. | `VehicleWheel3D` x4 | Named like the Rocket League car's, with the cgtrader wheel mesh from the CR-V or a plain cylinder. |
| `Seat` | `Marker3D` | The driver is hidden, so its only job is the Riding state's pin. Face it along `forward()`. |
| `VehicleCamera` | instance | `scenes/vehicle_camera.tscn`. |
| `MuzzleForward`, `MuzzleRear` | `Marker3D` | Front and back along `forward()`. |
| `TwCombat`, `TwAi` | `Node` | As today. `TwCombat.died` connected to `_on_died` in the scene. |
| `SFXEngine` | `AudioStreamPlayer3D` | Gravity Sound engine loop, pitched by speed. Placeholder. |
| `SFXTurbo` | `AudioStreamPlayer3D` | Leave the stream empty and ask the user for one. |

`physics_material_override` with friction and bounce set explicitly; note both as judgements.

Code changes around it:
- `car_combat.gd`: `_vehicle: TwCar`, and its comment stops saying "bolted onto a `Vehicle`".
- `ai_driver.gd`: `_vehicle: TwCar`, `target: TwCar`, `_combat_of(TwCar)`, drop the
  `is_ai_driven` line in `_ready`, `is_any_wheel_on_ground()` becomes `wheels_in_contact() > 0`,
  and the handbrake argument in every `set_drive_input` call becomes turbo. The AI uses turbo
  when in battle and the target is ahead and far, not when cornering. `-basis.z` becomes
  `_vehicle.forward()` in `_steer_towards`, `_ground_at` and `_update_attack`.
- `tm2_projectile.gd`: the shooter is `Node3D` and that is fine; the direction of flight comes
  from the muzzle's own transform, so once the muzzle faces `forward()` the projectile needs only
  its own `-basis.z` checked against the muzzle's orientation. Make them agree, and add a test
  that a shot fired forward moves away from the car along `forward()`.
- `twisted_metal.gd`: `player_car: TwCar`, `_make_car() -> TwCar`, the group loop in
  `_physics_process`. The hint text gains the turbo key.
- A small `scenes/tm2_ui.tscn` (`CanvasLayer`, script `tm2_ui.gd`, class `TwUi`) with a health
  bar, the selected weapon and its count, and the turbo meter, fed only by signals
  (`TwCombat.health_changed`, `TwCombat.weapon_changed`, `TwCar.turbo_changed`), the way
  `rocket_league_ui.gd` reads nothing. `twisted_metal.tscn` instances it and `twisted_metal.gd`
  calls `ui.watch(player_car)` once the player's car exists, the way `RlMatch` does.

Tests:
- New `tests/test_tm2_car.gd`: it is a `Vehicle`, not a `GtaCar`; the rideable contract names
  are all present; `forward()` agrees with the direction a driven car moves after 30 physics
  frames on a floor (build the floor in the test the way `test_rocket_car.gd` does); it reaches
  within 10 percent of `TwRoster.top_speed(car)` and not past it without turbo; turbo raises the
  ceiling and drains the meter; the meter recharges; a wrecked car ignores drive input; `died`
  reaches `_on_died` through the scene connection (`assert_connected`).
- `tests/test_ai_driver.gd`: retype, drop `test_the_car_is_told_an_ai_has_the_wheel` and replace
  it with a test that a disabled driver leaves the drive inputs at zero, and that an enabled one
  with a waypoint ahead sets accelerate within a few frames.
- `tests/test_car_combat.gd`: retype; the driver-hiding test stays, the CR-V one moved in Phase 1.
- `tests/test_tm2_ui.gd`: three signals in, three labels changed.

Gate: full suite green. Then `run_project` on `twisted_metal.tscn` through the MCP server. Confirm
with `run_script`: every car in `tm2_cars` is a `TwCar`, the player is riding one, opponents move
(velocity above 5 m/s for at least four of six within 20 seconds), at least one `TwCombat.fired`
happened, and no errors in `get_debug_output`. Take screenshots: the player's view at the wheel,
an opponent from the side at speed, the HUD after taking a hit, and a before-and-after pair of the
same spot from a run of the old scene captured before this phase started (capture the before shot
at the start of the phase, before touching `tm2_car.tscn`). Send them with `SendUserFile`. Remind
the user the editor needs a restart for the new class name.

## Phase 5: documentation and the plugin

1. `addons/gta/README.md`:
   - The opening paragraph describes the base and the three cars rather than "a rideable
     `Vehicle` with a GTA V style handling model".
   - "How to Use" gains a table of the three cars and a short section "Building your own car on
     `Vehicle`": what the base gives, what a subclass must add (a `Seat` unless it seats the
     Player itself, a `VehicleCamera`, `ride()`), and the `seat`-pins-immediately fact so nobody
     rediscovers it.
   - The Twisted Metal section: `tm2_car.tscn` is no longer "a scene inheriting `honda_crv.tscn`";
     describe the car, the turbo, the HUD, the sourced speeds and the `UNSOURCED` additions. Drop
     the `is_ai_driven` sentence. Rough edges: energy attacks not done, handling numbers are
     judgements, placeholder engine sound and no turbo sound yet.
   - The Rocket League "chassis" section as rewritten in Phase 3.
   - Tests section: the file list changed; say which test file covers which car.
2. Root `README.md`: the first paragraph, same change.
3. `plugin.gd`: three custom types.
4. Delete this plan's "temporary" retypes if any survived (grep for `GtaCar` outside
   `gta_car.gd`, `honda_crv.tscn`, `test_gta_car.gd`, `plugin.gd` and the README).

Gate: full suite green; `grep -rn "RocketVehicle\|rocket_vehicle\|is_ai_driven" addons/gta`
returns nothing.

## Phase 6: the host project

The host consumes this addon, and the change most likely to bite is the CR-V scene script path
and the exit action defaults.

1. Commit here first. The working tree holds the uncommitted Rocket League demo as well; ask the
   user whether to commit it in the same commit or separately, and stage by explicit path.
2. In `C:\GitHub\godot-3d-player-controller-v3`: `python tools/pull_addons.py`, then
   `grep -rn "Vehicle\b" scenes tests README.md` and fix any reference that named a member now on
   `GtaCar` (the README line about `Vehicle.radio_station` becomes `GtaCar.radio_station`; the
   test doc comments likewise).
3. Run that project's own two suites, nothing else:
   ```powershell
   & 'C:\Godot\godot.exe' --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit,res://tests/integration -gexit
   ```
4. `run_project` on its `world.tscn` through the MCP server: get in the CR-V, drive, tune the
   radio, get out.
5. The authority hand-off moved files. Its behaviour is unchanged, but the rule is that a change
   touching what peers see is verified with both machines: host on the PC through the `godot`
   MCP server, join from the Mac through `godot-mac` (pull the Mac clone level and run
   `python3 tools/pull_addons.py` there first, wrap long SSH work in `caffeinate -dis`), get in
   the car on one side and confirm `current_driver_peer_id` on the other. Screenshots from both
   sides. If `godot-mac` does not connect, say so rather than skipping it silently.
6. That project's `addons/gta` is a pulled copy, so once its own references are fixed it needs
   nothing pushed; the fix to its own files is a normal commit there.

## Order of work and where to stop

Phases 1 to 3 are one piece of work and should be done in one sitting; between them the code is
consistent but the story in the README is not. Phase 4 is the largest and is independent once
Phase 1 is in. Phase 5 can be done alongside 4. Phase 6 is last and needs the user (commit, Mac).

If time runs out, the clean stopping points are: after Phase 1 (base exists, three cars are two
and a CR-V), after Phase 3 (everything but Twisted Metal), after Phase 5 (all of it, unproven in
the host).

## What not to do

- Do not move any handling code into the base. It has none, on purpose.
- Do not make `TwCar` extend `GtaCar` to save writing a drivetrain. The point is three distinct
  cars.
- Do not touch `addons/3d_player_controller` or `addons/controls`; they are pulled copies and any
  change belongs in their own repositories. Nothing here needs one.
- Do not rename `RlCar`, `RlConst`, `RlMatch` or the `rocket_*` files; they are fine.
- Do not add sounds from anywhere. Ask.
