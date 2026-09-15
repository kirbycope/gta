@tool
class_name RlArena
extends Node3D
## The soccar pitch, built from the published dimensions in [RlConst].
##
## This is a script rather than a hand-placed scene because every measurement
## it needs is already a constant. Typing 81.92 metres of width into a
## [code].tscn[/code] as well would be the same number in two places, and the
## two would drift the first time one was corrected. [code]twisted_metal.gd[/code]
## builds its arena in code for the same sort of reason.
##
## It is a [code]@tool[/code] script, so the pitch is there in the editor
## viewport and any change to the shape shows up without running the project.
##
## The shape itself is Rocket League's: a rounded rectangle 81.92 by 102.4
## metres with a ceiling at 20.48 and a 45 degree chamfer across each corner.
## The chamfers are what the 1629.174 uu of corner wall in the published figures
## describe, and they work out at 11.52 metres cut off each axis. The goals are
## open mouths in the back walls with a box behind, rather than a hole cut out
## of a solid wall, because three flat panels are cheaper and more predictable
## than a constructive solid subtraction.

const WALL_THICKNESS: float = 1.0
const CORNER_CUT: float = 11.52 ## What each 45 degree chamfer takes off both axes.
const LINE_WIDTH: float = 0.25
## The quarter round along the base of every wall, which is what a car drives up
## to get onto one. Rocket League's arena is a mesh ripped from the game and its
## floor runs into its walls through a curve; a blockout made of boxes meets
## them at a right angle, and a right angle is a wall you can only hit. The
## radius is a judgement call rather than a published figure, because the real
## geometry is a mesh this project does not have.
const FILLET_RADIUS: float = 4.0
const FILLET_SIDES: int = 18
const CORNER_WALL_FACE: float = 16.29174 ## The chamfer's own length, which its fillet matches.

## Rocket League's own team colours, near enough for a blockout.
const BLUE: Color = Color(0.13, 0.45, 0.95)
const ORANGE: Color = Color(0.98, 0.5, 0.1)
const PITCH: Color = Color(0.30, 0.35, 0.43)
const WALL: Color = Color(0.20, 0.23, 0.30)

@export_tool_button("Rebuild") var rebuild_action: Callable = rebuild


func _ready() -> void:
	rebuild()


## Throw the pitch away and build it again. Safe to call at any time, and the
## tool button above is wired straight to it.
func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_build_surfaces()
	_build_fillets()
	_build_goals()
	_build_markings()
	if not Engine.is_editor_hint():
		_build_boost_pads()


## Floor, ceiling, side walls, back wall panels and the four corner chamfers.
func _build_surfaces() -> void:
	var half_x: float = RlConst.ARENA_EXTENT_X
	var half_z: float = RlConst.ARENA_EXTENT_Y
	var height: float = RlConst.ARENA_HEIGHT

	_box("Floor", Vector3(half_x * 2.0, WALL_THICKNESS, half_z * 2.0),
		Vector3(0.0, -WALL_THICKNESS * 0.5, 0.0), PITCH)
	# the roof is a lid on the arena, and a lid between the sun and the pitch
	# leaves the whole thing in shadow, so it takes no part in shadow casting
	_box("Ceiling", Vector3(half_x * 2.0, WALL_THICKNESS, half_z * 2.0),
		Vector3(0.0, height + WALL_THICKNESS * 0.5, 0.0), WALL, false)

	for side: int in [-1, 1]:
		_box("SideWall%s" % ("Left" if side < 0 else "Right"),
			Vector3(WALL_THICKNESS, height, RlConst.SIDE_WALL_LENGTH),
			Vector3(side * (half_x + WALL_THICKNESS * 0.5), height * 0.5, 0.0), WALL)

	# the back wall is three panels around the goal mouth: two uprights and a
	# crossbar, which leaves the mouth open without cutting a hole in anything
	var post: float = RlConst.GOAL_HALF_WIDTH
	var crossbar: float = RlConst.GOAL_HEIGHT
	for end: int in [-1, 1]:
		var z: float = end * (half_z + WALL_THICKNESS * 0.5)
		var panel_width: float = (RlConst.BACK_WALL_LENGTH * 0.5) - post
		for side: int in [-1, 1]:
			_box("BackWall%s%s" % ["Near" if end < 0 else "Far", "Left" if side < 0 else "Right"],
				Vector3(panel_width, height, WALL_THICKNESS),
				Vector3(side * (post + panel_width * 0.5), height * 0.5, z), WALL)
		_box("Crossbar%s" % ["Near" if end < 0 else "Far"],
			Vector3(post * 2.0, height - crossbar, WALL_THICKNESS),
			Vector3(0.0, crossbar + (height - crossbar) * 0.5, z), WALL)

	# the four 45 degree corners, each cutting CORNER_CUT off both axes
	var face: float = CORNER_CUT * sqrt(2.0)
	for side: int in [-1, 1]:
		for end: int in [-1, 1]:
			var corner: CSGBox3D = _box("Corner%s%s" % ["Near" if end < 0 else "Far",
				"Left" if side < 0 else "Right"],
				Vector3(WALL_THICKNESS, height, face),
				Vector3(side * (half_x - CORNER_CUT * 0.5), height * 0.5,
					end * (half_z - CORNER_CUT * 0.5)), WALL)
			corner.rotation.y = deg_to_rad(45.0) * -side * end


## The curved skirting where the floor runs into the walls.
##
## Without it the arena is a box and the walls are simply the edge of the world:
## a car driven at one stops dead against a right angle. With it, and with the
## sticky force in [RlCar], a car can carry speed off the floor and up onto
## a wall, which is half of how Rocket League is actually played.
##
## Each one is a cylinder laid on its side and sunk into the corner, so only the
## quarter facing the pitch is exposed. The back wall's is in two pieces either
## side of the goal, because a ramp across the mouth would be a ramp over the
## goal line.
func _build_fillets() -> void:
	var half_x: float = RlConst.ARENA_EXTENT_X
	var half_z: float = RlConst.ARENA_EXTENT_Y
	var post: float = RlConst.GOAL_HALF_WIDTH
	var back_half: float = RlConst.BACK_WALL_LENGTH * 0.5

	# each piece sits on the corner line itself and is turned so its own
	# positive x runs away from the wall and into the pitch
	for side: int in [-1, 1]:
		_fillet("FilletSide%s" % ("Left" if side < 0 else "Right"),
			Vector3(side * half_x, 0.0, 0.0), RlConst.SIDE_WALL_LENGTH,
			0.0 if side < 0 else PI)

	# two per end, from the goal post out to the corner, because a ramp across
	# the mouth would be a ramp over the goal line
	var panel: float = back_half - post
	for end: int in [-1, 1]:
		for side: int in [-1, 1]:
			_fillet("FilletBack%s%s" % ["Near" if end < 0 else "Far", "Left" if side < 0 else "Right"],
				Vector3(side * (post + panel * 0.5), 0.0, end * half_z),
				panel, PI * 0.5 if end > 0 else -PI * 0.5)

	# and one along each 45 degree corner, facing its own inward normal
	for side: int in [-1, 1]:
		for end: int in [-1, 1]:
			_fillet("FilletCorner%s%s" % ["Near" if end < 0 else "Far",
				"Left" if side < 0 else "Right"],
				Vector3(side * (half_x - CORNER_CUT * 0.5), 0.0,
					end * (half_z - CORNER_CUT * 0.5)),
				CORNER_WALL_FACE, atan2(float(end), float(-side)))


## One quarter pipe, sat on the line where a wall meets the floor.
##
## The shape has to be concave, like a skate ramp, or a car hits it instead of
## riding up it. A cylinder laid in the corner gives the opposite, a convex
## bump that stops the car dead, so this is the corner block with a cylinder
## taken out of it: the solid is everything outside the curve and the arc that
## is left is the surface a car drives on.
##
## [param corner] is the line itself, on the floor at the foot of the wall.
## [param yaw] turns the piece so its own positive x points away from the wall,
## into the pitch, and its length runs along the wall.
func _fillet(node_name: String, corner: Vector3, length: float, yaw: float) -> void:
	var piece: CSGCombiner3D = CSGCombiner3D.new()
	piece.name = node_name
	piece.position = corner
	piece.basis = Basis(Vector3.UP, yaw)
	piece.use_collision = true
	add_child(piece)
	piece.owner = owner

	# the solid block that fills the corner, from the wall in and the floor up
	var block: CSGBox3D = CSGBox3D.new()
	block.name = "Block"
	block.size = Vector3(FILLET_RADIUS, FILLET_RADIUS, length)
	block.position = Vector3(FILLET_RADIUS * 0.5, FILLET_RADIUS * 0.5, 0.0)
	# a combiner has no material of its own, so the colour goes on the solid
	block.material = _material(PITCH)
	piece.add_child(block)
	block.owner = owner

	# and the cylinder cut out of it, centred where the arc's centre belongs:
	# a radius in from the wall and a radius up from the floor
	var cut: CSGCylinder3D = CSGCylinder3D.new()
	cut.name = "Cut"
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	cut.radius = FILLET_RADIUS
	cut.height = length + 1.0 # over-long, so the ends cut cleanly through
	cut.sides = FILLET_SIDES
	cut.position = Vector3(FILLET_RADIUS, FILLET_RADIUS, 0.0)
	# a cylinder stands on its own y, so it is tipped a quarter turn to lie
	# along the length of the piece
	cut.basis = Basis(Vector3.RIGHT, PI * 0.5)
	piece.add_child(cut)
	cut.owner = owner


## A box behind each goal line, open at the front, so a scored ball has
## somewhere to go instead of flying out of the world.
func _build_goals() -> void:
	var post: float = RlConst.GOAL_HALF_WIDTH
	var crossbar: float = RlConst.GOAL_HEIGHT
	var depth: float = RlConst.GOAL_DEPTH
	for end: int in [-1, 1]:
		var mouth: float = end * RlConst.ARENA_EXTENT_Y
		var colour: Color = BLUE if end > 0 else ORANGE
		_box("GoalBack%s" % ["Near" if end < 0 else "Far"],
			Vector3(post * 2.0 + WALL_THICKNESS * 2.0, crossbar, WALL_THICKNESS),
			Vector3(0.0, crossbar * 0.5, mouth + end * (depth + WALL_THICKNESS * 0.5)), colour)
		_box("GoalRoof%s" % ["Near" if end < 0 else "Far"],
			Vector3(post * 2.0, WALL_THICKNESS, depth),
			Vector3(0.0, crossbar + WALL_THICKNESS * 0.5, mouth + end * depth * 0.5), WALL)
		_box("GoalFloor%s" % ["Near" if end < 0 else "Far"],
			Vector3(post * 2.0, WALL_THICKNESS, depth),
			Vector3(0.0, -WALL_THICKNESS * 0.5, mouth + end * depth * 0.5), colour)
		for side: int in [-1, 1]:
			_box("GoalSide%s%s" % ["Near" if end < 0 else "Far", "Left" if side < 0 else "Right"],
				Vector3(WALL_THICKNESS, crossbar, depth),
				Vector3(side * (post + WALL_THICKNESS * 0.5), crossbar * 0.5,
					mouth + end * depth * 0.5), WALL)


## Halfway line and centre circle, drawn flat on the floor. They are decoration
## and carry no collision, but a pitch with no markings is very hard to judge
## distance on from the chase camera.
func _build_markings() -> void:
	var line: CSGBox3D = _box("HalfwayLine",
		Vector3(RlConst.ARENA_EXTENT_X * 2.0, 0.02, LINE_WIDTH),
		Vector3(0.0, 0.01, 0.0), Color(0.8, 0.85, 0.9, 1.0))
	line.use_collision = false
	var circle: CSGCylinder3D = CSGCylinder3D.new()
	circle.name = "CentreCircle"
	circle.radius = 9.15
	circle.height = 0.02
	circle.sides = 48
	circle.position = Vector3(0.0, 0.005, 0.0)
	circle.material = _material(Color(0.30, 0.34, 0.40))
	add_child(circle)
	circle.owner = owner


## Every boost pad in the published tables, all thirty four of them. These are
## only built at run time: they are gameplay rather than scenery, and the
## editor does not need thirty four areas in the viewport.
func _build_boost_pads() -> void:
	var scene: PackedScene = load("res://addons/gta/rl/scenes/rl_boost_pad.tscn") as PackedScene
	if scene == null:
		push_warning("RlArena: rocket_boost_pad.tscn is missing, so the pitch has no boost.")
		return
	var pads: Node3D = Node3D.new()
	pads.name = "BoostPads"
	add_child(pads)
	for spot: Vector2 in RlConst.BIG_PADS:
		_add_pad(pads, scene, spot, true)
	for spot: Vector2 in RlConst.SMALL_PADS:
		_add_pad(pads, scene, spot, false)


func _add_pad(parent: Node3D, scene: PackedScene, spot: Vector2, big: bool) -> void:
	var pad: RlBoostPad = scene.instantiate() as RlBoostPad
	if pad == null:
		return
	pad.is_big = big
	# the tables are in Rocket League's axes, where y runs along the pitch
	pad.position = RlConst.to_godot(spot.x, spot.y, 0.0)
	parent.add_child(pad)


## One solid box of the arena. Everything structural goes through here so the
## collision and the material are set the same way every time.
func _box(node_name: String, size: Vector3, at: Vector3, colour: Color,
		casts_shadow: bool = true) -> CSGBox3D:
	var box: CSGBox3D = CSGBox3D.new()
	box.name = node_name
	box.size = size
	box.position = at
	box.use_collision = true
	box.material = _material(colour)
	if not casts_shadow:
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(box)
	box.owner = owner
	return box


func _material(colour: Color) -> StandardMaterial3D:
	var made: StandardMaterial3D = StandardMaterial3D.new()
	made.albedo_color = colour
	made.roughness = 0.85
	made.metallic = 0.0
	return made
