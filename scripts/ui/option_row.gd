class_name OptionRow
extends Button
## A menu row with a value you can change: "LAPS ............ <  3  >".
## Left/right (keys, D-pad, stick) or clicking cycles through the choices.
## The title is the button text; the value is drawn right-aligned.

## Emitted with the new choice index after the player changes it.
signal value_changed(index: int)

var choices: PackedStringArray = []
var index: int = 0


## A row titled row_title that cycles through row_choices, starting at start_index.
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


## Moves to the next (direction +1) or previous (-1) choice, wrapping round, and emits value_changed.
func step(direction: int) -> void:
	index = wrapi(index + direction, 0, choices.size())
	queue_redraw()
	value_changed.emit(index)


func _draw() -> void:
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var focused := has_focus()
	# The value fits between the title and the right edge (long car names
	# are shortened with "..." instead of running off the row).
	var title_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 60.0
	var arrow_w := font.get_string_size("<", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var room := size.x - title_w - 22.0 - (arrow_w + 26.0) * 2.0
	var value := _fit(choices[index], font, font_size, room)
	var vw := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var y := (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var right := size.x - 22.0
	var arrow_col := Color(MenuStyle.ACCENT, 0.9) if focused else Color(1, 1, 1, 0.35)
	var value_col := MenuStyle.ACCENT if focused else MenuStyle.TEXT
	var x_right_arrow := right - arrow_w
	var x_value := x_right_arrow - 20.0 - vw
	var x_left_arrow := x_value - 20.0 - arrow_w
	for part: Array in [[x_left_arrow, "<", arrow_col], [x_value, value, value_col], [x_right_arrow, ">", arrow_col]]:
		var pos := Vector2(part[0], y)
		draw_string_outline(font, pos, part[1], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.8))
		draw_string(font, pos, part[1], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, part[2])


static func _fit(s: String, font: Font, font_size: int, room: float) -> String:
	if room <= 0.0 or font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= room:
		return s
	var cut := s
	while cut.length() > 1 and font.get_string_size(cut + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > room:
		cut = cut.substr(0, cut.length() - 1)
	return cut.strip_edges() + "..."
