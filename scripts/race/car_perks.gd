class_name CarPerks
extends Node
## Race-time effects of a car's tournament upgrades (Upgrades.apply_to adds
## this as a child of the Vehicle): nitro, slipstream, rocket start, underdog
## power, crash armour / glass cannon, and no driving aids when stripped out.
## Sets vehicle.perk_power / perk_drag / damage_taken every physics tick.

const NITRO_POWER := 1.45
const NITRO_SECONDS := 3.0  ## full bottle, base
const NITRO_REFILL := 0.06  ## bottles per second, base

var owned: Dictionary = {}
## Nitro left, in seconds of boost; capacity in seconds.
var nitro := 0.0
var nitro_capacity := 0.0
var nitro_active := false
var drafting := false

var _car: Vehicle
var _race_start_time := -1.0


func _ready() -> void:
	_car = get_parent() as Vehicle
	if has("nitro"):
		nitro_capacity = NITRO_SECONDS * (1.0 + 0.5 * level("nitro_tank"))
		nitro = nitro_capacity
	if has("armour"):
		_car.damage_taken *= 0.5
	if has("glass"):
		_car.damage_taken *= 2.0


func has(id: String) -> bool:
	return int(owned.get(id, 0)) > 0


func level(id: String) -> int:
	return int(owned.get(id, 0))


func _physics_process(delta: float) -> void:
	if _car == null:
		return
	if has("stripped"):
		_car.assists.traction_control = 0.0
		_car.assists.abs_strength = 0.0
	var power := 1.0
	var drag := 1.0
	var race := get_tree().get_first_node_in_group("race_director") as RaceDirector
	var racing := race == null or race.state != RaceDirector.State.COUNTDOWN
	# Rocket start: a burst for the first 3 s of the race.
	if has("rocket") and race and race.state == RaceDirector.State.RACING and race.race_time < 3.0:
		power *= 1.6
	# Underdog: more power outside the top 3.
	if has("underdog") and race:
		var me := race.index_of(_car)
		if me >= 0 and race.position_of(me) > 3:
			power *= 1.1
	# Slipstream: less drag tucked in behind another car.
	drafting = has("slipstream") and _behind_a_car()
	if drafting:
		drag *= 0.65
	# Nitro: held button, while there's some left.
	nitro_active = false
	if nitro_capacity > 0.0 and racing:
		var want := _car.input != null and _car.input.nitro and not _car.controls_locked
		if want and nitro > 0.0 and _car.forward_speed > 3.0:
			nitro = maxf(nitro - delta, 0.0)
			nitro_active = true
			power *= NITRO_POWER
		else:
			var refill := NITRO_REFILL * nitro_capacity
			if has("nitro_drift"):
				var sliding := absf(_car.lateral_speed) > 2.5 and _car.forward_speed > 8.0
				refill *= 1.0 + (5.0 if sliding else 0.0) + (3.0 if _behind_a_car() else 0.0)
			nitro = minf(nitro + refill * delta, nitro_capacity)
	_car.perk_power = power
	_car.perk_drag = drag


## True if another car is close ahead (within 28 m, roughly in line).
func _behind_a_car() -> bool:
	var fwd := -_car.global_basis.z
	for node in get_tree().get_nodes_in_group("vehicles"):
		var other := node as Vehicle
		if other == null or other == _car:
			continue
		var to := other.global_position - _car.global_position
		var d := to.length()
		if d < 4.0 or d > 28.0:
			continue
		if to.normalized().dot(fwd) > 0.97:
			return true
	return false
