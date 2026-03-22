#!/usr/bin/env python3
"""Party Pool MVP prototype server.

This is a dependency-free prototype backend + static file host built on Python stdlib.
It implements:
1. Room create/join
2. Permission-gated join
3. 60-second ready timeout with auto-start
4. Tap challenge round with +1 score to all first-place ties
5. Basic rejoin token flow
"""

from __future__ import annotations

import json
import os
import secrets
import string
import threading
import time
from dataclasses import dataclass, field
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, quote, urlparse

ROOM_CODE_LEN = 4
MAX_PLAYERS = 8
READY_TIMEOUT_SEC = 60
ROUND_DURATION_SEC = 20
TOTAL_ROUNDS = 3
DISCONNECT_AFTER_SEC = 12
TICK_INTERVAL_SEC = 0.25
ROUND_COUNTDOWN_SEC = 3
LONG_POLL_TIMEOUT_SEC = 25.0


def _now() -> float:
    return time.time()


def _make_room_code(existing: set[str]) -> str:
    alphabet = string.ascii_uppercase + string.digits
    while True:
        code = "".join(secrets.choice(alphabet) for _ in range(ROOM_CODE_LEN))
        if code not in existing:
            return code


def _detect_lang(raw: str | None) -> str:
    if not raw:
        return "en"
    normalized = raw.lower()
    if normalized.startswith("zh"):
        return "zh-TW"
    return "en"


@dataclass
class Player:
    player_id: str
    nickname: str
    token: str
    lang: str
    score: int = 0
    connected: bool = True
    ready_ok: bool = False
    last_seen_at: float = field(default_factory=_now)


@dataclass
class Room:
    room_code: str
    host_token: str
    created_at: float = field(default_factory=_now)
    players: dict[str, Player] = field(default_factory=dict)
    status: str = "waiting"  # waiting | readying | playing | ended
    round_index: int = 0
    ready_deadline_at: float | None = None
    round_end_at: float | None = None
    tap_counts: dict[str, int] = field(default_factory=dict)
    last_round_result: dict[str, Any] | None = None
    version: int = 1


