extends SceneTree
## Pictures of the race HUD (F1-style tower and sector timer): the player's
## car is driven by the AI; the race runs fast between shots.
## Run windowed with an override.cfg containing window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/screenshot_hud.gd [-- --track=spa --scene=versus_race]

const OUT := "user://screenshots"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var scene_name := "circuit_race"
	GameSettings.track = "spa"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			GameSettings.track = arg.get_slice("=", 1)
		elif arg.begins_with("--scene="):
			scene_name = arg.get_slice("=", 1)
	GameSettings.time_of_day = 1
	GameSettings.ai_count = 6
	GameSettings.laps = 3
	if "--tournament" in OS.get_cmdline_user_args():
		# A tournament race: player has nitro + slipstream, AI hold nitro on straights.
		Tournament.start(1, PackedStringArray([GameSettings.track]), 15, 7)
		Tournament.race_index = 2
		Tournament.human(1).upgrades = {"nitro": 1, "slipstream": 1, "engine": 1}
		Tournament.human(1).points = 17
	var scene := (load("res://scenes/modes/%s.tscn" % scene_name) as PackedScene).instantiate()
	for node in scene.get_children():
		if node is Vehicle and node.get_node_or_null("PlayerInput"):
			var player := node.get_node("PlayerInput")
			node.remove_child(player)
			player.free()
			var ai := AIDriver.new()
			ai.name = "AIDriver"
			ai.skill = 0.8
			node.add_child(ai)
	root.add_child(scene)
	current_scene = scene
	var race := scene.find_children("*", "RaceDirector", true, false)[0] as RaceDirector
	var targets := [[25.0, "hud_start"], [70.0, "hud_sector"], [175.0, "hud_lap"]]
	if "--tournament" in OS.get_cmdline_user_args():
		targets = [[8.0, "hud_tournament_start"], [24.0, "hud_tournament"]]
	for target: Array in targets:
		Engine.time_scale = 4.0
		while race.race_time < float(target[0]):
			await process_frame
		Engine.time_scale = 1.0
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s_%s.png" % [OUT, target[1], scene_name])
		print("saved ", target[1])
	quit()
