extends SceneTree
## Checks the split-screen controls are separate: W only drives player 1,
## the Up arrow only drives player 2, and single-player input sees both.
## Run: Godot_console.exe --headless --path . -s res://tests/input_test.gd

func _init() -> void:
	InputActions.ensure()
	var solo := PlayerInput.new()
	var p1 := PlayerInput.new()
	p1.action_prefix = "p1_"
	var p2 := PlayerInput.new()
	p2.action_prefix = "p2_"
	var ok := true
	for case: Array in [[KEY_W, "W"], [KEY_UP, "Up arrow"]]:
		var down := InputEventKey.new()
		down.physical_keycode = case[0]
		down.pressed = true
		Input.parse_input_event(down)
		Input.flush_buffered_events()
		for i in 30:
			for pi: PlayerInput in [solo, p1, p2]:
				pi.poll(1.0 / 60.0)
		print("  %-9s -> solo %.2f   p1 %.2f   p2 %.2f" % [case[1], solo.throttle, p1.throttle, p2.throttle])
		var want_p1: bool = case[0] == KEY_W
		if (p1.throttle > 0.5) != want_p1 or (p2.throttle > 0.5) == want_p1 or solo.throttle < 0.5:
			ok = false
		var up := down.duplicate() as InputEventKey
		up.pressed = false
		Input.parse_input_event(up)
		Input.flush_buffered_events()
		for i in 30:
			for pi: PlayerInput in [solo, p1, p2]:
				pi.poll(1.0 / 60.0)
	print("input_test %s" % ("PASSED" if ok else "FAILED"))
	for pi in [solo, p1, p2]:
		pi.free()
	quit()
