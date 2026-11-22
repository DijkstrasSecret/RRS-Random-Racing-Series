class_name PlayerInput
extends VehicleInput
## Keyboard / gamepad driver. Keyboard keys are on/off, so steering and
## pedals are ramped to feel smooth.

@export var steer_speed: float = 4.5
@export var steer_return_speed: float = 6.0
@export var pedal_speed: float = 7.0
## "" = all keys and pads (single player); "p1_" / "p2_" = that player's keys
## and gamepad only (split screen).
@export var action_prefix: String = ""


func _ready() -> void:
	InputActions.ensure()


func poll(delta: float) -> void:
	throttle = move_toward(throttle, Input.get_action_strength(_a("throttle")), pedal_speed * delta)
	brake = move_toward(brake, Input.get_action_strength(_a("brake")), pedal_speed * delta)

	var target := Input.get_axis(_a("steer_left"), _a("steer_right"))
	var rate := steer_speed
	if absf(target) < absf(steer) or signf(target) != signf(steer):
		rate = steer_return_speed
	steer = move_toward(steer, target, rate * delta)

	handbrake = 1.0 if Input.is_action_pressed(_a("handbrake")) else 0.0
	shift_up_pressed = Input.is_action_just_pressed(_a("shift_up"))
	shift_down_pressed = Input.is_action_just_pressed(_a("shift_down"))
	recover_pressed = Input.is_action_just_pressed(_a("recover"))
	# Game-wide keys only for a single player (in split screen the race
	# director owns restart, and P / M would affect both cars).
	var solo := action_prefix.is_empty()
	toggle_transmission_pressed = solo and Input.is_action_just_pressed("toggle_transmission")
	restart_pressed = solo and Input.is_action_just_pressed("restart")
	cycle_profile_pressed = solo and Input.is_action_just_pressed("cycle_profile")


func _a(action: String) -> StringName:
	return StringName(action_prefix + action)
