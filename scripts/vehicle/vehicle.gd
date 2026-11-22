class_name Vehicle
extends RigidBody3D
## Custom raycast vehicle on a RigidBody3D (design concept §6.1, §14.2).
## Owns four Wheel children and one VehicleInput child (player, AI or replay).
## Everything runs in _physics_process at the project's 120 Hz tick.

signal profile_changed(profile: int)
## Emitted after the car is put back on the start (Backspace).
signal reset_to_start_done

const SUBSTEPS := 4
## Limited-slip coupling at diff_lock = 1, in N·m per rad/s of speed difference.
const DIFF_LOCK_MAX := 150.0
const AIR_DENSITY := 1.225
const FALL_RESET_Y := -30.0

@export var config: VehicleConfig
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
var _body_visual: Node3D
var _body_pitch: float = 0.0
var _body_pitch_vel: float = 0.0
var _body_roll: float = 0.0
var _body_roll_vel: float = 0.0
const BODY_PIVOT := Vector3(0.0, 0.35, 0.0)


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

	for w in wheels:
		w.setup(self, config)
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
	set_handling_profile(handling_profile)
	spawn_transform = global_transform


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


func wheelbase() -> float:
	return _wheelbase


func velocity_at_point(world_point: Vector3) -> Vector3:
	var com := global_transform * center_of_mass
	return linear_velocity + angular_velocity.cross(world_point - com)


func _physics_process(delta: float) -> void:
	input.poll(delta)
	if controls_locked:
		input.throttle = 0.0
		input.brake = 1.0
		input.steer = 0.0
		input.handbrake = 1.0
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
	steer_angle = move_toward(steer_angle, target, config.steer_rate * delta)
	for w in front_wheels:
		w.steer_angle = steer_angle

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
		if w.grounded and w.surface_grip < 0.85:
			slow_wheels += 1
	off_track = slow_wheels >= 2
	_apply_anti_roll(front_wheels, config.front_anti_roll)
	_apply_anti_roll(rear_wheels, config.rear_anti_roll)
	for w in wheels:
		if w.grounded and w.tire_load > 0.0:
			apply_force(b.y * w.tire_load, w.contact_point - global_position)

	# --- Tyres, engine and brakes ---
	for w in wheels:
		w.prepare_tire(b, velocity_at_point(w.contact_point))

	var tc := assists.traction_factor(driven_wheels, config.tire_peak_slip_ratio)
	throttle_out = thr * tc
	tc_active = thr > 0.05 and tc < 0.95
	var wheel_torque := drivetrain.update(_driven_mean_omega(), throttle_out, delta)

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
		w.update_visual(delta)

	_apply_aero()
	_apply_stability()
	if airborne:
		_apply_air_control()
	_update_body_motion(delta)


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
	var force := diff * stiffness
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
	var lock := config.diff_lock * DIFF_LOCK_MAX
	var dw := pair[0].omega - pair[1].omega
	pair[0].drive_torque = torque * 0.5 - lock * dw
	pair[1].drive_torque = torque * 0.5 + lock * dw


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
	apply_central_force(-v.normalized() * 0.5 * AIR_DENSITY * v2 * config.drag_area)
	var down := 0.5 * AIR_DENSITY * forward_speed * forward_speed * config.downforce_area
	var b := global_basis
	apply_force(-b.y * down * config.aero_balance, b * Vector3(0.0, 0.3, _front_axle_z))
	apply_force(-b.y * down * (1.0 - config.aero_balance), b * Vector3(0.0, 0.3, _rear_axle_z))


## Yaw damping when the car rotates faster than the steering asks for.
func _apply_stability() -> void:
	stability_active = false
	if assists.stability <= 0.0 or airborne or forward_speed < 3.0:
		return
	var up := global_basis.y
	var yaw_rate := angular_velocity.dot(up)
	var desired := -forward_speed * tan(steer_angle) / _wheelbase
	# The tyres cannot turn the car faster than grip allows, so cap the target.
	var grip_limit := config.tire_grip * 9.81 / maxf(forward_speed, 1.0) * 1.15
	desired = clampf(desired, -grip_limit, grip_limit)
	if absf(yaw_rate) > absf(desired) + 0.05:
		var err := yaw_rate - desired
		apply_torque(up * (-err * assists.stability * inertia.y * 2.5))
		stability_active = true


## Small pitch/roll correction while airborne (rally jumps).
func _apply_air_control() -> void:
	if assists.air_control <= 0.0:
		return
	var up := global_basis.y
	var level := up.cross(Vector3.UP)
	var w := angular_velocity
	var spin := w - Vector3.UP * w.dot(Vector3.UP)
	var strength := assists.air_control * (inertia.x + inertia.z) * 0.5
	apply_torque((level * 4.0 - spin * 1.0) * strength)


## Returns true if the car was moved this tick.
func _handle_meta_inputs() -> bool:
	if input.cycle_profile_pressed:
		set_handling_profile((handling_profile + 1) % HandlingAssists.PROFILE_NAMES.size())
	if input.restart_pressed:
		reset_to_start()
		return true
	if input.recover_pressed:
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


func reset_to_start() -> void:
	teleport(spawn_transform)
	reset_to_start_done.emit()


func teleport(xform: Transform3D) -> void:
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_velocity = Vector3.ZERO
	steer_angle = 0.0
	for w in wheels:
		w.reset()
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
	_model.name = "Model"
	add_child(_model)
	var greybox := get_node_or_null("Greybox") as Node3D
	if greybox:
		greybox.visible = false
	for w in wheels:
		var key := String(w.name).trim_prefix("Wheel")
		var src := _model.find_child("wheel_" + key, true, false) as Node3D
		if src == null:
			push_warning("%s: model has no wheel_%s" % [name, key])
			continue
		if align_wheels_to_model:
			var hub := to_local(src.global_position)
			# Mount sits one static spring length above the hub.
			var corner_load := config.mass * 9.81 * 0.25
			var rate := config.front_spring_rate if w.is_front else config.rear_spring_rate
			w.position = Vector3(hub.x, hub.y + config.rest_length - corner_load / rate, hub.z)
		w.custom_visual = src
	_collect_retro_surfaces(_model)


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
			var retro := ShaderMaterial.new()
			retro.shader = PSX_SHADER
			var ps2: Material = null
			if original is BaseMaterial3D:
				var base := original as BaseMaterial3D
				retro.set_shader_parameter("albedo_tex", base.albedo_texture)
				retro.set_shader_parameter("albedo_color", base.albedo_color)
				# PS2 style: smooth (bilinear) textures and per-vertex lighting.
				var soft := base.duplicate() as BaseMaterial3D
				soft.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				soft.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
				soft.roughness = 0.55
				soft.metallic_specular = 0.6
				ps2 = soft
			_retro_surfaces.append([mi, i, original, retro, ps2])
	for child in node.get_children():
		_collect_retro_surfaces(child)


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
