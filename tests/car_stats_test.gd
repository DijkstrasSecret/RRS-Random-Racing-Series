extends Node
## Measures every roster car on flat ground: 0-100 / 0-200 km/h, standing
## kilometre (time and speed) and braking 100-0 km/h. Run without a window:
##   Godot_console.exe --headless --fixed-fps 120 --path . res://tests/car_stats_test.tscn
## Options: -- --car=<id> (one car only)

class Driver extends VehicleInput:
	var target_dir := Vector3.FORWARD
	var full_throttle := true
	var full_brake := false
	func poll(_d: float) -> void:
		var car := get_parent() as Vehicle
		var fwd := -car.global_basis.z
		fwd.y = 0.0
		var err := fwd.normalized().signed_angle_to(target_dir, Vector3.UP)
		steer = clampf(-err * 3.0, -0.4, 0.4)
		throttle = 1.0 if full_throttle else 0.0
		brake = 1.0 if full_brake else 0.0

var _ids: PackedStringArray
var _index := -1
var _car: Vehicle
var _driver: Driver
var _track: Node
var _phase := ""
var _t := 0.0
var _start := Vector3.ZERO
var _row := {}
var _dir := Vector3(1, 0, -1).normalized()
var _min_up := 1.0


func _ready() -> void:
	GameSettings.use_defaults()
	_ids = CarRoster.ids()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--car="):
			_ids = PackedStringArray([arg.get_slice("=", 1)])
	_track = load("res://scenes/tracks/test_track.tscn").instantiate()
	add_child(_track)
	print("car_stats_test | %d car(s)" % _ids.size())
	print("  %-10s %7s %7s %10s %9s %9s %8s" % ["car", "0-100", "0-200", "1km time", "1km km/h", "100-0 m", "upright"])
	_next_car()


func _next_car() -> void:
	if _car:
		_car.queue_free()
	_index += 1
	if _index >= _ids.size():
		print("car_stats_test done")
		get_tree().quit()
		return
	var id := _ids[_index]
	_car = load("res://scenes/vehicle/vehicle.tscn").instantiate()
	var player := _car.get_node("PlayerInput")
	_car.remove_child(player)
	player.free()
	CarRoster.apply(_car, id)
	_driver = Driver.new()
	_driver.target_dir = _dir
	_car.add_child(_driver)
	add_child(_car)
	_car.teleport(Transform3D(Basis.looking_at(_dir, Vector3.UP), Vector3(-540, 0.05, 540)))
	_row = {"id": id, "0-100": -1.0, "0-200": -1.0}
	_min_up = 1.0
	_phase = "settle"
	_t = 0.0


func _physics_process(delta: float) -> void:
	if _car == null:
		return
	_t += delta
	_min_up = minf(_min_up, _car.global_basis.y.y)
	var kmh := _car.forward_speed * 3.6
	match _phase:
		"settle":
			_driver.full_throttle = false
			if _t > 1.0:
				_phase = "run"
				_t = 0.0
				_start = _car.global_position
				_driver.full_throttle = true
		"run":
			if kmh >= 100.0 and _row["0-100"] < 0.0:
				_row["0-100"] = _t
			if kmh >= 200.0 and _row["0-200"] < 0.0:
				_row["0-200"] = _t
			if _car.global_position.distance_to(_start) >= 1000.0 or _t > 90.0:
				_row["km_time"] = _t
				_row["km_speed"] = kmh
				# Braking: line up at exactly 100 km/h and stop.
				_car.teleport(Transform3D(Basis.looking_at(_dir, Vector3.UP), Vector3(-540, 0.05, 540)))
				_car.linear_velocity = _dir * (100.0 / 3.6)
				for w in _car.wheels:
					w.omega = 100.0 / 3.6 / w.radius
				_driver.full_throttle = false
				_driver.full_brake = true
				_start = _car.global_position
				_phase = "brake"
				_t = 0.0
		"brake":
			if absf(_car.forward_speed) < 0.3 or _t > 15.0:
				_row["brake_m"] = _car.global_position.distance_to(_start)
				print("  %-10s %6.2fs %6.2fs %9.2fs %9.0f %9.1f %8s" % [_row.id,
					_row["0-100"], _row["0-200"], _row.km_time, _row.km_speed, _row.brake_m, str(_min_up > 0.5)])
				_phase = ""
				_next_car.call_deferred()
