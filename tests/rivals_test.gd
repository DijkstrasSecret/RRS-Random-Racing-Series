extends SceneTree
## The rivals' characters: every driver name has one, a race hands them out,
## and each kind of mistake, forced at every corner, costs time but never
## ends in the car having to be put back on the track.
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/rivals_test.gd -- [--track=lydden]

var _ok := true


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	GameSettings.track = "lydden"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			GameSettings.track = a.get_slice("=", 1)
	var labels := {}
	for n in RaceSetup.AI_NAMES:
		labels[DriverStyle.label(n)] = true
	_check("every driver has a different style", labels.size() == RaceSetup.AI_NAMES.size() and not labels.has(""))
	_check("players have none", DriverStyle.label("YOU") == "")
	await _check_lineup()
	var clean := await _lap(AIDriver.Mistake.NONE)
	_check("clean lap %.2f s, %d resets, %d mistakes" % [clean.x, clean.y, clean.z], clean.x > 0.0 and clean.y == 0)
	for kind: int in [AIDriver.Mistake.LATE_BRAKE, AIDriver.Mistake.LOCK_UP, AIDriver.Mistake.WIDE, AIDriver.Mistake.MISSED_GEAR]:
		var r := await _lap(kind)
		_check("%s at %d corners: lap %.2f s (%+.2f), %d resets" % [AIDriver.Mistake.keys()[kind], r.z, r.x, r.x - clean.x, r.y],
				r.x > 0.0 and r.y == 0 and r.z > 0)
	print("rivals_test %s" % ("PASSED" if _ok else "FAILED"))
	quit(0 if _ok else 1)


## One lap from the grid, alone, always in the same car: (time, resets,
## mistakes made).
func _lap(kind: int) -> Vector3:
	GameSettings.ai_count = 0
	GameSettings.laps = 1
	GameSettings.p1_car = "bavaro"
	var scene := (load(GameSettings.RACE) as PackedScene).instantiate()
	var ai_car := scene.get_node("Vehicle") as Vehicle
	var player := ai_car.get_node("PlayerInput")
	ai_car.remove_child(player)
	player.free()
	var ai := AIDriver.new()
	ai.skill = 0.7
	ai.consistency = 1.0
	ai.nerve = 1.0
	ai_car.add_child(ai)
	root.add_child(scene)
	current_scene = scene
	for i in 20:
		await physics_frame
	var race := scene.find_children("*", "RaceDirector", true, false)[0] as RaceDirector
	var me := race.index_of(ai_car)
	var made := 0
	var last_id := -99
	while race.race_time < 240.0 and not race.finish_times.has(me):
		if kind != AIDriver.Mistake.NONE and ai._corner_dist < 60.0 and ai._corner_dist > 20.0 and ai_car.forward_speed > 18.0 \
				and absi(ai._corner_id - last_id) > 1 and ai._mistake == AIDriver.Mistake.NONE and race.state == RaceDirector.State.RACING:
			ai._start_mistake(kind as AIDriver.Mistake, ai._circuit.progress_at(ai_car.global_position))
			made += 1
		if absi(ai._corner_id - last_id) > 1 and ai._corner_dist < 20.0:
			last_id = ai._corner_id
		await physics_frame
	var out := Vector3(float(race.finish_times.get(me, -1.0)), ai.resets, made)
	scene.queue_free()
	current_scene = null
	for i in 4:
		await process_frame
	return out


func _check_lineup() -> void:
	GameSettings.ai_count = 5
	var scene := (load(GameSettings.RACE) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 20:
		await physics_frame
	var setup := scene.find_children("*", "RaceSetup", true, false)[0] as RaceSetup
	var seen := {}
	var right := 0
	for car in setup.ai_vehicles:
		var who := String(car.get_meta(&"driver_name"))
		seen[who] = true
		var ai := car.get_node("AIDriver") as AIDriver
		right += 1 if is_equal_approx(ai.aggression, DriverStyle.of(who).aggression) and is_equal_approx(ai.nerve, DriverStyle.of(who).nerve) else 0
	_check("5 different rivals, each with its own style (%s)" % ", ".join(PackedStringArray(seen.keys())), seen.size() == 5 and right == 5)
	scene.queue_free()
	current_scene = null
	for i in 4:
		await process_frame


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_ok = false
