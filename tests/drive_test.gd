extends Node3D
## Handling smoke test (design concept §6.4 feel targets). Drives the car with
## scripted inputs and prints the results. Run it without a window:
##   Godot_console.exe --headless --path . res://tests/drive_test.tscn
## Optional: add  -- --profile=0  (Arcade), 1 (Sport, default) or 2 (Sim).

class ScriptedInput extends VehicleInput:
	pass

var vehicle: Vehicle
var drv: ScriptedInput
var phase := "settle"
var t := 0.0
var phase_t := 0.0
var results: Dictionary = {}
var _brake_start := Vector3.ZERO
var _max_lat_g := 0.0
var _min_up := 1.0
var _spring_sum := 0.0
var _last_kmh := 0.0
var _air_time := 0.0
var _max_height := 0.0
var _takeoff_kmh := -1.0
var _teleported := false


func _ready() -> void:
	add_child(load("res://scenes/tracks/test_track.tscn").instantiate())
	vehicle = load("res://scenes/vehicle/vehicle.tscn").instantiate()
	var player := vehicle.get_node("PlayerInput")
	vehicle.remove_child(player)
	player.free()
	drv = ScriptedInput.new()
	vehicle.add_child(drv)
	vehicle.position = Vector3(0.0, 0.05, 0.0)
	add_child(vehicle)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):
			vehicle.set_handling_profile(int(arg.get_slice("=", 1)))
	print("drive_test | profile: %s" % vehicle.assists.profile_name())


func _physics_process(delta: float) -> void:
	t += delta
	phase_t += delta
	var kmh := vehicle.forward_speed * 3.6
	_min_up = minf(_min_up, vehicle.global_basis.y.y)
	if OS.get_cmdline_user_args().has("--verbose") and fmod(phase_t, 0.5) < delta:
		var fl := vehicle.front_wheels[0]
		var rl := vehicle.rear_wheels[0]
		print("  [%s %4.1fs] %5.1f km/h  g%s %4.0f rpm  thr %.2f  brk %.2f  FL slip %+.2f load %.1f  RL slip %+.2f load %.1f  susp %.0f%%/%.0f%%  pos %s" % [
			phase, phase_t, kmh, vehicle.drivetrain.gear_label(), vehicle.drivetrain.rpm,
			vehicle.throttle_out, vehicle.brake_out, fl.slip_ratio, fl.tire_load / 1000.0,
			rl.slip_ratio, rl.tire_load / 1000.0, fl.compression_ratio() * 100.0, rl.compression_ratio() * 100.0, vehicle.global_position.snapped(Vector3.ONE * 0.1)])
	if OS.get_cmdline_user_args().has("--trace") and fmod(phase_t, 0.1) < delta:
		var parts := PackedStringArray()
		for w in vehicle.wheels:
			parts.append("%s fx%+5.0f fy%+5.0f L%4.0f g%d" % [String(w.name).trim_prefix("Wheel"),
				w.force_long, w.force_lat, w.tire_load, int(w.grounded)])
		print("  t%.3f st%+5.1f v%5.1f lat%+5.2f yaw%+5.2f lv%s | %s" % [phase_t, rad_to_deg(vehicle.steer_angle), kmh, vehicle.lateral_speed,
			vehicle.angular_velocity.y, vehicle.linear_velocity.snapped(Vector3.ONE * 0.01), " | ".join(parts)])
	match phase:
		"settle":
			if phase_t > 1.5:
				for w in vehicle.wheels:
					_spring_sum += w.compression_ratio()
				results["static_compression_avg"] = "%.0f %%" % (_spring_sum / 4.0 * 100.0)
				results["static_load_FL_RL_kN"] = "%.2f / %.2f" % [
					vehicle.front_wheels[0].tire_load / 1000.0, vehicle.rear_wheels[0].tire_load / 1000.0]
				_next("accelerate")
		"accelerate":
			drv.throttle = 1.0
			if kmh >= 100.0 and not results.has("0_100_kmh_s"):
				results["0_100_kmh_s"] = "%.2f" % phase_t
			if phase_t > 14.0:
				results["speed_after_14s_kmh"] = "%.0f (gear %s)" % [kmh, vehicle.drivetrain.gear_label()]
				drv.throttle = 0.0
				_brake_start = vehicle.global_position
				results["brake_from_kmh"] = "%.0f" % kmh
				_next("brake")
		"brake":
			drv.brake = 1.0
			if absf(vehicle.forward_speed) < 0.5 or phase_t > 15.0:
				results["braking_distance_m"] = "%.1f" % vehicle.global_position.distance_to(_brake_start)
				results["braking_time_s"] = "%.2f" % phase_t
				drv.brake = 0.0
				_next("turn")
		"turn":
			drv.throttle = 0.45 if vehicle.forward_speed < 16.0 else 0.0
			drv.steer = 1.0
			if phase_t > 4.0:
				_max_lat_g = maxf(_max_lat_g, absf(vehicle.g_lat))
			if phase_t > 10.0:
				results["turn_max_lateral_g"] = "%.2f" % _max_lat_g
				results["turn_speed_kmh"] = "%.0f" % kmh
				drv.throttle = 0.0
				drv.steer = 0.0
				_next("reverse")
		"reverse":
			drv.brake = 1.0
			if phase_t > 4.0:
				results["reverse_speed_kmh"] = "%.1f (gear %s)" % [kmh, vehicle.drivetrain.gear_label()]
				drv.brake = 0.0
				# Line up 100 m before the table-top jump (ramp starts at z = -250).
				vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(70.0, 0.05, -150.0)))
				_teleported = true
				_next("jump")
		"jump":
			drv.throttle = 1.0
			drv.steer = 0.0
			if vehicle.airborne:
				_air_time += delta
				_max_height = maxf(_max_height, vehicle.global_position.y)
				if _takeoff_kmh < 0.0:
					_takeoff_kmh = kmh
			if vehicle.global_position.z < -340.0 or phase_t > 15.0:
				results["jump_takeoff_kmh"] = "%.0f" % _takeoff_kmh
				results["jump_air_time_s"] = "%.2f" % _air_time
				results["jump_max_height_m"] = "%.1f" % _max_height
				results["jump_exit_kmh"] = "%.0f" % kmh
				_finish()

	# A sudden big speed loss means the car hit something.
	if _teleported:
		_teleported = false
		_last_kmh = 0.0
		return
	if phase != "settle" and _last_kmh - absf(kmh) > 15.0:
		results["collision_%s_%.1fs" % [phase, phase_t]] = "lost %.0f km/h at %s" % [
			_last_kmh - absf(kmh), vehicle.global_position.snapped(Vector3.ONE)]
	_last_kmh = absf(kmh)


func _next(p: String) -> void:
	phase = p
	phase_t = 0.0


func _finish() -> void:
	results["stayed_upright"] = str(_min_up > 0.5)
	results["min_up_dot"] = "%.2f" % _min_up
	for k: String in results:
		print("  %-24s %s" % [k, results[k]])
	print("drive_test done in %.1f s sim time" % t)
	set_physics_process(false)
	get_tree().quit()
