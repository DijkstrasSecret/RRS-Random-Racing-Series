extends SceneTree
## Screenshots of the circuits at different times of day and weather, with an
## AI driver at the wheel (no user input, settings file untouched).
## Run windowed with an override.cfg containing window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/screenshot_env.gd -- [--quick]

const OUT := "user://screenshots"
## [track, time of day, weather, seconds of driving before each shot]
const SHOTS := [
	["monza", 2, 0, [3.5, 14.0]],
	["silverstone", 0, 0, [3.5, 22.0]],
	["istanbul", 1, 1, [3.5, 30.0]],
	["monza", 3, 0, [3.5, 14.0]],
	["spa", 2, 0, [3.5, 16.0]],
	["spa", 1, 2, [3.5, 12.0]],
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var list := SHOTS
	if "--quick" in OS.get_cmdline_user_args():
		list = SHOTS.slice(0, 1)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--haze-compare="):  # clear noon/morning at several haze amounts
			list = []
			for id in arg.get_slice("=", 1).split(","):
				for h in [0.0, 0.25, 0.5]:
					list.append([id, 1, 0, [4.0, 14.0], h])
					list.append([id, 0, 0, [14.0], h])
		if arg.begins_with("--tracks="):  # noon, clear, two shots per track
			list = []
			for id in arg.get_slice("=", 1).split(","):
				list.append([id, 1, 0, [4.0, 14.0]])
	for shot: Array in list:
		GameSettings.track = shot[0]
		GameSettings.time_of_day = shot[1]
		GameSettings.weather = shot[2]
		TrackAtmosphere.clear_haze = shot[4] if shot.size() > 4 else 0.25
		GameSettings.p1_car = "braxton"
		var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
		var car := scene.get_node("Vehicle") as Vehicle
		var player := car.get_node("PlayerInput")
		car.remove_child(player)
		player.free()
		var ai := AIDriver.new()
		ai.skill = 0.8
		car.add_child(ai)
		root.add_child(scene)
		current_scene = scene
		var start := Time.get_ticks_msec()
		for at: float in shot[3]:
			while (Time.get_ticks_msec() - start) / 1000.0 < at:
				await process_frame
			await RenderingServer.frame_post_draw
			var file := "%s/env_%s_%s_%s_%d%s.png" % [OUT, shot[0], GameSettings.TIME_NAMES[shot[1]].to_lower(),
					GameSettings.WEATHER_NAMES[shot[2]].to_lower(), roundi(at),
					("_haze%d" % roundi(shot[4] * 100.0)) if shot.size() > 4 else ""]
			root.get_texture().get_image().save_png(file)
			print("saved ", file)
		scene.queue_free()
		current_scene = null
		await process_frame
		await process_frame
	quit()
