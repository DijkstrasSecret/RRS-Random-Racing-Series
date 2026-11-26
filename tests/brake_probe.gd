extends SceneTree
## How hard each car can really stop: flat out down the start straight, then
## the brake pedal fully down (Arcade assists, wheel straight). Prints the
## average deceleration from the top speed reached down to 10 m/s, next to
## the deceleration the AI's speed plan assumes at a few skill levels.
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/brake_probe.gd -- [--cars=a,b] [--track=monza]


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	GameSettings.track = "monza"
	var cars := Array(CarRoster.ids())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cars="):
			cars = Array(a.get_slice("=", 1).split(","))
		elif a.begins_with("--track="):
			GameSettings.track = a.get_slice("=", 1)
	for id in cars:
		await _probe(String(id))
	quit()


func _probe(id: String) -> void:
	GameSettings.ai_count = 0
	GameSettings.laps = 1
	GameSettings.p1_car = id
	var scene := (load(GameSettings.RACE) as PackedScene).instantiate()
	var car := scene.get_node("Vehicle") as Vehicle
	var player := car.get_node("PlayerInput")
	car.remove_child(player)
	player.free()
	var inp := VehicleInput.new()
	car.add_child(inp)
	root.add_child(scene)
	current_scene = scene
	car.set_handling_profile(HandlingAssists.Profile.ARCADE)
	var race := scene.find_children("*", "RaceDirector", true, false)[0] as RaceDirector
	var start := Vector3.ZERO
	var braking := false
	var v0 := 0.0
	var t := 0.0
	var dist := 0.0
	var last := Vector3.ZERO
	while true:
		await physics_frame
		if race.state != RaceDirector.State.RACING:
			start = car.global_position
			last = start
			continue
		var v := car.forward_speed
		if not braking and (v > 30.0 or car.global_position.distance_to(start) > 210.0):
			braking = true
			v0 = v
		inp.throttle = 0.0 if braking else 1.0
		inp.brake = 1.0 if braking else 0.0
		inp.handbrake = 0.0
		inp.steer = 0.0
		if braking:
			t += 1.0 / 120.0
			dist += car.global_position.distance_to(last)
			if v < 10.0 or t > 8.0:
				break
		last = car.global_position
	var decel := (v0 - car.forward_speed) / maxf(t, 0.001)
	var grip := car.config.tire_grip * clampf(1.0 - (car.config.mass - 1300.0) / 9000.0, 0.85, 1.05) * 9.81
	print("%-9s mass %4.0f grip %.2f  %3.0f -> %2.0f km/h in %.2f s, %4.1f m: %.2f g   plan assumes %.2f g (skill .5) %.2f g (skill .95)" % [id, car.config.mass,
			car.config.tire_grip, v0 * 3.6, car.forward_speed * 3.6, t, dist, decel / 9.81, grip * lerpf(0.42, 0.58, 0.5) / 9.81, grip * lerpf(0.42, 0.58, 0.95) / 9.81])
	scene.queue_free()
	current_scene = null
	for i in 4:
		await process_frame
