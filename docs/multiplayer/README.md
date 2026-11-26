# Online multiplayer

*Current · updated 2026-11-26*

Start here for anything about online play. This page lists every multiplayer doc, says where the network code lives, and sets the one rule that keeps it apart from the rest of the game.

## Where things are

| Doc | What it says |
|-----|--------------|
| [ADR 0002](../decisions/0002-online-multiplayer-network-model.md) | **The network model:** the host simulates every car, over WebRTC, with room codes. Read it before writing any networking code. |
| [Must-fix review](../reviews/multiplayer_must_fix.md) | MF-1 … MF-11: what in the current code blocks online play, and the fix for each. |
| [Nice-to-have review](../reviews/multiplayer_nice_to_have.md) | NH- findings: improvements that can wait. |
| [WebRTC prototype plan](plans/2026-11-26-webrtc-prototype.md) | Step-by-step plan for issue #11 (MF-1): room codes, a WebRTC connection between desktop and browser, TURN on the VPS. |

Decision records stay in `decisions/` and reviews stay in `reviews/`, so their numbering stays in one place. This folder holds the rest: how the network code works, the server protocol, deploy steps and plans.

## Where the code is

| Path | What it holds |
|------|---------------|
| `scripts/net/`, `scenes/net/` | All network code and scenes. |
| `tests/net/` | Network tests. `make test-net` runs them; `make test` doesn't, so it stays offline. |
| `addons/webrtc_native/` | The desktop WebRTC add-on. Downloaded by `make webrtc`, not in git. |
| `export_presets.cfg` | Windows, Web (no-threads) and Linux exports: `make export-windows`, `make export-web`, `make export-linux`. |

## The separation rule

**Game code never depends on network code; network code may use the game.** A single-player race never creates a connection, so it works exactly as before.

- Scripts and scenes outside the `net/` folders must not name a class from `scripts/net/` or a `res://scripts/net/` / `res://scenes/net/` path.
- When the game does need a hook into multiplayer, it goes through a small, named entry point. Planned ones are network input as another `VehicleInput` (MF-5), save/restore state on `Vehicle` (MF-8), and one race setup sent by the host (MF-3). Each is added to `NET_ENTRY_POINTS` in `tools/docs_check.py`, with its reason.
- `make docs-check` fails on any other use (its `net` check).

## Writing multiplayer docs

- A doc only about online play goes in this folder, and gets a row in the table above in the same PR.
- A multiplayer *choice* still needs an ADR in `decisions/`, linked from here.
- Plans go in `plans/` here, named `YYYY-MM-DD-<topic>.md`. Repo paths quoted in plans aren't checked, since they name files still to be written.
- The general rules in [docs/README.md](../README.md) apply: header line, plain English, British spelling.
