class_name RocketLeagueUi
extends CanvasLayer
## The scoreboard, the clock, the boost meter and the banner that announces a
## goal.
##
## It reads nothing. Every number on screen arrives through a signal that is
## connected in [code]rocket_league.tscn[/code]: the match emits a score, a
## clock and a state, the player's car emits its boost. Polling the match every
## frame for a clock that changes once a second would be the wrong shape, and
## the addon's rules say so.

const GOAL_BANNER_SECONDS: float = 2.0

@onready var blue_score: Label = %BlueScore
@onready var orange_score: Label = %OrangeScore
@onready var clock_label: Label = %Clock
@onready var boost_label: Label = %BoostAmount
@onready var boost_bar: ProgressBar = %BoostBar
@onready var banner: Label = %Banner
@onready var hint: Label = %Hint
@onready var ball_cam: Label = %BallCam

var _ball_cam_on: bool = false ## What the car last said; the label also needs the game to be live.
var _is_playing: bool = false
@onready var banner_timer: Timer = $BannerTimer


func _ready() -> void:
	banner.text = ""
	boost_bar.max_value = RocketConst.BOOST_MAX
	banner_timer.timeout.connect(func() -> void: banner.text = "")


## Follow one car's tank. The match calls this once the player has a car,
## because which car that is is not known until the teams are built.
func watch(car: RocketCar) -> void:
	if not is_instance_valid(car):
		return
	car.boost_changed.connect(_on_boost_changed)
	car.ball_cam_changed.connect(_on_ball_cam_changed)
	_on_boost_changed(car.boost, RocketConst.BOOST_MAX)
	_on_ball_cam_changed(car.is_ball_cam)


func _on_score_changed(blue: int, orange: int) -> void:
	blue_score.text = str(blue)
	orange_score.text = str(orange)


## The clock counts down in regulation and up in overtime, and the match sends
## whichever it is; this only has to format it.
func _on_clock_changed(seconds: float) -> void:
	var whole: int = int(ceilf(seconds))
	clock_label.text = "%d:%02d" % [whole / 60, whole % 60]


func _on_state_changed(state: RocketMatch.State) -> void:
	# the indicator says what the camera behind the car is doing, and during a
	# replay or a countdown that is not the camera anybody is looking through
	_is_playing = state == RocketMatch.State.PLAYING
	_refresh_ball_cam()
	match state:
		RocketMatch.State.COUNTDOWN:
			banner_timer.stop()
			banner.text = "Kickoff"
		RocketMatch.State.PLAYING:
			banner.text = ""
		RocketMatch.State.REPLAY:
			banner.text = "Goal"
		RocketMatch.State.OVER:
			banner_timer.stop()
			banner.text = "Full Time"


func _on_goal_scored(team: RocketCar.Team, scorer: RocketCar) -> void:
	var side: String = "Blue" if team == RocketCar.Team.BLUE else "Orange"
	var who: String = ""
	if is_instance_valid(scorer) and scorer.has_meta(&"display_name"):
		who = " - %s" % scorer.get_meta(&"display_name")
	banner.text = "%s Goal%s" % [side, who]
	banner_timer.start(GOAL_BANNER_SECONDS)


func _on_match_ended(winner: RocketCar.Team, tied: bool) -> void:
	if tied:
		banner.text = "Draw"
		return
	banner.text = "%s Wins" % ["Blue" if winner == RocketCar.Team.BLUE else "Orange"]


func _on_boost_changed(amount: float, maximum: float) -> void:
	boost_bar.max_value = maximum
	boost_bar.value = amount
	boost_label.text = str(int(amount))


## Rocket League shows nothing at all when ball cam is off, because that is the
## state you can see for yourself, so this only marks the locked one.
func _on_ball_cam_changed(on: bool) -> void:
	_ball_cam_on = on
	_refresh_ball_cam()


func _refresh_ball_cam() -> void:
	ball_cam.visible = _ball_cam_on and _is_playing
