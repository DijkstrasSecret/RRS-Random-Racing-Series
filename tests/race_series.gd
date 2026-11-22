extends SceneTree
## Runs a series of AI-only races: every track x every car class (D, C, B, A,
## and a mixed field), 8 cars each, and writes one JSON line per race to
## user://race_series.jsonl (positions, cars, race and best lap times,
## resets, damage). Headless:
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/race_series.gd -- --tracks=a,b --classes=0,1,2,3,15
## Laps: 1 on the F1 circuits (3.4 km), 2 elsewhere. Settings file untouched.

var OUT := "user://race_series.jsonl"
const CLASS_NAMES := {1: "D", 2: "C", 4: "B", 8: "A", 15: "MIXED"}


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var tracks := TrackList.ids()
	var masks: Array[int] = [1, 2, 4, 8, 15]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tracks="):
			tracks = arg.get_slice("=", 1).split(",")
		elif arg.begins_with("--out="):
			OUT = "user://%s.jsonl" % arg.get_slice("=", 1)
		elif arg.begins_with("--classes="):
			masks.clear()
			for v in arg.get_slice("=", 1).split(","):
				masks.append(int(v))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for track_id in tracks:
		for mask in masks:
			await _race(track_id, mask, rng)
	quit()


func _race(track_id: String, mask: int, rng: RandomNumberGenerator) -> void:
	var t := TrackList.get_track(track_id)
	GameSettings.track = track_id
	GameSettings.ai_tiers = mask
	GameSettings.ai_count = 7
	GameSettings.ai_difficulty = 1
	GameSettings.laps = 1 if String(t.get("series", "")) == "F1" else 2
	GameSettings.time_of_day = 1
	GameSettings.weather = 0
	GameSettings.damage = 2
	var pool := CarRoster.ids_in_tiers(mask)
	GameSettings.p1_car = pool[rng.randi() % pool.size()]
	var scene := (load("res://scenes/modes/circuit_race.tscn") as PackedScene).instantiate()
	for node in scene.get_children():
		if node is Vehicle and node.get_node_or_null("PlayerInput"):
			var player := node.get_node("PlayerInput")
			node.remove_child(player)
			player.free()
			var ai := AIDriver.new()
			ai.name = "AIDriver"
			ai.skill = rng.randf_range(0.55, 0.85)
			node.add_child(ai)
	root.add_child(scene)
	current_scene = scene
	var race := scene.find_children("*", "RaceDirector", true, false)[0] as RaceDirector
	var circuit := scene.find_children("*", "Circuit", true, false)[0] as Circuit
	var limit := 30.0 + maxf(150.0, circuit.length / 1000.0 * 75.0) * GameSettings.laps
	var start := Time.get_ticks_msec()
	while race.race_time < limit:
		await physics_frame
		if race.car_count() > 0 and race.finish_order.size() == race.car_count():
			break
	var results: Array = []
	for i in race.standings():
		var car := race.vehicle_at(i)
		var ai := car.get_node_or_null("AIDriver") as AIDriver
		var timer := race.timer_at(i)
		results.append({
			"pos": race.position_of(i),
			"driver": race.name_at(i),
			"car": String(car.get_meta(&"car_id", "?")),
			"car_name": car.config.display_name,
			"tier": CarRoster.TIER_NAMES[CarRoster.tier(String(car.get_meta(&"car_id", "kartal")))],
			"time": float(race.finish_times.get(i, -1.0)),
			"best_lap": timer.best_lap,
			"laps": race.completed_laps(i),
			"skill": ai.skill if ai else 0.0,
			"resets": ai.resets if ai else 0,
			"damage": car.damage.total() if car.damage else 0.0,
		})
	var line := {
		"track": track_id, "track_name": t.name, "series": String(t.get("series", "")),
		"class": CLASS_NAMES.get(mask, str(mask)), "laps": GameSettings.laps,
		"length": circuit.length, "race_time": race.race_time,
		"finished": race.finish_order.size(), "cars": race.car_count(),
		"wall_s": (Time.get_ticks_msec() - start) / 1000.0, "results": results,
	}
	var f := FileAccess.open(OUT, FileAccess.READ_WRITE if FileAccess.file_exists(OUT) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(JSON.stringify(line))
	f.close()
	print("race %s %s: %d/%d finished, winner %s (%s) %.1f s, wall %.0f s" % [track_id, line["class"],
			line["finished"], line["cars"], results[0].car_name, results[0].driver, results[0].time, line["wall_s"]])
	scene.queue_free()
	current_scene = null
	for i in 4:
		await process_frame
