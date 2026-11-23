extends SceneTree
## Pictures of a pit stop (tyre panel with a flat tyre, PIT STOP countdown)
## and a car that has lost a wheel. Run windowed with an override.cfg:
##   Godot.exe --path . -s res://tests/screenshot_pit.gd [-- --track=monza]

const OUT := "user://screenshots"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	GameSettings.track = "monza"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			GameSettings.track = arg.get_slice("=", 1)
	GameSettings.time_of_day = 1
	GameSettings.ai_count = 6
	GameSettings.laps = 7
	GameSettings.damage = 2
	var scene := (load("res://scenes/modes/circuit_race.tscn") as PackedScene).instantiate()
	var car: Vehicle
	for node in scene.get_children():
		if node is Vehicle and node.get_node_or_null("PlayerInput"):
			car = node
			var player := node.get_node("PlayerInput")
			node.remove_child(player)
			player.free()
	root.add_child(scene)
	current_scene = scene
	var race := scene.find_children("*", "RaceDirector", true, false)[0] as RaceDirector
	var circuit := scene.find_children("*", "Circuit", true, false)[0] as Circuit
	Engine.time_scale = 4.0
	while race.race_time < 30.0:
		await process_frame
	Engine.time_scale = 1.0
	# Into the pit box: worn tyres, one flat, bent front right.
	var mid := circuit.pit_zone_mid()
	var spot := circuit.point_at(mid) + circuit.right_at(mid) * circuit.pit_lateral(mid)
	car.teleport(Transform3D(Basis.looking_at(circuit.direction_at(mid), Vector3.UP), spot + Vector3.UP * 0.5))
	for w in car.wheels:
		w.wear = 0.45
		w.temp = 96.0
		if w.is_front and w.is_left:
			w.punctured = true
			w.deflate = 1.0
		if w.is_front and not w.is_left:
			w.toe = 0.06
	for i in 150:
		await physics_frame
	await _shot("pit_stop")
	# Back on track, a wheel knocked off.
	var off := 300.0
	car.teleport(Transform3D(Basis.looking_at(circuit.direction_at(off), Vector3.UP), circuit.point_at(off) + Vector3.UP * 0.5))
	for i in 30:
		await physics_frame
	for w in car.wheels:
		if w.is_front and not w.is_left:
			w.detach(car.linear_velocity)
	for i in 60:
		await physics_frame
	await _shot("wheel_off")
	quit()


func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	print("saved ", name)
