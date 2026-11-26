extends SceneTree
## AI races with the same cars, grid and skills every time (fixed seeds), to
## compare how the rivals race before and after a change: overtakes, resets,
## damage, spread, and (if the driver counts them) defends and mistakes.
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/rival_series.gd -- [--tracks=a,b] [--seeds=1,2] [--laps=2] [--cars=8] [--difficulty=1]

const SWAP_GAP := 6.0  ## metres in front before a pass counts

var _totals := {}
var _brakes := {}


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var tracks := Array(TrackList.ids())
	var seeds: Array = [1]
	var laps := 2
	var cars := 8
	var player_skill := 0.7
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--tracks="):
			tracks = Array(value.split(","))
		elif arg.begins_with("--seeds="):
			seeds = Array(value.split(","))
		elif arg.begins_with("--laps="):
			laps = int(value)
		elif arg.begins_with("--cars="):
			cars = int(value)
		elif arg.begins_with("--player-skill="):
			player_skill = float(value)
		elif arg.begins_with("--difficulty="):
			GameSettings.ai_difficulty = int(value)
	GameSettings.ai_tiers = 4  # one class: close racing
	GameSettings.ai_count = cars - 1
	GameSettings.damage = 2
	for track_id in tracks:
		for s in seeds:
			await _race(String(track_id), int(s), laps, player_skill)
	print("TOTAL %s" % JSON.stringify(_totals))
	print("HEAVY BRAKING (s, all AI) %s" % JSON.stringify(_brakes))
	quit()


