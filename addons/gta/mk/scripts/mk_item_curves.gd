@tool
class_name MkItemCurves
extends Resource
## Mario Kart 64's real item tables, once they have been read out of a ROM.
##
## The game does not roll weighted dice for items. It keeps a flat hundred entry
## table for each finishing position and reads the entry the rolling index lands
## on, so the odds for a given position are simply how many times each item
## appears in that position's hundred. [MkItems] explains the draw; this
## resource is the tables it draws from.
##
## They are not in the decompilation. They live in the ROM behind a segment
## pointer, which is why the decomp source only ever names the symbol
## [code]common_grand_prix_human_item_curve[/code] without defining it.
## [code]tools/extract_mk64.py[/code] reads them out of your own copy of the game
## and writes one of these; without that file [MkItems] falls back to an even
## spread that is marked as not the real odds rather than passed off as them.
##
## [member curves] is stored flat, [constant MkItems.CURVE_LENGTH] entries per
## position one after another, because that is the shape the ROM holds and
## reshaping it here would only invite the two to drift apart.

## Every table end to end: position 0's hundred, then position 1's, and so on.
@export var curves: PackedInt32Array = PackedInt32Array()
## Which mode these came from, since the game keeps separate tables for a grand
## prix, for versus and for battle.
@export var mode: StringName = &"grand_prix_human"
## How many positions are in [member curves], so a versus table for four players
## and a grand prix table for eight can both be stored here.
@export var positions: int = MkConst.RACERS
## The SHA1 of the ROM these were read out of, so a table can be traced back to
## the copy it came from.
@export var source_sha1: String = ""


## The hundred entry table for [param rank], zero based, or an empty array when
## this resource does not carry that position.
func curve_for_rank(rank: int) -> PackedInt32Array:
	var length: int = MkItems.CURVE_LENGTH
	var start: int = clampi(rank, 0, maxi(positions - 1, 0)) * length
	if start + length > curves.size():
		return PackedInt32Array()
	return curves.slice(start, start + length)


## How often each item comes up for [param rank], as item id to count out of a
## hundred. This is the actual odds, and is what a test asserts against.
func odds_for_rank(rank: int) -> Dictionary:
	var counts: Dictionary = {}
	for item: int in curve_for_rank(rank):
		counts[item] = int(counts.get(item, 0)) + 1
	return counts
