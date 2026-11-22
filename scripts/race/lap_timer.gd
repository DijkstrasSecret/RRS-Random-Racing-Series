class_name LapTimer
extends Node
## Lap timing on a Circuit. The clock starts the first time the car crosses
## the start/finish line; a lap only counts if the car also went through the
## two checkpoints (one and two thirds of the way round).

signal lap_completed(lap_time: float, is_best: bool)

@export var circuit_path: NodePath
@export var vehicle_path: NodePath

var lap: int = 0
var lap_time: float = 0.0
var last_lap: float = -1.0
var best_lap: float = -1.0
var running: bool = false

var _circuit: Circuit
var _vehicle: Vehicle
var _prev_offset: float = -1.0
var _checkpoints: int = 0


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


func reset() -> void:
	running = false
	lap = 0
	lap_time = 0.0
	_checkpoints = 0
	_prev_offset = -1.0


func _physics_process(delta: float) -> void:
	if _circuit == null or _vehicle == null:
		return
	var length := _circuit.length
	var offset := _circuit.progress_at(_vehicle.global_position)
	if running:
		lap_time += delta
		var next_cp := length * (_checkpoints + 1) / 3.0
		if _checkpoints < 2 and offset > next_cp and offset < next_cp + 120.0:
			_checkpoints += 1
	# Crossing the line forwards: offset wraps from the end of the lap to the start.
	if _prev_offset > length - 80.0 and offset < 80.0:
		if not running:
			running = true
			lap = 1
			lap_time = 0.0
			_checkpoints = 0
		elif _checkpoints >= 2:
			last_lap = lap_time
			var is_best := best_lap < 0.0 or lap_time < best_lap
			if is_best:
				best_lap = lap_time
			lap_completed.emit(lap_time, is_best)
			lap += 1
			lap_time = 0.0
			_checkpoints = 0
	_prev_offset = offset


static func format_time(t: float) -> String:
	if t < 0.0:
		return "--:--.---"
	var minutes := int(t / 60.0)
	return "%d:%06.3f" % [minutes, t - minutes * 60.0]
