class_name MenuStyle
extends RefCounted
## Shared look for the menus: clean text over the scene, no boxes. The
## selected item turns yellow with a slim accent line on its left.
## Works with mouse, keyboard and gamepad (Godot's ui_* actions).

const ACCENT := Color(1.0, 0.78, 0.2)
const DARK := Color(0.05, 0.06, 0.08)
const TEXT := Color(1, 1, 1)
const SOFT := Color(1, 1, 1, 0.78)
const DIM := Color(0.8, 0.82, 0.86, 0.85)


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24

	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 20
	empty.content_margin_right = 20
	empty.content_margin_top = 4
	empty.content_margin_bottom = 4
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = ACCENT
	focus.border_width_left = 4
	focus.content_margin_left = 20
	for state: String in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		t.set_stylebox(state, "Button", empty)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", SOFT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_hover_pressed_color", "Button", ACCENT)
	t.set_font_size("font_size", "Button", 30)
	t.set_constant("outline_size", "Button", 8)
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.7))

	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 22)
	t.set_constant("outline_size", "Label", 8)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.7))

	t.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	t.set_constant("separation", "VBoxContainer", 4)
	return t


static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(440, 0)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(on_press)
	# Mouse hover and keyboard/gamepad selection look the same.
	b.mouse_entered.connect(b.grab_focus)
	return b


static func label(text: String, font_size: int = 22, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## Full-screen backdrop for the race-flow screens: slowly drifting
## diagonal stripes, a title bar on top and a hint bar along the bottom.
static func draw_backdrop(ci: CanvasItem, size: Vector2, t: float, accent: Color = ACCENT) -> void:
	var stripe := 90.0
	var shift := fmod(t * 18.0, stripe * 2.0)
	var x := -size.y - stripe * 2.0 + shift
	while x < size.x:
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x, size.y), Vector2(x + stripe, size.y),
				Vector2(x + stripe + size.y, 0.0), Vector2(x + size.y, 0.0)]), Color(1, 1, 1, 0.025))
		x += stripe * 2.0
	ci.draw_rect(Rect2(0, 0, size.x, 96.0), Color(0, 0, 0, 0.5))
	ci.draw_rect(Rect2(0, 96.0, size.x, 3.0), Color(accent, 0.8))
	ci.draw_rect(Rect2(0, size.y - 64.0, size.x, 64.0), Color(0, 0, 0, 0.5))
	ci.draw_rect(Rect2(0, size.y - 66.0, size.x, 2.0), Color(accent, 0.5))


## Wide letter spacing for titles ("R A C E").
static func spaced(text: String) -> String:
	return " ".join(text.split(""))


## Focus the first button in `container` (needed for keyboard / gamepad).
## Deferred, so it also works while the menu is still being built.
static func focus_first(container: Node) -> void:
	_focus_first_now.call_deferred(container)


static func _focus_first_now(container: Node) -> void:
	if not is_instance_valid(container):
		return
	for child in container.get_children():
		if child is Button and child.visible:
			child.grab_focus()
			return
