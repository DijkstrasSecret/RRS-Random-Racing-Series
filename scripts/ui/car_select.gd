class_name CarSelect
extends Control
## Fighting-game style car select: a grid of car portraits (with their class)
## and, above it, a big turning preview of each player's car with its stats.
## One player: arrows / WASD / gamepad, Enter / Space / A to choose.
## Two players choose at the same time: player 1 on WASD + Space or the first
## gamepad, player 2 on the arrows + Enter or the second gamepad.
## A player who already chose can press back (Q / Backspace / B) to change.

signal done
signal back

const P_COLORS: Array[Color] = [Color(0.35, 0.8, 1.0), Color(1.0, 0.38, 0.32)]
const COLUMNS := 10
const TILE := Vector2(150, 92)
const GAP := 10.0

var players: int = 1

var _cursor: Array[int] = [0, 0]
var _locked: Array[bool] = [false, false]
var _cards: Array[PlayerCard] = []
var _grid: CarGrid
var _portraits: CarPortraits
var _hint: Label
var _ready_timer := -1.0
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_portraits = CarPortraits.new()
	add_child(_portraits)


## Builds the screen for 1 or 2 players, starting on their saved cars.
func open(player_count: int) -> void:
	players = player_count
	for child in get_children():
		if child != _portraits:
			child.queue_free()
	_cards.clear()
	_locked = [false, false]
	_ready_timer = -1.0
	GameSettings.ensure_loaded()
	_cursor = [CarRoster.index_of(GameSettings.p1_car), CarRoster.index_of(GameSettings.p2_car)]

	var title := MenuStyle.label("SELECT YOUR CAR" if players == 1 else "SELECT YOUR CARS", 46, MenuStyle.ACCENT)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.offset_top = 28
	add_child(title)

	if players == 1:
		var card := PlayerCard.create(0, "YOU", true)
		card.position = Vector2(150, 110)
		add_child(card)
		_cards.append(card)
	else:
		for p in 2:
			var card := PlayerCard.create(p, "PLAYER %d" % (p + 1), false)
			card.position = Vector2(110 + p * 900, 100)
			add_child(card)
			_cards.append(card)

	_grid = CarGrid.new()
	_grid.owner_select = self
	_grid.portraits = _portraits
	var width := COLUMNS * TILE.x + (COLUMNS - 1) * GAP
	var rows := ceili(CarRoster.CARS.size() / float(COLUMNS))
	_grid.size = Vector2(width, rows * TILE.y + (rows - 1) * GAP + 24)
	_grid.position = Vector2((1920 - width) * 0.5, 692 if players == 2 else 660)
	add_child(_grid)

	_hint = MenuStyle.label("", 18, MenuStyle.DIM)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_top = -48
	_hint.offset_bottom = -18
	add_child(_hint)
	_refresh()


## Coming back from a later step: everyone chooses again.
func unlock_all() -> void:
	_locked = [false, false]
	_ready_timer = -1.0
	_refresh()


func cursor_of(player: int) -> int:
	return _cursor[player]


func is_locked(player: int) -> bool:
	return _locked[player]


func _refresh() -> void:
	for p in _cards.size():
		_cards[p].show_car(CarRoster.CARS[_cursor[p]].id, livery_of(p))
		_cards[p].set_locked(_locked[p])
	if players == 1:
		_hint.text = "Arrows / D-pad: choose      Enter / A: select      Y / R: livery on/off      Esc / B: back"
	else:
		_hint.text = "P1: WASD + Space, R livery, or pad 1      P2: arrows + Enter, L livery, or pad 2      Q / Backspace / B: change      Esc: back"


func livery_of(p: int) -> bool:
	return GameSettings.p1_livery if p == 0 else GameSettings.p2_livery


## Player `p` switches their car's livery on / off (cars that have one).
func toggle_livery(p: int) -> void:
	if not CarRoster.has_livery(CarRoster.CARS[_cursor[p]].id):
		return
	if p == 0:
		GameSettings.p1_livery = not GameSettings.p1_livery
	else:
		GameSettings.p2_livery = not GameSettings.p2_livery
	GameSettings.save()
	_refresh()
	if _grid:
		_grid.queue_redraw()


func _draw() -> void:
	MenuStyle.draw_backdrop(self, size, _t)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _ready_timer < 0.0:
		return
	_ready_timer -= delta
	if _ready_timer <= 0.0:
		_ready_timer = -1.0
		done.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed():
		return
	for p in players:
		if _handle_player(event, p):
			get_viewport().set_input_as_handled()
			return
	# Esc (or any gamepad's B in two-player mode): undo choices, then leave.
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _locked.has(true):
			_locked = [false, false]
			_ready_timer = -1.0
			_refresh()
		else:
			back.emit()


func _handle_player(event: InputEvent, p: int) -> bool:
	if _act(event, p, "back"):
		if _locked[p]:
			_locked[p] = false
			_ready_timer = -1.0
			_refresh()
		else:
			back.emit()
		return true
	if _act(event, p, "accept"):
		if not _locked[p]:
			choose(p, _cursor[p])
		return true
	if _act(event, p, "alt"):
		if not _locked[p]:
			toggle_livery(p)
		return true
	if _locked[p]:
		return _act(event, p, "left") or _act(event, p, "right") or _act(event, p, "up") or _act(event, p, "down")
	var moved := true
	if _act(event, p, "left"):
		_cursor[p] = wrapi(_cursor[p] - 1, 0, CarRoster.CARS.size())
	elif _act(event, p, "right"):
		_cursor[p] = wrapi(_cursor[p] + 1, 0, CarRoster.CARS.size())
	elif _act(event, p, "up"):
		_cursor[p] = _grid.vertical_neighbour(_cursor[p], -1)
	elif _act(event, p, "down"):
		_cursor[p] = _grid.vertical_neighbour(_cursor[p], 1)
	else:
		moved = false
	if moved:
		_refresh()
	return moved


## Player `p` picks car `index`. When everyone has picked, carry on.
func choose(p: int, index: int) -> void:
	_cursor[p] = index
	_locked[p] = true
	var id: String = CarRoster.CARS[index].id
	if p == 0:
		GameSettings.p1_car = id
	else:
		GameSettings.p2_car = id
	GameSettings.save()
	_refresh()
	if not _locked.slice(0, players).has(false):
		_ready_timer = 0.15 if players == 1 else 0.7


## Mouse: hovering moves player 1, clicking chooses.
func mouse_tile(index: int, clicked: bool) -> void:
	if _locked[0] or index < 0:
		return
	if index != _cursor[0]:
		_cursor[0] = index
		_refresh()
	if clicked:
		choose(0, index)


func _act(event: InputEvent, p: int, what: String) -> bool:
	var echo := what != "accept" and what != "back" and what != "alt"
	if event.is_action_pressed("p%d_menu_%s" % [p + 1, what], echo):
		return true
	if players == 1:
		if what == "alt":
			return event.is_action_pressed("menu_alt")
		var ui: String = {"up": "ui_up", "down": "ui_down", "left": "ui_left", "right": "ui_right",
			"accept": "ui_accept", "back": "ui_cancel"}[what]
		return event.is_action_pressed(ui, echo)
	return false


## The portrait grid. Rows are centred; the last row may be shorter.
class CarGrid extends Control:
	var owner_select: CarSelect
	var portraits: CarPortraits

	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # chunky PS1 portraits

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func tile_rect(i: int) -> Rect2:
		var n := CarRoster.CARS.size()
		var row := i / COLUMNS
		var in_row := mini(COLUMNS, n - row * COLUMNS)
		var row_w := in_row * TILE.x + (in_row - 1) * GAP
		var full_w := COLUMNS * TILE.x + (COLUMNS - 1) * GAP
		var x := (full_w - row_w) * 0.5 + (i % COLUMNS) * (TILE.x + GAP)
		return Rect2(Vector2(x, row * (TILE.y + GAP)), TILE)

	## The tile above (dir -1) or below (dir 1) that lines up best.
	func vertical_neighbour(i: int, dir: int) -> int:
		var n := CarRoster.CARS.size()
		var rows := ceili(n / float(COLUMNS))
		var row := wrapi(i / COLUMNS + dir, 0, rows)
		var cx := tile_rect(i).get_center().x
		var best := i
		var best_d := INF
		for j in n:
			if j / COLUMNS != row:
				continue
			var d := absf(tile_rect(j).get_center().x - cx)
			# Ties (rows offset by half a tile): down leans left, up leans
			# right, so down then up lands back where it started.
			if d < best_d - 0.5 or (absf(d - best_d) <= 0.5 and dir < 0 and j > best):
				best_d = d
				best = j
		return best

	func _gui_input(event: InputEvent) -> void:
		var mm := event as InputEventMouseMotion
		if mm:
			owner_select.mouse_tile(_tile_at(mm.position), false)
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			owner_select.mouse_tile(_tile_at(mb.position), true)
			accept_event()

	func _tile_at(pos: Vector2) -> int:
		for i in CarRoster.CARS.size():
			if tile_rect(i).has_point(pos):
				return i
		return -1

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for i in CarRoster.CARS.size():
			var e: Dictionary = CarRoster.CARS[i]
			var r := tile_rect(i)
			var tier := int(e.tier)
			var tc: Color = CarRoster.TIER_COLORS[tier]
			# Tiles under a cursor light up and lift a little.
			var hovered := false
			for p in owner_select.players:
				hovered = hovered or owner_select.cursor_of(p) == i
			if hovered:
				r = r.grow(3.0)
			var top := Color(0.11, 0.12, 0.16, 0.92) if hovered else Color(0.07, 0.08, 0.11, 0.88)
			draw_rect(r, top)
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)), Color(1, 1, 1, 0.035))
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - 4), Vector2(r.size.x, 4)), tc)
			var tex: Texture2D = portraits.textures.get(e.id)
			if tex:
				draw_texture_rect(tex, Rect2(r.position + Vector2(0, 2), Vector2(r.size.x, r.size.x * 0.6)), false)
			# Class badge.
			var badge := Rect2(r.position + Vector2(5, 5), Vector2(22, 22))
			draw_rect(badge, tc)
			draw_string(font, badge.position + Vector2(5, 17), CarRoster.TIER_NAMES[tier], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MenuStyle.DARK)
			var short_name: String = e.name.split(" ")[0]
			draw_string_outline(font, r.position + Vector2(6, r.size.y - 10), short_name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 10, 14, 4, Color(0, 0, 0, 0.85))
			draw_string(font, r.position + Vector2(6, r.size.y - 10), short_name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 10, 14, MenuStyle.TEXT)
		# Player cursors (player 2 inside player 1 when on the same car).
		for p in owner_select.players:
			var r := tile_rect(owner_select.cursor_of(p)).grow(7.0 - p * 5.0)
			var col: Color = P_COLORS[p]
			var locked := owner_select.is_locked(p)
			var pulse := 0.5 + 0.5 * sin(_t * 6.0 + p * 1.5)
			if locked:
				draw_rect(r, Color(col, 0.2))
			else:
				draw_rect(r.grow(3.0), Color(col, 0.18 * pulse), false, 6.0)
			draw_rect(r, col.lerp(Color.WHITE, 0.3 * pulse), false, 5.0 if locked else 3.0)
			var tag := "%dP" % (p + 1) if owner_select.players == 2 else ""
			if tag != "":
				var tp := Vector2(r.end.x - 30, r.position.y + 20) if p == 0 else Vector2(r.end.x - 30, r.end.y - 14)
				draw_rect(Rect2(tp - Vector2(4, 16), Vector2(30, 20)), col)
				draw_string(font, tp, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MenuStyle.DARK)


## One player's showroom: the hovering car, its name with a class badge,
## specs and sliding stat bars, in a frame of the player's colour.
class PlayerCard extends Control:
	var player: int
	var _header: Label
	var _preview: CarPreview
	var _badge_bg: ColorRect
	var _badge: Label
	var _name: Label
	var _class: Label
	var _tagline: Label
	var _specs: Label
	var _livery: Label
	var _bars: GaragePanel.StatBars
	var _title: String
	var _locked := false
	var _t := 0.0
	var _overlay: Control

	static func create(p: int, title: String, wide: bool) -> PlayerCard:
		var card := PlayerCard.new()
		card.player = p
		card._title = title
		card._build(wide)
		return card

	func _build(wide: bool) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col: Color = P_COLORS[player]
		_header = MenuStyle.label(_title, 26, col)
		_preview = CarPreview.new()
		_preview.accent = col
		_name = MenuStyle.label("", 40, MenuStyle.TEXT)
		_class = MenuStyle.label("", 20, MenuStyle.ACCENT)
		_tagline = MenuStyle.label("", 18, MenuStyle.DIM)
		_specs = MenuStyle.label("", 19, MenuStyle.ACCENT)
		_livery = MenuStyle.label("", 18, MenuStyle.TEXT)
		_bars = GaragePanel.StatBars.new()
		_bars.custom_minimum_size = Vector2(540, 6 * 30)
		# Class badge: a coloured square with the class letter, before the name.
		_badge_bg = ColorRect.new()
		_badge_bg.custom_minimum_size = Vector2(46, 46)
		_badge_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_badge = MenuStyle.label("", 30, MenuStyle.DARK)
		_badge.add_theme_constant_override("outline_size", 0)
		_badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_badge_bg.add_child(_badge)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 14)
		name_row.add_child(_badge_bg)
		name_row.add_child(_name)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 4)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for l: Control in [name_row, _class, _tagline, _specs, _livery]:
			info.add_child(l)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 10)
		info.add_child(gap)
		info.add_child(_bars)
		_header.position = Vector2(4, 0)
		if wide:
			_preview.position = Vector2(0, 44)
			_preview.size = Vector2(900, 456)
			info.position = Vector2(950, 60)
		else:
			_preview.position = Vector2(0, 40)
			_preview.size = Vector2(760, 216)
			_preview.camera_distance = 7.4
			info.position = Vector2(4, 266)
			_name.add_theme_font_size_override("font_size", 32)
			_badge_bg.custom_minimum_size = Vector2(38, 38)
			_badge.add_theme_font_size_override("font_size", 24)
			_bars.custom_minimum_size = Vector2(540, 6 * 26)
		add_child(_preview)
		add_child(_header)
		add_child(info)
		# Drawn on top of the 3D view (the READY banner).
		_overlay = Control.new()
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.position = _preview.position
		_overlay.size = _preview.size
		_overlay.draw.connect(_draw_overlay)
		add_child(_overlay)

	func show_car(id: String, livery: bool = true) -> void:
		var e := CarRoster.entry(id)
		var s := CarRoster.stats(id)
		var tier := int(e.tier)
		_preview.show_car(id, livery)
		if CarRoster.has_livery(id):
			var key := "Y / R" if player == 0 else "Y / L"
			_livery.text = "LIVERY  %s     (%s)" % ["ON" if livery else "OFF", key]
			_livery.add_theme_color_override("font_color", MenuStyle.ACCENT if livery else MenuStyle.DIM)
		else:
			_livery.text = "NO LIVERY FOR THIS CAR YET"
			_livery.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		_name.text = e.name
		_badge.text = CarRoster.TIER_NAMES[tier]
		_badge_bg.color = CarRoster.TIER_COLORS[tier]
		_class.text = "CLASS %s  ·  %s" % [CarRoster.TIER_NAMES[tier], CarRoster.TIER_TITLES[tier]]
		_class.add_theme_color_override("font_color", CarRoster.TIER_COLORS[tier])
		_tagline.text = e.tagline
		_specs.text = "%d HP   ·   %d KG   ·   %d KM/H   ·   %s%s" % [
			s.hp, s.kg, s.top_kmh, s.drive, "   ·   ELECTRIC" if s.electric else ""]
		_bars.stats = s

	func set_locked(locked: bool) -> void:
		_locked = locked
		_header.text = "%s  -  READY" % _title if locked else _title

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
		_overlay.queue_redraw()

	func _draw() -> void:
		var col: Color = P_COLORS[player]
		var r := Rect2(_preview.position, _preview.size)
		# Header strip and frame round the showroom (corner brackets glow
		# brighter, and pulse once the player is ready).
		draw_rect(Rect2(r.position.x, r.position.y - 8.0, r.size.x, 3.0), Color(col, 0.8))
		draw_rect(r.grow(6.0), Color(0, 0, 0, 0.6))
		var frame_a := 1.0 if _locked else 0.45
		draw_rect(r.grow(3.0), Color(col, frame_a), false, 2.0)
		var bright := col.lerp(Color.WHITE, 0.35 + (0.25 * sin(_t * 8.0) if _locked else 0.0))
		var k := 28.0
		var g := r.grow(6.0)
		for c: Vector2 in [g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]:
			var sx := 1.0 if c.x < g.get_center().x else -1.0
			var sy := 1.0 if c.y < g.get_center().y else -1.0
			draw_line(c, c + Vector2(k * sx, 0.0), bright, 5.0)
			draw_line(c, c + Vector2(0.0, k * sy), bright, 5.0)

	func _draw_overlay() -> void:
		if not _locked:
			return
		var col: Color = P_COLORS[player]
		var r := Rect2(Vector2.ZERO, _overlay.size)
		var banner := Rect2(r.position.x, r.end.y - 44.0, r.size.x, 40.0)
		_overlay.draw_rect(banner, Color(col, 0.8))
		var font := ThemeDB.fallback_font
		var w := font.get_string_size("READY", HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		_overlay.draw_string(font, Vector2(banner.get_center().x - w * 0.5, banner.end.y - 10.0), "READY",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 30, MenuStyle.DARK)
