# RRS — Random Racing Series
### Game Design Concept · v0.1 (draft)
*Date: 2026-11-22 · Engine: Godot 4.7 · Art pipeline: Blender 5.3 → glTF · Built with Godot MCP + Blender MCP*

---

## 1. One-line pitch

**A physics-driven racing game that sits between sim and arcade. Every championship is rolled fresh: random cars, random tracks, random weather, random rules. Learn the car, read the road, adapt.**

The car should feel heavy, grippy and believable, the way a real car does when you push it. It should forgive the player the way a good arcade racer does. The "Random Series" structure gives every session a new puzzle, so the game never becomes "memorise one car on one track".

---

## 2. Design pillars

| # | Pillar | What it means in practice |
|---|--------|---------------------------|
| 1 | **Weight you can feel** | Real mass, load transfer, suspension and tire slip drive the handling. Nothing is faked with "turn rate" values. |
| 2 | **Forgiving at the limit** | Assists, slide recovery and generous grip falloff let players drive at 9/10ths without spinning on every mistake. |
| 3 | **Every series is different** | Procedural championships combine car class, track, weather and modifiers, so no two runs feel the same. |
| 4 | **Readable and responsive** | Clear audio and visual feedback (tire squeal, camera shake, FFB-style cues) tell the player what the tires are doing. Low input latency. |
| 5 | **Small team, smart pipeline** | Modular cars and tracks built in Blender, assembled in Godot, automated through MCP tooling. |

---

## 3. Target experience

- **Genre:** Semi-realistic / semi-arcade circuit and point-to-point racing.
- **Reference feel (not content):** The weight of a "sim-cade" racer, the approachability of an open-world arcade racer, and the session-to-session variety of a roguelite.
- **Platform:** PC (Windows) first. Gamepad is the primary input, with keyboard and wheel supported.
- **Session length:** 3–6 minute races. A full "Series" takes 20–40 minutes.
- **Perspective:** Chase cam (default), bumper cam, hood cam and cockpit cam (later milestone).

---

## 4. Core loop

```
 ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
 │  Roll Series │ ─▶ │ Pick / Tune  │ ─▶ │     Race     │ ─▶ │   Results &  │
 │ (randomizer) │    │  your car    │    │  (3–5 events)│    │   Rewards    │
 └──────────────┘    └──────────────┘    └──────────────┘    └──────┬───────┘
        ▲                                                         │
        └──────────── unlock cars / parts / modifiers ◀───────────┘
```

1. **Roll a Series.** The randomizer picks a car class, 3–5 events (track + layout + weather + time of day) and 0–2 **Series Modifiers**.
2. **Pick / tune.** Choose from a short random draft of cars in the class and adjust a few tuning sliders.
3. **Race.** Points across the events decide the championship.
4. **Rewards.** Credits and unlocks (new cars, tuning parts, new modifier types, track variants).

---

## 5. The "Random" system

### 5.1 Series generator inputs

| Dimension | Example values |
|-----------|----------------|
| Car class | Hot Hatch · Rally (gravel) · GT · Muscle · Formula-lite · "Mixed bag" |
| Track | Circuit · Mountain pass · City streets · Rally stage · Oval |
| Layout | Full · Short · Reverse · Point-to-point segment |
| Weather | Dry · Damp · Rain (wet grip) · Fog · Snow (late) |
| Time of day | Dawn · Noon · Sunset · Night (headlights) |
| Modifiers | *Low Grip Tires*, *Heavy Fuel*, *No ABS*, *Mirror Track*, *Reverse Grid*, *Draft Boost*, *Ghost Rivals*, *Damage On* |

### 5.2 Rules
- Seeded RNG (`series_seed`). Players can share a seed so friends can race the same Series.
- Weighted tables, so harsh combinations (snow + Formula-lite + No ABS) are rare and can be flagged as "Hard Series" for bonus rewards.
- Difficulty rating is computed from the roll and shown before the player commits.
- **Daily Series:** one fixed seed per day for everyone (leaderboard later).

---

## 6. Vehicle physics & handling (the heart of the game)

### 6.1 Approach
We use **a custom raycast vehicle on a `RigidBody3D`**, not Godot's built-in `VehicleBody3D`. We need full control over tire forces, and the stock wheel model is too limited for the feel we want.

