class_name MkCourse
extends Node3D
## A course for the kart demo: a racing line, a road, walls, a grid and item
## boxes, placed as nodes, plus an optional drop-in model of the real thing.
##
## The scene is the primitive course and it is what a fresh clone races on:
## the road is a slab extruded along the real road's centre line, the walls
## are boxes where the game's fences stand, and the trees, the castle and the
## sign are primitives of the right size in the right place. Its collision is
## the shape of the real course.
##
## [member model] names a glTF of the real course in the git-ignored assets
## folder, written by [code]tools/mk64_course.py[/code] from your own rip. When
## it is there it is instanced here as [code]DropInModel[/code], the primitive
## dressing is hidden and its collision switched off, and the model's own
## collision-only nodes take over, with the ones named for grass and sand
## tagged with the surface the kart reads ([code]mk_surface[/code]). The
## racing line, the grid and the item boxes are the scene's either way.

## The drop-in model, a [code]res://[/code] path. Empty, or missing on disk,
## keeps the primitives.
@export var model: String = ""
## The nodes that are the primitive dressing: hidden, and their collision off,
## when the model is in.
@export var primitive_parts: Array[NodePath] = [^"Road", ^"Ground", ^"Walls", ^"Props", ^"StartLine"]

## What the model's collision nodes are called, and the surface each is.
const MODEL_SURFACES: Dictionary = {
	"grass": MkConst.SURFACE_GRASS,
	"sand": MkConst.SURFACE_SAND,
}

var _drop_in: Node3D


func _ready() -> void:
	if model.is_empty() or not ResourceLoader.exists(model):
		return
	var scene: PackedScene = load(model) as PackedScene
	if scene == null:
		push_warning("%s: %s is not a scene; keeping the primitive course." % [name, model])
		return
	_drop_in = scene.instantiate() as Node3D
	if _drop_in == null:
		push_warning("%s: %s is not a 3D scene; keeping the primitive course." % [name, model])
		return
	_drop_in.name = "DropInModel"
	add_child(_drop_in)
	_tag_surfaces(_drop_in)
	for path: NodePath in primitive_parts:
		_switch_off(get_node_or_null(path))


## Whether the real course is in and the primitives are off.
func has_drop_in() -> bool:
	return _drop_in != null


## Hide a primitive part and take away its collision, CSG or body.
func _switch_off(part: Node) -> void:
	if part == null:
		return
	if part is Node3D:
		(part as Node3D).visible = false
	for node: Node in [part] + part.find_children("*", "", true, false):
		if node is CSGShape3D:
			(node as CSGShape3D).use_collision = false
		elif node is CollisionShape3D:
			(node as CollisionShape3D).disabled = true


## A collision body in the model named for grass or sand carries that surface.
func _tag_surfaces(root: Node) -> void:
	for body: Node in root.find_children("*", "StaticBody3D", true, false):
		var key: String = body.name.to_lower()
		for surface_name: String in MODEL_SURFACES:
			if key.begins_with(surface_name):
				body.set_meta(&"mk_surface", MODEL_SURFACES[surface_name])
