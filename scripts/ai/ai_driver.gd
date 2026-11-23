class_name AIDriver
extends VehicleInput
## AI racing driver (design concept §9). Drives through the same VehicleInput
## as a player, so it gets no extra grip or power.
## - Speed: a per-lap speed plan (corner limits + braking zones) built once
##   from the circuit, scaled by `skill`.
## - Line: drifts toward the inside of the coming corner, using the road width.
## - Traffic: moves over to pass slower cars and brakes rather than ram them.
## - If it ends up lost (off the road or facing the wrong way) for a few
##   seconds, it is put back on the track like in most racing games.

## 0 = cautious, 1 = right on the limit.
@export_range(0.0, 1.0) var skill: float = 0.8
## Personal preference for one side of the road (metres, + = right).
@export var lane_bias: float = 0.0
@export var lookahead_base: float = 8.0
@export var lookahead_per_mps: float = 0.42
## Extra wheel angle on top of pure geometry, to cover tyre slip.
@export var steer_gain: float = 1.3
## Most steering input the AI uses.
@export var max_steer_input: float = 1.0
## Seconds lost (off the road or facing the wrong way) before it resets.
@export var reset_after: float = 3.0

var resets: int = 0
var target_speed: float = 0.0
var lane: float = 0.0

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
	var v := _vehicle.forward_speed
	var pos := _vehicle.global_position
	var off := _circuit.progress_at(pos)
	var road_half := _circuit.road_width * 0.5 - 1.7

	# --- Where on the road: inside of the next corner, plus traffic moves.
	var curv_ahead := _circuit.curvature_at(off + 12.0 + maxf(v, 0.0) * 0.6)
	var line := -clampf(curv_ahead * 220.0, -1.0, 1.0) * road_half * 0.75  # + curv = left turn
	var traffic := _read_traffic(v)
	var lane_target := clampf(line + lane_bias + traffic.x, -road_half, road_half)
	lane = move_toward(lane, lane_target, 3.5 * delta)

	# --- Steering: pure pursuit to a point ahead on that line.
	var look := lookahead_base + maxf(v, 0.0) * lookahead_per_mps
	var target_point := _circuit.point_at(off + look) + _circuit.right_at(off + look) * lane
	var local := _vehicle.to_local(target_point)
	var dist_sq := maxf(local.x * local.x + local.z * local.z, 1.0)
	var arc_curvature := 2.0 * local.x / dist_sq  # + = target to the right
	var wheel_angle := atan(arc_curvature * _vehicle.wheelbase()) * steer_gain
	steer = clampf(wheel_angle / _vehicle.current_steer_limit(), -max_steer_input, max_steer_input)

	# --- Speed: follow the plan, respect traffic, back off when sliding.
	target_speed = minf(_circuit.profile_speed(_profile, off + maxf(v, 0.0) * 0.3), traffic.y)
	var slip := absf(atan2(_vehicle.lateral_speed, maxf(absf(v), 0.5)))
	if v > 8.0 and slip > deg_to_rad(7.0):
		target_speed = minf(target_speed, v - 2.0)
	# Full lock at speed and still not turning enough (understeer): scrub off
	# speed now rather than at the edge of the road.
	if v > 14.0 and absf(steer) >= max_steer_input * 0.97:
		target_speed = minf(target_speed, v - 2.5)

	var from_centre := _circuit.distance_from_centre(pos)
	# Running wide toward the edge: ease off before it reaches the grass.
	if from_centre > _circuit.road_width * 0.45:
		target_speed = minf(target_speed, maxf(v - 1.5, 14.0))
	var off_line := from_centre > _circuit.road_width * 0.75
	if off_line:
		target_speed = minf(target_speed, 14.0)
	var track_dir := _circuit.direction_at(off)
	var wrong_way := (-_vehicle.global_basis.z).dot(track_dir) < -0.2
	var stuck := absf(v) < 1.0 and not _vehicle.controls_locked
	_lost_time = _lost_time + delta if (off_line or wrong_way or stuck) else 0.0
	if _lost_time > reset_after:
		if OS.get_cmdline_user_args().has("--log-resets"):
			print("    reset %s at %.0f m (%s%s%s)" % [_vehicle.name, off, "off line " if off_line else "",
				"wrong way " if wrong_way else "", "stuck" if stuck else ""])
		_reset_onto_track(off, track_dir)
		return

	# --- Pedals in proportion to the speed error; gentle while turning hard.
	var err := v - target_speed
	var turning := absf(steer) / maxf(max_steer_input, 0.01)
	if err > 0.5:
		throttle = 0.0
		brake = clampf(err / 2.0, 0.2, 1.0) * (1.0 - turning * 0.4)
	else:
		brake = 0.0
		# At full lock a front-drive car needs its front grip for turning.
		throttle = clampf(-err / 3.0, 0.25, 1.0) * clampf(1.0 - turning * 0.9, 0.08, 1.0)
	handbrake = 0.0
	# Nitro on the straights: flat out, wheel straight, and the road ahead fast.
	nitro = throttle > 0.95 and turning < 0.15 and target_speed > v + 4.0


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
	var grip := _vehicle.config.tire_grip * heavy * 9.81
	_profile = _circuit.build_speed_profile(grip * lerpf(0.46, 0.63, skill) * _corner_scale,
			grip * lerpf(0.42, 0.58, skill), 95.0)


## Returns (lane shift in metres, speed cap in m/s) caused by nearby cars.
func _read_traffic(v: float) -> Vector2:
	var shift := 0.0
	var cap := 999.0
	for node in get_tree().get_nodes_in_group("vehicles"):
		var other := node as Vehicle
		if other == null or other == _vehicle:
			continue
		var rel := _vehicle.to_local(other.global_position)
		var ahead := -rel.z
		var side := rel.x
		if ahead > 0.0 and ahead < 28.0 and absf(side) < 2.8:
			# Someone in our path: pass on the side with more room.
			var closing := v - other.forward_speed
			if closing > -1.0:
				var go_right := side < 0.0
				if absf(lane) > 2.0:
					go_right = lane < 0.0  # already near one edge: use the other side
				shift = 3.0 if go_right else -3.0
			if ahead < 10.0 and closing > 0.0:
				cap = minf(cap, other.forward_speed - 0.5)
		elif absf(ahead) < 5.0 and absf(side) < 3.2:
			# Side by side: give each other room.
			shift = -signf(side) * 1.5
	return Vector2(shift, cap)


## Put the car back on the centre line, pointing the right way.
func _reset_onto_track(off: float, track_dir: Vector3) -> void:
	resets += 1
	_corner_scale = maxf(_corner_scale * 0.95, 0.8)
	_build_profile()
	_lost_time = 0.0
	lane = 0.0
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
	track_dir = _circuit.direction_at(spot)
	var pos := _circuit.point_at(spot) + _circuit.right_at(spot) * lateral + Vector3.UP * 0.3
	_vehicle.teleport(Transform3D(Basis.looking_at(track_dir, Vector3.UP), pos))
	throttle = 0.0
	brake = 0.0
	steer = 0.0
