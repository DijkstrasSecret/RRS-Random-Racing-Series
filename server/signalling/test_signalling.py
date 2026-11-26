"""Unit tests for the signalling server.

    make test-signalling
    server/.venv/bin/python -m unittest discover -s server/signalling -v

Each test starts the server on a free local port and talks to it with real
WebSocket clients.
"""
import asyncio
import base64
import hashlib
import hmac
import json
import re
import time
import unittest

from websockets.asyncio.client import connect

import signalling

TIMEOUT = 2.0


class ServerCase(unittest.IsolatedAsyncioTestCase):
    """Starts a server per test and gives helpers for its clients."""
    config = signalling.Config()

    async def asyncSetUp(self) -> None:
        self.server = await signalling.serve("127.0.0.1", 0, self.config)
        self.url = "ws://127.0.0.1:%d" % self.server.sockets[0].getsockname()[1]
        self.conns = []

    async def asyncTearDown(self) -> None:
        for c in self.conns:
            await c.close()
        self.server.close()
        await self.server.wait_closed()

    async def open(self):
        c = await connect(self.url)
        self.conns.append(c)
        return c

    async def send(self, c, msg) -> None:
        await c.send(msg if isinstance(msg, str) else json.dumps(msg))

    async def recv(self, c) -> dict:
        return json.loads(await asyncio.wait_for(c.recv(), TIMEOUT))

    async def assert_silent(self, c) -> None:
        with self.assertRaises(asyncio.TimeoutError):
            await asyncio.wait_for(c.recv(), 0.2)

    async def host(self):
        h = await self.open()
        await self.send(h, {"type": "host"})
        return h, await self.recv(h)

    async def join(self, code: str):
        c = await self.open()
        await self.send(c, {"type": "join", "code": code})
        return c, await self.recv(c)


class SignallingTest(ServerCase):
    async def test_host_gets_code_and_id_1(self) -> None:
        _, hosted = await self.host()
        self.assertEqual(hosted["type"], "hosted")
        self.assertRegex(hosted["code"], r"^[A-HJ-NP-Z2-9]{4}$")
        self.assertEqual(hosted["id"], 1)
        self.assertEqual(hosted["ice_servers"], [])

    async def test_join_relays_offer_answer_candidate(self) -> None:
        h, hosted = await self.host()
        c, joined = await self.join(hosted["code"])
        self.assertEqual((joined["type"], joined["id"], joined["code"]), ("joined", 2, hosted["code"]))
        self.assertEqual(await self.recv(h), {"type": "peer_joined", "id": 2})
        await self.send(h, {"type": "offer", "to": 2, "sdp": "v=0 offer"})
        self.assertEqual(await self.recv(c), {"type": "offer", "from": 1, "sdp": "v=0 offer"})
        await self.send(c, {"type": "answer", "to": 1, "sdp": "v=0 answer"})
        self.assertEqual(await self.recv(h), {"type": "answer", "from": 2, "sdp": "v=0 answer"})
        await self.send(c, {"type": "candidate", "to": 1, "mid": "0", "index": 0, "sdp": "candidate:1"})
        self.assertEqual(await self.recv(h), {"type": "candidate", "from": 2, "mid": "0", "index": 0, "sdp": "candidate:1"})

    async def test_join_lower_case_code_with_spaces(self) -> None:
        _, hosted = await self.host()
        _, joined = await self.join(" %s " % hosted["code"].lower())
        self.assertEqual(joined["type"], "joined")

    async def test_unknown_code(self) -> None:
        _, reply = await self.join("ZZZZ")
        self.assertEqual(reply, {"type": "error", "reason": "no_such_room"})

    async def test_room_full_at_8(self) -> None:
        h, hosted = await self.host()
        for i in range(7):
            _, joined = await self.join(hosted["code"])
            self.assertEqual(joined["id"], i + 2)
        _, reply = await self.join(hosted["code"])
        self.assertEqual(reply, {"type": "error", "reason": "room_full"})

    async def test_client_cannot_message_other_client(self) -> None:
        _, hosted = await self.host()
        c2, _ = await self.join(hosted["code"])
        c3, _ = await self.join(hosted["code"])
        await self.send(c2, {"type": "offer", "to": 3, "sdp": "x"})
        self.assertEqual(await self.recv(c2), {"type": "error", "reason": "bad_message"})
        await self.assert_silent(c3)

    async def test_host_leaving_closes_room(self) -> None:
        h, hosted = await self.host()
        c, _ = await self.join(hosted["code"])
        await h.close()
        self.assertEqual(await self.recv(c), {"type": "closed", "reason": "host_left"})
        _, reply = await self.join(hosted["code"])
        self.assertEqual(reply, {"type": "error", "reason": "no_such_room"})

    async def test_client_leaving_tells_host(self) -> None:
        h, hosted = await self.host()
        c, _ = await self.join(hosted["code"])
        await self.recv(h)  # peer_joined
        await c.close()
        self.assertEqual(await self.recv(h), {"type": "peer_left", "id": 2})

    async def test_bad_json_keeps_connection(self) -> None:
        c = await self.open()
        await self.send(c, "not json")
        self.assertEqual(await self.recv(c), {"type": "error", "reason": "bad_message"})
        await self.send(c, {"type": "host"})
        self.assertEqual((await self.recv(c))["type"], "hosted")

    async def test_second_host_or_join_is_refused(self) -> None:
        h, hosted = await self.host()
        await self.send(h, {"type": "join", "code": hosted["code"]})
        self.assertEqual(await self.recv(h), {"type": "error", "reason": "already_in_room"})


class TurnCredentialsTest(ServerCase):
    config = signalling.Config(turn_urls=["turn:x:3478"], turn_secret="s3cret", stun_urls=["stun:x:3478"])

    async def test_turn_credentials(self) -> None:
        _, hosted = await self.host()
        stun, turn = hosted["ice_servers"]
        self.assertEqual(stun, {"urls": ["stun:x:3478"]})
        self.assertEqual(turn["urls"], ["turn:x:3478"])
        expected = base64.b64encode(hmac.new(b"s3cret", turn["username"].encode(), hashlib.sha1).digest()).decode()
        self.assertEqual(turn["credential"], expected)
        expiry = int(re.match(r"^(\d+):rrs$", turn["username"]).group(1))
        self.assertAlmostEqual(expiry, time.time() + 6 * 3600, delta=5)


if __name__ == "__main__":
    unittest.main()
