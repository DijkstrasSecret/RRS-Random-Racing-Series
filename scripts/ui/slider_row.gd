class_name SliderRow
extends Button
## A menu row with a value on a slider: "FIELD OF VIEW ..... [=====----] 64°".
## Left / right (keys, D-pad, stick; hold to keep going) or the mouse on the
## bar change it in steps. The title is the button text.

signal value_changed(value: float)

var min_value := 0.0
var max_value := 100.0
var step_size := 5.0
var value := 50.0
## How the value is shown, e.g. "%d%%" or "%d°".
var format := "%d"

const BAR_W := 240.0


static func create(row_title: String, from: float, to: float, step_by: float, start: float, fmt: String) -> SliderRow:
	var row := SliderRow.new()
	row.text = row_title
	row.min_value = from
	row.max_value = to
	row.step_size = step_by
	row.value = clampf(start, from, to)
	row.format = fmt
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.custom_minimum_size = Vector2(560, 0)
	row.focus_mode = Control.FOCUS_ALL
	row.mouse_entered.connect(row.grab_focus)
	return row


func _ready() -> void:
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left", true):
		set_value(value - step_size)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		set_value(value + step_size)
		accept_event()
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_value_from_mouse(mb.position.x)
		accept_event()
	var mm := event as InputEventMouseMotion
	if mm and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_value_from_mouse(mm.position.x)
		accept_event()


func set_value(v: float) -> void:
	v = clampf(snappedf(v - min_value, step_size) + min_value, min_value, max_value)
	if is_equal_approx(v, value):
		return
	value = v
	queue_redraw()
	value_changed.emit(value)


func _bar_rect() -> Rect2:
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var label_w := font.get_string_size(format % (max_value + step_size), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 30.0
	var title_end := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 40.0
	var right := size.x - 22.0 - label_w
	var left := maxf(right - BAR_W, title_end)
	return Rect2(Vector2(left, size.y * 0.5 - 6.0), Vector2(maxf(right - left, 60.0), 12.0))


func _value_from_mouse(x: float) -> void:
	var bar := _bar_rect()
	var t := clampf((x - bar.position.x) / bar.size.x, 0.0, 1.0)
	set_value(lerpf(min_value, max_value, t))


func _draw() -> void:
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var focused := has_focus()
	var bar := _bar_rect()
	var t := (value - min_value) / maxf(max_value - min_value, 0.001)
	draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.6))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), MenuStyle.ACCENT if focused else MenuStyle.TEXT)
	var knob := Vector2(bar.position.x + bar.size.x * t, bar.get_center().y)
	draw_circle(knob, 9.0 if focused else 7.0, MenuStyle.ACCENT if focused else MenuStyle.TEXT)
	var label := format % value
	var y := (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var pos := Vector2(bar.end.x + 18.0, y)
	var color := MenuStyle.ACCENT if focused else MenuStyle.TEXT
	draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.8))
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
