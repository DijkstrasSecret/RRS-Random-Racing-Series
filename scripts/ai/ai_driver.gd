class_name AIDriver
extends VehicleInput
## AI racing driver (design concept §9). Drives through the same VehicleInput
## as a player, so it gets no extra grip or power.
## - Speed: a per-lap speed plan (corner limits + braking zones) built once
##   from the circuit, scaled by `skill`.
## - Line: drifts toward the inside of the coming corner, using the road width.
## - Racing: tucks into the slipstream, picks a side and commits to a pass,
##   covers the inside when attacked, gives room side by side, and makes
##   mistakes (more of them under pressure). How much of each is the driver's
##   character: see DriverStyle.
## - If it ends up lost (off the road or facing the wrong way) for a few
##   seconds, it is put back on the track like in most racing games.

## 0 = cautious, 1 = right on the limit.
@export_range(0.0, 1.0) var skill: float = 0.8
@export_group("Character")
@export_range(0.0, 1.0) var aggression: float = 0.5
@export_range(0.0, 1.0) var defence: float = 0.5
@export_range(0.0, 1.0) var nerve: float = 0.7
@export_range(0.0, 1.0) var consistency: float = 0.8
@export_group("Driving")
## Personal preference for one side of the road (metres, + = right).
@export var lane_bias: float = 0.0
@export var lookahead_base: float = 8.0
@export var lookahead_per_mps: float = 0.42
## Extra wheel angle on top of pure geometry, to cover tyre slip.
@export var steer_gain: float = 1.3
## Most steering input the AI uses.
@export var max_steer_input: float = 1.0
## Test knobs (1 = as tuned): grip used by the corner and braking plan,
## and how much throttle is taken away while steering.
var tune_corner := 1.0
var tune_brake := 1.0
var tune_turn_cut := 0.9
## Seconds lost (off the road or facing the wrong way) before it resets.
@export var reset_after: float = 3.0

var resets: int = 0
var target_speed: float = 0.0
## What set target_speed this frame ("plan", "follow", "slide", ...).
var limiter: String = ""
var _traffic_reason := ""
var _since_go := 0.0
var lane: float = 0.0
## Counted for tests and the HUD.
var dives: int = 0
var defends: int = 0
var mistakes: int = 0
## Set for a moment when something worth telling the player happens
## ("RUNS WIDE", "LOCKS UP", ...); event_frame is in physics frames.
var event: String = ""
var event_frame: int = -100000

var _vehicle: Vehicle
var _circuit: Circuit
var _profile := PackedFloat32Array()
var _lost_time: float = 0.0
## Shrinks a little every time the car has to be reset, so a car that keeps
## overcooking a corner learns to take it slower.
var _corner_scale: float = 1.0


