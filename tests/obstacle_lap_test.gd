extends SceneTree
## One whole timed lap of the obstacle course by a simple autopilot: one car,
## no teleports and no repairs other than the course's own respawns (a fall,
## or the autopilot giving up after 10 s stuck, like a player pressing R / Y).
## Checks the lap finishes, every checkpoint counts, and the best time is
## saved and loaded again (to a throwaway file, never the player's).
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/obstacle_lap_test.gd -- [--car=id] [--delay=seconds]
## --delay waits at the start, so the moving obstacles are met at other times.

const TEMP_SAVE := "user://obstacle_course_test.cfg"

var _ok := true
var _route: Array[Vector3] = []
var _speed: Array[float] = []
var _name: Array[String] = []


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var delay := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car="):
			GameSettings.p1_car = a.trim_prefix("--car=")
		elif a.begins_with("--delay="):
			delay = float(a.trim_prefix("--delay="))
	DirAccess.remove_absolute(TEMP_SAVE)
	var scene := (load(GameSettings.OBSTACLE_COURSE) as PackedScene).instantiate()
	var course := scene.get_node("Course") as ObstacleCourse
	course.save_path = TEMP_SAVE
	root.add_child(scene)
	current_scene = scene
	var car := scene.get_node("Vehicle") as Vehicle
	for i in 60 + int(delay * 120.0):
		await physics_frame
	var inp := VehicleInput.new()
	car.add_child(inp)
	car.input.set_physics_process(false)
	car.input = inp
	_build_route(course)

	var i := 0
	var t := 0.0
	var last := car.global_position
	var slow := 0.0
	var stuck := 0.0
	var best_i := 0
	var reverse_left := 0.0
	var respawns: Array[String] = []
	var gave_up := 0
	var started := false
	var finished := false
	while t < 420.0:
		# Where on the line (after a respawn: find it again).
		if car.global_position.distance_to(last) > 4.0:
			respawns.append(_name[i])
			i = _nearest(car.global_position)
			best_i = i
			stuck = 0.0
		last = car.global_position
		var look := clampf(absf(car.forward_speed) * 0.45, 3.5, 12.0)
		while i < _route.size() - 1 and _distance(car.global_position, i) < look:
			i += 1
		if i > best_i + 2:
			best_i = i
			stuck = 0.0
		# Fast enough for here, slow enough for what comes next.
		var want := 40.0
		var ahead := 0.0
		for j in range(i, mini(i + 60, _route.size())):
			want = minf(want, sqrt(_speed[j] * _speed[j] + 2.0 * 4.0 * maxf(ahead - 4.0, 0.0)))
			if j + 1 < _route.size():
				ahead += _route[j].distance_to(_route[j + 1])
		# The lift: wait for it at the top, ride it down.
		var p := car.global_position
		var waiting := false
		if absf(p.x - 248.0) < 6.0 and p.y > 24.0 and p.z > -562.0 and p.z < -553.5:
			waiting = course.lift_phase() > 2.0
		elif absf(p.x - 248.0) < 6.0 and p.z > -548.5 and p.z < -540.0 and p.y > 10.4:
			waiting = true
		var v := car.forward_speed
		var local := car.to_local(_route[i])
		var angle := atan(2.0 * local.x / maxf(local.length_squared(), 1.0) * car.wheelbase()) * 1.3
		inp.steer = clampf(angle / car.current_steer_limit(), -1.0, 1.0)
		inp.handbrake = 0.0
		inp.throttle = clampf((want - v) * 0.4, 0.0, 1.0)
		inp.brake = clampf((v - want - 1.0) * 0.3, 0.0, 1.0)
		if waiting:
			inp.throttle = 0.0
			inp.brake = 1.0 if v > 1.0 else 0.0
			inp.handbrake = 1.0
			slow = 0.0
			reverse_left = 0.0
		else:
			stuck += 1.0 / 120.0
			slow = slow + 1.0 / 120.0 if absf(v) < 0.6 else 0.0
			if slow > 1.5:
				slow = 0.0
				reverse_left = 1.2
			if reverse_left > 0.0:
				reverse_left -= 1.0 / 120.0
				inp.steer = -inp.steer
				inp.throttle = 0.0
				inp.brake = 1.0
			if stuck > 10.0:
				gave_up += 1
				stuck = 0.0
				print("    gave up in %s at %s, speed %.1f want %.1f, aim %s, up %.2f (lift phase %.1f, boom y %.1f, seesaw tilt %.1f)" % [_name[i], car.global_position, v, want, _route[i], car.global_basis.y.y,
						course.lift_phase(), course._boom.position.y, rad_to_deg((course.get_node("Seesaw") as Node3D).rotation.x)])
				course.respawn()
		await physics_frame
		t += 1.0 / 120.0
		if OS.has_environment("DRIVE_TRACE") and int(t * 120.0) % 60 == 0:
			print("      t %.1f %s i %d pos %s v %.1f want %.1f thr %.2f brk %.2f hb %.0f lift %.1f boom %.1f" % [t, _name[i], i, car.global_position, v, want, inp.throttle, inp.brake, inp.handbrake, course.lift_phase(), course._boom.position.y])
		if course.running:
			started = true
		elif started:
			finished = true
			break
	print("  car %s, delay %.1f s: %d checkpoints of %d, respawns %d %s (gave up %d), damage %.2f" % [GameSettings.p1_car, delay,
			course.splits.size(), course.checkpoints.size(), respawns.size(), respawns, gave_up, car.damage.total() if car.damage else 0.0])
	_check("lap finished (%s, at %s in %s)" % [LapTimer.format_time(course.run_time), car.global_position, _name[i]], finished)
	_check("every checkpoint and the finish has a split (%d)" % course.splits.size(), course.splits.size() == course.checkpoints.size())
	if finished:
		var saved := course.best_time
		course.best_time = INF
		course._load_best()
		_check("best time saved and loaded (%.3f)" % course.best_time, absf(course.best_time - saved) < 0.001)
	DirAccess.remove_absolute(TEMP_SAVE)
	print("obstacle_lap_test %s" % ("PASSED" if _ok else "FAILED"))
	quit(0 if _ok else 1)


