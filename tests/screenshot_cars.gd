extends SceneTree
## In-game shots of chosen cars on the circuit, rendered with the game's
## look: a front and a rear three-quarter close-up on the grid, then a chase
## camera shot with the AI driving. No user input, settings file untouched.
## Run windowed with an override.cfg containing window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/screenshot_cars.gd -- --cars=a,b --prefix=after

const OUT := "user://screenshots"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var cars := PackedStringArray(["braxton", "atmaca", "bastion"])
	var prefix := "shot"
	var time_of_day := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cars="):
			cars = arg.get_slice("=", 1).split(",")
		elif arg.begins_with("--prefix="):
			prefix = arg.get_slice("=", 1)
		elif arg.begins_with("--time="):
			time_of_day = int(arg.get_slice("=", 1))
		elif arg.begins_with("--livery="):
			GameSettings.p1_livery = arg.get_slice("=", 1) == "1"
	GameSettings.track = "greenhill"
	GameSettings.time_of_day = time_of_day
	GameSettings.weather = 0
	for id in cars:
		GameSettings.p1_car = id
		var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
		var car := scene.get_node("Vehicle") as Vehicle
		var player := car.get_node("PlayerInput")
		car.remove_child(player)
		player.free()
		var ai := AIDriver.new()
		ai.skill = 0.7
		car.add_child(ai)
		root.add_child(scene)
		current_scene = scene
		car.controls_locked = true  # parked for the close-ups
		var hud := scene.get_node_or_null("HUDLayer") as CanvasLayer
		if hud:
			hud.visible = false
		await _wait(1.6)
		var chase := root.get_viewport().get_camera_3d()
		var cam := Camera3D.new()
		cam.fov = 40.0
		scene.add_child(cam)
		for shot: Array in [["front", Vector3(3.3, 1.05, -4.8)], ["rear", Vector3(-3.1, 1.35, 5.2)]]:
			cam.global_position = car.to_global(shot[1])
			cam.look_at(car.to_global(Vector3(0, 0.62, 0)), Vector3.UP)
			cam.make_current()
			await _wait(0.4)
			await _save("%s_game_%s_%s" % [prefix, id, shot[0]])
		chase.make_current()
		cam.queue_free()
		if hud:
			hud.visible = true
		car.controls_locked = false
		await _wait(7.0)
		await _save("%s_game_%s_chase" % [prefix, id])
		scene.queue_free()
		current_scene = null
		await process_frame
		await process_frame
	quit()


func _wait(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < seconds:
		await process_frame


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, shot_name])
	print("saved ", shot_name)
