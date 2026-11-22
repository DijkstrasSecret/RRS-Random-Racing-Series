extends Node
## Saves a screenshot of the dirt effect: the car is put on the grass next
## to the start straight at speed with full throttle. Visual check only.

const OUT := "user://screenshots"  

class Floored extends VehicleInput:
	func poll(_d: float) -> void:
		throttle = 1.0
		steer = 0.15

var _scene: Node
var _t := 0.0
var _done := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_scene = load("res://scenes/modes/circuit_practice.tscn").instantiate()
	var car: Vehicle = _scene.get_node("Vehicle")
	var player := car.get_node("PlayerInput")
	car.remove_child(player)
	player.free()
	car.add_child(Floored.new())
	add_child(_scene)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var circuit: Circuit = _scene.get_node("Circuit")
	var pos := circuit.point_at(120.0) + Vector3(-14.0, 0.3, 0.0)
	car.teleport(Transform3D(Basis.IDENTITY, pos))
	car.linear_velocity = Vector3(0, 0, -22.0)
	for w in car.wheels:
		w.omega = 22.0 / w.radius


func _process(delta: float) -> void:
	_t += delta
	if _t > 2.2 and not _done:
		_done = true
		get_viewport().get_texture().get_image().save_png(OUT + "/dirt.png")
		print("saved dirt")
		get_tree().quit()
