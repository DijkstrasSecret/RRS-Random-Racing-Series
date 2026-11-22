class_name InputActions
extends RefCounted
## Registers the game's input actions (keyboard + gamepad) at startup.
## Actions already defined in Project Settings are left alone.


static func ensure() -> void:
	_add("throttle", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_add("brake", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_add("steer_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_add("steer_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
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


static func _add(action: StringName, events: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.15)
	for e: InputEvent in events:
		InputMap.action_add_event(action, e)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


static func _button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e
