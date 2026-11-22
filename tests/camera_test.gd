extends SceneTree
## Camera view angles: Z / X step 45 degrees round the car, the right stick
## looks from the side it points to. Checks where the camera ends up.
## Run: Godot_console.exe --headless --fixed-fps 60 --path . -s res://tests/camera_test.gd
## With a window and -- --shots, also saves a picture of all 8 views.

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
	await _frames(60)
	_check("starts behind the car", _side(cam, car).z > 3.0)

	await _action("camera_right")
	await _action("camera_right")
	await _frames(90)
	_check("X X -> right side view (%s)" % cam.view_name(), cam.view_angle == 2 and _side(cam, car).x > 3.0)
	for i in 4:
		await _action("camera_left")
	await _frames(90)
	print("    left view camera at ", _side(cam, car), " angle_now ", cam._angle_now)
	_check("Z x4 -> left side view (%s)" % cam.view_name(), cam.view_angle == 6 and _side(cam, car).x < -3.0)
	await _action("camera_right")
	await _action("camera_right")
	await _frames(90)
	_check("back behind (%s)" % cam.view_name(), cam.view_angle == 0 and _side(cam, car).z > 3.0)

	# Right stick pushed up: look from the front while held.
	await _stick(0.0, -1.0)
	await _frames(90)
	_check("right stick up -> front view (%s)" % cam.view_name(), _side(cam, car).z < -3.0)
	await _stick(0.0, 0.0)
	await _frames(90)
	_check("stick released -> behind again", _side(cam, car).z > 3.0)

	if "--shots" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		for k in 8:
			cam.view_angle = k
			await _frames(70)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://screenshots/view_%d.png" % k)
	print("camera_test %s" % ("PASSED" if _ok else "FAILED"))
	quit()


## Camera position in the car's own frame (+X right, +Z behind).
func _side(cam: Camera3D, car: Node3D) -> Vector3:
	return car.global_transform.affine_inverse() * cam.global_position


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_ok = false


func _action(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
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
