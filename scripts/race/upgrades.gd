class_name Upgrades
extends RefCounted
## Tournament upgrades (roguelike): car parts, race perks, nitro and risky
## trade-offs. Bought between races with points; stack up to `max` times.
## apply_to() gives a car its upgrades before it enters the scene: tuning
## changes go on a private copy of its VehicleConfig, race-time effects
## (nitro, slipstream, rocket start...) come from a CarPerks node.

enum Kind { PART, PERK, NITRO, RISKY }
const KIND_NAMES: PackedStringArray = ["CAR PART", "RACE PERK", "NITRO", "RISKY"]
const KIND_COLORS: PackedColorArray = [Color(0.35, 0.7, 1.0), Color(0.55, 0.9, 0.4), Color(1.0, 0.45, 0.85), Color(1.0, 0.55, 0.2)]

## id: name, kind, cost, max stacks, description, needs (another upgrade).
const ALL := {
	"engine": {"name": "ENGINE TUNE", "kind": Kind.PART, "cost": 8, "max": 3, "desc": "+8% engine power."},
	"tyres": {"name": "SPORT TYRES", "kind": Kind.PART, "cost": 8, "max": 3, "desc": "+5% tyre grip."},
	"brakes": {"name": "RACE BRAKES", "kind": Kind.PART, "cost": 5, "max": 2, "desc": "+18% braking power."},
	"weight": {"name": "LIGHTWEIGHT", "kind": Kind.PART, "cost": 7, "max": 2, "desc": "-6% weight: quicker everywhere."},
	"aero": {"name": "AERO KIT", "kind": Kind.PART, "cost": 6, "max": 2, "desc": "More downforce in fast corners, a little more drag."},
	"gearbox": {"name": "CLOSE GEARS", "kind": Kind.PART, "cost": 5, "max": 2, "desc": "+5% acceleration, slightly lower top speed."},
	"suspension": {"name": "STIFF SUSPENSION", "kind": Kind.PART, "cost": 4, "max": 1, "desc": "Less body roll, sharper turn-in."},
	"rocket": {"name": "ROCKET START", "kind": Kind.PERK, "cost": 5, "max": 1, "desc": "+60% power for 3 s after the start."},
	"slipstream": {"name": "SLIPSTREAM", "kind": Kind.PERK, "cost": 6, "max": 1, "desc": "-35% drag when tucked in behind a car."},
	"armour": {"name": "ROLL CAGE", "kind": Kind.PERK, "cost": 4, "max": 1, "desc": "Takes half the crash damage."},
	"underdog": {"name": "UNDERDOG", "kind": Kind.PERK, "cost": 6, "max": 1, "desc": "+10% power while outside the top 3."},
	"nitro": {"name": "NITRO KIT", "kind": Kind.NITRO, "cost": 7, "max": 1, "desc": "Nitro bottle: +45% power while held (Shift / X). Refills slowly."},
	"nitro_tank": {"name": "BIGGER BOTTLE", "kind": Kind.NITRO, "cost": 5, "max": 2, "needs": "nitro", "desc": "+50% nitro capacity."},
	"nitro_drift": {"name": "DRIFT REFILL", "kind": Kind.NITRO, "cost": 5, "max": 1, "needs": "nitro", "desc": "Sliding and drafting refill the nitro fast."},
	"glass": {"name": "GLASS CANNON", "kind": Kind.RISKY, "cost": 6, "max": 1, "desc": "+18% power, but crashes do double damage."},
	"wing": {"name": "BIG WING", "kind": Kind.RISKY, "cost": 5, "max": 1, "desc": "+8% grip, but +14% drag (lower top speed)."},
	"stripped": {"name": "STRIPPED OUT", "kind": Kind.RISKY, "cost": 5, "max": 1, "desc": "-12% weight, but no traction control or ABS."},
	"long_gears": {"name": "LONG GEARS", "kind": Kind.RISKY, "cost": 4, "max": 1, "desc": "+7% top speed, -7% acceleration."},
}


## Up to `count` random upgrades this racer can still buy (not maxed out,
## prerequisites owned), weighted towards cheaper ones a little.
static func offers(rng: RandomNumberGenerator, owned: Dictionary, count: int = 3) -> PackedStringArray:
	var pool: Array[String] = []
	for id: String in ALL:
		var u: Dictionary = ALL[id]
		if int(owned.get(id, 0)) >= int(u.max):
			continue
		if u.has("needs") and int(owned.get(u.needs, 0)) == 0:
			continue
		pool.append(id)
	var out := PackedStringArray()
	while out.size() < count and not pool.is_empty():
		var k := rng.randi() % pool.size()
		out.append(pool[k])
		pool.remove_at(k)
	return out


static func cost(id: String) -> int:
	return int(ALL[id].cost)


## Gives `car` (not in the scene yet, config already set) its upgrades.
static func apply_to(car: Vehicle, owned: Dictionary) -> void:
	if owned.is_empty():
		return
	var c := car.config.duplicate() as VehicleConfig
	var n := func(id: String) -> int: return int(owned.get(id, 0))
	c.max_torque *= pow(1.08, n.call("engine")) * (1.18 if n.call("glass") > 0 else 1.0)
	c.tire_grip *= pow(1.05, n.call("tyres")) * (1.08 if n.call("wing") > 0 else 1.0)
	c.brake_torque *= pow(1.18, n.call("brakes"))
	var mass_scale := pow(0.94, n.call("weight")) * (0.88 if n.call("stripped") > 0 else 1.0)
	c.mass *= mass_scale
	c.downforce_area += 0.25 * n.call("aero") + (0.3 if n.call("wing") > 0 else 0.0)
	c.drag_area *= pow(1.03, n.call("aero")) * (1.14 if n.call("wing") > 0 else 1.0)
	c.final_drive *= pow(1.05, n.call("gearbox")) * (0.93 if n.call("long_gears") > 0 else 1.0)
	if n.call("suspension") > 0:
		c.front_anti_roll *= 1.35
		c.rear_anti_roll *= 1.35
		c.front_spring_rate *= 1.15
		c.rear_spring_rate *= 1.15
	car.config = c
	var perks := CarPerks.new()
	perks.name = "Perks"
	perks.owned = owned.duplicate()
	car.add_child(perks)


## Short list of what a racer owns, e.g. "ENGINE TUNE x2, NITRO KIT".
static func describe(owned: Dictionary) -> String:
	var parts := PackedStringArray()
	for id: String in owned:
		if int(owned[id]) > 0:
			parts.append(String(ALL[id].name) + (" x%d" % int(owned[id]) if int(owned[id]) > 1 else ""))
	return ", ".join(parts)
