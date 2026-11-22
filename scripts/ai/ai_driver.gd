class_name AIDriver
extends VehicleInput
## Simple racing-line follower (first step toward design concept §9): steers
## toward a point a little ahead on the circuit's centre line and brakes for
## corners using the curvature further ahead. Drives through the same
## VehicleInput as the player, so it gets no grip advantages.

## Lateral grip (in g) the driver is willing to use in corners.
@export var cornering_g: float = 0.7
## Deceleration (m/s²) it plans its braking with.
@export var braking_decel: float = 4.0
@export var lookahead_base: float = 9.0
@export var lookahead_per_mps: float = 0.45
## Extra wheel angle on top of pure geometry, to cover tyre slip.
@export var steer_gain: float = 1.4
## Most steering input the AI uses (about the grip limit in Sport).
@export var max_steer_input: float = 0.55
## Seconds lost (off the road or facing the wrong way) before it resets.
@export var reset_after: float = 2.5

var resets: int = 0
var _lost_time: float = 0.0

var target_speed: float = 0.0
var _vehicle: Vehicle
var _circuit: Circuit


func poll(delta: float) -> void:
	if _circuit == null:
		_circuit = get_tree().get_first_node_in_group("circuit") as Circuit
		_vehicle = get_parent() as Vehicle
		if _circuit == null or _vehicle == null:
			return
	var v := _vehicle.forward_speed
	var off := _circuit.progress_at(_vehicle.global_position)

	# Steering: aim at a point ahead on the line.
	var look := lookahead_base + maxf(v, 0.0) * lookahead_per_mps
	var local := _vehicle.to_local(_circuit.point_at(off + look))
	# Pure pursuit: the arc through the target point gives the curvature,
	# which becomes a wheel angle, then a share of the current steering lock.
	var dist_sq := maxf(local.x * local.x + local.z * local.z, 1.0)
	var arc_curvature := 2.0 * local.x / dist_sq  # + = target to the right
	var wheel_angle := atan(arc_curvature * _vehicle.wheelbase()) * steer_gain
	steer = clampf(wheel_angle / _vehicle.current_steer_limit(), -max_steer_input, max_steer_input)

	# Speed: the slowest corner within braking distance sets the target.
	var horizon := 30.0 + v * v / (2.0 * braking_decel)
	target_speed = 90.0
	var d := 0.0
	while d < horizon:
		var curv := absf(_circuit.curvature_at(off + d))
		var corner_v := sqrt(cornering_g * 9.81 / maxf(curv, 0.0005))
		# Speed we may carry now and still slow to corner_v by distance d.
		target_speed = minf(target_speed, sqrt(corner_v * corner_v + 2.0 * braking_decel * d))
		d += 4.0

	# Off the line (run wide, spun): slow right down and find the way back.
	var off_line := _circuit.distance_from_centre(_vehicle.global_position) > _circuit.road_width * 0.9
	if off_line:
		target_speed = minf(target_speed, 12.0)
	var track_dir := (_circuit.point_at(off + 2.0) - _circuit.point_at(off - 2.0)).normalized()
	var wrong_way := (-_vehicle.global_basis.z).dot(track_dir) < -0.2
	_lost_time = _lost_time + delta if (off_line or wrong_way) else 0.0
	if _lost_time > reset_after:
		_reset_onto_track(off, track_dir)
		return

	# Sliding: back off until the tyres hook up again.
	var slip := absf(atan2(_vehicle.lateral_speed, maxf(absf(v), 0.5)))
	if slip > deg_to_rad(6.0):
		target_speed = minf(target_speed, v - 3.0)

	# Smooth pedals: brake/throttle in proportion to the speed error, and
	# go easy on both while turning hard (the front tyres need grip to steer).
	var err := v - target_speed
	var turning := absf(steer) / maxf(max_steer_input, 0.01)
	if err > 0.5:
		throttle = 0.0
		brake = clampf(err / 2.0, 0.2, 1.0) * (1.0 - turning * 0.5)
	else:
		brake = 0.0
		throttle = clampf(-err / 4.0, 0.25, 1.0) * (1.0 - turning * 0.6)
	handbrake = 0.0


## Put the car back on the centre line, pointing the right way, like the
## reset in most racing games.
func _reset_onto_track(off: float, track_dir: Vector3) -> void:
	resets += 1
	_lost_time = 0.0
	var pos := _circuit.point_at(off) + Vector3.UP * 0.3
	_vehicle.teleport(Transform3D(Basis.looking_at(track_dir, Vector3.UP), pos))
	throttle = 0.0
	brake = 0.0
	steer = 0.0
