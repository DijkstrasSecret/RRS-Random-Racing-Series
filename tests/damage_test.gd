extends SceneTree
## Crash damage: driving on the road does no damage; a 100 km/h barrier hit
## dents the front, darkens the paint, breaks the headlights and (FULL) cuts
## engine power; a side scrape pulls the steering; DAMAGE OFF and the main
## menu's background cars get no damage at all.
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/damage_test.gd

var _ok := true


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	GameSettings.damage = 2
	var scene := await _load_practice()
	var car := scene.get_node("Vehicle") as Vehicle
	var circuit := scene.get_node("Circuit") as Circuit
	var dmg := car.damage
	_check("damage added to the car", dmg != null and car.contact_monitor)
	if dmg == null:
		return _finish()

	# Fast along the road: no damage from the ground.
	var off := 120.0
	car.teleport(Transform3D(Basis.looking_at(circuit.direction_at(off), Vector3.UP), circuit.point_at(off) + Vector3.UP * 0.4))
	await _ticks(20)
	car.linear_velocity = circuit.direction_at(off) * 100.0 / 3.6
	await _ticks(90)
	_check("100 km/h on the road: no damage (%.3f)" % dmg.total(), dmg.total() == 0.0)

	# Straight into the barrier at 100 km/h.
	var right := circuit.right_at(off)
	car.teleport(Transform3D(Basis.looking_at(right, Vector3.UP), circuit.point_at(off) + Vector3.UP * 0.4))
	await _ticks(30)
	car.linear_velocity = right * 100.0 / 3.6
	var t0 := Time.get_ticks_usec()
	await _ticks(150)
	print("  zones after barrier hit: %s" % _zones(dmg))
	var front := dmg.zones[CarDamage.Zone.FRONT]
	_check("barrier 100 km/h: front damaged (%.2f)" % front, front > 0.3)
	_check("headlights broken", car._head_broken == (front > 0.5))
	_check("FULL: engine power cut (%.2f)" % car.power_scale, car.power_scale < 1.0 and car.power_scale >= 0.6)
	var moved := _moved_vertices(dmg)
	_check("body dented (%d vertices moved)" % moved, moved > 50)
	_check("paint darkened round the dent", _darkest_tint(dmg) < 0.9)
	print("  (crash + dent took %.1f ms of wall time over 150 ticks)" % ((Time.get_ticks_usec() - t0) / 1000.0))

	# Side into the barrier: steering pulls to that side. On a level, straight
	# bit of road (on a slope the sliding car turns before it hits).
	var off2 := _level_spot(circuit)
	var r2 := circuit.right_at(off2)
	car.teleport(Transform3D(Basis.looking_at(circuit.direction_at(off2), Vector3.UP),
			circuit.point_at(off2) + Vector3.UP * 0.4))
	await _ticks(30)
	car.linear_velocity = r2 * 70.0 / 3.6
	await _ticks(120)
	print("  zones after side hit: %s" % _zones(dmg))
	_check("right side damaged", dmg.zones[CarDamage.Zone.RIGHT] > 0.1)
	_check("steering pulls right (%.2f deg)" % rad_to_deg(car.steer_pull), car.steer_pull > 0.0)
	scene.queue_free()
	await _ticks(5)

	# VISUAL: dents but no handling change.
	GameSettings.damage = 1
	scene = await _load_practice()
	car = scene.get_node("Vehicle") as Vehicle
	circuit = scene.get_node("Circuit") as Circuit
	right = circuit.right_at(off)
	car.teleport(Transform3D(Basis.looking_at(right, Vector3.UP), circuit.point_at(off) + Vector3.UP * 0.4))
	await _ticks(30)
	car.linear_velocity = right * 100.0 / 3.6
	await _ticks(150)
	_check("VISUAL: front damaged (%.2f)" % car.damage.zones[0], car.damage.zones[0] > 0.3)
	_check("VISUAL: full power kept", car.power_scale == 1.0 and car.steer_pull == 0.0)
	scene.queue_free()
	await _ticks(5)

	# OFF: no damage node at all.
	GameSettings.damage = 0
	scene = await _load_practice()
	car = scene.get_node("Vehicle") as Vehicle
	_check("OFF: no damage", car.damage == null)
	scene.queue_free()
	await _ticks(5)

	# Main menu background cars stay clean.
	GameSettings.damage = 2
	var menu := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu
	await _ticks(30)
	var any := false
	for v in get_nodes_in_group("vehicles"):
		if (v as Vehicle).damage != null:
			any = true
	_check("main menu cars: no damage", not any)
	_finish()


func _finish() -> void:
	print("damage_test %s" % ("PASSED" if _ok else "FAILED"))
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


## Lap distance of the flattest, straightest piece of road.
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


func _zones(dmg: CarDamage) -> String:
	var parts: PackedStringArray = []
	for i in dmg.zones.size():
		parts.append("%s %.2f" % [CarDamage.ZONE_NAMES[i], dmg.zones[i]])
	return ", ".join(parts)


func _moved_vertices(dmg: CarDamage) -> int:
	var n := 0
	for entry: Dictionary in dmg._meshes:
		for off: PackedVector3Array in entry.offsets:
			for o in off:
				if o.length() > 0.005:
					n += 1
	return n


func _darkest_tint(dmg: CarDamage) -> float:
	var m := 1.0
	for entry: Dictionary in dmg._meshes:
		for tint: PackedFloat32Array in entry.tints:
			for t in tint:
				m = minf(m, t)
	return m


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_ok = false


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame
