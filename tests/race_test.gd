extends Node
## Race smoke test: runs a full race with every car driven by an AIDriver
## (the players' cars too). Checks the countdown holds the field, the race
## finishes, prints the results, AI resets and whether the dirt effect ran.
## Run without a window:
##   Godot_console.exe --headless --fixed-fps 120 --path . res://tests/race_test.tscn
## Options:  -- --laps=N (default 2)  --scene=versus_race | circuit_race  --track=<id>

var _scene: Node
var _race: RaceDirector
var _t := 0.0
var _moved_in_countdown := 0.0
var _dirt_seen := false
var _laps := 2
var _scene_name := "versus_race"
var _started := false


func _ready() -> void:
	GameSettings.use_defaults()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--laps="):
			_laps = int(arg.get_slice("=", 1))
		if arg.begins_with("--scene="):
			_scene_name = arg.get_slice("=", 1)
		if arg.begins_with("--track="):
			GameSettings.track = arg.get_slice("=", 1)
	_scene = load("res://scenes/modes/%s.tscn" % _scene_name).instantiate()
	_race = _scene.get_node("RaceLayer/RaceDirector")
	_race.use_game_settings = false
	_race.laps = _laps
	# Replace the human players with AI drivers.
	for node in _scene.get_children():
		if node is Vehicle:
			var player := node.get_node_or_null("PlayerInput")
			if player:
				node.remove_child(player)
				player.free()
				var ai := AIDriver.new()
				ai.name = "AIDriver"
				ai.skill = 0.75
				node.add_child(ai)
	add_child(_scene)
	print("race_test | %s | %s | %d lap(s)" % [_scene_name, GameSettings.track, _laps])


func _physics_process(delta: float) -> void:
	_t += delta
	if _race.state == RaceDirector.State.COUNTDOWN:
		_started = true
		for i in _race.car_count():
			var v := _race.vehicle_at(i).linear_velocity
			_moved_in_countdown = maxf(_moved_in_countdown, Vector2(v.x, v.z).length())
	for i in _race.car_count():
		for w in _race.vehicle_at(i).wheels:
			if w._dirt and w._dirt._chunks.emitting:
				_dirt_seen = true
	var all_done := _race.car_count() > 0 and _race.finish_order.size() == _race.car_count()
	# Allow ~1 minute per kilometre per lap (+ the countdown).
	var circuit := get_tree().get_first_node_in_group("circuit") as Circuit
	var per_lap := maxf(120.0, circuit.length / 1000.0 * 60.0) if circuit else 120.0
	if all_done or _t > 10.0 + per_lap * _laps:
		print("  cars in race           %d" % _race.car_count())
		print("  countdown held cars    %s (max rolling speed %.2f m/s)" % [str(_started and _moved_in_countdown < 0.6), _moved_in_countdown])
		print("  everyone finished      %s" % str(all_done))
		for i in _race.standings():
			var car := _race.vehicle_at(i)
			var ai := car.get_node_or_null("AIDriver") as AIDriver
			var time := LapTimer.format_time(_race.finish_times[i]) if _race.finish_times.has(i) else "DNF"
			print("  %-4s %-9s %-22s %s   skill %.2f  resets %d  damage %.2f" % [RaceDirector.ordinal(_race.position_of(i)),
				_race.name_at(i), car.config.display_name, time, ai.skill if ai else 0.0, ai.resets if ai else 0,
				car.damage.total() if car.damage else -1.0])
		print("  dirt effect seen       %s" % str(_dirt_seen))
		print("race_test done, %.1f s sim time" % _t)
		set_physics_process(false)
		get_tree().quit()
