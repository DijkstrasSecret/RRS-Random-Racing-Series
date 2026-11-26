class_name Tournament
extends RefCounted
## Tournament mode (roguelike): six 1-lap races on random tracks with an
## upgrade shop between them. Every race pays shop points by position; only
## the last three races also count for the tournament score. Tyre wear and
## damage carry over from race to race (the shop sells fresh tyres and
## repairs). No recovery: a car stuck or upside down is out of that race (DNF,
## no points). The AI earn and spend points too (stat cards and X / Y items).
## State lives in static vars so it survives the scene changes.

const RACES := 6
const SCORED := 3  ## the last this-many races count for the tournament score
const RACE_LAPS := 1
const POINTS: PackedInt32Array = [10, 8, 6, 5, 4, 3, 2, 1]
const REROLL_COST := 1
const TYRES_COST := 2
const REPAIR_COST_PER_10 := 1  ## points per 10% of damage
const INTEREST_RATE := 0.1
const INTEREST_CAP := 10
const BOUNTY := 6
const SHOP_SCENE := "res://scenes/ui/tournament_shop.tscn"

static var active := false
static var players := 1
## 0..RACES-1 = the race about to be run / just run.
static var race_index := 0
static var tracks: PackedStringArray = []
## One per racer: {name, car, color, human, player (0 = AI, 1 / 2), skill,
## points (earned in total), wallet (left to spend), score (scored races),
## results [positions, 0 = DNF], stats [{id, tier}], unlocks {id: level},
## power_slot / power_level, tactical_slot / tactical_level, bet (stake on
## the next race), rival (racer index or -1), tyre_wear [4], damage [zones],
## offers [cards], rerolled, notes [shop messages]}.
static var racers: Array[Dictionary] = []
## Final standings (racer indices), set after the last race.
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
	for i in RACES:
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
		"skill": skill, "points": 0, "wallet": 0, "score": 0, "results": [], "stats": [], "unlocks": {},
		"power_slot": "", "power_level": 0, "tactical_slot": "", "tactical_level": 0, "bet": 0, "rival": -1,
		"tyre_wear": [0.0, 0.0, 0.0, 0.0], "damage": [], "offers": [], "rerolled": false, "notes": []}


## True if the race at race_index counts for the tournament score.
static func is_scored(index: int = -1) -> bool:
	return (race_index if index < 0 else index) >= RACES - SCORED


## Kept for the old callers: the last race.
static func is_final() -> bool:
	return race_index >= RACES - 1


static func current_track() -> String:
	return tracks[mini(race_index, tracks.size() - 1)]


static func current_laps() -> int:
	return RACE_LAPS


static func race_title() -> String:
	return "RACE %d / %d%s" % [race_index + 1, RACES, "  ·  SCORED" if is_scored() else ""]


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


## The grid goes by points: the leader starts at the back.
static func grid_order() -> Array[int]:
	var order: Array[int] = []
	for i in racers.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if int(racers[a].points) != int(racers[b].points):
			return int(racers[a].points) < int(racers[b].points)
		return a > b)
	return order


## Racer indices by tournament score (ties: better finish in the last race run).
static func score_order() -> Array[int]:
	var order: Array[int] = []
	for i in racers.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if int(racers[a].score) != int(racers[b].score):
			return int(racers[a].score) > int(racers[b].score)
		return _last_pos(a) < _last_pos(b))
	return order


static func _last_pos(i: int) -> int:
	var res: Array = racers[i].results
	if res.is_empty() or int(res.back()) == 0:
		return 99
	return int(res.back())


## Takes the finishing order from the race (cars still running are placed by
## their position on the road, retired cars last and pay nothing), pays
## points, settles bets and bounties, saves tyre wear and damage, moves on.
static func record(race: RaceDirector) -> void:
	var standings := race.standings()
	var scored := is_scored()
	var positions := {}
	for pos in standings.size():
		var i: int = standings[pos]
		var k := find(race.name_at(i))
		if k < 0:
			continue
		var r := racers[k]
		r.notes = []
		var dnf := race.is_retired(i)
		positions[k] = 0 if dnf else pos + 1
		(r.results as Array).append(positions[k])
		if not dnf:
			var pts := POINTS[mini(pos, POINTS.size() - 1)]
			r.points = int(r.points) + pts
			r.wallet = int(r.wallet) + pts
			if scored:
				r.score = int(r.score) + pts
		else:
			(r.notes as Array).append("DNF: no points")
		_save_car(r, race.vehicle_at(i))
	# Bets and bounties.
	for k in positions:
		var r := racers[k]
		var pos: int = positions[k]
		if int(r.bet) > 0:
			if pos >= 1 and pos <= 3:
				r.wallet = int(r.wallet) + int(r.bet) * 2
				(r.notes as Array).append("Bet won: +%d" % (int(r.bet) * 2))
			else:
				(r.notes as Array).append("Bet lost: -%d" % int(r.bet))
			r.bet = 0
		var rival := int(r.rival)
		if int((r.unlocks as Dictionary).get("rival_bounty", 0)) > 0 and positions.has(rival):
			var theirs: int = positions[rival]
			if pos > 0 and (theirs == 0 or pos < theirs):
				r.wallet = int(r.wallet) + BOUNTY
				(r.notes as Array).append("Beat %s: bounty +%d" % [racers[rival].name, BOUNTY])
	race_index += 1
	if race_index >= RACES:
		final_order = score_order()
	else:
		_prepare_shop()


## Tyre wear and damage the car finished the race with.
static func _save_car(r: Dictionary, car: Vehicle) -> void:
	if car == null:
		return
	var wear := [0.0, 0.0, 0.0, 0.0]
	for n in mini(car.wheels.size(), 4):
		wear[n] = car.wheels[n].wear
	r.tyre_wear = wear
	r.damage = Array(car.damage.zones) if car.damage else []


## Puts the carried-over tyre wear and damage on a car at the start of a race.
static func restore_car(r: Dictionary, car: Vehicle) -> void:
	var wear: Array = r.get("tyre_wear", [])
	for n in mini(car.wheels.size(), wear.size()):
		car.wheels[n].wear = float(wear[n])
	var dmg: Array = r.get("damage", [])
	if car.damage and not dmg.is_empty():
		car.damage.restore(PackedFloat32Array(dmg))


static func damage_total(r: Dictionary) -> float:
	var dmg: Array = r.get("damage", [])
	if dmg.is_empty():
		return 0.0
	var s := 0.0
	for z in dmg:
		s += float(z)
	return s / dmg.size()


static func tyre_wear_avg(r: Dictionary) -> float:
	var s := 0.0
	for w in r.tyre_wear:
		s += float(w)
	return s / 4.0


static func repair_cost(r: Dictionary) -> int:
	var d := damage_total(r)
	return 0 if d <= 0.001 else maxi(1, ceili(d * 10.0) * REPAIR_COST_PER_10)


## Rolls everyone's offers (and pays interest); the AI shop straight away.
static func _prepare_shop() -> void:
	var round_i := race_index - 1
	for k in racers.size():
		var r := racers[k]
		if int((r.unlocks as Dictionary).get("interest", 0)) > 0:
			var gain := mini(floori(int(r.wallet) * INTEREST_RATE), INTEREST_CAP)
			if gain > 0:
				r.wallet = int(r.wallet) + gain
				(r.notes as Array).append("Interest: +%d" % gain)
		r.offers = Upgrades.offers(rng, r, round_i, RACES - 1, r.human)
		r.rerolled = false
		if not r.human:
			_ai_shop(r)


## The AI: fresh tyres and repairs when worn / damaged, an X item and a Y
## item if it has none, then the stat cards it can afford (most valuable first).
static func _ai_shop(r: Dictionary) -> void:
	if tyre_wear_avg(r) > 0.3 and int(r.wallet) >= TYRES_COST:
		buy_tyres(r)
	if damage_total(r) > 0.2 and int(r.wallet) >= repair_cost(r):
		repair(r)
	var offers: Array = (r.offers as Array).duplicate()
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Upgrades.cost(a) > Upgrades.cost(b))
	for card: Dictionary in offers:
		var kind := Upgrades.kind_of(card.id)
		if kind == Upgrades.Kind.POWER and r.power_slot != "" and r.power_slot != card.id:
			continue
		if kind == Upgrades.Kind.TACTICAL and r.tactical_slot != "" and r.tactical_slot != card.id:
			continue
		if Upgrades.cost(card) <= int(r.wallet) and rng.randf() < 0.85:
			buy(r, card)


static func buy(r: Dictionary, card: Dictionary) -> bool:
	var c := Upgrades.cost(card)
	if c > int(r.wallet):
		return false
	if not Upgrades.is_stat(card.id) and not Upgrades.can_take(r, card.id):
		return false
	r.wallet = int(r.wallet) - c
	Upgrades.take(r, card)
	(r.offers as Array).erase(card)
	return true


static func buy_tyres(r: Dictionary) -> bool:
	if TYRES_COST > int(r.wallet) or tyre_wear_avg(r) <= 0.001:
		return false
	r.wallet = int(r.wallet) - TYRES_COST
	r.tyre_wear = [0.0, 0.0, 0.0, 0.0]
	return true


static func repair(r: Dictionary) -> bool:
	var c := repair_cost(r)
	if c == 0 or c > int(r.wallet):
		return false
	r.wallet = int(r.wallet) - c
	r.damage = []
	return true


## Rival Bounty: the next racer to aim at (skips yourself).
static func next_rival(r: Dictionary) -> void:
	var me := racers.find(r)
	var k := int(r.rival)
	for step in racers.size():
		k = wrapi(k + 1, 0, racers.size())
		if k != me:
			break
	r.rival = k


static func reroll(r: Dictionary) -> bool:
	var c := reroll_cost(r)
	if c > int(r.wallet):
		return false
	r.wallet = int(r.wallet) - c
	r.rerolled = true
	r.offers = Upgrades.offers(rng, r, race_index - 1, RACES - 1, r.human)
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
