extends Control
## Between tournament races: the standings, then each player's shop (3 random
## upgrade offers, a reroll and READY). Split screen: two shops, each player
## with their own keys / pad. After the final it becomes the podium.
## Keys: left / right to move, Enter / A (P1: Space) to buy or press.

const CARD := Vector2(300, 250)

var _cursor := [0, 0]  ## per player: 0..2 offers, 3 reroll, 4 ready
var _is_ready := [false, false]
var _flash := ["", ""]
var _flash_until := [0.0, 0.0]
var _font: Font
var _bold: FontVariation
var _t := 0.0
var _podium := false


func _ready() -> void:
	InputActions.ensure()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = MenuStyle.make_theme()
	_font = ThemeDB.fallback_font
	_bold = FontVariation.new()
	_bold.base_font = _font
	_bold.variation_embolden = 0.7
	_podium = not Tournament.final_order.is_empty()
	MusicPlayer.start_menu()
	var logo := MenuStyle.logo(300.0)
	logo.position = Vector2(40, 22)
	add_child(logo)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	MenuStyle.draw_backdrop(self, size, _t)
	if _podium:
		_draw_podium()
		return
	var done := Tournament.race_index  # races finished
	_big(Vector2(1180, 70), "AFTER RACE %d / %d  ·  UPGRADE SHOP" % [done, Tournament.RACES], 40, MenuStyle.ACCENT)
	var next_track := TrackList.display_name(Tournament.current_track())
	var next := ("NEXT: THE FINAL  ·  %s  ·  %d LAPS  ·  only this result counts!" % [next_track, Tournament.FINAL_LAPS]) \
			if Tournament.is_final() else ("NEXT: RACE %d / %d  ·  %s  ·  %d LAP" % [done + 1, Tournament.RACES, next_track, Tournament.RACE_LAPS])
	_big(Vector2(1180, 112), next, 22, MenuStyle.TEXT)
	_draw_standings(Rect2(40, 160, 560, 860))
	if Tournament.players == 1:
		_draw_shop(Rect2(640, 200, 1240, 760), 1)
	else:
		_draw_shop(Rect2(640, 160, 1240, 420), 1)
		_draw_shop(Rect2(640, 600, 1240, 420), 2)


func _draw_standings(r: Rect2) -> void:
	draw_rect(r, Color(0.05, 0.06, 0.09, 0.9))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 5)), Color(0.9, 0.08, 0.08))
	_text(r.position + Vector2(20, 40), "STANDINGS (POINTS)", 22, MenuStyle.DIM, true)
	var order: Array[int] = []
	for i in Tournament.racers.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return int(Tournament.racers[a].points) > int(Tournament.racers[b].points))
	var y := r.position.y + 70.0
	for n in order.size():
		var rc: Dictionary = Tournament.racers[order[n]]
		var row := Rect2(r.position.x + 12, y, r.size.x - 24, 88)
		draw_rect(row, Color(0.95, 0.95, 0.96, 0.95) if rc.human else (Color(0.1, 0.1, 0.12, 0.85) if n % 2 == 0 else Color(0.13, 0.13, 0.15, 0.85)))
		var ink := Color(0.05, 0.05, 0.07) if rc.human else MenuStyle.TEXT
		_text(row.position + Vector2(12, 36), str(n + 1), 24, ink, true)
		draw_rect(Rect2(row.position + Vector2(48, 12), Vector2(5, 64)), rc.color)
		_text(row.position + Vector2(64, 34), rc.name, 22, ink, true)
		_text(row.position + Vector2(64, 60), CarRoster.config(rc.car).display_name, 15, Color(0.3, 0.3, 0.35) if rc.human else MenuStyle.DIM)
		var res: Array = rc.results
		var last := ("last: %s" % RaceDirector.ordinal(int(res[res.size() - 1]))) if not res.is_empty() else ""
		_text(row.position + Vector2(64, 80), last + "   upgrades: %d" % _count(rc.upgrades), 14, Color(0.35, 0.35, 0.4) if rc.human else MenuStyle.DIM)
		draw_string(_bold, row.position + Vector2(0, 52), "%d" % int(rc.points), HORIZONTAL_ALIGNMENT_RIGHT, row.size.x - 16, 34, ink)
		y += 96.0


func _draw_shop(r: Rect2, player: int) -> void:
	var rc := Tournament.human(player)
	var p := player - 1
	draw_rect(r, Color(0.05, 0.06, 0.09, 0.9))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 5)), rc.color)
	_text(r.position + Vector2(24, 44), rc.name, 30, rc.color, true)
	draw_string(_bold, r.position + Vector2(0, 46), "POINTS TO SPEND: %d" % int(rc.wallet), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 24, 28, MenuStyle.ACCENT)
	var owned := Upgrades.describe(rc.upgrades)
	_text(r.position + Vector2(24, 76), "OWNED: " + (owned if owned != "" else "nothing yet"), 15, MenuStyle.DIM)
	var compact := Tournament.players == 2
	var card := Vector2(CARD.x, 190.0 if compact else CARD.y)
	var top := r.position.y + (96.0 if compact else 120.0)
	var offers: PackedStringArray = rc.offers
	for k in 3:
		var cr := Rect2(r.position.x + 24 + k * (card.x + 24), top, card.x, card.y)
		var sel: bool = _cursor[p] == k and not _is_ready[p]
		if k >= offers.size():
			draw_rect(cr, Color(0.08, 0.09, 0.12, 0.6))
			_text(cr.position + Vector2(20, card.y * 0.5), "SOLD", 22, MenuStyle.DIM, true)
			if sel:
				draw_rect(cr, MenuStyle.ACCENT, false, 4.0)
			continue
		var id: String = offers[k]
		var u: Dictionary = Upgrades.ALL[id]
		var kc: Color = Upgrades.KIND_COLORS[u.kind]
		var afford := Upgrades.cost(id) <= int(rc.wallet)
		draw_rect(cr, Color(0.1, 0.11, 0.15, 0.95))
		draw_rect(Rect2(cr.position, Vector2(cr.size.x, 8)), kc)
		draw_rect(cr, MenuStyle.ACCENT if sel else Color(1, 1, 1, 0.12), false, 5.0 if sel else 2.0)
		_text(cr.position + Vector2(16, 34), Upgrades.KIND_NAMES[u.kind], 14, kc, true)
		var lvl := int(rc.upgrades.get(id, 0))
		var title := String(u.name) + (" (%d/%d)" % [lvl + 1, int(u.max)] if int(u.max) > 1 else "")
		_text(cr.position + Vector2(16, 66), title, 21, MenuStyle.TEXT, true)
		draw_multiline_string(_font, cr.position + Vector2(16, 96), u.desc, HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 32, 16, 4,
				MenuStyle.DIM)
		var price := Rect2(cr.position + Vector2(16, cr.size.y - 46), Vector2(cr.size.x - 32, 34))
		draw_rect(price, Color(0.95, 0.75, 0.1) if afford else Color(0.3, 0.3, 0.33))
		draw_string(_bold, price.position + Vector2(0, 25), "BUY  ·  %d PTS" % Upgrades.cost(id), HORIZONTAL_ALIGNMENT_CENTER,
				price.size.x, 18, Color(0.05, 0.05, 0.07) if afford else Color(0.6, 0.6, 0.62))
	# Reroll and ready buttons.
	var bx := r.position.x + 24 + 3 * (card.x + 24)
	var bw := r.end.x - 24 - bx
	var reroll := Rect2(bx, top, bw, card.y * 0.45)
	var ready := Rect2(bx, top + card.y * 0.55, bw, card.y * 0.45)
	var rc_cost := Tournament.reroll_cost(rc)
	_button(reroll, "REROLL  ·  %s" % ("FREE" if rc_cost == 0 else "%d PTS" % rc_cost), _cursor[p] == 3 and not _is_ready[p], Color(0.25, 0.45, 0.8))
	_button(ready, "READY ✓" if _is_ready[p] else "READY", _cursor[p] == 4 or _is_ready[p], Color(0.2, 0.65, 0.3))
	if Time.get_ticks_msec() / 1000.0 < _flash_until[p]:
		_text(Vector2(r.position.x + 24, r.end.y - 18), _flash[p], 18, Color(1.0, 0.5, 0.4), true)
	else:
		var keys := "Left / right: choose   Enter / A: buy or press" if Tournament.players == 1 else \
				("A / D + Space   or pad 1" if player == 1 else "Arrows + Enter   or pad 2")
		_text(Vector2(r.position.x + 24, r.end.y - 18), keys, 15, MenuStyle.DIM)


func _button(r: Rect2, label: String, sel: bool, col: Color) -> void:
	draw_rect(r, col if sel else col.darkened(0.55))
	draw_rect(r, MenuStyle.ACCENT if sel else Color(1, 1, 1, 0.15), false, 4.0 if sel else 2.0)
	draw_string(_bold, Vector2(r.position.x, r.get_center().y + 9), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22, MenuStyle.TEXT)


func _draw_podium() -> void:
	var order := Tournament.final_order
	var champ: Dictionary = Tournament.racers[order[0]]
	_big(Vector2(960, 110), "TOURNAMENT CHAMPION", 34, MenuStyle.DIM)
	_big(Vector2(960, 185), String(champ.name), 72, champ.color)
	_big(Vector2(960, 232), CarRoster.config(champ.car).display_name, 24, MenuStyle.TEXT)
	# Podium blocks: 2nd, 1st, 3rd.
	var heights := [180.0, 250.0, 130.0]
	var slots := [1, 0, 2]
	for k in 3:
		if slots[k] >= order.size():
			continue
		var rc: Dictionary = Tournament.racers[order[slots[k]]]
		var block := Rect2(560 + k * 270, 560 - heights[k], 250, heights[k])
		draw_rect(block, rc.color.darkened(0.25))
		draw_rect(block, Color(1, 1, 1, 0.3), false, 3.0)
		draw_string(_bold, Vector2(block.position.x, block.position.y + 60), str(slots[k] + 1), HORIZONTAL_ALIGNMENT_CENTER, block.size.x, 56, MenuStyle.TEXT)
		draw_string(_bold, Vector2(block.position.x, block.position.y - 16), rc.name, HORIZONTAL_ALIGNMENT_CENTER, block.size.x, 24, rc.color)
	# Everyone, in final order.
	var y := 620.0
	for n in order.size():
		var rc: Dictionary = Tournament.racers[order[n]]
		var row := Rect2(360, y, 1200, 38)
		draw_rect(row, Color(0.95, 0.95, 0.96, 0.9) if rc.human else Color(0.08, 0.09, 0.12, 0.85))
		var ink := Color(0.05, 0.05, 0.07) if rc.human else MenuStyle.TEXT
		_text(row.position + Vector2(14, 27), "%d   %s" % [n + 1, rc.name], 20, ink, true)
		_text(row.position + Vector2(300, 27), CarRoster.config(rc.car).display_name, 17, ink)
		_text(row.position + Vector2(620, 27), "%d pts earned  ·  %d upgrades" % [int(rc.points), _count(rc.upgrades)], 17, ink)
		y += 44.0
	_big(Vector2(960, 1040), "Enter / A: main menu", 20, MenuStyle.DIM)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if _podium:
		if _any(event, 0, "accept") or _any(event, 0, "back"):
			Tournament.finish()
			get_tree().change_scene_to_file(GameSettings.MAIN_MENU)
		return
	for player in Tournament.players:
		var dev := player + 1 if Tournament.players == 2 else 0
		if _any(event, dev, "left"):
			_move(player, -1)
		elif _any(event, dev, "right"):
			_move(player, 1)
		elif _any(event, dev, "accept"):
			_press(player)
		else:
			continue
		get_viewport().set_input_as_handled()
		return


## dev 0 = any keys / pads (single player), 1 / 2 = that player's own.
func _any(event: InputEvent, dev: int, action: String) -> bool:
	if dev == 0:
		var ui: String = {"left": "ui_left", "right": "ui_right", "accept": "ui_accept", "back": "ui_cancel"}[action]
		return event.is_action_pressed(ui, true) or event.is_action_pressed("p1_menu_" + action, true) \
				or event.is_action_pressed("p2_menu_" + action, true)
	return event.is_action_pressed("p%d_menu_%s" % [dev, action], true)


func _move(p: int, step: int) -> void:
	if _is_ready[p]:
		_is_ready[p] = false  # changed their mind
	_cursor[p] = wrapi(_cursor[p] + step, 0, 5)


func _press(p: int) -> void:
	var rc := Tournament.human(p + 1)
	var c: int = _cursor[p]
	if c <= 2:
		var offers: PackedStringArray = rc.offers
		if c >= offers.size():
			return
		if not Tournament.buy(rc, offers[c]):
			_say(p, "Not enough points")
	elif c == 3:
		if not Tournament.reroll(rc):
			_say(p, "Not enough points to reroll")
	else:
		_is_ready[p] = true
		var all_ready := true
		for k in Tournament.players:
			all_ready = all_ready and _is_ready[k]
		if all_ready:
			get_tree().change_scene_to_file(Tournament.race_scene())


func _say(p: int, msg: String) -> void:
	_flash[p] = msg
	_flash_until[p] = Time.get_ticks_msec() / 1000.0 + 1.6


static func _count(owned: Dictionary) -> int:
	var n := 0
	for id: String in owned:
		n += int(owned[id])
	return n


func _text(pos: Vector2, s: String, font_size: int, color: Color, bold: bool = false) -> void:
	draw_string(_bold if bold else _font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _big(centre: Vector2, s: String, font_size: int, color: Color) -> void:
	draw_string_outline(_bold, Vector2(centre.x - 960, centre.y), s, HORIZONTAL_ALIGNMENT_CENTER, 1920, font_size, 8, Color(0, 0, 0, 0.8))
	draw_string(_bold, Vector2(centre.x - 960, centre.y), s, HORIZONTAL_ALIGNMENT_CENTER, 1920, font_size, color)
