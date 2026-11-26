"""Room-code signalling server for RRS online play (ADR 0002).

    python server/signalling/signalling.py --host 127.0.0.1 --port 9081 \\
        [--stun URL ...] [--turn-url URL ...] [--turn-secret SECRET]

A host asks for a room and gets a 4-character code; friends join with that
code. The server then only passes WebRTC offers, answers and ICE candidates
between the host and each client, so they can connect directly. No game
traffic goes through it. The protocol is described in
docs/multiplayer/protocol.md:

    client -> server  {"type":"host"}
                      {"type":"join","code":"ABCD"}
                      {"type":"offer"|"answer","to":int,"sdp":str}
                      {"type":"candidate","to":int,"mid":str,"index":int,"sdp":str}
    server -> host    {"type":"hosted","code":str,"id":1,"ice_servers":[...]}
                      {"type":"peer_joined","id":int}  {"type":"peer_left","id":int}
    server -> client  {"type":"joined","code":str,"id":int,"ice_servers":[...]}
                      {"type":"closed","reason":"host_left"}
    server -> either  offer/answer/candidate relayed with "from" in place of "to"
                      {"type":"error","reason":"no_such_room"|"room_full"|
                                                "bad_message"|"already_in_room"}

Messages are JSON text frames. A frame over 64 KB closes the connection; any
other bad message gets an error and the connection stays open. The host is
peer 1 and clients are 2, 3, ... in join order, never reused within a room.
A room holds at most 8 connections, host included, and closes when the host
disconnects.

With --turn-secret, each hosted/joined reply carries TURN REST credentials
for coturn's use-auth-secret mode, valid for 6 hours.
"""
import argparse
import asyncio
import base64
import hashlib
import hmac
import json
import secrets
import time
from dataclasses import dataclass, field

from websockets.asyncio.server import Server, ServerConnection, serve as ws_serve
from websockets.exceptions import ConnectionClosed

CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 4
MAX_PEERS = 8
MAX_MESSAGE_BYTES = 64 * 1024
TURN_TTL_S = 6 * 3600
HOST_ID = 1
RELAYED = {"offer": ("sdp",), "answer": ("sdp",), "candidate": ("mid", "index", "sdp")}


@dataclass
class Config:
    """ICE servers handed to every host and client."""
    stun_urls: list[str] = field(default_factory=list)
    turn_urls: list[str] = field(default_factory=list)
    turn_secret: str = ""


@dataclass
class Room:
    code: str
    host: ServerConnection
    clients: dict[int, ServerConnection] = field(default_factory=dict)
    next_id: int = HOST_ID + 1


def ice_servers(config: Config, now: float) -> list[dict]:
    """Returns the RTCIceServer list: one entry per STUN URL, plus TURN with credentials."""
    servers: list[dict] = [{"urls": [url]} for url in config.stun_urls]
    if config.turn_urls and config.turn_secret:
        username = "%d:rrs" % int(now + TURN_TTL_S)
        digest = hmac.new(config.turn_secret.encode(), username.encode(), hashlib.sha1).digest()
        servers.append({"urls": list(config.turn_urls), "username": username,
                        "credential": base64.b64encode(digest).decode()})
    return servers


class Signalling:
    """All open rooms, and the WebSocket handler that serves them."""

    def __init__(self, config: Config) -> None:
        self.config = config
        self.rooms: dict[str, Room] = {}

    def _new_code(self) -> str:
        while True:
            code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
            if code not in self.rooms:
                return code

    async def handler(self, conn: ServerConnection) -> None:
        room: Room | None = None
        my_id = 0
        try:
            async for raw in conn:
                msg = _parse(raw)
                kind = msg.get("type") if msg else None
                if kind in ("host", "join") and room is not None:
                    await _send(conn, {"type": "error", "reason": "already_in_room"})
                elif kind == "host":
                    room = Room(self._new_code(), conn)
                    self.rooms[room.code] = room
                    my_id = HOST_ID
                    await _send(conn, {"type": "hosted", "code": room.code, "id": my_id,
                                       "ice_servers": ice_servers(self.config, time.time())})
                elif kind == "join" and isinstance(msg.get("code"), str):
                    target = self.rooms.get(msg["code"].strip().upper())
                    if target is None:
                        await _send(conn, {"type": "error", "reason": "no_such_room"})
                    elif 1 + len(target.clients) >= MAX_PEERS:
                        await _send(conn, {"type": "error", "reason": "room_full"})
                    else:
                        room, my_id = target, target.next_id
                        target.next_id += 1
                        target.clients[my_id] = conn
                        await _send(conn, {"type": "joined", "code": room.code, "id": my_id,
                                           "ice_servers": ice_servers(self.config, time.time())})
                        await _send(room.host, {"type": "peer_joined", "id": my_id})
                elif kind in RELAYED and room is not None and _well_formed(msg, kind):
                    to = msg["to"]
                    dest = room.clients.get(to) if my_id == HOST_ID else (room.host if to == HOST_ID else None)
                    if dest is None:
                        await _send(conn, {"type": "error", "reason": "bad_message"})
                    else:
                        out = {"type": kind, "from": my_id}
                        out.update({k: msg[k] for k in RELAYED[kind]})
                        await _send(dest, out)
                else:
                    await _send(conn, {"type": "error", "reason": "bad_message"})
        except ConnectionClosed:
            pass
        finally:
            await self._leave(room, my_id)

    async def _leave(self, room: Room | None, my_id: int) -> None:
        if room is None:
            return
        if my_id == HOST_ID:
            self.rooms.pop(room.code, None)
            for client in list(room.clients.values()):
                await _send(client, {"type": "closed", "reason": "host_left"})
        elif room.clients.pop(my_id, None) is not None and room.code in self.rooms:
            await _send(room.host, {"type": "peer_left", "id": my_id})


def _parse(raw: str | bytes) -> dict | None:
    if not isinstance(raw, str):
        return None
    try:
        msg = json.loads(raw)
    except ValueError:
        return None
    return msg if isinstance(msg, dict) else None


def _well_formed(msg: dict, kind: str) -> bool:
    if not isinstance(msg.get("to"), int) or isinstance(msg.get("to"), bool):
        return False
    types = {"sdp": str, "mid": str, "index": int}
    return all(isinstance(msg.get(k), types[k]) for k in RELAYED[kind])


async def _send(conn: ServerConnection, msg: dict) -> None:
    try:
        await conn.send(json.dumps(msg))
    except ConnectionClosed:
        pass


async def serve(host: str, port: int, config: Config) -> Server:
    """Starts the server and returns it (port 0 picks a free port)."""
    return await ws_serve(Signalling(config).handler, host, port, max_size=MAX_MESSAGE_BYTES)


async def _main() -> None:
    ap = argparse.ArgumentParser(description="RRS room-code signalling server")
    ap.add_argument("--host", default="127.0.0.1", help="address to listen on")
    ap.add_argument("--port", type=int, default=9081)
    ap.add_argument("--stun", action="append", default=[], help="STUN URL; repeatable")
    ap.add_argument("--turn-url", action="append", default=[], help="TURN URL; repeatable")
    ap.add_argument("--turn-secret", default="", help="coturn static-auth-secret")
    args = ap.parse_args()
    server = await serve(args.host, args.port, Config(args.stun, args.turn_url, args.turn_secret))
    print("signalling on ws://%s:%d" % (args.host, args.port), flush=True)
    await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(_main())
    except KeyboardInterrupt:
        pass
