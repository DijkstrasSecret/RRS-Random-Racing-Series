class_name VehicleInput
extends Node
## Driving commands for a Vehicle (design concept §14.2). PlayerInput, AIDriver
## and ReplayPlayer all extend this, so every driver uses the same car.

var throttle: float = 0.0  ## 0..1
var brake: float = 0.0  ## 0..1
var steer: float = 0.0  ## -1 (left) .. +1 (right)
var handbrake: float = 0.0  ## 0..1

# One-tick "pressed" pulses.
var shift_up_pressed: bool = false
var shift_down_pressed: bool = false
var toggle_transmission_pressed: bool = false
var recover_pressed: bool = false
var restart_pressed: bool = false
var cycle_profile_pressed: bool = false


## Called by the Vehicle once per physics tick, before it reads the values.
func poll(_delta: float) -> void:
	pass
