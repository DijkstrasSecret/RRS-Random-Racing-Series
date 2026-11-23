extends SceneTree
## Pit lanes from above (entry, boxes, exit) on each F1 circuit, plus a
## driver's-eye view of the entry. Run windowed with an override.cfg:
##   Godot.exe --path . -s res://tests/screenshot_pitlane.gd [-- --tracks=monza,spa]

const OUT := "user://screenshots"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var tracks := PackedStringArray(["monza", "spa", "silverstone", "istanbul"])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tracks="):
			tracks = arg.get_slice("=", 1).split(",")
	for id in tracks:
		GameSettings.track = id
		GameSettings.time_of_day = 1
		GameSettings.weather = 0
		TrackAtmosphere.clear_haze = 0.0  # crisp from up high
		var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
		var car := scene.get_node("Vehicle") as Vehicle
		var player := car.get_node("PlayerInput")
		car.remove_child(player)
		player.free()
		root.add_child(scene)
		current_scene = scene
		for n in scene.find_children("*", "CanvasLayer", true, false):
			(n as CanvasLayer).visible = false
		var circuit := scene.find_children("*", "Circuit", true, false)[0] as Circuit
		if circuit.pit.is_empty():
			print("no pit lane on ", id)
			scene.queue_free()
			await process_frame
			continue
		var cam := Camera3D.new()
		cam.far = 3000.0
		scene.add_child(cam)
		cam.current = true
		var from := float(circuit.pit.from)
		var to := float(circuit.pit.to)
		var ramp := float(circuit.pit.ramp)
		var views := {"entry": from + ramp * 0.35, "entry2": from + ramp * 0.9, "boxes": circuit.pit_zone_mid(), "exit": to - ramp * 0.5}
		for key: String in views:
			var off := fposmod(float(views[key]), circuit.length)
			var side := float(circuit.pit.side)
			var c := circuit.point_at(off) + circuit.right_at(off) * side * 9.0
			cam.global_position = c + Vector3.UP * 38.0 - circuit.direction_at(off) * 22.0
			cam.look_at(c, circuit.direction_at(off))
			await _shot("pitlane_%s_%s" % [id, key])
		# Driver's eye: 60 m before the entry, on the pit side of the track.
		var o := fposmod(from - 40.0, circuit.length)
		cam.global_position = circuit.point_at(o) + circuit.right_at(o) * float(circuit.pit.side) * 2.5 + Vector3.UP * 1.6
		cam.look_at(circuit.point_at(fposmod(from + 40.0, circuit.length)) + Vector3.UP * 1.0, Vector3.UP)
		await _shot("pitlane_%s_driver" % id)
		scene.queue_free()
		current_scene = null
		await process_frame
	quit()


func _shot(name: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	print("saved ", name)
