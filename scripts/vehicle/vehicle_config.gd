class_name VehicleConfig
extends Resource
## Every tunable number for one car (design concept §7.2).
## The default values describe the greybox Hot Hatch (FWD).
## Units: metres, kilograms, seconds, Newtons, N·m.

enum DriveType { FWD, RWD, AWD }

@export_group("Body")
@export var display_name: String = "Hot Hatch (greybox)"
@export var mass: float = 1250.0
## Centre of mass in the car's local space (origin = ground, between the axles).
@export var center_of_mass: Vector3 = Vector3(0.0, 0.42, -0.15)
## Box (width, height, length) used to compute the rotational inertia.
@export var inertia_box_size: Vector3 = Vector3(1.76, 1.2, 4.1)
@export var inertia_scale: Vector3 = Vector3.ONE

@export_group("Wheels & Tires")
@export var wheel_radius: float = 0.31
@export var wheel_width: float = 0.22
@export var wheel_inertia: float = 1.1
## Peak friction coefficient (road tyres ≈ 1.0, slicks ≈ 1.4).
@export var tire_grip: float = 1.1
@export var tire_peak_slip_ratio: float = 0.10
@export var tire_peak_slip_angle_deg: float = 8.0
## How much grip per Newton drops as load rises (0 = none).
@export var tire_load_sensitivity: float = 0.12
## Rear grip relative to the front. Below 1 lets the rear step out when
## the car is pushed too hard (lift-off and high-speed oversteer).
@export var rear_grip_scale: float = 0.98
@export var rolling_resistance: float = 0.015

@export_group("Suspension")
## Free length of the spring (wheel fully hanging).
@export var rest_length: float = 0.30
## Spring compression from free length until the bump stop.
@export var max_travel: float = 0.22
@export var front_spring_rate: float = 32000.0
@export var rear_spring_rate: float = 27000.0
@export var front_damper_bump: float = 2400.0
@export var front_damper_rebound: float = 3300.0
@export var rear_damper_bump: float = 2150.0
@export var rear_damper_rebound: float = 2900.0
@export var front_anti_roll: float = 10000.0
@export var rear_anti_roll: float = 11000.0

@export_group("Engine")
@export var idle_rpm: float = 900.0
@export var redline_rpm: float = 7000.0
## Engine speed the clutch slips at when pulling away at full throttle.
@export var launch_rpm: float = 3800.0
@export var max_torque: float = 320.0
## (rpm, fraction of max_torque) points, linearly interpolated.
@export var torque_curve: PackedVector2Array = PackedVector2Array([
	Vector2(1000.0, 0.55), Vector2(2500.0, 0.85), Vector2(4000.0, 1.0),
	Vector2(5500.0, 0.97), Vector2(6500.0, 0.85), Vector2(7200.0, 0.7),
])
@export var engine_brake_torque: float = 75.0

@export_group("Gearbox & Drive")
@export var gear_ratios: PackedFloat32Array = PackedFloat32Array([3.4, 2.1, 1.5, 1.15, 0.95, 0.8])
@export var reverse_ratio: float = 3.2
@export var final_drive: float = 3.9
@export var drivetrain_efficiency: float = 0.88
@export var shift_time: float = 0.15
@export var auto_upshift_rpm: float = 6600.0
@export var auto_downshift_rpm: float = 3000.0
@export var drive_type: DriveType = DriveType.FWD
## 0 = open differential, 1 = (almost) locked.
@export_range(0.0, 1.0) var diff_lock: float = 0.15
## Share of torque sent to the front axle for AWD cars.
@export_range(0.0, 1.0) var awd_front_split: float = 0.4

@export_group("Brakes & Steering")
## Total brake torque for all four wheels at full pedal.
@export var brake_torque: float = 4800.0
## Share of brake torque on the front axle.
@export_range(0.0, 1.0) var brake_bias: float = 0.7
## Extra brake torque per rear wheel from the handbrake.
@export var handbrake_torque: float = 2500.0
@export var max_steer_deg: float = 33.0
## How fast the front wheels can turn, in radians per second.
@export var steer_rate: float = 4.0

@export_group("Aero")
## Drag coefficient × frontal area (m²).
@export var drag_area: float = 0.68
## Lift coefficient × area (m²); positive = downforce.
@export var downforce_area: float = 0.15
## Share of downforce on the front axle.
@export_range(0.0, 1.0) var aero_balance: float = 0.45
