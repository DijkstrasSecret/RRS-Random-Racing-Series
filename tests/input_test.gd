extends SceneTree
## Checks the controls:
## - split-screen keys are separate (W only drives player 1, Up only player 2)
## - gamepads are separate (pad 0 = player 1, pad 1 = player 2)
## - partial stick and trigger movement gives partial steering / throttle
## Run: Godot_console.exe --headless --path . -s res://tests/input_test.gd

var _solo: PlayerInput
var _p1: PlayerInput
var _p2: PlayerInput
var _ok := true


func _init() -> void:
	InputActions.ensure()
	_solo = PlayerInput.new()
	_p1 = PlayerInput.new()
	_p1.action_prefix = "p1_"
	_p2 = PlayerInput.new()
	_p2.action_prefix = "p2_"
	for pi in [_solo, _p1, _p2]:
		root.add_child(pi)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	# Keyboard
	await _check_key(KEY_W, "W", true)
	await _check_key(KEY_UP, "Up arrow", false)
	# Gamepad: half stick right on pad 0, then on pad 1.
	for device in [0, 1]:
		await _send_axis(device, JOY_AXIS_LEFT_X, 0.5)
		var p1s := _p1.steer
		var p2s := _p2.steer
		print("  pad %d stick 50%%  -> solo %.2f   p1 %.2f   p2 %.2f   (gamepad mode p1 %s p2 %s)" % [
			device, _solo.steer, p1s, p2s, _p1.using_gamepad, _p2.using_gamepad])
		var mine := p1s if device == 0 else p2s
		var other := p2s if device == 0 else p1s
		if mine < 0.15 or mine > 0.5 or absf(other) > 0.01:
			_ok = false
		await _send_axis(device, JOY_AXIS_LEFT_X, 0.0)
	# Gamepad: light and full trigger on pad 0.
	for amount in [0.3, 1.0]:
		await _send_axis(0, JOY_AXIS_TRIGGER_RIGHT, amount)
		print("  pad 0 trigger %d%% -> p1 throttle %.2f" % [int(amount * 100), _p1.throttle])
		if absf(_p1.throttle - (amount - 0.04) / 0.96) > 0.05:
			_ok = false
	await _send_axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	print("input_test %s" % ("PASSED" if _ok else "FAILED"))
	quit()


func _check_key(code: Key, label: String, is_p1: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await _settle()
	print("  %-9s -> solo %.2f   p1 %.2f   p2 %.2f" % [label, _solo.throttle, _p1.throttle, _p2.throttle])
	if (_p1.throttle > 0.5) != is_p1 or (_p2.throttle > 0.5) == is_p1 or _solo.throttle < 0.5:
		_ok = false
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await _settle()


func _send_axis(device: int, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	await _settle()


## Let the input arrive and the smoothing settle.
func _settle() -> void:
	Input.flush_buffered_events()
	await process_frame
	for i in 40:
		for pi: PlayerInput in [_solo, _p1, _p2]:
			pi.poll(1.0 / 60.0)
