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
## Grip multiplier of the surface under the tyre (collider meta "surface_grip").
var surface_grip: float = 1.0
## Extra rolling drag of the surface (collider meta "surface_drag").
var surface_drag: float = 0.0
## True when the tyre is on the track itself (road of any surface or curbs).
var on_road: bool = true

## Tyre temperature (C) and wear (0 new .. 1 gone). Sliding heats and wears
## the tyre; airflow cools it. Grip is best between 80 and 105 C.
var temp: float = 50.0
var wear: float = 0.0
## Wear speed: 0 = tyre heat / wear off, 1 = normal, 2 = fast.
var wear_rate: float = 1.0
## Energy (J) the tyre has turned into heat since the race started (calibration).
var slide_energy: float = 0.0
const AMBIENT_C := 28.0
const HEAT_CAPACITY := 1150.0  ## J per C
const WEAR_PER_J := 3.6e-7

## Running-gear damage. puncture: 0 = fine, > 0 = punctured and deflating
## towards 1 (flat); toe: bent suspension, extra steer angle (radians);
## detached: the wheel has come off.
var punctured := false
## Tournament grip bonuses (CarPerks sets it every tick).
var perk_grip := 1.0
var deflate := 0.0
var toe := 0.0
var detached := false

var _prev_spring_length: float = 0.30
var _fwd: Vector3 = Vector3.FORWARD
var _right: Vector3 = Vector3.RIGHT
var _fx_sum: float = 0.0
var _fy_sum: float = 0.0
var _visual: Node3D
## Optional wheel mesh from an imported car model (origin at the hub,
## axle along X). Set before setup(); replaces the generated tyre.
var custom_visual: Node3D
var _dirt: WheelDirt


func setup(vehicle: RigidBody3D, cfg: VehicleConfig) -> void:
	radius = cfg.wheel_radius
	width = cfg.wheel_width
	inertia = cfg.wheel_inertia
	rest_length = cfg.rest_length
	bump_length = maxf(cfg.rest_length - cfg.max_travel, 0.0)
	spring_rate = (cfg.front_spring_rate if is_front else cfg.rear_spring_rate) * Vehicle.SPRING_SCALE
	damper_bump = cfg.front_damper_bump if is_front else cfg.rear_damper_bump
	damper_rebound = cfg.front_damper_rebound if is_front else cfg.rear_damper_rebound
	grip = cfg.tire_grip * (1.0 if is_front else cfg.rear_grip_scale)
	peak_slip_ratio = cfg.tire_peak_slip_ratio
	tan_peak_angle = tan(deg_to_rad(cfg.tire_peak_slip_angle_deg))
	load_sensitivity = cfg.tire_load_sensitivity
	nominal_load = cfg.mass * 9.81 * 0.25
	rolling_resistance = cfg.rolling_resistance

	target_position = Vector3(0.0, -(rest_length + radius), 0.0)
	# World (ground, ramps, walls) + wheels-only surfaces (a loop: the car
	# body would scrape the tight curve, the tyres ride it).
	collision_mask = 1 | 8
	add_exception(vehicle)
	enabled = true
	_build_visual()
	if _dirt == null:
		_dirt = WheelDirt.new()
		_dirt.name = "Dirt"
		add_child(_dirt)
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
	if punctured:
		deflate = minf(deflate + dt / 4.0, 1.0)
	if detached:
		grounded = false
		spring_force = 0.0
		spring_length = rest_length
		return
	force_raycast_update()
	grounded = is_colliding()
	if grounded:
		contact_point = get_collision_point()
		contact_normal = get_collision_normal()
		var collider := get_collider()
		surface_grip = collider.get_meta(&"surface_grip", 1.0) if collider else 1.0
		surface_drag = collider.get_meta(&"surface_drag", 0.0) if collider else 0.0
		# Track bodies say so; anything without surface info (test track,
		# free-roam ground) counts as road, loose ground (grip < 0.85) doesn't.
		if collider == null:
			on_road = false
		elif collider.has_meta(&"road"):
			on_road = true
		else:
			on_road = surface_grip >= 0.85
		# A flat tyre: the rim sits ~9 cm lower.
		spring_length = clampf(global_position.distance_to(contact_point) - radius * (1.0 - 0.3 * deflate), 0.0, rest_length)
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
	var b := body_basis * Basis(Vector3.UP, -(steer_angle + toe))
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


## Velocity of whatever the tyre stands on at the contact point: zero for
## the ground, the deck's motion on a lift, seesaw or turntable, the belt
## speed of a conveyor / roller (StaticBody3D constant velocities).
func ground_velocity() -> Vector3:
	if not grounded:
		return Vector3.ZERO
	var c := get_collider()
	if c is RigidBody3D or c is AnimatableBody3D:
		var st := PhysicsServer3D.body_get_direct_state((c as CollisionObject3D).get_rid())
		if st:
			return st.get_velocity_at_local_position(contact_point - st.transform.origin)
	elif c is StaticBody3D:
		var sb := c as StaticBody3D
		if sb.constant_linear_velocity != Vector3.ZERO or sb.constant_angular_velocity != Vector3.ZERO:
			return sb.constant_linear_velocity + sb.constant_angular_velocity.cross(contact_point - sb.global_position)
	return Vector3.ZERO


## The body the tyre stands on, if it can be pushed (a seesaw, a loose plank).
func pushable_ground() -> RigidBody3D:
	if not grounded:
		return null
	var c := get_collider() as RigidBody3D
	if c and not c.freeze:
		return c
	return null


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
			# Around the grip peak the true slope drops to zero, which would let
			# the wheel speed overshoot each substep (heavy cars at low speed
			# chatter instead of driving). Keep the pre-peak stiffness until
			# the tyre is clearly spinning, then let it go.
			var slope := maxf(TireModel.curve_slope(rho, tire_shape), 0.0)
			var stiff := TireModel.curve_slope(0.0, tire_shape) * clampf(2.0 - rho, 0.0, 1.0)
			slope = maxf(slope, stiff)
			dfx_dsx = mu_load * (slope * c2 + f_norm / rho * (1.0 - c2))
		else:
			dfx_dsx = mu_load * TireModel.curve_slope(0.0, tire_shape)
		dfx_domega = dfx_dsx * radius / (peak_slip_ratio * d)

	# Implicit Euler: the tyre's stiffness acts like extra inertia, which
	# keeps the wheel stable at 120 Hz even at low speed.
	var i_eff := inertia + h * radius * dfx_domega
	omega += h * (drive_torque - fx * radius) / i_eff

	# Brakes and rolling resistance can stop the wheel but never reverse it.
	var resist := brake_torque + ((rolling_resistance + surface_drag + 0.06 * deflate) * tire_load * radius if grounded else 0.3)
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


## Tyre heat and wear for one physics tick (after finish_tire).
func update_tyre(dt: float) -> void:
	if wear_rate <= 0.0:
		return
	var power := 0.0
	if grounded:
		var slip_speed := omega * radius - v_long
		power = absf(force_long * slip_speed) + absf(force_lat * v_lat)
	slide_energy += power * dt
	# Airflow cools it (faster at speed), sliding heats it.
	var cool := 0.012 + 0.0004 * absf(v_long)
	temp += (power / HEAT_CAPACITY - (temp - AMBIENT_C) * cool) * dt
	temp = clampf(temp, AMBIENT_C - 5.0, 160.0)
	var loose := 1.4 if surface_grip < 0.9 else 1.0
	wear = minf(wear + power * WEAR_PER_J * wear_rate * loose * dt, 1.0)


## Grip multiplier from temperature and wear (1 = warm, new tyre).
func condition() -> float:
	if wear_rate <= 0.0:
		return 1.0
	var t := 1.0
	if temp < 80.0:
		t = lerpf(0.88, 1.0, smoothstep(30.0, 80.0, temp))
	elif temp > 105.0:
		t = lerpf(1.0, 0.85, smoothstep(105.0, 140.0, temp))
	return t * (1.0 - 0.34 * pow(wear, 1.2))


## Fresh, warm tyres, straight suspension, wheel back on (pit stop).
func new_tyres() -> void:
	wear = 0.0
	temp = 65.0
	punctured = false
	deflate = 0.0
	toe = 0.0
	detached = false


## The wheel comes off: it bounces away as a loose body (the car keeps the
## corner empty until a recovery or a pit stop).
func detach(car_velocity: Vector3) -> void:
	if detached or _visual == null:
		return
	detached = true
	var loose := RigidBody3D.new()
	loose.mass = 18.0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = width
	cs.shape = cyl
	cs.rotation_degrees = Vector3(0, 0, 90)
	loose.add_child(cs)
	var copy := _visual.duplicate() as Node3D
	copy.visible = true
	copy.transform = Transform3D.IDENTITY
	loose.add_child(copy)
	get_tree().current_scene.add_child(loose)
	loose.global_transform = _visual.global_transform
	var side := global_basis.x * (-1.0 if is_left else 1.0)
	loose.linear_velocity = car_velocity * 0.8 + side * 4.0 + Vector3.UP * 3.0
	loose.angular_velocity = global_basis.x * omega
	loose.get_tree().create_timer(10.0).timeout.connect(loose.queue_free)


func update_visual(dt: float) -> void:
	spin_angle = wrapf(spin_angle + omega * dt, 0.0, TAU)
	if _dirt:
		_dirt.update_from(self)
	if _visual:
		_visual.visible = not detached
		_visual.position = Vector3(0.0, -spring_length, 0.0)
		var wobble := Basis(Vector3.BACK, sin(spin_angle) * absf(toe) * 1.5) if toe != 0.0 else Basis.IDENTITY
		_visual.basis = Basis(Vector3.UP, -(steer_angle + toe)) * wobble * Basis(Vector3.RIGHT, -spin_angle)


func _mu_load() -> float:
	var load_factor := clampf(1.0 - load_sensitivity * (tire_load / nominal_load - 1.0), 0.5, 1.3)
	return grip * surface_grip * tire_load * load_factor * condition() * (1.0 - 0.55 * deflate) * perk_grip


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
