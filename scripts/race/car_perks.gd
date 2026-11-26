class_name CarPerks
extends Node
## Race-time effects of a racer's tournament cards (Upgrades.apply_to adds
## this as a child of the Vehicle):
## - X (Power) item: nitro burst / charges / regen, KERS, push-to-pass. All
##   run on "energy" = seconds of boost left; passives can add to it.
## - Y (Tactical) item: engine map (power / stability), DRS.
## - Skill passives: perfect shift, heel-toe, drift harvest, late braker,
##   clean sector. Risks: overbored engine, stripped interior.
## - Stat cards for tyre wear and damage, and the tyre wear / damage carried
##   over from the last race (set on the first physics tick, after the car).
## Sets vehicle.perk_power / perk_drag and each wheel's perk_grip every tick.

## X items: how they fire (hold = while held, pulse = a press fires `len`
## seconds), boost (power multiplier), energy capacity / start, refill.
const POWER := {
	"nitro_burst": {"mode": "pulse", "boost": 1.55, "len": 2.5, "len_lvl": 0.5, "uses": 1, "uses_lvl": 0},
	"nitro_charges": {"mode": "pulse", "boost": 1.45, "len": 1.0, "len_lvl": 0.0, "uses": 3, "uses_lvl": 1},
	"nitro_regen": {"mode": "hold", "boost": 1.35, "cap": 1.5, "cap_lvl": 0.5, "regen": 0.12},
	"kers": {"mode": "hold", "boost": 1.4, "cap": 2.0, "cap_lvl": 0.5, "empty": true},
	"push_to_pass": {"mode": "pulse", "boost": 1.25, "len": 3.0, "len_lvl": 0.0, "uses": 3, "uses_lvl": 1},
}
const DRS_GAP := 1.0      ## seconds to the car ahead
const DRS_DRAG := 0.78
const HEAT_LIMIT := 2.0   ## seconds on the redline before an overbored engine cooks
const CLEAN_TIME := 8.0

var racer: Dictionary = {}

## X item state.
var power_id := ""
var power_level := 0
var energy := 0.0
var capacity := 0.0
var boosting := false
var _pulse_left := 0.0
var _x_was_down := false

## Y item state.
var tactical_id := ""
var tactical_level := 0
var map_stability := false
var drs_available := false
var drs_open := false

## Passive state (for the HUD).
var shift_bonus := 0.0      ## seconds of perfect-shift boost left
var heel_meter := 0.0       ## 0..1
var heel_armed := false
var grip_bonus := 0.0       ## seconds of exit grip left (heel-toe / late braker)
var late_armed := false
var clean_time := 0.0
var engine_heat := 0.0      ## seconds on the redline (overbored)
var wall_contact := false

var _car: Vehicle
var _set_up := false
var _wait_frames := 0
var _stab_left := 0.0
var _slide_time := 0.0
var _prev_rpm_frac := 0.0
var _prev_brake := 0.0
var _was_wall := false
var _base_tc := 0.5
var _base_stability := 0.3


func _ready() -> void:
	_car = get_parent() as Vehicle
	power_id = String(racer.get("power_slot", ""))
	power_level = int(racer.get("power_level", 0))
	tactical_id = String(racer.get("tactical_slot", ""))
	tactical_level = int(racer.get("tactical_level", 0))
	if power_id != "":
		var p: Dictionary = POWER[power_id]
		if p.mode == "pulse":
			capacity = (float(p.len) + float(p.len_lvl) * (power_level - 1)) * (int(p.uses) + int(p.uses_lvl) * (power_level - 1))
		else:
			capacity = float(p.cap) + float(p.cap_lvl) * (power_level - 1)
		energy = 0.0 if p.get("empty", false) else capacity
	if level("clean_sector") > 0 or level("stripped") > 0:
		_car.contact_monitor = true
		_car.max_contacts_reported = maxi(_car.max_contacts_reported, 6)


## Level of item `id` for this car's racer (0 = not owned).
func level(id: String) -> int:
	return Upgrades.level_of(racer, id)


