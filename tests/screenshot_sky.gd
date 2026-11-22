extends SceneTree
## Sky / cloud pictures: from the start straight, looking a little up, towards
## the sun and away from it, for each time of day (clear) plus hazy and fog.
## Saves one 2x4 contact sheet per run: user://screenshots/sky_sheet.png
## Run windowed with an override.cfg containing window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/screenshot_sky.gd [-- --track=spa]

const OUT := "user://screenshots"
const CASES := [[0, 0], [1, 0], [2, 0], [3, 0], [1, 1], [1, 2]]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	GameSettings.track = "monza"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			GameSettings.track = arg.get_slice("=", 1)
	var shots: Array[Image] = []
	for case: Array in CASES:
		GameSettings.time_of_day = case[0]
		GameSettings.weather = case[1]
		var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
		root.add_child(scene)
		current_scene = scene
		for layer in scene.find_children("*", "CanvasLayer", true, false):
			if not (layer is RetroLook):
				(layer as CanvasLayer).visible = false
		var circuit := scene.get_node("Circuit") as Circuit
		var cam := Camera3D.new()
		cam.fov = 70.0
		scene.add_child(cam)
		await _wait(1.0)
		var sun := circuit.atmosphere.sun_dir
		var flat_sun := Vector3(sun.x, 0.0, sun.z).normalized()
		for look: Vector3 in [flat_sun, -flat_sun]:
			cam.global_position = circuit.point_at(40.0) + Vector3.UP * 3.0
			var dir := (look + Vector3.UP * 0.32).normalized()
			cam.look_at(cam.global_position + dir, Vector3.UP)
			cam.make_current()
			await _wait(0.6)
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.resize(640, 360)
			shots.append(img)
		scene.queue_free()
		current_scene = null
		await process_frame
		await process_frame
	var sheet := Image.create_empty(1280, 360 * CASES.size(), false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, 640, 360), Vector2i((i % 2) * 640, (i / 2) * 360))
	sheet.save_png("%s/sky_sheet.png" % OUT)
	print("saved sky_sheet")
	quit()


func _wait(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < seconds:
		await process_frame
