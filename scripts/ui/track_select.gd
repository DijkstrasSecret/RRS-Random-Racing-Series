class_name TrackSelect
extends Control
## Pick the circuit: one card per layout with its map, length and corners.
## The cards slide along so the chosen one sits in the middle.
## Left / right to browse, Enter / Space / A to pick, Esc / B to go back.
## In split screen either player can choose.

signal done
signal back

const CARD := Vector2(500, 600)
const GAP := 40.0

var _index := 0
var _cards: Array[TrackCard] = []
var _scroll := 0.0  ## x offset of the card row (eases towards the chosen card)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var title := MenuStyle.label("SELECT TRACK", 46, MenuStyle.ACCENT)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.offset_top = 28
	add_child(title)
	var n := TrackList.TRACKS.size()
	for i in n:
		var card := TrackCard.new()
		card.track_id = TrackList.TRACKS[i].id
		card.size = CARD
		card.hovered.connect(func() -> void: _select(i))
		card.clicked.connect(func() -> void:
			_select(i)
			_pick())
		add_child(card)
		_cards.append(card)
	var hint := MenuStyle.label("Left / right: choose      Enter / A: select      Esc / B: back", 18, MenuStyle.DIM)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_top = -48
	hint.offset_bottom = -18
	add_child(hint)


var _t := 0.0


func _draw() -> void:
	MenuStyle.draw_backdrop(self, size, _t)


func _process(delta: float) -> void:
	_t += delta
	_scroll = lerpf(_scroll, _target_scroll(), 1.0 - exp(-10.0 * delta))
	_place_cards()
	queue_redraw()


## Row offset that puts the chosen card in the middle of the screen.
func _target_scroll() -> float:
	return _index * (CARD.x + GAP) - (1920.0 - CARD.x) * 0.5


func _place_cards() -> void:
	for i in _cards.size():
		_cards[i].position = Vector2(i * (CARD.x + GAP) - _scroll, 190)


func open() -> void:
	GameSettings.ensure_loaded()
	_select(TrackList.index_of(GameSettings.track))
	_scroll = _target_scroll()
	_place_cards()


func selected_id() -> String:
	return TrackList.TRACKS[_index].id


func _select(i: int) -> void:
	_index = i
	for k in _cards.size():
		_cards[k].selected = k == i
		_cards[k].queue_redraw()


func _pick() -> void:
	GameSettings.track = selected_id()
	GameSettings.save()
	done.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed():
		return
	if _any(event, "left", "ui_left", true):
		_select(wrapi(_index - 1, 0, _cards.size()))
	elif _any(event, "right", "ui_right", true):
		_select(wrapi(_index + 1, 0, _cards.size()))
	elif _any(event, "accept", "ui_accept", false):
		_pick()
	elif _any(event, "back", "ui_cancel", false):
		back.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _any(event: InputEvent, menu: String, ui: String, echo: bool) -> bool:
	return (event.is_action_pressed(ui, echo) or event.is_action_pressed("p1_menu_" + menu, echo)
			or event.is_action_pressed("p2_menu_" + menu, echo))


## A map card: the circuit outline, its name and numbers.
class TrackCard extends Control:
	signal hovered
	signal clicked

	var track_id: String
	var selected := false
	var _outline: Dictionary

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_outline = TrackList.outline(track_id)
		mouse_entered.connect(func() -> void: hovered.emit())

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
			accept_event()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var t := TrackList.get_track(track_id)
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.07, 0.08, 0.11, 0.85))
		draw_rect(r, MenuStyle.ACCENT if selected else Color(1, 1, 1, 0.15), false, 5.0 if selected else 2.0)
		# Map, fitted into the top of the card.
		var pts: PackedVector2Array = _outline.points
		var box := Rect2(Vector2(40, 40), Vector2(size.x - 80, 330))
		var bounds := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			bounds = bounds.expand(p)
		var sc := minf(box.size.x / bounds.size.x, box.size.y / bounds.size.y)
		var off := box.get_center() - bounds.get_center() * sc
		var line := PackedVector2Array()
		for p in pts:
			line.append(p * sc + off)
		line.append(line[0])
		draw_polyline(line, Color(0, 0, 0, 0.6), 13.0, true)
		draw_polyline(line, MenuStyle.TEXT if selected else Color(0.75, 0.78, 0.82), 7.0, true)
		# Start / finish line and driving direction.
		var a := line[0]
		var b := line[2]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		draw_line(a - side * 14.0, a + side * 14.0, MenuStyle.ACCENT, 5.0)
		draw_colored_polygon(PackedVector2Array([b + dir * 22.0, b + side * 9.0, b - side * 9.0]), MenuStyle.ACCENT)
		var y := 420.0
		if t.get("real", false):
			var tag := Rect2(Vector2(size.x - 150, 20), Vector2(130, 34))
			draw_rect(tag, Color(0.85, 0.1, 0.1, 0.9))
			draw_string(font, tag.position + Vector2(0, 25), "F1 CIRCUIT", HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 18, MenuStyle.TEXT)
		draw_string_outline(font, Vector2(30, y), t.name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 60, 34, 6, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(30, y), t.name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 60, 34,
				MenuStyle.ACCENT if selected else MenuStyle.TEXT)
		var facts := "%.1f KM   ·   %d CORNERS" % [_outline.length / 1000.0, _outline.corners]
		draw_string(font, Vector2(30, y + 40), facts, HORIZONTAL_ALIGNMENT_LEFT, size.x - 60, 20, MenuStyle.ACCENT)
		draw_multiline_string(font, Vector2(30, y + 80), t.tagline, HORIZONTAL_ALIGNMENT_LEFT, size.x - 60, 19, 3, MenuStyle.DIM)
