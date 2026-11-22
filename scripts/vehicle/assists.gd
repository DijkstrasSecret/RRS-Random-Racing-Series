class_name HandlingAssists
extends RefCounted
## The "semi-arcade" layer (design concept §6.3). These are corrective forces
## and input shaping on top of the physics, never replacements for it.

enum Profile { ARCADE, SPORT, SIM }
const PROFILE_NAMES: PackedStringArray = ["Arcade", "Sport", "Sim"]

var profile: int = Profile.SPORT
## Full steering lock at speed = this × the angle the tyres can actually use.
## 1 = hard to overdo, 2+ = full lock at speed easily breaks traction.
var steer_overdrive: float = 1.8
## How strongly the front wheels ease toward the direction of travel in slides.
var counter_steer: float = 0.3
## Yaw damping when the car rotates more than the steering asks for.
var stability: float = 0.3
var traction_control: float = 0.5
var abs_strength: float = 0.8
## Fraction of peak grip a sliding tyre keeps.
var tire_falloff: float = 0.85
var air_control: float = 0.5

var _tc_factor: float = 1.0


func set_profile(p: int) -> void:
	profile = p
	match p:
		Profile.ARCADE:
			_apply(1.3, 0.55, 0.6, 1.0, 1.0, 0.9, 1.0)
		Profile.SIM:
			_apply(2.3, 0.0, 0.0, 0.0, 1.0, 0.7, 0.0)
		_:
			profile = Profile.SPORT
			_apply(1.8, 0.3, 0.3, 0.5, 0.8, 0.85, 0.5)


func profile_name() -> String:
	return PROFILE_NAMES[profile]


func _apply(overdrive: float, counter: float, stab: float, tc: float,
		abs_value: float, falloff: float, air: float) -> void:
	steer_overdrive = overdrive
	counter_steer = counter
	stability = stab
	traction_control = tc
	abs_strength = abs_value
	tire_falloff = falloff
	air_control = air


## Front wheel angle (radians, + = right) for a steering input in -1..1.
## The lock shrinks with speed so that full input asks for `steer_overdrive`
## times the angle the tyres can hold: gentle inputs stay in grip, a big
## yank at high speed breaks traction. Low speed keeps nearly full lock.
func steer_target(input: float, v_long: float, v_lat: float, max_steer: float,
		wheelbase: float, grip: float) -> float:
	var limit := steer_limit(v_long, max_steer, wheelbase, grip)
	var target := input * limit
	if counter_steer > 0.0 and v_long > 3.0:
		# Body slip angle: + when the car travels to the right of where it points.
		var beta := atan2(v_lat, v_long)
		var dead := deg_to_rad(4.0)
		if absf(beta) > dead:
			target += (beta - signf(beta) * dead) * counter_steer
	return clampf(target, -max_steer, max_steer)


## Largest front wheel angle (radians) full steering input gives at this speed.
func steer_limit(v_long: float, max_steer: float, wheelbase: float, grip: float) -> float:
	var v := maxf(absf(v_long), 1.0)
	var grip_angle := wheelbase * grip * 9.81 / (v * v) + deg_to_rad(2.0)
	return clampf(grip_angle * steer_overdrive, deg_to_rad(3.0), max_steer)


## Throttle multiplier (0..1) from the driven wheels' slip last tick.
func traction_factor(driven: Array, peak_slip: float) -> float:
	var target := 1.0
	if traction_control > 0.0:
		var worst := 0.0
		for w in driven:
			worst = maxf(worst, absf(w.slip_ratio))
		var excess := clampf((worst - peak_slip * 1.3) / (peak_slip * 1.5), 0.0, 1.0)
		target = 1.0 - excess * traction_control * 0.9
	_tc_factor = lerpf(_tc_factor, target, 0.35)
	return _tc_factor


## Brake torque multiplier (0..1). `slip` is the slip ratio signed so that
## negative = wheel turning slower than the ground (locking).
func abs_factor(slip: float, peak_slip: float) -> float:
	if abs_strength <= 0.0:
		return 1.0
	var excess := clampf((-slip - peak_slip * 1.3) / (peak_slip * 2.0), 0.0, 1.0)
	return 1.0 - excess * abs_strength * 0.85
