# Damage effects — research notes (2026-11-22)

## Where the game is today
- No damage. Hard hits only play a thud (CarAudio guesses hits from sudden velocity changes).
- Design doc: "Damage On" is listed as a race modifier; open question 5 asks "visual only or mechanical?".
- Car collision = two boxes (lower body + cabin) sized from the model. Any dents will be visual only
  (like nearly every racing game); handling changes come from a damage model, not from the shape.

## Measured in our game (tests/damage_probe.gd)
Bavaro (1600 kg) driven straight into the trackside barrier, and into a parked car:

| Hit | Peak contact impulse (Jolt) | Biggest velocity change | Hit point on the car |
|---|---|---|---|
| Barrier 60 km/h | 16 400 Ns | 18.6 m/s | front centre (z = -2.36) |
| Barrier 100 km/h | 28 000 Ns | 32.1 m/s | front centre |
| Barrier 150 km/h | 39 100 Ns | 39.2 m/s | front-left corner, high (car spun) |
| Car 40 km/h | 3 900 Ns | 4.9 m/s | front-left corner |
| Car 90 km/h | 9 600 Ns | 10.9 m/s | front-left corner |

- `PhysicsDirectBodyState3D.get_contact_impulse()` works with Jolt (values are *estimates*, per Godot's
  Jolt docs) and scales cleanly with speed, so it is good enough to drive damage. Needs `contact_monitor`.
- `get_contact_local_position()` gives the hit point (world space) on our car's collision boxes — fine for
  "which corner / zone" and the dent centre.
- Ground contacts must be ignored (wheels are raycasts, but body scrapes on grass/kerbs also report).
- Denting a whole car body mesh on the CPU in GDScript (move vertices within 0.8 m of the hit, rebuild):
  **~0.4–0.5 ms + ~0.3 ms** for 10–12k vertices. Cheap enough to do on every real impact, for every car.
  Each car needs its own copy of its mesh (imported meshes are shared): ~0.5 MB per car.

## How other games do it (and what fits RRS)
- **Destruction Derby (PS1, 1995):** early car deformation, simple / precomputed. The right *feel* for us.
- **Burnout / FlatOut / Wreckfest / TRAIL OUT:** layered — vertex dents at impact points, morph targets for
  big crumples, rigid-body detachable parts (bumpers, doors, bonnets) on constraints, sparks and debris.
- **BeamNG / Next Car Game:** full soft-body simulation. Too heavy and not the PS1 style; skip.
- Godot's SoftBody3D has no permanent (plastic) deformation, so a custom system is the usual route.

## Building blocks for RRS
1. **Damage model** (per car): hits → damage in zones (front, rear, left, right, roof) + engine / wheels.
   Ignore small taps (threshold), scale by impulse, clamp per hit.
2. **Visual:** vertex dents (radius-limited, pushed along the hit direction, capped so they never reach the
   wheels or poke through), livery mesh dented the same way, scuffed / darkened paint (vertex colour), broken
   head / brake lamps (lamp glow off), cracked windscreen (swap glass material), sparks when scraping
   barriers or other cars, a puff of debris on big hits, engine smoke when the front is badly hurt.
3. **Loose parts:** generator exports bumpers, mirrors, spoiler, bonnet as separate nodes; they wobble /
   hang, then fall off as short-lived debris bodies.
4. **Mechanical (optional):** engine power loss and smoke, top-speed drop, steering pull from a bent wheel,
   wheel wobble, (much later) punctures. Kept arcade-fair.
5. **Setting:** DAMAGE in race settings: OFF / VISUAL / FULL. Recover (R / Y) could repair a little.
6. **HUD:** small car outline whose zones turn yellow / red.

## Suggested phases
1. Damage model + setting + sparks / impact particles + HUD outline (no visuals on the car yet).
2. Dents + scuffs + broken lamps + cracked glass (VISUAL).
3. Loose / falling parts (generator change).
4. Mechanical effects + engine smoke (FULL).

## Built (2026-11-22): "Visual + light mechanical"
- `scripts/vehicle/car_damage.gd` (CarDamage, added by Vehicle unless DAMAGE is OFF or the scene is in group
  `no_damage`, e.g. the main menu). Hits from Jolt contacts (ground = colliders with `surface_grip` meta are
  ignored), speed change = impulse / mass, damage from 1.8 m/s up, max 0.6 per hit, five zones.
- Dents every non-wheel mesh of the model (livery too) round the hit, at bumper / door height, with smooth
  crumple, bent shading normals and darker paint (vertex colours; psx_lit `vertex_tint`).
- Head lamps out at front > 0.5, brake lamps out at rear > 0.5; sparks while scraping; debris on big hits;
  engine smoke from front > 0.45.
- FULL: engine power down to 60 % with front damage, up to +15 % drag, steering pull towards a damaged side.
- Race settings row DAMAGE (OFF / VISUAL / FULL, default FULL); HUD outline beside the dial.
- Tests: `tests/damage_test.gd`, pictures: `tests/screenshot_damage.gd`.
