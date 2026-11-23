class_name Tournament
extends RefCounted
## Tournament mode (roguelike): five 1-lap races on random tracks, then a
## 3-lap final. Each race pays points by finishing position; points are spent
## in the shop between races on upgrades (3 random offers each time). The AI
## earn and spend points too. Only the final's result decides the winner.
## State lives in static vars so it survives the scene changes.

const RACES := 5  ## qualifying races before the final
const RACE_LAPS := 1
const FINAL_LAPS := 3
const POINTS: PackedInt32Array = [10, 8, 6, 5, 4, 3, 2, 1]
const REROLL_COST := 2
const SHOP_SCENE := "res://scenes/ui/tournament_shop.tscn"

static var active := false
static var players := 1
## 0..RACES-1 = qualifying race, RACES = the final.
static var race_index := 0
static var tracks: PackedStringArray = []
## One per racer: {name, car, color, human, player (0 = AI, 1 / 2), skill,
## points (earned in total), wallet (left to spend), upgrades {id: count},
## results [positions], offers [ids], rerolled (bool)}.
static var racers: Array[Dictionary] = []
## Final standings (racer indices), set after the final.
static var final_order: Array[int] = []
static var rng := RandomNumberGenerator.new()


## Starts a new tournament: `track_pool` to draw from, AI from `ai_tiers`.
static func start(player_count: int, track_pool: PackedStringArray, ai_tiers: int, ai_count: int) -> void:
	active = true
	players = player_count
	race_index = 0
	final_order.clear()
	rng.randomize()
	var pool := Array(track_pool)
	pool.shuffle()
	tracks = PackedStringArray()
	for i in RACES + 1:
		tracks.append(pool[i % pool.size()])
	racers.clear()
	var names := ["YOU"] if player_count == 1 else ["PLAYER 1", "PLAYER 2"]
	var colors := [Color(0.35, 0.8, 1.0), Color(1.0, 0.4, 0.35)]
	var picks := [GameSettings.p1_car, GameSettings.p2_car]
	for p in player_count:
		racers.append(_racer(names[p], picks[p], colors[p], p + 1, 0.0))
	var roster := Array(CarRoster.ids_in_tiers(ai_tiers))
	if roster.is_empty():
		roster = Array(CarRoster.ids())
	roster.shuffle()
	var skill_range := GameSettings.ai_skill_range()
	for i in ai_count:
		var skill := lerpf(skill_range.x, skill_range.y, float(i) / maxf(ai_count - 1, 1))
		racers.append(_racer(RaceSetup.AI_NAMES[i], roster[i % roster.size()],
				RaceSetup.AI_COLORS[i % RaceSetup.AI_COLORS.size()], 0, skill))


static func _racer(racer_name: String, car: String, color: Color, player: int, skill: float) -> Dictionary:
	return {"name": racer_name, "car": car, "color": color, "human": player > 0, "player": player,
		"skill": skill, "points": 0, "wallet": 0, "upgrades": {}, "results": [], "offers": PackedStringArray(),
		"rerolled": false}


static func is_final() -> bool:
	return race_index >= RACES


static func current_track() -> String:
	return tracks[mini(race_index, tracks.size() - 1)]


static func current_laps() -> int:
	return FINAL_LAPS if is_final() else RACE_LAPS


static func race_title() -> String:
	return "FINAL" if is_final() else "RACE %d / %d" % [race_index + 1, RACES]


static func find(racer_name: String) -> int:
	for i in racers.size():
		if racers[i].name == racer_name:
			return i
	return -1


static func human(player: int) -> Dictionary:
	for r in racers:
		if int(r.player) == player:
			return r
	return {}


## AI racers, the slowest-on-points first: they start nearer the front.
static func grid_order() -> Array[int]:
	var order: Array[int] = []
	for i in racers.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if int(racers[a].points) != int(racers[b].points):
			return int(racers[a].points) < int(racers[b].points)
		return a > b)
	return order


## Takes the finishing order from the race (cars still running are placed
## by their position on the road), pays points, then moves on.
static func record(race: RaceDirector) -> void:
	var standings := race.standings()
	for pos in standings.size():
		var k := find(race.name_at(standings[pos]))
		if k < 0:
			continue
		var r := racers[k]
		(r.results as Array).append(pos + 1)
		if not is_final():
			var pts := POINTS[mini(pos, POINTS.size() - 1)]
			r.points = int(r.points) + pts
			r.wallet = int(r.wallet) + pts
	if is_final():
		final_order.clear()
		for i in standings:
			var k := find(race.name_at(i))
			if k >= 0:
				final_order.append(k)
	else:
		_prepare_shop()
	race_index += 1


## Rolls everyone's offers; the AI shop straight away.
static func _prepare_shop() -> void:
	for r in racers:
		r.offers = Upgrades.offers(rng, r.upgrades)
		r.rerolled = false
		if not r.human:
			_ai_shop(r)


## The AI buys what it can afford from its offers, most expensive first
## (sometimes it keeps the points for later).
static func _ai_shop(r: Dictionary) -> void:
	var offers := Array(r.offers)
	offers.sort_custom(func(a: String, b: String) -> bool: return Upgrades.cost(a) > Upgrades.cost(b))
	for id: String in offers:
		if Upgrades.cost(id) <= int(r.wallet) and rng.randf() < 0.85:
			buy(r, id)


static func buy(r: Dictionary, id: String) -> bool:
	var c := Upgrades.cost(id)
	if c > int(r.wallet):
		return false
	r.wallet = int(r.wallet) - c
	r.upgrades[id] = int(r.upgrades.get(id, 0)) + 1
	var offers := PackedStringArray(r.offers)
	offers.remove_at(offers.find(id))
	r.offers = offers
	return true


static func reroll(r: Dictionary) -> bool:
	var c := 0 if _won_last(r) and not r.rerolled else REROLL_COST
	if c > int(r.wallet):
		return false
	r.wallet = int(r.wallet) - c
	r.rerolled = true
	r.offers = Upgrades.offers(rng, r.upgrades)
	return true


## Reroll price for this racer right now (the last race's winner gets one free).
static func reroll_cost(r: Dictionary) -> int:
	return 0 if _won_last(r) and not r.rerolled else REROLL_COST


static func _won_last(r: Dictionary) -> bool:
	var res: Array = r.results
	return not res.is_empty() and int(res[res.size() - 1]) == 1


## Scene to load for the next race.
static func race_scene() -> String:
	return GameSettings.VERSUS if players == 2 else GameSettings.RACE


static func finish() -> void:
	active = false
