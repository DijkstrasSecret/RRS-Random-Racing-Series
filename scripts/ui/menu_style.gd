class_name MenuStyle
extends RefCounted
## Shared look for the menus: each menu sits on a dark rounded card with an
## accent line on top; the selected row gets a soft highlight bar with an
## accent edge (same margins as the others, so nothing shifts).
## Works with mouse, keyboard and gamepad (Godot's ui_* actions).

const ACCENT := Color(1.0, 0.78, 0.2)
const DARK := Color(0.05, 0.06, 0.08)
const TEXT := Color(1, 1, 1)
const SOFT := Color(1, 1, 1, 0.78)
const DIM := Color(0.8, 0.82, 0.86, 0.85)


## Builds the shared menu Theme: fonts, colours, and button and panel styles.
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24

	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 20
	empty.content_margin_right = 20
	empty.content_margin_top = 4
	empty.content_margin_bottom = 4
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(ACCENT, 0.13)
	focus.border_color = ACCENT
	focus.border_width_left = 5
	focus.corner_radius_top_right = 4
	focus.corner_radius_bottom_right = 4
	focus.content_margin_left = 20
	focus.content_margin_right = 20
	focus.content_margin_top = 4
	focus.content_margin_bottom = 4
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

	t.set_stylebox("panel", "PanelContainer", card_style())
	t.set_constant("separation", "VBoxContainer", 4)
	return t


## The dark rounded card menus sit on.
static func card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.04, 0.055, 0.84)
	sb.border_color = ACCENT
	sb.border_width_top = 3
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 18
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	return sb


## Draws a card behind `c` (a plain container), `pad` pixels bigger all
## round. Layout is untouched: the card is only painted.
static func card(c: Control, pad: Vector2 = Vector2(34, 26)) -> void:
	var sb := card_style()
	c.draw.connect(func() -> void:
		sb.draw(c.get_canvas_item(), Rect2(-pad, c.size + pad * 2.0)))
	c.resized.connect(c.queue_redraw)


## A small section heading inside a menu ("CAMERA").
static func section(text: String) -> Label:
	var l := label(text, 17, Color(ACCENT, 0.9))
	l.custom_minimum_size = Vector2(0, 26)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


## A menu button that calls on_press when pressed. Mouse hover focuses it, so hover and gamepad selection look the same.
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


## The game logo (RRS / Random Racing Series), `width` pixels wide.
static func logo(width: float) -> TextureRect:
	var tex := load("res://assets/ui/logo.png") as Texture2D
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rect.custom_minimum_size = Vector2(width, width * tex.get_height() / tex.get_width())
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## A Label in the menu font, `font_size` in pixels.
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
