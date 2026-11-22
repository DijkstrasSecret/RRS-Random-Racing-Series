extends SceneTree
## Frame rate check: a full race (AI in every car) at different times of day,
## rendered in a real window. Prints average and worst frame times.
## Run windowed with an override.cfg containing window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/fps_test.gd

const RUNS := [["monza", 2], ["spa", 3], ["spa", 1]]


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	for run: Array in RUNS:
		GameSettings.track = run[0]
		GameSettings.time_of_day = run[1]
		var scene := (load("res://scenes/modes/circuit_race.tscn") as PackedScene).instantiate()
		var car := scene.get_node("Vehicle") as Vehicle
		var player := car.get_node("PlayerInput")
		car.remove_child(player)
		player.free()
		car.add_child(AIDriver.new())
		root.add_child(scene)
		current_scene = scene
		for i in 240:
			await process_frame
		var frames := 0
		var worst := 0.0
		var start := Time.get_ticks_usec()
		var last := start
		while Time.get_ticks_usec() - start < 12_000_000:
			await process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			last = now
			frames += 1
		var avg_ms := (Time.get_ticks_usec() - start) / 1000.0 / frames
		print("fps %s %s: %.0f fps avg (%.1f ms), worst frame %.1f ms" % [run[0],
				GameSettings.TIME_NAMES[run[1]], 1000.0 / avg_ms, avg_ms, worst])
		scene.queue_free()
		current_scene = null
		await process_frame
	quit()
