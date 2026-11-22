extends SceneTree
## Pictures of the logo where the game shows it: the main menu, and the
## pause menu during a night race. Settings file untouched.
## Run windowed with an override.cfg containing window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/screenshot_logo.gd

const OUT := "user://screenshots"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	GameSettings.track = "spa"
	GameSettings.time_of_day = 3
	change_scene_to_file(GameSettings.MAIN_MENU)
	await _wait(3.0)
	await _save("logo_main_menu")
	change_scene_to_file("res://scenes/modes/circuit_practice.tscn")
	await _wait(3.0)
	for pm in current_scene.find_children("*", "PauseMenu", true, false):
		(pm as PauseMenu).open()
	await _wait(0.5)
	await _save("logo_pause_menu")
	quit()


func _wait(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < seconds:
		await process_frame


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, shot_name])
	print("saved ", shot_name)
