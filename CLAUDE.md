# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

RRS – Random Racing Series: a semi-sim / semi-arcade racer in **Godot 4.7 (GDScript)** with Jolt physics. The design source of truth is `docs/design/RRS_Design_Concept.md`; code comments cite its sections as `§N`.

**Current direction: online multiplayer.** Target: 8 players online, 2-player split-screen that can join online races, Windows + Web cross-play, either platform can host, dedicated server later, tournaments online. Start at the multiplayer hub, `docs/multiplayer/README.md`, which lists every multiplayer doc. Before touching race, vehicle, input, settings or tournament code, read `docs/reviews/multiplayer_must_fix.md`. The network model (host-authoritative over WebRTC, room codes) is in `docs/decisions/0002-online-multiplayer-network-model.md`; read it before writing any networking code. New code must not make any must-fix item (MF-1 … MF-11) worse. In particular:
- No new gameplay reads of `GameSettings` (MF-3).
- No unseeded `randf()` / `shuffle()` in gameplay (MF-9).
- No new hard-coded P1/P2 or racer-by-name logic (MF-5).
- Network code lives only in `scripts/net/`, `scenes/net/` and `tests/net/`. Game code never names it, except through the entry points listed in `NET_ENTRY_POINTS` in `tools/docs_check.py`; `make docs-check` enforces this.

## Running and testing

No build step. Open `project.godot` in Godot 4.7.x, or run from the repo root. The original author works on Windows (`Godot_console.exe`); on Linux/macOS the binary is usually `godot`.

The `Makefile` wraps the common commands; `make help` lists them. Override the binaries with `make <target> GODOT=Godot_console.exe PY=python`.
- `make import` once after a fresh clone, then `make play`.
- `make test` runs the main smoke tests and, unlike calling Godot directly, exits non-zero if any fails. It hides the missing-MP3 errors.
- `make test-<name> ARGS="..."` runs one test, e.g. `make test-race_test ARGS="--laps=2 --track=rx"`. It finds tests in `tests/` and `tests/net/`.
- `make webrtc` once downloads and imports the desktop WebRTC add-on; then `make test-net` runs the network tests, which `make test` leaves out.
- `make export-windows`, `make export-web` and `make export-linux` build into `build/`; `make serve-web` serves the Web build at `http://localhost:8060`.
- `make docs-check` checks the `##` doc comment rules below, the links between docs, the repo paths quoted in them and the multiplayer code boundary. It prints `file:line` per problem. Run it before every PR. It needs [lychee](https://github.com/lycheeverse/lychee/releases) on the `PATH`.

The raw commands:

```sh
# Play
godot --path .

# Headless test scene (most smoke tests)
godot --headless --fixed-fps 120 --path . res://tests/race_test.tscn -- --laps=1 --scene=circuit_race --track=spa

# Headless test script
godot --headless --fixed-fps 120 --path . -s res://tests/damage_test.gd

# Screenshot / visual checks need a window (no --headless)
godot --path . -s res://tests/screenshot_hud.gd -- --track=spa
```

- **Every test file's header comment has its exact command and options.** Read it before running.
- **Tests always exit with code 0.** The result is in stdout:
  - Look for `<name> PASSED` / `<name> FAILED` and per-check `[ok]` / `[FAIL]` lines.
  - Probes (`*_probe.gd`) and `track_report.gd` print measurements to compare against earlier runs; they don't pass or fail.
  - Screenshot scripts write images for a person to look at.
- Main smoke tests: `race_test`, `lap_test`, `drive_test`, `car_stats_test`, `damage_test`, `tournament_test`, `tournament_cards_test`, `menu_test`.
- `tests/hitbox_check.gd` (windowed) checks that collision matches the drawn geometry for every track and car. Run it after touching collision, cars or track dressing.
- There is no code linter or CI; `make docs-check` is the only automated rule check.
- If Godot isn't installed, say so plainly in the PR and never claim tests passed.

Python tools (run from the repo root):
- `python tools/make_car_configs.py` regenerates every `assets/cars/<id>/<id>.tres`. **Edit car numbers in this script, not in the `.tres` files.**
- `tools/blender_*.py` build the car and track-kit models; they need Blender (the Blender MCP server in `.mcp.json`).
- `python tools/md_to_pdf.py docs/design/RRS_Design_Concept.md` rebuilds the design PDF. **Rebuild it whenever that doc changes.**

## Architecture

**Scene flow.** `scenes/ui/main_menu.tscn` (the main scene) picks a mode and switches to a scene in `scenes/modes/`:
- `free_roam` and `circuit_practice` use `scripts/modes/drive_mode.gd`.
- `circuit_race` (1 player) and `versus_race` (2-player split-screen, `versus_mode.gd`) are races.

Scene paths are constants in `GameSettings`. Tournament mode moves between races and `scenes/ui/tournament_shop.tscn`.

**Global state.** These are static classes (`class_name` + `static var`), not autoloads, and any script can reach them:
- `GameSettings`: menu choices, saved to `user://settings.cfg`.
- `Tournament`: the current tournament session.
- `CarRoster`: every car and its garage info.
- `TrackList`: every track layout.

The only autoload is `Music` (`scripts/core/music.gd`).

**Race assembly.** In a race scene:
1. `Circuit` (`scripts/tracks/circuit.gd`) builds the track from `TrackList` data in `_ready`. The road and curbs come from a spline; `TrackDressing` adds everything around it, using `assets/track_kit/track_kit.glb`; `Terrain` and `Atmosphere` add the ground, sky and weather. Each track's `seed` drives all of this, so the same track id always produces the same track. Circuit also answers track-progress queries (`progress_at`, `nearest_sample`) for lap timing, AI and the HUD.
2. `RaceSetup` spawns the AI cars, gives every car a `LapTimer`, lines the cars up on the grid (AI in front) and hands them to `RaceDirector`.
3. `RaceDirector` (a `Control`, so it also draws) runs the countdown, positions, finishes, DNFs and the race end, and records tournament results.

**Vehicle.**
- `Vehicle` (`RigidBody3D`, `scripts/vehicle/vehicle.gd`) is a custom raycast car. Each of its four `Wheel` nodes uses `TireModel`; `Drivetrain` and `HandlingAssists` (the Arcade / Sport / Sim profiles) sit alongside. Forces are applied in `_physics_process` with 4 substeps per 120 Hz tick.
- Every tunable number for a car lives in its `VehicleConfig` resource (SI units).
- `CarRoster.apply(vehicle, car_id, paint, livery)` turns the generic `scenes/vehicle/vehicle.tscn` into any of the 22 cars before it's ready. It loads `assets/cars/<id>/<id>.glb`, and the collision hull is built from the model's mesh.
- `CarDamage`, `CarAudio`, `CarPaint`, `CarLook` and `CarPerks` (tournament items) are attached per car.

**Input.** Every driver goes through `VehicleInput` (`scripts/input/vehicle_input.gd`), with these implementations:
- `PlayerInput` (keyboard/gamepad, using action prefixes `""` / `p1_` / `p2_`)
- `AIDriver`

A replay driver is mentioned in comments but doesn't exist yet.

The Vehicle calls `input.poll()` once per physics tick. Input actions are registered in code by `InputActions.ensure()`, not in Project Settings. New drivers, such as network input, must extend `VehicleInput`.

**Visual style.** `RetroLook` (`scripts/fx/retro_look.gd`) applies the PS1/PS2 screen effect and tells nodes in the `retro_aware` group to swap materials. Car and track materials use `assets/vfx/shaders/psx_lit.gdshader`.

**Physics layers:** world = 1, cars = 2. Set layers explicitly on every new body.

## Conventions

- **GDScript style:** static types everywhere (`var x: float`, `-> void`), `class_name` for reusable classes, `##` doc comments. See the documentation rules below for what needs one.
- **Commit `.uid` files** with their scripts and scenes; they come in pairs.
- **Assets** come from Blender as glTF/`.glb`: metres, origin at ground centre between the axles, and wheel nodes named `wheel_FL/FR/RL/RR` (§15). Never commit `*.blend1`.
- **Soundtrack MP3s are licensed and git-ignored** (`soundtrack/*.mp3`). Only their `.import` files are in the repo; never add the audio.
- **British spelling** in comments and docs ("tyre", "colour"). Keep existing API names (`TireModel`, `paint_color`, and Godot's own `Color`). Never rename only to change spelling.

## Documentation rules

**Read `docs/README.md` before you create or move any doc.** It has the full layout, naming rules and templates. In short:

- **Docs live under `docs/` by purpose:**
  - `design/`: what the game is.
  - `architecture/`: how the code works.
  - `decisions/`: numbered ADRs, `NNNN-kebab-title.md`.
  - `research/`: findings and comparisons.
  - `reviews/`: audits with must-fix lists.
  - New files are lower_snake_case `.md`, except ADRs. Add every new doc to the index in `docs/README.md`.
- **A change is done only when the docs match the code, in the same PR.** Behaviour or tuning changes update the matching design or architecture doc. A new system, a reversal of an earlier choice, or any multiplayer or netcode choice needs an ADR. A PR that fixes a review item marks it fixed in that review doc (`✅ Fixed in #<PR>`).
- **Code comments:**
  - A `##` doc comment is required on every `class_name` script, signal, `@export` and public function.
  - Say what it does, its units (m/s, N·m, lap fraction 0–1) and its range or meaning (`-1 left … +1 right`), and cite `§N` where the design doc covers it.
  - Private `_helpers` only need a comment when the *why* isn't obvious.
  - Comments describe the code as it is now, not its history.
- **Plain English:** short sentences, no filler, and numbers with units.

## Git workflow: issue → branch → PR

**Always start from a GitHub issue.** Every change, however small, has an issue. If none exists, create one before writing code (`gh issue create`), and say what's wrong or wanted and how to tell it's done. Review findings (MF-x / NH-x) get one issue each, with the review ID in the title and a link to the review doc.

Classic git conventions apply. For issue **#42** that fixes the lap timer:

| What | Format | Example |
|------|--------|---------|
| Branch | `<type>/<issue>-<kebab-summary>` | `fix/42-lap-timer-reset` |
| Commit | `<type>: <summary> #<issue>` | `fix: lap timer resets on pit exit #42` |
| PR title | `<kebab-summary>-<type>-(<issue>)` | `lap-timer-reset-fix-(42)` |

- **Types (Conventional Commits):**
  - `feat`: new behaviour
  - `fix`: bug fix
  - `refactor`: no behaviour change
  - `docs`
  - `test`
  - `perf`
  - `chore`: tooling, config, assets housekeeping
- **The issue number is required** on the branch, every commit and the PR title. It's what links them together.
- **Commit messages:**
  - The summary is lower case and imperative ("fix", not "fixed"), with no full stop, and 72 characters or fewer including ` #42`.
  - Optionally a blank line, then a bullet body: what changed and why, in player-visible terms where possible, mentioning review IDs (`MF-3`) where relevant.
  - Keep commits small and focused; one issue per branch.
- **Never commit or push to `main`.** Everything merges through a PR.
- **PR description:**
  - Starts with `Closes #<issue>`, so the issue closes on merge.
  - What changed and why.
  - The tests you ran, with their PASSED/FAILED lines pasted, or "not run: no Godot available".
  - Screenshots for visual changes.
  - The docs you updated.
- **After merging,** mark fixed review findings `✅ Fixed in #<PR>` (see `docs/README.md`).
