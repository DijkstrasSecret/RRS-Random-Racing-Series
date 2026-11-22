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
	_hint.offset_top = -70
	_hint.offset_bottom = -40
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
		_cards[p].show_car(CarRoster.CARS[_cursor[p]].id)
		_cards[p].set_locked(_locked[p])
	if players == 1:
		_hint.text = "Arrows / D-pad: choose      Enter / A: select      Esc / B: back"
	else:
		_hint.text = "P1: WASD + Space or gamepad 1      P2: arrows + Enter or gamepad 2      Q / Backspace / B: change      Esc: back"
	if _grid:
		_grid.queue_redraw()


func _process(delta: float) -> void:
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
	var echo := what != "accept" and what != "back"
	if event.is_action_pressed("p%d_menu_%s" % [p + 1, what], echo):
		return true
	if players == 1:
		var ui: String = {"up": "ui_up", "down": "ui_down", "left": "ui_left", "right": "ui_right",
			"accept": "ui_accept", "back": "ui_cancel"}[what]
		return event.is_action_pressed(ui, echo)
	return false


## The portrait grid. Rows are centred; the last row may be shorter.
class CarGrid extends Control:
	var owner_select: CarSelect
	var portraits: CarPortraits

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

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
			draw_rect(r, Color(0.07, 0.08, 0.11, 0.88))
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
			var r := tile_rect(owner_select.cursor_of(p)).grow(4.0 - p * 5.0)
			var col: Color = P_COLORS[p]
			var locked := owner_select.is_locked(p)
			if locked:
				draw_rect(r, Color(col, 0.18))
			draw_rect(r, col, false, 5.0 if locked else 3.0)
			var tag := "%dP" % (p + 1) if owner_select.players == 2 else ""
			if tag != "":
				var tp := Vector2(r.end.x - 30, r.position.y + 20) if p == 0 else Vector2(r.end.x - 30, r.end.y - 14)
				draw_rect(Rect2(tp - Vector2(4, 16), Vector2(30, 20)), col)
				draw_string(font, tp, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MenuStyle.DARK)


## One player's big preview: turning car, name, class, specs and stat bars.
class PlayerCard extends Control:
	var player: int
	var _header: Label
	var _preview: CarPreview
	var _name: Label
	var _class: Label
	var _tagline: Label
	var _specs: Label
	var _bars: GaragePanel.StatBars
	var _title: String

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
		_name = MenuStyle.label("", 40, MenuStyle.TEXT)
		_class = MenuStyle.label("", 20, MenuStyle.ACCENT)
		_tagline = MenuStyle.label("", 18, MenuStyle.DIM)
		_specs = MenuStyle.label("", 19, MenuStyle.ACCENT)
		_bars = GaragePanel.StatBars.new()
		_bars.custom_minimum_size = Vector2(540, 6 * 30)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 4)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for l: Control in [_name, _class, _tagline, _specs]:
			info.add_child(l)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		info.add_child(gap)
		info.add_child(_bars)
		if wide:
			_preview.position = Vector2(0, 30)
			_preview.size = Vector2(900, 470)
			_header.position = Vector2(10, 0)
			info.position = Vector2(960, 70)
		else:
			_header.position = Vector2(10, 0)
			_preview.position = Vector2(0, 26)
			_preview.size = Vector2(760, 228)
			_preview.camera_distance = 5.6
			info.position = Vector2(10, 252)
			_name.add_theme_font_size_override("font_size", 32)
			_bars.custom_minimum_size = Vector2(540, 6 * 26)
		add_child(_preview)
		add_child(_header)
		add_child(info)

	func show_car(id: String) -> void:
		var e := CarRoster.entry(id)
		var s := CarRoster.stats(id)
		var tier := int(e.tier)
		_preview.show_car(id)
		_name.text = e.name
		_class.text = "CLASS %s  ·  %s" % [CarRoster.TIER_NAMES[tier], CarRoster.TIER_TITLES[tier]]
		_class.add_theme_color_override("font_color", CarRoster.TIER_COLORS[tier])
		_tagline.text = e.tagline
		_specs.text = "%d HP   ·   %d KG   ·   %d KM/H   ·   %s%s" % [
			s.hp, s.kg, s.top_kmh, s.drive, "   ·   ELECTRIC" if s.electric else ""]
		_bars.stats = s
		_bars.queue_redraw()

	func set_locked(locked: bool) -> void:
		_header.text = "%s  -  READY" % _title if locked else _title
