class_name TierToggleRow
extends Button
## "AI CAR CLASSES      [D] [C] [B] [A]": left / right picks a class, Enter /
## A (or a click) switches it on or off. At least one class stays on.

## Emitted with the new class mask (bit 0 = D … bit 3 = A) after a class is switched.
signal mask_changed(mask: int)

const CHIP := Vector2(58, 36)
const CHIP_GAP := 12.0

var mask: int = 15
var cursor: int = 0


## A row of class chips D–A; start_mask uses bit 0 = D … bit 3 = A (0 means all on).
static func create(row_title: String, start_mask: int) -> TierToggleRow:
	var row := TierToggleRow.new()
	row.text = row_title
	row.mask = start_mask if start_mask & 15 else 15
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.custom_minimum_size = Vector2(760, 44)
	row.focus_mode = Control.FOCUS_ALL
	row.mouse_entered.connect(row.grab_focus)
	return row


func _ready() -> void:
	pressed.connect(func() -> void: toggle(cursor))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left", true):
		cursor = wrapi(cursor - 1, 0, 4)
		queue_redraw()
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		cursor = wrapi(cursor + 1, 0, 4)
		queue_redraw()
		accept_event()
	var mm := event as InputEventMouseMotion
	if mm:
		for i in 4:
			if _chip_rect(i).grow(6.0).has_point(mm.position) and cursor != i:
				cursor = i
				queue_redraw()


## Switches class i (0 = D … 3 = A) on or off; refuses to switch off the last one.
func toggle(i: int) -> void:
	var m := mask ^ (1 << i)
	if m & 15 == 0:
		return  # keep at least one class
	mask = m
	queue_redraw()
	mask_changed.emit(mask)


func _chip_rect(i: int) -> Rect2:
	var right := size.x - 22.0
	var x := right - (4 - i) * (CHIP.x + CHIP_GAP) + CHIP_GAP
	return Rect2(Vector2(x, (size.y - CHIP.y) * 0.5), CHIP)


func _draw() -> void:
	var font := get_theme_font("font")
	for i in 4:
		var r := _chip_rect(i)
		var on := mask & (1 << i) != 0
		var col: Color = CarRoster.TIER_COLORS[i]
		if on:
			draw_rect(r, col)
		else:
			draw_rect(r, Color(0, 0, 0, 0.45))
			draw_rect(r, Color(col, 0.6), false, 2.0)
		var letter: String = CarRoster.TIER_NAMES[i]
		var tw := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(font, Vector2(r.get_center().x - tw * 0.5, r.position.y + 27), letter,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 24, MenuStyle.DARK if on else Color(1, 1, 1, 0.5))
		if has_focus() and i == cursor:
			draw_rect(r.grow(5.0), MenuStyle.ACCENT, false, 3.0)
