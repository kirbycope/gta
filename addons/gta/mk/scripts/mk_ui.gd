class_name MkUi
extends CanvasLayer
## The race HUD: position, lap, the item slot, the countdown and the speedometer.
##
## It reads nothing, the same shape [TwUi] and [RlUi] use. Every
## number on screen arrives through a signal: [MkRace] emits the order, the
## laps and the lights, [MkItemSlot] emits the slot, and [MkCar] emits its
## boosts. The one exception is the speedometer, which follows a continuously
## changing value and so is sampled in [method _process] rather than pretending
## a signal would suit it.
##
## The speed shown is km/h, because that is the unit Mario Kart 64's own
## speedometer reads in; [method MkConst.ms_to_kmh] does the conversion and its
## derivation is written up in [MkConst].
##
## [b]The odds warning.[/b] When the real item tables have not been extracted
## from a ROM, the HUD says so once rather than letting stand in odds pass for
## the real ones. See [method MkItems.has_real_odds].

const ORDINALS: PackedStringArray = ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th"]

@onready var position_label: Label = %Position
@onready var lap_label: Label = %Lap
@onready var item_label: Label = %Item
@onready var speed_label: Label = %Speed
@onready var countdown_label: Label = %Countdown
@onready var notice_label: Label = %Notice

var _kart: MkCar
var _race: MkRace


func _ready() -> void:
	countdown_label.text = ""
	notice_label.text = ""
	if not MkItems.has_real_odds():
		notice_label.text = "Placeholder item odds: run tools/extract_mk64.py to use the real ones."


## Follow one kart in one race. The demo calls this once it knows which kart is
## the player's, because that is not known until the grid has been filled.
func watch(kart: MkCar, race: MkRace) -> void:
	if not is_instance_valid(kart) or not is_instance_valid(race):
		return
	_kart = kart
	_race = race
	race.countdown_tick.connect(_on_countdown_tick)
	race.race_started.connect(_on_race_started)
	race.order_changed.connect(_on_order_changed)
	race.lap_completed.connect(_on_lap_completed)
	race.kart_finished.connect(_on_kart_finished)
	var slot: MkItemSlot = kart.get_node_or_null(^"ItemSlot") as MkItemSlot
	if slot != null:
		slot.item_changed.connect(_on_item_changed)
		slot.roulette_started.connect(_on_roulette_started)
		_on_item_changed(slot.item, slot.uses_left)
	_on_order_changed(race.order)
	_on_lap_completed(kart, 0)


func _process(_delta: float) -> void:
	if not is_instance_valid(_kart):
		return
	speed_label.text = "%d km/h" % roundi(MkConst.ms_to_kmh(absf(_kart.forward_speed())))


func _on_countdown_tick(seconds_left: int) -> void:
	countdown_label.text = str(seconds_left)


func _on_race_started() -> void:
	countdown_label.text = "Go"
	await get_tree().create_timer(1.0).timeout
	countdown_label.text = ""


func _on_order_changed(order: Array) -> void:
	if not is_instance_valid(_kart):
		return
	var index: int = order.find(_kart)
	if index < 0 or index >= ORDINALS.size():
		return
	position_label.text = ORDINALS[index]


func _on_lap_completed(kart: MkCar, _lap: int) -> void:
	if kart != _kart or not is_instance_valid(_race):
		return
	lap_label.text = "Lap %d/%d" % [mini(_race.lap_of(_kart), _race.laps), _race.laps]


func _on_kart_finished(kart: MkCar, place: int) -> void:
	if kart != _kart:
		return
	countdown_label.text = "Finish: %s" % ORDINALS[clampi(place - 1, 0, ORDINALS.size() - 1)]


func _on_roulette_started() -> void:
	item_label.text = "..."


func _on_item_changed(item: int, uses_left: int) -> void:
	if item == MkItems.Item.NONE:
		item_label.text = ""
		return
	var name_text: String = MkItems.display_name(item)
	item_label.text = name_text if uses_left <= 1 else "%s x%d" % [name_text, uses_left]
