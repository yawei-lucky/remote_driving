"""Relay legacy to_fleetMonitor vehicle telemetry to fleet_monitor.html."""

import asyncio
import json
import logging

from websockets.asyncio.server import broadcast, serve
from websockets.exceptions import ConnectionClosed


LOGGER = logging.getLogger("fleet_monitor")


class FleetRelay:
    def __init__(self):
        self.vehicles = {}
        self.viewers = set()
        self.snapshot = None

    async def handle_client(self, websocket):
        self.viewers.add(websocket)
        LOGGER.info("Client connected: %s", websocket.remote_address)
        try:
            if self.snapshot is not None:
                broadcast({websocket}, self.snapshot)

            async for message in websocket:
                try:
                    update = json.loads(message)
                    if not isinstance(update, dict) or not update or not all(
                        isinstance(state, dict) for state in update.values()
                    ):
                        raise ValueError("expected {vehicle_id: {vehicle state}}")
                    # Reject NaN / Infinity before they can poison browser JSON.
                    json.dumps(update, allow_nan=False)
                except (ValueError, UnicodeError, RecursionError):
                    LOGGER.warning("Ignored invalid telemetry from %s", websocket.remote_address)
                    continue

                # Upload-only clients must not accumulate their own broadcasts.
                if websocket in self.viewers:
                    LOGGER.info("收到车端数据: %s", ", ".join(update))
                self.viewers.discard(websocket)
                for vehicle_id, state in update.items():
                    self.vehicles.setdefault(vehicle_id, {}).update(state)
                self.snapshot = json.dumps(
                    self.vehicles, allow_nan=False, separators=(",", ":")
                )
                # A slow browser cannot block incoming vehicle telemetry.
                broadcast(self.viewers, self.snapshot)
        except ConnectionClosed:
            pass
        finally:
            self.viewers.discard(websocket)
            LOGGER.info("Client disconnected: %s", websocket.remote_address)


async def main():
    relay = FleetRelay()
    async with serve(relay.handle_client, "0.0.0.0", 8004):
        LOGGER.info("Fleet Monitor telemetry listening on ws://0.0.0.0:8004")
        await asyncio.Future()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
