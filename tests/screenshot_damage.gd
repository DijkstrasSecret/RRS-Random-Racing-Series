extends SceneTree
## Pictures of crash damage in the game: a car before, after a 100 km/h
## barrier hit plus a side hit (front / side close-ups), then a chase shot
## with the HUD damage outline while the AI drives it on. Settings untouched.
## Run windowed with an override.cfg containing window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/screenshot_damage.gd -- --cars=bavaro,quadra

const OUT := "user://screenshots"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var cars := PackedStringArray(["bavaro"])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cars="):
			cars = arg.get_slice("=", 1).split(",")
	GameSettings.track = "monza"
	GameSettings.time_of_day = 1
	GameSettings.weather = 0
	GameSettings.damage = 2
	for id in cars:
		GameSettings.p1_car = id
		var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
		var car := scene.get_node("Vehicle") as Vehicle
		var player := car.get_node("PlayerInput")
		car.remove_child(player)
		player.free()
		root.add_child(scene)
		current_scene = scene
		var circuit := scene.get_node("Circuit") as Circuit
		var hud := scene.get_node_or_null("HUDLayer") as CanvasLayer
		if hud:
			hud.visible = false
		await _wait(1.2)
		var off := 120.0
		var park := Transform3D(Basis.looking_at(circuit.direction_at(off), Vector3.UP), circuit.point_at(off) + Vector3.UP * 0.4)
		car.teleport(park)
		car.controls_locked = true
		await _wait(0.8)
		var chase := root.get_viewport().get_camera_3d()
		var cam := Camera3D.new()
		cam.fov = 40.0
		scene.add_child(cam)
		await _shots(car, cam, "%s_before" % id)
		chase.make_current()

		# Nose into the barrier, then the right side into it.
		var right := circuit.right_at(off)
		car.teleport(Transform3D(Basis.looking_at(right, Vector3.UP), circuit.point_at(off) + Vector3.UP * 0.4))
		await _ticks(30)
		car.linear_velocity = right * 100.0 / 3.6
		await _ticks(150)
		var off2 := off + 60.0
		car.teleport(Transform3D(Basis.looking_at(circuit.direction_at(off2), Vector3.UP), circuit.point_at(off2) + Vector3.UP * 0.4))
		await _ticks(30)
		car.linear_velocity = circuit.right_at(off2) * 70.0 / 3.6
		await _ticks(120)
		print("%s zones: %s" % [id, str(car.damage.zones)])
		car.teleport(park)
		await _wait(0.8)
		await _shots(car, cam, "%s_after" % id)

		# Drive on with the HUD: smoke, damage outline.
		chase.make_current()
		cam.queue_free()
		if hud:
			hud.visible = true
		var ai := AIDriver.new()
		ai.skill = 0.7
		car.add_child(ai)
		car.input = ai  # added after the car was ready: hook it up by hand
		car.controls_locked = false
		await _wait(6.0)
		await _save("%s_after_chase" % id)
		scene.queue_free()
		current_scene = null
		await process_frame
		await process_frame
	quit()


func _shots(car: Vehicle, cam: Camera3D, prefix: String) -> void:
	for shot: Array in [["front", Vector3(3.3, 1.2, -4.8)], ["side", Vector3(5.6, 1.3, 0.6)]]:
		cam.global_position = car.to_global(shot[1])
		cam.look_at(car.to_global(Vector3(0, 0.62, 0)), Vector3.UP)
		cam.make_current()
		await _wait(0.4)
		await _save("%s_%s" % [prefix, shot[0]])


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _wait(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < seconds:
		await process_frame


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, shot_name])
	print("saved ", shot_name)
