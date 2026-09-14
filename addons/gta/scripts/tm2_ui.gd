class_name Tm2Ui
extends CanvasLayer
## The Twisted Metal HUD: health, the selected weapon and its count, and the turbo meter.
##
## It reads nothing. Every number on screen arrives through a signal, the same shape
## [RocketLeagueUi] uses: [CarCombat] emits health and the weapon, [Tm2Car] emits the turbo meter.
## Polling a car every frame for a bar that moves when it is hit would be the wrong shape, and the
## addon's rules say so.

@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthAmount
@onready var weapon_label: Label = %Weapon
@onready var turbo_bar: ProgressBar = %TurboBar


## Follow one car. The demo calls this once the player has a car, because which car that is is not
## known until the field has been spawned.
func watch(car: Tm2Car) -> void:
	if not is_instance_valid(car):
		return
	car.turbo_changed.connect(_on_turbo_changed)
	_on_turbo_changed(car.turbo)
	var combat: CarCombat = car.get_node_or_null(^"CarCombat") as CarCombat
	if combat == null:
		return
	combat.health_changed.connect(_on_health_changed)
	combat.weapon_changed.connect(_on_weapon_changed)
	_on_health_changed(combat.health, combat.max_health)
	_on_weapon_changed(combat.selected, int(combat.inventory.get(combat.selected, 0)))


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maxf(maximum, 1.0)
	health_bar.value = current
	health_label.text = "%d" % roundi(current)


func _on_weapon_changed(weapon: StringName, count: int) -> void:
	if weapon == &"":
		weapon_label.text = "Machine Gun"
		return
	weapon_label.text = "%s  x%d" % [String(weapon).capitalize(), count]


func _on_turbo_changed(amount: float) -> void:
	turbo_bar.value = amount
