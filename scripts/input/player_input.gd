class_name PlayerInput
extends VehicleInput
## Keyboard / gamepad driver.
## - Keyboard keys are on/off, so steering and pedals are ramped to feel smooth.
## - A gamepad is analog: the stick steers directly through a response curve
##   (small movements = fine corrections, full tilt = full lock) and the
##   triggers give partial throttle and brake. The pad also rumbles on
##   wheelspin/slides, grass and hard landings.
## Whichever device was used last is the one being read.

@export_group("Keyboard")
@export var steer_speed: float = 4.5
@export var steer_return_speed: float = 6.0
@export var pedal_speed: float = 7.0

@export_group("Gamepad")
## Stick response: 1 = linear, higher = finer control near the centre.
@export_range(1.0, 3.0) var steer_curve: float = 1.6
## How quickly the wheels follow the stick (per second). High = direct.
@export var pad_steer_speed: float = 14.0
@export var pad_pedal_speed: float = 18.0
@export var rumble_enabled: bool = true
@export_group("")

## "" = all keys and pads (single player); "p1_" / "p2_" = that player's keys
## and gamepad only (split screen).
@export var action_prefix: String = ""

## True while the last input came from a gamepad.
var using_gamepad: bool = false
var _pad_device: int = 0
var _rumble_timer: float = 0.0
var _was_airborne: bool = false
var _landing_kick: float = 0.0


func _ready() -> void:
	InputActions.ensure()
	if action_prefix == "p2_":
		_pad_device = 1


func _input(event: InputEvent) -> void:
	# Work out which device this player is using right now.
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		if not _owns_device(event.device):
			return
		var moved := event is InputEventJoypadButton or absf((event as InputEventJoypadMotion).axis_value) > 0.25
		if moved:
			using_gamepad = true
			_pad_device = event.device
	elif event is InputEventKey and event.pressed and _is_my_key(event):
		using_gamepad = false
		Input.stop_joy_vibration(_pad_device)


func poll(delta: float) -> void:
	var raw_steer := Input.get_axis(_a("steer_left"), _a("steer_right"))
	var raw_throttle := Input.get_action_strength(_a("throttle"))
	var raw_brake := Input.get_action_strength(_a("brake"))
	if using_gamepad:
		# Analog: curve the stick, follow it quickly, triggers pass straight through.
		var target := signf(raw_steer) * pow(absf(raw_steer), steer_curve)
		steer = move_toward(steer, target, pad_steer_speed * delta)
		throttle = move_toward(throttle, raw_throttle, pad_pedal_speed * delta)
		brake = move_toward(brake, raw_brake, pad_pedal_speed * delta)
	else:
		throttle = move_toward(throttle, raw_throttle, pedal_speed * delta)
		brake = move_toward(brake, raw_brake, pedal_speed * delta)
		var rate := steer_speed
		if absf(raw_steer) < absf(steer) or signf(raw_steer) != signf(steer):
			rate = steer_return_speed
		steer = move_toward(steer, raw_steer, rate * delta)

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

	_update_rumble(delta)


## Weak (high-frequency) motor = tyres sliding or spinning.
## Strong (low-frequency) motor = grass and landing impacts.
func _update_rumble(delta: float) -> void:
	if not rumble_enabled or not GameSettings.vibration or not using_gamepad:
		return
	var car := get_parent() as Vehicle
	if car == null:
		return
	var slide := 0.0
	for w in car.wheels:
		if w.grounded:
			slide = maxf(slide, clampf((w.grip_usage - 0.95) * 4.0, 0.0, 1.0) * clampf(absf(w.v_long) / 10.0, 0.0, 1.0))
	if _was_airborne and not car.airborne:
		_landing_kick = 0.25
	_was_airborne = car.airborne
	_landing_kick = maxf(_landing_kick - delta, 0.0)
	var speed_factor := clampf(absf(car.forward_speed) / 15.0, 0.0, 1.0)
	var weak := slide * 0.6
	var strong := (0.35 * speed_factor if car.off_track else 0.0) + (0.8 if _landing_kick > 0.0 else 0.0)
	_rumble_timer -= delta
	if weak < 0.03 and strong < 0.03:
		if _rumble_timer > -0.5:
			Input.stop_joy_vibration(_pad_device)
			_rumble_timer = -1.0
		return
	if _rumble_timer <= 0.0:
		Input.start_joy_vibration(_pad_device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), 0.15)
		_rumble_timer = 0.1


func _owns_device(device: int) -> bool:
	match action_prefix:
		"p1_": return device == 0
		"p2_": return device == 1
	return true


func _is_my_key(event: InputEvent) -> bool:
	for action: String in ["throttle", "brake", "steer_left", "steer_right", "handbrake"]:
		if event.is_action(_a(action)):
			return true
	return false


func _a(action: String) -> StringName:
	return StringName(action_prefix + action)
