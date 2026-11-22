class_name Wheel
extends RayCast3D
## One wheel: raycast suspension, tyre forces and spin (design concept §6.2).
## Place the node at the suspension's top mount. The ray points straight down.
## The Vehicle drives the update order; this node never applies forces itself.

## Below this speed (m/s) slip is measured against this speed instead, which
## keeps the tyre model stable when the car is nearly stopped.
const LOW_SPEED := 3.0
const MAX_OMEGA := 400.0

@export var is_front: bool = true
@export var is_left: bool = true

# --- Set from VehicleConfig in setup() ---
var radius: float = 0.31
var width: float = 0.22
var inertia: float = 1.1
var rest_length: float = 0.30
var bump_length: float = 0.08
var spring_rate: float = 35000.0
var damper_bump: float = 2800.0
var damper_rebound: float = 3800.0
var grip: float = 1.05
var peak_slip_ratio: float = 0.1
var tan_peak_angle: float = 0.14
var load_sensitivity: float = 0.12
var nominal_load: float = 3000.0
var rolling_resistance: float = 0.015
## Pacejka shape factor C, set from the handling profile.
var tire_shape: float = 1.3

# --- Live state ---
var omega: float = 0.0  ## Spin speed, rad/s (+ = rolling forward).
var spin_angle: float = 0.0
var steer_angle: float = 0.0  ## Radians, + = right.
var grounded: bool = false
var contact_point: Vector3 = Vector3.ZERO
var contact_normal: Vector3 = Vector3.UP
var spring_length: float = 0.30
var spring_force: float = 0.0
var tire_load: float = 0.0  ## Normal load in Newtons (spring + anti-roll).
var drive_torque: float = 0.0
var brake_torque: float = 0.0
var v_long: float = 0.0
var v_lat: float = 0.0

# --- Telemetry ---
var slip_ratio: float = 0.0
var slip_angle: float = 0.0  ## Radians.
var grip_usage: float = 0.0  ## 1.0 = at the friction limit.
var force_long: float = 0.0
var force_lat: float = 0.0
var mu_load: float = 0.0  ## Max friction force available right now.

var _prev_spring_length: float = 0.30
var _fwd: Vector3 = Vector3.FORWARD
var _right: Vector3 = Vector3.RIGHT
var _fx_sum: float = 0.0
var _fy_sum: float = 0.0
var _visual: Node3D
## Optional wheel mesh from an imported car model (origin at the hub,
## axle along X). Set before setup(); replaces the generated tyre.
var custom_visual: Node3D


func setup(vehicle: RigidBody3D, cfg: VehicleConfig) -> void:
	radius = cfg.wheel_radius
	width = cfg.wheel_width
	inertia = cfg.wheel_inertia
	rest_length = cfg.rest_length
	bump_length = maxf(cfg.rest_length - cfg.max_travel, 0.0)
	spring_rate = cfg.front_spring_rate if is_front else cfg.rear_spring_rate
	damper_bump = cfg.front_damper_bump if is_front else cfg.rear_damper_bump
	damper_rebound = cfg.front_damper_rebound if is_front else cfg.rear_damper_rebound
	grip = cfg.tire_grip
	peak_slip_ratio = cfg.tire_peak_slip_ratio
	tan_peak_angle = tan(deg_to_rad(cfg.tire_peak_slip_angle_deg))
	load_sensitivity = cfg.tire_load_sensitivity
	nominal_load = cfg.mass * 9.81 * 0.25
	rolling_resistance = cfg.rolling_resistance

	target_position = Vector3(0.0, -(rest_length + radius), 0.0)
	collision_mask = 1  # World only (ground, ramps, walls).
	add_exception(vehicle)
	enabled = true
	_build_visual()
	reset()


func reset() -> void:
	omega = 0.0
	spring_length = rest_length
	_prev_spring_length = rest_length
	spring_force = 0.0
	tire_load = 0.0
	slip_ratio = 0.0
	slip_angle = 0.0


## Step 1: cast the ray and compute the spring/damper force.
func update_suspension(dt: float) -> void:
	force_raycast_update()
	grounded = is_colliding()
	if grounded:
		contact_point = get_collision_point()
		contact_normal = get_collision_normal()
		spring_length = clampf(global_position.distance_to(contact_point) - radius, 0.0, rest_length)
	else:
		spring_length = rest_length
		contact_point = global_position - global_basis.y * (rest_length + radius)
		contact_normal = global_basis.y

	var spring_velocity := (spring_length - _prev_spring_length) / dt
	_prev_spring_length = spring_length
	if not grounded:
		spring_force = 0.0
		return

	var force := spring_rate * (rest_length - spring_length)
	var damper := damper_bump if spring_velocity < 0.0 else damper_rebound
	force -= damper * spring_velocity
	if spring_length < bump_length:
		force += (bump_length - spring_length) * spring_rate * 8.0
	spring_force = maxf(force, 0.0)


## 0 = fully extended, 1 = on the bump stop.
func compression_ratio() -> float:
	return clampf((rest_length - spring_length) / maxf(rest_length - bump_length, 0.001), 0.0, 1.0)


