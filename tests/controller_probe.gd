extends SceneTree
## Controller check: shows every connected gamepad, what it sends, and what
## the game's actions read. Also logs to user://controller_log.txt.
##   Godot.exe --path . -s res://tests/controller_probe.gd
## Closes by itself after 5 minutes (or close the window).

var _label: Label
var _log: FileAccess
var _t := 0.0
var _events: PackedStringArray = []


func _init() -> void:
	InputActions.ensure()
	_log = FileAccess.open("user://controller_log.txt", FileAccess.WRITE)
	root.title = "RRS controller test"
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	_label = Label.new()
	_label.position = Vector2(40, 30)
	_label.add_theme_font_size_override("font_size", 22)
	root.add_child(_label)
	_write("joypads at start: %s" % str(Input.get_connected_joypads()))
	for d in Input.get_connected_joypads():
		_write("  device %d: %s %s" % [d, Input.get_joy_name(d), str(Input.get_joy_info(d))])
	var watcher := Watcher.new()
	watcher.probe = self
	root.add_child.call_deferred(watcher)
	Input.joy_connection_changed.connect(func(d: int, on: bool) -> void:
		_write("connection changed: device %d %s" % [d, "connected" if on else "disconnected"]))


func _write(line: String) -> void:
	print(line)
	_log.store_line("%.2f  %s" % [_t, line])
	_log.flush()


class Watcher extends Node:
	var probe
	func _input(event: InputEvent) -> void:
		probe.on_event(event)


func on_event(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		var line := event.as_text()
		_events.append(line)
		if _events.size() > 12:
			_events.remove_at(0)
		_write("event: " + line)


func _process(delta: float) -> bool:
	_t += delta
	var lines := PackedStringArray(["RRS CONTROLLER TEST  -  press buttons, move sticks, pull triggers on each pad", "",
		"window focused: %s" % str(DisplayServer.window_is_focused()), "connected: %s" % str(Input.get_connected_joypads()), ""])
	for d in Input.get_connected_joypads():
		lines.append("pad %d  %s   LX %+.2f  LY %+.2f  LT %.2f  RT %.2f   A %s  B %s" % [d, Input.get_joy_name(d),
			Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y),
			Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT), Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT),
			str(Input.is_joy_button_pressed(d, JOY_BUTTON_A)), str(Input.is_joy_button_pressed(d, JOY_BUTTON_B))])
	lines.append("")
	lines.append("game actions:  throttle %.2f  brake %.2f  steer %+.2f  |  p1 throttle %.2f  p2 throttle %.2f  |  ui_accept %s" % [
		Input.get_action_strength("throttle"), Input.get_action_strength("brake"),
		Input.get_axis("steer_left", "steer_right"), Input.get_action_strength("p1_throttle"),
		Input.get_action_strength("p2_throttle"), str(Input.is_action_pressed("ui_accept"))])
	lines.append("")
	lines.append("last events:")
	lines.append_array(_events)
	_label.text = "\n".join(lines)
	if fmod(_t, 2.0) < delta:
		for d in Input.get_connected_joypads():
			_log.store_line("%.2f  poll pad %d LX %+.2f RT %.2f A %s focused %s" % [_t, d, Input.get_joy_axis(d, JOY_AXIS_LEFT_X),
				Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT), str(Input.is_joy_button_pressed(d, JOY_BUTTON_A)),
				str(DisplayServer.window_is_focused())])
		_log.flush()
	if _t > 300.0:
		quit()
	return false
