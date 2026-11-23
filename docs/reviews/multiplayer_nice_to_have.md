# Multiplayer: nice-to-have changes

*Snapshot · 2026-11-23 · static code review only (Godot not run).* These aren't blockers, but each one makes the multiplayer work easier or the Web build better. For the must-fix list, see [multiplayer_must_fix.md](multiplayer_must_fix.md). *Found by* shows which reviewer reported it: **A**, **B**, or **both**.

## Gameplay and simulation

| ID | Change | Evidence | Fix | Effort | Found by |
|---|--------|----------|-----|--------|----------|
| NH-1 | *Moved to MF-11: tournaments must work online.* | — | — | — | — |
| NH-2 | **Detached wheels collide with the world.** They're physics bodies on the world layer, so car raycasts and car bodies hit them, and they're never sent to other peers. | `wheel.gd:113, 302-324`; `car_damage.gd:147` | Put them on their own layer that cars ignore, or make them visual-only. | S | both |
| NH-3 | **Logic keyed to the global frame counter.** The draft check and standings cache use `Engine.get_physics_frames()`, which counts differently on each peer. | `vehicle.gd:448`; `race_director.gd:252, 273` | Use the race tick instead. | S | both |
| NH-4 | **Float timers.** Race time, lap time and clocks are floats. | `lap_timer.gd:35, 81`; `race_director.gd` | Use integer ticks, which are exact and easy to send. | S | both |
| NH-5 | **Perks update order.** CarPerks sets power and grip in its own physics update, which runs after the Vehicle's, so it's one tick behind. | `car_perks.gd:12, 115` (uncertain) | Call it from the Vehicle update in a fixed order. | S | A |
| NH-6 | **Pit service has several writers.** Pit state is changed in the Vehicle and also overrides the input. | `vehicle.gd:460-491` | Make it state owned by the host. | S | B |
| NH-7 | **Upgrades change car configs at spawn.** Every peer has to apply them identically. | `upgrades.gd:245-259` | Work them out from `RaceConfig` on every peer. | S | B |

## Structure and code quality

| ID | Change | Evidence | Fix | Effort | Found by |
|---|--------|----------|-----|--------|----------|
| NH-8 | **Group lookups assume one race per game instance.** The HUD can fall back to another car's lap timer. | `hud.gd:91-100`; `vehicle.gd:462, 618, 683`; `ai_driver.gd:123, 158`; `car_perks.gd:124, 281` | Pass references in at spawn. | S | both |
| NH-9 | **Local player found by type checks** (`input is PlayerInput`). | `retro_look.gd:58-68`; `game_settings.gd:185-188` | Use an explicit local-player list or an `is_local_human` flag. | S | both |
| NH-10 | **Scene changes are scattered** across hotkeys and menus. | `drive_mode.gd:81-85`; `versus_mode.gd:40-42`; `main_menu.gd:327` | Route them all through one scene-flow manager that knows whether a race is online. | S | A |
| NH-11 | **Car state is spread across many fields.** | `vehicle.gd:71, 74-115` | Group them into one `VehicleState` struct, and move profile/restart/recover handling out of Vehicle. | S–M | B |
| NH-12 | **Racer names come from display strings.** | `race_setup.gd:79` | Use ids; display names are for showing only. | S | B |
| NH-13 | **The three 1,000+ line files** (`vehicle.gd`, `circuit.gd`, `track_dressing.gd`). | — | Split them by responsibility as part of the simulation/visuals split. | M | overview |

## Web and dedicated server

| ID | Change | Evidence | Fix | Effort | Found by |
|---|--------|----------|-----|--------|----------|
| NH-14 | **Collision shapes are built from render meshes at runtime.** This works headless today, but a server build without visual assets would have no collision. | `vehicle.gd:791-929`; `car_damage.gd:237-260`; `track_dressing.gd:649-656` | Bake the hulls and building shapes into resources. | M | B |
| NH-15 | **A server would build all the visuals** (terrain meshes, sky, HUD, the retro effect), and the track is generated all at once during loading. | `circuit.gd:101-116`; `terrain.gd:38`; `car_paint.gd:15-40` | Add a no-visuals server flag and build the track in steps. | M | both |
| NH-16 | **Track generation may differ across platforms.** It's seeded, but float comparisons decide whether random numbers get drawn, so Windows and Web could diverge. | `track_dressing.gd:880-907, 1018` | Compare a checksum of the generated collision with the host's after loading. | S | both |
| NH-17 | **Track-select video clips** (18 MB of Theora) decode slowly on Web. | `track_select.gd:12, 44, 160` | Use still images or smaller clips on Web. | S | both |
| NH-18 | **Audio cost on Web.** About 9 3D sound players per car, roughly 72 for 8 cars, with constant pitch changes. | `car_audio.gd:38-53` | Lower audio detail for distant cars. | S | B |
| NH-19 | **Soundtrack licence.** The MP3s are kept out of git but would ship inside a public Web build. | `.gitignore` | Check the licence covers browser distribution. | S | A |

## Already good for multiplayer (both reviewers agree)
- Every driver (player, AI, replay) goes through the one `VehicleInput` interface, so a `NetworkInput` fits in naturally.
- Fixed 120 Hz physics with physics interpolation on, and `teleport()` already resets interpolation.
- Tracks are built from data with fixed seeds, so peers only need the track id, not the track itself.
- Cars are described by `car_id + paint + livery`, so spawn messages are tiny.
- Damage state is compact (5 zones, with `restore()`/`repair()`), and `Upgrades.offers` takes an injected RNG.
- The game already checks for headless mode before using audio, the window and lights, and many tests run headless at a fixed rate, which makes a good base for server tests.
