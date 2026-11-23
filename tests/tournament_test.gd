extends SceneTree
## Plays a whole tournament by itself: the players' cars are driven by the AI
## and they shop like the AI does (buy what they can afford), race after race
## through to the podium. Prints each race's result and the final standings.
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/tournament_test.gd -- --players=1 --tracks=rx
## (--tracks=rx = rallycross + island, f1, or all). Settings file untouched.

var _ok := true
var _seen: Node = null


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var players := 1
	var set_name := "rx"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--players="):
			players = int(arg.get_slice("=", 1))
		elif arg.begins_with("--tracks="):
			set_name = arg.get_slice("=", 1)
	var pool := PackedStringArray()
	for t in TrackList.TRACKS:
		var series := String(t.get("series", ""))
		if set_name == "all" or (set_name == "f1" and series == "F1") or (set_name == "rx" and series != "F1"):
			pool.append(t.id)
	GameSettings.p1_car = "bavaro"
	GameSettings.p2_car = "kaze"
	GameSettings.ai_tiers = 15
	Tournament.start(players, pool, 15, 8 - players)
	print("tournament: %d player(s), tracks %s" % [players, ", ".join(Tournament.tracks)])
	change_scene_to_file(Tournament.race_scene())
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) < 1800 * 1000:
		await process_frame
		var scene := current_scene
		if scene == null or scene == _seen:
			continue
		_seen = scene
		if scene.scene_file_path == Tournament.SHOP_SCENE:
			if not Tournament.final_order.is_empty():
				_report_final()
				break
			_report_race()
			_shop_for_humans()
			await create_timer(0.2).timeout
			change_scene_to_file(Tournament.race_scene())
		else:
			_drive_humans(scene)
	_check("tournament reached the podium", not Tournament.final_order.is_empty())
	print("tournament_test %s" % ("PASSED" if _ok else "FAILED"))
	quit()


func _drive_humans(scene: Node) -> void:
	for node in scene.get_children():
		var car := node as Vehicle
		if car == null:
			continue
		var player := car.get_node_or_null("PlayerInput")
		if player:
			car.remove_child(player)
			player.queue_free()
			var ai := AIDriver.new()
			ai.name = "AIDriver"
			ai.skill = 0.8
			car.add_child(ai)
			car.input = ai
	var setup_title := "%s (%s, %d lap)" % [Tournament.race_title(), Tournament.current_track(), Tournament.current_laps()]
	print("  racing %s" % setup_title)


func _shop_for_humans() -> void:
	for p in Tournament.players:
		var r := Tournament.human(p + 1)
		for id: String in Array(r.offers):
			Tournament.buy(r, id)


func _report_race() -> void:
	var line := PackedStringArray()
	var order: Array[int] = []
	for i in Tournament.racers.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return int(Tournament.racers[a].points) > int(Tournament.racers[b].points))
	for i in order:
		var r: Dictionary = Tournament.racers[i]
		line.append("%s %d (P%d)" % [r.name, int(r.points), int((r.results as Array).back())])
	print("  after race %d: %s" % [Tournament.race_index, ", ".join(line)])
	var total := 0
	for r in Tournament.racers:
		total += (r.results as Array).size()
	_check("every racer got a result", total == Tournament.racers.size() * Tournament.race_index)


func _report_final() -> void:
	print("  FINAL (%s):" % Tournament.tracks[Tournament.RACES])
	for n in Tournament.final_order.size():
		var r: Dictionary = Tournament.racers[Tournament.final_order[n]]
		print("    %d. %s  %s  (%d pts earned, %s)" % [n + 1, r.name, CarRoster.config(r.car).display_name,
				int(r.points), Upgrades.describe(r.upgrades)])


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_ok = false