func _race(track_id: String, race_seed: int, laps: int, player_skill: float) -> void:
	GameSettings.track = track_id
	GameSettings.laps = laps
	seed(race_seed)
	var pool := CarRoster.ids_in_tiers(GameSettings.ai_tiers)
	GameSettings.p1_car = pool[race_seed % pool.size()]
	var scene := (load("res://scenes/modes/circuit_race.tscn") as PackedScene).instantiate()
	(scene.find_children("*", "RaceSetup", true, false)[0] as RaceSetup).random_seed = race_seed
	var player_car: Vehicle
	for node in scene.get_children():
		if node is Vehicle and node.get_node_or_null("PlayerInput"):
			var player := node.get_node("PlayerInput")
			node.remove_child(player)
			player.free()
			var ai := AIDriver.new()
			ai.name = "AIDriver"
			ai.skill = player_skill
			node.add_child(ai)
			player_car = node
	root.add_child(scene)
	current_scene = scene
	var race := scene.find_children("*", "RaceDirector", true, false)[0] as RaceDirector
	var circuit := scene.find_children("*", "Circuit", true, false)[0] as Circuit
	var limit := 30.0 + maxf(150.0, circuit.length / 1000.0 * 60.0) * laps
	var ahead := {}  # "a b" -> 1 if a leads b, -1 if b leads a
	var overtakes := 0
	var close_time := 0.0  # car-seconds spent within 15 m of the car ahead
	var ticks := 0
	var bumps := 0  # contacts: a sudden change of speed with another car touching distance away
	var last_v := {}
	var bump_wait := {}
	var go := -1.0
	var places := []
	var brakes := {}
	while race.race_time < limit:
		await physics_frame
		if race.car_count() > 0 and race.finish_order.size() + race.retired.size() == race.car_count():
			break
		ticks += 1
		if race.state == RaceDirector.State.RACING:
			if go < 0.0:
				go = race.race_time
			if places.size() < 3 and race.race_time - go >= [15.0, 30.0, 60.0][places.size()]:
				places.append(race.position_of(race.index_of(player_car)))
			for a in race.car_count():
				var car_ai := race.vehicle_at(a).get_node_or_null("AIDriver") as AIDriver
				if car_ai != null and race.vehicle_at(a) != player_car and car_ai.brake > 0.3 and not a in race.finish_order:
					brakes[car_ai.limiter] = float(brakes.get(car_ai.limiter, 0.0)) + 1.0 / 120.0
					_brakes[car_ai.limiter] = float(_brakes.get(car_ai.limiter, 0.0)) + 1.0 / 120.0
		for a in race.car_count():
			var car := race.vehicle_at(a)
			var knock := (car.linear_velocity - Vector3(last_v.get(a, car.linear_velocity))).length()
			last_v[a] = car.linear_velocity
			bump_wait[a] = maxi(int(bump_wait.get(a, 0)) - 1, 0)
			if knock > 0.7 and race.state == RaceDirector.State.RACING and bump_wait[a] == 0:
				for b in race.car_count():
					if b != a and race.vehicle_at(b).global_position.distance_to(car.global_position) < 5.2:
						bumps += 1
						bump_wait[a] = 60
						break
		if race.state != RaceDirector.State.RACING or race.race_time < 6.0 or ticks % 12 != 0:
			continue
		for a in race.car_count():
			if a in race.finish_order:
				continue
			var nearest := 999.0
			for b in race.car_count():
				if b == a or b in race.finish_order:
					continue
				var gap := race._race_distance(b) - race._race_distance(a)
				if gap > 0.0:
					nearest = minf(nearest, gap)
				if b > a and absf(gap) > SWAP_GAP:
					var key := "%d %d" % [a, b]
					var now := -1 if gap > 0.0 else 1
					if ahead.has(key) and ahead[key] != now:
						overtakes += 1
					ahead[key] = now
			if nearest < 15.0:
				close_time += 0.1
	var resets := 0
	var damage := 0.0
	var defends := 0
	var mistakes := 0
	var dives := 0
	var times: Array[float] = []
	var rows: Array[String] = []
	for i in race.standings():
		var car := race.vehicle_at(i)
		var ai := car.get_node_or_null("AIDriver") as AIDriver
		resets += ai.resets
		damage += car.damage.total() if car.damage else 0.0
		defends += int(ai.get("defends") if ai.get("defends") != null else 0)
		mistakes += int(ai.get("mistakes") if ai.get("mistakes") != null else 0)
		dives += int(ai.get("dives") if ai.get("dives") != null else 0)
		if race.finish_times.has(i):
			times.append(race.finish_times[i])
		rows.append("    %-7s %-9s skill %.2f  %s  resets %d damage %.2f%s" % [race.name_at(i), String(car.get_meta(&"car_id", "?")), ai.skill,
				LapTimer.format_time(race.finish_times[i]) if race.finish_times.has(i) else "DNF", ai.resets,
				car.damage.total() if car.damage else 0.0,
				"  defends %d dives %d mistakes %d" % [ai.get("defends"), ai.get("dives"), ai.get("mistakes")] if ai.get("defends") != null else ""])
	var mean := 0.0
	for t in times:
		mean += t / maxi(times.size(), 1)
	var spread: float = times.max() - times.min() if not times.is_empty() else 0.0
	print("%-12s seed %d  finished %d/%d  overtakes %3d  close %5.1f s  resets %2d  bumps %2d  damage %5.2f  mean %6.1f s  spread %5.1f s  defends %d dives %d mistakes %d" % [track_id, race_seed,
			race.finish_order.size(), race.car_count(), overtakes, close_time, resets, bumps, damage, mean, spread, defends, dives, mistakes])
	print("    back-of-grid car (skill %.2f) place after 15/30/60 s: %s  heavy braking %s" % [player_skill, places, JSON.stringify(brakes)])
	if OS.get_cmdline_user_args().has("--rows"):
		for r in rows:
			print(r)
	for pair in [["races", 1], ["finished", race.finish_order.size()], ["overtakes", overtakes], ["close", close_time], ["resets", resets], ["bumps", bumps], ["damage", damage],
			["mean", mean], ["spread", spread], ["defends", defends], ["dives", dives], ["mistakes", mistakes]]:
		_totals[pair[0]] = float(_totals.get(pair[0], 0.0)) + float(pair[1])
	scene.queue_free()
	current_scene = null
	for i in 4:
		await process_frame
