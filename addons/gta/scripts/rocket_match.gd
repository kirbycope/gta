class_name RocketMatch
extends Node3D
## A game of soccar: the demo's root, and everything that is a rule rather than
## a physics constant.
##
## It owns the teams, the clock, the score, the kickoff, the goal replay and the
## reset. The pitch itself is [RocketArena], the handling is [RocketCar] and the
## opponents think in [RocketAi]; none of those know the score.
##
## The player is hidden at the wheel of a blue car exactly the way the Twisted
## Metal demo hides them, through [member Vehicle.hides_driver_model] and
## [method Player.mount]. There is no walking around: the match seats them the
## moment it starts and re-seats them after every kickoff.
##
## The rules here are Rocket League's, and they are rules rather than published
## constants, so [constant RocketConst.UNSOURCED] lists the clock as a judgement
## call. A goal is the one exception: the game defines it as the ball's centre
## crossing 5124.25 uu, which is a number, so that is what is checked.

signal score_changed(blue: int, orange: int)
signal clock_changed(seconds: float)
signal state_changed(state: State)
signal goal_scored(team: RocketCar.Team, scorer: RocketCar)
signal match_ended(winner: RocketCar.Team, tied: bool)

enum State {
	COUNTDOWN, ## Frozen on the kickoff spots while the three counts down.
	PLAYING, ## Live.
	REPLAY, ## Watching the goal that was just scored.
	OVER, ## Full time.
}

const COUNTDOWN_SECONDS: float = 3.0
const REPLAY_SECONDS: float = 4.0 ## How much of the buffer a goal replay shows.
const REPLAY_SUBJECT_HEIGHT: float = 2.6 ## How far up the goal mouth the replay looks at.
## Where the replay camera wants to be, relative to the goal: off to one side,
## up, and out toward the halfway line. The z is applied toward the pitch
## whichever end was scored in, so both goals are filmed the same way.
const REPLAY_OFFSET: Vector3 = Vector3(11.0, 7.5, 18.0)
const CENTRE_SPOT: Vector3 = Vector3(0.0, RocketConst.BALL_REST_HEIGHT, 0.0)
const FELL_OUT_Y: float = -20.0 ## Anything under this has escaped the arena and is put back.
const BLUE_NAMES: Array[String] = ["You", "Mate", "Wing"]
const ORANGE_NAMES: Array[String] = ["Striker", "Sweeper", "Keeper"]

@export_range(1, 5) var team_size: int = 3 ## Cars a side. Three is Rocket League's standard match.
@export var match_minutes: float = 5.0 ## The clock, which is a rule rather than a published constant.
@export var ai_skill: float = 0.8 ## Handed to every [RocketAi]; zero dawdles, one commits.
@export var seat_player: bool = true ## Off makes the demo an AI match to watch.

@onready var arena: RocketArena = $Arena
@onready var ball: RocketBall = $Ball
@onready var replay: RocketReplay = $Replay
@onready var ui: RocketLeagueUi = $UI
@onready var countdown_timer: Timer = $CountdownTimer
## The replay camera hangs off a spring arm anchored at the goal, so anything
## that comes between the two pulls it in rather than blocking the shot.
@onready var replay_pivot: Node3D = $ReplayCamera
@onready var replay_arm: SpringArm3D = $ReplayCamera/SpringArm3D
@onready var replay_camera: Camera3D = $ReplayCamera/SpringArm3D/Camera3D

var state: State = State.COUNTDOWN: set = _set_state
var blue_score: int = 0
var orange_score: int = 0
var clock: float = 0.0
var is_overtime: bool = false

var cars: Array[RocketCar] = []
var player_car: RocketCar

var _kickoff_taker: int = 0 ## Rotates which spot the player starts on.