## Step 2: build the tyre's frame and read the ground speed at the contact.
func prepare_tire(body_basis: Basis, contact_velocity: Vector3) -> void:
	var b := body_basis * Basis(Vector3.UP, -steer_angle)
	var n := contact_normal
	_fwd = -b.z
	_fwd = (_fwd - n * _fwd.dot(n)).normalized()
	_right = b.x
	_right = (_right - n * _right.dot(n)).normalized()
	v_long = contact_velocity.dot(_fwd)
	v_lat = contact_velocity.dot(_right)
	_fx_sum = 0.0
	_fy_sum = 0.0
	mu_load = _mu_load()


## Step 3 (run several times per tick): tyre force + implicit wheel-spin update.
func substep(h: float) -> void:
	var fx := 0.0
	var fy := 0.0
	var dfx_domega := 0.0
	if grounded and tire_load > 0.0:
		var d := maxf(absf(v_long), LOW_SPEED)
		var kappa := (omega * radius - v_long) / d
		var sx := kappa / peak_slip_ratio
		var sy := (v_lat / d) / tan_peak_angle
		var rho := sqrt(sx * sx + sy * sy)
		var dfx_dsx := 0.0
		if rho > 1e-5:
			var f_norm := TireModel.curve(rho, tire_shape)
			var f := f_norm * mu_load
			fx = f * sx / rho
			fy = -f * sy / rho
			var c2 := (sx * sx) / (rho * rho)
			var slope := maxf(TireModel.curve_slope(rho, tire_shape), 0.0)
			dfx_dsx = mu_load * (slope * c2 + f_norm / rho * (1.0 - c2))
		else:
			dfx_dsx = mu_load * TireModel.curve_slope(0.0, tire_shape)
		dfx_domega = dfx_dsx * radius / (peak_slip_ratio * d)

	# Implicit Euler: the tyre's stiffness acts like extra inertia, which
	# keeps the wheel stable at 120 Hz even at low speed.
	var i_eff := inertia + h * radius * dfx_domega
	omega += h * (drive_torque - fx * radius) / i_eff

	# Brakes and rolling resistance can stop the wheel but never reverse it.
	var resist := brake_torque + (rolling_resistance * tire_load * radius if grounded else 0.3)
	var dw := resist * h / i_eff
	if absf(omega) <= dw:
		omega = 0.0
	else:
		omega -= signf(omega) * dw
	omega = clampf(omega, -MAX_OMEGA, MAX_OMEGA)

	_fx_sum += fx
	_fy_sum += fy


## Step 4: average the substeps and return the tyre force in world space.
func finish_tire(substeps: int) -> Vector3:
	force_long = _fx_sum / substeps
	force_lat = _fy_sum / substeps
	var d := maxf(absf(v_long), LOW_SPEED)
	slip_ratio = (omega * radius - v_long) / d if grounded else 0.0
	slip_angle = atan2(v_lat, maxf(absf(v_long), 0.5)) if grounded else 0.0
	grip_usage = sqrt(force_long * force_long + force_lat * force_lat) / mu_load if mu_load > 1.0 else 0.0
	if not grounded:
		return Vector3.ZERO
	return _fwd * force_long + _right * force_lat


func update_visual(dt: float) -> void:
	spin_angle = wrapf(spin_angle + omega * dt, 0.0, TAU)
	if _visual:
		_visual.position = Vector3(0.0, -spring_length, 0.0)
		_visual.basis = Basis(Vector3.UP, -steer_angle) * Basis(Vector3.RIGHT, -spin_angle)


func _mu_load() -> float:
	var load_factor := clampf(1.0 - load_sensitivity * (tire_load / nominal_load - 1.0), 0.5, 1.3)
	return grip * tire_load * load_factor


func _build_visual() -> void:
	if _visual:
		return
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	if custom_visual:
		custom_visual.reparent(_visual, false)
		custom_visual.transform = Transform3D.IDENTITY
		return

	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = radius
	tire_mesh.bottom_radius = radius
	tire_mesh.height = width
	tire_mesh.radial_segments = 24
	tire_mesh.rings = 1
	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.07, 0.07, 0.08)
	tire_mat.roughness = 0.9
	tire_mesh.material = tire_mat
	var tire := MeshInstance3D.new()
	tire.name = "Tire"
	tire.mesh = tire_mesh
	tire.rotation = Vector3(0.0, 0.0, PI * 0.5)  # Cylinder axis Y -> wheel axle X.
	_visual.add_child(tire)

	# Two crossed bars so you can see the wheel spin.
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.75, 0.76, 0.78)
	rim_mat.metallic = 0.6
	rim_mat.roughness = 0.35
	for i in 2:
		var bar := BoxMesh.new()
		bar.size = Vector3(radius * 1.4, width + 0.02, 0.08)
		bar.material = rim_mat
		var spoke := MeshInstance3D.new()
		spoke.mesh = bar
		spoke.rotation = Vector3(0.0, PI * 0.5 * i, 0.0)
		tire.add_child(spoke)
