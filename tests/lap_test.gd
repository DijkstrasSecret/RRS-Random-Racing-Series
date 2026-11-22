extends Node
## Circuit smoke test: the AIDriver drives the PSX hatch round the circuit.
## Checks the track is drivable and lap timing works. Run without a window:
##   Godot_console.exe --headless --fixed-fps 120 --path . res://tests/lap_test.tscn
## Optional: -- --laps=2

var _scene: Node
var _car: Vehicle
var _timer: LapTimer
var _circuit: Circuit
var _ai: AIDriver
var _t := 0.0
var _off_track_time := 0.0
var _max_centre := 0.0
var _top_speed := 0.0
var _laps_wanted := 2
var _laps: Array[float] = []
var _last_kmh := 0.0
var _hits: Array[String] = []
var _min_up := 1.0
var _trace_from := 0.0
var _trace_to := 150.0
var _trace_step := 1.0


func _ready() -> void:
	GameSettings.use_defaults()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trace="):
			var parts := arg.get_slice("=", 1).split(",")
			_trace_from = float(parts[0])
			_trace_to = float(parts[1])
			_trace_step = float(parts[2]) if parts.size() > 2 else 0.25
		if arg.begins_with("--laps="):
			_laps_wanted = int(arg.get_slice("=", 1))
	_scene = load("res://scenes/modes/circuit_practice.tscn").instantiate()
	_car = _scene.get_node("Vehicle")
	var player := _car.get_node("PlayerInput")
	_car.remove_child(player)
	player.free()
	_ai = AIDriver.new()
	_ai.name = "AIDriver"
	_car.add_child(_ai)
	add_child(_scene)
	_timer = _scene.get_node("LapTimer")
	_circuit = _scene.get_node("Circuit")
	_timer.lap_completed.connect(func(time: float, _best: bool) -> void:
		_laps.append(time)
		print("  lap %d: %s" % [_laps.size(), LapTimer.format_time(time)]))
	print("lap_test | %s | %.0f m | car: %s" % [_circuit.track_name, _circuit.length, _car.config.display_name])


func _physics_process(delta: float) -> void:
	_t += delta
	var kmh := absf(_car.forward_speed) * 3.6
	_top_speed = maxf(_top_speed, kmh)
	_min_up = minf(_min_up, _car.global_basis.y.y)
	if _car.off_track:
		_off_track_time += delta
	if _t > 2.0:
		_max_centre = maxf(_max_centre, _circuit.distance_from_centre(_car.global_position))
		if _last_kmh - kmh > 25.0:
			_hits.append("lost %.0f km/h at %s" % [_last_kmh - kmh, _car.global_position.snapped(Vector3.ONE)])
	_last_kmh = kmh
	if OS.get_cmdline_user_args().has("--verbose") and fmod(_t, _trace_step) < delta and _t > _trace_from and _t < _trace_to:
		var off := _circuit.progress_at(_car.global_position)
		var beta := rad_to_deg(atan2(_car.lateral_speed, maxf(absf(_car.forward_speed), 0.5)))
		print("  t%.1f off %.0f dc %.1f v %+.0f tgt %.0f steer %+.2f thr %.2f brk %.2f beta %+.0f yaw %+.2f g%s whl %s" % [
			_t, off, _circuit.distance_from_centre(_car.global_position),
			_car.forward_speed * 3.6, _ai.target_speed * 3.6,
			_ai.steer, _ai.throttle, _ai.brake, beta, _car.angular_velocity.y, _car.drivetrain.gear_label(),
			"".join(_car.wheels.map(func(w): return "%.0f " % (w.grip_usage * 100.0)))])
	if _laps.size() >= _laps_wanted or _t > 150.0 * _laps_wanted:
		print("  laps completed        %d / %d" % [_laps.size(), _laps_wanted])
		print("  top speed             %.0f km/h" % _top_speed)
		print("  time off track        %.1f s" % _off_track_time)
		print("  max distance from line %.1f m (road half-width %.1f)" % [_max_centre, _circuit.road_width * 0.5])
		print("  stayed upright        %s (min up %.2f)" % [str(_min_up > 0.5), _min_up])
		print("  AI resets             %d" % _ai.resets)
		print("  big speed losses      %s" % (", ".join(_hits) if _hits.size() > 0 else "none"))
		print("lap_test done, %.1f s sim time" % _t)
		set_physics_process(false)
		get_tree().quit()
