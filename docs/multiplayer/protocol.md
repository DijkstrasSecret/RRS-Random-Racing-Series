# Signalling protocol

*Current · updated 2026-11-26*

The signalling server hands out room codes and passes WebRTC connection details between a host and the players who join it. Once the WebRTC connection is open, the game talks peer to peer and the server carries nothing more. The server is `server/signalling/signalling.py`; its tests are `server/signalling/test_signalling.py`.

## Messages

Every message is one JSON object in a WebSocket text frame.

| Direction | Message |
|---|---|
| client → server | `{"type":"host"}` · `{"type":"join","code":"ABCD"}` · `{"type":"offer"/"answer","to":int,"sdp":str}` · `{"type":"candidate","to":int,"mid":str,"index":int,"sdp":str}` |
| server → host | `{"type":"hosted","code":str,"id":1,"ice_servers":[…]}` · `{"type":"peer_joined","id":int}` · `{"type":"peer_left","id":int}` |
| server → client | `{"type":"joined","code":str,"id":int,"ice_servers":[…]}` · `{"type":"closed","reason":"host_left"}` |
| server → either | `offer` / `answer` / `candidate` relayed with `"from":int` in place of `"to"` · `{"type":"error","reason":…}` |

Error reasons:

| Reason | When |
|---|---|
| `no_such_room` | The code doesn't match an open room. |
| `room_full` | The room already has 8 connections, host included. |
| `already_in_room` | This connection already hosted or joined a room. |
| `bad_message` | Not JSON, an unknown `type`, a missing or wrong-typed field, or a `to` the sender may not reach. |

## Rules

- **Peer ids:** the host is `1`. Clients are `2, 3, …` in join order, and an id is never reused within a room.
- **Who can talk to whom:** a client may only send to `1`; the host may send to any of its clients. This is the star topology from ADR 0002: clients never connect to each other.
- **Room codes:** 4 characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no `0`/`O` or `1`/`I`), random, and unique among open rooms. The server strips spaces and upper-cases a code before looking it up, so `" k7qm "` finds `K7QM`.
- **Room life:** a room closes when the host's connection closes, and every client gets `closed` / `host_left`. When a client's connection closes, the host gets `peer_left`.
- **Size limit:** a frame over 64 KB closes the connection. Any other bad message gets `bad_message`, and the connection stays open.

## Typical join

1. Host sends `host` and gets `hosted` with code `K7QM`. The host shows the code.
2. A friend sends `join` `K7QM` and gets `joined` with id `2`. The host gets `peer_joined` `2`.
3. The host sends an `offer` to `2`. The client answers with an `answer` to `1`. Both sides send `candidate`s as they find them.
4. The WebRTC connection opens. Both sides can keep the signalling connection open, so the client learns at once if the host leaves.

## ICE servers

`hosted` and `joined` carry `ice_servers`, the list a WebRTC peer needs to find a route to the other side:

- One `{"urls":[url]}` per `--stun` option.
- With `--turn-url` (repeatable) and `--turn-secret`, one TURN entry: `{"urls":[…],"username":"<expiry>:rrs","credential":base64(HMAC-SHA1(secret, username))}`. This is coturn's `use-auth-secret` scheme; the username's expiry is a Unix time 6 hours ahead.
- With neither option the list is empty, which works on one PC or one home network.

## Running it

```sh
make server-venv    # once: creates server/.venv with websockets 17.4
make signalling     # ws://127.0.0.1:9081
make test-signalling
```

The server needs Python 3.11 or newer.
