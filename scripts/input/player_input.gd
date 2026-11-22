class_name PlayerInput
extends VehicleInput
## Keyboard / gamepad driver. Keyboard keys are on/off, so steering and
## pedals are ramped to feel smooth.

@export var steer_speed: float = 4.5
@export var steer_return_speed: float = 6.0
@export var pedal_speed: float = 7.0


func _ready() -> void:
	InputActions.ensure()


func poll(delta: float) -> void:
	throttle = move_toward(throttle, Input.get_action_strength("throttle"), pedal_speed * delta)
	brake = move_toward(brake, Input.get_action_strength("brake"), pedal_speed * delta)

	var target := Input.get_axis("steer_left", "steer_right")
	var rate := steer_speed
	if absf(target) < absf(steer) or signf(target) != signf(steer):
		rate = steer_return_speed
	steer = move_toward(steer, target, rate * delta)

	handbrake = 1.0 if Input.is_action_pressed("handbrake") else 0.0
	shift_up_pressed = Input.is_action_just_pressed("shift_up")
	shift_down_pressed = Input.is_action_just_pressed("shift_down")
	toggle_transmission_pressed = Input.is_action_just_pressed("toggle_transmission")
	recover_pressed = Input.is_action_just_pressed("recover")
	restart_pressed = Input.is_action_just_pressed("restart")
	cycle_profile_pressed = Input.is_action_just_pressed("cycle_profile")
