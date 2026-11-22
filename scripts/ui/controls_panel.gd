class_name ControlsPanel
extends VBoxContainer
## "How to drive" page: keyboard and gamepad layouts side by side.

signal closed

## Plain (untyped) nested array: a typed Array[PackedStringArray] constant
## loads with empty rows in Godot 4.7.
const ROWS := [
	["", "KEYBOARD (P1 / P2)", "GAMEPAD"],
	["Throttle", "W  /  Up", "RT (analog)"],
	["Brake / reverse", "S  /  Down", "LT (analog)"],
	["Steer", "A D  /  Left Right", "Left stick or D-pad"],
	["Handbrake", "Space  /  ( / )", "A"],
	["Shift down / up", "Q E  /  , .", "LB / RB"],
	["Recover car", "R  /  Enter", "Y"],
	["Camera", "C  /  '", "X"],
	["Camera angle", "Z X  /  Num 4 6", "Right stick left / right"],
	["Look back", "B  /  Num 8", "Right stick forward"],
	["Pause menu", "Esc", "Start"],
	["Visual style", "V", ""],
	["Telemetry", "F1", ""],
]


func _ready() -> void:
	add_child(MenuStyle.label("CONTROLS", 40, MenuStyle.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 8)
	for r in ROWS.size():
		for c in 3:
			var header := r == 0 or c == 0
			grid.add_child(MenuStyle.label(str(ROWS[r][c]), 20, MenuStyle.ACCENT if header else MenuStyle.TEXT))
	add_child(grid)
	add_child(MenuStyle.label("Split screen: player 1 = left keys + gamepad 1, player 2 = right keys + gamepad 2.", 17, MenuStyle.DIM))
	var back := MenuStyle.button("BACK", func() -> void: closed.emit())
	add_child(back)


func focus_first() -> void:
	MenuStyle.focus_first(self)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
