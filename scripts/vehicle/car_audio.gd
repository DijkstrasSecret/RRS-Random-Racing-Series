class_name CarAudio
extends Node3D
## Sounds for one car (design concept §11), all in 3D so other cars are heard
## going past (with Doppler shift):
## - engine: four layers recorded at 1500 and 4500 rpm, on and off throttle,
##   pitch-shifted to the real rpm and cross-faded by rpm and throttle
## - tyre squeal when tyres slide or spin on tarmac
## - dirt rumble on grass / gravel, wind at speed, a thud on hard impacts
## The sounds are made by tools/make_sounds.py.

const LOW_RPM := 1500.0
const HIGH_RPM := 4500.0
const DIR := "res://assets/audio/car/"

## Overall loudness of this car (dB).
@export var gain_db: float = 0.0

var _vehicle: Vehicle
var _low_on: AudioStreamPlayer3D
var _low_off: AudioStreamPlayer3D
var _high_on: AudioStreamPlayer3D
var _high_off: AudioStreamPlayer3D
var _squeal: AudioStreamPlayer3D
var _dirt: AudioStreamPlayer3D
var _wind: AudioStreamPlayer3D
var _impact: AudioStreamPlayer3D
var _whine: AudioStreamPlayer3D
var _pitch_mult: float = 1.0
var _electric: bool = false
var _load: float = 0.0
var _squeal_level: float = 0.0
var _prev_velocity := Vector3.ZERO
var _impact_cooldown: float = 0.0


func _ready() -> void:
	add_to_group("car_audio")
	_vehicle = get_parent() as Vehicle
	_low_on = _player("engine_low_on", 14.0)
	_low_off = _player("engine_low_off", 14.0)
	_high_on = _player("engine_high_on", 14.0)
	_high_off = _player("engine_high_off", 14.0)
	_squeal = _player("tire_squeal", 12.0)
	_dirt = _player("dirt_rumble", 9.0)
	_wind = _player("wind", 6.0)
	_impact = _player("impact", 14.0, false)
	_electric = _vehicle.config.electric
	_pitch_mult = _vehicle.config.engine_sound_pitch
	gain_db += _vehicle.config.engine_sound_gain_db
	if _electric:
		_whine = _player("ev_whine", 12.0)


## Sets the volume offset for all this car's sounds, in dB (replaces the car's own engine_sound_gain_db).
func set_gain(db: float) -> void:
	gain_db = db


func _player(file: String, unit_size: float, looping: bool = true) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = file
	p.stream = load(DIR + file + ".wav")
	p.unit_size = unit_size
	p.max_distance = 260.0
	p.attenuation_filter_cutoff_hz = 9000.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	p.volume_db = -80.0
	p.bus = &"SFX"
	add_child(p)
	if looping:
		p.play()
	return p


func _physics_process(delta: float) -> void:
	if _vehicle == null:
		return
	var rpm := _vehicle.drivetrain.rpm
	_load = move_toward(_load, _vehicle.throttle_out, delta * 6.0)

	# --- Engine: equal-power cross-fade between the low and high recordings.
	var x := clampf((rpm - LOW_RPM) / (HIGH_RPM - LOW_RPM), 0.0, 1.0)
	var w_high := sin(x * PI * 0.5)
	var w_low := cos(x * PI * 0.5)
	var on := 0.3 + 0.7 * _load
	var off := (1.0 - _load) * 0.6
	if _electric:
		# Motor whine rises with motor speed; louder under load.
		var motor := clampf(rpm / 13000.0, 0.0, 1.0)
		_level(_whine, (0.15 + 0.6 * _load) * clampf(motor * 4.0, 0.0, 1.0), 0.35 + motor * 1.9)
		for p in [_low_on, _low_off, _high_on, _high_off]:
			_level(p, 0.0, 1.0)
	else:
		# Cylinder count raises the note (V8 x2, V12 x3 vs. a 4-cylinder).
		_level(_low_on, w_low * on, rpm / LOW_RPM * _pitch_mult)
		_level(_low_off, w_low * off, rpm / LOW_RPM * _pitch_mult)
		_level(_high_on, w_high * on, rpm / HIGH_RPM * _pitch_mult)
		_level(_high_off, w_high * off, rpm / HIGH_RPM * _pitch_mult)

	# --- Tyres: squeal on tarmac when sliding or spinning, rumble off-road.
	var squeal := 0.0
	var loose := 0
	var speed := absf(_vehicle.forward_speed)
	for w in _vehicle.wheels:
		if not w.grounded:
			continue
		if w.surface_grip < WheelDirt.LOOSE_GRIP:
			loose += 1
			continue
		var slide := clampf((w.grip_usage - 0.93) * 7.0, 0.0, 1.0) * clampf(absf(w.v_long) / 6.0, 0.0, 1.0)
		var spin := clampf((absf(w.slip_ratio) - 0.18) * 3.0, 0.0, 1.0) * clampf(absf(w.v_long) / 3.0, 0.0, 1.0)
		squeal = maxf(squeal, maxf(slide, spin))
	_squeal_level = move_toward(_squeal_level, squeal, delta * 5.0)
	_level(_squeal, _squeal_level * 0.8, 0.92 + 0.16 * _squeal_level)
	_level(_dirt, (loose / 4.0) * clampf(speed / 15.0, 0.0, 1.0) * 0.9, 0.8 + clampf(speed / 40.0, 0.0, 0.5))
	_level(_wind, clampf((speed - 15.0) / 40.0, 0.0, 1.0) * 0.45, 0.8 + clampf(speed / 60.0, 0.0, 0.6))

	# --- Impacts: a sudden sideways/backwards change of speed is a hit.
	var v := _vehicle.linear_velocity
	var dv := Vector2(v.x - _prev_velocity.x, v.z - _prev_velocity.z).length()
	_prev_velocity = v
	_impact_cooldown -= delta
	if dv > 1.2 and _impact_cooldown <= 0.0 and not _vehicle.airborne:
		_impact.volume_db = linear_to_db(clampf(dv / 6.0, 0.15, 1.0)) + gain_db
		_impact.pitch_scale = randf_range(0.85, 1.1)
		_impact.play()
		_impact_cooldown = 0.25


func _level(p: AudioStreamPlayer3D, amplitude: float, pitch: float) -> void:
	p.volume_db = linear_to_db(maxf(amplitude, 0.0001)) + gain_db
	p.pitch_scale = clampf(pitch, 0.3, 4.0)
