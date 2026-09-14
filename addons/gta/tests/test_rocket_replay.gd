extends GutTest

## Purpose: the goal replay records a fixed window of the past, plays it back as
## it happened rather than re-simulating it, and hands the bodies back to the
## physics world afterwards.
##
## The ring buffer is the thing to get wrong, because it only misbehaves once it
## has wrapped, which in a real match is after six seconds and in a test needs
## forcing. These tests fill it past its own length on purpose.

var replay: RocketReplay
var one: Node3D
var two: Node3D


func before_each() -> void:
	replay = RocketReplay.new()
	add_child_autofree(replay)
	one = Node3D.new()
	two = Node3D.new()
	add_child_autofree(one)
	add_child_autofree(two)
	replay.track([one, two] as Array[Node3D])


func test_a_fresh_buffer_has_nothing_to_play() -> void:
	assert_false(replay.play(), "There is nothing recorded yet, so a goal skips the replay")
	assert_false(replay.is_playing)


func test_it_plays_once_there_is_something_recorded() -> void:
	for i: int in 30:
		one.position = Vector3(float(i), 0.0, 0.0)
		replay.record()
	assert_true(replay.play(0.5))
	assert_true(replay.is_playing)


func test_recording_stops_while_a_replay_is_running() -> void:
	for i: int in 30:
		one.position = Vector3(float(i), 0.0, 0.0)
		replay.record()
	replay.play(0.5)
	var before: int = replay._filled
	replay.record()
	assert_eq(replay._filled, before, "A replay must not record itself")


func test_playback_puts_the_bodies_where_they_were() -> void:
	for i: int in 30:
		one.position = Vector3(float(i), 0.0, 0.0)
		two.position = Vector3(0.0, float(i), 0.0)
		replay.record()
	# move them somewhere else entirely, the way a goal would
	one.position = Vector3(999.0, 999.0, 999.0)
	two.position = Vector3(-999.0, -999.0, -999.0)
	replay.play(0.5)
	replay._apply(0)
	assert_ne(one.position.x, 999.0, "The replay overrides where the body is now")
	assert_lt(one.position.x, 30.0, "And puts it somewhere it actually was")


func test_the_buffer_wraps_instead_of_growing() -> void:
	for i: int in RocketReplay.FRAMES * 2:
		one.position = Vector3(float(i), 0.0, 0.0)
		replay.record()
	assert_eq(replay._filled, RocketReplay.FRAMES,
		"The cost of the recording is flat however long the match runs")


func test_a_wrapped_buffer_plays_the_most_recent_window() -> void:
	# fill it twice over, so the oldest frames have been overwritten
	var total: int = RocketReplay.FRAMES * 2
	for i: int in total:
		one.position = Vector3(float(i), 0.0, 0.0)
		replay.record()
	replay.play(RocketReplay.SECONDS)
	replay._apply(replay._play_length - 1)
	assert_almost_eq(one.position.x, float(total - 1), 1.0,
		"The end of the window is the last thing recorded, not the first")


func test_the_bodies_come_back_to_the_physics_world_afterwards() -> void:
	for i: int in 30:
		one.position = Vector3(float(i), 0.0, 0.0)
		replay.record()
	replay.play(0.5)
	assert_eq(one.process_mode, Node.PROCESS_MODE_DISABLED, "Nothing simulates during a replay")
	replay.stop()
	assert_eq(one.process_mode, Node.PROCESS_MODE_INHERIT, "And everything runs again after it")


func test_stopping_a_replay_that_is_not_running_does_nothing() -> void:
	replay.stop()
	assert_false(replay.is_playing)


func test_it_says_when_it_has_finished_so_the_kickoff_can_follow() -> void:
	for i: int in 30:
		one.position = Vector3(float(i), 0.0, 0.0)
		replay.record()
	watch_signals(replay)
	replay.play(0.1)
	# run it past its own length at the playback speed
	for _i: int in 60:
		replay._physics_process(1.0 / 60.0)
	assert_signal_emitted(replay, "finished")
	assert_false(replay.is_playing)


func test_asking_for_more_than_was_recorded_plays_what_there_is() -> void:
	for i: int in 20:
		one.position = Vector3(float(i), 0.0, 0.0)
		replay.record()
	replay.play(RocketReplay.SECONDS)
	assert_eq(replay._play_length, 20, "It cannot show a past it never saw")
