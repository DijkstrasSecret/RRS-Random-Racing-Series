extends SceneTree
## Screenshots of the circuits at different times of day and weather, with an
## AI driver at the wheel (no user input, settings file untouched).
## Run windowed with an override.cfg containing window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/screenshot_env.gd -- [--quick]

const OUT := "user://screenshots"
## [track, time of day, weather, seconds of driving before each shot]
const SHOTS := [
	["greenhill", 2, 0, [3.5, 14.0]],
	["greenhill", 0, 0, [3.5, 22.0]],
	["greenhill", 1, 1, [3.5, 30.0]],
	["greenhill", 3, 0, [3.5, 14.0]],
	["kestrel", 2, 0, [3.5, 16.0]],
	["kestrel", 1, 2, [3.5, 12.0]],
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var list := SHOTS
	if "--quick" in OS.get_cmdline_user_args():
		list = SHOTS.slice(0, 1)
	for shot: Array in list:
		GameSettings.track = shot[0]
		GameSettings.time_of_day = shot[1]
		GameSettings.weather = shot[2]
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
			var file := "%s/env_%s_%s_%s_%d.png" % [OUT, shot[0], GameSettings.TIME_NAMES[shot[1]].to_lower(),
					GameSettings.WEATHER_NAMES[shot[2]].to_lower(), roundi(at)]
			root.get_texture().get_image().save_png(file)
			print("saved ", file)
		scene.queue_free()
		current_scene = null
		await process_frame
		await process_frame
	quit()
