class_name Drivetrain
extends RefCounted
## Engine -> clutch -> gearbox -> final drive (design concept §6.2).
## The differential split is done by the Vehicle.

const RAD_S_TO_RPM := 60.0 / TAU

var config: VehicleConfig
## -1 = reverse, 0 = neutral, 1..n = forward gears.
var gear: int = 1
var rpm: float = 900.0
var automatic: bool = true
var shift_timer: float = 0.0
var clutch_slipping: bool = false


func setup(cfg: VehicleConfig) -> void:
	config = cfg
	reset()


func reset() -> void:
	gear = 1
	rpm = config.idle_rpm
	shift_timer = 0.0
	clutch_slipping = false


func gear_count() -> int:
	return config.gear_ratios.size()


## Overall ratio from engine to wheels (negative in reverse).
func gear_ratio() -> float:
	if gear > 0:
		return config.gear_ratios[gear - 1] * config.final_drive
	if gear < 0:
		return -config.reverse_ratio * config.final_drive
	return 0.0


func gear_label() -> String:
	if gear < 0:
		return "R"
	if gear == 0:
		return "N"
	if config.electric:
		return "D"
	return str(gear)


func set_gear(new_gear: int) -> void:
	new_gear = clampi(new_gear, -1, gear_count())
	if new_gear == gear:
		return
	gear = new_gear
	shift_timer = config.shift_time


func shift_up() -> void:
	set_gear(gear + 1)


func shift_down() -> void:
	set_gear(gear - 1)


func engine_torque_at(at_rpm: float) -> float:
	var pts := config.torque_curve
	if pts.is_empty():
		return config.max_torque
	if at_rpm <= pts[0].x:
		return pts[0].y * config.max_torque
	for i in range(1, pts.size()):
		if at_rpm <= pts[i].x:
			var a := pts[i - 1]
			var b := pts[i]
			return lerpf(a.y, b.y, (at_rpm - a.x) / (b.x - a.x)) * config.max_torque
	return pts[pts.size() - 1].y * config.max_torque


## Advances the engine by one tick. `wheel_omega` is the mean spin speed of
## the driven wheels (rad/s). Returns the total torque at the driven wheels.
func update(wheel_omega: float, throttle: float, dt: float) -> float:
	var ratio := gear_ratio()
	if shift_timer > 0.0:
		shift_timer -= dt
	var coupled_rpm := wheel_omega * ratio * RAD_S_TO_RPM

	if ratio == 0.0 or shift_timer > 0.0:
		# Clutch open (neutral or mid-shift): the engine revs freely.
		var free_target := lerpf(config.idle_rpm, config.redline_rpm * 0.95, throttle)
		if ratio != 0.0:
			free_target = maxf(coupled_rpm, config.idle_rpm)
		rpm = move_toward(rpm, free_target, 12000.0 * dt)
		clutch_slipping = false
		return 0.0

	var launch := lerpf(config.idle_rpm, config.launch_rpm, throttle)
	clutch_slipping = coupled_rpm < launch
	if clutch_slipping:
		rpm = move_toward(rpm, launch, 9000.0 * dt)
	else:
		rpm = coupled_rpm
	rpm = clampf(rpm, 0.0, config.redline_rpm + 300.0)

	var torque := 0.0
	if throttle > 0.01:
		torque = engine_torque_at(rpm) * throttle
		# Soft rev limiter.
		torque *= clampf((config.redline_rpm - rpm) / 150.0, 0.0, 1.0)
	elif not clutch_slipping:
		torque = -config.engine_brake_torque * clampf(rpm / config.redline_rpm, 0.0, 1.0)
	return torque * ratio * config.drivetrain_efficiency


## Automatic gearbox: shift on engine speed.
func update_auto() -> void:
	if not automatic or gear < 1 or shift_timer > 0.0:
		return
	if rpm > config.auto_upshift_rpm and gear < gear_count() and not clutch_slipping:
		shift_up()
	elif rpm < config.auto_downshift_rpm and gear > 1:
		shift_down()
