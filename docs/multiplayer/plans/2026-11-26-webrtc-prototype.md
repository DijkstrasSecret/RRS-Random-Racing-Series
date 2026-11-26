# WebRTC Connectivity Prototype Implementation Plan

*Snapshot · 2026-11-26 · issue #11*

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove that a desktop host and a browser host can each be joined by the other platform with a room code, over WebRTC, with messages both ways. No cars and no race code.

**Architecture:** A small Python signalling server hands out room codes and relays WebRTC offers, answers and ICE candidates between a host and its clients (star topology, host = peer 1). In Godot, `SignallingClient` speaks that protocol over a `WebSocketPeer`, `NetSession` builds a `WebRTCMultiplayerPeer` on its own `SceneMultiplayer` branch and checks build versions, and `NetProbe` measures round-trip time and loss with an unreliable 60/s stream. A "Net Lab" scene puts it on screen. TURN (coturn) and the signalling server then move to the owner's VPS behind Caddy.

**Tech Stack:** Godot 4.7.2 (GDScript), `webrtc-native` 1.2.2 GDExtension (desktop), the browser's built-in WebRTC (Web), Python 3.11+ with `websockets` 17.4, coturn, Caddy.

**Spec:** [ADR 0002](../../decisions/0002-online-multiplayer-network-model.md), and review finding [MF-1](../../reviews/multiplayer_must_fix.md#mf-1-no-network-model-or-transport-chosen-web-hosting-needs-webrtc).

## Global Constraints

- Follow `CLAUDE.md`: static types, `##` doc comments on every `class_name`, signal, `@export` and public function (`make docs-check` must pass), British spelling in comments and docs, `.uid` files committed with their scripts and scenes.
- Branch `feat/11-webrtc-prototype`; every commit is `<type>: <summary> #11`. No attribution lines.
- Star topology: the host is always peer id `1` and talks to every client; clients never talk to each other (ADR 0002 "Authority").
- At most 8 connections per room, host included: `NetProtocol.MAX_PEERS = 8`.
- A peer silent for 5 s is gone: `NetProtocol.PEER_TIMEOUT = 5.0` (seconds, wall clock).
- Unreliable probe stream at 60 messages/s by default (ADR 0002 "Rates"), adjustable.
- Build version check on join: `NetProtocol.build_version()` must match exactly, otherwise the host refuses (ADR 0002 "Versions").
- Network timing uses wall-clock time (`Time.get_ticks_msec()`), never frame delta. Tests run with `--fixed-fps 120`, which makes frame time run faster than real time.
- Gameplay randomness rules (MF-9) don't apply to room codes; the server makes them with Python's `secrets`.
- Don't write the owner's domain into any repo file. Use `net.example.com` in examples.
- Web build: no-threads export. `rendering/renderer/rendering_method.web` is already `gl_compatibility`; don't change the desktop renderer here (MF-2 is separate).
- Multiplayer stays separate (see [the multiplayer hub](../README.md)): network code lives in `scripts/net/`, `scenes/net/` and `tests/net/`, and game code never names it. `make docs-check` (its `net` check) fails otherwise; the few allowed entry points are listed in `NET_ENTRY_POINTS` in `tools/docs_check.py`, each with a reason. This prototype needs none.
- Net tests are listed in `NET_TESTS` in the `Makefile` and run with `make test-net`; `make test` stays offline.
- Desktop WebRTC needs the add-on imported once: `make webrtc` (fetch and import) before any net test.

## Review Focus

1. **A browser page on `https://` given a `ws://` signalling URL.** Browsers block it silently. Expect a clear `failed("insecure_url")`. Test: `url_problem()` cases in Task 4.
2. **Codes typed in lower case or with spaces** (`" abcd "`). Expect the join to work. Test: `NetProtocol.normalise_code()` in Task 3 and a lower-case join in Task 3's client test.
3. **Signalling server unreachable** (wrong URL, server down). Expect `failed("signalling_unreachable")` within 6 s, not a hang. Test in Task 3.
4. **Host leaves while a client is still connecting.** Expect the client to get `session_closed("host_left")` and not wait forever. Test in Task 3 (signalling `closed` before WebRTC is open).
5. **A ninth connection to a full room.** Expect `failed("room_full")`. Tests in Task 2 (server) and Task 3 (client).

---

## File Structure

| Path | Responsibility |
|---|---|
| `tools/fetch_webrtc.py` | Downloads `webrtc-native` 1.2.2, checks its SHA-256 and extracts the desktop x86_64 libraries into `addons/webrtc_native/`. |
| `server/.gdignore` | Empty; tells Godot not to import the Python server. |
| `server/signalling/signalling.py` | Room codes, peer ids, relaying offers/answers/candidates, TURN credentials. |
| `server/signalling/test_signalling.py` | Unit tests for the server (stdlib `unittest`). |
| `server/signalling/requirements.txt` | `websockets==17.4`. |
| `server/deploy/` | `rrs-signalling.service`, `turnserver.conf.example`, `Caddyfile.example` for the VPS. |
| `scripts/net/net_protocol.gd` | `NetProtocol`: shared constants, code rules, build version, packet kinds. |
| `scripts/net/signalling_client.gd` | `SignallingClient`: the signalling protocol over `WebSocketPeer`. |
| `scripts/net/net_session.gd` | `NetSession`: WebRTC multiplayer peer, version check, timeouts, events, packets. |
| `scripts/net/net_probe.gd` | `NetProbe`: RTT, loss and rate over the unreliable stream. |
| `scripts/net/net_lab.gd`, `scenes/net/net_lab.tscn` | The on-screen test bench. |
| `tests/net/webrtc_available_test.gd` | The add-on loads and an in-process data channel opens. |
| `tests/net/signalling_client_test.gd`, `tests/net/net_loopback_test.gd` | Headless tests against a local signalling server. |
| `export_presets.cfg` | Windows, Web (no-threads, feature `net_lab`) and Linux presets; committed. |
| `docs/multiplayer/networking.md` | How the pieces fit, peer ids, packet kinds, running locally, known limits. |
| `docs/multiplayer/protocol.md` | The signalling wire protocol (Task 2's table). |
| `docs/multiplayer/deploy.md` | The owner's VPS steps: Python service, coturn, firewall, Caddy. |

---

### Task 1: WebRTC add-on, build version and export presets

**Files:**
- Create: `tools/fetch_webrtc.py`, `tests/net/webrtc_available_test.gd`, `export_presets.cfg`
- Modify: `.gitignore` (drop `export_presets.cfg`; add `addons/webrtc_native/` and `build/`), `project.godot` (`application/config/version="0.1.0"`), `Makefile` (`webrtc`, `export-web`, `export-windows`, `export-linux`, `serve-web`)

**Interfaces:**
- Produces: `make webrtc` leaves `addons/webrtc_native/webrtc_native.gdextension` plus `lib/libwebrtc_native.{linux,windows}.template_{debug,release}.x86_64.{so,dll}` and the `LICENSE.*` files, then runs `godot --headless --path . --import`.
- Produces: export preset names `Windows Desktop`, `Web`, `Linux` (used by the Makefile).

- [ ] **Step 1: Write `tests/net/webrtc_available_test.gd`** (`extends SceneTree`, header comment with its command). Checks:
  - `[ok] extension loaded`: `GDExtensionManager.is_extension_loaded("res://addons/webrtc_native/webrtc_native.gdextension")`.
  - `[ok] data channel opens`: two `WebRTCPeerConnection`s in one process, `initialize({"iceServers": []})`, each other's descriptions and candidates passed directly, a negotiated channel (`id 1`, unordered, `maxRetransmits 0`). Peer B receives `"ping"` within 5 s of wall-clock time.
  - Prints `webrtc_available_test PASSED` / `FAILED`.
- [ ] **Step 2: Run it before fetching.** `make test-webrtc_available_test`. Expected: `✗ webrtc_available_test failed`, with `[FAIL] extension loaded`.
- [ ] **Step 3: Write `tools/fetch_webrtc.py`** (stdlib only; module docstring with usage).
  - URL `https://github.com/godotengine/webrtc-native/releases/download/1.2.2-stable/godot-extension-webrtc_native.zip`.
  - SHA-256 `98e9446921740d995bd9ca1be48798dc3c2ceed51e044a25ce18b3cff11f56e5`; exit non-zero on a mismatch.
  - Extract only the `.gdextension`, the `LICENSE.*` files and the four x86_64 Linux/Windows libraries.
  - Skip the download when the files are already there.
- [ ] **Step 4: Update the ignore file, version and Makefile.** In `.gitignore`, ignore `addons/webrtc_native/` and `build/`, and stop ignoring `export_presets.cfg`. In `project.godot`, set `config/version="0.1.0"`. Add `webrtc:` (fetch, then `$(GODOT) --headless --path . --import`).
- [ ] **Step 5: Run `make webrtc && make test-webrtc_available_test`.** Expected: `✓ webrtc_available_test`.
- [ ] **Step 6: Create `export_presets.cfg`** in the Godot editor (Project → Export) or by hand. It has three presets:
  - `Windows Desktop`: x86_64, output `build/windows/RRS.exe`.
  - `Web`: Variant *No Threads*, custom feature `net_lab`, output `build/web/index.html`.
  - `Linux`: x86_64, output `build/linux/RRS.x86_64`.

  No secrets in the file (no code-signing passwords). Add Makefile targets `export-web`, `export-windows` and `export-linux` (`$(GODOT) --headless --path . --export-release "<preset>" <output>`, after `mkdir -p`), and `serve-web` (`$(PY) -m http.server 8060 -d build/web`).
- [ ] **Step 7: Check the exports.** `make export-linux export-windows export-web`. Expected: all three output files exist. `build/windows/` contains `libwebrtc_native.windows.template_release.x86_64.dll`, and `build/web/index.html` exists. Then run `make test` (all 8 smoke tests still pass) and `make docs-check`.
- [ ] **Step 8: Commit.** `chore: add webrtc-native fetch, build version and export presets #11`

### Task 2: Signalling server

**Files:**
- Create: `server/.gdignore` (empty), `server/signalling/signalling.py`, `server/signalling/test_signalling.py`, `server/signalling/requirements.txt`, `docs/multiplayer/protocol.md` (the protocol table and rules below, `*Current*` header; add it to the hub's table)
- Modify: `Makefile` (`signalling`, `test-signalling`), `docs/decisions/0002-online-multiplayer-network-model.md` ("Servers" row: add "Signalling is a small Python program using `websockets`". The ADR is still `Proposed`, so it can be edited.)

**Interfaces:**
- Produces: the wire protocol below. JSON text frames, at most 64 KB each; anything else gets `error`/`bad_message`, and the connection stays open.

| Direction | Message |
|---|---|
| client → server | `{"type":"host"}` · `{"type":"join","code":"ABCD"}` · `{"type":"offer"/"answer","to":int,"sdp":str}` · `{"type":"candidate","to":int,"mid":str,"index":int,"sdp":str}` |
| server → host | `{"type":"hosted","code":str,"id":1,"ice_servers":[…]}` · `{"type":"peer_joined","id":int}` · `{"type":"peer_left","id":int}` |
| server → client | `{"type":"joined","code":str,"id":int,"ice_servers":[…]}` · `{"type":"closed","reason":"host_left"}` |
| server → either | relayed `offer`/`answer`/`candidate` with `"from":int` instead of `"to"` · `{"type":"error","reason":"no_such_room"/"room_full"/"bad_message"/"already_in_room"}` |

- Ids: host `1`; clients `2, 3, …` in join order, never reused in a room. A client may only send to `1`, and the host only to its own clients; any other `to` is `bad_message`.
- Codes: 4 characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, unique among open rooms. The server upper-cases and strips a code before looking it up.
- Room life: the room closes when the host's socket closes; every client gets `closed`/`host_left`. A client's socket closing sends `peer_left` to the host.
- `ice_servers`: one entry per `--stun URL` (repeatable). With `--turn-url URL` (repeatable) and `--turn-secret S`, it adds `{"urls":[…],"username":u,"credential":c}`, where `u = f"{now + 6 h}:rrs"` and `c = base64(hmac_sha1(S, u))` (coturn `use-auth-secret`).
- CLI: `python server/signalling/signalling.py --host 127.0.0.1 --port 9081 [--stun …] [--turn-url …] [--turn-secret …]`.

- [ ] **Step 1: Write `test_signalling.py`.** It starts the server on a free port in a background asyncio task, and each test opens `websockets` clients. Tests:
  - `test_host_gets_code_and_id_1`: code matches `^[A-HJ-NP-Z2-9]{4}$`; id == 1.
  - `test_join_relays_offer_answer_candidate`: the client gets id 2; the host gets `peer_joined` 2; host→2 `offer` arrives with `from` 1; client `answer` and `candidate` arrive at the host with `from` 2 and all fields intact.
  - `test_join_lower_case_code_with_spaces`: joining `" abcd "`-style (the real code lower-cased and padded) works.
  - `test_unknown_code`: `error`/`no_such_room`.
  - `test_room_full_at_8`: 7 clients join; the 8th client (9th connection) gets `room_full`.
  - `test_client_cannot_message_other_client`: client 2 → `to` 3 gets `bad_message`, and 3 receives nothing.
  - `test_host_leaving_closes_room`: clients get `closed`/`host_left`; a later join of that code gets `no_such_room`.
  - `test_client_leaving_tells_host`: the host gets `peer_left`.
  - `test_bad_json_keeps_connection`: sending `"not json"` gets `bad_message`, then `host` still works.
  - `test_turn_credentials`: with `--turn-secret s3cret --turn-url turn:x:3478`, `ice_servers[-1].credential == base64(hmac_sha1("s3cret", username))` and the username's expiry is 6 h ± 5 s from now.
- [ ] **Step 2: Run them.** `make test-signalling` (`$(PY) -m unittest discover -s server/signalling -v`). Expected: errors, because `signalling` doesn't exist yet.
- [ ] **Step 3: Implement `signalling.py`** with `websockets.asyncio.server.serve`. One `Room` dataclass (`code`, `host`, `clients: dict[int, conn]`, `next_id`). A module docstring documents the protocol table above.
- [ ] **Step 4: Run `make test-signalling`.** Expected: all 10 pass. Add the `signalling:` target (runs it on `127.0.0.1:9081`). Note in `requirements.txt` that it needs Python ≥ 3.11.
- [ ] **Step 5: Update the ADR "Servers" row**, then run `make docs-check`.
- [ ] **Step 6: Commit.** `feat: add room-code signalling server #11`

### Task 3: NetProtocol and SignallingClient

**Files:**
- Create: `scripts/net/net_protocol.gd`, `scripts/net/signalling_client.gd`, `tests/net/signalling_client_test.gd`
- Delete: `scripts/net/.gitkeep` (the folder now has real files)
- Modify: `Makefile` (add `signalling_client_test net_loopback_test` to `NET_TESTS`; `test-net` starts `signalling.py --port 9081` in the background, runs the net tests, then always stops the server, returning the tests' status)

**Interfaces:**
- Produces `class_name NetProtocol extends RefCounted`:
  - `const PROTOCOL_VERSION := 1`, `const MAX_PEERS := 8`, `const PEER_TIMEOUT := 5.0`, `const CODE_LENGTH := 4`, `const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"`, `const DEFAULT_SIGNALLING_URL := "ws://127.0.0.1:9081"`.
  - Packet kinds (first byte of every `send_bytes` packet): `const PACKET_HEARTBEAT := 1`, `const PACKET_PROBE := 2`, `const PACKET_PROBE_ECHO := 3`.
  - `static func build_version() -> String`, returning `"<application/config/version>+p<PROTOCOL_VERSION>"`, e.g. `"0.1.0+p1"`.
  - `static func normalise_code(code: String) -> String` (strip and upper-case).
  - `static func is_valid_code(code: String) -> bool` (after normalising).
- Produces `class_name SignallingClient extends RefCounted`, driven by `poll()`:
  - Signals: `hosted(code: String, my_id: int, ice_servers: Array)`, `joined(code: String, my_id: int, ice_servers: Array)`, `peer_joined(id: int)`, `peer_left(id: int)`, `offer_received(from: int, sdp: String)`, `answer_received(from: int, sdp: String)`, `candidate_received(from: int, mid: String, index: int, sdp: String)`, `closed(reason: String)`, `error_received(reason: String)`, `disconnected()`.
  - `func connect_to_url(url: String) -> Error`, `func poll() -> void`, `func host() -> void`, `func join(code: String) -> void` (both queue until the socket is open), `func send_offer(to: int, sdp: String) -> void`, `func send_answer(to: int, sdp: String) -> void`, `func send_candidate(to: int, mid: String, index: int, sdp: String) -> void`, `func close() -> void`, `func is_open() -> bool`.
  - Emits `disconnected` when the socket closes, or fails to open within 5 s of wall-clock time.

- [ ] **Step 1: Write `tests/net/signalling_client_test.gd`** (needs the server on 9081; its header says to run it via `make test-net`). Two `SignallingClient`s:
  - `[ok] host gets a valid code`
  - `[ok] lower-case join works`: join with `" " + code.to_lower() + " "`.
  - `[ok] offer reaches the client from 1`
  - `[ok] unknown code -> no_such_room`
  - `[ok] host close -> client gets closed host_left`
  - `[ok] unreachable server -> disconnected within 6 s`: `ws://127.0.0.1:1`.
  - `[ok] 9th connection -> room_full`
  - Plus `NetProtocol` checks: `normalise_code(" ab2c ") == "AB2C"`; `is_valid_code("AB0C") == false` (0 isn't in the alphabet); `build_version() == "0.1.0+p1"`.
- [ ] **Step 2: Run `make test-net`.** Expected: FAILED, because the classes don't exist yet.
- [ ] **Step 3: Implement `net_protocol.gd` and `signalling_client.gd`.** The client wraps `WebSocketPeer`, sends JSON with `send_text`, and parses each received packet with `JSON.parse_string`. It ignores unknown `type`s.
- [ ] **Step 4: Run `make test-net`.** Expected: `✓ signalling_client_test`; `net_loopback_test` is still missing, so the target fails on that one only.
- [ ] **Step 5: Run `make docs-check`, then commit.** `feat: add signalling client and net protocol constants #11`

### Task 4: NetSession

**Files:**
- Create: `scripts/net/net_session.gd`, `tests/net/net_loopback_test.gd`

**Interfaces:**
- Consumes: `SignallingClient` and `NetProtocol` (Task 3).
- Produces `class_name NetSession extends Node`:
  - `@export var signalling_url: String = NetProtocol.DEFAULT_SIGNALLING_URL`, `@export var relay_only: bool = false`. Also `var build_version: String = NetProtocol.build_version()`, which tests override to force a mismatch.
  - Signals: `hosted(code: String)`, `connected(my_id: int)` (client: data channel open *and* version accepted), `peer_connected(id: int)` (host: client passed the version check), `peer_disconnected(id: int)`, `failed(reason: String)`, `session_closed(reason: String)`, `message_received(from: int, text: String)`, `packet_received(from: int, kind: int, data: PackedByteArray)`.
  - `func host_room() -> void`, `func join_room(code: String) -> void`, `func leave() -> void`, `func is_host() -> bool`, `func peers() -> PackedInt32Array` (accepted peers only), `func send_message(text: String) -> void` (reliable; host → all clients, client → host), `func send_packet(to: int, kind: int, data: PackedByteArray, reliable: bool) -> void`.
  - `static func url_problem(url: String, page_is_https: bool) -> String`: `""` if fine; `"insecure_url"` when `page_is_https` and the url starts with `ws://`; `"bad_url"` if it starts with neither `ws://` nor `wss://`.
  - Failure reasons: `"webrtc_unavailable"` (desktop without the add-on: `GDExtensionManager.is_extension_loaded(...)` is false), `"signalling_unreachable"`, `"no_such_room"`, `"room_full"`, `"version_mismatch"`, `"insecure_url"`, `"bad_url"`. Close reasons: `"host_left"`, `"host_timeout"`, `"left"`.

Behaviour the tests pin:
- In `_enter_tree`, the session calls `get_tree().set_multiplayer(SceneMultiplayer.new(), get_path())`, so two sessions can share one SceneTree.
- The host uses `WebRTCMultiplayerPeer.create_server()`; a client uses `create_client(my_id)`. The host makes the offer when `peer_joined` arrives.
- With `relay_only`, local candidates whose SDP doesn't contain `" typ relay "` are not sent.
- Version check: on connect, a client calls `@rpc("any_peer", "reliable") _hello(version)`. The host answers `_welcome()` or `_refused(host_version)`, and on refusal disconnects that peer 0.5 s later. A refused client emits `failed("version_mismatch")`.
- Both sides send `PACKET_HEARTBEAT` 10 times a second. A host drops a client silent for `PEER_TIMEOUT` (emits `peer_disconnected`). A client silent from its host for `PEER_TIMEOUT` emits `session_closed("host_timeout")`.
- A signalling `closed` before or after the WebRTC connection is up emits `session_closed("host_left")` once.

- [ ] **Step 1: Write `tests/net/net_loopback_test.gd`** (via `make test-net`). Sessions are added as children at different paths under one root:
  - `[ok] url_problem`: `("ws://x", true) == "insecure_url"`, `("wss://x", true) == ""`, `("ws://x", false) == ""`, `("http://x", false) == "bad_url"`.
  - `[ok] host gets code`
  - `[ok] client connected as id >= 2` within 10 s
  - `[ok] host sees peer_connected`
  - `[ok] message both ways`: `"hello host"` and `"hello client"` arrive with the right `from`.
  - `[ok] unreliable packets arrive`: 60 `PACKET_PROBE` packets host→client in 1 s; at least 55 received (loopback).
  - `[ok] version mismatch refused`: a third session with `build_version = "0.0.0+p0"` gets `failed("version_mismatch")`, and the host's `peers()` doesn't include it.
  - `[ok] silent client dropped`: stop the client's `_process` (`set_process(false)`); the host emits `peer_disconnected` between 5 and 7 s later.
  - `[ok] host leave closes client`: a fresh client, then `host.leave()`; the client emits `session_closed("host_left")` within 3 s.
  - `[ok] unreachable signalling`: a session with `ws://127.0.0.1:1` emits `failed("signalling_unreachable")` within 6 s.
- [ ] **Step 2: Run `make test-net`.** Expected: FAILED (no `NetSession`).
- [ ] **Step 3: Implement `net_session.gd`.**
- [ ] **Step 4: Run `make test-net`.** Expected: `✓ signalling_client_test` and `✓ net_loopback_test`. Then `make test` and `make docs-check`.
- [ ] **Step 5: Commit.** `feat: add webrtc net session with version check and timeouts #11`

### Task 5: NetProbe and the Net Lab scene

**Files:**
- Create: `scripts/net/net_probe.gd`, `scripts/net/net_lab.gd`, `scenes/net/net_lab.tscn`
- Delete: `scenes/net/.gitkeep`
- Modify: `project.godot` (`application/run/main_scene.net_lab="res://scenes/net/net_lab.tscn"`), `Makefile` (`net-lab:` runs `$(GODOT) --path . res://scenes/net/net_lab.tscn`), `tests/net/net_loopback_test.gd` (probe checks)

**Interfaces:**
- Consumes: `NetSession.send_packet`, `packet_received`, `peers()`, and `NetProtocol.PACKET_PROBE` / `PACKET_PROBE_ECHO` (Task 4).
- Produces `class_name NetProbe extends Node`:
  - `@export var send_rate_hz: float = 60.0`, `func setup(session: NetSession) -> void`, `func stats(peer: int) -> Dictionary` returning `{"rtt_ms": float, "loss_pct": float, "rate_hz": float}` over the last 2 s.
  - Packet payload: `u32 seq` + `f64 sent_msec`. The receiver echoes it unchanged as `PACKET_PROBE_ECHO`. Loss counts the round trip: echoes received out of probes sent.

- [ ] **Step 1: Add the probe checks to `net_loopback_test.gd`:**
  - `[ok] probe rtt measured`: after 3 s connected, `stats(client).rtt_ms` is greater than 0 and under 50 (loopback).
  - `[ok] probe rate ~60`: `rate_hz` is between 50 and 70.
  - `[ok] probe loss low`: `loss_pct` is under 10.
- [ ] **Step 2: Run `make test-net`.** Expected: FAILED.
- [ ] **Step 3: Implement `net_probe.gd`.**
- [ ] **Step 4: Build the Net Lab.** It builds its UI in code with `MenuStyle`, like the other menus:
  - A signalling URL field. It starts as `NetProtocol.DEFAULT_SIGNALLING_URL`, and the last URL used is saved to `user://net_lab.cfg`, so each tester types it once. The Web page is hosted on itch.io, not on the VPS, so its own address is no use as a default.
    A real release will need the VPS address built into the game. It is left out here because the domain must not go into the repo (Global Constraints).
  - **HOST**, a code field with **JOIN**, a **relay only** toggle, a message field with **SEND**, and **LEAVE**.
  - A status line showing the code, my id and the last failure or close reason.
  - One line per peer: `id · rtt ms · loss % · rate Hz`, refreshed 4 times a second.
  - The room code in large text, so it can be read out to a friend.
- [ ] **Step 5: Run the automated checks.** `make test-net`, `make test` and `make docs-check` all pass.
- [ ] **Step 6: Run the manual local check and record the results in the PR.**
  1. `make signalling`, then `make net-lab` twice: host in one window, join in the other, send a message both ways. RTT is shown.
  2. `make export-web serve-web`. Open `http://localhost:8060` in a browser and confirm the Net Lab opens (the `net_lab` feature selects the main scene). Host there and join from `make net-lab`; then host on the desktop and join from the browser.
  3. Write down RTT, loss and rate for both directions.
- [ ] **Step 7: Commit.** `feat: add net probe and net lab test scene #11`

### Task 6: Servers on the VPS, TURN relay check and docs

The owner runs the VPS steps; the implementer writes the files and the instructions. Don't log into the VPS unless the owner asks.

**Files:**
- Create: `server/deploy/rrs-signalling.service`, `server/deploy/turnserver.conf.example`, `server/deploy/Caddyfile.example`, `docs/multiplayer/networking.md`, `docs/multiplayer/deploy.md`
- Modify: `docs/multiplayer/README.md` (rows for the new docs; status), `docs/architecture/directory_tree.md` (`server/`, `scenes/net/`, `scripts/net/`), `CLAUDE.md` (Running and testing: `make webrtc`, `make signalling`, `make test-net`, `make net-lab`, the exports), `docs/reviews/multiplayer_must_fix.md` (MF-1 `✅ Fixed in #<PR>`)

- [ ] **Step 1: Write the deploy files:**
  - `Caddyfile.example`: `net.example.com { handle /signal* { reverse_proxy 127.0.0.1:9081 } }`.
  - `rrs-signalling.service`: runs `signalling.py --host 127.0.0.1 --port 9081 --stun stun:net.example.com:3478 --turn-url turn:net.example.com:3478?transport=udp --turn-url turn:net.example.com:3478?transport=tcp --turn-secret ${TURN_SECRET}`, with the secret from an `EnvironmentFile` that isn't in git.
  - `turnserver.conf.example`: `use-auth-secret`, `static-auth-secret=<same secret>`, `realm=net.example.com`, `listening-port=3478`, `min-port=49160`, `max-port=49200`, `no-cli`, `fingerprint`, and `denied-peer-ip` for private ranges, so the relay can't reach the VPS's own network.
- [ ] **Step 2: Write the two docs,** each with a `*Current · updated <date>*` header.
  - `docs/multiplayer/networking.md`: how the parts fit (a small ASCII diagram: host ⇄ signalling ⇄ client, then host ⇄ client over WebRTC, TURN as fallback); `SignallingClient`, `NetSession`, `NetProbe` and who owns what; peer ids and packet kinds; running it locally; known limits from ADR 0002. Link `protocol.md` rather than repeat it.
  - `docs/multiplayer/deploy.md`: the owner's steps, in order. Install Python 3.11+, the venv and `requirements.txt`; install coturn; the firewall opens 3478 udp/tcp and 49160–49200 udp; generate the secret into the env file; enable the service; add the Caddy block; reload Caddy. Then how to check each part works.
- [ ] **Step 3: Owner's VPS check, recorded in the PR.** Net Lab against `wss://net.<domain>/signal`. With **relay only** on, a browser on another network joins a desktop host, and rtt, loss and rate are written down. Repeat with relay only off. If the owner can't test from another network, write that down instead of claiming it worked.
  Optional: the original author runs the `Windows Desktop` export and repeats the join both ways with a Web host. If nobody tries it, write "not tried on Windows".
- [ ] **Step 4: Update the docs.** Make the hub, `directory_tree.md` and `CLAUDE.md` changes, and mark MF-1 `✅ Fixed in #<PR>` with one line naming this PR's prototype and the export presets. Then `make docs-check` and `make test`.
- [ ] **Step 5: Commit.** `docs: add networking architecture and vps deploy steps #11`
