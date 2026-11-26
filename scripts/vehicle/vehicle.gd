class_name Vehicle
extends RigidBody3D
## Custom raycast vehicle on a RigidBody3D (design concept §6.1, §14.2).
## Owns four Wheel children and one VehicleInput child (player, AI or replay).
## Everything runs in _physics_process at the project's 120 Hz tick.

## Emitted after set_handling_profile(); profile is 0 Arcade, 1 Sport, 2 Sim.
signal profile_changed(profile: int)
## Emitted after the car is put back on the start (Backspace).
signal reset_to_start_done

const SUBSTEPS := 4
## Limited-slip coupling at diff_lock = 1, in N·m per rad/s of speed difference.
const DIFF_LOCK_MAX := 150.0
const AIR_DENSITY := 1.225
const FALL_RESET_Y := -30.0

## Every tuning number for this car (SI units). CarRoster.apply() sets it.
@export var config: VehicleConfig
## Assist level: 0 Arcade, 1 Sport, 2 Sim. Change it at runtime with set_handling_profile().
@export_enum("Arcade", "Sport", "Sim") var handling_profile: int = 1
## Optional imported car model (.glb) with nodes body and wheel_FL/FR/RL/RR
## (design concept §15). When set, the greybox meshes are hidden.
@export var body_model: PackedScene
## Move the Wheel nodes so their hubs line up with the model's wheels.
@export var align_wheels_to_model: bool = true
## Optional replacement texture for the model (e.g. another paint colour).
@export var paint_texture: Texture2D
## Repaint the car in this colour (alpha 0 = keep the model's own paint).
@export var paint_color: Color = Color(0, 0, 0, 0)
## A second colour variant of the model's texture, used to find the paint area.
@export var paint_reference: Texture2D
## Show the racing livery (stripes, numbers, sponsors) if the model has one.
@export var show_livery: bool = true
## Engine, tyre and surface sounds.
@export var sounds_enabled: bool = true

@export_group("Body motion (visual only)")
## Extra body tilt per g of acceleration/braking (nose up / nose dive).
@export var pitch_per_g_deg: float = 8.5
## Extra body lean per g of cornering.
@export var roll_per_g_deg: float = 5.0
## How quickly the body settles (Hz). Lower = slower, floatier.
@export var body_motion_hz: float = 0.8
## 1 = no wobble, lower = the body overshoots a little and settles.
@export var body_motion_damping: float = 0.55
@export_group("")

const PSX_SHADER := preload("res://assets/vfx/shaders/psx_lit.gdshader")

var wheels: Array[Wheel] = []
var front_wheels: Array[Wheel] = []  ## [left, right]
var rear_wheels: Array[Wheel] = []  ## [left, right]
var driven_wheels: Array[Wheel] = []
var drivetrain := Drivetrain.new()
var assists := HandlingAssists.new()
var input: VehicleInput

# --- Live values (read by HUD, camera, telemetry) ---
var steer_angle: float = 0.0
var forward_speed: float = 0.0  ## m/s, negative when reversing.
var lateral_speed: float = 0.0
var throttle_out: float = 0.0
var brake_out: float = 0.0
var g_long: float = 0.0
var g_lat: float = 0.0
var tc_active: bool = false
var abs_active: bool = false
var stability_active: bool = false
var airborne: bool = false
## True when two or more wheels are on a low-grip surface (grass, gravel).
var off_track: bool = false
## While true (race countdown) the car ignores its driver and holds still.
var controls_locked: bool = false
var spawn_transform: Transform3D

var _reverse_timer: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO
var _front_axle_z: float = -1.3
var _rear_axle_z: float = 1.3
var _wheelbase: float = 2.6
var _model: Node3D
## [MeshInstance3D, surface index, original material, retro material]
var _retro_surfaces: Array = []
## [PS1 material, PS2 material] of the brake and head lamps, glowing live.
var _brake_lamps: Array = []
var _head_lamps: Array = []
var _brake_glow := -1.0
var _night := false
## Crash damage (CarDamage sets these; 1 / 1 / 0 = undamaged).
var damage: CarDamage
var power_scale: float = 1.0
var drag_scale: float = 1.0
var steer_pull: float = 0.0  ## radians, + = pulls right
## Tournament perks (CarPerks sets these each tick): power and drag multipliers,
## and how much crash damage the car takes.
var perk_power: float = 1.0
var perk_drag: float = 1.0
var damage_taken: float = 1.0
## Slipstream: 0..1, how well tucked in behind another car this car is
## (closer and more in line = stronger). Up to 20% less drag.
var draft: float = 0.0
const DRAFT_RANGE := 30.0
## Pit lane: true while in the lane (speed limiter on), seconds of service
## left while stopped in the box, and how many stops this race.
var in_pit_lane := false
var pit_service_left := 0.0
var pit_stops := 0
var _pit_served := false
var _circuit_ref: Circuit
var _head_broken := false
var _brake_broken := false
var _head_energy := 2.2
var _body_visual: Node3D
var _body_pitch: float = 0.0
var _body_pitch_vel: float = 0.0
var _body_roll: float = 0.0
var _body_roll_vel: float = 0.0
const BODY_PIVOT := Vector3(0.0, 0.35, 0.0)
## Real weight transfer: springs and anti-roll bars a bit softer than the
## configs, so the body really pitches and rolls on its suspension (load moves
## between the tyres through the springs) instead of a painted-on lean.
const SPRING_SCALE := 0.8
const ANTI_ROLL_SCALE := 0.7