func _ready() -> void:
	clock = match_minutes * 60.0
	# the pitch only has collision once physics has seen it, and the cars are
	# dropped onto that collision
	await get_tree().physics_frame
	_spawn_teams()
	var cast: Array[Node3D] = []
	for car: RocketCar in cars:
		cast.append(car)
	cast.append(ball)
	replay.track(cast)
	# the spring arm is there to keep the arena out of the shot; a car or the
	# ball crossing in front of it is the replay, not an obstruction
	for car: RocketCar in cars:
		replay_arm.add_excluded_object(car.get_rid())
	replay_arm.add_excluded_object(ball.get_rid())
	replay.finished.connect(_on_replay_finished)
	countdown_timer.timeout.connect(_on_countdown_finished)
	# which car the player is in is not known until the teams are built, so the
	# boost meter is pointed at it here rather than wired up in the scene
	if is_instance_valid(player_car):
		ui.watch(player_car)
	score_changed.emit(blue_score, orange_score)
	clock_changed.emit(clock)
	if seat_player:
		_seat_the_player.call_deferred()
	else:
		_stand_the_player_down()
	start_kickoff()


func _physics_process(delta: float) -> void:
	replay.record()
	if state == State.REPLAY:
		_track_replay()
		return
	if state != State.PLAYING:
		return
	_tick_clock(delta)
	_recover_escapees()
	var scored: int = _goal_crossed()
	if scored != 0:
		_award_goal(RocketCar.Team.ORANGE if scored > 0 else RocketCar.Team.BLUE)


## Put everyone on their kickoff spots, freeze them and count three. Called at
## the start of the match and after every goal.
func start_kickoff() -> void:
	replay.stop()
	ball.reset_to(CENTRE_SPOT)
	for pad: Node in get_tree().get_nodes_in_group(&"rocket_boost_pads"):
		(pad as RocketBoostPad).reset_pad()
	_kickoff_taker = (_kickoff_taker + 1) % maxi(team_size, 1)
	for i: int in cars.size():
		var car: RocketCar = cars[i]
		var index: int = i % team_size
		# the player takes a different spot each kickoff, which is what stops
		# the same car taking every one
		var spot_index: int = (index + _kickoff_taker) % RocketConst.KICKOFF_SPOTS.size()
		_place_on_kickoff(car, spot_index)
		car.refill_boost()
	if player_car != null:
		_reseat_player()
	replay_camera.current = false
	state = State.COUNTDOWN
	countdown_timer.start(COUNTDOWN_SECONDS)


## Back to nothing: scores cleared, clock full, everyone on the spots again.
## The demo's reset key comes here.
func reset_match() -> void:
	blue_score = 0
	orange_score = 0
	is_overtime = false
	clock = match_minutes * 60.0
	_kickoff_taker = 0
	score_changed.emit(blue_score, orange_score)
	clock_changed.emit(clock)
	start_kickoff()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"reload"):
		reset_match()


## Regulation time runs out, but the game does not stop until the ball is down.
## A shot in the air as the clock hits zero is still live, which is the rule
## Rocket League actually plays.
func _tick_clock(delta: float) -> void:
	if is_overtime:
		clock += delta
		clock_changed.emit(clock)
		return
	clock = maxf(0.0, clock - delta)
	clock_changed.emit(clock)
	if clock > 0.0:
		return
	var grounded: bool = ball.global_position.y <= RocketConst.BALL_REST_HEIGHT + 0.2 \
		and ball.linear_velocity.y <= 0.1
	if not grounded:
		return
	if blue_score == orange_score:
		_begin_overtime()
	else:
		_end_match()


func _begin_overtime() -> void:
	is_overtime = true
	clock = 0.0
	clock_changed.emit(clock)
	start_kickoff()


func _end_match() -> void:
	state = State.OVER
	var tied: bool = blue_score == orange_score
	var winner: RocketCar.Team = RocketCar.Team.BLUE if blue_score > orange_score \
		else RocketCar.Team.ORANGE
	for car: RocketCar in cars:
		car.release_controls()
	match_ended.emit(winner, tied)


## Which goal the ball is in, as minus one for the orange net, plus one for the
## blue net and zero for still in play. Rocket League scores on the ball's
## centre passing 5124.25 uu, which is [constant RocketConst.GOAL_LINE_Y].
func _goal_crossed() -> int:
	var z: float = ball.global_position.z
	if absf(z) < RocketConst.GOAL_LINE_Y:
		return 0
	if absf(ball.global_position.x) > RocketConst.GOAL_HALF_WIDTH:
		return 0
	if ball.global_position.y > RocketConst.GOAL_HEIGHT:
		return 0
	return signi(int(z))


func _award_goal(team: RocketCar.Team) -> void:
	if team == RocketCar.Team.BLUE:
		blue_score += 1
	else:
		orange_score += 1
	score_changed.emit(blue_score, orange_score)
	goal_scored.emit(team, ball.last_touch())

	# golden goal: overtime ends the moment anyone scores
	if is_overtime:
		_end_match()
		return
	_show_replay(team)


## Cut to the goal that was just scored in and play the buffer back. A goal in
## the opening seconds has nothing recorded yet, and goes straight to the
## kickoff rather than sitting on a frozen frame.
func _show_replay(team: RocketCar.Team) -> void:
	var end: float = RocketConst.GOAL_LINE_Y if team == RocketCar.Team.ORANGE else -RocketConst.GOAL_LINE_Y
	_aim_replay_at(end)
	# the buffer holds six seconds but only the last four are worth watching,
	# and at the replay's own slower playback that is about six on screen
	if not replay.play(REPLAY_SECONDS):
		start_kickoff()
		return
	replay_camera.current = true
	state = State.REPLAY


## Frame the goal at [param goal_z] from out on the pitch, above and off to one
## side.
##
## Rocket League watches its goals from behind the net, because its stadium is
## open back there and full of seats. This one is a closed box: everything
## beyond a back wall is either the inside of the goal or the void outside the
## arena, and a camera put there films the back of a wall. So the shot is taken
## from the playing side instead, looking back at the mouth.
##
## The camera hangs off a spring arm anchored at the goal rather than being
## placed outright, so if anything does come between the two it is pulled in
## until it can see again. That is the same thing [VehicleCamera] does to keep
## the chase camera out of walls, and a bare camera with nothing watching its
## line of sight is exactly how this came to be filming the outside of the
## stadium in the first place.
func _aim_replay_at(goal_z: float) -> void:
	var subject: Vector3 = Vector3(0.0, REPLAY_SUBJECT_HEIGHT, goal_z)
	# up, off to one side, and back toward the halfway line
	var offset: Vector3 = Vector3(REPLAY_OFFSET.x, REPLAY_OFFSET.y,
		-REPLAY_OFFSET.z * signf(goal_z))
	replay_pivot.global_position = subject
	# the arm runs along the pivot's own positive z, so the pivot is turned to
	# face the other way and the camera ends up looking back down it at the goal
	replay_pivot.look_at(subject - offset, Vector3.UP)
	replay_arm.spring_length = offset.length()


## Hold the camera where the spring arm put it, but turn it to keep the ball in
## the middle of the shot. The replay starts four seconds before the goal, when
## the ball was still out on the pitch, so a camera bolted to the goal mouth
## would open on an empty net and only catch the last of it.
func _track_replay() -> void:
	if not is_instance_valid(ball):
		return
	var at: Vector3 = ball.global_position
	var flat: Vector2 = Vector2(at.x - replay_camera.global_position.x,
		at.z - replay_camera.global_position.z)
	# straight overhead there is no heading to turn to, and look_at would fail
	if flat.length() < 1.0:
		return
	replay_camera.look_at(at, Vector3.UP)


func _on_replay_finished() -> void:
	start_kickoff()


func _on_countdown_finished() -> void:
	if state != State.COUNTDOWN:
		return
	state = State.PLAYING


