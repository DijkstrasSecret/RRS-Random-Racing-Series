extends SceneTree
## Handling probe: scripted manoeuvres on a big flat test pad (well away from
## the circuit) for every car, like a gamepad player would drive them.
## - STEP: at 110 km/h, half stick held for 2.5 s: peak body slip, yaw overshoot.
## - FLICK: at 130 km/h, a quick half-stick left-right flick (lane change).
## - LIFT: steady corner at 100 km/h, then throttle off: extra slip.
## - EXIT: steady 60 km/h corner, then full throttle: slip, wheelspin, spin.
## - LAUNCH: full throttle from 30 km/h for 2.5 s: driven wheel slip.
## Prints one line per car. Spin = body slip over 25 degrees.
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/handling_probe.gd -- [--cars=a,b] [--profile=0]

const PAD_Y := 400.0
var _profile := 0


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var cars := CarRoster.ids()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cars="):
			cars = arg.get_slice("=", 1).split(",")
		elif arg.begins_with("--profile="):
			_profile = int(arg.get_slice("=", 1))
	GameSettings.handling_profile = _profile
	GameSettings.damage = 0
	GameSettings.tyre_wear = 0
	print("handling_probe  profile %s" % HandlingAssists.PROFILE_NAMES[_profile])
	print("%-10s %-2s %-4s | STEP slip  yaw-over | FLICK slip | LIFT +slip | EXIT slip  wheel-slip%% | LAUNCH wheel-slip%% | spins" % ["car", "cl", "drv"])
	for id in cars:
		await _probe(id)
	quit()


func _probe(id: String) -> void:
	GameSettings.p1_car = id
	var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
	var car := scene.get_node("Vehicle") as Vehicle
	var player := car.get_node("PlayerInput")
	car.remove_child(player)
	player.free()
	var inp := VehicleInput.new()
	car.add_child(inp)
	root.add_child(scene)
	current_scene = scene
	_add_pad(scene)
	await _ticks(30)
	car.input = inp
	var spins := 0
	# STEP
	await _settle(car, inp, 110.0 / 3.6)
	var r := await _hold(car, inp, 0.5, 1.0, 2.5)
	var step_slip: float = r.x
	var overshoot: float = r.y
	spins += int(r.z)
	# FLICK
	await _settle(car, inp, 130.0 / 3.6)
	var f1 := await _hold(car, inp, 0.5, 1.0, 0.35)
	var f2 := await _hold(car, inp, -0.5, 1.0, 0.45)
	var f3 := await _hold(car, inp, 0.0, 1.0, 1.5)
	var flick := maxf(f1.x, maxf(f2.x, f3.x))
	spins += int(f1.z or f2.z or f3.z)
	# LIFT
	await _settle(car, inp, 100.0 / 3.6)
	var steady := await _hold(car, inp, 0.35, 0.55, 1.5)
	var lift := await _hold(car, inp, 0.35, 0.0, 1.5)
	var lift_extra := lift.x - steady.w
	spins += int(lift.z)
	# EXIT
	await _settle(car, inp, 60.0 / 3.6)
	await _hold(car, inp, 0.45, 0.3, 1.2)
	var wheelspin := [0.0, 0]
	var ex := await _hold(car, inp, 0.45, 1.0, 2.0, wheelspin)
	spins += int(ex.z)
	var exit_spin := float(wheelspin[0]) / maxf(wheelspin[1], 1) * 100.0
	# LAUNCH
	await _settle(car, inp, 0.0)
	var ws2 := [0.0, 0]
	await _hold(car, inp, 0.0, 1.0, 2.5, ws2)
	var launch_spin := float(ws2[0]) / maxf(ws2[1], 1) * 100.0
	var entry := CarRoster.entry(id)
	print("%-10s %-2s %-4s | %5.1f°  %5.2f   | %6.1f°   | %+6.1f°   | %5.1f°  %5.0f  | %7.0f      | %d" % [id,
			CarRoster.TIER_NAMES[int(entry.tier)], ["FWD", "RWD", "AWD"][car.config.drive_type],
			step_slip, overshoot, flick, lift_extra, ex.x, exit_spin, launch_spin, spins])
	scene.queue_free()
	current_scene = null
	await _ticks(3)


## A big flat tarmac pad high above the circuit.
func _add_pad(scene: Node) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.set_meta(&"surface_grip", 1.0)
	body.set_meta(&"surface_drag", 0.0)
	body.set_meta(&"road", true)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 1, 4000)
	cs.shape = box
	body.add_child(cs)
	scene.add_child(body)
	body.global_position = Vector3(0, PAD_Y - 0.5, 0)


## Puts the car on the pad heading +X at `speed` and lets it run straight.
func _settle(car: Vehicle, inp: VehicleInput, speed: float) -> void:
	car.teleport(Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), Vector3(-1500, PAD_Y + 0.6, 0)))
	inp.steer = 0.0
	inp.throttle = 0.0
	inp.brake = 0.0
	await _ticks(20)
	car.linear_velocity = Vector3.RIGHT * speed
	for w in car.wheels:
		w.omega = speed / w.radius
	# Hold the speed for a moment (simple throttle P-control).
	for i in 120:
		inp.throttle = clampf((speed - car.forward_speed) * 0.5 + 0.35, 0.0, 1.0) if speed > 0.0 else 0.0
		inp.brake = 1.0 if speed <= 0.0 else 0.0
		await physics_frame
	inp.brake = 0.0


## Holds steer / throttle for `seconds`. Returns (peak |body slip| deg, yaw
## overshoot = peak / final yaw rate, spun 0/1, final |slip| deg). Optional
## `spin` [sum, count] collects driven-wheel slip > 0.25 frames.
func _hold(car: Vehicle, inp: VehicleInput, steer: float, throttle: float, seconds: float, spin: Array = []) -> Vector4:
	inp.steer = steer
	inp.throttle = throttle
	var peak := 0.0
	var peak_yaw := 0.0
	var last_yaw := 0.0
	var last_slip := 0.0
	var spun := false
	for i in int(seconds * 120.0):
		await physics_frame
		var v := car.linear_velocity
		var fwd := -car.global_basis.z
		var slip := rad_to_deg(absf(atan2(v.dot(car.global_basis.x), maxf(v.dot(fwd), 0.5)))) if v.length() > 3.0 else 0.0
		peak = maxf(peak, slip)
		last_slip = slip
		var yaw := absf(car.angular_velocity.y)
		peak_yaw = maxf(peak_yaw, yaw)
		last_yaw = yaw
		if slip > 25.0:
			spun = true
		if OS.get_environment("PROBE_TRACE") != "" and i % 12 == 0:
			print("      t%.1f yaw %.2f slip %.1f tc %.2f thr %.2f" % [i / 120.0, car.angular_velocity.y, slip, car.throttle_out, throttle])
		if not spin.is_empty():
			var worst := 0.0
			for w in car.driven_wheels:
				worst = maxf(worst, absf(w.slip_ratio))
			spin[1] = int(spin[1]) + 1
			spin[0] = float(spin[0]) + worst
	return Vector4(peak, peak_yaw / maxf(last_yaw, 0.01), 1.0 if spun else 0.0, last_slip)


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame
