# 0002. Host-authoritative online play over WebRTC

*Proposed · 2026-11-26*

## Context
RRS is going online ([MF-1](../reviews/multiplayer_must_fix.md#mf-1-no-network-model-or-transport-chosen-web-hosting-needs-webrtc)). Targets: up to 8 cars, Windows and Web cross-play, a split-screen pair joining as two racers, either platform can host, and a dedicated server later. The first players are friends invited by the owner.

Facts that limit the choice:
- A browser can't accept incoming connections. A Web host needs WebRTC, which needs a signalling server, and a TURN relay for players whose networks block direct connections.
- Jolt isn't deterministic between Windows x64 and wasm, so lockstep is out.
- A Godot `RigidBody3D` can't be re-simulated on its own, so client prediction with rollback and replay is out.
- The Web build is single-threaded. Whether it can run 8 cars at 120 Hz is unmeasured ([MF-10](../reviews/multiplayer_must_fix.md#mf-10-web-host-cpu-budget-at-120-hz-is-unmeasured)).

## Options
**Who decides where the cars are:**
1. **The host simulates every car; clients send inputs and draw snapshots.** One true race, fair contact, and it moves straight to a dedicated server. A client's own car responds one round trip late (about 115 ms on a 40 ms link at 60 Hz).
2. **Each player simulates their own car; the host runs the race rules.** Steering feels instant. Car-to-car contact is seen differently on each screen, and cheating is easy.

**Transport:**
1. **WebRTC between peers** (`WebRTCMultiplayerPeer`, `webrtc-native` on Windows). Direct and cheap, with unreliable channels, so a lost snapshot doesn't hold up the next. Needs signalling, STUN and TURN.
2. **A WebSocket relay that forwards everything.** Simple, and works on every network. All traffic goes through the server, and TCP ordering makes every car stutter on one lost packet.

**Finding each other:** room codes for invited friends, or matchmaking with strangers.

## Decision
We will run races **host-authoritative over WebRTC, with room codes**:

| Area | Decision |
|---|---|
| Authority | The host simulates every car, including the AI, and owns race state, damage and the tournament. Clients send inputs and show interpolated snapshots. |
| Own car | Pure host authority for now: a client's own car is shown from snapshots like every other car. |
| Transport | WebRTC data channels. Godot RPCs (reliable) for events: lobby, ready, countdown, finishes, damage, shop. Our own packed messages (unreliable) for car snapshots and inputs. |
| Rates | Physics stays at 120 Hz. The host sends 60 snapshots/s, adjustable; clients send inputs at 60/s, each repeating the last few. A Web host may drop to 30/s. |
| Servers | Signalling (room codes) and TURN (coturn) run on the owner's VPS. Signalling sits behind the existing Caddy as `wss://` on a subdomain; coturn has its own UDP ports. Early tests run signalling on a local PC with no TURN. Signalling is a small Python program using `websockets`, so the VPS needs only Python, not Godot. |
| Hosting | Windows hosts allow 8 cars. A Web host gets a lower car limit, set by measurement (MF-10); car physics isn't changed to fit the browser. |
| Racers | A peer can own several racers. A split-screen pair takes 2 of the 8 places, can host on Windows, and can only join from Web. The host fills empty places with AI. |
| Settings | The host sets the race: track, laps, weather, time of day, damage, AI count and difficulty, tournament options. Each player picks their own car, livery and assist profile, shown in the lobby. |
| Disconnects | If the host leaves, the race ends for everyone, and a tournament in progress is lost. A client silent for 5 s is gone: AI takes over its car, and it can rejoin at the next race. |
| Versions | On join, a client sends its build version. The host refuses any mismatch. |
| Web build | Published on itch.io as the no-threads Web export. |
| Code layout | Network code lives in `scripts/net/`, `scenes/net/` and `tests/net/`. Game code never depends on it, except through a few named entry points; `make docs-check` enforces this. Single-player never opens a connection. See the [multiplayer hub](../multiplayer/README.md). |

## Consequences
- The design moves to a dedicated server with little change: the server takes the host's place.
- Every screen shows the same race, and contact between cars is decided once, on the host.
- **Clients feel input delay** on their own car (one round trip plus about 35 ms of interpolation). The host doesn't, so the host has an advantage. *Revisit:* a "run ahead and blend" mode, where the client also simulates its own car and is nudged towards the host's state without replaying it, would remove most of the delay. Decide after real online play.
- The host's CPU and upload limit the room: about 1.2 Mbit/s upload for 8 cars at 60 snapshots/s *(estimate, not yet measured)*.
- Losing the host loses the race and the tournament until a dedicated server exists.
- Matchmaking with strangers and a host "lock assists" option are left for later; both fit this design.
- Follow-up work:
  - **WebRTC prototype before any race networking:** Windows and Web hosts, room codes over local signalling, then TURN on the VPS, messages both ways. Add Windows, Web and Linux-server export presets (MF-1).
  - Separate racers from peers and from local P1/P2 (MF-5, MF-7).
  - One host-built race setup sent to all peers, replacing `GameSettings` reads in gameplay (MF-3); assist profile per racer (MF-4).
  - A proxy mode and `get_net_state()` / `apply_net_state()` for Vehicle (MF-8).
  - Host-owned seeds for gameplay randomness (MF-9).
  - Measure the Web host with 8 cars and set its car limit and snapshot rate (MF-10).
  - Host-owned tournament state (MF-11).
  - The Compatibility renderer for Web (MF-2) is a separate decision.
