# Multiplayer: must-fix before netcode work

*Snapshot · 2026-11-23 · static code review only (Godot not run).*

**Target:** up to 8 players online, 2-player split-screen that can also join online races, Windows + Web cross-play, either platform can host (listen server), dedicated server later. Jolt physics, 120 Hz.

**Must-fix** = blocks networking/Web, guarantees desync, or makes later rework much more expensive. Smaller items are in [multiplayer_nice_to_have.md](multiplayer_nice_to_have.md).

**Method:** two independent reviewers got the same brief; findings were merged and the key citations spot-checked. Fixed items are marked `✅ Fixed in #<PR>` next to their heading. *Found by* shows who reported each issue: **A**, **B**, or **both**.

## Summary

| ID | Issue | Severity | Effort | Found by |
|---|-------|----------|--------|----------|
| MF-1 | No network model or transport chosen; Web hosting needs WebRTC | blocker | M–L | A |
| MF-2 | Forward+ renderer can't run on Web | blocker | M | both |
| MF-3 | Race rules read from each machine's local `GameSettings` | blocker | M | both |
| MF-4 | Handling profile and restart/recover are local, not per-racer | blocker | S–M | both |
| MF-5 | Human players are fixed scene nodes; racers identified by index/name | blocker | L | both |
| MF-6 | Race authority and scene flow live in a UI node, run on every peer | high | M | both |
| MF-7 | Input layer isn't network-shaped; P1/P2 hard-coded | high | M | both (B rated it nice-to-have) |
| MF-8 | Vehicle mixes simulation and visuals; no state snapshot | high | L | both |
| MF-9 | Gameplay randomness uses the unseeded global RNG | high | S | both |
| MF-10 | Web host CPU budget at 120 Hz is unmeasured | high | M | both |
| MF-11 | Tournament is single-machine static state | high | M | both (A rated it nice-to-have) |

Suggested order: **MF-1 and MF-2 first** (they're decisions that shape everything), then **MF-3, MF-4, MF-9** (small and cheap), then **MF-5, MF-6, MF-7, MF-8** (the big refactors), with **MF-10** measured alongside. **MF-11** builds on MF-3, MF-5 and MF-6.

---

## MF-1. No network model or transport chosen; Web hosting needs WebRTC
- **Evidence:** no networking code anywhere; no `export_presets.cfg` (git-ignored); `addons/` is empty.
- **Why it matters:**
  - A browser can't accept incoming connections, so a Web player can't host over WebSocket. Web hosting means `WebRTCMultiplayerPeer`, which needs a signalling server and STUN/TURN.
  - Windows players need the webrtc-native GDExtension to talk to Web peers.
  - Jolt isn't deterministic between Windows x64 and wasm, so lockstep is out. A Godot `RigidBody3D` can't be re-simulated on its own, so textbook rollback is out too.
- **Fix:** pick the model now: server-authoritative snapshots with interpolated remote cars (recommended), or owner-simulated cars checked by the host. Prototype a WebRTC host from both Windows and Web, with signalling and TURN, before writing any gameplay networking. Add Windows, Web and Linux-server export presets.
- **Effort:** M–L

## MF-2. Forward+ renderer can't run on Web
- **Evidence:** `project.godot:16` (features "Forward Plus"), `project.godot:43` (`rendering_method="forward_plus"`).
- **Why it matters:** a Web build fails or renders differently, so there's no Web host or client and no cross-play.
- **Things to check under the Compatibility renderer** (support uncertain until tested):
  - Screen and depth texture reads: `screen_fx.gdshader:11-12`, `water.gdshader:7`, `psx_post.gdshader:6`.
  - Glow, fog and adjustments: `atmosphere.gd:123-132`, `retro_look.gd:124-139`.
  - Clearcoat and detail textures on car materials: `vehicle.gd:748-750, 981-985`.
  - GPU particles: `wheel_dirt.gd:41-78`.
  - Night lights: a SpotLight3D per car (`vehicle.gd:694-703`) and many OmniLight3D trackside (`track_dressing.gd:272-310`). Compatibility limits lights per object.
- **Fix:** switch to `gl_compatibility` on all platforms (simplest, and Windows and Web then look the same), or use a per-platform override. Port and test the items above, and do all future visual work in that renderer.
- **Effort:** M

## MF-3. Race rules read from each machine's local `GameSettings`
- **Evidence:** every value below is a `static var` loaded from `user://settings.cfg` (`game_settings.gd:21-61, 67-114`):
  - Track: `circuit.gd:88`
  - Laps: `race_director.gd:51-55`
  - AI count, difficulty and classes: `race_setup.gd:43-49, 67`
  - Tyre wear: `vehicle.gd:145`
  - Damage level and durability: `vehicle.gd:179-188`, `car_perks.gd:122`
  - Time of day and weather: `circuit.gd:283-287`, `vehicle.gd:683, 970`
- **Why it matters:** peer A has damage FULL and 3 laps; the host has damage OFF and 5 laps. Each builds a different race, so they desync immediately.
- **Fix:** add a serializable `RaceConfig` (track id, laps, damage, wear, durability, weather, seed, AI list, per-racer car, paint and profile). The host builds it from its menus and sends it to every peer. Gameplay code reads only `RaceConfig`; `GameSettings` keeps menu defaults and video/audio settings.
- **Effort:** M

## MF-4. Handling profile and restart/recover are local, not per-racer
- **Evidence:**
  - Every Vehicle, including AI and remote humans, takes the local `GameSettings.handling_profile` (`vehicle.gd:171`). The profile changes tyre shape and assists (`vehicle.gd:208-214`, `assists.gd:30-46`).
  - The P key changes the profile mid-race and saves it to disk (`vehicle.gd:592-595`). `apply_live` applies it to every `PlayerInput` car, so both split-screen players share one profile (`game_settings.gd:185-188`).
  - Restart and recover teleport the car locally (`vehicle.gd:596-601, 615-637`); AI resets teleport too (`ai_driver.gd:103`).
- **Why it matters:** the host simulates a remote player's car with the *host's* assists. A client pressing R or Backspace teleports its own copy of the car while the host's copy stays where it was.
- **Fix:** make the profile a per-racer field in `RaceConfig`, locked during the race. Restart, recover and profile changes become requests the host carries out.
- **Effort:** S–M

## MF-5. Human players are fixed scene nodes; racers identified by index/name
- **Evidence:**
  - `circuit_race.tscn` has 1 player car; `versus_race.tscn` has fixed `Car1`/`Car2`, LapTimer1/2, HUD1/2 and Camera1/2.
  - The race scene is chosen by local player count: `players == 2 ? VERSUS : RACE` (`tournament.gd:332-333`).
  - Racer index is the order cars are added, AI first (`race_setup.gd:77-121`, `race_director.gd:65`).
  - Tournament humans are named "YOU" / "PLAYER 1/2" and looked up by name (`tournament.gd:53-57, 98, 152`; `race_setup.gd:127-132`).
- **Why it matters:** there's no scene for 8 racers coming from several peers with 0–2 local players each. Indices and node paths differ between peers, so network messages and synchronizers hit the wrong car. Two remote players both called "YOU" collide.
- **Fix:** one race scene that spawns every car (human and AI) from `RaceConfig` entries with a stable `racer_id`, `owner_peer`, `local_slot`, car and control type. Name nodes by `racer_id` and key all race and tournament data by it. Create a camera, viewport and HUD per local slot at runtime, so split-screen becomes "this peer has 2 local slots".
- **Effort:** L

## MF-6. Race authority and scene flow live in a UI node, run on every peer
- **Evidence:**
  - `RaceDirector extends Control` (`race_director.gd:1-2`) and handles both the race logic and the drawing.
  - Countdown, finish order and DNF timers are local (`race_director.gd:84-90, 95-115, 136-159`).
  - The race only ends when every human has finished, with no timeout (`race_director.gd:101-107`).
  - The director calls `Tournament.record` and changes scene itself (`race_director.gd:118-123`).
  - Each LapTimer runs its own clock from its own `_ready` (`lap_timer.gd:35, 81`).
  - Pause freezes the whole game: `get_tree().paused = true` (`pause_menu.gd:75`).
  - Restart and Backspace reload the scene (`pause_menu.gd:92`, `race_director.gd:77-79`); F2/F3 switch scenes (`drive_mode.gd:39-43`, `versus_mode.gd:40-42`).
- **Why it matters:**
  - Peers start the race at different moments and disagree on finish order, then each changes scene on its own.
  - The host opening the pause menu freezes the race for everyone.
  - A disconnected or AFK player keeps the race open forever.
- **Fix:** move race logic into a plain host-only `RaceState` node: integer race tick, countdown, laps, finish order and retirements, sent to peers as events. RaceDirector and the HUD only display that state. Online, pause is a local overlay; restart and scene changes become host actions; a finish timer starts after the first finisher.
- **Effort:** M

## MF-7. Input layer isn't network-shaped; P1/P2 hard-coded
- **Evidence:**
  - `PlayerInput.poll` reads the global `Input` singleton during the car's physics update (`player_input.gd:57-87`).
  - Button presses are one-tick bools (`vehicle_input.gd:13-20`) that are lost or doubled under packet loss.
  - The Vehicle writes back into its input object for the countdown lock and pit limiter (`vehicle.gd:234-238, 472-491`).
  - Player identity is the action prefix `""`/`p1_`/`p2_`, with gamepad devices 0/1 hard-wired (`player_input.gd:27, 37-40, 122-126`; `input_actions.gd:53-71`).
- **Why it matters:** there's no per-tick command to send, timestamp, buffer or replay, so this layer gets rewritten anyway once netcode starts.
- **Note:** reviewer B rated this nice-to-have. It's listed as must-fix because every netcode design needs it first.
- **Fix:** define `InputCommand {tick, steer, throttle, brake, handbrake, buttons}` and work out presses by comparing buttons with the previous tick. The Vehicle copies the command and never changes it. Add a `NetworkInput` subclass and a local "player slot" object (slot index, device, key map) instead of string prefixes.
- **Effort:** M

## MF-8. Vehicle mixes simulation and visuals; no state snapshot
- **Evidence:**
  - Physics forces and visual updates run in the same physics update: wheel visuals and dirt particles, brake lamps (`vehicle.gd:231-332, 324`; `wheel.gd:327-335`).
  - Audio reads live simulation fields directly (`car_audio.gd:77-122`).
  - CarDamage computes gameplay damage and deforms meshes in the same `_hit` (`car_damage.gd:177-200`). Damage is only set up when a visual model exists (`vehicle.gd:179`).
  - Simulation state is spread across Drivetrain, each Wheel, private Vehicle fields and CarPerks (`drivetrain.gd:10-18`, `wheel.gd:34-82`, `car_perks.gd:30-65`), with no get/set state API.
- **Why it matters:** a remote car on a client has no "proxy" mode. If it keeps simulating, it fights the incoming snapshots; if it's frozen, the wheels, lamps, audio and dirt all stop. There's also no state to snapshot, send or correct.
- **Fix:** add a `simulated` / `proxy` mode to Vehicle. In proxy mode it skips forces and drives the visuals from replicated state. Add `get_net_state()` / `apply_net_state()` covering transform, velocity, steer, per-wheel spin and suspension, rpm, gear, pedals, damage zones and perk energy. Damage outcomes are decided only on the host and sent as events.
- **Effort:** L

## MF-9. Gameplay randomness uses the unseeded global RNG
- **Evidence:**
  - Damage rolls for wheel off, toe, puncture and roll-over use global `randf()` (`car_damage.gd:61-67, 193`).
  - `race_setup.gd:62, 70` use global `shuffle()` for AI skills and cars, bypassing the local `rng`, which is itself `randomize()`d (`:56`).
  - `tournament.gd:46` calls `rng.randomize()`; `:48, 61` use global `shuffle()`.
- **Why it matters:** one peer's wheel comes off while another's only punctures, and AI line-ups differ between peers.
- **Fix:** one host-owned seed per race or tournament, passed in `RaceConfig`. Route all gameplay randomness through `RandomNumberGenerator` instances made from that seed (`Upgrades.offers` already takes an rng). Damage results come only from the host.
- **Effort:** S

## MF-10. Web host CPU budget at 120 Hz is unmeasured
- **Evidence:**
  - Physics runs at 120 Hz with up to 12 catch-up steps per frame (`project.godot:36-38`).
  - Each car per tick: 4 wheels × 4 substeps of GDScript tyre maths (`vehicle.gd:314-324`), and about 4–6 brute-force `Curve3D.get_closest_*` queries on a curve baked at 1 m (`lap_timer.gd:85`, `race_director.gd:286`, `ai_driver.gd:44, 80`, `vehicle.gd:465, 483`, `car_perks.gd:284`).
  - The AI traffic scan is O(n²) (`ai_driver.gd:219`).
  - The Web build is single-threaded and also renders the host's own view.
- **Why it matters:** an 8-car race on a Web host may fall below real time, and with up to 12 catch-up steps it can spiral, slowing the race for everyone.
- **Fix:**
  - Compute track progress once per car per tick and share it, using the existing `nearest_sample` grid (`circuit.gd:348`).
  - Profile `tests/fps_test.gd` with 8–9 cars in a Web build before designing netcode around 120 Hz. Then decide the network rate (e.g. 60 Hz network over a 120 Hz simulation) and lower the catch-up step cap.
- **Effort:** M

## MF-11. Tournament is single-machine static state
- **Evidence:**
  - All tournament state is `static var` (`tournament.gd:23-37`).
  - Humans are hard-coded as "YOU" / "PLAYER 1/2", with cars taken from the p1/p2 settings (`tournament.gd:53-57`).
  - Humans are assumed to be the first `players` entries (`race_setup.gd:50, 81`).
  - The AI shop runs locally (`tournament.gd:254-268`).
  - The shop assumes 1–2 local players with fixed gamepads, and moves on when the *local* players are ready (`tournament_shop.gd:249-250, 311-317`).
- **Why it matters:** online, each machine would have its own wallets, shop rolls, standings and transitions, so nothing is shared.
- **Fix:** keep the logic, but make it an instance owned by the host and keyed by `racer_id`. Buying and rerolling become requests the host checks. Standings, wallets and shop state are sent to every peer, and the shop moves on when *all* peers are ready (with a timeout). Damage and tyre-wear carry-over (`tournament.gd:194-211`) moves to the host too.
- **Effort:** M
