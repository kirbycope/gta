extends Node3D
## Skate park demo for Tim Cope's Pro Skater: a half pipe, a quarter pipe and a funbox to ride.
## The MountTimer in the scene puts the Player on the board once the scene has settled.

@export var player: Player
@export var skateboard: Node3D ## The pickup board; its equip() puts the Player on their own board.


## Wired to MountTimer.timeout in the scene.
func _on_mount_timer_timeout() -> void:
	if is_instance_valid(player) and is_instance_valid(skateboard) and not player.is_riding:
		skateboard.equip(player)
