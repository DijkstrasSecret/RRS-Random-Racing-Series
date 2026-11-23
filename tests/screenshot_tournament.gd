extends SceneTree
## Pictures of the tournament screens with a made-up mid-tournament state:
## the shop for 1 and 2 players, and the final podium.
## Run windowed with an override.cfg containing window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/screenshot_tournament.gd

const OUT := "user://screenshots"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	for players in [1, 2]:
		_fake_state(players)
		change_scene_to_file(Tournament.SHOP_SCENE)
		await _wait(1.2)
		await _save("tournament_shop_%dp" % players)
	Tournament.final_order.clear()
	var order: Array[int] = []
	for i in Tournament.racers.size():
		order.append(i)
	order.shuffle()
	Tournament.final_order = order
	change_scene_to_file(Tournament.SHOP_SCENE)
	await _wait(1.2)
	await _save("tournament_podium")
	Tournament.finish()
	quit()


func _fake_state(players: int) -> void:
	GameSettings.p1_car = "atmaca"
	GameSettings.p2_car = "bavaro"
	Tournament.start(players, PackedStringArray(["spa", "holjes", "coral", "monza", "hell", "silverstone"]), 15, 8 - players)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for race in 2:
		var order: Array[int] = []
		for i in Tournament.racers.size():
			order.append(i)
		order.shuffle()
		for pos in order.size():
			var r: Dictionary = Tournament.racers[order[pos]]
			(r.results as Array).append(pos + 1)
			r.points = int(r.points) + Tournament.POINTS[pos]
			r.wallet = int(r.wallet) + Tournament.POINTS[pos]
		Tournament.race_index += 1
		Tournament._prepare_shop()
	# The players already bought something last time, and carry some wear.
	var p1 := Tournament.human(1)
	p1.power_slot = "nitro_burst"
	p1.power_level = 1
	p1.unlocks = {"perfect_shift": 1, "interest": 1}
	p1.stats = [{"id": "grip", "tier": 1}]
	p1.wallet = 24
	p1.tyre_wear = [0.42, 0.38, 0.35, 0.33]
	p1.damage = [0.3, 0.0, 0.12, 0.0, 0.0]
	p1.notes = ["Interest: +2"]
	if players == 2:
		var p2 := Tournament.human(2)
		p2.tactical_slot = "engine_map"
		p2.tactical_level = 1
		p2.wallet = 15
		p2.tyre_wear = [0.2, 0.2, 0.25, 0.25]


func _wait(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < seconds:
		await process_frame


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, shot_name])
	print("saved ", shot_name)
