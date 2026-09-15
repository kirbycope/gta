class_name MkAssets
extends RefCounted
## Drop-in art and audio for the kart demo, if you have any.
##
## The demo ships with the addon's own karts: boxes, cylinders and a capsule for
## the driver, liveried per roster entry. They are deliberately simple and they
## are what runs on a fresh clone with nothing else present.
##
## This class is the seam for replacing them. Put a model or a sound in
## [constant ROOT] under the name of the thing it replaces and it is picked up
## the next time the scene runs; take it away again and the primitives come
## back. Nothing here is required, nothing is fetched, and nothing is committed:
## [constant ROOT] is git-ignored, the same way the Twisted Metal demo treats the
## files [code]tools/extract_tm2.py[/code] builds off your own disc.
##
## [b]The layout.[/b] Every entry is optional and the extension may be any that
## Godot imports, so a [code].glb[/code] and a [code].obj[/code] are both fine.
##
## [codeblock]
## addons/gta/mk/assets/
##   karts/rook.glb          replaces one driver's whole kart
##   karts/default.glb       replaces every kart that has no file of its own
##   drivers/rook.glb        replaces just the figure in the seat
##   drivers/default.glb
##   sounds/engine.ogg       the engine loop
##   sounds/boost.ogg        a boost or mini turbo firing
##   sounds/drift.ogg        the drift
## [/codeblock]
##
## [b]Which way a model faces.[/b] This chassis drives along +Z, so a kart model
## is expected nose along +Z too. Anything authored the other way round is
## turned with [member MkCar.model_yaw_degrees] rather than by editing the
## file, because that export lives in the kart scene where it can be seen and
## changed.
##
## [b]Scale and licence are yours.[/b] Nothing checks either. A model that
## arrives ten times too big will look ten times too big, and whatever you put
## here carries whatever terms it came with, which is why this folder is not
## part of the repository.

const ROOT: String = "res://addons/gta/mk/assets"
const KART_DIR: String = ROOT + "/karts"
const DRIVER_DIR: String = ROOT + "/drivers"
const SOUND_DIR: String = ROOT + "/sounds"

## The name a file takes to stand in for every driver without one of their own.
const DEFAULT_NAME: String = "default"

## What Godot will import as a scene, in the order they are tried.
const MODEL_EXTENSIONS: PackedStringArray = [".glb", ".gltf", ".tscn", ".scn", ".obj", ".res"]
## And as audio.
const SOUND_EXTENSIONS: PackedStringArray = [".ogg", ".wav", ".mp3"]


## Whether anything at all has been dropped in. The demo says so on screen, so
## that a folder full of files that are not being picked up is noticed rather
## than puzzled over.
static func has_any() -> bool:
	return DirAccess.dir_exists_absolute(ROOT)


## A kart model for [param driver], their own or the shared default, or null
## when there is neither and the primitives should be used.
static func kart_model(driver: StringName) -> PackedScene:
	return _load_scene(KART_DIR, String(driver))


## Just the figure in the seat for [param driver], or null.
static func driver_model(driver: StringName) -> PackedScene:
	return _load_scene(DRIVER_DIR, String(driver))


## A named sound, or null. [param sound_name] is the bare name: "engine",
## "boost", "drift".
static func sound(sound_name: String) -> AudioStream:
	var path: String = _find(SOUND_DIR, sound_name, SOUND_EXTENSIONS)
	if path.is_empty():
		return null
	return load(path) as AudioStream


## Load [param base] from [param dir], falling back to the shared default.
static func _load_scene(dir: String, base: String) -> PackedScene:
	var path: String = _find(dir, base, MODEL_EXTENSIONS)
	if path.is_empty():
		path = _find(dir, DEFAULT_NAME, MODEL_EXTENSIONS)
	if path.is_empty():
		return null
	return load(path) as PackedScene


## The first existing file called [param base] with one of [param extensions],
## or an empty string. Nothing is scanned: each candidate is asked for by name,
## so a folder of unrelated files costs nothing.
static func _find(dir: String, base: String, extensions: PackedStringArray) -> String:
	if base.is_empty():
		return ""
	for extension: String in extensions:
		var path: String = "%s/%s%s" % [dir, base, extension]
		if ResourceLoader.exists(path):
			return path
	return ""
