extends SceneTree
## Cover pictures: a night race at Spa led by the Tofaş Şahin (livery on), the
## pack of AI cars around it, no HUD. Saves chase-camera shots and low "TV"
## shots from beside / ahead of the Şahin a few seconds into the race.
## Run windowed with an override.cfg containing window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/screenshot_cover.gd [-- --track=spa]

const OUT := "user://screenshots"
const HERO := "atmaca"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	GameSettings.track = "spa"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			GameSettings.track = arg.get_slice("=", 1)
	GameSettings.p1_car = HERO
	GameSettings.p1_livery = true
	GameSettings.time_of_day = 3
	GameSettings.weather = 0
	GameSettings.ai_count = 6
	GameSettings.ai_tiers = 15
	GameSettings.laps = 3
	var scene := (load("res://scenes/modes/circuit_race.tscn") as PackedScene).instantiate()
	var hero: Vehicle = null
	for node in scene.get_children():
		if node is Vehicle and node.get_node_or_null("PlayerInput"):
			hero = node
			var player := node.get_node("PlayerInput")
			node.remove_child(player)
			player.free()
			var ai := AIDriver.new()
			ai.name = "AIDriver"
			ai.skill = 0.9
			node.add_child(ai)
	root.add_child(scene)
	current_scene = scene
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		if not (layer is RetroLook):  # keep the PS1 screen effect, hide the HUD
			(layer as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.fov = 50.0
	scene.add_child(cam)
	var chase := root.get_viewport().get_camera_3d()
	var shot := 0
	for at: float in [8.0, 10.5, 13.0, 15.5, 18.0, 21.0]:
		await _until(at)
		chase = root.get_viewport().get_camera_3d() if not cam.current else chase
		await _save("cover_chase_%d" % shot)
		# Low, ahead and to the side, looking back at the Şahin and the pack.
		var xf := hero.global_transform
		var fwd := -xf.basis.z
		var right := xf.basis.x
		var side := 1.0 if shot % 2 == 0 else -1.0
		cam.global_position = xf.origin + fwd * 7.5 + right * side * 3.2 + Vector3.UP * 0.9
		cam.look_at(xf.origin + Vector3.UP * 0.7 - fwd * 2.0, Vector3.UP)
		cam.make_current()
		await _save("cover_tv_%d" % shot)
		chase.make_current()
		shot += 1
	quit()


var _start_ms := -1


func _until(seconds: float) -> void:
	if _start_ms < 0:
		_start_ms = Time.get_ticks_msec()
	while (Time.get_ticks_msec() - _start_ms) / 1000.0 < seconds:
		await process_frame


func _save(shot_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, shot_name])
	print("saved ", shot_name)