## Build both teams and switch the AI on for everyone the player is not in.
func _spawn_teams() -> void:
	var scene: PackedScene = load("res://addons/gta/scenes/rocket_car.tscn") as PackedScene
	if scene == null:
		push_error("RocketMatch: rocket_car.tscn is missing.")
		return
	for team: RocketCar.Team in [RocketCar.Team.BLUE, RocketCar.Team.ORANGE]:
		var names: Array[String] = BLUE_NAMES if team == RocketCar.Team.BLUE else ORANGE_NAMES
		for i: int in team_size:
			var car: RocketCar = scene.instantiate() as RocketCar
			car.name = "%s%d" % ["Blue" if team == RocketCar.Team.BLUE else "Orange", i]
			car.team = team
			# the player takes the first blue car, so that one gets no AI
			var driven: bool = seat_player and team == RocketCar.Team.BLUE and i == 0
			# everything is set before the car enters the tree, the way
			# twisted_metal.gd builds its opponents, because both the car and
			# the brain read each other in their own _ready
			var brain: RocketAi = car.get_node_or_null(^"RocketAi") as RocketAi
			if brain != null:
				brain.enabled = not driven
				brain.skill = ai_skill
			car.is_ai = not driven
			if driven:
				player_car = car
			add_child(car)
			_paint(car, team, names[i % names.size()])
			cars.append(car)


## Team colour on the body, so the two sides can be told apart at a glance.
func _paint(car: RocketCar, team: RocketCar.Team, label: String) -> void:
	var body: MeshInstance3D = car.get_node_or_null(^"Body") as MeshInstance3D
	if body == null:
		return
	var paint: StandardMaterial3D = StandardMaterial3D.new()
	paint.albedo_color = RocketArena.BLUE if team == RocketCar.Team.BLUE else RocketArena.ORANGE
	paint.metallic = 0.35
	paint.roughness = 0.45
	body.material_override = paint
	car.set_meta(&"display_name", label)


func _place_on_kickoff(car: RocketCar, spot_index: int) -> void:
	var spot: Vector3 = RocketConst.KICKOFF_SPOTS[spot_index]
	var mirrored: float = 1.0 if car.team == RocketCar.Team.BLUE else -1.0
	car.place_at(
		RocketConst.to_godot(spot.x * mirrored, spot.y * mirrored, RocketConst.CAR_REST_HEIGHT),
		RocketConst.to_godot_yaw(spot.z) + (0.0 if car.team == RocketCar.Team.BLUE else PI))


## Anything that has fallen out of the world goes back into play, the way
## [code]twisted_metal.gd[/code] puts a lost car back on the roof.
func _recover_escapees() -> void:
	if ball.global_position.y < FELL_OUT_Y:
		ball.reset_to(CENTRE_SPOT)
	for car: RocketCar in cars:
		if is_instance_valid(car) and car.global_position.y < FELL_OUT_Y:
			_place_on_kickoff(car, 4)


## Hide the player at the wheel, the same way the Twisted Metal demo does: the
## Player is moved onto the car and mounted, and the car hides the driver model
## because a battle car has no cabin to put anyone in.
func _seat_the_player() -> void:
	var player: Player = get_node_or_null(^"Player") as Player
	if player == null or not is_instance_valid(player_car):
		return
	player.global_position = player_car.global_position
	player.mount(player_car)


## With [member seat_player] off the demo is an AI match to watch, and the
## Player has no part in it. Left alone they stand on the halfway line getting
## run over, so they are taken out of the way instead.
func _stand_the_player_down() -> void:
	var player: Player = get_node_or_null(^"Player") as Player
	if player == null:
		return
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_collision_layer_value(1, false)
	player.set_collision_mask_value(1, false)


## After a kickoff the Player has to be put back on the seat, or the mount
## drags them from wherever the last whistle left them.
func _reseat_player() -> void:
	var player: Player = get_node_or_null(^"Player") as Player
	if player == null or not is_instance_valid(player_car):
		return
	player.global_position = player_car.global_position


func _set_state(to: State) -> void:
	state = to
	# nobody drives during a countdown, a replay or after full time. Which car
	# belongs to the player is remembered here rather than read back off the
	# cars, because switching a brain off also clears that car's own flag and
	# the match would forget who it had to leave alone.
	var live: bool = to == State.PLAYING
	for car: RocketCar in cars:
		if not is_instance_valid(car):
			continue
		var brain: RocketAi = car.get_node_or_null(^"RocketAi") as RocketAi
		if brain != null:
			brain.enabled = live and car != player_car
		if not live:
			car.release_controls()
	state_changed.emit(state)
