extends "res://tests/handling_probe.gd"
## Corner power: full throttle held in a steady corner (60 and 100 km/h
## entry, half / third stick) on the flat pad. Reports how much of the
## throttle reaches the engine (after traction control and stability
## control), how much each of them took, the inside / outside driven wheel
## slip, and the speed gained.
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/corner_power_probe.gd -- [--cars=a,b] [--profile=0]


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
	var line := "%-10s %-3s" % [id, ["FWD", "RWD", "AWD"][car.config.drive_type]]
	for setup: Array in [[60.0, 0.5], [100.0, 0.33]]:
		await _settle(car, inp, setup[0] / 3.6)
		inp.steer = setup[1]
		inp.throttle = 0.4
		for i in 60:
			await physics_frame
		inp.throttle = 1.0
		var v0 := car.forward_speed
		var out := 0.0
		var tc := 0.0
		var esc := 0.0
		var slip_in := 0.0
		var slip_out := 0.0
		var n := 0
		for i in 180:
			await physics_frame
			n += 1
			out += car.throttle_out
			var beta := atan2(car.lateral_speed, maxf(absf(car.forward_speed), 0.5))
			esc += car.assists.oversteer_cut(beta, car.forward_speed)
			var ws := car.driven_wheels
			# Inside wheel = the less loaded one.
			var a: Wheel = ws[0]
			var b: Wheel = ws[1] if ws.size() > 1 else ws[0]
			if a.tire_load > b.tire_load:
				var t := a
				a = b
				b = t
			slip_in += absf(a.slip_ratio)
			slip_out += absf(b.slip_ratio)
		var esc_avg := esc / n
		var out_avg := out / n
		line += " | %3.0f km/h: power %3.0f%% (TC %3.0f%%, ESC %3.0f%%) slip in %.2f out %.2f, +%4.1f km/h" % [setup[0],
				out_avg * 100.0, (out_avg / maxf(esc_avg, 0.01)) * 100.0, esc_avg * 100.0, slip_in / n, slip_out / n,
				(car.forward_speed - v0) * 3.6]
	print(line)
	scene.queue_free()
	current_scene = null
	await _ticks(3)
