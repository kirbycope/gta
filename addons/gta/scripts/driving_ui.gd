extends CanvasLayer
## Speedometer for a [Vehicle]; the vehicle shows it while it is driven.

const NEEDLE_MIN_DEGREES: float = -132.5 ## Needle rotation at zero speed.
const NEEDLE_SWEEP_DEGREES: float = 265.0 ## Needle travel from zero to [member speedometer_max_speed].
const MPS_TO_MPH: float = 2.23694

@export var vehicle: RigidBody3D
@export var speedometer_max_speed: float = 120.0 ## Speed (mph) at which the needle tops out.

@onready var speedometer_needle: TextureRect = $Speedometer/Needle


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	set_process(visible)


func _on_visibility_changed() -> void:
	set_process(visible)
	speedometer_needle.rotation_degrees = NEEDLE_MIN_DEGREES


func _process(_delta: float) -> void:
	if vehicle == null:
		return
	var speed_mph: float = vehicle.linear_velocity.length() * MPS_TO_MPH
	speedometer_needle.rotation_degrees = clampf(
		NEEDLE_MIN_DEGREES + speed_mph / speedometer_max_speed * NEEDLE_SWEEP_DEGREES,
		NEEDLE_MIN_DEGREES, -NEEDLE_MIN_DEGREES)
