extends SceneTree
## How fast a rival can lap alone: one AI car, a few skill values (above 1 =
## past the hard setting), best lap, resets, and how it gets off the line.
## Used to find how much pace the speed plan leaves on the table.
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/rival_pace.gd -- [--track=monza] [--car=orion] [--skills=0.95,1.2] [--laps=3]
##       [--tune=tune_brake:1.2;tune_corner:1.1] [--events] [--launch]
## A skill below 0 is the reference: flat out with the wheel straight (launch only).
## --events lists every brake on the last lap (where, how hard, and why);
## --launch prints the pedals and steering for the first 3 s.


var _tune := {}
var _trace := Vector2.ZERO


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	GameSettings.track = "monza"
	GameSettings.p1_car = "orion"
	var skills: Array = [0.95]
	var laps := 3
	for a in OS.get_cmdline_user_args():
		var value := a.get_slice("=", 1)
		if a.begins_with("--track="):
			GameSettings.track = value
		elif a.begins_with("--car="):
			GameSettings.p1_car = value
		elif a.begins_with("--skills="):
			skills = Array(value.split(","))
		elif a.begins_with("--laps="):
			laps = int(value)
		elif a.begins_with("--trace="):
			_trace = Vector2(float(value.get_slice(":", 0)), float(value.get_slice(":", 1)))
		elif a.begins_with("--tune="):
			for kv in value.split(";"):
				_tune[kv.get_slice(":", 0)] = float(kv.get_slice(":", 1))
	for s in skills:
		await _laps(float(s), laps)
	quit()


