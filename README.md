![Preview](addons/gta/assets/gta.png)

# Godot Tim's Automobile (GTA) for Godot 4.8+

One rideable car chassis and four cars built on it, each driving like the game it comes from: a road
car with GTA V style handling (a five-speed box, traction curves, a handbrake and a chase camera), a
Twisted Metal 2 car with arcade handling and a turbo, a Rocket League battle car with boost, flips
and aerials, and a Mario Kart 64 kart with that game's ten band acceleration curve, its hop into a
drift and the mini turbo it pays out. Each has a demo: an asphalt lot, that game's own Los Angeles
arena converted from the disc, a full size soccar pitch with AI opponents and goal replays, and three
laps of a circuit against seven computer drivers who brake for the corners and throw things at you.

**[Read the full documentation](addons/gta/README.md)**, which ships with the addon so it is
there however you installed it.

## This repository

It uses the layout the [Godot Asset Library](https://docs.godotengine.org/en/stable/community/asset_library/submitting_to_assetlib.html) expects, so it is both the addon and a
project you can open and edit it in:

```
project.godot                 the demo project, which is this repository
addons/gta/                   the addon itself: the shared Vehicle chassis and camera
addons/gta/gta/               the road car, and its demo
addons/gta/tw/                Twisted Metal
addons/gta/rl/                Rocket League
addons/gta/mk/                Mario Kart
addons/gta/resources/control_schemes/  the GTA control scheme, for the player on foot
tools/extract_tm2.py          builds the Twisted Metal level from your own disc
tools/extract_mk64.py         reads the kart item odds out of your own Mario Kart 64 ROM
addons/3d_player_controller/  what the demo drives around as
addons/controls/              the on-screen input hints
addons/gut/                   the test runner
```

## The control scheme

`addons/gta/resources/control_schemes/gta.tres` is this addon's pad layout for the player **on foot**, not for the
car: A sprint, B attack, X jump, Y action, with Focus a free over-the-shoulder aim rather than a lock-on. It is
a `ControlScheme` from the 3D Player Controller, so a scene puts it on a Player through
`Player.control_scheme`, and a game that wants it offered in the settings menu announces it once:

```gdscript
PlayerControls.register_scheme(preload("res://addons/gta/resources/control_schemes/gta.tres"))
```

It lives here rather than in the player controller because it is named after this game. The player controller
carries only what any game needs, and it must never preload out of another addon, or the drop-in template would
depend on an addon that may not be installed. The car's own controls are separate and are on `CarControls`.


Each game is a folder of its own, with its own scripts, scenes, assets, tests and README, and each
is prefixed the way it is named: `gta`, `tw`, `rl`, `mk`. What stays at the top of the addon is only
what all four share.

Clone it, open `project.godot` in Godot, and run the demo scene. The addon is mounted at
`res://addons/gta/` exactly as it is in a game, so it is edited in place with nothing copied
anywhere first. Installing through the Asset Library takes `addons/` and skips the root
`project.godot` as a conflict, which is why that file can live here harmlessly.

## The vendored addons

`addons/3d_player_controller/` and `addons/controls/` are not part of this repository. They are
copies taken from their own repositories by `tools/pull_addons.py`, and both are git-ignored here,
so git sees nothing when one of them changes. `tools/addons.lock.json` records the commit each copy
came from.

```bash
python3 tools/pull_addons.py              # take the latest of every addon
python3 tools/pull_addons.py --dry-run    # report, change nothing
git config core.hooksPath .githooks       # once per clone, see below
```

Two guards keep work here from being lost, because it has been lost this way before: hand-tuned
animation `.tres` files edited in a vendored copy were quietly overwritten by a later pull, and
nothing said so at the time.

A pull now refuses to overwrite a file that was edited here and never sent upstream. It tells that
apart from an ordinary upstream change by diffing against the commit the lock file recorded, since a
file differing only from the incoming commit is just something new arriving:

```
3d_player_controller         1e11cff  STOPPED: 1 file(s) edited here since the last pull
                               assets/mixamo/animations/tuned/Swimming.tres
                             push them first with tools/push_addons.py, or re-run with --force to overwrite
```

A `pre-push` hook covers the other direction. It runs `tools/push_addons.py --dry-run` and refuses
to push this project while any addon here differs from its own repository, so the project half and
the addon half of a change land together instead of one going out alone. Enable it per clone with
the `git config` line above, and bypass it once with `git push --no-verify`.

`python3 -m unittest tools/test_addon_common.py` covers both guards.

## Textures import Lossless

Every texture here imports with `compress/mode=0` (Lossless) and `detect_3d/compress_to=1`, so the
editor promotes one to VRAM Compressed the first time it sees it used in 3D. That is Godot's own
default.

This repository used to force `compress/mode=1` (Lossy) with promotion disabled, project wide. That
re-encoded every image through WebP at quality 0.7 before Godot saw it, and still uploaded
uncompressed to VRAM, so it lost real data in the car and city normal maps and bought nothing at run time. It existed only to
squeeze a built `.pck` under GitHub's 100 MB limit, and nothing built is committed any more.

`python ../godot-3d-player-controller-v3/tools/texture_import_policy.py --root .` puts the
repository back on that policy, and `--check` reports without writing.

## Installing it in a game

Copy `addons/gta/` into your project's `addons/`. See the
[addon's README](addons/gta/README.md) for what it needs and how to use it.
