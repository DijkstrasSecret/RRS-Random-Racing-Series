class_name VehicleConfig
extends Resource
## Every tunable number for one car (design concept §7.2).
## The default values describe the greybox Hot Hatch (FWD).
## Units: metres, kilograms, seconds, Newtons, N·m.

enum DriveType { FWD, RWD, AWD }

@export_group("Body")
## Name shown in menus and the HUD.
@export var display_name: String = "Hot Hatch (greybox)"
## Kerb mass in kg.
@export var mass: float = 1250.0
## Centre of mass in the car's local space (origin = ground, between the axles).
@export var center_of_mass: Vector3 = Vector3(0.0, 0.42, -0.15)
## Box (width, height, length) used to compute the rotational inertia.
@export var inertia_box_size: Vector3 = Vector3(1.76, 1.2, 4.1)
## Per-axis multiplier on the box inertia (x pitch, y yaw, z roll). 1 = solid box.
@export var inertia_scale: Vector3 = Vector3.ONE

@export_group("Wheels & Tires")
## Tyre radius in metres.
@export var wheel_radius: float = 0.31
## Tyre width in metres.
@export var wheel_width: float = 0.22
## Rotational inertia of one wheel and tyre, kg·m².
@export var wheel_inertia: float = 1.1
## Peak friction coefficient (road tyres ≈ 1.0, slicks ≈ 1.4).
@export var tire_grip: float = 1.16
## Longitudinal slip ratio at peak grip (0.10 = the tyre turns 10% faster or slower than the road).
@export var tire_peak_slip_ratio: float = 0.10
## Slip angle at peak cornering grip, in degrees.
@export var tire_peak_slip_angle_deg: float = 8.0
## How much grip per Newton drops as load rises (0 = none).
@export var tire_load_sensitivity: float = 0.12
## Rear grip relative to the front. Below 1 lets the rear step out when
## the car is pushed too hard (lift-off and high-speed oversteer).
@export var rear_grip_scale: float = 0.95
## Rolling resistance coefficient: resisting force = this × tyre load.
@export var rolling_resistance: float = 0.015

@export_group("Suspension")
## Free length of the spring (wheel fully hanging).
@export var rest_length: float = 0.30
## Spring compression from free length until the bump stop.
@export var max_travel: float = 0.22
## Spring rate per front wheel, N/m.
@export var front_spring_rate: float = 32000.0
## Spring rate per rear wheel, N/m.
@export var rear_spring_rate: float = 27000.0
## Front damping while the spring compresses, N·s/m.
@export var front_damper_bump: float = 2400.0
## Front damping while the spring extends, N·s/m.
@export var front_damper_rebound: float = 3300.0
## Rear damping while the spring compresses, N·s/m.
@export var rear_damper_bump: float = 2150.0
## Rear damping while the spring extends, N·s/m.
@export var rear_damper_rebound: float = 2900.0
## Front anti-roll bar stiffness, N per metre of left/right compression difference (scaled by Vehicle.ANTI_ROLL_SCALE).
@export var front_anti_roll: float = 10000.0
## Rear anti-roll bar stiffness, N per metre of left/right compression difference (scaled by Vehicle.ANTI_ROLL_SCALE).
@export var rear_anti_roll: float = 13000.0

@export_group("Engine")
## Engine speed at idle, rpm.
@export var idle_rpm: float = 900.0
## Highest engine speed, rpm; the rev limiter cuts power here.
@export var redline_rpm: float = 7000.0
## Engine speed the clutch slips at when pulling away at full throttle.
@export var launch_rpm: float = 3800.0
## Peak engine torque, N·m (torque_curve scales it with rpm).
@export var max_torque: float = 320.0
## (rpm, fraction of max_torque) points, linearly interpolated.
@export var torque_curve: PackedVector2Array = PackedVector2Array([
	Vector2(1000.0, 0.55), Vector2(2500.0, 0.85), Vector2(4000.0, 1.0),
	Vector2(5500.0, 0.97), Vector2(6500.0, 0.85), Vector2(7200.0, 0.7),
])
## Engine braking at the redline with the throttle closed, N·m; scales down linearly with rpm.
@export var engine_brake_torque: float = 75.0
## Turbo: share of the torque that comes from boost (0 = no turbo) and how
## long the boost takes to build (seconds). Boost needs throttle and revs
## above turbo_spool_rpm.
@export_range(0.0, 0.7) var turbo: float = 0.0
## Time for the boost to build, in seconds.
@export var turbo_lag: float = 0.6
## Engine speed below which the turbo gives no boost, rpm.
@export var turbo_spool_rpm: float = 1800.0

@export_group("Gearbox & Drive")
## Forward gear ratios, first gear first. One entry for an electric car.
@export var gear_ratios: PackedFloat32Array = PackedFloat32Array([3.4, 2.1, 1.5, 1.15, 0.95, 0.8])
## Reverse gear ratio, as a positive number.
@export var reverse_ratio: float = 3.2
## Final drive ratio, applied on top of every gear.
@export var final_drive: float = 3.9
## Share of engine torque that reaches the wheels, 0–1.
@export var drivetrain_efficiency: float = 0.88
## Time with no drive during a gear change, in seconds.
@export var shift_time: float = 0.15
## Engine speed the automatic gearbox shifts up at, rpm.
@export var auto_upshift_rpm: float = 6600.0
## Engine speed the automatic gearbox shifts down at, rpm.
@export var auto_downshift_rpm: float = 3000.0
## Which wheels are driven: FWD, RWD or AWD.
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
## Largest front wheel angle at full lock, in degrees (assists lower it at speed).
@export var max_steer_deg: float = 33.0
## How fast the front wheels can turn, in radians per second.
@export var steer_rate: float = 4.0

@export_group("Sound")
## Electric motor: one gear, whine instead of engine sound.
@export var electric: bool = false
## Engine note relative to a 4-cylinder (V8 = 2, V12 = 3, diesel ~0.85).
@export var engine_sound_pitch: float = 1.0
## Engine sound volume offset, dB.
@export var engine_sound_gain_db: float = 0.0

@export_group("Aero")
## Drag coefficient × frontal area (m²).
@export var drag_area: float = 0.68
## Lift coefficient × area (m²); positive = downforce.
@export var downforce_area: float = 0.15
## Share of downforce on the front axle.
@export_range(0.0, 1.0) var aero_balance: float = 0.45
