class_name ChaseCamera
extends Camera3D
## Chase camera (design concept §11): follows the car with a lagging yaw so
## slides read clearly, looks a little toward the direction of travel and
## widens its field of view with speed. C cycles chase / far / hood view.

enum Mode { CHASE, FAR, HOOD }

@export var target_path: NodePath
@export var distance: float = 5.6
@export var height: float = 2.0
@export var look_height: float = 1.0
## Higher = the camera swings round behind the car faster.
@export var yaw_follow: float = 5.0
## 0 = look where the car points, 1 = look where it is travelling.
@export var look_ahead: float = 0.3
@export var base_fov: float = 68.0
@export var max_fov: float = 84.0
@export var fov_full_speed: float = 55.0

var mode: int = Mode.CHASE
var _target: RigidBody3D
var _yaw_dir: Vector3 = Vector3.FORWARD


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_target = get_node_or_null(target_path) as RigidBody3D
	fov = base_fov
	if _target:
		_yaw_dir = _flat_forward(_target.global_transform)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_camera"):
		mode = (mode + 1) % Mode.size()


func _process(delta: float) -> void:
	if _target == null:
		return
	var xf := _target.get_global_transform_interpolated()

	if mode == Mode.HOOD:
		global_transform = Transform3D(xf.basis, xf * Vector3(0.0, 1.25, -0.3))
		fov = base_fov
		return

	var fwd := _flat_forward(xf)
	var desired := fwd
	var vel := _target.linear_velocity
	vel.y = 0.0
	if vel.length() > 3.0 and vel.dot(fwd) > 0.0:
		desired = fwd.lerp(vel.normalized(), look_ahead).normalized()
	_yaw_dir = _yaw_dir.lerp(desired, 1.0 - exp(-yaw_follow * delta)).normalized()

	var dist := distance * (1.6 if mode == Mode.FAR else 1.0)
	var lift := height * (1.4 if mode == Mode.FAR else 1.0)
	var pivot := xf.origin + Vector3.UP * look_height
	global_position = pivot - _yaw_dir * dist + Vector3.UP * (lift - look_height)
	look_at(pivot + _yaw_dir * 3.0, Vector3.UP)

	var speed_frac := clampf(_target.linear_velocity.length() / fov_full_speed, 0.0, 1.0)
	fov = lerpf(fov, lerpf(base_fov, max_fov, speed_frac), 1.0 - exp(-3.0 * delta))


func _flat_forward(xf: Transform3D) -> Vector3:
	var f := -xf.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD
