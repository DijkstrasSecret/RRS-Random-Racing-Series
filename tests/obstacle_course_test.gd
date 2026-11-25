extends SceneTree
## Obstacle course: builds, spawns on the road, moving parts move, the run
## starts at the gate, checkpoints count in order, a fall respawns the car.
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/obstacle_course_test.gd

var _ok := true


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var scene := (load(GameSettings.OBSTACLE_COURSE) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	var course := scene.get_node("Course") as ObstacleCourse
	var car := scene.get_node("Vehicle") as Vehicle
	await _ticks(240)
	_check("%d checkpoints (start + 7)" % course.checkpoints.size(), course.checkpoints.size() == 8)
	_check("car sits on the road at the start (y %.2f, speed %.2f)" % [car.global_position.y, car.linear_velocity.length()],
			absf(car.global_position.y - 0.5) < 0.6 and car.linear_velocity.length() < 0.5)
	var grounded := 0
	for w in car.wheels:
		if w.grounded:
			grounded += 1
	_check("all wheels on the ground (%d)" % grounded, grounded == 4)
	# Every checkpoint: a car dropped there lands on something.
	for i in course.checkpoints.size():
		var xf: Transform3D = course.checkpoints[i]
		car.teleport(xf)
		await _ticks(150)
		var g := 0
		for w in car.wheels:
			if w.grounded:
				g += 1
		_check("checkpoint %d at %s: car lands (y %.1f -> %.1f, %d wheels)" % [i, xf.origin, xf.origin.y, car.global_position.y, g],
				g >= 3 and absf(car.global_position.y - xf.origin.y) < 1.5)
	# Run: through the start gate, then the checkpoints in order.
	car.teleport(course.get_spawn_transform())
	await _ticks(30)
	car.linear_velocity = -car.global_basis.z * 12.0
	await _ticks(120)
	_check("run started at the gate (running %s)" % course.running, course.running and course.next_cp == 1)
	for i in range(1, course.checkpoints.size()):
		var xf: Transform3D = course.checkpoints[i]
		car.teleport(Transform3D(xf.basis, xf.origin - (-xf.basis.z) * 8.0))
		await _ticks(10)
		car.linear_velocity = -xf.basis.z * 10.0
		await _ticks(90)
		print("    cp %d: car %s next %d" % [i, car.global_position, course.next_cp])
	_check("all checkpoints counted (next %d)" % course.next_cp, course.next_cp == course.checkpoints.size())
	# Fall into the ravine: back to the last checkpoint.
	car.teleport(Transform3D(Basis.IDENTITY, Vector3(80, -20, -600)))
	await _ticks(120)
	var last: Transform3D = course.checkpoints[course.checkpoints.size() - 1]
	_check("fell: respawned at the last checkpoint (%.0f m away)" % car.global_position.distance_to(last.origin),
			car.global_position.distance_to(last.origin) < 6.0)
	# Moving parts move (in the physics world, not just on screen).
	var ball: AnimatableBody3D = course._pendulums[0].ball
	var b0 := PhysicsServer3D.body_get_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM).origin as Vector3
	await _ticks(60)
	var b1 := PhysicsServer3D.body_get_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM).origin as Vector3
	_check("wrecking ball swings in physics (moved %.1f m in 0.5 s)" % b0.distance_to(b1), b0.distance_to(b1) > 1.0)
	var lift := course.get_node("Lift") as Node3D
	var y0 := lift.position.y
	await _ticks(120 * 5)
	_check("lift moves (%.1f -> %.1f)" % [y0, lift.position.y], absf(lift.position.y - y0) > 1.0)
	print("obstacle_course_test %s" % ("PASSED" if _ok else "FAILED"))
	quit()


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_ok = false


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame
