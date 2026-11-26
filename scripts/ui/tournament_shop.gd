extends Control
## Between tournament races: the standings, then each player's shop: 2 stat
## cards + 2 unlock cards, and buttons for fresh tyres, repairs, a reroll,
## the rival (with Rival Bounty) and READY. Split screen: two shops, each
## player with their own keys / pad. After the last race it becomes the podium.
## Keys: left / right to move, Enter / A (P1: Space) to buy or press.

const CARD_W := 232.0

var _cursor := [0, 0]
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


## The buttons after the 4 cards, for this racer.
func _buttons(rc: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if GameSettings.tyre_wear > 0.0:
		out.append("tyres")
	if GameSettings.damage > 0:
		out.append("repair")
	out.append("reroll")
	if int((rc.unlocks as Dictionary).get("rival_bounty", 0)) > 0:
		out.append("rival")
	out.append("ready")
	return out


func _draw() -> void:
	MenuStyle.draw_backdrop(self, size, _t)
	if _podium:
		_draw_podium()
		return
	var done := Tournament.race_index  # races finished
	_big(Vector2(1180, 70), "AFTER RACE %d / %d  ·  UPGRADE SHOP" % [done, Tournament.RACES], 40, MenuStyle.ACCENT)
	var next_track := TrackList.display_name(Tournament.current_track())
	var next := "NEXT: RACE %d / %d  ·  %s  ·  1 LAP" % [done + 1, Tournament.RACES, next_track]
	if Tournament.is_scored():
		next += "  ·  SCORED: counts for the tournament!"
	else:
		next += "  ·  points for the shop only (races %d-%d are scored)" % [Tournament.RACES - Tournament.SCORED + 1, Tournament.RACES]
	_big(Vector2(1180, 112), next, 20, MenuStyle.TEXT)
	_draw_standings(Rect2(40, 160, 560, 860))
	if Tournament.players == 1:
		_draw_shop(Rect2(640, 160, 1240, 860), 1)
	else:
		_draw_shop(Rect2(640, 160, 1240, 420), 1)
		_draw_shop(Rect2(640, 600, 1240, 420), 2)


func _draw_standings(r: Rect2) -> void:
	draw_rect(r, Color(0.05, 0.06, 0.09, 0.9))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 5)), Color(0.9, 0.08, 0.08))
	var scored := Tournament.race_index > Tournament.RACES - Tournament.SCORED
	_text(r.position + Vector2(20, 40), "STANDINGS  (SCORE · POINTS)" if scored else "STANDINGS  (POINTS EARNED)", 20, MenuStyle.DIM, true)
	var order: Array[int] = Tournament.score_order() if scored else Tournament.grid_order()
	if not scored:
		order.reverse()
	var y := r.position.y + 64.0
	for n in order.size():
		var rc: Dictionary = Tournament.racers[order[n]]
		var row := Rect2(r.position.x + 12, y, r.size.x - 24, 92)
		draw_rect(row, Color(0.95, 0.95, 0.96, 0.95) if rc.human else (Color(0.1, 0.1, 0.12, 0.85) if n % 2 == 0 else Color(0.13, 0.13, 0.15, 0.85)))
		var ink := Color(0.05, 0.05, 0.07) if rc.human else MenuStyle.TEXT
		var dim := Color(0.3, 0.3, 0.35) if rc.human else MenuStyle.DIM
		_text(row.position + Vector2(12, 36), str(n + 1), 24, ink, true)
		draw_rect(Rect2(row.position + Vector2(48, 12), Vector2(5, 68)), rc.color)
		_text(row.position + Vector2(64, 32), rc.name, 21, ink, true)
		_text(row.position + Vector2(64, 56), CarRoster.config(rc.car).display_name, 15, dim)
		var res: Array = rc.results
		var last := ""
		if not res.is_empty():
			last = "last: " + ("DNF" if int(res.back()) == 0 else RaceDirector.ordinal(int(res.back())))
		_text(row.position + Vector2(64, 80), last, 14, dim)
		var big := "%d" % (int(rc.score) if scored else int(rc.points))
		draw_string(_bold, row.position + Vector2(0, 48), big, HORIZONTAL_ALIGNMENT_RIGHT, row.size.x - 16, 34, ink)
		if scored:
			draw_string(_font, row.position + Vector2(0, 76), "%d pts" % int(rc.points), HORIZONTAL_ALIGNMENT_RIGHT, row.size.x - 16, 14, dim)
		y += 98.0


func _draw_shop(r: Rect2, player: int) -> void:
	var rc := Tournament.human(player)
	var p := player - 1
	var compact := Tournament.players == 2
	draw_rect(r, Color(0.05, 0.06, 0.09, 0.9))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 5)), rc.color)
	_text(r.position + Vector2(24, 42), rc.name, 28, rc.color, true)
	draw_string(_bold, r.position + Vector2(0, 44), "POINTS TO SPEND: %d" % int(rc.wallet), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 24, 26, MenuStyle.ACCENT)
	# Car state and loadout.
	var wear := Tournament.tyre_wear_avg(rc)
	var dmg := Tournament.damage_total(rc)
	var state := "TYRES %d%% worn   ·   DAMAGE %d%%   ·   PASSIVES %d / %d" % [roundi(wear * 100.0), roundi(dmg * 100.0),
			Upgrades.passive_count(rc), Upgrades.MAX_PASSIVES]
	if int(rc.bet) > 0:
		state += "   ·   BET %d ON A PODIUM" % int(rc.bet)
	if int(rc.rival) >= 0 and int((rc.unlocks as Dictionary).get("rival_bounty", 0)) > 0:
		state += "   ·   RIVAL: %s" % Tournament.racers[int(rc.rival)].name
	_text(r.position + Vector2(24, 70), state, 15, Color(1.0, 0.5, 0.4) if wear > 0.5 or dmg > 0.3 else MenuStyle.DIM)
	var owned := Upgrades.describe(rc)
	_text(r.position + Vector2(24, 92), "LOADOUT: " + (owned if owned != "" else "nothing yet"), 15, MenuStyle.DIM)
	var notes: Array = rc.notes
	if not notes.is_empty():
		_text(r.position + Vector2(24, 114), "  ·  ".join(PackedStringArray(notes)), 15, Color(1.0, 0.82, 0.25), true)
	var card_h := 230.0 if compact else 360.0
	var top := r.position.y + (128.0 if compact else 150.0)
	var offers: Array = rc.offers
	for k in 4:
		var cr := Rect2(r.position.x + 24 + k * (CARD_W + 14), top, CARD_W, card_h)
		var sel: bool = _cursor[p] == k and not _is_ready[p]
		if k >= offers.size():
			draw_rect(cr, Color(0.08, 0.09, 0.12, 0.6))
			_text(cr.position + Vector2(20, card_h * 0.5), "SOLD", 22, MenuStyle.DIM, true)
			if sel:
				draw_rect(cr, MenuStyle.ACCENT, false, 4.0)
			continue
		_draw_card(cr, offers[k], rc, sel, compact)
	# Buttons.
	var bx := r.position.x + 24 + 4 * (CARD_W + 14)
	var bw := r.end.x - 24 - bx
	var buttons := _buttons(rc)
	var bh := (card_h - 8.0 * (buttons.size() - 1)) / buttons.size()
	for n in buttons.size():
		var br := Rect2(bx, top + n * (bh + 8.0), bw, bh)
		var sel: bool = _cursor[p] == 4 + n and not _is_ready[p]
		match buttons[n]:
			"tyres":
				_button(br, "FRESH TYRES · %d" % Tournament.TYRES_COST, sel, Color(0.25, 0.5, 0.35))
			"repair":
				var c := Tournament.repair_cost(rc)
				_button(br, "REPAIR · %s" % ("—" if c == 0 else "%d" % c), sel, Color(0.55, 0.35, 0.2))
			"reroll":
				var c := Tournament.reroll_cost(rc)
				_button(br, "REROLL · %s" % ("FREE" if c == 0 else "%d" % c), sel, Color(0.25, 0.45, 0.8))
			"rival":
				var who := "pick" if int(rc.rival) < 0 else String(Tournament.racers[int(rc.rival)].name)
				_button(br, "RIVAL: %s ▸" % who, sel, Color(0.6, 0.45, 0.1))
			"ready":
				_button(br, "READY ✓" if _is_ready[p] else "READY", sel or _is_ready[p], Color(0.2, 0.65, 0.3))
	var foot_y := r.end.y - 18
	if Time.get_ticks_msec() / 1000.0 < _flash_until[p]:
		_text(Vector2(r.position.x + 24, foot_y), _flash[p], 18, Color(1.0, 0.5, 0.4), true)
	else:
		var keys := "Left / right: choose   Enter / A: buy or press" if Tournament.players == 1 else \
				("A / D + Space   or pad 1" if player == 1 else "Arrows + Enter   or pad 2")
		_text(Vector2(r.position.x + 24, foot_y), keys, 15, MenuStyle.DIM)


func _draw_card(cr: Rect2, card: Dictionary, rc: Dictionary, sel: bool, compact: bool) -> void:
	var id: String = card.id
	var stat := Upgrades.is_stat(id)
	var kind := Upgrades.kind_of(id)
	var band: Color = Upgrades.TIER_COLORS[int(card.tier)] if stat else Upgrades.KIND_COLORS[kind]
	var cost := Upgrades.cost(card)
	var afford := cost <= int(rc.wallet)
	draw_rect(cr, Color(0.1, 0.11, 0.15, 0.95))
	draw_rect(Rect2(cr.position, Vector2(cr.size.x, 10)), band)
	draw_rect(cr, MenuStyle.ACCENT if sel else Color(1, 1, 1, 0.12), false, 5.0 if sel else 2.0)
	var tag := "%s  ·  %s" % [Upgrades.KIND_NAMES[kind], Upgrades.TIER_NAMES[int(card.tier)]] if stat else Upgrades.KIND_NAMES[kind]
	_text(cr.position + Vector2(14, 34), tag, 13, band, true)
	draw_multiline_string(_bold, cr.position + Vector2(14, 62), Upgrades.card_name(card), HORIZONTAL_ALIGNMENT_LEFT,
			cr.size.x - 28, 20, 2, MenuStyle.TEXT)
	var desc_y := 112.0
	var lvl := 0 if stat else Upgrades.level_of(rc, id)
	var note := ""
	if lvl > 0 and not Upgrades.UNLOCKS[id].get("consumable", false):
		note = "LEVEL UP  →  %s" % ["", "I", "II", "III"][mini(lvl + 1, 3)]
	elif kind == Upgrades.Kind.POWER and rc.power_slot != "":
		note = "REPLACES " + String(Upgrades.UNLOCKS[rc.power_slot].name)
	elif kind == Upgrades.Kind.TACTICAL and rc.tactical_slot != "":
		note = "REPLACES " + String(Upgrades.UNLOCKS[rc.tactical_slot].name)
	if note != "":
		_text(cr.position + Vector2(14, 106), note, 13, Color(1.0, 0.82, 0.25), true)
		desc_y = 128.0
	draw_multiline_string(_font, cr.position + Vector2(14, desc_y), Upgrades.describe_card(card), HORIZONTAL_ALIGNMENT_LEFT,
			cr.size.x - 28, 15, 5 if compact else 9, MenuStyle.DIM)
	var price := Rect2(cr.position + Vector2(14, cr.size.y - 44), Vector2(cr.size.x - 28, 32))
	draw_rect(price, Color(0.95, 0.75, 0.1) if afford else Color(0.3, 0.3, 0.33))
	draw_string(_bold, price.position + Vector2(0, 23), "BUY  ·  %d PTS" % cost, HORIZONTAL_ALIGNMENT_CENTER,
			price.size.x, 17, Color(0.05, 0.05, 0.07) if afford else Color(0.6, 0.6, 0.62))


func _button(r: Rect2, label: String, sel: bool, col: Color) -> void:
	draw_rect(r, col if sel else col.darkened(0.55))
	draw_rect(r, MenuStyle.ACCENT if sel else Color(1, 1, 1, 0.15), false, 4.0 if sel else 2.0)
	draw_string(_bold, Vector2(r.position.x, r.get_center().y + 7), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, MenuStyle.TEXT)


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
		_text(row.position + Vector2(620, 27), "SCORE %d  ·  %d pts earned" % [int(rc.score), int(rc.points)], 17, ink)
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
	var rc := Tournament.human(p + 1)
	_cursor[p] = wrapi(_cursor[p] + step, 0, 4 + _buttons(rc).size())


func _press(p: int) -> void:
	var rc := Tournament.human(p + 1)
	var c: int = _cursor[p]
	if c < 4:
		var offers: Array = rc.offers
		if c >= offers.size():
			return
		var card: Dictionary = offers[c]
		if Upgrades.cost(card) > int(rc.wallet):
			_say(p, "Not enough points")
		elif not Tournament.buy(rc, card):
			_say(p, "Can't take that: passive slots full or already maxed")
		elif card.id == "rival_bounty":
			Tournament.next_rival(rc)
			_say(p, "Rival Bounty: press RIVAL to change who you're hunting")
		return
	match _buttons(rc)[c - 4]:
		"tyres":
			if Tournament.tyre_wear_avg(rc) <= 0.001:
				_say(p, "Your tyres are already fresh")
			elif not Tournament.buy_tyres(rc):
				_say(p, "Not enough points for tyres")
		"repair":
			if Tournament.repair_cost(rc) == 0:
				_say(p, "Nothing to repair")
			elif not Tournament.repair(rc):
				_say(p, "Not enough points to repair")
		"reroll":
			if not Tournament.reroll(rc):
				_say(p, "Not enough points to reroll")
		"rival":
			Tournament.next_rival(rc)
		"ready":
			_is_ready[p] = true
			var all_ready := true
			for k in Tournament.players:
				all_ready = all_ready and _is_ready[k]
			if all_ready:
				get_tree().change_scene_to_file(Tournament.race_scene())


func _say(p: int, msg: String) -> void:
	_flash[p] = msg
	_flash_until[p] = Time.get_ticks_msec() / 1000.0 + 1.8


func _text(pos: Vector2, s: String, font_size: int, color: Color, bold: bool = false) -> void:
	draw_string(_bold if bold else _font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _big(centre: Vector2, s: String, font_size: int, color: Color) -> void:
	draw_string_outline(_bold, Vector2(centre.x - 960, centre.y), s, HORIZONTAL_ALIGNMENT_CENTER, 1920, font_size, 8, Color(0, 0, 0, 0.8))
	draw_string(_bold, Vector2(centre.x - 960, centre.y), s, HORIZONTAL_ALIGNMENT_CENTER, 1920, font_size, color)
