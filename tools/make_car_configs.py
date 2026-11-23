"""Writes the VehicleConfig (.tres) for every roster car.

    python tools/make_car_configs.py

Numbers are based on the real cars (power,
weight, gearing, drivetrain), then tuned for the game's handling.
Writes assets/cars/<id>/<id>.tres.
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FWD, RWD, AWD = 0, 1, 2

CARS = {
    "kartal": dict(
        wheel_inertia=0.9,
        display_name="Anadol A2 SL", mass=960, center_of_mass=(0, 0.46, -0.12), inertia_box_size=(1.62, 1.3, 4.2),
        wheel_radius=0.30, wheel_width=0.17, tire_grip=1.06, tire_peak_slip_angle_deg=9.0, rear_grip_scale=0.95,
        front_spring_rate=24000, rear_spring_rate=20000, front_damper_bump=1900, front_damper_rebound=2500,
        rear_damper_bump=1700, rear_damper_rebound=2300, front_anti_roll=6000, rear_anti_roll=9000,
        idle_rpm=800, redline_rpm=5800, launch_rpm=3000, max_torque=122,
        torque_curve=[(1000, .6), (2500, .9), (3200, 1.0), (4500, .9), (5600, .72)],
        engine_brake_torque=30, gear_ratios=[3.65, 1.97, 1.37, 1.0], reverse_ratio=3.66, final_drive=4.11,
        auto_upshift_rpm=5400, auto_downshift_rpm=2200, drive_type=RWD, diff_lock=0.0,
        brake_torque=3000, brake_bias=0.7, handbrake_torque=2200, max_steer_deg=34, steer_rate=3.4,
        drag_area=0.82, downforce_area=-0.05, engine_sound_pitch=1.0, engine_sound_gain_db=-1.0),
    "ashford": dict(
        wheel_inertia=1.6,
        display_name="Aston Martin DB11 V12", mass=1870, center_of_mass=(0, 0.45, 0.1), inertia_box_size=(1.95, 1.2, 4.74),
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
        display_name="Audi A3 Sedan 1.6 TDI", mass=1300, center_of_mass=(0, 0.45, -0.25), inertia_box_size=(1.8, 1.3, 4.46),
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
        display_name="Bentley Flying Spur V8", mass=2330, center_of_mass=(0, 0.5, -0.12), inertia_box_size=(1.98, 1.4, 5.32),
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
        display_name="Alfa Romeo Giulietta", mass=1370, center_of_mass=(0, 0.45, -0.2), inertia_box_size=(1.8, 1.35, 4.35),
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
        display_name="BMW 4 Series Gran Coupe", mass=1600, center_of_mass=(0, 0.46, 0.05), inertia_box_size=(1.85, 1.35, 4.78),
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
        display_name="BYD Han EV", mass=2250, center_of_mass=(0, 0.42, 0.0), inertia_box_size=(1.91, 1.2, 4.99),
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
    # --- second wave -----------------------------------------------------------------
    "orion": dict(  # Ioniq 6 SR RWD: 111 kW, 350 Nm, 1800 kg
        wheel_inertia=1.5,
        display_name="Hyundai Ioniq 6", mass=1800, center_of_mass=(0, 0.42, 0.05), inertia_box_size=(1.88, 1.2, 4.86),
        wheel_radius=0.34, wheel_width=0.23, tire_grip=1.1, rear_grip_scale=0.95,
        front_spring_rate=42000, rear_spring_rate=44000, front_damper_bump=3500, front_damper_rebound=4700,
        rear_damper_bump=3600, rear_damper_rebound=4900, front_anti_roll=14000, rear_anti_roll=12000,
        idle_rpm=50, redline_rpm=15300, launch_rpm=100, max_torque=350,
        torque_curve=[(0, 1.0), (3000, 1.0), (6000, .5), (9000, .33), (12000, .25), (15400, .2)],
        engine_brake_torque=40, gear_ratios=[1.0], reverse_ratio=1.0, final_drive=10.65,
        drivetrain_efficiency=0.95, shift_time=0.0, auto_upshift_rpm=99999, auto_downshift_rpm=0,
        drive_type=RWD, diff_lock=0.25, brake_torque=8500, brake_bias=0.66, handbrake_torque=3000,
        max_steer_deg=33, steer_rate=3.9, drag_area=0.48, downforce_area=0.12,
        electric=True, engine_sound_pitch=1.1, engine_sound_gain_db=-1.0),
    "braxton": dict(  # Challenger SXT 3.6 V6: 305 hp, 363 Nm, 1750 kg
        wheel_inertia=1.5,
        display_name="Dodge Challenger SXT", mass=1750, center_of_mass=(0, 0.48, -0.15), inertia_box_size=(1.92, 1.3, 5.02),
        wheel_radius=0.36, wheel_width=0.26, tire_grip=1.12, rear_grip_scale=0.94,
        front_spring_rate=42000, rear_spring_rate=40000, front_damper_bump=3300, front_damper_rebound=4400,
        rear_damper_bump=3200, rear_damper_rebound=4300, front_anti_roll=15000, rear_anti_roll=11000,
        idle_rpm=700, redline_rpm=6400, launch_rpm=2800, max_torque=363,
        torque_curve=[(1000, .6), (2500, .82), (4800, 1.0), (6350, .94), (6500, .88)],
        engine_brake_torque=80, gear_ratios=[4.71, 3.14, 2.1, 1.67, 1.29, 1.0, 0.84, 0.67], reverse_ratio=3.3,
        final_drive=3.07, auto_upshift_rpm=6100, auto_downshift_rpm=2300, drive_type=RWD, diff_lock=0.35,
        brake_torque=8500, brake_bias=0.68, handbrake_torque=3200, max_steer_deg=32, steer_rate=3.6,
        drag_area=0.9, downforce_area=0.05, engine_sound_pitch=1.35, engine_sound_gain_db=1.5),
    "kaze": dict(  # Civic 1.6 i-VTEC sedan: 125 hp, 152 Nm, 1280 kg
        wheel_inertia=1.2,
        display_name="Honda Civic 1.6 i-VTEC", mass=1280, center_of_mass=(0, 0.45, -0.25), inertia_box_size=(1.8, 1.3, 4.63),
        wheel_radius=0.33, wheel_width=0.22, tire_grip=1.12, rear_grip_scale=0.96,
        front_spring_rate=34000, rear_spring_rate=30000, front_damper_bump=2500, front_damper_rebound=3400,
        rear_damper_bump=2300, rear_damper_rebound=3100, front_anti_roll=11000, rear_anti_roll=13000,
        idle_rpm=750, redline_rpm=6800, launch_rpm=3200, max_torque=152,
        torque_curve=[(1000, .6), (2500, .8), (4300, 1.0), (6500, .9), (6900, .8)],
        engine_brake_torque=40, gear_ratios=[3.6, 2.05, 1.38, 1.03, 0.82, 0.68], reverse_ratio=3.6,
        final_drive=4.1, auto_upshift_rpm=6500, auto_downshift_rpm=2600, drive_type=FWD, diff_lock=0.1,
        brake_torque=5600, brake_bias=0.68, handbrake_torque=2400, max_steer_deg=33, steer_rate=4.0,
        drag_area=0.62, downforce_area=0.1, engine_sound_pitch=1.25, engine_sound_gain_db=-1.0),
    "atmaca": dict(  # slammed Sahin 1.6: 80 hp, 123 Nm, 950 kg, lowered and stiff
        wheel_inertia=0.9,
        display_name="Tofaş Şahin Stance", mass=950, center_of_mass=(0, 0.42, -0.1), inertia_box_size=(1.65, 1.2, 4.26),
        wheel_radius=0.30, wheel_width=0.21, tire_grip=1.04, tire_peak_slip_angle_deg=8.5, rear_grip_scale=0.94,
        front_spring_rate=30000, rear_spring_rate=26000, front_damper_bump=2300, front_damper_rebound=3000,
        rear_damper_bump=2100, rear_damper_rebound=2800, front_anti_roll=8000, rear_anti_roll=10000,
        idle_rpm=850, redline_rpm=6000, launch_rpm=3200, max_torque=123,
        torque_curve=[(1000, .65), (2000, .85), (3000, 1.0), (4500, .95), (5800, .8), (6100, .7)],
        engine_brake_torque=30, gear_ratios=[3.67, 2.1, 1.36, 1.0, 0.86], reverse_ratio=3.7,
        final_drive=3.9, auto_upshift_rpm=5700, auto_downshift_rpm=2400, drive_type=RWD, diff_lock=0.0,
        brake_torque=3200, brake_bias=0.7, handbrake_torque=2300, max_steer_deg=34, steer_rate=3.8,
        drag_area=0.8, downforce_area=-0.03, engine_sound_pitch=1.05, engine_sound_gain_db=0.0),
    "mirelle": dict(  # Clio IV 1.5 dCi: 75 hp, 200 Nm, 1070 kg
        wheel_inertia=1.0,
        display_name="Renault Clio 1.5 dCi", mass=1070, center_of_mass=(0, 0.44, -0.25), inertia_box_size=(1.73, 1.3, 4.06),
        wheel_radius=0.31, wheel_width=0.2, tire_grip=1.01, rear_grip_scale=0.97,
        front_spring_rate=30000, rear_spring_rate=26000, front_damper_bump=2200, front_damper_rebound=3000,
        rear_damper_bump=2000, rear_damper_rebound=2700, front_anti_roll=9000, rear_anti_roll=11000,
        idle_rpm=800, redline_rpm=4800, launch_rpm=2200, max_torque=170,
        torque_curve=[(1000, .55), (1750, 1.0), (2500, .95), (4000, .67), (4800, .45)],
        engine_brake_torque=50, gear_ratios=[3.73, 1.96, 1.23, 0.84, 0.65], reverse_ratio=3.5,
        final_drive=3.73, auto_upshift_rpm=4300, auto_downshift_rpm=1700, drive_type=FWD, diff_lock=0.1,
        brake_torque=4400, brake_bias=0.68, handbrake_torque=2200, max_steer_deg=34, steer_rate=4.1,
        drag_area=0.74, downforce_area=0.05, engine_sound_pitch=0.85, engine_sound_gain_db=-1.5),
    "kerkenez": dict(  # Dogan SLX 1.6ie: 83 hp, 125 Nm, 1000 kg
        wheel_inertia=0.9,
        display_name="Tofaş Doğan SLX", mass=1000, center_of_mass=(0, 0.46, -0.1), inertia_box_size=(1.65, 1.3, 4.3),
        wheel_radius=0.30, wheel_width=0.18, tire_grip=1.02, tire_peak_slip_angle_deg=9.0, rear_grip_scale=0.95,
        front_spring_rate=24000, rear_spring_rate=21000, front_damper_bump=1900, front_damper_rebound=2500,
        rear_damper_bump=1800, rear_damper_rebound=2400, front_anti_roll=6500, rear_anti_roll=9000,
        idle_rpm=850, redline_rpm=6000, launch_rpm=3200, max_torque=131,
        torque_curve=[(1000, .65), (2000, .85), (3000, 1.0), (4500, .95), (5800, .82), (6100, .7)],
        engine_brake_torque=30, gear_ratios=[3.67, 2.1, 1.36, 1.0, 0.86], reverse_ratio=3.7,
        final_drive=3.9, auto_upshift_rpm=5700, auto_downshift_rpm=2400, drive_type=RWD, diff_lock=0.0,
        brake_torque=3300, brake_bias=0.7, handbrake_torque=2300, max_steer_deg=34, steer_rate=3.5,
        drag_area=0.82, downforce_area=-0.05, engine_sound_pitch=1.0, engine_sound_gain_db=-0.5),
    "piccolo": dict(  # Mini Cooper R50 1.6: 115 hp, 149 Nm, 1140 kg
        wheel_inertia=1.0,
        display_name="Mini Cooper", mass=1140, center_of_mass=(0, 0.44, -0.2), inertia_box_size=(1.69, 1.3, 3.63),
        wheel_radius=0.30, wheel_width=0.2, tire_grip=1.15, rear_grip_scale=0.96,
        front_spring_rate=34000, rear_spring_rate=30000, front_damper_bump=2500, front_damper_rebound=3300,
        rear_damper_bump=2300, rear_damper_rebound=3100, front_anti_roll=10000, rear_anti_roll=14000,
        idle_rpm=800, redline_rpm=6500, launch_rpm=3200, max_torque=149,
        torque_curve=[(1000, .6), (2500, .85), (4500, 1.0), (6000, .92), (6600, .8)],
        engine_brake_torque=40, gear_ratios=[3.5, 2.1, 1.5, 1.15, 0.92, 0.76], reverse_ratio=3.4,
        final_drive=3.9, auto_upshift_rpm=6200, auto_downshift_rpm=2600, drive_type=FWD, diff_lock=0.15,
        brake_torque=5000, brake_bias=0.67, handbrake_torque=2400, max_steer_deg=35, steer_rate=4.8,
        drag_area=0.63, downforce_area=0.05, engine_sound_pitch=1.2, engine_sound_gain_db=-1.0),
    "mammoth": dict(  # Amarok 2.0 TDI 4x4: 205 hp, 500 Nm, 2300 kg, 10-speed
        wheel_inertia=2.4,
        display_name="VW Amarok 2.0 TDI", mass=2300, center_of_mass=(0, 0.6, -0.1), inertia_box_size=(1.95, 1.7, 5.35),
        wheel_radius=0.40, wheel_width=0.29, tire_grip=1.0, tire_peak_slip_angle_deg=9.0, rear_grip_scale=0.98,
        front_spring_rate=52000, rear_spring_rate=62000, front_damper_bump=4600, front_damper_rebound=6200,
        rear_damper_bump=4800, rear_damper_rebound=6500, front_anti_roll=20000, rear_anti_roll=12000,
        idle_rpm=750, redline_rpm=4500, launch_rpm=2000, max_torque=500,
        torque_curve=[(1000, .6), (1750, 1.0), (2500, 1.0), (3750, .78), (4500, .55)],
        engine_brake_torque=110, gear_ratios=[4.7, 2.99, 2.15, 1.8, 1.52, 1.28, 1.0, 0.85, 0.69, 0.64],
        reverse_ratio=4.9, final_drive=3.73, auto_upshift_rpm=4000, auto_downshift_rpm=1600, drive_type=AWD,
        diff_lock=0.4, awd_front_split=0.45, brake_torque=11000, brake_bias=0.68, handbrake_torque=3500,
        max_steer_deg=33, steer_rate=3.2, drag_area=1.15, downforce_area=-0.05,
        engine_sound_pitch=0.8, engine_sound_gain_db=2.0),
    "bastion": dict(  # G 350d: 245 hp, 600 Nm, 2500 kg, 7-speed, 4x4
        wheel_inertia=2.3,
        display_name="Mercedes-Benz G 350 d", mass=2500, center_of_mass=(0, 0.62, 0.0), inertia_box_size=(1.86, 1.8, 4.66),
        wheel_radius=0.38, wheel_width=0.28, tire_grip=1.05, tire_peak_slip_angle_deg=8.5, rear_grip_scale=0.98,
        front_spring_rate=60000, rear_spring_rate=62000, front_damper_bump=5000, front_damper_rebound=6600,
        rear_damper_bump=5100, rear_damper_rebound=6800, front_anti_roll=22000, rear_anti_roll=13000,
        idle_rpm=700, redline_rpm=4600, launch_rpm=2000, max_torque=600,
        torque_curve=[(1000, .62), (1600, 1.0), (2400, 1.0), (3600, .8), (4600, .55)],
        engine_brake_torque=130, gear_ratios=[4.38, 2.86, 1.92, 1.37, 1.0, 0.82, 0.73], reverse_ratio=3.4,
        final_drive=3.7, auto_upshift_rpm=4200, auto_downshift_rpm=1700, drive_type=AWD, diff_lock=0.5,
        awd_front_split=0.4, brake_torque=12500, brake_bias=0.68, handbrake_torque=3500, max_steer_deg=33,
        steer_rate=3.1, drag_area=1.55, downforce_area=-0.08, engine_sound_pitch=0.85, engine_sound_gain_db=2.0),
    "dingo": dict(  # Renegade 1.3T FWD: 150 hp, 270 Nm, 1400 kg
        wheel_inertia=1.3,
        display_name="Jeep Renegade 1.3T", mass=1400, center_of_mass=(0, 0.55, -0.22), inertia_box_size=(1.81, 1.55, 4.24),
        wheel_radius=0.34, wheel_width=0.22, tire_grip=1.08, rear_grip_scale=0.97,
        front_spring_rate=36000, rear_spring_rate=32000, front_damper_bump=2700, front_damper_rebound=3600,
        rear_damper_bump=2500, rear_damper_rebound=3400, front_anti_roll=13000, rear_anti_roll=12000,
        idle_rpm=750, redline_rpm=6200, launch_rpm=2600, max_torque=270,
        torque_curve=[(1000, .6), (1850, 1.0), (3500, 1.0), (5500, .71), (6300, .55)],
        engine_brake_torque=55, gear_ratios=[3.77, 2.32, 1.43, 0.98, 0.76, 0.64], reverse_ratio=3.7,
        final_drive=4.1, auto_upshift_rpm=5800, auto_downshift_rpm=2000, drive_type=FWD, diff_lock=0.1,
        brake_torque=6500, brake_bias=0.68, handbrake_torque=2600, max_steer_deg=33, steer_rate=3.7,
        drag_area=0.95, downforce_area=0.0, engine_sound_pitch=1.1, engine_sound_gain_db=-0.5),
    "harcourt": dict(  # X-Type 2.1 V6 FWD: 157 hp, 200 Nm, 1550 kg
        wheel_inertia=1.3,
        display_name="Jaguar X-Type 2.1 V6", mass=1550, center_of_mass=(0, 0.46, -0.22), inertia_box_size=(1.79, 1.3, 4.67),
        wheel_radius=0.33, wheel_width=0.21, tire_grip=1.1, rear_grip_scale=0.97,
        front_spring_rate=34000, rear_spring_rate=30000, front_damper_bump=2600, front_damper_rebound=3500,
        rear_damper_bump=2400, rear_damper_rebound=3300, front_anti_roll=11000, rear_anti_roll=12000,
        idle_rpm=700, redline_rpm=6800, launch_rpm=2800, max_torque=200,
        torque_curve=[(1000, .65), (3000, 1.0), (4500, .98), (6000, .9), (6800, .82)],
        engine_brake_torque=55, gear_ratios=[3.42, 2.21, 1.6, 1.0, 0.75], reverse_ratio=3.0,
        final_drive=3.8, auto_upshift_rpm=6400, auto_downshift_rpm=2500, drive_type=FWD, diff_lock=0.1,
        brake_torque=6200, brake_bias=0.67, handbrake_torque=2600, max_steer_deg=32, steer_rate=3.6,
        drag_area=0.66, downforce_area=0.05, engine_sound_pitch=1.5, engine_sound_gain_db=0.0),
    "e30": dict(  # 325i E30: 170 hp, 222 Nm, 1200 kg, 5-speed, RWD
        wheel_inertia=1.0,
        display_name="BMW 325i (E30)", mass=1200, center_of_mass=(0, 0.45, -0.05), inertia_box_size=(1.65, 1.3, 4.33),
        wheel_radius=0.30, wheel_width=0.2, tire_grip=1.06, tire_peak_slip_angle_deg=8.5, rear_grip_scale=0.95,
        front_spring_rate=30000, rear_spring_rate=28000, front_damper_bump=2300, front_damper_rebound=3100,
        rear_damper_bump=2200, rear_damper_rebound=3000, front_anti_roll=9000, rear_anti_roll=10000,
        idle_rpm=800, redline_rpm=6500, launch_rpm=3200, max_torque=200,
        torque_curve=[(1000, .6), (2500, .85), (4300, 1.0), (5800, .92), (6500, .8)],
        engine_brake_torque=45, gear_ratios=[3.83, 2.2, 1.4, 1.0, 0.81], reverse_ratio=3.46,
        final_drive=3.73, auto_upshift_rpm=6200, auto_downshift_rpm=2600, drive_type=RWD, diff_lock=0.25,
        brake_torque=4600, brake_bias=0.68, handbrake_torque=2500, max_steer_deg=34, steer_rate=3.8,
        drag_area=0.7, downforce_area=0.0, engine_sound_pitch=1.35, engine_sound_gain_db=0.0),
    "troc": dict(  # T-Roc 1.5 TSI: 150 hp, 250 Nm, 1320 kg, FWD
        wheel_inertia=1.3,
        display_name="VW T-Roc 1.5 TSI", mass=1320, center_of_mass=(0, 0.53, -0.2), inertia_box_size=(1.82, 1.5, 4.23),
        wheel_radius=0.34, wheel_width=0.22, tire_grip=1.08, rear_grip_scale=0.97,
        front_spring_rate=36000, rear_spring_rate=32000, front_damper_bump=2700, front_damper_rebound=3600,
        rear_damper_bump=2500, rear_damper_rebound=3400, front_anti_roll=13000, rear_anti_roll=12000,
        idle_rpm=750, redline_rpm=6200, launch_rpm=2600, max_torque=230,
        torque_curve=[(1000, .62), (1500, 1.0), (3500, 1.0), (5000, .82), (6200, .6)],
        engine_brake_torque=55, gear_ratios=[3.77, 2.24, 1.46, 1.08, 0.86, 0.72], reverse_ratio=3.6,
        final_drive=3.9, auto_upshift_rpm=5800, auto_downshift_rpm=2000, drive_type=FWD, diff_lock=0.1,
        brake_torque=6200, brake_bias=0.68, handbrake_torque=2600, max_steer_deg=33, steer_rate=3.8,
        drag_area=0.88, downforce_area=0.0, engine_sound_pitch=1.15, engine_sound_gain_db=-0.5),
    "passat": dict(  # Passat 2.0 BiTDI 4MOTION: 240 hp, 500 Nm, 1700 kg, 7-speed DSG
        wheel_inertia=1.5,
        display_name="VW Passat 2.0 BiTDI 4MOTION", mass=1700, center_of_mass=(0, 0.47, -0.15), inertia_box_size=(1.83, 1.35, 4.77),
        wheel_radius=0.34, wheel_width=0.24, tire_grip=1.14, rear_grip_scale=0.98,
        front_spring_rate=42000, rear_spring_rate=40000, front_damper_bump=3100, front_damper_rebound=4100,
        rear_damper_bump=3000, rear_damper_rebound=4000, front_anti_roll=15000, rear_anti_roll=12000,
        idle_rpm=750, redline_rpm=4800, launch_rpm=2200, max_torque=420,
        torque_curve=[(1000, .55), (1750, 1.0), (2500, 1.0), (3800, .85), (4800, .6)],
        engine_brake_torque=80, gear_ratios=[3.56, 2.53, 1.59, 0.94, 0.72, 0.6, 0.5], reverse_ratio=3.2,
        final_drive=4.1, auto_upshift_rpm=4400, auto_downshift_rpm=1700, drive_type=AWD, diff_lock=0.3,
        awd_front_split=0.55, brake_torque=8200, brake_bias=0.67, handbrake_torque=3000, max_steer_deg=33,
        steer_rate=3.8, drag_area=0.64, downforce_area=0.08, engine_sound_pitch=0.9, engine_sound_gain_db=0.0),
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


# Gear shift times (s, engine cut while changing) and turbos (share of torque
# from boost, lag in seconds) per car.
DRIVETRAIN = {
    "kartal": dict(shift_time=0.35), "atmaca": dict(shift_time=0.3), "kerkenez": dict(shift_time=0.3),
    "mirelle": dict(shift_time=0.3, turbo=0.4, turbo_lag=0.8, turbo_spool_rpm=1500),
    "quadra": dict(shift_time=0.12, turbo=0.4, turbo_lag=0.7, turbo_spool_rpm=1500),
    "romola": dict(shift_time=0.25, turbo=0.4, turbo_lag=0.7, turbo_spool_rpm=1500),
    "kaze": dict(shift_time=0.25), "piccolo": dict(shift_time=0.25), "harcourt": dict(shift_time=0.3),
    "dingo": dict(shift_time=0.2, turbo=0.35, turbo_lag=0.6, turbo_spool_rpm=1800),
    "mammoth": dict(shift_time=0.2, turbo=0.45, turbo_lag=0.9, turbo_spool_rpm=1400),
    "bastion": dict(shift_time=0.2, turbo=0.4, turbo_lag=0.8, turbo_spool_rpm=1500),
    "bavaro": dict(shift_time=0.15, turbo=0.35, turbo_lag=0.5, turbo_spool_rpm=1700),
    "braxton": dict(shift_time=0.2), "e30": dict(shift_time=0.3),
    "troc": dict(shift_time=0.12, turbo=0.4, turbo_lag=0.55, turbo_spool_rpm=1500),
    "passat": dict(shift_time=0.1, turbo=0.45, turbo_lag=0.7, turbo_spool_rpm=1500),
    "ashford": dict(shift_time=0.12, turbo=0.35, turbo_lag=0.45, turbo_spool_rpm=2000),
    "bellmont": dict(shift_time=0.1, turbo=0.35, turbo_lag=0.45, turbo_spool_rpm=1900),
}
for cid in CARS:
    if cid in DRIVETRAIN:
        CARS[cid].update(DRIVETRAIN[cid])

import sys
ONLY = sys.argv[1:]  # e.g. python tools/make_car_configs.py e30 troc (others keep their tuned .tres)
for cid, props in CARS.items():
    if ONLY and cid not in ONLY:
        continue
    out = os.path.join(ROOT, "assets", "cars", cid, cid + ".tres")
    lines = ['[gd_resource type="Resource" script_class="VehicleConfig" load_steps=2 format=3]', "",
             '[ext_resource type="Script" path="res://scripts/vehicle/vehicle_config.gd" id="1_cfg"]', "",
             "[resource]", 'script = ExtResource("1_cfg")']
    for key, value in props.items():
        lines.append("%s = %s" % (key, fmt(value)))
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", os.path.relpath(out, ROOT))