## The line round the course with a speed for each stretch.
func _build_route(course: ObstacleCourse) -> void:
	_add(course, "village", 15.0, [Vector3(0, 0, 8), Vector3(0, 0.5, -40), Vector3(0, 1.5, -80), Vector3(6, 3, -130), Vector3(0, 4, -180), Vector3(0, 4, -198)])
	_add(course, "chicane", 9.0, [Vector3(0, 4, -206), Vector3(2.5, 4, -214), Vector3(5, 4, -222), Vector3(5, 4, -228), Vector3(0, 4, -237),
			Vector3(-5, 4, -246), Vector3(-5, 4, -252), Vector3(-2.5, 4, -260), Vector3(0, 4, -266), Vector3(0, 4, -274)])
	_add(course, "jump", 30.0, [Vector3(0, 3, -300), Vector3(0, 0, -350), Vector3(0, -2, -395), Vector3(0, -2, -445)])
	_add(course, "wrecking balls", 14.0, [Vector3(0, -2, -500), Vector3(0, -2, -560)])
	_add(course, "turn east", 9.0, [Vector3(2, -2, -580), Vector3(15, -2, -593), Vector3(36, -2, -595)])
	_add(course, "bridges", 11.0, [Vector3(110, -2, -595), Vector3(160, -2, -595), Vector3(185, -2, -595)])
	_add(course, "hairpins", 7.5, [Vector3(200, -2, -604), Vector3(200, -2, -612), Vector3(200, 6, -652), Vector3(204, 6, -661), Vector3(212, 6, -661),
			Vector3(216, 6, -652), Vector3(216, 14, -613), Vector3(220, 14, -604), Vector3(228, 14, -604), Vector3(232, 14, -613), Vector3(232, 22, -652),
			Vector3(236, 22, -661), Vector3(244, 22, -661), Vector3(248, 22, -652), Vector3(248, 26, -606)])
	_add(course, "seesaw", 7.0, [Vector3(248, 26, -575), Vector3(248, 26, -562)])
	_add(course, "lift", 4.0, [Vector3(248, 26, -547), Vector3(248, 10, -540)])
	_add(course, "rollers + turntable", 7.0, [Vector3(248, 10, -500), Vector3(248, 10, -470), Vector3(248, 10, -450)])
	_add(course, "loop run-in", 30.0, [Vector3(248, 10, -416)])
	for k in range(4, course.loop_line.size(), 4):
		_route.append(course.loop_line[k])
		_speed.append(30.0)
		_name.append("loop")
	_add(course, "road home", 17.0, [Vector3(258, 10, -372), Vector3(258, 6, -330), Vector3(255, 3, -220), Vector3(248, 1, -110), Vector3(236, 0, -10)])
	_add(course, "last bends", 11.0, [Vector3(210, 0, 38), Vector3(120, 0, 46), Vector3(40, 0, 42), Vector3(8, 0, 30), Vector3(0, 0, 14), Vector3(0, 0, -20)])


func _add(course: ObstacleCourse, part: String, speed: float, points: Array) -> void:
	var pts: Array = []
	if not _route.is_empty():
		pts.append(_route[_route.size() - 1])
	pts.append_array(points)
	for q in course._smooth(pts, 1.0):
		_route.append(q)
		_speed.append(speed)
		_name.append(part)


func _nearest(p: Vector3) -> int:
	var best := 0
	for k in _route.size():
		if _route[k].distance_squared_to(p) < _route[best].distance_squared_to(p):
			best = k
	return best


## The lift goes straight down: only its sideways distance counts.
func _distance(p: Vector3, k: int) -> float:
	var d := _route[k] - p
	if _name[k] == "lift":
		d.y = 0.0
	return d.length()


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_ok = false
