class_name InputActions
extends RefCounted
## Registers the game's input actions (keyboard + gamepad) at startup.
## Actions already defined in Project Settings are left alone.


## Stick drift is usually below 0.1; triggers rest at 0.
const STICK_DEADZONE := 0.12
const TRIGGER_DEADZONE := 0.04


static func ensure() -> void:
	_add("throttle", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)], TRIGGER_DEADZONE)
	_add("brake", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)], TRIGGER_DEADZONE)
	_add("steer_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0), _button(JOY_BUTTON_DPAD_LEFT)], STICK_DEADZONE)
	_add("steer_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0), _button(JOY_BUTTON_DPAD_RIGHT)], STICK_DEADZONE)
	_add("handbrake", [_key(KEY_SPACE), _button(JOY_BUTTON_A)])
	_add("shift_up", [_key(KEY_E), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	_add("shift_down", [_key(KEY_Q), _button(JOY_BUTTON_LEFT_SHOULDER)])
	_add("toggle_transmission", [_key(KEY_M)])
	_add("recover", [_key(KEY_R), _button(JOY_BUTTON_Y)])
	_add("restart", [_key(KEY_BACKSPACE), _button(JOY_BUTTON_BACK)])
	_add("cycle_profile", [_key(KEY_P)])
	_add("cycle_camera", [_key(KEY_C), _button(JOY_BUTTON_X)])
	_add("toggle_telemetry", [_key(KEY_F1), _key(KEY_T)])
	_add("toggle_help", [_key(KEY_H)])
	_add("cycle_look", [_key(KEY_V)])
	_add("switch_track", [_key(KEY_F2)])
	_add("versus_mode", [_key(KEY_F3)])

	# Two-player split screen: each player has their own keys and gamepad.
	# Player 1 = left side of the keyboard + first gamepad.
	_add_player(1, 0, {
		"throttle": [KEY_W], "brake": [KEY_S], "steer_left": [KEY_A], "steer_right": [KEY_D],
		"handbrake": [KEY_SPACE], "shift_up": [KEY_E], "shift_down": [KEY_Q], "recover": [KEY_R],
		"cycle_camera": [KEY_C],
	})
	# Player 2 = arrow keys and the keys around them + second gamepad.
	_add_player(2, 1, {
		"throttle": [KEY_UP], "brake": [KEY_DOWN], "steer_left": [KEY_LEFT], "steer_right": [KEY_RIGHT],
		"handbrake": [KEY_SLASH, KEY_KP_0], "shift_up": [KEY_PERIOD], "shift_down": [KEY_COMMA],
		"recover": [KEY_ENTER, KEY_KP_ENTER], "cycle_camera": [KEY_APOSTROPHE],
	})


## Adds "p<player>_<action>" actions: the given keys plus that player's gamepad.
static func _add_player(player: int, device: int, keys: Dictionary) -> void:
	var pad := {
		"throttle": [_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0, device)],
		"brake": [_axis(JOY_AXIS_TRIGGER_LEFT, 1.0, device)],
		"steer_left": [_axis(JOY_AXIS_LEFT_X, -1.0, device), _button(JOY_BUTTON_DPAD_LEFT, device)],
		"steer_right": [_axis(JOY_AXIS_LEFT_X, 1.0, device), _button(JOY_BUTTON_DPAD_RIGHT, device)],
		"handbrake": [_button(JOY_BUTTON_A, device)],
		"shift_up": [_button(JOY_BUTTON_RIGHT_SHOULDER, device)],
		"shift_down": [_button(JOY_BUTTON_LEFT_SHOULDER, device)],
		"recover": [_button(JOY_BUTTON_Y, device)],
		"cycle_camera": [_button(JOY_BUTTON_X, device)],
	}
	for action: String in keys:
		var events: Array = []
		for code: Key in keys[action]:
			events.append(_key(code))
		events.append_array(pad.get(action, []))
		_add(StringName("p%d_%s" % [player, action]), events, _deadzone_for(action))


static func _deadzone_for(action: String) -> float:
	if action == "throttle" or action == "brake":
		return TRIGGER_DEADZONE
	if action.begins_with("steer"):
		return STICK_DEADZONE
	return 0.5


## `deadzone` applies to analog sticks/triggers; Godot rescales what is left
## to 0..1, so partial stick and trigger movement comes through smoothly.
static func _add(action: StringName, events: Array, deadzone: float = 0.5) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, deadzone)
	for e: InputEvent in events:
		InputMap.action_add_event(action, e)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _axis(axis: JoyAxis, value: float, device: int = -1) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	return e


static func _button(button: JoyButton, device: int = -1) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	return e