class PartyPoolState:
    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._rooms: dict[str, Room] = {}
        self._token_to_room: dict[str, tuple[str, str | None]] = {}
        self._cv = threading.Condition(self._lock)

    def create_room(self) -> tuple[Room, str]:
        with self._lock:
            code = _make_room_code(set(self._rooms.keys()))
            host_token = secrets.token_urlsafe(16)
            room = Room(room_code=code, host_token=host_token)
            self._rooms[code] = room
            self._token_to_room[host_token] = (code, None)
            self._bump_room_locked(code)
            return room, host_token

    def _bump_room_locked(self, room_code: str) -> None:
        room = self._rooms.get(room_code)
        if room is None:
            return
        room.version += 1
        self._cv.notify_all()

    def get_room(self, room_code: str) -> Room | None:
        with self._lock:
            return self._rooms.get(room_code)

    def join_room(
        self,
        *,
        room_code: str,
        nickname: str,
        lang: str,
        permission_granted: bool,
        rejoin_token: str | None = None,
    ) -> tuple[Player, Room]:
        if not permission_granted:
            raise ValueError("permission_required")
        with self._lock:
            room = self._rooms.get(room_code)
            if room is None:
                raise ValueError("room_not_found")
            if len(room.players) >= MAX_PLAYERS and rejoin_token is None:
                raise ValueError("room_full")

            if rejoin_token:
                linked = self._token_to_room.get(rejoin_token)
                if not linked or linked[0] != room_code:
                    raise ValueError("invalid_rejoin_token")
                player_id = linked[1]
                if player_id is None or player_id not in room.players:
                    raise ValueError("invalid_rejoin_token")
                player = room.players[player_id]
                player.connected = True
                player.last_seen_at = _now()
                if lang:
                    player.lang = lang
                self._bump_room_locked(room_code)
                return player, room

            player_id = secrets.token_hex(6)
            token = secrets.token_urlsafe(16)
            player = Player(
                player_id=player_id,
                nickname=nickname.strip()[:20] or "Player",
                token=token,
                lang=lang,
            )
            room.players[player_id] = player
            self._token_to_room[token] = (room_code, player_id)
            self._bump_room_locked(room_code)
            return player, room

    def _resolve_room_and_actor(self, token: str) -> tuple[Room, Player | None] | None:
        with self._lock:
            linked = self._token_to_room.get(token)
            if not linked:
                return None
            room_code, player_id = linked
            room = self._rooms.get(room_code)
            if room is None:
                return None
            if player_id is None:
                return room, None
            player = room.players.get(player_id)
            if player is None:
                return None
            return room, player

    def touch(self, token: str) -> None:
        resolved = self._resolve_room_and_actor(token)
        if not resolved:
            return
        room, player = resolved
        if player:
            with self._lock:
                was_connected = player.connected
                player.last_seen_at = _now()
                player.connected = True
                if not was_connected:
                    self._bump_room_locked(room.room_code)

    def start_round_ready_phase(self, *, room_code: str, host_token: str) -> Room:
        with self._lock:
            room = self._rooms.get(room_code)
            if room is None:
                raise ValueError("room_not_found")
            if room.host_token != host_token:
                raise ValueError("unauthorized")

            if room.status in {"readying", "playing"}:
                raise ValueError("round_in_progress")

            if room.status == "ended":
                room.round_index = 0
                room.last_round_result = None
                for p in room.players.values():
                    p.score = 0

            room.status = "readying"
            room.ready_deadline_at = _now() + READY_TIMEOUT_SEC
            room.round_end_at = None
            room.tap_counts = {pid: 0 for pid in room.players}
            for player in room.players.values():
                player.ready_ok = False
            self._bump_room_locked(room_code)
            return room

    def mark_ready_ok(self, *, room_code: str, token: str) -> Room:
        with self._lock:
            room = self._rooms.get(room_code)
            if room is None:
                raise ValueError("room_not_found")
            linked = self._token_to_room.get(token)
            if not linked or linked[0] != room_code or linked[1] is None:
                raise ValueError("unauthorized")
            if room.status != "readying":
                raise ValueError("not_ready_phase")
            player_id = linked[1]
            player = room.players.get(player_id)
            if player is None:
                raise ValueError("unauthorized")
            player.ready_ok = True
            player.last_seen_at = _now()
            player.connected = True
            self._bump_room_locked(room_code)
            return room

    def register_tap(self, *, room_code: str, token: str) -> Room:
        with self._lock:
            room = self._rooms.get(room_code)
            if room is None:
                raise ValueError("room_not_found")
            linked = self._token_to_room.get(token)
            if not linked or linked[0] != room_code or linked[1] is None:
                raise ValueError("unauthorized")
            if room.status != "playing":
                raise ValueError("not_playing")
            if room.round_end_at is not None and _now() >= room.round_end_at:
                raise ValueError("round_ended")
            player_id = linked[1]
            if player_id not in room.tap_counts:
                room.tap_counts[player_id] = 0
            room.tap_counts[player_id] += 1
            player = room.players[player_id]
            player.last_seen_at = _now()
            player.connected = True
            self._bump_room_locked(room_code)
            return room

    def snapshot(self, *, room_code: str, token: str) -> dict[str, Any]:
        with self._lock:
            room = self._rooms.get(room_code)
            if room is None:
                raise ValueError("room_not_found")
            linked = self._token_to_room.get(token)
            if not linked or linked[0] != room_code:
                raise ValueError("unauthorized")
            actor_id = linked[1]
            if actor_id is not None and actor_id in room.players:
                room.players[actor_id].last_seen_at = _now()
                room.players[actor_id].connected = True

            return {
                "version": room.version,
                "room_code": room.room_code,
                "status": room.status,
                "round_index": room.round_index,
                "total_rounds": TOTAL_ROUNDS,
                "ready_deadline_at": room.ready_deadline_at,
                "round_end_at": room.round_end_at,
                "control_profile": {
                    "mode": "tap",
                    "instruction_key": "round1.tap_fast",
                    "round_duration_sec": ROUND_DURATION_SEC,
                    "ready_timeout_sec": READY_TIMEOUT_SEC,
                    "countdown_sec": ROUND_COUNTDOWN_SEC,
                    "allow_input_before_start": False,
                },
                "server_time": _now(),
                "you_are_host": actor_id is None,
                "your_player_id": actor_id,
                "players": [
                    {
                        "player_id": p.player_id,
                        "nickname": p.nickname,
                        "connected": p.connected,
                        "ready_ok": p.ready_ok,
                        "score": p.score,
                        "taps": room.tap_counts.get(p.player_id, 0),
                        "lang": p.lang,
                    }
                    for p in room.players.values()
                ],
                "last_round_result": room.last_round_result,
            }

    def wait_for_update(
        self,
        *,
        room_code: str,
        token: str,
        after_version: int,
        timeout_sec: float = LONG_POLL_TIMEOUT_SEC,
    ) -> dict[str, Any]:
        deadline = _now() + timeout_sec
        with self._lock:
            while True:
                room = self._rooms.get(room_code)
                if room is None:
                    raise ValueError("room_not_found")
                linked = self._token_to_room.get(token)
                if not linked or linked[0] != room_code:
                    raise ValueError("unauthorized")
                if room.version > after_version:
                    break
                remaining = deadline - _now()
                if remaining <= 0:
                    break
                self._cv.wait(timeout=remaining)
        return self.snapshot(room_code=room_code, token=token)

    def tick(self) -> None:
        with self._lock:
            now = _now()
            for room in self._rooms.values():
                room_changed = False
                for player in room.players.values():
                    should_disconnect = now - player.last_seen_at > DISCONNECT_AFTER_SEC
                    if should_disconnect and player.connected:
                        player.connected = False
                        room_changed = True

                if room.status == "readying":
                    all_ready = bool(room.players) and all(
                        p.connected and p.ready_ok for p in room.players.values()
                    )
                    timeout = room.ready_deadline_at is not None and now >= room.ready_deadline_at
                    if all_ready or timeout:
                        self._start_playing(room, now=now)
                        room_changed = True
                elif room.status == "playing":
                    timeout = room.round_end_at is not None and now >= room.round_end_at
                    if timeout:
                        self._finish_round(room)
                        room_changed = True
                if room_changed:
                    self._bump_room_locked(room.room_code)

    def _start_playing(self, room: Room, *, now: float) -> None:
        room.status = "playing"
        room.round_index += 1
        room.round_end_at = now + ROUND_DURATION_SEC
        room.ready_deadline_at = None
        room.tap_counts = {pid: 0 for pid in room.players}
        for player in room.players.values():
            player.ready_ok = False

    def _finish_round(self, room: Room) -> None:
        room.status = "ended" if room.round_index >= TOTAL_ROUNDS else "waiting"
        room.round_end_at = None
        counts = room.tap_counts.copy()
        if not counts:
            winners: list[str] = []
            top_score = 0
        else:
            top_score = max(counts.values())
            winners = [pid for pid, value in counts.items() if value == top_score]
            for pid in winners:
                if pid in room.players:
                    room.players[pid].score += 1

        room.last_round_result = {
            "round_index": room.round_index,
            "tap_counts": counts,
            "top_taps": top_score,
            "winner_ids": winners,
            "winner_names": [
                room.players[pid].nickname for pid in winners if pid in room.players
            ],
        }
        room.tap_counts = {pid: 0 for pid in room.players}


STATE = PartyPoolState()


def _ticker() -> None:
    while True:
        STATE.tick()
        time.sleep(TICK_INTERVAL_SEC)


class PartyPoolHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        static_dir = os.path.join(os.path.dirname(__file__), "static")
        super().__init__(*args, directory=static_dir, **kwargs)

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
        print(f"[{self.log_date_time_string()}] {format % args}")

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/":
            self.path = "/host.html"
            return super().do_GET()
        if parsed.path == "/api/room-state":
            query = parse_qs(parsed.query)
            room_code = (query.get("room_code") or [""])[0].strip().upper()
            token = (query.get("token") or [""])[0].strip()
            return self._handle_room_state(room_code=room_code, token=token)
        if parsed.path == "/api/wait-state":
            query = parse_qs(parsed.query)
            room_code = (query.get("room_code") or [""])[0].strip().upper()
            token = (query.get("token") or [""])[0].strip()
            try:
                after_version = int((query.get("after_version") or ["0"])[0])
            except ValueError:
                after_version = 0
            return self._handle_wait_state(
                room_code=room_code,
                token=token,
                after_version=after_version,
            )
        return super().do_GET()

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        body = self._read_json()
        if body is None:
            return
        routes = {
            "/api/create-room": self._create_room,
            "/api/join-room": self._join_room,
            "/api/rejoin-room": self._rejoin_room,
            "/api/start-round": self._start_round,
            "/api/ready-ok": self._ready_ok,
            "/api/tap": self._tap,
        }
        handler = routes.get(parsed.path)
        if handler is None:
            self._send_json({"error": "not_found"}, status=HTTPStatus.NOT_FOUND)
            return
        handler(body)

    def _read_json(self) -> dict[str, Any] | None:
        length_str = self.headers.get("Content-Length")
        if not length_str:
            self._send_json({"error": "empty_body"}, status=HTTPStatus.BAD_REQUEST)
            return None
        try:
            length = int(length_str)
            payload = self.rfile.read(length).decode("utf-8")
            return json.loads(payload)
        except (ValueError, json.JSONDecodeError):
            self._send_json({"error": "invalid_json"}, status=HTTPStatus.BAD_REQUEST)
            return None

    def _send_json(self, payload: dict[str, Any], *, status: HTTPStatus = HTTPStatus.OK) -> None:
        raw = json.dumps(payload).encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _handle_room_state(self, *, room_code: str, token: str) -> None:
        try:
            snapshot = STATE.snapshot(room_code=room_code, token=token)
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        self._send_json(snapshot)

    def _handle_wait_state(self, *, room_code: str, token: str, after_version: int) -> None:
        try:
            snapshot = STATE.wait_for_update(
                room_code=room_code,
                token=token,
                after_version=after_version,
            )
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        self._send_json(snapshot)

    def _create_room(self, _: dict[str, Any]) -> None:
        room, host_token = STATE.create_room()
        base = f"http://{self.headers.get('Host', 'localhost:8000')}"
        join_url = f"{base}/controller.html?room={room.room_code}"
        qr_url = (
            "https://api.qrserver.com/v1/create-qr-code/?size=220x220&data="
            f"{quote(join_url, safe='')}"
        )
        self._send_json(
            {
                "room_code": room.room_code,
                "host_token": host_token,
                "join_url": join_url,
                "qr_url": qr_url,
            }
        )

    def _join_room(self, body: dict[str, Any]) -> None:
        room_code = str(body.get("room_code", "")).strip().upper()
        nickname = str(body.get("nickname", "")).strip()
        permission_granted = bool(body.get("permission_granted", False))
        lang = _detect_lang(str(body.get("lang") or self.headers.get("Accept-Language") or ""))
        try:
            player, room = STATE.join_room(
                room_code=room_code,
                nickname=nickname,
                lang=lang,
                permission_granted=permission_granted,
                rejoin_token=None,
            )
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        self._send_json(
            {
                "room_code": room.room_code,
                "player_id": player.player_id,
                "player_token": player.token,
                "rejoin_token": player.token,
                "lang": player.lang,
            }
        )

    def _rejoin_room(self, body: dict[str, Any]) -> None:
        room_code = str(body.get("room_code", "")).strip().upper()
        rejoin_token = str(body.get("rejoin_token", "")).strip()
        permission_granted = bool(body.get("permission_granted", False))
        lang = _detect_lang(str(body.get("lang") or self.headers.get("Accept-Language") or ""))
        try:
            player, room = STATE.join_room(
                room_code=room_code,
                nickname="",
                lang=lang,
                permission_granted=permission_granted,
                rejoin_token=rejoin_token,
            )
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        self._send_json(
            {
                "room_code": room.room_code,
                "player_id": player.player_id,
                "player_token": player.token,
                "rejoin_token": player.token,
                "lang": player.lang,
            }
        )

    def _start_round(self, body: dict[str, Any]) -> None:
        room_code = str(body.get("room_code", "")).strip().upper()
        host_token = str(body.get("host_token", "")).strip()
        try:
            room = STATE.start_round_ready_phase(room_code=room_code, host_token=host_token)
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        self._send_json(
            {
                "ok": True,
                "status": room.status,
                "ready_deadline_at": room.ready_deadline_at,
            }
        )

    def _ready_ok(self, body: dict[str, Any]) -> None:
        room_code = str(body.get("room_code", "")).strip().upper()
        token = str(body.get("player_token", "")).strip()
        try:
            room = STATE.mark_ready_ok(room_code=room_code, token=token)
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        self._send_json({"ok": True, "status": room.status})

    def _tap(self, body: dict[str, Any]) -> None:
        room_code = str(body.get("room_code", "")).strip().upper()
        token = str(body.get("player_token", "")).strip()
        try:
            room = STATE.register_tap(room_code=room_code, token=token)
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        linked = STATE._token_to_room.get(token)  # intentional lightweight lookup
        player_id = linked[1] if linked else None
        taps = room.tap_counts.get(player_id or "", 0)
        self._send_json({"ok": True, "my_taps": taps})


def run() -> None:
    ticker_thread = threading.Thread(target=_ticker, daemon=True)
    ticker_thread.start()

    host = "0.0.0.0"
    port = 8000
    server = ThreadingHTTPServer((host, port), PartyPoolHandler)
    print(f"Party Pool prototype server running on http://{host}:{port}")
    print("Open /host.html for the main display and /controller.html for mobile.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    run()