func poll(delta: float) -> void:
	if _circuit == null and not _setup():
		return
	_check_tyres(delta)
	var v := _vehicle.forward_speed
	var pos := _vehicle.global_position
	_refresh_field()
	var here: Array = _field[_vehicle.get_instance_id()]
	var off: float = here[1]
	var road_half := _circuit.road_width * 0.5 - 1.7

	# --- Where on the road: inside of the next corner, plus traffic moves.
	var curv_ahead := _circuit.curvature_at(off + 12.0 + maxf(v, 0.0) * 0.6)
	var line := -clampf(curv_ahead * 220.0, -1.0, 1.0) * road_half * 0.75  # + curv = left turn
	_look_for_corner(off)
	_measure_bend(off, v)
	_feel_pressure(delta, off, v)
	_think_mistakes(delta, off, v)
	# Hairpins: turn in late. Going for the inside early means arriving at the
	# apex still pointing straight on, and running wide.
	if _corner_dist > 0.0 and _corner_dist < 60.0:
		line *= lerpf(1.0, 0.2, clampf((_corner_curv - 0.018) / 0.008, 0.0, 1.0))
	var traffic := _race_others(delta, off, here[2], v, clampf(line + lane_bias, -road_half, road_half), road_half)
	var planned := _circuit.profile_speed(_profile, off + maxf(v, 0.0) * 0.3)
	var lane_rate := 4.5 if _attack != null else 3.5
	# Hard on the brakes for a corner the tyres have no grip left to change
	# lanes with: most of that has to be done before.
	if _corner_dist < 40.0 and v > planned + 1.0:
		lane_rate = 1.8
	# Drifting outward in a bend uses up the same grip.
	if _bend > 0.35 and (traffic.x - lane) * _bend_side < 0.0:
		lane_rate = minf(lane_rate, 1.5)
	# Off the line: straight ahead and flat out, ease over once rolling.
	_since_go = 0.0 if _vehicle.controls_locked else _since_go + delta
	var launching := _since_go < 3.0 and v < 25.0
	if launching:
		lane_rate = 0.8
	lane = move_toward(lane, traffic.x, lane_rate * delta)
	if _vehicle.controls_locked:
		lane = here[2]
	_think_pits(off)

	# --- Steering: pure pursuit to a point ahead on that line.
	var look := lookahead_base + maxf(v, 0.0) * lookahead_per_mps
	var aim_lane := lane
	if _pitting:
		aim_lane = _circuit.pit_lateral(off + look) if absf(_circuit.pit_lateral(off + look)) > 0.1 else lane
		lane = aim_lane
	var target_point := _circuit.point_at(off + look) + _circuit.right_at(off + look) * aim_lane
	var local := _vehicle.to_local(target_point)
	var dist_sq := maxf(local.x * local.x + local.z * local.z, 1.0)
	var arc_curvature := 2.0 * local.x / dist_sq  # + = target to the right
	var wheel_angle := atan(arc_curvature * _vehicle.wheelbase()) * steer_gain
	steer = clampf(wheel_angle / _vehicle.current_steer_limit(), -max_steer_input, max_steer_input)

	# --- Speed: follow the plan, respect traffic, back off when sliding.
	target_speed = planned * _pace_scale
	limiter = "plan" if _mistake == Mistake.NONE else "mistake"
	# Right on the inside the bend is tighter than the speed plan thinks.
	if _corner_dist < 25.0:
		var tight := clampf((_corner_curv - 0.022) / 0.016, 0.0, 1.0)
		var tucked := maxf(lane * _corner_side - lerpf(road_half * 0.75, 0.5, tight), 0.0)
		_cap(target_speed * sqrt(clampf(1.0 - _corner_curv * tucked, 0.7, 1.0)), "tucked")
	_cap(traffic.y, _traffic_reason)
	if _pitting:
		_cap(_pit_speed(off), "pit")
	var slip := absf(atan2(_vehicle.lateral_speed, maxf(absf(v), 0.5)))
	if v > 8.0 and slip > deg_to_rad(7.0):
		_cap(v - 2.0, "slide")
	# Full lock and still not turning enough (understeer), even in a slow
	# hairpin: scrub off speed now rather than at the edge of the road.
	if v > 8.0 and absf(steer) >= max_steer_input * 0.97:
		_cap(v - lerpf(1.0, 2.5, clampf((v - 8.0) / 6.0, 0.0, 1.0)), "understeer")

	var from_centre := _circuit.distance_from_centre(pos)
	# Running wide toward the edge: ease off before it reaches the grass.
	if from_centre > _circuit.road_width * 0.45:
		_cap(maxf(v - 1.5, 14.0), "edge")
	var off_line := from_centre > _circuit.road_width * 0.75 and not _pitting and not _vehicle.in_pit_lane
	if off_line:
		_cap(14.0, "off road")
	var track_dir := _circuit.direction_at(off)
	var wrong_way := (-_vehicle.global_basis.z).dot(track_dir) < -0.2
	# (Standing in the pit box being serviced is not stuck.)
	var stuck := absf(v) < 1.0 and not _vehicle.controls_locked and _vehicle.pit_service_left <= 0.0 and not (_pitting and _vehicle.in_pit_lane)
	_lost_time = _lost_time + delta if (off_line or wrong_way or stuck) else 0.0
	if _lost_time > reset_after and Tournament.active and _wrecked():
		_lost_time = 0.0  # no recovery in a tournament: the race director retires it
	if _lost_time > reset_after:
		if OS.get_cmdline_user_args().has("--log-resets"):
			print("    reset %s at %.0f m (%s%s%s) t %.1f s, %.0f km/h, %.1f m from centre, pitting %s" % [_vehicle.name, off, "off line " if off_line else "",
				"wrong way " if wrong_way else "", "stuck" if stuck else "", _find_race().race_time if _find_race() else 0.0, v * 3.6, from_centre, _pitting])
		if OS.get_cmdline_user_args().has("--log-resets"):
			var gear := ""
			for w in _vehicle.wheels:
				gear += "%s%s%s " % ["F" if w.punctured else "", "B" if absf(w.toe) > 0.02 else "", "X" if w.detached else ""]
			print("      gear [%s] pit_lane %s service %.1f" % [gear, _vehicle.in_pit_lane, _vehicle.pit_service_left])
		_reset_onto_track(off, track_dir)
		return

	# --- Pedals in proportion to the speed error; gentle while turning hard.
	var err := v - target_speed
	var turning := absf(steer) / maxf(max_steer_input, 0.01)
	if err > 0.4:
		# A little too fast: just lift. Much too fast: the pedal goes down hard.
		throttle = 0.0
		brake = clampf((err - 0.4) / 1.2, 0.0, 1.0) * (1.0 - turning * 0.4)
	else:
		brake = 0.0
		# At full lock a front-drive car needs its front grip for turning.
		throttle = clampf(-err / 3.0, 0.25, 1.0) * clampf(1.0 - turning * tune_turn_cut * (0.2 if launching else 1.0), 0.08, 1.0)
	handbrake = 0.0
	if _mistake == Mistake.MISSED_GEAR:
		# It happens when the power goes back on, not while braking.
		if throttle > 0.4 and v > 10.0:
			if _mistake_time >= MISTAKE_SECONDS[_mistake]:
				_announce("MISSES A GEAR")
			throttle = 0.0
		else:
			_mistake_time += delta
	# Nitro on the straights: flat out, wheel straight, and the road ahead fast.
	nitro = throttle > 0.95 and turning < 0.15 and target_speed > v + 4.0
	tactical = nitro


