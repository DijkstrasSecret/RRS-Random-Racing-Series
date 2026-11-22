class_name OptionRow
extends Button
## A menu row with a value you can change: "LAPS ............ <  3  >".
## Left/right (keys, D-pad, stick) or clicking cycles through the choices.
## The title is the button text; the value is drawn right-aligned.

signal value_changed(index: int)

var choices: PackedStringArray = []
var index: int = 0


static func create(row_title: String, row_choices: PackedStringArray, start_index: int) -> OptionRow:
	var row := OptionRow.new()
	row.text = row_title
	row.choices = row_choices
	row.index = clampi(start_index, 0, row_choices.size() - 1)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.custom_minimum_size = Vector2(560, 0)
	row.focus_mode = Control.FOCUS_ALL
	row.mouse_entered.connect(row.grab_focus)
	return row


func _ready() -> void:
	pressed.connect(func() -> void: step(1))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		step(1)
		accept_event()


func step(direction: int) -> void:
	index = wrapi(index + direction, 0, choices.size())
	queue_redraw()
	value_changed.emit(index)


func _draw() -> void:
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var value := "<   %s   >" % choices[index]
	var w := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var y := (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var pos := Vector2(size.x - w - 22.0, y)
	var color := MenuStyle.ACCENT if has_focus() else MenuStyle.TEXT
	draw_string_outline(font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.8))
	draw_string(font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
