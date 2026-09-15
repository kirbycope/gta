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
tools/extract_tm2.py          builds the Twisted Metal level from your own disc
tools/extract_mk64.py         reads the kart item odds out of your own Mario Kart 64 ROM
addons/3d_player_controller/  what the demo drives around as
addons/controls/              the on-screen input hints
addons/gut/                   the test runner
```

Each game is a folder of its own, with its own scripts, scenes, assets, tests and README, and each
is prefixed the way it is named: `gta`, `tw`, `rl`, `mk`. What stays at the top of the addon is only
what all four share.

Clone it, open `project.godot` in Godot, and run the demo scene. The addon is mounted at
`res://addons/gta/` exactly as it is in a game, so it is edited in place with nothing copied
anywhere first. Installing through the Asset Library takes `addons/` and skips the root
`project.godot` as a conflict, which is why that file can live here harmlessly.

## Installing it in a game

Copy `addons/gta/` into your project's `addons/`. See the
[addon's README](addons/gta/README.md) for what it needs and how to use it.