## Lowers the target speed, remembering why (for tests).
func _cap(speed: float, reason: String) -> void:
	if speed < target_speed:
		target_speed = speed
		limiter = reason


func _setup() -> bool:
	_circuit = get_tree().get_first_node_in_group("circuit") as Circuit
	_vehicle = get_parent() as Vehicle
	if _circuit == null or _vehicle == null:
		_circuit = null
		return false
	# AI cars use the Arcade assists (stability and counter-steer help); this
	# changes how the car is driven, not how much grip it has.
	_vehicle.set_handling_profile(HandlingAssists.Profile.ARCADE)
	_build_profile()
	return true


func _build_profile() -> void:
	# Heavy cars lose grip under load (tyre load sensitivity): plan for it.
	var heavy := clampf(1.0 - (_vehicle.config.mass - 1300.0) / 9000.0, 0.85, 1.05)
	_tyre_condition = _mean_tyre_condition()
	var grip := _vehicle.config.tire_grip * heavy * 9.81 * _tyre_condition
	# Braking: every car stops at about 0.88 x its tyre grip in g with the pedal
	# fully down (tests/brake_probe.gd), heavy or not. A top driver uses nearly
	# all of it, as late as it can.
	var stop := _vehicle.config.tire_grip * 0.88 * 9.81 * _tyre_condition
	# A flat tyre or a wheel gone: the car pulls and slides, so nurse it home.
	_flat = _has_flat()
	if _flat:
		grip *= 0.7
		stop *= 0.7
	_profile = _circuit.build_speed_profile(grip * lerpf(0.46, 0.63, skill) * _corner_scale * tune_corner,
			stop * lerpf(0.40, 0.96, skill) * tune_brake, 95.0)


var _tyre_condition := 1.0
var _flat := false
var _pitting := false


