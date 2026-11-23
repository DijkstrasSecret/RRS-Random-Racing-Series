extends SceneTree
## Running-gear damage (DAMAGE FULL): hard hits near a wheel puncture it, bend
## its suspension or knock it off; a flat tyre loses grip and sparks; a lost
## wheel bounces away; a huge side hit or a sideways slide on a flat tyre can
## roll the car over; a pit stop / recovery puts it all right.
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/running_gear_test.gd

var _ok := true


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	GameSettings.damage = 2
	seed(7)
	var scene := await _load_practice()
	var car := scene.get_node("Vehicle") as Vehicle
	var circuit := scene.get_node("Circuit") as Circuit
	var dmg := car.damage
	var fl := car.wheels[0]
	for w in car.wheels:
		if w.is_front and w.is_left:
			fl = w

	# Hits near the front-left wheel: something on it breaks.
	var broke := 0
	for i in 12:
		for w in car.wheels:
			w.new_tyres()
		dmg._hurt_running_gear(fl.position, 0.3)
		if fl.punctured or fl.toe != 0.0:
			broke += 1
	_check("0.3 hits by a wheel break something most times (%d / 12)" % broke, broke >= 6)
	var far := 0
	for i in 12:
		for w in car.wheels:
			w.new_tyres()
		dmg._hurt_running_gear(Vector3(0, 1.2, 0), 0.3)  # roof, no wheel near
		for w in car.wheels:
			if w.punctured or w.toe != 0.0 or w.detached:
				far += 1
	_check("hits away from the wheels leave them alone", far == 0)
	for w in car.wheels:
		w.new_tyres()

	# Puncture: deflates, loses grip, rim sparks at speed.
	var off := _level_spot(circuit)
	var fwd := circuit.direction_at(off)
	car.teleport(Transform3D(Basis.looking_at(fwd, Vector3.UP), circuit.point_at(off) + Vector3.UP * 0.4))
	await _ticks(30)
	var grip_before := fl._mu_load()
	fl.punctured = true
	car.linear_velocity = fwd * 80.0 / 3.6
	var sparks := false
	for i in 600:
		await physics_frame
		car.input.throttle = 0.4
		if dmg._sparks.emitting:
			sparks = true
	_check("tyre fully flat after 5 s (%.2f)" % fl.deflate, fl.deflate >= 0.99)
	var grip_after := fl._mu_load()
	_check("flat tyre grip %.0f%% of before" % (grip_after / grip_before * 100.0), grip_after < grip_before * 0.6)
	_check("rim sparks", sparks)

	# Bent suspension: the wheel points off line and wobbles.
	fl.toe = 0.08
	await _ticks(10)
	_check("bent wheel is turned (%.1f deg)" % rad_to_deg(fl.toe), absf(fl.toe) > 0.05)

	# Wheel off.
	var bodies_before := _loose_wheels(scene)
	fl.detach(car.linear_velocity)
	await _ticks(30)
	_check("wheel came off and bounces away (%d loose)" % (_loose_wheels(scene) - bodies_before), _loose_wheels(scene) > bodies_before)
	_check("lost wheel: no grip, not drawn", not fl.grounded and not fl._visual.visible)

	# Pit stop puts it all right.
	for w in car.wheels:
		w.new_tyres()
	dmg.repair()
	await _ticks(10)
	_check("pit stop: wheel back, straight, inflated", not fl.detached and fl.toe == 0.0 and fl.deflate == 0.0 and fl._visual.visible)

	# Sliding sideways at 70 km/h on a flat leading tyre: it trips and rolls.
	var rolled_trip := await _slide_test(car, circuit, off, func() -> void:
		for w in car.wheels:
			if not w.is_left:
				w.punctured = true
				w.deflate = 1.0)
	_check("sideways on flat tyres: rolls over (%.0f deg)" % rolled_trip, rolled_trip > 70.0)
	# Same slide on good tyres, on tarmac: stays on its wheels.
	var rolled_ok := await _slide_test(car, circuit, off, func() -> void: pass)
	_check("sideways on good tyres: stays upright (%.0f deg)" % rolled_ok, rolled_ok < 45.0)

	# A huge side hit kicks it over.
	var rolled_hit := await _hit_test(car, circuit, off)
	_check("huge side hit: rolls (%.0f deg)" % rolled_hit, rolled_hit > 70.0)
	_finish()


## Max roll (degrees) after a 70 km/h sideways slide (to the right).
func _slide_test(car: Vehicle, circuit: Circuit, off: float, prep: Callable) -> float:
	var fwd := circuit.direction_at(off)
	for w in car.wheels:
		w.new_tyres()
	car.damage.repair()
	# From near the left barrier, so it has room to slide right.
	var dressing := circuit.get_node("Dressing")
	var i2 := int(off / circuit.length * circuit._samples.size()) % circuit._samples.size()
	var lateral := maxf(float(dressing._barrier_dist[0][i2]) - 2.5, 0.0)
	car.teleport(Transform3D(Basis.looking_at(fwd, Vector3.UP), circuit.point_at(off) - circuit.right_at(off) * lateral + Vector3.UP * 0.4))
	await _ticks(40)
	prep.call()
	car.linear_velocity = circuit.right_at(off) * 70.0 / 3.6
	var worst := 0.0
	for i in 150:
		await physics_frame
		worst = maxf(worst, rad_to_deg(acos(clampf(car.global_basis.y.dot(Vector3.UP), -1.0, 1.0))))
		if OS.get_environment("RG_DEBUG") != "" and i % 10 == 0:
			var g := 0
			for w in car.wheels:
				g += int(w.grounded)
			print("    t%d v_lat %.1f air %s grounded %d roll %.0f" % [i, car.linear_velocity.dot(car.global_basis.x), car.airborne, g, worst])
	return worst


func _hit_test(car: Vehicle, circuit: Circuit, off: float) -> float:
	var fwd := circuit.direction_at(off)
	for w in car.wheels:
		w.new_tyres()
	car.damage.repair()
	car.teleport(Transform3D(Basis.looking_at(fwd, Vector3.UP), circuit.point_at(off) + Vector3.UP * 0.4))
	await _ticks(40)
	car.knock_roll(1.0, 1.0)
	var worst := 0.0
	for i in 180:
		await physics_frame
		worst = maxf(worst, rad_to_deg(acos(clampf(car.global_basis.y.dot(Vector3.UP), -1.0, 1.0))))
	return worst


func _loose_wheels(scene: Node) -> int:
	var n := 0
	for c in root.get_children() + scene.get_children():
		if c is RigidBody3D and not c is Vehicle:
			n += 1
	return n


func _finish() -> void:
	print("running_gear_test %s" % ("PASSED" if _ok else "FAILED"))
	quit()


func _load_practice() -> Node:
	var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
	var car := scene.get_node("Vehicle") as Vehicle
	var player := car.get_node("PlayerInput")
	car.remove_child(player)
	player.free()
	root.add_child(scene)
	current_scene = scene
	await _ticks(60)
	return scene


func _level_spot(circuit: Circuit) -> float:
	var best := 0.0
	var score := 1e9
	var o := 100.0
	while o < circuit.length - 100.0:
		var rise := absf(circuit.point_at(o + 30.0).y - circuit.point_at(o - 30.0).y)
		var bend := absf(circuit.curvature_at(o)) * 200.0
		if rise + bend < score:
			score = rise + bend
			best = o
		o += 10.0
	return best


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_ok = false


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame
