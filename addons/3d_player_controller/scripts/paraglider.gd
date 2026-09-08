extends Node3D
## Paraglider visuals and audio, shown while the Player is in the PARAGLIDING state.

@export var player: Player:
	set(value):
		if player:
			player.state_changed.disconnect(_on_player_state_changed)
		player = value
		if player:
			player.state_changed.connect(_on_player_state_changed)

@onready var opening: AudioStreamPlayer3D = $Opening
@onready var cloth_ruffling: AudioStreamPlayer3D = $ClothRuffling
@onready var left_wing: Contrail3D = $LeftWing
@onready var right_wing: Contrail3D = $RightWing
@onready var airflow_streaks: GPUParticles3D = $AirflowStreaks
@onready var opening_wind_burst: GPUParticles3D = $OpeningWindBurst


## Opens the paraglider when paragliding starts and packs it away when it ends.
func _on_player_state_changed(from_state: int, to_state: int) -> void:
	if not is_multiplayer_authority(): return

	if to_state == NodeStateMachine.States.PARAGLIDING:
		show()
		left_wing.emitting = true
		right_wing.emitting = true
		airflow_streaks.emitting = true
		opening_wind_burst.restart()
		opening_wind_burst.emitting = true
		opening.play()
		cloth_ruffling.play()
	elif from_state == NodeStateMachine.States.PARAGLIDING:
		hide()
		opening.stop()
		cloth_ruffling.stop()
		left_wing.emitting = false
		right_wing.emitting = false
		airflow_streaks.emitting = false
		opening_wind_burst.emitting = false
		left_wing.clear()
		right_wing.clear()
