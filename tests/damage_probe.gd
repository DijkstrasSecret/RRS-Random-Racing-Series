extends SceneTree
## Research probe for a damage system (not a pass/fail test):
## 1. Crashes a car into the trackside barrier at several speeds, and into a
##    parked car, and prints what Jolt reports per hit: contact impulse,
##    where on the car it hit (local position) and the change in velocity.
## 2. Times denting a car body mesh on the CPU (moving vertices near an
##    impact point and rebuilding the mesh).
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/damage_probe.gd

const SPEEDS_KMH := [30.0, 60.0, 100.0, 150.0]


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
	var car := scene.get_node("Vehicle") as Vehicle
	var player := car.get_node("PlayerInput")
	car.remove_child(player)
	player.free()
	root.add_child(scene)
	current_scene = scene
	await _ticks(60)
	var circuit := scene.get_node("Circuit") as Circuit
	car.contact_monitor = true
	car.max_contacts_reported = 16

	print("== barrier crashes (car: %s, %.0f kg)" % [car.config.display_name, car.mass])
	print("  speed   peak impulse   total impulse   max dv     hit point (car local x,y,z)   contacts")
	for kmh: float in SPEEDS_KMH:
		var off := 120.0
		var centre := circuit.point_at(off)
		var right := circuit.right_at(off)
		# Face the right-hand barrier, start in the middle of the road.
		var xf := Transform3D(Basis.looking_at(right, Vector3.UP), centre + Vector3.UP * 0.4)
		car.teleport(xf)
		await _ticks(30)
		car.linear_velocity = right * kmh / 3.6
		car.angular_velocity = Vector3.ZERO
		await _report(car, kmh)

	print("== car into a parked car (same model)")
	var other := (load("res://scenes/vehicle/vehicle.tscn") as PackedScene).instantiate() as Vehicle
	var p2 := other.get_node_or_null("PlayerInput")
	if p2:
		other.remove_child(p2)
		p2.free()
	CarRoster.apply(other, GameSettings.p1_car)
	scene.add_child(other)
	await _ticks(10)
	for kmh: float in [40.0, 90.0]:
		var off := 200.0
		var centre := circuit.point_at(off)
		var dir := circuit.direction_at(off)
		other.teleport(Transform3D(Basis.looking_at(circuit.right_at(off), Vector3.UP), centre + dir * 12.0 + Vector3.UP * 0.4))
		car.teleport(Transform3D(Basis.looking_at(dir, Vector3.UP), centre + Vector3.UP * 0.4))
		await _ticks(40)
		car.linear_velocity = dir * kmh / 3.6
		await _report(car, kmh)

	_time_mesh_dent()
	quit()


## Watches ~1.5 s after launch and prints the biggest hit.
func _report(car: Vehicle, kmh: float) -> void:
	var peak := 0.0
	var total := 0.0
	var max_dv := 0.0
	var hit_local := Vector3.ZERO
	var count := 0
	var last_v := car.linear_velocity
	for i in 180:
		await physics_frame
		var state := PhysicsServer3D.body_get_direct_state(car.get_rid())
		for c in state.get_contact_count():
			var collider := state.get_contact_collider_object(c)
			if collider is StaticBody3D and String(collider.name) in ["Grass", "TerrainBody", "Road", "Curbs", "Gravel"]:
				continue  # ground, not a crash
			var imp := state.get_contact_impulse(c).length()
			total += imp
			count += 1
			if imp > peak:
				peak = imp
				# The contact point on our own car (Godot returns it in world space).
				hit_local = car.global_transform.affine_inverse() * state.get_contact_local_position(c)
		max_dv = maxf(max_dv, (car.linear_velocity - last_v).length())
		last_v = car.linear_velocity
	print("  %3d km/h  %9.0f Ns  %11.0f Ns  %6.1f m/s   (%+.2f, %+.2f, %+.2f)          %d" % [
		kmh, peak, total, max_dv, hit_local.x, hit_local.y, hit_local.z, count])


func _time_mesh_dent() -> void:
	print("== denting a body mesh on the CPU")
	for id in ["braxton", "bellmont", "kartal"]:
		var model := (load(CarRoster.model_path(id)) as PackedScene).instantiate()
		var body := model.find_child("body*", true, false) as MeshInstance3D
		var src := body.mesh as ArrayMesh
		var verts := 0
		var surfaces: Array = []
		for s in src.get_surface_count():
			var arrays := src.surface_get_arrays(s)
			surfaces.append(arrays)
			verts += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var hit := Vector3(0.0, 0.6, -2.2)  # front corner-ish
		var push := Vector3(0.0, 0.0, 0.18)
		var t0 := Time.get_ticks_usec()
		var moved := 0
		for arrays: Array in surfaces:
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in v.size():
				var d := v[i].distance_to(hit)
				if d < 0.8:
					var w := 1.0 - d / 0.8
					v[i] += push * w * w
					moved += 1
			arrays[Mesh.ARRAY_VERTEX] = v
		var t1 := Time.get_ticks_usec()
		var mesh := ArrayMesh.new()
		for s in surfaces.size():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[s])
			mesh.surface_set_material(s, src.surface_get_material(s))
		var t2 := Time.get_ticks_usec()
		print("  %-9s %5d vertices, %4d moved: move %.2f ms, rebuild mesh %.2f ms" % [
			id, verts, moved, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
		model.free()


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame
