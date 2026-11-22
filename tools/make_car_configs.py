"""Writes the VehicleConfig (.tres) for every roster car.

    python tools/make_car_configs.py

Numbers are based on the real cars that inspired each design (power,
weight, gearing, drivetrain), then tuned for the game's handling.
Writes assets/cars/<id>/<id>.tres.
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FWD, RWD, AWD = 0, 1, 2

CARS = {
    "kartal": dict(
        wheel_inertia=0.9,
        display_name="Kartal 77 SL", mass=960, center_of_mass=(0, 0.46, -0.12), inertia_box_size=(1.62, 1.3, 4.2),
        wheel_radius=0.30, wheel_width=0.17, tire_grip=1.0, tire_peak_slip_angle_deg=9.0, rear_grip_scale=0.95,
        front_spring_rate=24000, rear_spring_rate=20000, front_damper_bump=1900, front_damper_rebound=2500,
        rear_damper_bump=1700, rear_damper_rebound=2300, front_anti_roll=6000, rear_anti_roll=9000,
        idle_rpm=800, redline_rpm=5800, launch_rpm=3000, max_torque=105,
        torque_curve=[(1000, .6), (2500, .9), (3200, 1.0), (4500, .9), (5600, .72)],
        engine_brake_torque=30, gear_ratios=[3.65, 1.97, 1.37, 1.0], reverse_ratio=3.66, final_drive=4.11,
        auto_upshift_rpm=5400, auto_downshift_rpm=2200, drive_type=RWD, diff_lock=0.0,
        brake_torque=3000, brake_bias=0.7, handbrake_torque=2200, max_steer_deg=34, steer_rate=3.4,
        drag_area=0.82, downforce_area=-0.05, engine_sound_pitch=1.0, engine_sound_gain_db=-1.0),
    "ashford": dict(
        wheel_inertia=1.6,
        display_name="Ashford GT12", mass=1870, center_of_mass=(0, 0.45, 0.1), inertia_box_size=(1.95, 1.2, 4.74),
        wheel_radius=0.35, wheel_width=0.25, tire_grip=1.28, tire_peak_slip_angle_deg=7.5, rear_grip_scale=0.97,
        front_spring_rate=52000, rear_spring_rate=56000, front_damper_bump=4200, front_damper_rebound=5600,
        rear_damper_bump=4400, rear_damper_rebound=5900, front_anti_roll=18000, rear_anti_roll=17000,
        idle_rpm=750, redline_rpm=7000, launch_rpm=3200, max_torque=700,
        torque_curve=[(1000, .7), (1500, .85), (3000, 1.0), (6000, .95), (7100, .85)],
        engine_brake_torque=120, gear_ratios=[3.5, 2.5, 1.9, 1.45, 1.15, 0.93, 0.75], reverse_ratio=3.0,
        final_drive=2.9, auto_upshift_rpm=6700, auto_downshift_rpm=3000, drive_type=RWD, diff_lock=0.45,
        brake_torque=10500, brake_bias=0.66, handbrake_torque=4000, max_steer_deg=32, steer_rate=4.0,
        drag_area=0.63, downforce_area=0.35, aero_balance=0.42, engine_sound_pitch=2.4, engine_sound_gain_db=2.0),
    "quadra": dict(
        wheel_inertia=1.2,
        display_name="Quadra 16d", mass=1300, center_of_mass=(0, 0.45, -0.25), inertia_box_size=(1.8, 1.3, 4.46),
        wheel_radius=0.32, wheel_width=0.22, tire_grip=1.1, rear_grip_scale=0.96,
        front_spring_rate=34000, rear_spring_rate=28000, front_damper_bump=2500, front_damper_rebound=3400,
        rear_damper_bump=2200, rear_damper_rebound=3000, front_anti_roll=11000, rear_anti_roll=12000,
        idle_rpm=800, redline_rpm=4600, launch_rpm=2200, max_torque=250,
        torque_curve=[(1000, .55), (1500, .95), (2000, 1.0), (3000, .95), (4000, .7), (4700, .5)],
        engine_brake_torque=60, gear_ratios=[3.8, 2.12, 1.27, 0.86, 0.66, 0.55], reverse_ratio=3.6,
        final_drive=3.4, auto_upshift_rpm=4200, auto_downshift_rpm=1700, drive_type=FWD, diff_lock=0.1,
        brake_torque=5200, brake_bias=0.68, handbrake_torque=2400, max_steer_deg=33, steer_rate=3.8,
        drag_area=0.64, downforce_area=0.1, engine_sound_pitch=0.85, engine_sound_gain_db=-1.0),
    "bellmont": dict(
        wheel_inertia=2.0,
        display_name="Bellmont Wingspan V8", mass=2330, center_of_mass=(0, 0.5, -0.12), inertia_box_size=(1.98, 1.4, 5.32),
        wheel_radius=0.37, wheel_width=0.27, tire_grip=1.2, rear_grip_scale=1.0,
        front_spring_rate=52000, rear_spring_rate=54000, front_damper_bump=4500, front_damper_rebound=6000,
        rear_damper_bump=4600, rear_damper_rebound=6200, front_anti_roll=18000, rear_anti_roll=11000,
        idle_rpm=650, redline_rpm=6500, launch_rpm=2600, max_torque=770,
        torque_curve=[(1000, .75), (2000, 1.0), (4500, 1.0), (5500, .9), (6600, .75)],
        engine_brake_torque=130, gear_ratios=[4.7, 3.1, 2.1, 1.67, 1.29, 1.0, 0.84, 0.67], reverse_ratio=3.3,
        final_drive=2.85, auto_upshift_rpm=6100, auto_downshift_rpm=2500, drive_type=AWD, diff_lock=0.4,
        awd_front_split=0.4, brake_torque=12500, brake_bias=0.7, handbrake_torque=3500, max_steer_deg=31,
        steer_rate=3.4, drag_area=0.72, downforce_area=0.1, engine_sound_pitch=1.7, engine_sound_gain_db=1.0),
    "romola": dict(
        wheel_inertia=1.2,
        display_name="Romola Stella 16d", mass=1370, center_of_mass=(0, 0.45, -0.2), inertia_box_size=(1.8, 1.35, 4.35),
        wheel_radius=0.32, wheel_width=0.23, tire_grip=1.14, rear_grip_scale=0.94,
        front_spring_rate=36000, rear_spring_rate=30000, front_damper_bump=2600, front_damper_rebound=3500,
        rear_damper_bump=2300, rear_damper_rebound=3100, front_anti_roll=10000, rear_anti_roll=15000,
        idle_rpm=800, redline_rpm=4700, launch_rpm=2300, max_torque=320,
        torque_curve=[(1000, .5), (1750, 1.0), (2500, 1.0), (3500, .8), (4700, .5)],
        engine_brake_torque=65, gear_ratios=[3.82, 2.16, 1.37, 0.97, 0.76, 0.63], reverse_ratio=3.6,
        final_drive=3.35, auto_upshift_rpm=4300, auto_downshift_rpm=1700, drive_type=FWD, diff_lock=0.2,
        brake_torque=5400, brake_bias=0.66, handbrake_torque=2600, max_steer_deg=34, steer_rate=4.5,
        drag_area=0.66, downforce_area=0.1, engine_sound_pitch=0.85, engine_sound_gain_db=-1.0),
    "bavaro": dict(
        wheel_inertia=1.4,
        display_name="Bavaro 4 Gran", mass=1600, center_of_mass=(0, 0.46, 0.05), inertia_box_size=(1.85, 1.35, 4.78),
        wheel_radius=0.34, wheel_width=0.24, tire_grip=1.16, rear_grip_scale=0.95,
        front_spring_rate=40000, rear_spring_rate=42000, front_damper_bump=3000, front_damper_rebound=4000,
        rear_damper_bump=3100, rear_damper_rebound=4200, front_anti_roll=13000, rear_anti_roll=14000,
        idle_rpm=700, redline_rpm=6500, launch_rpm=2800, max_torque=300,
        torque_curve=[(1000, .7), (1350, 1.0), (4000, 1.0), (5000, .9), (6600, .65)],
        engine_brake_torque=70, gear_ratios=[5.25, 3.36, 2.17, 1.72, 1.32, 1.0, 0.82, 0.64], reverse_ratio=4.0,
        final_drive=2.81, auto_upshift_rpm=6100, auto_downshift_rpm=2200, drive_type=RWD, diff_lock=0.3,
        brake_torque=7600, brake_bias=0.66, handbrake_torque=3000, max_steer_deg=33, steer_rate=4.2,
        drag_area=0.57, downforce_area=0.15, engine_sound_pitch=1.05, engine_sound_gain_db=0.0),
    "hanlong": dict(
        wheel_inertia=1.7,
        display_name="Hanlong E9", mass=2250, center_of_mass=(0, 0.42, 0.0), inertia_box_size=(1.91, 1.2, 4.99),
        wheel_radius=0.35, wheel_width=0.25, tire_grip=1.18, rear_grip_scale=0.97,
        front_spring_rate=50000, rear_spring_rate=52000, front_damper_bump=4300, front_damper_rebound=5800,
        rear_damper_bump=4400, rear_damper_rebound=6000, front_anti_roll=16000, rear_anti_roll=15000,
        idle_rpm=50, redline_rpm=13300, launch_rpm=100, max_torque=700,
        torque_curve=[(0, 1.0), (6000, 1.0), (8000, .75), (10000, .6), (12000, .5), (13400, .45)],
        engine_brake_torque=60, gear_ratios=[1.0], reverse_ratio=1.0, final_drive=9.5,
        drivetrain_efficiency=0.95, shift_time=0.0, auto_upshift_rpm=99999, auto_downshift_rpm=0,
        drive_type=AWD, diff_lock=0.3, awd_front_split=0.45, brake_torque=12000, brake_bias=0.63,
        handbrake_torque=3500, max_steer_deg=32, steer_rate=3.8, drag_area=0.58, downforce_area=0.12,
        electric=True, engine_sound_pitch=1.0, engine_sound_gain_db=0.0),
}


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, tuple):
        return "Vector3(%s)" % ", ".join(str(float(x)) for x in v)
    if isinstance(v, list) and v and isinstance(v[0], tuple):
        return "PackedVector2Array(%s)" % ", ".join("%s, %s" % (float(a), float(b)) for a, b in v)
    if isinstance(v, list):
        return "PackedFloat32Array(%s)" % ", ".join(str(float(x)) for x in v)
    if isinstance(v, float):
        return repr(v)
    return str(v)


for cid, props in CARS.items():
    out = os.path.join(ROOT, "assets", "cars", cid, cid + ".tres")
    lines = ['[gd_resource type="Resource" script_class="VehicleConfig" load_steps=2 format=3]', "",
             '[ext_resource type="Script" path="res://scripts/vehicle/vehicle_config.gd" id="1_cfg"]', "",
             "[resource]", 'script = ExtResource("1_cfg")']
    for key, value in props.items():
        lines.append("%s = %s" % (key, fmt(value)))
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", os.path.relpath(out, ROOT))
