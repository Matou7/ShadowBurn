import asyncio
import json
import logging
import os
import socket
import time
from typing import Any, Dict, Set
import websockets
from websockets.asyncio.server import ServerConnection
from websockets.datastructures import Headers
from websockets.http11 import Request, Response

HOST = "0.0.0.0"
PORT = int(os.environ.get("SHADOWBURN_LAN_PORT", "8765"))

MAX_HUNTERS_PER_ROOM = 100
MAX_LOGS_STORED = 20
MAX_DAMAGE_PER_STRIKE = 500
MIN_STRIKE_INTERVAL_SEC = 1.5
MIN_ADMIN_INTERVAL_SEC = 2.0
ROOM_IDLE_TIMEOUT_SEC = 3600  # 1h d'inactivité -> recyclage


def get_local_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"


def http_guard(connection: ServerConnection, request: Request) -> Response | None:
    """Rejette proprement les requêtes HTTP non-WebSocket sans crash de traceback."""
    upgrade = (request.headers.get("Upgrade") or "").strip().lower()
    conn = (request.headers.get("Connection") or "").strip().lower()
    if upgrade != "websocket" or "upgrade" not in conn:
        body = (
            "ShadowBurn LAN WebSocket Server actif.\n"
            "Utilisez le protocole ws:// (et non http://) pour vous connecter.\n"
        ).encode("utf-8")
        headers = Headers(
            [
                ("Content-Type", "text/plain; charset=utf-8"),
                ("Content-Length", str(len(body))),
                ("Connection", "close"),
            ]
        )
        return Response(426, "Upgrade Required", headers, body)
    return None


class RaidRoom:
    def __init__(self, room_id: str, max_hp: int = 5000, duration_sec: int = 1800) -> None:
        now = time.time()
        self.room_id = room_id
        self.max_hp = max_hp
        self.current_hp = max_hp
        self.status = "waiting"  # waiting | active | victory | failed
        self.preset_label = f"RAID LAN ({max_hp} PV)"
        self.target_end_time = now + duration_sec
        self.last_activity = now
        self.hunters: Dict[str, Dict[str, Any]] = {}
        self.logs: list[Dict[str, Any]] = []
        self.clients: Set[ServerConnection] = set()

    def touch(self) -> None:
        self.last_activity = time.time()

    def tick_timer(self) -> bool:
        """Retourne True si l'état a changé (ex. défaite par temps écoulé)."""
        now = time.time()
        if self.status == "active" and self.current_hp > 0 and now >= self.target_end_time:
            self.status = "failed"
            self.touch()
            return True
        return False

    def apply_strike(
        self,
        hunter_id: str,
        hunter_name: str,
        category: str,
        reps: int,
        damage: int,
        action_label: str,
    ) -> tuple[bool, str]:
        self.tick_timer()
        if self.status != "active":
            return False, f"Salle [{self.room_id}] non active ({self.status})."

        if damage <= 0 or damage > MAX_DAMAGE_PER_STRIKE:
            return False, "Montant de dégâts invalide."

        reps_clean = max(1, min(reps, 50))
        now_ms = int(time.time() * 1000)

        if hunter_id not in self.hunters:
            if len(self.hunters) >= MAX_HUNTERS_PER_ROOM:
                return False, "Salle complète."
            self.hunters[hunter_id] = {
                "id": hunter_id,
                "name": hunter_name[:24],
                "total_damage": 0,
                "squat_reps": 0,
                "pushup_reps": 0,
                "abs_reps": 0,
                "last_seen": now_ms,
            }

        hunter = self.hunters[hunter_id]
        hunter["name"] = hunter_name[:24]
        hunter["total_damage"] = int(hunter["total_damage"]) + damage
        hunter["last_seen"] = now_ms

        if category == "squat":
            hunter["squat_reps"] = int(hunter["squat_reps"]) + reps_clean
        elif category == "pushup":
            hunter["pushup_reps"] = int(hunter["pushup_reps"]) + reps_clean
        elif category == "abs":
            hunter["abs_reps"] = int(hunter["abs_reps"]) + reps_clean

        self.current_hp = max(0, self.current_hp - damage)
        if self.current_hp == 0:
            self.status = "victory"

        self.logs.insert(
            0,
            {
                "id": hunter_id,
                "name": hunter["name"],
                "category": category,
                "reps": reps_clean,
                "action": action_label[:40],
                "damage": damage,
                "timestamp": now_ms,
            },
        )
        if len(self.logs) > MAX_LOGS_STORED:
            del self.logs[MAX_LOGS_STORED:]

        self.touch()
        return True, "OK"

    def to_payload(self) -> Dict[str, Any]:
        remaining_sec = max(0, int(self.target_end_time - time.time()))
        sorted_hunters = sorted(
            self.hunters.values(),
            key=lambda h: int(h.get("total_damage", 0)),
            reverse=True,
        )
        return {
            "type": "state",
            "roomId": self.room_id,
            "status": self.status,
            "preset_label": self.preset_label,
            "max_hp": self.max_hp,
            "current_hp": self.current_hp,
            "remaining_seconds": remaining_sec,
            "target_end_time_ms": int(self.target_end_time * 1000),
            "hunters": sorted_hunters,
            "logs": self.logs[:MAX_LOGS_STORED],
        }


class LanRaidServer:
    def __init__(self) -> None:
        self.rooms: Dict[str, RaidRoom] = {}
        self.client_room: Dict[ServerConnection, str] = {}
        self.last_strike_at: Dict[str, float] = {}
        self.last_admin_at: Dict[str, float] = {}

    def get_or_create_room(self, room_id: str) -> RaidRoom:
        clean_id = "".join(ch for ch in room_id.strip() if ch.isalnum() or ch in ("_", "-"))[:32]
        if not clean_id:
            clean_id = "room_1"
        if clean_id not in self.rooms:
            self.rooms[clean_id] = RaidRoom(clean_id)
        return self.rooms[clean_id]

    async def broadcast_room(self, room: RaidRoom) -> None:
        if not room.clients:
            return
        payload = json.dumps(room.to_payload(), ensure_ascii=False)
        dead: list[ServerConnection] = []
        for ws in list(room.clients):
            try:
                await ws.send(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            room.clients.discard(ws)

    async def send_error(self, ws: ServerConnection, message: str) -> None:
        try:
            await ws.send(json.dumps({"type": "error", "message": message}, ensure_ascii=False))
        except Exception:
            pass

    async def handle_client(self, ws: ServerConnection) -> None:
        peer = ws.remote_address
        print(f"[CONNEXION] Client connecté : {peer}")
        try:
            async for raw_msg in ws:
                if not isinstance(raw_msg, str) or len(raw_msg) > 4096:
                    await self.send_error(ws, "Message invalide ou trop volumineux.")
                    continue

                try:
                    msg = json.loads(raw_msg)
                except json.JSONDecodeError:
                    await self.send_error(ws, "JSON mal formé.")
                    continue

                if not isinstance(msg, dict):
                    await self.send_error(ws, "Format de message invalide.")
                    continue

                msg_type = str(msg.get("type", "")).strip()
                room_id = str(msg.get("roomId", self.client_room.get(ws, "room_1"))).strip()
                room = self.get_or_create_room(room_id)

                old_room_id = self.client_room.get(ws)
                if old_room_id and old_room_id != room.room_id and old_room_id in self.rooms:
                    self.rooms[old_room_id].clients.discard(ws)

                self.client_room[ws] = room.room_id
                room.clients.add(ws)
                room.touch()

                if msg_type == "join":
                    hunter_id = str(msg.get("hunterId", f"id_{id(ws)}"))[:40]
                    hunter_name = str(msg.get("name", "Chasseur"))[:24]
                    if hunter_id not in room.hunters:
                        if len(room.hunters) >= MAX_HUNTERS_PER_ROOM:
                            await self.send_error(ws, "Salle complète.")
                            continue
                        room.hunters[hunter_id] = {
                            "id": hunter_id,
                            "name": hunter_name,
                            "total_damage": 0,
                            "squat_reps": 0,
                            "pushup_reps": 0,
                            "abs_reps": 0,
                            "last_seen": int(time.time() * 1000),
                        }
                    await ws.send(json.dumps(room.to_payload(), ensure_ascii=False))

                elif msg_type == "strike":
                    hunter_id = str(msg.get("hunterId", f"id_{id(ws)}"))[:40]
                    now = time.monotonic()
                    prev = self.last_strike_at.get(hunter_id, 0.0)
                    if now - prev < MIN_STRIKE_INTERVAL_SEC:
                        await self.send_error(ws, "Anti-spam frappe actif.")
                        continue
                    self.last_strike_at[hunter_id] = now

                    hunter_name = str(msg.get("name", "Chasseur"))[:24]
                    category = str(msg.get("category", "squat"))[:16]
                    action_label = str(msg.get("action", "Frappe"))[:40]
                    try:
                        reps = int(msg.get("reps", 5))
                        damage = int(msg.get("damage", 25))
                    except (TypeError, ValueError):
                        await self.send_error(ws, "Valeurs numériques invalides.")
                        continue

                    ok, err = room.apply_strike(
                        hunter_id=hunter_id,
                        hunter_name=hunter_name,
                        category=category,
                        reps=reps,
                        damage=damage,
                        action_label=action_label,
                    )
                    if not ok:
                        await self.send_error(ws, err)
                        continue
                    await self.broadcast_room(room)

                elif msg_type == "admin":
                    actor_id = str(msg.get("actorId", f"admin_{id(ws)}"))[:40]
                    now = time.monotonic()
                    prev = self.last_admin_at.get(actor_id, 0.0)
                    if now - prev < MIN_ADMIN_INTERVAL_SEC:
                        await self.send_error(ws, "Anti-spam admin actif.")
                        continue
                    self.last_admin_at[actor_id] = now

                    cmd = str(msg.get("command", "")).strip()
                    if cmd == "start":
                        room.status = "active"
                        if time.time() >= room.target_end_time:
                            room.target_end_time = time.time() + 1800
                    elif cmd == "strike_boss":
                        try:
                            dmg = int(msg.get("damage", 200))
                        except (TypeError, ValueError):
                            dmg = 200
                        dmg = max(1, min(dmg, 5000))
                        room.current_hp = max(0, room.current_hp - dmg)
                        if room.current_hp == 0:
                            room.status = "victory"
                    elif cmd == "reset_boss":
                        room.current_hp = room.max_hp
                        room.status = "active"
                        room.logs.clear()
                        for h in room.hunters.values():
                            h["total_damage"] = 0
                            h["squat_reps"] = 0
                            h["pushup_reps"] = 0
                            h["abs_reps"] = 0
                    elif cmd == "set_preset":
                        try:
                            hp = int(msg.get("maxHp", 5000))
                        except (TypeError, ValueError):
                            hp = 5000
                        hp = max(500, min(hp, 500000))
                        room.max_hp = hp
                        room.current_hp = hp
                        room.preset_label = str(msg.get("label", f"RAID LAN ({hp} PV)"))[:50]
                        room.logs.clear()
                    elif cmd == "add_minutes":
                        try:
                            mins = int(msg.get("minutes", 1))
                        except (TypeError, ValueError):
                            mins = 1
                        mins = max(-240, min(mins, 240))
                        base = max(time.time(), room.target_end_time) if mins > 0 else room.target_end_time
                        room.target_end_time = max(time.time(), base + mins * 60)
                    elif cmd == "expire_now":
                        room.target_end_time = time.time() - 1
                        room.status = "failed"
                    else:
                        await self.send_error(ws, f"Commande admin inconnue : {cmd}")
                        continue

                    room.touch()
                    await self.broadcast_room(room)

                elif msg_type == "ping":
                    await ws.send(json.dumps({"type": "pong", "roomId": room.room_id}))

                else:
                    await self.send_error(ws, f"Type de message inconnu : {msg_type}")

        except websockets.ConnectionClosed:
            pass
        finally:
            room_id = self.client_room.pop(ws, None)
            if room_id and room_id in self.rooms:
                self.rooms[room_id].clients.discard(ws)
            print(f"[DÉCONNEXION] Client déconnecté : {peer}")

    async def maintenance_loop(self) -> None:
        while True:
            await asyncio.sleep(1.0)
            now = time.time()
            stale_rooms: list[str] = []

            for room_id, room in list(self.rooms.items()):
                changed = room.tick_timer()
                if changed:
                    await self.broadcast_room(room)

                if not room.clients and (now - room.last_activity) > ROOM_IDLE_TIMEOUT_SEC:
                    stale_rooms.append(room_id)

            for room_id in stale_rooms:
                del self.rooms[room_id]
                print(f"[NETTOYAGE] Salle inactive supprimée : {room_id}")


async def run_server() -> None:
    logging.getLogger("websockets").setLevel(logging.CRITICAL)
    server_logic = LanRaidServer()
    local_ip = get_local_ip()
    stop_event = asyncio.Event()

    async with websockets.serve(
        server_logic.handle_client,
        HOST,
        PORT,
        process_request=http_guard,
    ):
        print(f"Serveur ShadowBurn LAN actif sur ws://0.0.0.0:{PORT}")
        print(f"Adresse Wi-Fi locale : ws://{local_ip}:{PORT}")
        print("Appuyez sur Ctrl+C pour arrêter proprement.")

        maint_task = asyncio.create_task(server_logic.maintenance_loop())
        try:
            await stop_event.wait()
        finally:
            maint_task.cancel()
            try:
                await maint_task
            except asyncio.CancelledError:
                pass


def main() -> None:
    try:
        asyncio.run(run_server())
    except KeyboardInterrupt:
        print("\n[ARRÊT] Serveur ShadowBurn LAN stoppé proprement.")


if __name__ == "__main__":
    main()