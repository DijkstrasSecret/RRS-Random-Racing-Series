extends SceneTree
## Drives each obstacle of the obstacle course with a simple autopilot
## (aim at waypoints, hold a speed) and checks the car gets through without
## falling off (a fall respawns it, which shows as a jump backwards).
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/obstacle_drive_test.gd

var _ok := true
var car: Vehicle
var course: ObstacleCourse
var inp: VehicleInput
var _max_side := 0.0


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var scene := (load(GameSettings.OBSTACLE_COURSE) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	course = scene.get_node("Course") as ObstacleCourse
	car = scene.get_node("Vehicle") as Vehicle
	await _ticks(120)
	inp = VehicleInput.new()
	car.add_child(inp)
	var player := car.input
	car.input = inp
	player.set_physics_process(false)
	var V := Vector3.FORWARD
	var top := 0.0
	for q in course.loop_line:
		top = maxf(top, q.y)
	print("  loop: top %.1f m up, exit %s" % [top - 10.0, course.loop_line[course.loop_line.size() - 1]])
	await _drive("slalom", Vector3(0, 0, 8), V, [Vector3(0, 0.5, -40), Vector3(0, 4, -185)], 16.0, 30.0)
	await _drive("chicane", Vector3(0, 4, -196), V, [Vector3(0, 4, -206), Vector3(2.5, 4, -214), Vector3(5, 4, -222), Vector3(5, 4, -228),
			Vector3(0, 4, -237), Vector3(-5, 4, -246), Vector3(-5, 4, -252), Vector3(-2.5, 4, -260), Vector3(0, 4, -266), Vector3(0, 4, -280)], 9.0, 25.0)
	await _drive("boosts + gap jump", Vector3(0, 4, -276), V, [Vector3(0, -2, -395), Vector3(0, -2, -450)], 24.0, 25.0)
	await _drive("wrecking balls", Vector3(0, -2, -440), V, [Vector3(0, -2, -556)], 14.0, 30.0, true)
	print("  [--] wrecking balls: side speed from hits up to %.1f m/s" % _max_side)
	await _drive("narrow + plank bridges", Vector3(30, -2, -595), Vector3.RIGHT, [Vector3(110, -2, -595), Vector3(160, -2, -595), Vector3(186, -2, -595)], 12.0, 30.0)
	await _drive("hairpins", Vector3(200, -2, -612), V, [Vector3(200, 6, -650), Vector3(204, 6, -661), Vector3(212, 6, -661), Vector3(216, 6, -650),
			Vector3(216, 14, -615), Vector3(220, 14, -604), Vector3(228, 14, -604), Vector3(232, 14, -615), Vector3(232, 22, -650),
			Vector3(236, 22, -661), Vector3(244, 22, -661), Vector3(248, 22, -650), Vector3(248, 26, -606)], 8.0, 60.0)
	# Seesaw, then wait on the lift until it is down.
	await _drive("seesaw", Vector3(248, 26, -603), Vector3.BACK, [Vector3(248, 26, -575)], 7.0, 20.0)
	await _drive("up to the lift", car.global_position, Vector3.BACK, [Vector3(248, 26, -558)], 5.0, 15.0)
	while course.lift_phase() > 1.0:
		_hold()
		await physics_frame
	await _drive("onto the lift", car.global_position, Vector3.BACK, [Vector3(248, 26, -543)], 4.0, 10.0)
	while course.lift_phase() < 10.0:
		_hold()
		await physics_frame
	inp.handbrake = 0.0
	_check("lift took the car down (y %.1f)" % car.global_position.y, car.global_position.y < 12.0 and car.global_position.y > 9.0)
	await _drive("off the lift, rollers, turntable", car.global_position, Vector3.BACK, [Vector3(248, 10, -500), Vector3(248, 10, -470), Vector3(248, 10, -452)], 7.0, 30.0)
	await _drive("boosts + loop", Vector3(248, 10, -449), Vector3.BACK, _loop_points(), 30.0, 20.0, false, false)
	_check("loop exit reached (car %s)" % car.global_position, car.global_position.distance_to(course.loop_line[course.loop_line.size() - 1]) < 25.0)
	await _drive("road home", course.loop_line[course.loop_line.size() - 1] + Vector3(0, 0, 4), Vector3.BACK, [Vector3(258, 6, -330), Vector3(255, 3, -220),
			Vector3(248, 1, -110), Vector3(236, 0, -10), Vector3(210, 0, 38), Vector3(120, 0, 46), Vector3(40, 0, 42)], 17.0, 80.0)
	await _drive("into the finish", Vector3(60, 0, 44), Vector3.LEFT, [Vector3(40, 0, 42), Vector3(8, 0, 30), Vector3(0, 0, 14), Vector3(0, 0, -4)], 10.0, 30.0)
	print("obstacle_drive_test %s" % ("PASSED" if _ok else "FAILED"))
	quit()


## Stand still (handbrake: holding the brake at a stop would engage reverse).
func _hold() -> void:
	inp.throttle = 0.0
	inp.brake = 0.0
	inp.steer = 0.0
	inp.handbrake = 1.0


func _loop_points() -> Array:
	var pts: Array = [Vector3(248, 10, -420)]
	for k in range(6, course.loop_line.size(), 6):
		pts.append(course.loop_line[k])
	pts.append(course.loop_line[course.loop_line.size() - 1] + Vector3(0, 0, 12))
	return pts


## Start at `from` facing `dir`, follow the smoothed line through the points
## (aiming a few metres ahead) at `speed`.
func _drive(what: String, from: Vector3, dir: Vector3, points: Array, speed: float, limit: float, _contact_ok: bool = false, smooth: bool = true) -> void:
	var pts: Array = [from]
	pts.append_array(points)
	if smooth:
		points = Array(course._smooth(pts, 1.0))
	car.teleport(Transform3D(Basis.looking_at(dir, Vector3.UP), from + Vector3.UP * 0.6))
	# Each obstacle with a fresh car (a wrecking ball can bend the steering).
	if car.damage:
		car.damage.repair()
	for w in car.wheels:
		w.new_tyres()
	inp.brake = 0.0
	inp.handbrake = 0.0
	await _ticks(20)
	var i := 0
	var t := 0.0
	var worst_jump := 0.0
	var last := car.global_position
	var min_up := 1.0
	var top_speed := 0.0
	var slow := 0.0
	var reverse_left := 0.0
	var reversals := 0
	while i < points.size() and t < limit:
		var look := clampf(absf(car.forward_speed) * 0.45, 3.5, 12.0)
		while i < points.size() - 1 and car.global_position.distance_to(points[i]) < look:
			i += 1
		var target: Vector3 = points[i]
		if i == points.size() - 1 and car.global_position.distance_to(target) < 5.0:
			i += 1
			break
		var local := car.to_local(target)
		var dist_sq := maxf(local.length_squared(), 1.0)
		var wheel_angle := atan(2.0 * local.x / dist_sq * car.wheelbase()) * 1.3
		inp.steer = clampf(wheel_angle / car.current_steer_limit(), -1.0, 1.0)
		var v := car.forward_speed
		inp.throttle = clampf((speed - v) * 0.4, 0.0, 1.0)
		inp.brake = clampf((v - speed - 1.5) * 0.3, 0.0, 1.0)
		# Stuck against something: back out like a driver would.
		slow = slow + 1.0 / 120.0 if absf(v) < 0.6 else 0.0
		if slow > 1.5:
			reverse_left = 1.2
			slow = 0.0
			reversals += 1
		if reverse_left > 0.0:
			reverse_left -= 1.0 / 120.0
			inp.steer = -inp.steer
			inp.throttle = 0.0
			inp.brake = 1.0
		await physics_frame
		t += 1.0 / 120.0
		worst_jump = maxf(worst_jump, car.global_position.distance_to(last))
		last = car.global_position
		min_up = minf(min_up, car.global_basis.y.y)
		top_speed = maxf(top_speed, v)
		if _contact_ok:
			_max_side = maxf(_max_side, absf(car.linear_velocity.x))
		if OS.has_environment("DRIVE_TRACE") and int(t * 120.0) % 60 == 0:
			print("      t %.1f pos %s v %.1f thr %.2f brk %.2f st %.2f gear %d rpm %.0f wp %d/%d" % [t, car.global_position, v, inp.throttle, inp.brake, inp.steer, car.drivetrain.gear, car.drivetrain.rpm, i, points.size()])
	inp.throttle = 0.0
	var made_it := i >= points.size()
	var respawned := worst_jump > 3.0
	if not made_it:
		var wheels := ""
		for w in car.wheels:
			wheels += "%s%s " % ["G" if w.grounded else "-", "X" if w.detached else ""]
		print("    speed %.1f, gear %d, wheels %s, damage %.2f" % [car.forward_speed, car.drivetrain.gear, wheels, car.damage.total() if car.damage else 0.0])
		print("    throttle %.2f brake %.2f steer %.2f rpm %.0f" % [inp.throttle, inp.brake, inp.steer, car.drivetrain.rpm])
		var space := car.get_world_3d().direct_space_state
		for k in 8:
			for h: float in [0.3, 0.8]:
				var ray_dir := car.global_basis * Vector3(sin(k * PI / 4.0), 0, -cos(k * PI / 4.0))
				var q := PhysicsRayQueryParameters3D.create(car.global_position + Vector3.UP * h, car.global_position + Vector3.UP * h + ray_dir * 3.0, 1 | 4, [car.get_rid()])
				var hit := space.intersect_ray(q)
				if hit:
					print("      ray %d h%.1f hits %s at %.2f m" % [k, h, (hit.collider as Node).get_path(), (hit.position as Vector3).distance_to(car.global_position + Vector3.UP * h)])
	if _contact_ok and not made_it:
		print("  [--] %s: knocked out of the way (fine: it's the obstacle)" % what)
		return
	_check("%s: %s in %.1f s (top %.0f km/h, min up %.2f, backed out %d x%s)" % [what, "through" if made_it else "STUCK at wp %d, car %s" % [i, car.global_position],
			t, top_speed * 3.6, min_up, reversals, ", RESPAWNED" if respawned else ""], made_it and not respawned)


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_ok = false


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame
