class_name LapTimer
extends Node
## Lap timing on a Circuit. The clock starts the first time the car crosses
## the start/finish line; a lap only counts if the car also went through both
## sector lines (the circuit's real F1 sector split points).
##
## Sector times are coloured like F1 timing screens:
## purple = fastest by anyone this session, green = this driver's best,
## yellow = slower than this driver's best.
## Each car also logs the clock at TIMING_POINTS spots per lap, so gaps
## between cars can be read off like real timing loops.

## Emitted when the car crosses the line to end a lap: its time in seconds, and whether it's this car's best.
signal lap_completed(lap_time: float, is_best: bool)
## Emitted at each sector split: sector index (0-based), time in seconds, and colour.
## The colour is a SectorColor: PURPLE = best by anyone, GREEN = this car's best, YELLOW = slower.
signal sector_completed(sector: int, time: float, color: int)

enum SectorColor { NONE, YELLOW, GREEN, PURPLE }
const TIMING_POINTS := 40

## The Circuit to time on. Not needed when the timer is set up with setup().
@export var circuit_path: NodePath
## The car to time. Not needed when the timer is set up with setup().
@export var vehicle_path: NodePath

var lap: int = 0
var lap_time: float = 0.0
var last_lap: float = -1.0
var best_lap: float = -1.0
var running: bool = false
## Sector being driven (0..2) and this lap's / last lap's sector times (-1 = not yet).
var sector: int = 0
var sectors := PackedFloat32Array([-1.0, -1.0, -1.0])
var sector_colors := PackedInt32Array([0, 0, 0])
var last_sectors := PackedFloat32Array([-1.0, -1.0, -1.0])
var last_sector_colors := PackedInt32Array([0, 0, 0])
var best_sectors := PackedFloat32Array([-1.0, -1.0, -1.0])
## Time since the scene started (the same clock for every car's timer).
var clock: float = 0.0
## Timing point index (lap * TIMING_POINTS + point) -> clock when passed.
var points: Dictionary = {}
var last_point: int = -1

var _circuit: Circuit
var _vehicle: Vehicle
var _prev_offset: float = -1.0
var _sector_start: float = 0.0


func _ready() -> void:
	add_to_group("lap_timer")
	if _circuit == null:
		_circuit = get_node_or_null(circuit_path) as Circuit
	if _vehicle == null:
		setup(_circuit, get_node_or_null(vehicle_path) as Vehicle)


## Use instead of the paths when creating a timer from code.
func setup(circuit: Circuit, vehicle: Vehicle) -> void:
	_circuit = circuit
	if _vehicle == vehicle:
		return
	_vehicle = vehicle
	if _vehicle:
		_vehicle.reset_to_start_done.connect(reset)


## Back to before the first lap: lap 0, current lap and sector times cleared, not running. Best times are kept.
func reset() -> void:
	running = false
	lap = 0
	lap_time = 0.0
	sector = 0
	_sector_start = 0.0
	sectors.fill(-1.0)
	sector_colors.fill(0)
	_prev_offset = -1.0


## The car the timer is on.
func vehicle() -> Vehicle:
	return _vehicle


func _physics_process(delta: float) -> void:
	clock += delta
	if _circuit == null or _vehicle == null:
		return
	var length := _circuit.length
	var offset := _circuit.progress_at(_vehicle.global_position)
	if running:
		lap_time += delta
		if sector < 2:
			var line := _circuit.sector_splits[sector] * length
			if offset > line and offset < line + 120.0:
				_finish_sector(lap_time - _sector_start)
		_log_points(offset / length)
	# Crossing the line forwards: offset wraps from the end of the lap to the start.
	if _prev_offset > length - 80.0 and offset < 80.0:
		if not running:
			running = true
			lap = 1
			lap_time = 0.0
			sector = 0
			_sector_start = 0.0
			_log_points(0.0)
		elif sector >= 2:
			_finish_sector(lap_time - _sector_start)
			last_lap = lap_time
			var is_best := best_lap < 0.0 or lap_time < best_lap
			if is_best:
				best_lap = lap_time
			if _circuit.best_lap < 0.0 or lap_time < _circuit.best_lap:
				_circuit.best_lap = lap_time
			last_sectors = sectors.duplicate()
			last_sector_colors = sector_colors.duplicate()
			lap_completed.emit(lap_time, is_best)
			lap += 1
			lap_time = 0.0
			sector = 0
			_sector_start = 0.0
			sectors.fill(-1.0)
			sector_colors.fill(0)
			_log_points(0.0)
	_prev_offset = offset


func _finish_sector(t: float) -> void:
	var color := SectorColor.YELLOW
	var overall := _circuit.best_sectors[sector]
	if overall < 0.0 or t < overall:
		color = SectorColor.PURPLE
		_circuit.best_sectors[sector] = t
	elif best_sectors[sector] < 0.0 or t < best_sectors[sector]:
		color = SectorColor.GREEN
	if best_sectors[sector] < 0.0 or t < best_sectors[sector]:
		best_sectors[sector] = t
	sectors[sector] = t
	sector_colors[sector] = color
	sector_completed.emit(sector, t, color)
	_sector_start += t
	sector = mini(sector + 1, 3)


## Records the clock at every timing point passed since the last one.
func _log_points(lap_fraction: float) -> void:
	var idx := (lap - 1) * TIMING_POINTS + clampi(int(lap_fraction * TIMING_POINTS), 0, TIMING_POINTS - 1)
	if idx <= last_point or idx > last_point + TIMING_POINTS / 2 and last_point >= 0:
		return  # behind the last point (or a jump from a reset)
	for i in range(last_point + 1, idx + 1):
		points[i] = clock
	last_point = idx


## Formats seconds as "m:ss.mmm", e.g. 83.4 → "1:23.400"; "--:--.---" for a negative time.
static func format_time(t: float) -> String:
	if t < 0.0:
		return "--:--.---"
	var minutes := int(t / 60.0)
	return "%d:%06.3f" % [minutes, t - minutes * 60.0]


## Sector style: 27.384 (or 1:02.110 when over a minute).
static func format_sector(t: float) -> String:
	if t < 0.0:
		return "-"
	if t >= 60.0:
		return format_time(t)
	return "%.3f" % t
