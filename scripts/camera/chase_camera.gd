class_name ChaseCamera
extends Camera3D
## "Balloon on a string" chase camera (design concept §11).
## The camera floats behind the car on springs: it trails a little when the
## car speeds up, drifts closer under braking, swings round slowly in slides
## and bobs gently, but never falls far behind at a steady speed.
## C cycles chase / far / hood view.

enum Mode { CHASE, FAR, HOOD }

@export var target_path: NodePath
## Input action that switches view (split screen gives each player their own).
@export var cycle_action: StringName = &"cycle_camera"
@export var distance: float = 7.8
@export var height: float = 3.0
@export var look_height: float = 0.9
## How far ahead of the car the camera aims, in metres.
@export var look_ahead_distance: float = 4.0
## Spring stiffness of the string (higher = tighter).
@export var stiffness: float = 9.0
## 1 = no overshoot, lower = more floaty bounce.
@export var damping_ratio: float = 0.7
## Vertical spring is softer so bumps and jumps read as a gentle bob.
@export var vertical_stiffness: float = 5.0
## How fast the camera swings round behind the car (lower = lazier).
@export var yaw_follow: float = 2.6
## 0 = stay behind where the car points, 1 = behind where it travels.
@export var velocity_bias: float = 0.35
@export var hover_amplitude: float = 0.05
@export var base_fov: float = 66.0
@export var max_fov: float = 80.0
@export var fov_full_speed: float = 60.0

var mode: int = Mode.CHASE
var _target: RigidBody3D
var _yaw_dir: Vector3 = Vector3.FORWARD
var _velocity: Vector3 = Vector3.ZERO
var _look_point: Vector3 = Vector3.ZERO
var _time: float = 0.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_target = get_node_or_null(target_path) as RigidBody3D
	fov = base_fov
	snap()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(cycle_action):
		mode = (mode + 1) % Mode.size()
		snap()


## Follow a different car.
func set_target(target: RigidBody3D) -> void:
	_target = target
	snap()


## Jump straight to the resting position (after a reset or teleport).
func snap() -> void:
	if _target == null:
		return
	var xf := _target.global_transform
	_yaw_dir = _flat_forward(xf)
	global_position = _anchor(xf)
	_velocity = _target.linear_velocity
	_look_point = xf.origin + Vector3.UP * look_height + _yaw_dir * look_ahead_distance
	look_at(_look_point, Vector3.UP)


func _process(delta: float) -> void:
	if _target == null:
		return
	delta = minf(delta, 0.05)
	_time += delta
	var xf := _target.get_global_transform_interpolated()

	if mode == Mode.HOOD:
		global_transform = Transform3D(xf.basis, xf * Vector3(0.0, 1.2, -0.3))
		fov = base_fov
		return

	# Swing lazily toward "behind the car", leaning toward the travel direction.
	var fwd := _flat_forward(xf)
	var desired := fwd
	var car_vel := _target.linear_velocity
	var flat_vel := Vector3(car_vel.x, 0.0, car_vel.z)
	if flat_vel.length() > 4.0 and flat_vel.dot(fwd) > 0.0:
		desired = fwd.lerp(flat_vel.normalized(), velocity_bias).normalized()
	_yaw_dir = _yaw_dir.slerp(desired, 1.0 - exp(-yaw_follow * delta)).normalized()

	var anchor := _anchor(xf)
	if global_position.distance_to(anchor) > 40.0:
		snap()
		return

	# Spring-damper toward the anchor, matching the car's velocity so the
	# camera only lags when the car speeds up, brakes or turns.
	var c := 2.0 * damping_ratio * sqrt(stiffness)
	var cv := 2.0 * damping_ratio * sqrt(vertical_stiffness)
	var err := anchor - global_position
	var vel_err := car_vel - _velocity
	var accel := Vector3(
		err.x * stiffness + vel_err.x * c,
		err.y * vertical_stiffness + vel_err.y * cv,
		err.z * stiffness + vel_err.z * c)
	_velocity += accel * delta
	global_position += _velocity * delta
	# Never sink below the car's roof line.
	global_position.y = maxf(global_position.y, xf.origin.y + 1.2)

	var look_target := xf.origin + Vector3.UP * look_height + _yaw_dir * look_ahead_distance
	_look_point = _look_point.lerp(look_target, 1.0 - exp(-10.0 * delta))
	look_at(_look_point, Vector3.UP)

	var speed_frac := clampf(car_vel.length() / fov_full_speed, 0.0, 1.0)
	fov = lerpf(fov, lerpf(base_fov, max_fov, speed_frac), 1.0 - exp(-2.5 * delta))


func _anchor(xf: Transform3D) -> Vector3:
	var far_view := mode == Mode.FAR
	var dist := distance * (1.45 if far_view else 1.0)
	var lift := height * (1.4 if far_view else 1.0)
	var bob := sin(_time * 2.4) * hover_amplitude
	return xf.origin - _yaw_dir * dist + Vector3.UP * (lift + bob)


func _flat_forward(xf: Transform3D) -> Vector3:
	var f := -xf.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD
