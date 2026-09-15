class_name TwWaypoints
extends Resource
## The AI driving points for one Twisted Metal 2 arena.
##
## Built by [code]tools/extract_tm2.py[/code] from the level's .PTS file on the
## game disc, which holds 140 fixed-size records of positions in game units.
## Twisted Metal drives its opponents from point to point along these, which is
## what [code]AICarDriveBetweenPts[/code] does in the original.

@export var points: PackedVector3Array = PackedVector3Array()


## Index of the point nearest [param where], or -1 when there are none.
func nearest(where: Vector3) -> int:
	var best: int = -1
	var best_distance: float = INF
	for i: int in points.size():
		var d: float = points[i].distance_squared_to(where)
		if d < best_distance:
			best_distance = d
			best = i
	return best


## The point after [param index], wrapping at the end.
func next_index(index: int) -> int:
	return 0 if points.is_empty() else (index + 1) % points.size()


## A point picked at random, for scattering cars at the start of a round.
func random_index() -> int:
	return -1 if points.is_empty() else randi() % points.size()
