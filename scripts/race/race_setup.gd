class_name RaceSetup
extends Node
## Builds a race: adds AI opponents, gives every car a lap timer, lines them
## all up on the grid (AI in front, players at the back) and hands everyone
## to the RaceDirector, then starts the countdown.

@export var circuit_path: NodePath
@export var race_director_path: NodePath
@export var car_scene: PackedScene
@export_range(0, 9) var ai_count: int = 5
## Players already in the scene, with their lap timers, names and colours.
@export var player_paths: Array[NodePath] = []
@export var player_timer_paths: Array[NodePath] = []
@export var player_names: PackedStringArray = ["YOU"]
@export var player_colors: PackedColorArray = [Color(0.35, 0.8, 1.0)]
## Opponent skills: 0 = cautious, 1 = on the limit. Spread across the field.
@export var ai_skill_min: float = 0.5
@export var ai_skill_max: float = 0.82
@export var random_seed: int = 0

const AI_NAMES: PackedStringArray = ["VEGA", "KATO", "MOREAU", "LIND", "OKAFOR", "RUIZ", "HALE", "NOVAK", "SATO"]
const AI_COLORS: PackedColorArray = [
	Color(0.95, 0.8, 0.1), Color(0.15, 0.35, 0.95), Color(0.92, 0.92, 0.9), Color(1.0, 0.45, 0.05),
	Color(0.55, 0.2, 0.75), Color(0.12, 0.12, 0.14), Color(0.95, 0.4, 0.65), Color(0.2, 0.75, 0.75),
	Color(0.6, 0.45, 0.25),
]

var ai_vehicles: Array[Vehicle] = []


func _ready() -> void:
	add_to_group("race_setup")
	# Adding cars to the scene has to wait until the scene finished loading.
	_build.call_deferred()


func _build() -> void:
	var circuit := get_node(circuit_path) as Circuit
	var director := get_node(race_director_path) as RaceDirector
	var root := get_parent()
	var rng := RandomNumberGenerator.new()
	if random_seed != 0:
		rng.seed = random_seed
	else:
		rng.randomize()
	var names := Array(AI_NAMES)
	var skills: Array[float] = []
	for i in ai_count:
		skills.append(lerpf(ai_skill_min, ai_skill_max, float(i) / maxf(ai_count - 1, 1)))
	# Faster drivers start further back, so there is racing to do.
	skills.shuffle()

	var slot := 0
	for i in ai_count:
		var car := car_scene.instantiate() as Vehicle
		car.name = "AI_%s" % names[i]
		car.paint_color = AI_COLORS[i % AI_COLORS.size()]
		var player_input := car.get_node_or_null("PlayerInput")
		if player_input:
			car.remove_child(player_input)
			player_input.free()
		var ai := AIDriver.new()
		ai.name = "AIDriver"
		ai.skill = skills[i]
		ai.lane_bias = rng.randf_range(-0.8, 0.8)
		car.add_child(ai)
		root.add_child(car)
		_place(car, circuit, slot)
		slot += 1
		var timer := LapTimer.new()
		timer.name = "LapTimer_%s" % names[i]
		root.add_child(timer)
		timer.setup(circuit, car)
		director.add_racer(car, timer, names[i], AI_COLORS[i % AI_COLORS.size()], false)
		ai_vehicles.append(car)

	for i in player_paths.size():
		var car := get_node(player_paths[i]) as Vehicle
		_place(car, circuit, slot)
		slot += 1
		var timer := get_node(player_timer_paths[i]) as LapTimer
		director.add_racer(car, timer, player_names[i] if i < player_names.size() else "PLAYER %d" % (i + 1),
				player_colors[i] if i < player_colors.size() else Color.WHITE, true)
	director.begin()


func _place(car: Vehicle, circuit: Circuit, slot: int) -> void:
	var xf := circuit.get_grid_transform(slot)
	car.spawn_transform = xf
	car.teleport(xf)