func _laps(skill: float, laps: int) -> void:
	GameSettings.ai_count = 0
	GameSettings.laps = laps
	var scene := (load(GameSettings.RACE) as PackedScene).instantiate()
	var car := scene.get_node("Vehicle") as Vehicle
	var player := car.get_node("PlayerInput")
	car.remove_child(player)
	player.free()
	var flat := skill < 0.0  # reference: flat out, wheel straight, from the GO
	var ai = VehicleInput.new() if flat else AIDriver.new()
	ai.name = "AIDriver"
	if flat:
		ai.throttle = 1.0
	else:
		ai.skill = skill
		ai.consistency = 1.0
		ai.nerve = 1.0
		for k in _tune:
			ai.set(k, _tune[k])
	car.add_child(ai)
	root.add_child(scene)
	current_scene = scene
	var race := scene.find_children("*", "RaceDirector", true, false)[0] as RaceDirector
	var me := race.index_of(car)
	var start_pos := Vector3.ZERO
	var go := -1.0
	var launch := {}
	var thr_sum := 0.0
	var thr_n := 0
	var brake_time := 0.0
	var max_lat := 0.0
	var max_brake_g := 0.0
	var ev := {}
	var timer: LapTimer = null
	while race.race_time < 600.0 and not race.finish_times.has(me):
		await physics_frame
		if race.state != RaceDirector.State.RACING:
			start_pos = car.global_position
			continue
		if go < 0.0:
			go = race.race_time
			me = race.index_of(car)
			timer = race.timer_at(me)
		var t := race.race_time - go
		var d := car.global_position.distance_to(start_pos)
		for mark: float in [50.0, 100.0, 200.0]:
			if d >= mark and not launch.has(mark):
				launch[mark] = t
		if flat:
			ai.throttle = 1.0
			ai.brake = 0.0
			ai.handbrake = 0.0
			if t > 15.0 or launch.has(200.0):
				break
		if not flat and _trace.y > 0.0:
			var at: float = ai._circuit.progress_at(car.global_position)
			if at > _trace.x and at < _trace.y and t < 60.0 and int(t * 120.0) % 6 == 0:
				print("    %5.0f m v %5.1f km/h plan %5.1f target %5.1f %-10s thr %.2f brk %.2f steer %+.2f lane %+.1f lat %+.1f slip %4.1f deg corner %.0f m curv %.3f" % [at, car.forward_speed * 3.6,
						ai._circuit.profile_speed(ai._profile, at) * 3.6, ai.target_speed * 3.6, ai.limiter, ai.throttle, ai.brake, ai.steer, ai.lane,
						(car.global_position - ai._circuit.point_at(at)).dot(ai._circuit.right_at(at)), rad_to_deg(atan2(car.lateral_speed, maxf(absf(car.forward_speed), 0.5))), ai._corner_dist, ai._corner_curv])
		if not flat and OS.get_cmdline_user_args().has("--launch") and t < 3.0 and int(t * 120.0) % 12 == 0:
			print("    t %.1f v %4.1f thr %.2f brk %.2f steer %+.2f target %4.1f %s lane %+.1f gear %d rpm %.0f" % [t, car.forward_speed, ai.throttle, ai.brake, ai.steer, ai.target_speed, ai.limiter, ai.lane,
					car.drivetrain.gear, car.drivetrain.rpm if "rpm" in car.drivetrain else 0.0])
		if t < 3.0:
			thr_sum += ai.throttle
			thr_n += 1
		if ai.brake > 0.05:
			brake_time += 1.0 / 120.0
		if not flat and OS.get_cmdline_user_args().has("--events") and timer.lap == laps - 1:
			var off: float = ai._circuit.progress_at(car.global_position)
			if ai.brake > 0.05:
				if ev.is_empty():
					ev = {"at": off, "v0": car.forward_speed, "vmin": car.forward_speed, "t": 0.0, "why": {}, "peak": 0.0, "plan_min": 999.0}
				ev.t += 1.0 / 120.0
				ev.vmin = minf(ev.vmin, car.forward_speed)
				ev.peak = maxf(ev.peak, ai.brake)
				ev.why[ai.limiter] = float(ev.why.get(ai.limiter, 0.0)) + 1.0 / 120.0
			elif not ev.is_empty():
				ev.plan_min = ai._circuit.profile_speed(ai._profile, off)
				print("    brake at %5.0f m: %3.0f -> %3.0f km/h, %.1f s, peak %.2f, plan here %3.0f, curv ahead %.4f  %s" % [ev.at, ev.v0 * 3.6, ev.vmin * 3.6, ev.t, ev.peak,
						ev.plan_min * 3.6, ai._corner_curv, JSON.stringify(ev.why)])
				ev = {}
		if not flat and OS.get_cmdline_user_args().has("--hits") and (absf(car.g_lat) > 3.0 or -car.g_long > 3.0) and Engine.get_physics_frames() % 6 == 0:
			var at2: float = ai._circuit.progress_at(car.global_position)
			print("    HIT t %.1f at %.0f m, %.0f km/h, g_lat %.1f g_long %.1f, lateral %+.1f, %.1f m from centre, pitting %s in_pit %s, damage %.2f" % [t, at2, car.forward_speed * 3.6, car.g_lat, car.g_long,
					ai._circuit.lateral_of(car.global_position), ai._circuit.distance_from_centre(car.global_position), ai._pitting, car.in_pit_lane, car.damage.total() if car.damage else 0.0])
		if car.forward_speed > 10.0:
			max_lat = maxf(max_lat, absf(car.g_lat))
			max_brake_g = maxf(max_brake_g, -car.g_long)
	print("%-10s %-8s %s skill %.2f  best %s  total %s  resets %d  braking %.0f s  max lat %.2f g  max brake %.2f g  0-50/100/200 m %.2f/%.2f/%.2f s  throttle first 3 s %.2f" % [
			GameSettings.track, GameSettings.p1_car, JSON.stringify(_tune), skill, LapTimer.format_time(timer.best_lap) if timer.best_lap > 0.0 else "-",
			LapTimer.format_time(race.finish_times[me]) if race.finish_times.has(me) else "DNF", 0 if flat else ai.resets, brake_time,
			max_lat, max_brake_g, launch.get(50.0, -1.0), launch.get(100.0, -1.0), launch.get(200.0, -1.0), thr_sum / maxi(thr_n, 1)])
	scene.queue_free()
	current_scene = null
	for i in 4:
		await process_frame