## Decides when to pit (worn tyres or heavy damage, at least 2 laps to go)
## and when the stop is over.
func _think_pits(off: float) -> void:
	if _circuit.pit.is_empty():
		return
	if _pitting:
		# Done once served and back out on the track.
		if _vehicle.pit_stops > _stops_at_entry and absf(_circuit.pit_lateral(off)) < 0.5:
			_pitting = false
		return
	var race := get_tree().get_first_node_in_group("race_director") as RaceDirector
	if race == null or race.state != RaceDirector.State.RACING:
		return
	var me := race.index_of(_vehicle)
	if me < 0 or race.laps - race.completed_laps(me) < 2 or _vehicle.pit_stops >= 3:
		return
	var worn := _mean_tyre_condition() < 0.86
	var broken := _vehicle.damage != null and _vehicle.damage.total() > 0.35
	for w in _vehicle.wheels:
		if w.punctured or w.detached or absf(w.toe) > 0.04:
			broken = true
	if not (worn or broken):
		return
	# Commit when the pit entry is coming up.
	var to_entry := fposmod(float(_circuit.pit.from) - off, _circuit.length)
	if to_entry > 40.0 and to_entry < 500.0:
		_pitting = true
		_stops_at_entry = _vehicle.pit_stops


var _stops_at_entry := 0


## Speed plan in the pit lane: the limit, then a stop in the box zone.
func _pit_speed(off: float) -> float:
	if absf(_circuit.pit_lateral(off)) < 2.0 and _circuit._rel(off) < float(_circuit.pit.from) + 10.0:
		return 999.0  # not in the lane yet
	var limit := Circuit.PIT_LIMIT - 0.6
	if _vehicle.pit_stops > _stops_at_entry or _vehicle.pit_service_left > 0.0:
		return limit if _vehicle.pit_service_left <= 0.0 else 0.0
	var to_box := _circuit._rel(_circuit.pit_zone_mid()) - _circuit._rel(off)
	if to_box < 0.5:
		return 0.0
	return minf(limit, sqrt(2.0 * 3.5 * maxf(to_box - 1.0, 0.0)))
var _tyre_check := 0.0


func _has_flat() -> bool:
	for w in _vehicle.wheels:
		if w.punctured or w.detached:
			return true
	return false


## Average grip of the four tyres (heat and wear), 1 = fresh and warm.
func _mean_tyre_condition() -> float:
	if _vehicle == null or _vehicle.wheels.is_empty():
		return 1.0
	var c := 0.0
	for w in _vehicle.wheels:
		c += 0.3 if w.detached else w.condition() * (1.0 - 0.55 * w.deflate)
	return c / _vehicle.wheels.size()


## Every couple of seconds: re-plan corner speeds if the tyres have changed.
func _check_tyres(delta: float) -> void:
	_tyre_check += delta
	if _tyre_check < 2.0:
		return
	_tyre_check = 0.0
	if absf(_mean_tyre_condition() - _tyre_condition) > 0.015 or _has_flat() != _flat:
		_build_profile()


# --- Racing the others -------------------------------------------------------

## Where every car is along and across the track, worked out once per physics
## frame and shared by all AI drivers: instance id -> [car, off, lateral, speed,
## acceleration].
static var _field := {}
static var _field_frame := -1
static var _field_circuit := 0

enum Mistake { NONE, LATE_BRAKE, LOCK_UP, WIDE, MISSED_GEAR }

const MISTAKE_SECONDS := {Mistake.LATE_BRAKE: 1.6, Mistake.LOCK_UP: 1.8, Mistake.WIDE: 2.6, Mistake.MISSED_GEAR: 1.0}
const CORNER_CURV := 0.008  ## tighter than a 125 m radius counts as a corner
const PASS_LANE := 3.0  ## metres beside the car being passed
const CAR_LENGTH := 4.6

## 0..1: how long someone has been right behind.
var pressure := 0.0

var _corner_dist := 999.0  ## metres to the next corner (0 = in one)
var _corner_side := 0.0  ## its inside: -1 left, +1 right
var _corner_curv := 0.0  ## how tight it gets
var _bend := 0.0
var _bend_side := 0.0
var _corner_id := -1
var _rolled_corner := -1
var _attack: Vehicle
var _attack_side := 0.0
var _attack_time := 0.0
var _attack_wait := 0.0
var _dived := false
var _defend_lane := NAN
var _defended_corner := -1
var _mistake := Mistake.NONE
var _mistake_time := 0.0
var _pace_scale := 1.0
var _grudge: Vehicle
var _grudge_time := 0.0
var _last_velocity := Vector3.ZERO
var _race: RaceDirector