## Seconds of boost one X press gives (pulse items), 0 for hold items.
func pulse_length() -> float:
	if power_id == "" or POWER[power_id].mode != "pulse":
		return 0.0
	var p: Dictionary = POWER[power_id]
	return float(p.len) + float(p.len_lvl) * (power_level - 1)


## Energy that passives give the X item (seconds of boost).
func charge(amount: float) -> void:
	if capacity > 0.0:
		energy = minf(energy + amount, capacity)


func _setup_once() -> void:
	_set_up = true
	_base_tc = _car.assists.traction_control
	_base_stability = _car.assists.stability
	var keep_wear := Upgrades.stat_scale(racer, "tire_pres")
	for w in _car.wheels:
		w.wear_rate *= keep_wear
	_car.damage_taken *= Upgrades.stat_scale(racer, "durability")
	Tournament.restore_car(racer, _car)


func _physics_process(delta: float) -> void:
	if _car == null:
		return
	if not _set_up:
		# Wait for the car's damage model (it's set up a frame late) so the
		# carried-over damage lands on it.
		_wait_frames += 1
		if _car.damage != null or GameSettings.damage <= 0 or _wait_frames > 30:
			_setup_once()
	var race := get_tree().get_first_node_in_group("race_director") as RaceDirector
	var racing := (race == null or race.state != RaceDirector.State.COUNTDOWN) and not _car.controls_locked
	var input := _car.input
	var v := _car.forward_speed
	var power := 1.0
	var drag := 1.0
	var grip := 1.0
	var rear_grip := 1.0
	var rpm_frac := _car.drivetrain.rpm / maxf(_car.config.redline_rpm, 1.0)
	var brake := input.brake if input else 0.0
	var throttle := input.throttle if input else 0.0

	_update_walls()

	# --- X item.
	boosting = false
	if power_id != "" and racing and input:
		var p: Dictionary = POWER[power_id]
		var down := input.nitro
		if p.mode == "hold":
			if down and energy > 0.0 and v > 3.0:
				energy = maxf(energy - delta, 0.0)
				boosting = true
			elif power_id == "nitro_regen":
				charge(float(p.regen) * capacity * delta)
		else:
			# A press fires one pulse (the AI just holds the button).
			var press := down and (not _x_was_down or _car.input is AIDriver)
			if _pulse_left <= 0.0 and press and energy >= pulse_length() * 0.98 and v > 3.0:
				_pulse_left = minf(pulse_length(), energy)
			if _pulse_left > 0.0:
				_pulse_left -= delta
				energy = maxf(energy - delta, 0.0)
				boosting = true
		if power_id == "kers" and brake > 0.2 and v > 5.0:
			charge(brake * v * delta * 0.012 * (1.0 + 0.25 * (power_level - 1)))
		if boosting:
			power *= float(p.boost) + (0.05 * (power_level - 1) if p.mode == "hold" else 0.0)
		_x_was_down = down

	# --- Y item.
	drs_available = false
	if tactical_id == "engine_map" and input:
		if input.tactical_pressed:
			map_stability = not map_stability
		if map_stability:
			power *= 0.96
			rear_grip *= 1.05 + 0.02 * (tactical_level - 1)
			_car.assists.traction_control = maxf(_base_tc, 0.85)
			_car.assists.stability = maxf(_base_stability, 0.6)
		else:
			power *= 1.06 + 0.02 * (tactical_level - 1)
			_car.assists.traction_control = _base_tc
			_car.assists.stability = _base_stability
	elif tactical_id == "drs" and race and input:
		var gap := _gap_ahead(race)
		drs_available = gap < DRS_GAP + 0.2 * (tactical_level - 1) and v > 15.0
		if input.tactical and brake < 0.1 and (drs_open or drs_available):
			drs_open = true
		else:
			drs_open = false
		if drs_open:
			drag *= DRS_DRAG - 0.03 * (tactical_level - 1)

	# --- Skill passives.
	if level("perfect_shift") > 0 and input and input.shift_up_pressed:
		var window := 0.94 - 0.025 * (level("perfect_shift") - 1)
		if _prev_rpm_frac >= window:
			shift_bonus = 1.0
	if shift_bonus > 0.0:
		shift_bonus -= delta
		power *= 1.12 + 0.03 * (level("perfect_shift") - 1)

	if level("heel_toe") > 0 and input:
		if input.shift_down_pressed and brake > 0.3 and v > 8.0:
			_stab_left = 0.8
			heel_meter = minf(heel_meter + 0.34 + 0.08 * (level("heel_toe") - 1), 1.0)
			if heel_meter >= 1.0:
				heel_armed = true
		if heel_armed and brake < 0.05 and throttle > 0.5:
			heel_armed = false
			heel_meter = 0.0
			grip_bonus = maxf(grip_bonus, 2.0)
	if _stab_left > 0.0:
		_stab_left -= delta
		rear_grip *= 1.06

	if level("drift_harvest") > 0 and input:
		var sliding := input.handbrake > 0.5 and absf(_car.lateral_speed) > 3.0 and v > 8.0
		_slide_time = _slide_time + delta if sliding else 0.0
		if _slide_time > 0.4:
			charge((0.35 + 0.12 * (level("drift_harvest") - 1)) * delta)

	if level("late_braker") > 0 and input:
		if brake > 0.6 and _prev_brake < 0.2 and v > 20.0:
			var d := _distance_to_corner()
			late_armed = d < v * (1.6 + 0.15 * (level("late_braker") - 1))
		if late_armed and brake < 0.05:
			late_armed = false
			grip_bonus = maxf(grip_bonus, 1.8)

	if level("clean_sector") > 0:
		clean_time = 0.0 if wall_contact else clean_time + delta
		if clean_time > CLEAN_TIME - (level("clean_sector") - 1):
			charge((0.06 + 0.03 * (level("clean_sector") - 1)) * delta)

	if grip_bonus > 0.0:
		grip_bonus -= delta
		grip *= 1.08 + 0.02 * maxi(level("heel_toe"), level("late_braker")) - 0.02

	# --- Risks.
	if level("overbored") > 0 and racing:
		engine_heat = engine_heat + delta if rpm_frac > 0.95 and throttle > 0.5 else maxf(engine_heat - delta * 0.5, 0.0)
		if engine_heat > HEAT_LIMIT and _car.damage:
			_car.damage.engine_heat(0.05 * delta * Upgrades.stat_scale(racer, "durability"))
	if level("stripped") > 0 and wall_contact and not _was_wall:
		_car.linear_velocity *= 0.88  # no padding: walls bite

	_was_wall = wall_contact
	_prev_rpm_frac = rpm_frac
	_prev_brake = brake
	_car.perk_power = power
	_car.perk_drag = drag
	for w in _car.wheels:
		w.perk_grip = grip * (1.0 if w.is_front else rear_grip)


## Touching a wall / barrier (not the ground, not another car) this tick.
func _update_walls() -> void:
	wall_contact = false
	if not _car.contact_monitor:
		return
	for b in _car.get_colliding_bodies():
		if b is Vehicle or b.has_meta(&"surface_grip"):
			continue
		wall_contact = true
		return


## Seconds to the car just ahead on the road (INF if none).
func _gap_ahead(race: RaceDirector) -> float:
	var me := race.index_of(_car)
	if me < 0:
		return INF
	var mine := race._race_distance(me)
	var best := INF
	for j in race.car_count():
		if j == me:
			continue
		var d := race._race_distance(j) - mine
		if d > 0.0 and d < best:
			best = d
	return best / maxf(_car.forward_speed, 1.0)


## Metres to the next real corner ahead (or a long way).
func _distance_to_corner() -> float:
	var circuit := get_tree().get_first_node_in_group("circuit") as Circuit
	if circuit == null:
		return INF
	var off := circuit.progress_at(_car.global_position)
	var d := 5.0
	while d < 260.0:
		if absf(circuit.curvature_at(off + d)) > 1.0 / 70.0:
			return d
		d += 5.0
	return INF
