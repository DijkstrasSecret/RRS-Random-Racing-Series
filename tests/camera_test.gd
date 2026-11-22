extends SceneTree
## Camera view angles: Z / X (or the right stick left / right) swing to 45
## degrees rear left / rear right and no further; right stick forward / B
## cuts to the look-back camera while held, leaving the normal camera put.
## Run: Godot_console.exe --headless --fixed-fps 60 --path . -s res://tests/camera_test.gd
## With a window and -- --shots, also saves pictures of the views.

var _ok := true


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	var car := scene.get_node("Vehicle") as Vehicle
	car.controls_locked = true
	await _frames(30)
	var cam: ChaseCamera = null
	for node in get_nodes_in_group("chase_cameras"):
		cam = node
	_check("chase camera found", cam != null)
	await _frames(90)
	_check("starts behind the car", _side(cam, car).z > 3.0 and absf(_side(cam, car).x) < 1.0)

	await _action("camera_right")
	await _frames(150)
	var p := _side(cam, car)
	_check("X -> rear right (%s, %.1f / %.1f)" % [cam.view_name(), p.x, p.z], cam.view_angle == 1 and p.x > 2.5 and p.z > 2.5)
	await _action("camera_right")
	_check("X again stays at 45 degrees", cam.view_angle == 1)
	await _action("camera_left")
	await _action("camera_left")
	await _frames(150)
	p = _side(cam, car)
	_check("Z Z -> rear left (%s, %.1f / %.1f)" % [cam.view_name(), p.x, p.z], cam.view_angle == -1 and p.x < -2.5 and p.z > 2.5)
	await _action("camera_right")
	await _frames(150)
	_check("back behind (%s)" % cam.view_name(), cam.view_angle == 0 and absf(_side(cam, car).x) < 1.0)

	# Right stick forward: the look-back camera, normal camera stays behind.
	await _stick(0.0, -1.0)
	await _frames(20)
	var vp := root.get_viewport()
	var back := vp.get_camera_3d()
	_check("stick forward -> look-back camera (%s)" % cam.view_name(), cam.is_looking_back() and back != cam)
	_check("look-back camera sits ahead of the car", back != null and _side(back, car).z < -3.0)
	_check("normal camera stays behind", _side(cam, car).z > 3.0)
	if "--shots" in OS.get_cmdline_user_args():
		await _shot("look_back")
	await _stick(0.0, 0.0)
	await _frames(10)
	_check("released -> normal camera again", vp.get_camera_3d() == cam and not cam.is_looking_back())
	await _hold("look_back", true)
	await _frames(10)
	_check("B -> look back", cam.is_looking_back())
	await _hold("look_back", false)
	await _frames(10)

	if "--shots" in OS.get_cmdline_user_args():
		for k in [-1, 0, 1]:
			cam.view_angle = k
			await _frames(150)
			await _shot("view_%d" % (k + 1))
	print("camera_test %s" % ("PASSED" if _ok else "FAILED"))
	quit()


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://screenshots/%s.png" % shot_name)


## Position in the car's own frame (+X right, +Z behind).
func _side(cam: Camera3D, car: Node3D) -> Vector3:
	return car.global_transform.affine_inverse() * cam.global_position


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_ok = false


func _action(action: String) -> void:
	await _hold(action, true)
	await _hold(action, false)


func _hold(action: String, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	Input.parse_input_event(e)
	await _frames(2)


func _stick(x: float, y: float) -> void:
	for pair: Array in [[JOY_AXIS_RIGHT_X, x], [JOY_AXIS_RIGHT_Y, y]]:
		var e := InputEventJoypadMotion.new()
		e.device = 0
		e.axis = pair[0]
		e.axis_value = pair[1]
		Input.parse_input_event(e)
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
