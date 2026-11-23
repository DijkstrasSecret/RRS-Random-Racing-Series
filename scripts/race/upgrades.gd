class_name Upgrades
extends RefCounted
## Tournament shop cards (see docs/tournament_upgrades.md):
## - STAT cards in four rarities (Common x1, Rare x1.5, Epic x2, Legendary x3);
##   the rarity scales both the effect and the price. Additive stats add up,
##   reductions stack multiplicatively (never reach 100%).
## - UNLOCK cards: skill passives (max 4), Power actives (X slot), Tactical
##   actives (Y slot), risks and economy. Buying one you own levels it up;
##   a different active for a slot replaces the old one.
## Every shop offers 2 stat cards and 2 unlock cards; rarer stat cards show
## up more often in later rounds.
## apply_to() gives a car its stats (on a private copy of its VehicleConfig)
## and a CarPerks node for the race-time effects.

enum Kind { STAT, PASSIVE, POWER, TACTICAL, RISK, ECONOMY }
const KIND_NAMES: PackedStringArray = ["STAT", "SKILL PASSIVE", "POWER  ·  X", "TACTICAL  ·  Y", "RISK", "ECONOMY"]
const KIND_COLORS: PackedColorArray = [Color(0.35, 0.7, 1.0), Color(0.55, 0.9, 0.4), Color(1.0, 0.45, 0.85),
		Color(0.3, 0.9, 0.85), Color(1.0, 0.55, 0.2), Color(1.0, 0.82, 0.25)]

const TIER_NAMES: PackedStringArray = ["COMMON", "RARE", "EPIC", "LEGENDARY"]
const TIER_MULT: PackedFloat32Array = [1.0, 1.5, 2.0, 3.0]
const TIER_COLORS: PackedColorArray = [Color(0.75, 0.77, 0.8), Color(0.3, 0.6, 1.0), Color(0.7, 0.4, 1.0), Color(1.0, 0.65, 0.15)]
## Rarity odds [common, rare, epic, legendary] for the first and the last shop
## (in between they blend).
const ODDS_FIRST: PackedFloat32Array = [0.70, 0.25, 0.05, 0.0]
const ODDS_LAST: PackedFloat32Array = [0.30, 0.35, 0.25, 0.10]

const MAX_PASSIVES := 4
const MAX_LEVEL := 3

## Stat cards: base value (fraction), whether it's a reduction (multiplicative),
## base price.
const STATS := {
	"power": {"name": "POWER", "value": 0.03, "reduce": false, "cost": 6, "fmt": "+%s%% engine torque"},
	"top_speed": {"name": "TOP SPEED", "value": 0.02, "reduce": false, "cost": 5, "fmt": "+%s%% top speed"},
	"grip": {"name": "GRIP", "value": 0.03, "reduce": false, "cost": 6, "fmt": "+%s%% cornering grip"},
	"braking": {"name": "BRAKING", "value": 0.04, "reduce": false, "cost": 4, "fmt": "+%s%% brake force"},
	"weight": {"name": "WEIGHT", "value": 0.02, "reduce": true, "cost": 5, "fmt": "-%s%% weight"},
	"tire_pres": {"name": "TIRE PRESERVATION", "value": 0.15, "reduce": true, "cost": 4, "fmt": "-%s%% tyre wear"},
	"durability": {"name": "DURABILITY", "value": 0.03, "reduce": true, "cost": 4, "fmt": "-%s%% damage taken"},
}

## Unlock cards. "max" 1 = can't level up; "consumable" = bought fresh each time.
const UNLOCKS := {
	# Skill passives (max 4 owned).
	"perfect_shift": {"name": "PERFECT SHIFT", "kind": Kind.PASSIVE, "cost": 10,
		"desc": "Upshift (RB / E) right at the redline: a short torque boost. Levels widen the window."},
	"heel_toe": {"name": "HEEL-TOE", "kind": Kind.PASSIVE, "cost": 9,
		"desc": "Downshift (LB / Q) while braking: steadies the rear and fills a meter. Full meter: extra grip out of the next corner."},
	"drift_harvest": {"name": "DRIFT HARVEST", "kind": Kind.PASSIVE, "cost": 9,
		"desc": "Long handbrake slides (A / Space) charge your X item."},
	"late_braker": {"name": "LATE BRAKER", "kind": Kind.PASSIVE, "cost": 9,
		"desc": "Brake late for a corner: extra grip on the way out."},
	"clean_sector": {"name": "CLEAN SECTOR", "kind": Kind.PASSIVE, "cost": 10,
		"desc": "No wall contact for 8 s: your X item slowly recharges."},
	# Power actives (X).
	"nitro_burst": {"name": "NITRO: BURST", "kind": Kind.POWER, "cost": 10,
		"desc": "X: one big 2.5 s nitro burst (+55% power)."},
	"nitro_charges": {"name": "NITRO: CHARGES", "kind": Kind.POWER, "cost": 10,
		"desc": "X: three short 1 s boosts (+45% power)."},
	"nitro_regen": {"name": "NITRO: REGEN", "kind": Kind.POWER, "cost": 9,
		"desc": "Hold X: a small nitro bottle (+35%) that refills by itself."},
	"kers": {"name": "KERS", "kind": Kind.POWER, "cost": 11,
		"desc": "Braking stores energy; hold X to deploy it (+40% power)."},
	"push_to_pass": {"name": "PUSH-TO-PASS", "kind": Kind.POWER, "cost": 8,
		"desc": "X: 3 uses per race, 3 s of +25% power each."},
	# Tactical actives (Y).
	"engine_map": {"name": "ENGINE MAP", "kind": Kind.TACTICAL, "cost": 9,
		"desc": "Y: switch POWER map (+6% power) / STABILITY map (traction control, steadier rear)."},
	"drs": {"name": "DRS", "kind": Kind.TACTICAL, "cost": 11,
		"desc": "Hold Y within 1 s of the car ahead: -22% drag (more top speed). Closes when you brake."},
	# Risk / curse.
	"overbored": {"name": "OVERBORED ENGINE", "kind": Kind.RISK, "cost": 8, "max": 1,
		"desc": "+12% power, but sitting on the redline overheats the engine and damages it."},
	"stripped": {"name": "STRIPPED INTERIOR", "kind": Kind.RISK, "cost": 8, "max": 1,
		"desc": "-12% weight, but wall hits cost you more speed."},
	"bet": {"name": "BET ON YOURSELF", "kind": Kind.RISK, "cost": 6, "max": 1, "consumable": true,
		"desc": "Stake 6 points: a podium next race pays 12, anything else loses the stake."},
	# Economy.
	"interest": {"name": "INTEREST", "kind": Kind.ECONOMY, "cost": 8, "max": 1,
		"desc": "Unspent points grow 10% every round (up to +10)."},
	"rival_bounty": {"name": "RIVAL BOUNTY", "kind": Kind.ECONOMY, "cost": 6, "max": 1,
		"desc": "Pick a rival in the shop. Beat them in a race: +6 points."},
}


static func is_stat(id: String) -> bool:
	return STATS.has(id)


static func card_name(card: Dictionary) -> String:
	var id: String = card.id
	return String(STATS[id].name) if is_stat(id) else String(UNLOCKS[id].name)


static func kind_of(id: String) -> int:
	return Kind.STAT if is_stat(id) else int(UNLOCKS[id].kind)


## Value of a stat card (fraction), e.g. legendary tyre preservation = 0.45.
static func stat_value(id: String, tier: int) -> float:
	return float(STATS[id].value) * TIER_MULT[tier]


static func cost(card: Dictionary) -> int:
	var id: String = card.id
	if is_stat(id):
		return roundi(int(STATS[id].cost) * TIER_MULT[int(card.tier)])
	return int(UNLOCKS[id].cost)


static func describe_card(card: Dictionary) -> String:
	var id: String = card.id
	if is_stat(id):
		var v := stat_value(id, int(card.tier)) * 100.0
		var txt := ("%.1f" % v).trim_suffix(".0")
		return String(STATS[id].fmt) % txt
	return String(UNLOCKS[id].desc)


## Rarity odds for shop number `round_i` of `rounds` (0 = first).
static func odds(round_i: int, rounds: int) -> PackedFloat32Array:
	var t := clampf(float(round_i) / maxf(rounds - 1, 1), 0.0, 1.0)
	var out := PackedFloat32Array()
	for k in 4:
		out.append(lerpf(ODDS_FIRST[k], ODDS_LAST[k], t))
	return out


static func roll_tier(rng: RandomNumberGenerator, round_i: int, rounds: int) -> int:
	var o := odds(round_i, rounds)
	var x := rng.randf()
	for k in 4:
		x -= o[k]
		if x <= 0.0:
			return k
	return 0


## The level a racer has of an unlock (0 = not owned). Passives, risks and
## economy live in `unlocks`; the X / Y items in their slots.
static func level_of(r: Dictionary, id: String) -> int:
	if r.get("power_slot", "") == id:
		return int(r.get("power_level", 1))
	if r.get("tactical_slot", "") == id:
		return int(r.get("tactical_level", 1))
	return int((r.get("unlocks", {}) as Dictionary).get(id, 0))


static func passive_count(r: Dictionary) -> int:
	var n := 0
	var owned: Dictionary = r.get("unlocks", {})
	for id: String in owned:
		if int(UNLOCKS[id].kind) == Kind.PASSIVE and int(owned[id]) > 0:
			n += 1
	return n


## True if this racer can take the unlock (not maxed, passive slots left,
## a bet not already running).
static func can_take(r: Dictionary, id: String) -> bool:
	var u: Dictionary = UNLOCKS[id]
	var lvl := level_of(r, id)
	if u.get("consumable", false):
		return int(r.get("bet", 0)) == 0
	if lvl >= int(u.get("max", MAX_LEVEL)):
		return false
	if int(u.kind) == Kind.PASSIVE and lvl == 0 and passive_count(r) >= MAX_PASSIVES:
		return false
	return true


## A fresh shop: 2 stat cards and 2 unlock cards (different ids). Cards are
## {id, tier} (tier -1 for unlocks).
static func offers(rng: RandomNumberGenerator, r: Dictionary, round_i: int, rounds: int, human: bool = true) -> Array:
	var out: Array = []
	var stats := STATS.keys()
	for k in 2:
		var id: String = stats[rng.randi() % stats.size()]
		stats.erase(id)
		out.append({"id": id, "tier": roll_tier(rng, round_i, rounds)})
	var pool: Array[String] = []
	for id: String in UNLOCKS:
		var kind := int(UNLOCKS[id].kind)
		# The AI only uses the X / Y items.
		if not human and kind != Kind.POWER and kind != Kind.TACTICAL:
			continue
		if can_take(r, id):
			pool.append(id)
	for k in 2:
		if pool.is_empty():
			break
		var id: String = pool[rng.randi() % pool.size()]
		pool.erase(id)
		out.append({"id": id, "tier": -1})
	return out


## Buys `card` for racer `r` (points already checked): stats are added,
## unlocks taken / levelled / slotted.
static func take(r: Dictionary, card: Dictionary) -> void:
	var id: String = card.id
	if is_stat(id):
		(r.stats as Array).append({"id": id, "tier": int(card.tier)})
		return
	var kind := int(UNLOCKS[id].kind)
	if kind == Kind.POWER:
		if r.power_slot == id:
			r.power_level = mini(int(r.power_level) + 1, MAX_LEVEL)
		else:
			r.power_slot = id
			r.power_level = 1
	elif kind == Kind.TACTICAL:
		if r.tactical_slot == id:
			r.tactical_level = mini(int(r.tactical_level) + 1, MAX_LEVEL)
		else:
			r.tactical_slot = id
			r.tactical_level = 1
	elif UNLOCKS[id].get("consumable", false):
		r.bet = int(UNLOCKS[id].cost)
	else:
		r.unlocks[id] = int(r.unlocks.get(id, 0)) + 1


## Total of an additive stat, e.g. 0.075 = +7.5%.
static func stat_total(r: Dictionary, id: String) -> float:
	var total := 0.0
	for s: Dictionary in r.get("stats", []):
		if s.id == id:
			total += stat_value(id, int(s.tier))
	return total


## Multiplier left after reductions, e.g. tyre wear: 1 - (1 - 0.45)(1 - 0.3) -> 0.385.
static func stat_scale(r: Dictionary, id: String) -> float:
	var keep := 1.0
	for s: Dictionary in r.get("stats", []):
		if s.id == id:
			keep *= 1.0 - stat_value(id, int(s.tier))
	return keep


## Gives `car` (not in the scene yet, config already set) its stats and the
## race-time effects of its unlocks.
static func apply_to(car: Vehicle, r: Dictionary) -> void:
	if r.is_empty():
		return
	var c := car.config.duplicate() as VehicleConfig
	var lv := func(id: String) -> int: return level_of(r, id)
	c.max_torque *= (1.0 + stat_total(r, "power")) * (1.12 if lv.call("overbored") > 0 else 1.0)
	# Top speed: less drag (speed is power-limited at the top: drag goes with v^3)
	# and a slightly longer final drive so the top gear has room.
	var ts := 1.0 + stat_total(r, "top_speed")
	c.drag_area /= pow(ts, 3.0)
	c.final_drive /= ts
	c.tire_grip *= 1.0 + stat_total(r, "grip")
	c.brake_torque *= 1.0 + stat_total(r, "braking")
	c.mass *= stat_scale(r, "weight") * (0.88 if lv.call("stripped") > 0 else 1.0)
	car.config = c
	var perks := CarPerks.new()
	perks.name = "Perks"
	perks.racer = r
	car.add_child(perks)


## Short list of what a racer has, e.g. "X NITRO: BURST II, PERFECT SHIFT, 5 stat cards".
static func describe(r: Dictionary) -> String:
	var parts := PackedStringArray()
	if r.get("power_slot", "") != "":
		parts.append("X " + String(UNLOCKS[r.power_slot].name) + _roman(int(r.power_level)))
	if r.get("tactical_slot", "") != "":
		parts.append("Y " + String(UNLOCKS[r.tactical_slot].name) + _roman(int(r.tactical_level)))
	var owned: Dictionary = r.get("unlocks", {})
	for id: String in owned:
		if int(owned[id]) > 0:
			parts.append(String(UNLOCKS[id].name) + _roman(int(owned[id])))
	var n := (r.get("stats", []) as Array).size()
	if n > 0:
		parts.append("%d stat card%s" % [n, "" if n == 1 else "s"])
	return ", ".join(parts)


static func _roman(level: int) -> String:
	return ["", "", " II", " III"][clampi(level, 0, 3)]