func _ready() -> void:
	add_to_group("retro_aware")
	add_to_group("vehicles")
	if config == null:
		config = VehicleConfig.new()
	_apply_config()

	for child in get_children():
		if child is Wheel:
			wheels.append(child)
		elif child is VehicleInput:
			input = child
	if input == null:
		input = VehicleInput.new()
		add_child(input)
	if body_model:
		_attach_model()

	GameSettings.ensure_loaded()
	for w in wheels:
		w.setup(self, config)
		w.wear_rate = GameSettings.tyre_wear / 100.0
		if w.is_front:
			front_wheels.append(w)
		else:
			rear_wheels.append(w)
	var left_first := func(a: Wheel, b: Wheel) -> bool: return a.is_left and not b.is_left
	front_wheels.sort_custom(left_first)
	rear_wheels.sort_custom(left_first)
	match config.drive_type:
		VehicleConfig.DriveType.FWD:
			driven_wheels = front_wheels.duplicate()
		VehicleConfig.DriveType.RWD:
			driven_wheels = rear_wheels.duplicate()
		_:
			driven_wheels = wheels.duplicate()

	_front_axle_z = _mean_z(front_wheels)
	_rear_axle_z = _mean_z(rear_wheels)
	_wheelbase = maxf(absf(_rear_axle_z - _front_axle_z), 1.0)

	drivetrain.setup(config)
	if sounds_enabled and DisplayServer.get_name() != "headless":
		var audio := CarAudio.new()
		audio.name = "Audio"
		add_child(audio)
	GameSettings.ensure_loaded()
	set_handling_profile(GameSettings.handling_profile)
	spawn_transform = global_transform
	_setup_damage.call_deferred()


## Crash damage unless it is off in the race settings or the scene opts out
## (the main menu's background cars join group "no_damage").
func _setup_damage() -> void:
	if not is_inside_tree() or GameSettings.damage <= 0 or _model == null:
		return
	if get_tree().get_first_node_in_group("no_damage") != null:
		return
	# DURABILITY (race setting): 200% = half the damage from the same crash.
	damage_taken *= 100.0 / maxf(GameSettings.durability, 1.0)
	damage = CarDamage.new()
	damage.name = "Damage"
	add_child(damage)
	damage.setup(self, GameSettings.damage)


func _apply_config() -> void:
	mass = config.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = config.center_of_mass
	var s := config.inertia_box_size
	inertia = Vector3(s.y * s.y + s.z * s.z, s.x * s.x + s.z * s.z, s.x * s.x + s.y * s.y) \
			* (mass / 12.0) * config.inertia_scale
	can_sleep = false
	continuous_cd = true
	# The project's default damping would act like a hidden brake; drag and
	# rolling resistance are modelled explicitly instead.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0


## Switches the assists and tyre shape to profile p (0 Arcade, 1 Sport, 2 Sim) and emits profile_changed.
func set_handling_profile(p: int) -> void:
	assists.set_profile(p)
	handling_profile = assists.profile
	var shape := TireModel.shape_from_falloff(assists.tire_falloff)
	for w in wheels:
		w.tire_shape = shape
	profile_changed.emit(handling_profile)


## Front wheel angle (radians) that full steering input gives right now.
func current_steer_limit() -> float:
	return assists.steer_limit(forward_speed, deg_to_rad(config.max_steer_deg), _wheelbase, config.tire_grip)


## Distance between the front and rear axles, in metres.
func wheelbase() -> float:
	return _wheelbase


## World velocity (m/s) of a world-space point on the body, including rotation.
func velocity_at_point(world_point: Vector3) -> Vector3:
	var com := global_transform * center_of_mass
	return linear_velocity + angular_velocity.cross(world_point - com)


func _physics_process(delta: float) -> void:
	_update_brake_lamps()
	input.poll(delta)
	if controls_locked:
		input.throttle = 0.0
		input.brake = 1.0
		input.steer = 0.0
		input.handbrake = 1.0
	_update_pit(delta)
	if _handle_meta_inputs():
		return
	if global_position.y < FALL_RESET_Y:
		reset_to_start()
		return

	var b := global_basis
	var fwd := -b.z
	var right := b.x
	forward_speed = linear_velocity.dot(fwd)
	lateral_speed = linear_velocity.dot(right)
	var accel := (linear_velocity - _prev_velocity) / delta
	_prev_velocity = linear_velocity
	g_long = lerpf(g_long, accel.dot(fwd) / 9.81, 0.1)
	g_lat = lerpf(g_lat, accel.dot(right) / 9.81, 0.1)

	var pedals := _update_gears(delta)
	var thr := pedals.x
	var brk := pedals.y

	# --- Steering ---
	var target := assists.steer_target(input.steer, forward_speed, lateral_speed,
			deg_to_rad(config.max_steer_deg), _wheelbase, config.tire_grip)
	# At speed the wheels turn more slowly (the usable lock is small there):
	# about 0.2 s to full lock, so a flick of the stick can't make the car dart.
	var steer_speed := minf(config.steer_rate, maxf(current_steer_limit() * 5.0, 0.35))
	steer_angle = move_toward(steer_angle, target, steer_speed * delta)
	for w in front_wheels:
		w.steer_angle = steer_angle + steer_pull

	# --- Suspension ---
	var grounded_count := 0
	for w in wheels:
		w.update_suspension(delta)
		w.tire_load = w.spring_force
		if w.grounded:
			grounded_count += 1
	airborne = grounded_count == 0
	var slow_wheels := 0
	for w in wheels:
		if w.grounded and not w.on_road:
			slow_wheels += 1
	off_track = slow_wheels >= 2
	_apply_anti_roll(front_wheels, config.front_anti_roll)
	_apply_anti_roll(rear_wheels, config.rear_anti_roll)
	for w in wheels:
		if w.grounded and w.tire_load > 0.0:
			apply_force(b.y * w.tire_load, w.contact_point - global_position)
			# What the car stands on feels its weight (a seesaw tips).
			var under := w.pushable_ground()
			if under:
				under.apply_force(-b.y * w.tire_load, w.contact_point - under.global_position)

	# --- Tyres, engine and brakes ---
	for w in wheels:
		# Relative to the ground under the tyre (it may be a lift or a turntable).
		w.prepare_tire(b, velocity_at_point(w.contact_point) - w.ground_velocity())

	var tc := assists.traction_factor(driven_wheels, config.tire_peak_slip_ratio, forward_speed)
	tc *= assists.oversteer_cut(atan2(lateral_speed, maxf(absf(forward_speed), 0.5)), forward_speed)
	throttle_out = thr * tc
	tc_active = thr > 0.05 and tc < 0.95
	var wheel_torque := drivetrain.update(_driven_mean_omega(), throttle_out, delta) * power_scale * perk_power

	abs_active = false
	brake_out = brk
	var front_brake := config.brake_torque * config.brake_bias * 0.5 * brk
	var rear_brake := config.brake_torque * (1.0 - config.brake_bias) * 0.5 * brk
	for w in wheels:
		var t := front_brake if w.is_front else rear_brake
		if brk > 0.01:
			var f := assists.abs_factor(w.slip_ratio * signf(w.v_long), config.tire_peak_slip_ratio)
			if f < 0.98:
				abs_active = true
			t *= f
		if not w.is_front:
			t += config.handbrake_torque * input.handbrake
		w.brake_torque = t

	var h := delta / SUBSTEPS
	for i in SUBSTEPS:
		_distribute_drive_torque(wheel_torque)
		for w in wheels:
			w.substep(h)
	for w in wheels:
		var tire_force := w.finish_tire(SUBSTEPS)
		if w.grounded:
			apply_force(tire_force, w.contact_point - global_position)
			var under := w.pushable_ground()
			if under:
				under.apply_force(-tire_force, w.contact_point - under.global_position)
		w.update_tyre(delta)
		w.update_visual(delta)

	_apply_aero()
	_apply_stability()
	_check_trip()
	if airborne:
		_apply_air_control()
	# (The old painted-on body lean is off: the body moves on its springs now.)


## Slow, springy body tilt on top of the real suspension movement, so speeding
## up lifts the nose and braking dips it (wheels stay where they are).
func _update_body_motion(delta: float) -> void:
	if _body_visual == null:
		_body_visual = _model if _model else get_node_or_null("Greybox") as Node3D
		if _body_visual == null:
			return
	var w := TAU * body_motion_hz
	var target_pitch := clampf(g_long, -1.5, 1.5) * deg_to_rad(pitch_per_g_deg)
	var target_roll := clampf(g_lat, -1.5, 1.5) * deg_to_rad(roll_per_g_deg)
	if airborne:
		target_pitch = 0.0
		target_roll = 0.0
	_body_pitch_vel += (w * w * (target_pitch - _body_pitch) - 2.0 * body_motion_damping * w * _body_pitch_vel) * delta
	_body_pitch += _body_pitch_vel * delta
	_body_roll_vel += (w * w * (target_roll - _body_roll) - 2.0 * body_motion_damping * w * _body_roll_vel) * delta
	_body_roll += _body_roll_vel * delta
	# + pitch lifts the nose (-Z); + roll lifts the right side (leans outward
	# in a right-hander, where g_lat is positive).
	var tilt := Basis(Vector3.RIGHT, _body_pitch) * Basis(Vector3.BACK, _body_roll)
	_body_visual.transform = Transform3D(tilt, BODY_PIVOT - tilt * BODY_PIVOT)


## Gear selection. Returns the (throttle, brake) actually sent to the car.
func _update_gears(delta: float) -> Vector2:
	var thr := input.throttle
	var brk := input.brake
	if controls_locked:
		# Held on the grid: brakes on, stay in first gear.
		_reverse_timer = 0.0
		if drivetrain.gear < 1:
			drivetrain.set_gear(1)
		return Vector2(0.0, 1.0)
	if input.toggle_transmission_pressed:
		drivetrain.automatic = not drivetrain.automatic
	if input.shift_up_pressed:
		drivetrain.automatic = false
		drivetrain.shift_up()
	if input.shift_down_pressed:
		drivetrain.automatic = false
		drivetrain.shift_down()

	if drivetrain.automatic:
		if drivetrain.gear == 0:
			drivetrain.set_gear(1)
		if drivetrain.gear >= 1:
			# Hold the brake while stopped to engage reverse.
			if brk > 0.3 and thr < 0.1 and forward_speed < 0.8:
				_reverse_timer += delta
				if _reverse_timer > 0.35:
					drivetrain.set_gear(-1)
					_reverse_timer = 0.0
			else:
				_reverse_timer = 0.0
		elif thr > 0.3 and forward_speed > -0.8:
			drivetrain.set_gear(1)
		if drivetrain.gear == -1:
			# In reverse the brake pedal drives backwards and throttle brakes.
			var swap := thr
			thr = brk
			brk = swap
		drivetrain.update_auto()
	return Vector2(thr, brk)


func _apply_anti_roll(pair: Array[Wheel], stiffness: float) -> void:
	if pair.size() < 2:
		return
	var l := pair[0]
	var r := pair[1]
	var diff := (l.rest_length - l.spring_length) - (r.rest_length - r.spring_length)
	var force := diff * stiffness * ANTI_ROLL_SCALE
	if l.grounded:
		l.tire_load = maxf(l.tire_load + force, 0.0)
	if r.grounded:
		r.tire_load = maxf(r.tire_load - force, 0.0)


func _distribute_drive_torque(total: float) -> void:
	for w in wheels:
		w.drive_torque = 0.0
	match config.drive_type:
		VehicleConfig.DriveType.FWD:
			_split_axle(front_wheels, total)
		VehicleConfig.DriveType.RWD:
			_split_axle(rear_wheels, total)
		_:
			_split_axle(front_wheels, total * config.awd_front_split)
			_split_axle(rear_wheels, total * (1.0 - config.awd_front_split))


func _split_axle(pair: Array[Wheel], torque: float) -> void:
	if pair.size() < 2:
		return
	var dw := pair[0].omega - pair[1].omega
	# Limited slip that scales with the drive (clutch type): when one wheel
	# spins faster (the light inside wheel in a corner), up to `bias` of the
	# axle's torque moves to the wheel that grips, so the power isn't lost.
	var bias := maxf(config.diff_lock, assists.lsd_min)
	var shift := clampf(dw * 400.0, -absf(torque) * 0.5 * bias, absf(torque) * 0.5 * bias)
	# Plus the old viscous coupling (keeps the wheels together off throttle).
	shift += config.diff_lock * DIFF_LOCK_MAX * dw
	pair[0].drive_torque = torque * 0.5 - shift
	pair[1].drive_torque = torque * 0.5 + shift


func _driven_mean_omega() -> float:
	if driven_wheels.is_empty():
		return 0.0
	var sum := 0.0
	for w in driven_wheels:
		sum += w.omega
	return sum / driven_wheels.size()


func _apply_aero() -> void:
	var v := linear_velocity
	var v2 := v.length_squared()
	if v2 < 0.01:
		return
	if Engine.get_physics_frames() % 4 == 0:
		draft = _measure_draft()
	var slip := 1.0 - 0.2 * draft
	apply_central_force(-v.normalized() * 0.5 * AIR_DENSITY * v2 * config.drag_area * drag_scale * perk_drag * slip)
	var down := 0.5 * AIR_DENSITY * forward_speed * forward_speed * config.downforce_area
	var b := global_basis
	apply_force(-b.y * down * config.aero_balance, b * Vector3(0.0, 0.3, _front_axle_z))
	apply_force(-b.y * down * (1.0 - config.aero_balance), b * Vector3(0.0, 0.3, _rear_axle_z))


## Pit lane: 60 km/h limiter in the lane; stop in the box zone and the crew
## fits new tyres and fixes the damage (3 s + up to 4 s for a wreck).
func _update_pit(delta: float) -> void:
	if _circuit_ref == null:
		_circuit_ref = get_tree().get_first_node_in_group("circuit") as Circuit
	if _circuit_ref == null or _circuit_ref.pit.is_empty():
		return
	in_pit_lane = _circuit_ref.in_pit_lane(global_position)
	if not in_pit_lane:
		_pit_served = false
		pit_service_left = 0.0
		return
	if pit_service_left > 0.0:
		pit_service_left -= delta
		input.throttle = 0.0
		input.brake = 1.0
		input.handbrake = 1.0
		if pit_service_left <= 0.0:
			for w in wheels:
				w.new_tyres()
			if damage:
				damage.repair()
			pit_stops += 1
			_pit_served = true
		return
	if not _pit_served and absf(forward_speed) < 1.5 and _circuit_ref.in_pit_zone(global_position):
		pit_service_left = 3.0 + (damage.total() * 8.0 if damage else 0.0)
		return
	# Speed limiter.
	if forward_speed > Circuit.PIT_LIMIT:
		input.throttle = 0.0
		input.brake = maxf(input.brake, clampf((forward_speed - Circuit.PIT_LIMIT) * 0.4, 0.0, 1.0))
	elif forward_speed > Circuit.PIT_LIMIT - 1.0:
		input.throttle = minf(input.throttle, 0.2)


## How strongly this car is in another car's wake (0 = clean air).
func _measure_draft() -> float:
	if forward_speed < 15.0:
		return 0.0
	var fwd := -global_basis.z
	var best := 0.0
	for node in get_tree().get_nodes_in_group("vehicles"):
		var other := node as Vehicle
		if other == null or other == self:
			continue
		var to := other.global_position - global_position
		var d := to.length()
		if d < 3.0 or d > DRAFT_RANGE:
			continue
		var line := to.normalized().dot(fwd)
		if line < 0.96:
			continue
		# Strongest close behind and right in line.
		best = maxf(best, (1.0 - d / DRAFT_RANGE) * smoothstep(0.96, 0.995, line))
	return clampf(best * 1.6, 0.0, 1.0)


## Yaw damping when the car rotates faster than the steering asks for, and
## (at speed) against sudden swings of the rotation, so turn-in doesn't
## overshoot and the car settles into the corner instead of wagging.
var _yaw_smooth := 0.0

func _apply_stability() -> void:
	stability_active = false
	var up := global_basis.y
	var yaw_now := angular_velocity.dot(up)
	_yaw_smooth = lerpf(_yaw_smooth, yaw_now, clampf(get_physics_process_delta_time() / 0.25, 0.0, 1.0))
	if assists.stability <= 0.0 or airborne or forward_speed < 3.0:
		return
	var fast := clampf((forward_speed - 10.0) / 20.0, 0.0, 1.0)
	if fast > 0.0:
		apply_torque(up * (-(yaw_now - _yaw_smooth) * assists.stability * inertia.y * 6.0 * fast))
	var yaw_rate := yaw_now
	var desired := -forward_speed * tan(steer_angle) / _wheelbase
	# The tyres cannot turn the car faster than grip allows, so cap the target.
	var grip_limit := config.tire_grip * 9.81 / maxf(forward_speed, 1.0) * 1.15
	desired = clampf(desired, -grip_limit, grip_limit)
	if absf(yaw_rate) > absf(desired) + 0.05:
		var err := yaw_rate - desired
		apply_torque(up * (-err * assists.stability * inertia.y * 2.5))
		stability_active = true


## Tripping: a car sliding sideways fast whose leading wheels dig into
## gravel or sand, or run on a flat / missing wheel, gets rolled over that
## side (only with damage on).
func _check_trip() -> void:
	if damage == null or airborne:
		return
	var up := global_basis.y
	if up.y < 0.5:
		return  # already going over: physics takes it from here
	var v_lat := linear_velocity.dot(global_basis.x)
	if absf(v_lat) < 10.0:
		return
	var lead_left := v_lat < 0.0
	var dig := 0.0
	for w in wheels:
		if w.is_left != lead_left:
			continue
		if w.detached or w.deflate > 0.6:
			dig = maxf(dig, 1.0)
		elif w.grounded and w.surface_drag > 0.05:
			dig = maxf(dig, clampf(w.surface_drag * 1.8, 0.0, 0.45))
	if dig <= 0.0:
		return
	var k := clampf((absf(v_lat) - 10.0) / 8.0, 0.0, 1.0) * dig
	# Sliding right (+x): the right side digs in and drops, the left lifts.
	apply_torque(-global_basis.z * signf(v_lat) * inertia.z * 30.0 * k)


## A huge side hit can start a roll-over: kick the car around its length.
func knock_roll(push_side: float, strength: float) -> void:
	apply_torque_impulse(-global_basis.z * push_side * inertia.z * 10.0 * strength)
	apply_central_impulse(Vector3.UP * mass * 2.5 * strength)


## Small pitch/roll correction while airborne (rally jumps).
func _apply_air_control() -> void:
	if assists.air_control <= 0.0:
		return
	var up := global_basis.y
	if up.y < 0.64:
		return  # past ~50 degrees: a real crash, let it roll over
	var level := up.cross(Vector3.UP)
	var w := angular_velocity
	var spin := w - Vector3.UP * w.dot(Vector3.UP)
	var strength := assists.air_control * (inertia.x + inertia.z) * 0.5
	apply_torque((level * 4.0 - spin * 1.0) * strength)


## Returns true if the car was moved this tick.
func _handle_meta_inputs() -> bool:
	if input.cycle_profile_pressed:
		set_handling_profile((handling_profile + 1) % HandlingAssists.PROFILE_NAMES.size())
		GameSettings.handling_profile = handling_profile
		GameSettings.save()
	if input.restart_pressed:
		reset_to_start()
		return true
	if input.recover_pressed and not Tournament.active:
		recover()
		return true
	return false


## Put the car back on its wheels where it is, facing the same way.
func recover() -> void:
	var facing := -global_basis.z
	facing.y = 0.0
	if facing.length() < 0.1:
		facing = Vector3.FORWARD
	teleport(Transform3D(Basis.looking_at(facing.normalized(), Vector3.UP),
			global_position + Vector3.UP * 1.0))


## Puts the car back on its grid spot, stopped, and emits reset_to_start_done.
## Falls back to the circuit's start line if the saved spot is underground.
func reset_to_start() -> void:
	# Safety net: a reset point underground (car never placed on the grid)
	# would make it fall forever; use the circuit's start line instead.
	var circuit := get_tree().get_first_node_in_group("circuit") as Circuit
	if circuit:
		var o := spawn_transform.origin
		if o.y < circuit.surface_height(o.x, o.z) - 2.0:
			spawn_transform = circuit.get_spawn_transform()
	teleport(spawn_transform)
	reset_to_start_done.emit()


## Moves the car to `xform` and stops it: velocities, steering, wheels and gearbox are reset, and a lost wheel is refitted.
func teleport(xform: Transform3D) -> void:
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_velocity = Vector3.ZERO
	steer_angle = 0.0
	for w in wheels:
		w.reset()
		w.detached = false  # a recovery puts a lost wheel back on
	drivetrain.reset()
	reset_physics_interpolation()


func _mean_z(list: Array[Wheel]) -> float:
	if list.is_empty():
		return 0.0
	var sum := 0.0
	for w in list:
		sum += w.position.z
	return sum / list.size()


# --- Imported model & retro look ---------------------------------------------

func _attach_model() -> void:
	_model = body_model.instantiate() as Node3D
	set_livery(show_livery)
	_model.name = "Model"
	add_child(_model)
	var greybox := get_node_or_null("Greybox") as Node3D
	if greybox:
		greybox.visible = false
	for w in wheels:
		var key := String(w.name).trim_prefix("Wheel")
		# "wheel_FL" (Blender may add a suffix such as "wheel_FL.001").
		var src := _model.find_child("wheel_" + key + "*", true, false) as Node3D
		if src == null:
			push_warning("%s: model has no wheel_%s" % [name, key])
			continue
		if align_wheels_to_model:
			var hub := to_local(src.global_position)
			# Mount sits one static spring length above the hub.
			var corner_load := config.mass * 9.81 * 0.25
			var rate := (config.front_spring_rate if w.is_front else config.rear_spring_rate) * SPRING_SCALE
			w.position = Vector3(hub.x, hub.y + config.rest_length - corner_load / rate, hub.z)
		w.custom_visual = src
	_fit_collision_to_model()
	_shade_tex = CarLook.shade_texture(_model)
	_collect_retro_surfaces(_model)
	_setup_lamps()


## Headlights glow (brighter at night, with a real light beam), brake
## lights flare up while braking.
func _setup_lamps() -> void:
	GameSettings.ensure_loaded()
	_night = GameSettings.time_of_day == 3 and get_tree().get_first_node_in_group("circuit") != null
	_head_energy = 5.0 if _night else 0.4  # by day just a lit lens, not a glare
	_set_lamp_energy(_head_lamps, _head_energy)
	_update_brake_lamps(true)
	if not _night or DisplayServer.get_name() == "headless":
		return
	var body := _model.find_child("body*", true, false) as MeshInstance3D
	var front := -2.2
	if body:
		var box := body.mesh.get_aabb()
		front = to_local(body.global_transform * box.position).z
	var beam := SpotLight3D.new()
	beam.name = "HeadlightBeam"
	beam.position = Vector3(0.0, 0.75, front - 0.1)
	beam.rotation_degrees = Vector3(-7.0, 0.0, 0.0)
	beam.spot_range = 60.0
	beam.spot_angle = 32.0
	beam.spot_attenuation = 0.8
	beam.light_energy = 9.0
	beam.light_color = Color(1.0, 0.95, 0.85)
	add_child(beam)


func _update_brake_lamps(force: bool = false) -> void:
	if _brake_lamps.is_empty():
		return
	var braking := input != null and (input.brake > 0.05 or input.handbrake > 0.5)
	var glow := 7.0 if braking else (2.0 if _night else 0.45)
	if _brake_broken:
		glow = 0.0
	if force or glow != _brake_glow:
		_brake_glow = glow
		_set_lamp_energy(_brake_lamps, glow)


## Smashed lamps go dark (and the night beam with the headlights).
func set_lamps_broken(head: bool, brake: bool) -> void:
	if head != _head_broken:
		_head_broken = head
		_set_lamp_energy(_head_lamps, 0.0 if head else _head_energy)
		var beam := get_node_or_null("HeadlightBeam") as Light3D
		if beam:
			beam.visible = not head
	if brake != _brake_broken:
		_brake_broken = brake
		_update_brake_lamps(true)


## Damage darkens these surfaces of `mi` through its vertex colours.
func use_vertex_tint(mi: MeshInstance3D) -> void:
	for entry: Array in _retro_surfaces:
		if entry[0] == mi:
			(entry[3] as ShaderMaterial).set_shader_parameter("vertex_tint", 1.0)
			if entry[4] is BaseMaterial3D:
				(entry[4] as BaseMaterial3D).vertex_color_use_as_albedo = true


## Paint, glass and chrome get glossy so they reflect the sky and sun.
func _set_shine(mat_name: String, retro: ShaderMaterial, soft: BaseMaterial3D) -> void:
	var rough := -1.0
	var metal := 0.0
	if mat_name.contains("paint"):
		# Satin, not mirror: the body's shape and shading read, like PS1 cars.
		rough = 0.5
		metal = 0.15
		soft.clearcoat_enabled = true
		soft.clearcoat = 0.8
		soft.clearcoat_roughness = 0.15
	elif mat_name.contains("glass"):
		# Dark tinted glass with a soft sheen (pale mirror glass washed the cabins out).
		rough = 0.25
		metal = 0.15
	elif mat_name.contains("chrome") or mat_name.contains("rim_silver") or mat_name.contains("silver"):
		rough = 0.18
		metal = 0.9
	if rough < 0.0:
		return
	retro.set_shader_parameter("roughness_value", rough)
	retro.set_shader_parameter("metallic_value", metal)
	retro.set_shader_parameter("specular_value", 0.6)
	soft.roughness = rough
	soft.metallic = metal
	soft.metallic_specular = 0.7


func _set_lamp_energy(lamps: Array, energy: float) -> void:
	for pair: Array in lamps:
		(pair[0] as ShaderMaterial).set_shader_parameter("emission_energy", energy)
		var soft := pair[1] as BaseMaterial3D
		soft.emission_enabled = true
		soft.emission_energy_multiplier = energy


## Switches the model's livery (a separate "livery" mesh) on or off.
func set_livery(on: bool) -> void:
	show_livery = on
	if _model:
		var liv := _model.find_child("livery*", true, false) as Node3D
		if liv:
			liv.visible = on


## Collision shape: a rounded hull wrapped round the model's body (so cars
## slide off each other, roll over and tumble naturally instead of acting like
## two boxes). The floor of the hull stays above the wheels' contact so the
## body doesn't scrape on kerbs. Worked out once per car model.
static var _hull_cache: Dictionary = {}

func _fit_collision_to_model() -> void:
	var body := _model.find_child("body*", true, false) as MeshInstance3D
	if body == null:
		return
	var key := body.mesh.resource_path if body.mesh.resource_path != "" else str(body.mesh.get_instance_id())
	var shapes: Array = _hull_cache.get(key, [])
	if shapes.is_empty():
		shapes = _build_hulls(body)
		_hull_cache[key] = shapes
	# shapes = [lower piece 0 .. LOWER_PIECES-1, cabin]: one lower piece on
	# CollisionBody, the cabin on CollisionCabin, the rest on extra shapes.
	var main := LOWER_PIECES / 2
	var lower := get_node_or_null("CollisionBody") as CollisionShape3D
	if lower:
		lower.shape = shapes[main]
		lower.transform = Transform3D.IDENTITY
	var cabin := get_node_or_null("CollisionCabin") as CollisionShape3D
	if cabin:
		cabin.shape = shapes[LOWER_PIECES]
		cabin.transform = Transform3D.IDENTITY
		cabin.disabled = shapes[LOWER_PIECES] == null
	for k in LOWER_PIECES:
		if k == main:
			continue
		var part_name := "CollisionPart%d" % k
		var part := get_node_or_null(part_name) as CollisionShape3D
		if part == null:
			part = CollisionShape3D.new()
			part.name = part_name
			add_child(part)
		part.shape = shapes[k]
		part.disabled = shapes[k] == null


## Hulls hugging the model: the lower body (up to the belt line) in pieces
## along the car so it follows the bonnet and boot slopes, and the cabin
## (glasshouse) on top. One hull round the whole car bridged from the mirrors,
## over the bonnet and over the narrower cabin: empty space you could hit.
## Antenna tips and mirrors are left out.
const LOWER_PIECES := 6

func _build_hulls(body: MeshInstance3D) -> Array:
	var to_car := global_transform.affine_inverse() * body.global_transform
	var bottom := 0.32
	var seen := {}
	var pts: Array[Vector3] = []
	for sidx in body.mesh.get_surface_count():
		var verts: PackedVector3Array = body.mesh.surface_get_arrays(sidx)[Mesh.ARRAY_VERTEX]
		for v in verts:
			var p := to_car * v
			p.y = maxf(p.y, bottom)
			# One point per 8 cm cell is plenty for the hulls.
			var cell := Vector3i((p / 0.08).round())
			if not seen.has(cell):
				seen[cell] = true
				pts.append(p)
	var ys: Array[float] = []
	for p in pts:
		ys.append(p.y)
	ys.sort()
	var top := ys[int(ys.size() * 0.985)]
	var belt := bottom + (top - bottom) * 0.5
	# Widths: the lower body without mirror tips, the cabin narrower.
	var xs_lower: Array[float] = []
	var xs_upper: Array[float] = []
	var high_z: Array[float] = []
	var peak := Vector3(0, -INF, 0)
	for p in pts:
		if p.y > top + 0.03:
			continue  # antenna, tall aerials
		if p.y <= belt + 0.04:
			xs_lower.append(absf(p.x))
		else:
			xs_upper.append(absf(p.x))
		if p.y > belt + 0.2:
			high_z.append(p.z)
		if p.y > peak.y:
			peak = p
	xs_lower.sort()
	xs_upper.sort()
	# The glasshouse: the run of high points round the roof's peak; a rear
	# wing or a roll bar further along (a gap of 30 cm+) isn't part of it.
	high_z.sort()
	var cabin_z := Vector2(peak.z, peak.z)
	var at := high_z.bsearch(peak.z)
	var i := clampi(at, 0, high_z.size() - 1)
	while i > 0 and high_z[i] - high_z[i - 1] < 0.3:
		i -= 1
	if not high_z.is_empty():
		cabin_z.x = minf(high_z[i], peak.z)
	i = clampi(at, 0, high_z.size() - 1)
	while i < high_z.size() - 1 and high_z[i + 1] - high_z[i] < 0.3:
		i += 1
	if not high_z.is_empty():
		cabin_z.y = maxf(high_z[i], peak.z)
	var lower_w := xs_lower[int(xs_lower.size() * 0.99)] if not xs_lower.is_empty() else 1.0
	var cabin_w := xs_upper[int(xs_upper.size() * 0.85)] + 0.04 if not xs_upper.is_empty() else 1.0
	var z_front := INF
	var z_back := -INF
	for p in pts:
		z_front = minf(z_front, p.z)
		z_back = maxf(z_back, p.z)
	var step := (z_back - z_front) / LOWER_PIECES
	var parts: Array[Array] = []
	for k in LOWER_PIECES:
		parts.append([])
	var lower_all := PackedVector3Array()
	var upper := PackedVector3Array()
	for p in pts:
		if p.y > top + 0.03:
			continue
		if p.y <= belt + 0.04 and absf(p.x) <= lower_w + 0.01:
			lower_all.append(p)
			for k in LOWER_PIECES:
				# Overlap 10 cm so there's no gap between the pieces.
				if p.z >= z_front + step * k - 0.1 and p.z <= z_front + step * (k + 1) + 0.1:
					parts[k].append(p)
		# The glasshouse only: between the screen bottoms, not over the bonnet.
		if p.y >= belt - 0.04 and absf(p.x) <= cabin_w and p.z >= cabin_z.x - 0.05 and p.z <= cabin_z.y + 0.05:
			upper.append(p)
	var out: Array = []
	for k in LOWER_PIECES:
		var part := PackedVector3Array(parts[k])
		if part.size() >= 8:
			var sh := ConvexPolygonShape3D.new()
			sh.points = part
			out.append(sh)
		else:
			out.append(null)
	if out[LOWER_PIECES / 2] == null:  # never leave the car without a body shape
		var sh := ConvexPolygonShape3D.new()
		sh.points = lower_all
		out[LOWER_PIECES / 2] = sh
	var upper_shape: ConvexPolygonShape3D = null
	if upper.size() >= 8:
		upper_shape = ConvexPolygonShape3D.new()
		upper_shape.points = upper
	out.append(upper_shape)
	return out


var _shade_tex: Texture2D

func _collect_retro_surfaces(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var original := mi.get_active_material(i)
			if original is BaseMaterial3D:
				var tex: Texture2D = paint_texture
				var src := (original as BaseMaterial3D).albedo_texture
				if paint_color.a > 0.0 and paint_reference and src:
					tex = CarPaint.make(src, paint_reference, paint_color)
				if tex:
					var painted := original.duplicate() as BaseMaterial3D
					painted.albedo_texture = tex
					original = painted
				elif paint_color.a > 0.0 and original.resource_name.contains("paint"):
					# Flat-colour models: the paint material just changes colour.
					var recolored := original.duplicate() as BaseMaterial3D
					recolored.albedo_color = paint_color
					original = recolored
				elif paint_color.a > 0.0 and original.resource_name.contains("seam"):
					# Door seams: a darker shade of the (new) paint.
					var seam := original.duplicate() as BaseMaterial3D
					seam.albedo_color = Color(paint_color.r * 0.7, paint_color.g * 0.7, paint_color.b * 0.7)
					original = seam
			var retro := ShaderMaterial.new()
			retro.shader = CarLook.PSX_DECAL_SHADER if _is_livery(mi) else PSX_SHADER
			var ps2: Material = null
			if original is BaseMaterial3D:
				var base := original as BaseMaterial3D
				retro.set_shader_parameter("albedo_tex", base.albedo_texture)
				var is_paint := base.resource_name.to_lower().contains("paint") and not _is_livery(mi)
				retro.set_shader_parameter("albedo_color", CarLook.grade_paint(base.albedo_color) if is_paint else base.albedo_color)
				if base.emission_enabled:
					retro.set_shader_parameter("emission_color", base.emission)
					# Running lights / amber lamps: a soft glow by day, full at night.
					var lamp_energy := base.emission_energy_multiplier
					if GameSettings.time_of_day != 3:
						lamp_energy = minf(lamp_energy, 0.5)
					retro.set_shader_parameter("emission_energy", lamp_energy)
				# PS2 style: smooth (bilinear) textures and per-vertex lighting.
				var soft := base.duplicate() as BaseMaterial3D
				soft.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				soft.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
				soft.roughness = 0.55
				soft.metallic_specular = 0.6
				if is_paint:
					soft.albedo_color = CarLook.grade_paint(base.albedo_color)
				if _shade_tex and String(mi.name).begins_with("body"):
					soft.detail_enabled = true
					soft.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
					soft.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
					soft.detail_albedo = _shade_tex
				ps2 = soft
				var mat_name := base.resource_name.to_lower()
				_set_shine(mat_name, retro, soft)
				if mat_name.contains("taillight"):
					_brake_lamps.append([retro, soft])
				elif mat_name.contains("headlight") and not mat_name.contains("amber"):
					_head_lamps.append([retro, soft])
			if _is_livery(mi):
				CarLook.make_decal(retro)
			CarLook.apply_shade(retro, mi, _shade_tex)
			_retro_surfaces.append([mi, i, original, retro, ps2])
	for child in node.get_children():
		_collect_retro_surfaces(child)


func _is_livery(node: Node) -> bool:
	while node != null and node != _model:
		if String(node.name).begins_with("livery"):
			return true
		node = node.get_parent()
	return false


## Called by RetroLook: 0 = modern, 1 = PS2, 2 = PS1.
func set_retro_level(level: int) -> void:
	var res := RetroLook.resolution_for(level)
	for entry: Array in _retro_surfaces:
		var mi: MeshInstance3D = entry[0]
		var retro: ShaderMaterial = entry[3]
		retro.set_shader_parameter("snap_resolution", res)
		var mat: Material = entry[2]
		if level == RetroLook.Level.PS1:
			mat = retro
		elif level == RetroLook.Level.PS2:
			mat = entry[4]
		mi.set_surface_override_material(entry[1], mat)
