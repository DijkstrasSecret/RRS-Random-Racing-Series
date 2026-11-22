extends Node
## Versus race smoke test: two AIDrivers race in the real split-screen scene.
## Checks the countdown holds the cars, the race finishes with a winner and
## the off-road dirt effect switches on. Run without a window:
##   Godot_console.exe --headless --fixed-fps 120 --path . res://tests/race_test.tscn
## Optional: -- --laps=N  (default 1)

var _scene: Node
var _race: RaceDirector
var _cars: Array[Vehicle] = []
var _t := 0.0
var _moved_in_countdown := 0.0
var _dirt_seen := false
var _laps := 1


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--laps="):
			_laps = int(arg.get_slice("=", 1))
	_scene = load("res://scenes/modes/versus_race.tscn").instantiate()
	_race = _scene.get_node("RaceLayer/RaceDirector")
	_race.laps = _laps
	for car_name: String in ["Car1", "Car2"]:
		var car: Vehicle = _scene.get_node(car_name)
		var player := car.get_node("PlayerInput")
		car.remove_child(player)
		player.free()
		var ai := AIDriver.new()
		ai.name = "AIDriver"
		# Make the second driver a little more careful so the race has a winner.
		if car_name == "Car2":
			ai.cornering_g = 0.62
		car.add_child(ai)
		_cars.append(car)
	add_child(_scene)
	print("race_test | %d lap(s)" % _laps)


func _physics_process(delta: float) -> void:
	_t += delta
	if _race.state == RaceDirector.State.COUNTDOWN:
		for car in _cars:
			_moved_in_countdown = maxf(_moved_in_countdown, car.linear_velocity.length())
	for car in _cars:
		for w in car.wheels:
			if w._dirt and w._dirt._chunks.emitting:
				_dirt_seen = true
	if _race.state == RaceDirector.State.FINISHED or _t > 200.0 * _laps:
		print("  countdown held cars    %s (max speed %.2f m/s)" % [str(_moved_in_countdown < 0.5), _moved_in_countdown])
		print("  race finished          %s" % str(_race.state == RaceDirector.State.FINISHED))
		for place in _race.finish_order.size():
			var i: int = _race.finish_order[place]
			print("  %s %s  %s" % [RaceDirector.ordinal(place + 1), _race.player_names[i], LapTimer.format_time(_race.finish_times[i])])
		print("  dirt effect seen       %s" % str(_dirt_seen))
		print("race_test done, %.1f s sim time" % _t)
		set_physics_process(false)
		get_tree().quit()
