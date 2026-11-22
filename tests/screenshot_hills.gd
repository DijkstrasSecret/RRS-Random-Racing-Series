extends SceneTree
## Pictures of a track's hills: for each lap fraction, a camera by the road
## looking up the track (a car parked a little ahead for scale).
## Run windowed with an override.cfg containing window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/screenshot_hills.gd -- --track=spa --at=0.08,0.2,0.6
## --side: from 110 m to the side, so the climb shows in profile.
## --high: from high up and far out, over the valley.
## --chase: the car drives (AI) from the spot; chase camera shot 3 s later.

const OUT := "user://screenshots"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var track := "spa"
	var spots := PackedFloat32Array([0.08, 0.2, 0.6])
	var side := "--side" in OS.get_cmdline_user_args()
	var high := "--high" in OS.get_cmdline_user_args()
	var chase := "--chase" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			track = arg.get_slice("=", 1)
		elif arg.begins_with("--at="):
			spots = PackedFloat32Array()
			for v in arg.get_slice("=", 1).split(","):
				spots.append(float(v))
	GameSettings.track = track
	GameSettings.time_of_day = 1
	GameSettings.weather = 0
	GameSettings.p1_car = "bavaro"
	var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
	var car := scene.get_node("Vehicle") as Vehicle
	var player := car.get_node("PlayerInput")
	car.remove_child(player)
	player.free()
	root.add_child(scene)
	current_scene = scene
	var hud := scene.get_node_or_null("HUDLayer") as CanvasLayer
	if hud:
		hud.visible = false
	var circuit := scene.get_node("Circuit") as Circuit
	var cam := Camera3D.new()
	cam.fov = 60.0
	scene.add_child(cam)
	await _wait(1.0)
	for f in spots:
		var off := f * circuit.length
		var car_off := off + 22.0
		car.teleport(Transform3D(Basis.looking_at(circuit.direction_at(car_off), Vector3.UP),
				circuit.point_at(car_off) + Vector3.UP * 0.5))
		car.controls_locked = true
		if chase:
			var ai := AIDriver.new()
			ai.skill = 0.8
			car.add_child(ai)
			car.input = ai
			car.controls_locked = false
			car.linear_velocity = circuit.direction_at(car_off) * 22.0
			for cam_node in get_nodes_in_group("chase_cameras"):
				(cam_node as ChaseCamera).snap()
				(cam_node as Camera3D).make_current()
			await _wait(3.0)
			await RenderingServer.frame_post_draw
			var cfile := "%s/hills_%s_%02d_chase.png" % [OUT, track, roundi(f * 100.0)]
			root.get_texture().get_image().save_png(cfile)
			print("saved ", cfile)
			car.remove_child(ai)
			ai.queue_free()
			continue
		if high:
			var mid2 := circuit.point_at(off + 60.0)
			var eye2 := mid2 + circuit.right_at(off + 60.0) * 260.0
			eye2.y = maxf(mid2.y, circuit.ground_height(eye2.x, eye2.z)) + 75.0
			cam.global_position = eye2
			cam.look_at(mid2, Vector3.UP)
		elif side:
			var mid := circuit.point_at(off + 30.0)
			var eye := mid + circuit.right_at(off + 30.0) * 110.0
			eye.y = maxf(mid.y, circuit.ground_height(eye.x, eye.z)) + 18.0
			cam.global_position = eye
			cam.look_at(mid + Vector3.UP * 2.0, Vector3.UP)
		else:
			cam.global_position = circuit.point_at(off) + circuit.right_at(off) * 9.0 + Vector3.UP * 2.2
			cam.look_at(circuit.point_at(off + 75.0) + Vector3.UP * 1.0, Vector3.UP)
		cam.make_current()
		await _wait(1.2)
		await RenderingServer.frame_post_draw
		var file := "%s/hills_%s_%02d%s.png" % [OUT, track, roundi(f * 100.0), "_high" if high else ("_side" if side else "")]
		root.get_texture().get_image().save_png(file)
		print("saved ", file)
	quit()


func _wait(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < seconds:
		await process_frame