func _refresh_field() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _field_frame and _field_circuit == _circuit.get_instance_id() and _field.has(_vehicle.get_instance_id()):
		return
	_field_frame = frame
	_field_circuit = _circuit.get_instance_id()
	var before := _field.duplicate()
	_field.clear()
	var dt := get_physics_process_delta_time()
	for node in get_tree().get_nodes_in_group("vehicles"):
		var car := node as Vehicle
		if car == null:
			continue
		var off := _circuit.progress_at(car.global_position)
		var lat := (car.global_position - _circuit.point_at(off)).dot(_circuit.right_at(off))
		var speed := car.linear_velocity.dot(_circuit.direction_at(off))
		var id := car.get_instance_id()
		# How hard it is speeding up (+) or braking (-): its brake lights.
		var accel := 0.0
		if before.has(id):
			accel = lerpf(float(before[id][4]), (speed - float(before[id][3])) / dt, 0.2)
		_field[id] = [car, off, lat, speed, accel]


## Signed distance along the track from `from` to `to` (+ = ahead).
func _gap(from: float, to: float) -> float:
	return fposmod(to - from + _circuit.length * 0.5, _circuit.length) - _circuit.length * 0.5


## The next corner within 170 m (a few looks per second would do, but the
## curvature table is cheap).
func _look_for_corner(off: float) -> void:
	_corner_dist = 999.0
	var d := 0.0
	while d <= 170.0:
		var c := _circuit.curvature_at(off + d)
		if absf(c) > CORNER_CURV:
			_corner_dist = d
			_corner_side = -signf(c)
			_corner_id = int(fposmod(off + d, _circuit.length) / 25.0)
			_corner_curv = 0.0
			for step: float in [0.0, 12.0, 24.0, 36.0]:
				_corner_curv = maxf(_corner_curv, absf(_circuit.curvature_at(off + d + step)))
			return
		d += 8.0


## How much of the tyres' grip the bend here and just ahead needs at this
## speed (about 0.6 = as much as the driver dares), and its inside.
func _measure_bend(off: float, v: float) -> void:
	var k := 0.0
	for t: float in [0.0, 0.35, 0.7, 1.1]:
		var c := _circuit.curvature_at(off + v * t)
		if absf(c) > absf(k):
			k = c
	_bend_side = -signf(k)
	_bend = absf(k) * v * v / Circuit._banked_accel(_vehicle.config.tire_grip * 9.81 * float(Circuit.SURFACE_GRIP[_circuit.surface_at(off)]),
			_circuit.bank_slope_at(off))


func _find_race() -> RaceDirector:
	if _race == null:
		_race = get_tree().get_first_node_in_group("race_director") as RaceDirector
	return _race


## True if that car is racing us for position (not lapping or being lapped).
func _same_lap(other: Vehicle) -> bool:
	var race := _find_race()
	if race == null:
		return true
	var a := race.index_of(_vehicle)
	var b := race.index_of(other)
	if a < 0 or b < 0:
		return true
	return absf(race._race_distance(a) - race._race_distance(b)) < _circuit.length * 0.5


func _announce(text: String) -> void:
	event = text
	event_frame = Engine.get_physics_frames()


## Somebody close behind wears a driver down; contact starts a grudge.
func _feel_pressure(delta: float, off: float, v: float) -> void:
	var chased := false
	var knock := (_vehicle.linear_velocity - _last_velocity).length()
	_last_velocity = _vehicle.linear_velocity
	for id in _field:
		var e: Array = _field[id]
		if e[0] == _vehicle:
			continue
		var gap := _gap(off, e[1])
		if gap < 0.0 and gap > -14.0 and v > 12.0 and _same_lap(e[0]):
			chased = true
		if knock > 1.0 and v > 8.0 and (e[0] as Vehicle).global_position.distance_to(_vehicle.global_position) < 5.5:
			_grudge = e[0]
			_grudge_time = 25.0
	pressure = clampf(pressure + (delta / 6.0 if chased else -delta / 4.0), 0.0, 1.0)
	_grudge_time -= delta
	if _grudge_time <= 0.0 or not is_instance_valid(_grudge):
		_grudge = null


## Once per corner: does this driver get it wrong? Each kind costs time
## (about half a second to two seconds), none throws the car off the road.
func _think_mistakes(delta: float, off: float, v: float) -> void:
	if _mistake != Mistake.NONE:
		_mistake_time -= delta
		if _mistake_time <= 0.0:
			_mistake = Mistake.NONE
	_pace_scale = 1.0
	match _mistake:
		Mistake.LATE_BRAKE:
			_pace_scale = 1.05
		Mistake.LOCK_UP:
			_pace_scale = 0.6
		Mistake.WIDE:
			_pace_scale = 0.94
	if _corner_dist > 70.0 or _corner_dist < 20.0 or _pitting or v < 18.0 or _corner_id == _rolled_corner:
		return
	# (The id moves a little while the corner comes closer: one roll per approach.)
	if absi(_corner_id - _rolled_corner) <= 1 or _mistake != Mistake.NONE:
		_rolled_corner = _corner_id
		return
	_rolled_corner = _corner_id
	var race := _find_race()
	if race != null and (race.state != RaceDirector.State.RACING or race.race_time < 8.0):
		return
	var chance := (1.0 - consistency) * 0.14 + pressure * (1.0 - nerve) * 0.4
	if randf() >= chance * lerpf(1.3, 0.6, skill):
		return
	_start_mistake([Mistake.LATE_BRAKE, Mistake.LOCK_UP, Mistake.WIDE, Mistake.MISSED_GEAR].pick_random(), off)


func _start_mistake(kind: Mistake, off: float) -> void:
	_mistake = kind
	# Too late on the brakes on gravel or over the water would be a crash.
	var ahead := off + _corner_dist
	if kind == Mistake.LATE_BRAKE and (_circuit.surface_at(ahead) != "tarmac" or _circuit.surface_at(off) != "tarmac" 			or _circuit.on_bridge(off) or _circuit.on_bridge(ahead)):
		_mistake = Mistake.LOCK_UP
	_mistake_time = MISTAKE_SECONDS[_mistake]
	mistakes += 1
	if _mistake != Mistake.MISSED_GEAR:
		_announce({Mistake.LATE_BRAKE: "BRAKES TOO LATE", Mistake.LOCK_UP: "LOCKS UP", Mistake.WIDE: "RUNS WIDE"}[_mistake])


## Returns (lane to aim for, speed cap). Everything in track coordinates, so
## it works the same on a straight and round a bend.
func _race_others(delta: float, off: float, lat: float, v: float, line: float, road_half: float) -> Vector2:
	var cap := 999.0
	_traffic_reason = "follow"
	var edge := road_half + 0.5
	var front: Array = []
	var front_gap := 999.0
	var chaser: Array = []
	var chaser_gap := -999.0
	for id in _field:
		var e: Array = _field[id]
		if e[0] == _vehicle or (e[0] as Vehicle).in_pit_lane:
			continue
		var gap := _gap(off, e[1])
		if gap > 70.0 or gap < -20.0:
			continue
		var dlat: float = e[2] - lat
		var ov: float = e[3]
		if gap > 0.0:
			var in_path := minf(absf(dlat), absf(e[2] - lane)) < 2.4
			if in_path and gap < front_gap:
				front = e
				front_gap = gap
			# Never faster than it can still slow down to the car in front.
			if absf(dlat) < 2.2:
				var stop := lerpf(8.0, 6.2, aggression)
				# Brake lights on: aim for the speed it will be doing a moment from now.
				var soon := maxf(ov + minf(float(e[4]), 0.0) * 0.45, 0.0)
				cap = minf(cap, soon - 0.5 + sqrt(10.0 * maxf(gap - stop, 0.0)))
		elif gap > chaser_gap and gap < -CAR_LENGTH:
			chaser = e
			chaser_gap = gap

	var target := line
	if _mistake == Mistake.WIDE or _mistake == Mistake.LATE_BRAKE:
		target = -_corner_side * road_half * 0.5
	_attack_wait -= delta
	_think_attack(delta, off, lat, v, front, front_gap, edge)
	if _attack != null:
		_defend_lane = NAN
		target = clampf(float(_field[_attack.get_instance_id()][2]) + _attack_side * PASS_LANE, -edge, edge)
	elif _mistake == Mistake.NONE:
		_think_defend(lat, v, chaser, chaser_gap, road_half)
		if not is_nan(_defend_lane):
			target = _defend_lane
		elif front_gap < 32.0 and front_gap > 9.0 and v > 24.0 and _corner_dist > 60.0:
			# A straight: sit in the slipstream until there is a gap to go for.
			target = clampf(front[2], -road_half, road_half)

	# Side by side: always leave the other car its space.
	var room := lerpf(2.9, 2.4, aggression)
	for id in _field:
		var e: Array = _field[id]
		if e[0] == _vehicle:
			continue
		var gap := _gap(off, e[1])
		if absf(gap) > 6.0:
			continue
		var dlat: float = e[2] - lat
		if absf(dlat) > 4.0 or absf(dlat) < 0.8 and gap > 0.0:
			continue  # (right behind it: that is the speed cap's business)
		if dlat > 0.0:
			target = minf(target, float(e[2]) - room)
		else:
			target = maxf(target, float(e[2]) + room)
		# Squeezed with nowhere to go and not in front: back out of it.
		if absf(dlat) < 2.0 and gap > 0.5 and maxf(float(e[3]) - 1.0, 4.0) < cap:
			cap = maxf(float(e[3]) - 1.0, 4.0)
			_traffic_reason = "squeezed"
	target = clampf(target, -edge, edge)
	# Into a fast or tight bend nobody hangs on round the outside edge of the road:
	# stay off it, and drop in behind whoever is in the way.
	if _bend > 0.3:
		var outside := road_half * lerpf(0.6, 0.2, clampf((_bend - 0.3) / 0.25, 0.0, 1.0))
		if -target * _bend_side > outside:
			target = -_bend_side * outside
			for id in _field:
				var e: Array = _field[id]
				if e[0] != _vehicle and absf(float(e[2]) - target) < 2.4 and _gap(off, e[1]) > -2.0 and _gap(off, e[1]) < 9.0 \
						and maxf(float(e[3]) - 1.5, 4.0) < cap:
					cap = maxf(float(e[3]) - 1.5, 4.0)
					_traffic_reason = "outside"
	return Vector2(target, cap)


## Picks a side to pass on and sticks with it until it works or clearly won't.
func _think_attack(delta: float, off: float, lat: float, v: float, front: Array, front_gap: float, edge: float) -> void:
	if _attack != null:
		if not is_instance_valid(_attack) or not _field.has(_attack.get_instance_id()):
			_attack = null
			return
		var e: Array = _field[_attack.get_instance_id()]
		var gap := _gap(off, e[1])
		_attack_time += delta
		# Out-braking: on the inside and nearly there, hold on a little longer.
		var inside := _attack_side == _corner_side
		if inside and _corner_dist < 90.0 and _corner_dist > 8.0 and gap < 9.0 and gap > -3.0 and _mistake == Mistake.NONE:
			_pace_scale = maxf(_pace_scale, 1.0 + (0.06 if _corner_curv < 0.03 else 0.02) * _bold_against(_attack))
			if not _dived:
				_dived = true
				dives += 1
		var round_outside := _attack_side == -_bend_side and _bend > 0.4 and gap > -2.0
		var blocked := (float(e[2]) + _attack_side * 2.4) * _attack_side > edge
		if gap < -7.0 or gap > 40.0 or _attack_time > 9.0 or round_outside or (blocked and gap > 5.0) or _pitting or v < 8.0:
			if gap > 0.0:
				_attack_wait = lerpf(4.0, 0.8, aggression)
			_attack = null
		return
	if front.is_empty() or _attack_wait > 0.0 or _pitting or v < 12.0 or _mistake != Mistake.NONE:
		return
	var other: Vehicle = front[0]
	var bold := _bold_against(other)
	var closing := v - float(front[3])
	# (A much slower car: start going round it early.)
	if front_gap > maxf(lerpf(14.0, 28.0, bold), closing * 2.4) or closing < -1.0:
		return
	# A careful driver doesn't try it in the middle of a corner.
	if _corner_dist < 10.0 and closing < lerpf(6.0, 0.5, bold):
		return
	var best := 0.0
	var best_score := -99.0
	for side: float in [-1.0, 1.0]:
		var want: float = front[2] + side * PASS_LANE
		if want * side > edge + 0.4:
			continue  # no road there
		var score: float = (edge - want * side) * 0.15  # room left over
		score += 0.6 if (lat - float(front[2])) * side > 0.3 else 0.0  # already that way
		if _corner_dist < 150.0:
			score += side * _corner_side * lerpf(0.4, 1.2, bold)
		for id in _field:  # somebody else already there
			var o: Array = _field[id]
			if o[0] == _vehicle or o[0] == other:
				continue
			if absf(float(o[2]) - want) < 2.2 and _gap(off, o[1]) > -7.0 and _gap(off, o[1]) < front_gap + 8.0:
				score -= 3.0
		if score > best_score:
			best_score = score
			best = side
	if best == 0.0 or best_score < -1.5:
		return
	_attack = other
	_attack_side = best
	_attack_time = 0.0
	_dived = false


func _bold_against(other: Vehicle) -> float:
	return clampf(aggression + (0.35 if other == _grudge else 0.0), 0.0, 1.0)


## One move per straight: cover the inside of the next corner while the
## car behind is close but not yet alongside.
func _think_defend(lat: float, v: float, chaser: Array, chaser_gap: float, road_half: float) -> void:
	if not is_nan(_defend_lane):
		if _corner_dist < 14.0 or _corner_dist > 200.0 or chaser.is_empty() or chaser_gap < -24.0:
			_defend_lane = NAN
		return
	if chaser.is_empty() or chaser_gap < -15.0 or _corner_dist < 40.0 or v < 18.0:
		return
	if absi(_corner_id - _defended_corner) <= 2:
		return
	if float(chaser[3]) - v < -0.5 or not _same_lap(chaser[0]):
		return
	var will := clampf(defence + (0.3 if chaser[0] == _grudge else 0.0), 0.0, 1.0)
	if will < 0.25:
		return
	var cover := _corner_side * road_half * lerpf(0.4, 0.9, will)
	# The gap is already taken: moving over now would be a crash, not a block.
	if chaser_gap > -8.0 and (float(chaser[2]) - lat) * _corner_side > 1.2:
		return
	_defended_corner = _corner_id
	# Not every driver does it every time.
	if randf() > will:
		return
	_defend_lane = cover
	defends += 1


## Upside down / on its side, or a wheel gone.
func _wrecked() -> bool:
	if _vehicle.global_basis.y.y < 0.5:
		return true
	for w in _vehicle.wheels:
		if w.detached:
			return true
	return false


## Put the car back on the centre line, pointing the right way.
func _reset_onto_track(off: float, _track_dir: Vector3) -> void:
	resets += 1
	_pitting = false  # decide again from the new spot (never steer into the pit wall)
	_corner_scale = maxf(_corner_scale * 0.95, 0.8)
	_build_profile()
	_lost_time = 0.0
	lane = 0.0
	_attack = null
	_defend_lane = NAN
	_mistake = Mistake.NONE
	_pace_scale = 1.0
	# Put it back on a clear patch of road: several cars stuck in one pile
	# would otherwise all reset onto the same spot and crash again.
	var spot := off
	var lateral := 0.0
	for attempt in 12:
		var cand_off := off - attempt * 9.0
		var cand_lat: float = [0.0, -3.2, 3.2][attempt % 3]
		var cand: Vector3 = _circuit.point_at(cand_off) + _circuit.right_at(cand_off) * cand_lat
		var clear := true
		for node in get_tree().get_nodes_in_group("vehicles"):
			var other := node as Vehicle
			if other != _vehicle and other.global_position.distance_to(cand) < 7.0:
				clear = false
				break
		if clear:
			spot = cand_off
			lateral = cand_lat
			break
	_vehicle.teleport(_circuit.road_transform(spot, lateral))
	throttle = 0.0
	brake = 0.0
	steer = 0.0