- Physics backend: **Jolt** (Godot's built-in 3D physics engine option).
- Physics tick: **120 Hz** (`physics/common/physics_ticks_per_second = 120`). The visual layer interpolates.
- Units: **1 unit = 1 metre, kg, seconds, Newtons.**

### 6.2 Simulation layers

| Layer | Model | Semi-real / semi-arcade knob |
|-------|-------|------------------------------|
| **Suspension** | One raycast (or shape-cast) per wheel. Spring + damper (bump/rebound), anti-roll bars. | Stiffness presets per class |
| **Tires** | Simplified **Pacejka "Magic Formula"** curves for longitudinal and lateral force, combined with a friction circle/ellipse. Load sensitivity included. | Grip multiplier, peak-slip width (wider = more forgiving) |
| **Load transfer** | Emerges from the suspension and centre of mass. Not scripted. | CoM height tweak |
| **Drivetrain** | Engine torque curve → clutch → gearbox (auto/manual) → differential (open / LSD / locked) → wheels. | Auto-blip, auto-clutch |
| **Brakes** | Torque per wheel, brake bias, optional ABS. | ABS strength |
| **Aero** | Drag + downforce ∝ v², front/rear balance. | Downforce multiplier |
| **Surfaces** | Physics material → grip, rolling resistance, particle and sound set (asphalt, curb, grass, gravel, wet). | Off-track penalty strength |

### 6.3 The "arcade" assists (what makes it *semi*-arcade)
These sit **on top of** the physics. They are corrective forces and input shaping, never replacements:

1. **Steering assist:** speed-sensitive steering lock, plus auto counter-steer that eases toward the velocity direction during slides.
2. **Stability assist:** a small yaw-damping torque when the yaw rate exceeds what the steering asks for. Off in "Sim" mode.
3. **Traction control & ABS:** slip-ratio limiting, with strength 0–100%.
4. **Drift-friendly grip falloff:** after peak slip angle the lateral curve stays high (≈85–90% of peak) instead of dropping off a cliff. Slides are long and controllable.
5. **Air control (small):** limited pitch/roll correction when airborne, for rally jumps.
6. **Catch-up and assists off in ranked/daily.**

A single **Handling Profile** slider sets all of these together, with an advanced menu for individual control:

| Profile | Assists | Tire falloff | Who it's for |
|---------|---------|-------------|--------------|
| **Arcade** | High | Very forgiving | Gamepad, casual |
| **Sport** (default) | Medium | Forgiving | Most players |
| **Sim** | Off / ABS only | Realistic | Wheel users, purists |

### 6.4 Feel targets (measurable)
- 0–100 km/h for a Hot Hatch ≈ 7–8 s. GT ≈ 4 s.
- Max lateral g ≈ 1.0 (road tires) to 1.4 (slicks + aero) in Sport profile.
- A player on gamepad should hold a 3-second slide on the test track within their first 10 minutes.
- Input-to-response latency under 50 ms at 60 fps.

### 6.5 Debug tooling (built first)
- In-game telemetry overlay: per-wheel load, slip ratio, slip angle, suspension compression, grip usage circle.
- Live tuning panel for every `VehicleConfig` value, reloaded at runtime.
- A test track with a skidpad, slalom, braking zone and jump.

---

## 7. Cars

### 7.1 Launch roster target (fictional, original designs)
| Class | Count (MVP → 1.0) | Drivetrain notes |
|-------|-------------------|------------------|
| Hot Hatch | 1 → 3 | FWD, light, nimble |
| GT | 1 → 3 | RWD, aero |
| Rally | 0 → 2 | AWD, long-travel suspension |
| Muscle | 0 → 2 | RWD, heavy, torquey |
| Formula-lite | 0 → 1 | RWD, high downforce |

All cars are **original designs**. No licensed or real-brand vehicles.

### 7.2 Car data model (`VehicleConfig` resource)
`mass`, `center_of_mass`, `inertia_scale`, `wheelbase/track`, per-axle `spring_rate / damper_bump / damper_rebound / anti_roll / rest_length / max_travel`, `tire_curve (long/lat)`, `torque_curve`, `gear_ratios`, `final_drive`, `diff_type`, `brake_torque`, `brake_bias`, `drag_coef`, `downforce_coef`, `aero_balance`.

### 7.3 Tuning (player-facing, kept simple)
Brake bias · Diff lock · Ride height · Spring stiffness (soft↔stiff) · Downforce · Gear length.

---

## 8. Tracks & environments

- **MVP:** 1 test track + 1 circuit with 2 layouts.
- **1.0 target:** 5 environments × 2–3 layouts each.
- **Modular track kit** made in Blender: road straights, curves at set radii, junctions, curbs, barriers, run-off and props. Layout splines are assembled in Godot with a road-mesh generator (`Path3D` → extruded road) so the randomizer can create **layout variants**.
- Track data: racing line spline (AI), checkpoints, sector splits, spawn grid, surface zones, camera points for replays.

---

## 9. AI opponents

- **Spline-following AI** that drives through **the same physics and input layer** as the player. AI does not cheat on grip.
- Racing line + braking points baked from the track spline (curvature → target speed).
- Behaviours: overtaking lanes, defending, collision avoidance, mistakes scaled by skill.
- Difficulty: skill (line accuracy, braking precision) and aggression. Light rubber-banding only in Arcade profile.
- Field size: 8 cars at MVP, up to 12–16 later.

---

## 10. Game modes

| Mode | Milestone |
|------|-----------|
| Free Roam / Test Track | MVP |
| Single Race (pick anything) | MVP |
| Time Trial + ghost | MVP |
| **Random Series** (core mode) | Alpha |
| Daily Seed Series | Beta |
| Split-screen / Online | Post-1.0 (stretch) |

---

## 11. Camera, audio & feedback

- **Chase cam:** spring-arm with velocity look-ahead, FOV that widens with speed, slight lag on yaw so slides read clearly, and subtle shake on curbs and impacts.
- **Audio:** layered engine sound (on/off-load samples crossfaded by RPM), tire squeal driven by slip, wind, gear-shift clunks, surface rumble.
- **Visual feedback:** skid marks, tire smoke, gravel/grass particles, brake glow, speed lines (Arcade only).
- **Controller rumble** mapped to tire slip and surface.

---

## 12. UI / HUD

- HUD: speed, gear, RPM bar with shift light, position, lap/sector times, mini-map, assist indicators.
- Menus: Main → Series (roll / reroll / seed entry) → Car draft → Tuning → Race → Results.
- Visual style: clean, bold motorsport typography, high contrast, colour-coded by series class.

---

## 13. Art direction

- **Stylised-realistic:** believable proportions and PBR materials, slightly saturated colours, clean shapes. This look is achievable for a small team and keeps a consistent identity.
- Cars: about 30–60k tris LOD0, with 2 LODs. Livery uses a shared "paint mask" material so the randomizer can generate team colours.
- Environments: modular kits and trim sheets. Godot `GPUParticles3D` for effects. SDFGI or baked lightmaps, decided by performance tests.

---

## 14. Technical architecture (Godot 4.7)

### 14.1 Project layout
```
res://
├─ addons/                 # editor tools, (optional) MCP helper plugins
├─ assets/
│  ├─ cars/<car_id>/       # .glb from Blender, textures, VehicleConfig .tres
│  ├─ tracks/<track_id>/   # .glb kit pieces, layouts, track data
│  ├─ audio/  vfx/  ui/
├─ scenes/
│  ├─ vehicle/             # Vehicle.tscn (RigidBody3D + Wheel nodes)
│  ├─ tracks/  ui/  modes/
├─ scripts/
│  ├─ vehicle/             # vehicle.gd, wheel.gd, tire_model.gd, drivetrain.gd, assists.gd
│  ├─ ai/  series/  race/  camera/  input/
└─ tests/                  # handling regression scenes
```

### 14.2 Key systems
- `Vehicle` (RigidBody3D) owns 4× `Wheel` (Node3D + RayCast/ShapeCast). Wheels compute forces in `_physics_process` and apply them with `apply_force` at the contact point.
- `VehicleInput` is an interface fed by `PlayerInput`, `AIDriver` or `ReplayPlayer`, so all three drive identically.
- `SeriesGenerator` takes a seeded `RandomNumberGenerator` and weighted `Resource` tables, and outputs a `SeriesDefinition`.
- `RaceDirector` handles grid, countdown, laps, checkpoints, positions and results.
- **Language:** GDScript first. Port the tire/wheel hot path to C++ GDExtension only if profiling shows a need.

### 14.3 Performance budget
60 fps at 1080p on a mid-range GPU with 8 AI cars. Physics cost under 2 ms per frame for 9 vehicles at 120 Hz.

---

## 15. Asset pipeline: Blender → Godot

1. Model in Blender at **real-world scale (metres)**, **+Y forward in Blender → exported as glTF (-Z forward in Godot)**. Apply all transforms before export.
2. **Car hierarchy convention:**
   ```
   car_<id>            (root, origin at ground centre between axles)
   ├─ body             (main mesh, paint material slot "paint")
   ├─ wheel_FL / wheel_FR / wheel_RL / wheel_RR   (origin at hub centre)
   ├─ brake_FL ... (caliper, does not rotate)
   ├─ col_body-colonly (simplified convex collision)
   └─ lights_head / lights_brake (emissive slots)
   ```
3. Export **.glb**. Godot import hints: `-colonly`, `-convcolonly` for collision; per-asset import scripts set materials and LODs.
4. Tracks: kit pieces with `-colonly` trimesh collision and surface-type naming (`_asphalt`, `_curb`, `_grass`, `_gravel`) mapped to physics materials.

---

## 16. How we build it with MCP

| Tool | Used for |
|------|----------|
| **Blender MCP** (`mcp-for-blender`) | Blocking out car bodies and track kit pieces, setting up hierarchy and naming, materials, exporting .glb. Inspecting scenes and taking viewport screenshots for review. |
| **Godot MCP** (`@coding-solo/godot-mcp`) | Creating scenes and nodes, running the project, reading debug output and errors, launching the editor, managing UIDs. |
| **Claude Code (files)** | Writing GDScript, resources (`.tres`) and project settings directly. |

**Typical loop:** block out a mesh in Blender → export .glb into `res://assets/...` → build or update the scene in Godot → run the test track → read debug output → tune → repeat.

---

## 17. Roadmap

| Milestone | Goal | Key deliverables |
|-----------|------|------------------|
| **M0 Setup** | Tools ready | MCPs connected, Godot project, folder structure, git repo |
| **M1 Handling Prototype** | "The car feels good" | Raycast vehicle, tire model, drivetrain, chase cam, telemetry overlay, test track, greybox car |
| **M2 First Track** | Lap a real circuit | Track kit v1, 1 circuit, lap timing, surfaces, skid marks, audio v1 |
| **M3 Racing** | Race against AI | AI driver, race director, HUD, Single Race + Time Trial |
| **M4 Random Series (Vertical Slice)** | The core loop works | Series generator, modifiers, weather (dry/wet), car draft, results/rewards |
| **M5 Content Alpha** | Variety | 5+ cars, 3 environments, night, more modifiers |
| **M6 Beta → 1.0** | Polish | Menus, settings, wheel support, daily seed, optimisation, balancing |

---

## 18. Risks & mitigations

| Risk | Mitigation |
|------|-----------|
| Handling feels "floaty" or "twitchy" | Build telemetry and live tuning first (M1). Test against fixed numeric targets (§6.4). |
| Physics instability at high speed | 120 Hz tick, wheel shape-casts, clamped forces, CCD on the body. |
| Random combinations aren't fun | Weighted tables, difficulty rating, rerolls, playtest data on which combinations get rerolled. |
| Art scope too large | Modular kits, shared materials, stylised-realistic look, small roster that grows. |
| MCP tooling limits | Fall back to writing scene and script files directly. Godot `.tscn`/`.tres` files are plain text. |

---

## 19. Open questions (for you to decide)

1. **What does "Random" mean to you?** This doc assumes randomised championships. Alternatives: random cars only, fully procedural tracks, or a chaotic party-game tone.
2. **Tone:** clean motorsport, or a little playful and colourful?
3. **Tracks:** real-world-*inspired* circuits, or fully fictional locations?
4. **Multiplayer:** in scope for 1.0 (split-screen?) or post-launch?
5. **Damage:** visual only, or mechanical (affects handling)?
6. **First car to prototype:** Hot Hatch (FWD, easiest to tune) or GT (RWD, more drift-fun)?

---

*End of concept v0.1. Next step: M0 setup, then M1 handling prototype.*
