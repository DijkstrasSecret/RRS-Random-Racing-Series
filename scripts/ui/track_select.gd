class_name TrackSelect
extends Control
## Pick the circuit, laid out like the car select: a big preview of the chosen
## track at the top (a looping race clip, its map, numbers and surfaces) and a
## row of small track cards along the bottom.
## Left / right to browse, Enter / Space / A to pick, Esc / B to go back.
## In split screen either player can choose.

signal done
signal back

const CLIP_DIR := "res://assets/ui/track_clips/%s.ogv"
const COUNTRY := {
	"monza": "ITALY", "spa": "BELGIUM", "silverstone": "GREAT BRITAIN", "istanbul": "TURKEY",
	"holjes": "SWEDEN", "lydden": "GREAT BRITAIN", "montalegre": "PORTUGAL", "hell": "NORWAY",
	"coral": "TROPICAL ISLAND",
}
const SERIES_NAME := {"F1": "F1 CIRCUIT", "RX": "RALLYCROSS", "ISLAND": "ISLAND"}
const SERIES_COLOR := {"F1": Color(0.85, 0.1, 0.1), "RX": Color(0.9, 0.52, 0.1), "ISLAND": Color(0.1, 0.62, 0.66)}
const SURFACE_COLOR := {"tarmac": Color(0.45, 0.46, 0.5), "gravel": Color(0.66, 0.55, 0.4),
	"sand": Color(0.9, 0.82, 0.6), "wood": Color(0.55, 0.38, 0.24)}

const PREVIEW := Rect2(70, 108, 1120, 630)
const INFO := Rect2(1214, 108, 636, 630)
const CARD := Vector2(192, 200)
const CARD_Y := 788.0

var _index := 0
var _cards: Array[TrackCard] = []
var _video: VideoStreamPlayer
var _overlay: Control
var _outlines: Dictionary = {}
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var title := MenuStyle.label("SELECT TRACK", 46, MenuStyle.ACCENT)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.offset_top = 24
	add_child(title)
	_video = VideoStreamPlayer.new()
	_video.position = PREVIEW.position
	_video.size = PREVIEW.size
	_video.expand = true
	_video.loop = true
	_video.volume_db = -80.0
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_video)
	# Small map over the corner of the clip (drawn above the video).
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.draw.connect(func() -> void:
		var mini := Rect2(PREVIEW.end - Vector2(210, 150), Vector2(196, 136))
		overlay.draw_rect(mini, Color(0, 0, 0, 0.55))
		TrackCard.draw_outline(overlay, mini.grow(-12), _outlines[selected_id()], Color(1, 1, 1, 0.9), 3.0, MenuStyle.ACCENT))
	add_child(overlay)
	_overlay = overlay
	var n := TrackList.TRACKS.size()
	var gap := (1920.0 - 2.0 * 50.0 - n * CARD.x) / maxf(n - 1, 1)
	for i in n:
		var id: String = TrackList.TRACKS[i].id
		_outlines[id] = TrackList.outline(id)
		var card := TrackCard.new()
		card.track_id = id
		card.outline = _outlines[id]
		card.size = CARD
		card.position = Vector2(50.0 + i * (CARD.x + gap), CARD_Y)
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
	hint.offset_top = -44
	hint.offset_bottom = -16
	add_child(hint)


func _draw() -> void:
	MenuStyle.draw_backdrop(self, size, _t)
	var t := TrackList.get_track(selected_id())
	var series := String(t.get("series", ""))
	var accent: Color = SERIES_COLOR.get(series, MenuStyle.ACCENT)
	var font := ThemeDB.fallback_font
	# Preview frame (the clip plays inside it; the map if there's no clip).
	draw_rect(PREVIEW.grow(6), Color(0, 0, 0, 0.75))
	draw_rect(PREVIEW.grow(6), accent, false, 4.0)
	if _video.stream == null:
		draw_rect(PREVIEW, Color(0.06, 0.07, 0.1))
		_draw_map(PREVIEW.grow(-60), _outlines[selected_id()], Color(0.85, 0.87, 0.92), 9.0)
	# Info panel.
	draw_rect(INFO, Color(0.05, 0.06, 0.09, 0.9))
	draw_rect(Rect2(INFO.position, Vector2(INFO.size.x, 6)), accent)
	var x := INFO.position.x + 30.0
	var y := INFO.position.y + 40.0
	var tag := Rect2(Vector2(x, y), Vector2(180, 34))
	draw_rect(tag, accent)
	draw_string(font, tag.position + Vector2(0, 25), SERIES_NAME.get(series, series), HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 18, MenuStyle.TEXT)
	draw_string(font, Vector2(tag.end.x + 16, y + 25), COUNTRY.get(selected_id(), ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MenuStyle.DIM)
	y += 100.0
	draw_string_outline(font, Vector2(x, y), t.name, HORIZONTAL_ALIGNMENT_LEFT, INFO.size.x - 60, 46, 8, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(x, y), t.name, HORIZONTAL_ALIGNMENT_LEFT, INFO.size.x - 60, 46, MenuStyle.TEXT)
	y += 60.0
	var o: Dictionary = _outlines[selected_id()]
	var stats := [["LENGTH", "%.2f KM" % (o.length / 1000.0)], ["CORNERS", str(o.corners)], ["ELEVATION", "%d M" % roundi(_elevation(t))]]
	for k in stats.size():
		var sx := x + k * 190.0
		draw_string(font, Vector2(sx, y), stats[k][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MenuStyle.DIM)
		draw_string(font, Vector2(sx, y + 36), stats[k][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, accent.lerp(Color.WHITE, 0.35))
	y += 84.0
	# Surface mix as a bar.
	draw_string(font, Vector2(x, y), "SURFACE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MenuStyle.DIM)
	var mix := _surface_mix(t)
	var bar := Rect2(x, y + 12.0, INFO.size.x - 60.0, 22.0)
	var bx := bar.position.x
	var labels := PackedStringArray()
	for kind: String in ["tarmac", "gravel", "sand", "wood"]:
		var share: float = mix.get(kind, 0.0)
		if share <= 0.0:
			continue
		draw_rect(Rect2(bx, bar.position.y, bar.size.x * share, bar.size.y), SURFACE_COLOR[kind])
		bx += bar.size.x * share
		labels.append("%s %d%%" % [kind.to_upper(), roundi(share * 100.0)])
	draw_string(font, Vector2(x, bar.end.y + 30.0), "   ".join(labels), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, MenuStyle.TEXT)
	y = bar.end.y + 80.0
	draw_multiline_string(font, Vector2(x, y), t.tagline, HORIZONTAL_ALIGNMENT_LEFT, INFO.size.x - 60, 22, 4, MenuStyle.DIM)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func open() -> void:
	GameSettings.ensure_loaded()
	_select(TrackList.index_of(GameSettings.track))


func selected_id() -> String:
	return TrackList.TRACKS[_index].id


func _select(i: int) -> void:
	var changed := i != _index or _video.stream == null
	_index = i
	for k in _cards.size():
		_cards[k].selected = k == i
		_cards[k].queue_redraw()
	if changed:
		var path := CLIP_DIR % selected_id()
		_video.stop()
		_video.stream = load(path) as VideoStream if ResourceLoader.exists(path) else null
		if _video.stream and is_visible_in_tree():
			_video.play()
	queue_redraw()
	if _overlay:
		_overlay.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _video:
		if is_visible_in_tree() and _video.stream:
			_video.play()
		else:
			_video.stop()


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


## Rise and fall of the track in metres (from its height data).
static func _elevation(t: Dictionary) -> float:
	if t.has("profile"):
		var lo := 1e9
		var hi := -1e9
		for key: Array in t.profile:
			lo = minf(lo, float(key[1]))
			hi = maxf(hi, float(key[1]))
		return (hi - lo) * float(t.get("height_scale", 1.0))
	return float(t.get("hills", 0.0))


## Share of the lap on each road surface.
static func _surface_mix(t: Dictionary) -> Dictionary:
	var mix := {"tarmac": 1.0}
	for sec: Array in t.get("surfaces", []):
		var share := float(sec[1]) - float(sec[0])
		mix[sec[2]] = float(mix.get(sec[2], 0.0)) + share
		mix["tarmac"] = float(mix["tarmac"]) - share
	return mix


## The circuit outline fitted into `box`, with the start line and direction.
func _draw_map(box: Rect2, o: Dictionary, color: Color, width: float) -> void:
	TrackCard.draw_outline(self, box, o, color, width, MenuStyle.ACCENT)


## A small map card for the bottom row: outline, name, series colour strip.
class TrackCard extends Control:
	signal hovered
	signal clicked

	var track_id: String
	var selected := false
	var outline: Dictionary

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void: hovered.emit())

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
			accept_event()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var t := TrackList.get_track(track_id)
		var series := String(t.get("series", ""))
		var col: Color = SERIES_COLOR.get(series, MenuStyle.ACCENT)
		var r := Rect2(Vector2.ZERO, size)
		if selected:
			r = r.grow(6)
		draw_rect(r, Color(0.07, 0.08, 0.11, 0.92))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 5)), col)
		draw_rect(r, MenuStyle.ACCENT if selected else Color(1, 1, 1, 0.15), false, 4.0 if selected else 2.0)
		draw_outline(self, Rect2(r.position + Vector2(18, 18), Vector2(r.size.x - 36, r.size.y - 82)), outline,
				MenuStyle.TEXT if selected else Color(0.7, 0.73, 0.78), 4.0, MenuStyle.ACCENT)
		draw_string(font, Vector2(r.position.x + 6, r.end.y - 38), t.name, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 12, 15 if String(t.name).length() > 13 else 17,
				MenuStyle.ACCENT if selected else MenuStyle.TEXT)
		draw_string(font, Vector2(r.position.x + 10, r.end.y - 14), SERIES_NAME.get(series, series), HORIZONTAL_ALIGNMENT_CENTER,
				r.size.x - 20, 13, col.lerp(Color.WHITE, 0.3))

	## Draws a circuit outline fitted into `box` on `ci`, with start line and arrow.
	static func draw_outline(ci: CanvasItem, box: Rect2, o: Dictionary, color: Color, width: float, mark: Color) -> void:
		var pts: PackedVector2Array = o.points
		var bounds := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			bounds = bounds.expand(p)
		var sc := minf(box.size.x / maxf(bounds.size.x, 1.0), box.size.y / maxf(bounds.size.y, 1.0))
		var off := box.get_center() - bounds.get_center() * sc
		var line := PackedVector2Array()
		for p in pts:
			line.append(p * sc + off)
		line.append(line[0])
		ci.draw_polyline(line, Color(0, 0, 0, 0.6), width + 4.0, true)
		ci.draw_polyline(line, color, width, true)
		var a := line[0]
		var b := line[mini(2, line.size() - 1)]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		ci.draw_line(a - side * width * 2.2, a + side * width * 2.2, mark, width * 0.8)
