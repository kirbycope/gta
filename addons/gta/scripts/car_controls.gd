class_name CarControls
extends Controls
## The on-screen controls for a demo that is only ever a car.
##
## The Controls addon's HUD, with the slots the addon's battle cars read mapped in
## [code]car_controls.tscn[/code] and every other slot left blank, which hides it. There is no Attack,
## no Seeker, no Whistle and no menu on it, because there is no [Player] in those demos to do any of
## that: a [HumanDriver] fills the car's pad and this is the pad drawn on the screen.
##
## The HUD is also what puts the addon's action names into the InputMap, and in the road car demo the
## Player's own HUD does that. Here the car actions are registered with the same keys the player
## controller binds, read straight from its table so they cannot drift: Space is jump, which a keyboard
## accelerates with, Shift is sprint, which reverses, and so on. The joypad buttons come with the slots.
##
## Every slot's label is written by the [HumanDriver] from what the car says its buttons do, and
## [code]test_car_controls.gd[/code] reads every one of those labels back against the action the slot
## really carries, so a label cannot sit on the wrong key.

## The actions the battle cars read that have a key or mouse button behind them. The bindings come from
## the player controller's own table so a person moving between the demos meets nothing new.
const CAR_ACTIONS: Array[StringName] = [
	&"jump", &"sprint", &"action", &"crouch", &"ability", &"throw", &"shoot", &"focus",
	&"reload", ## Resets the Rocket League match; no button on the HUD, the way the player controller has it.
]


func _ready() -> void:
	var table: Dictionary = {}
	for action: StringName in CAR_ACTIONS:
		if PlayerControls.PLAYER_ACTIONS.has(String(action)):
			table[String(action)] = PlayerControls.PLAYER_ACTIONS[String(action)]
	extra_actions = table
	super()
