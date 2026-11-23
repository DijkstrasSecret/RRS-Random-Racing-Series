class_name ChaseCamera
extends Camera3D
## "Balloon on a string" chase camera (design concept §11).
## The camera floats behind the car on springs: it trails a little when the
## car speeds up, drifts closer under braking, swings round slowly in slides
## and bobs gently, but never falls far behind at a steady speed.
## C cycles chase / far / hood view.
## View angle: behind, or looking 45 degrees left / right. Z / X (player 2:
## numpad 4 / 6) or the right stick left / right; the camera swings round
## gently to the opposite rear corner, so you look the way you pushed. Right stick forward or B (player 2: numpad 8) cuts to a
## separate look-back camera ahead of the car, looking back over it, while
## held; the normal camera stays where it is.

enum Mode { CHASE, FAR, HOOD }

@export var target_path: NodePath
## Input action that switches view (split screen gives each player their own).
@export var cycle_action: StringName = &"cycle_camera"
@export var distance: float = 7.8
@export var height: float = 3.6
@export var look_height: float = 1.0
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

## How quickly the camera swings to a new view angle (lower = gentler).
@export var angle_swing_speed: float = 2.6

const VIEW_NAMES: PackedStringArray = ["LOOK LEFT", "BEHIND", "LOOK RIGHT"]
const LOOK_BACK := 2

var mode: int = Mode.CHASE
## Chosen view angle: -1 look left, 0 behind, 1 look right (45 degree steps;
## the camera sits on the opposite rear corner).
var view_angle: int = 0
## Seconds since the view angle last changed (the HUD shows its name).
var view_changed_ago: float = 99.0
var _angle_now: float = 0.0
var _shown_angle: int = 0
var _prefix: String = ""
var _target: RigidBody3D
var _yaw_dir: Vector3 = Vector3.FORWARD
var _velocity: Vector3 = Vector3.ZERO
var _look_point: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _back_cam: Camera3D
var _looking_back := false


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	doppler_tracking = Camera3D.DOPPLER_TRACKING_IDLE_STEP
	_target = get_node_or_null(target_path) as RigidBody3D
	fov = base_fov
	add_to_group("chase_cameras")
	# Split screen: "p1_cycle_camera" -> player 1's keys and gamepad.
	var action := String(cycle_action)
	if action.begins_with("p1_") or action.begins_with("p2_"):
		_prefix = action.substr(0, 3)
	_back_cam = Camera3D.new()
	_back_cam.name = "LookBackCamera"
	_back_cam.top_level = true
	_back_cam.fov = 70.0
	_back_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_back_cam)
	snap()


## True while the look-back camera is showing.
func is_looking_back() -> bool:
	return _looking_back


## The car this camera follows.
func target() -> RigidBody3D:
	return _target


## Name of the view currently shown (held stick or chosen angle).
func view_name() -> String:
	return "LOOKING BACK" if _shown_angle == LOOK_BACK else VIEW_NAMES[_shown_angle + 1]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(cycle_action):
		mode = (mode + 1) % Mode.size()
		snap()
	elif event.is_action_pressed(StringName(_prefix + "camera_left")):
		view_angle = maxi(view_angle - 1, -1)
	elif event.is_action_pressed(StringName(_prefix + "camera_right")):
		view_angle = mini(view_angle + 1, 1)


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
	_update_view_angle(delta)
	_update_look_back(xf)

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

	# Behind the car it aims a little ahead; from the sides / front it aims at the car.
	var side_view := clampf(absf(_angle_now) / (PI * 0.25), 0.0, 1.0)
	var look_target := xf.origin + Vector3.UP * look_height + _yaw_dir * look_ahead_distance * (1.0 - 0.5 * side_view)
	_look_point = _look_point.lerp(look_target, 1.0 - exp(-10.0 * delta))
	look_at(_look_point, Vector3.UP)

	var speed_frac := clampf(car_vel.length() / fov_full_speed, 0.0, 1.0)
	fov = lerpf(fov, lerpf(base_fov, max_fov, speed_frac), 1.0 - exp(-2.5 * delta))


func _anchor(xf: Transform3D) -> Vector3:
	var far_view := mode == Mode.FAR
	var dist := distance * (1.45 if far_view else 1.0)
	var lift := height * (1.4 if far_view else 1.0)
	var bob := sin(_time * 2.4) * hover_amplitude
	var away := (-_yaw_dir).rotated(Vector3.UP, _angle_now)
	return xf.origin + away * dist + Vector3.UP * (lift + bob)


## Picks the view (right stick held, else the chosen angle) and swings the
## normal camera gently towards it. Stick forward / B = look back.
func _update_view_angle(delta: float) -> void:
	var wanted := view_angle
	var stick := Vector2(Input.get_axis(StringName(_prefix + "look_left"), StringName(_prefix + "look_right")),
			Input.get_axis(StringName(_prefix + "look_up"), StringName(_prefix + "look_down")))
	var back := Input.is_action_pressed(StringName(_prefix + "look_back"))
	if stick.y < -0.55 and absf(stick.y) >= absf(stick.x):
		back = true
	elif absf(stick.x) > 0.55 and absf(stick.x) > absf(stick.y):
		wanted = 1 if stick.x > 0.0 else -1
	var shown := LOOK_BACK if back else wanted
	if shown != _shown_angle:
		_shown_angle = shown
		view_changed_ago = 0.0
	view_changed_ago += delta
	_looking_back = back
	# Looking right = camera swung round to the rear left (and vice versa).
	var goal := -wanted * PI * 0.25
	_angle_now += (goal - _angle_now) * (1.0 - exp(-angle_swing_speed * delta))


## The look-back camera: ahead of the car, looking back over it at whoever is
## behind. Only current while looking back.
func _update_look_back(xf: Transform3D) -> void:
	if _back_cam == null:
		return
	if _looking_back:
		var fwd := _flat_forward(xf)
		_back_cam.global_position = xf.origin + fwd * 6.2 + Vector3.UP * 2.1
		_back_cam.look_at(xf.origin + Vector3.UP * 0.8 - fwd * 4.0, Vector3.UP)
		if not _back_cam.current:
			_back_cam.make_current()
	elif _back_cam.current:
		make_current()



func _flat_forward(xf: Transform3D) -> Vector3:
	var f := -xf.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD
