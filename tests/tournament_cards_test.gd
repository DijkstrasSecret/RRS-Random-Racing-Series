extends SceneTree
## Tournament cards: stat stacking, X items (charges, burst, KERS), Y items
## (engine map), perfect shift, carried-over tyre wear / damage, no recovery,
## and the DNF rule (upside down -> out of the race).
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/tournament_cards_test.gd

var _ok := true


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	GameSettings.damage = 2
	# --- Stat maths.
	var r := Tournament._racer("T", "bavaro", Color.WHITE, 1, 0.0)
	r.stats = [{"id": "tire_pres", "tier": 3}, {"id": "tire_pres", "tier": 2}, {"id": "power", "tier": 0}, {"id": "power", "tier": 1}]
	_check("tyre wear stacks multiplicatively (keep %.3f, want 0.385)" % Upgrades.stat_scale(r, "tire_pres"),
			absf(Upgrades.stat_scale(r, "tire_pres") - 0.385) < 0.001)
	_check("power adds up (+%.1f%%, want 7.5)" % (Upgrades.stat_total(r, "power") * 100.0), absf(Upgrades.stat_total(r, "power") - 0.075) < 0.0001)
	_check("legendary power card costs 18", Upgrades.cost({"id": "power", "tier": 3}) == 18)
	var odds0 := Upgrades.odds(0, 5)
	var odds4 := Upgrades.odds(4, 5)
	_check("legendary only shows up later (%.2f -> %.2f)" % [odds0[3], odds4[3]], odds0[3] == 0.0 and odds4[3] > 0.05)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var offers := Upgrades.offers(rng, r, 2, 5)
	_check("shop: 2 stat + 2 unlock cards", offers.size() == 4 and Upgrades.is_stat(offers[0].id) and Upgrades.is_stat(offers[1].id)
			and not Upgrades.is_stat(offers[2].id) and not Upgrades.is_stat(offers[3].id))
	# Passives cap at 4; a duplicate levels up.
	r.unlocks = {"perfect_shift": 1, "heel_toe": 1, "drift_harvest": 1, "late_braker": 1}
	_check("5th passive refused", not Upgrades.can_take(r, "clean_sector"))
	_check("owned passive can level up", Upgrades.can_take(r, "heel_toe"))
	Upgrades.take(r, {"id": "heel_toe", "tier": -1})
	_check("heel-toe now level 2", Upgrades.level_of(r, "heel_toe") == 2)
	Upgrades.take(r, {"id": "kers", "tier": -1})
	Upgrades.take(r, {"id": "nitro_charges", "tier": -1})
	_check("a new X item replaces the old one", r.power_slot == "nitro_charges" and r.power_level == 1)

	# --- Car effects.
	Tournament.active = true
	var plain := await _car_with({})
	var base_torque: float = plain.config.max_torque
	_free(plain)
	var rc := Tournament._racer("T", "bavaro", Color.WHITE, 1, 0.0)
	rc.stats = [{"id": "power", "tier": 3}]
	rc.power_slot = "nitro_charges"
	rc.power_level = 1
	rc.tactical_slot = "engine_map"
	rc.tactical_level = 1
	rc.unlocks = {"perfect_shift": 1}
	rc.tyre_wear = [0.5, 0.5, 0.4, 0.4]
	rc.damage = [0.3, 0.0, 0.0, 0.0, 0.0]
	var car := await _car_with(rc)
	var perks := car.get_node("Perks") as CarPerks
	var inp := car.input
	_check("power card: torque %.0f -> %.0f (+9%%)" % [base_torque, car.config.max_torque], absf(car.config.max_torque / base_torque - 1.09) < 0.001)
	_check("tyre wear carried over (%.2f)" % car.wheels[0].wear, absf(car.wheels[0].wear - 0.5) < 0.01)
	_check("damage carried over (front %.2f)" % car.damage.zones[0], car.damage.zones[0] >= 0.29)
	_check("charges: 3 x 1 s of energy (%.1f)" % perks.capacity, absf(perks.capacity - 3.0) < 0.01)
	inp.throttle = 1.0
	await _ticks(120)
	inp.nitro = true
	await _ticks(2)
	inp.nitro = false
	await _ticks(30)
	_check("X press fires a pulse (boosting %s, power x%.2f)" % [perks.boosting, car.perk_power], perks.boosting and car.perk_power > 1.4)
	await _ticks(120)
	_check("one charge used (%.2f left)" % perks.energy, absf(perks.energy - 2.0) < 0.05)
	# Engine map toggles with Y.
	var before := car.perk_power
	inp.tactical_pressed = true
	await _ticks(1)
	inp.tactical_pressed = false
	await _ticks(2)
	_check("Y switches to the STABILITY map (power x%.2f -> x%.2f)" % [before, car.perk_power], perks.map_stability and car.perk_power < before)
	# Perfect shift: upshift at the redline.
	perks._prev_rpm_frac = 0.97
	inp.shift_up_pressed = true
	await _ticks(1)
	inp.shift_up_pressed = false
	_check("perfect shift boost (%.2f s)" % perks.shift_bonus, perks.shift_bonus > 0.5)
	# No recovery in a tournament.
	car.teleport(Transform3D(Basis(Vector3.FORWARD, PI), car.global_position + Vector3.UP * 1.5))
	await _ticks(60)
	inp.recover_pressed = true
	await _ticks(1)
	inp.recover_pressed = false
	await _ticks(5)
	_check("recover does nothing in a tournament (up %.2f)" % car.global_basis.y.y, car.global_basis.y.y < 0.3)
	_free(car)

	# KERS charges under braking.
	var rk := Tournament._racer("T", "bavaro", Color.WHITE, 1, 0.0)
	rk.power_slot = "kers"
	rk.power_level = 1
	car = await _car_with(rk)
	perks = car.get_node("Perks") as CarPerks
	_check("KERS starts empty", perks.energy == 0.0)
	car.linear_velocity = -car.global_basis.z * 30.0
	car.input.brake = 1.0
	await _ticks(120)
	_check("KERS stored energy braking (%.2f s)" % perks.energy, perks.energy > 0.3)
	_free(car)
	Tournament.active = false

	# --- DNF: a tournament race, flip the player's car.
	Tournament.start(1, PackedStringArray(["monza"]), 15, 3)
	var scene := (load(Tournament.race_scene()) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	var race := scene.find_children("*", "RaceDirector", true, false)[0] as RaceDirector
	while race.state != RaceDirector.State.RACING or race.race_time < 4.0:
		await physics_frame
	var me: Vehicle = null
	for i in race.car_count():
		if race.is_human(i):
			me = race.vehicle_at(i)
	me.teleport(Transform3D(Basis(Vector3.FORWARD, PI), me.global_position + Vector3.UP * 1.5))
	await _ticks(120 * 7)
	var idx := race.index_of(me)
	_check("upside down for 5 s: DNF (retired %s, position %d of %d)" % [race.is_retired(idx), race.position_of(idx), race.car_count()],
			race.is_retired(idx) and race.position_of(idx) == race.car_count())
	_check("race ends when the only human is out", race.state == RaceDirector.State.FINISHED)
	Tournament.finish()
	print("tournament_cards_test %s" % ("PASSED" if _ok else "FAILED"))
	quit()


func _car_with(racer: Dictionary) -> Vehicle:
	var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
	var car := scene.get_node("Vehicle") as Vehicle
	var player := car.get_node("PlayerInput")
	car.remove_child(player)
	player.free()
	var inp := VehicleInput.new()
	inp.name = "TestInput"
	car.add_child(inp)
	# The real path: the practice scene gives player 1 their tournament cards.
	Tournament.tracks = PackedStringArray(["monza"])
	Tournament.race_index = 0
	Tournament.players = 1
	Tournament.racers.clear()
	if not racer.is_empty():
		Tournament.racers.append(racer)
	root.add_child(scene)
	current_scene = scene
	await _ticks(90)
	car.input = inp
	return car


func _free(car: Vehicle) -> void:
	var scene := car.get_parent()
	scene.queue_free()
	current_scene = null
	await _ticks(3)


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_ok = false


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame
