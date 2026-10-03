"""Polling coordinator for Dune HD."""
from __future__ import annotations

from datetime import timedelta
import logging

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .api import DuneHDClient, DuneHDConnectionError, DuneHDError
from .const import SCAN_INTERVAL_SECONDS, STATE_UNREACHABLE
from .ui_browser import DuneUINavigator

_LOGGER = logging.getLogger(__name__)

type DuneHDConfigEntry = ConfigEntry[DuneHDCoordinator]

_DEVICE_KEYS = (
    "product_id",
    "product_name",
    "firmware_version",
    "serial_number",
    "commercial_serial_number",
)


class DuneHDCoordinator(DataUpdateCoordinator[dict[str, str]]):
    """Polls cmd=status."""

    config_entry: DuneHDConfigEntry

    def __init__(
        self, hass: HomeAssistant, entry: DuneHDConfigEntry, client: DuneHDClient
    ) -> None:
        super().__init__(
            hass,
            _LOGGER,
            config_entry=entry,
            name=f"Dune HD {entry.title}",
            update_interval=timedelta(seconds=SCAN_INTERVAL_SECONDS),
        )
        self.client = client
        self.ui = DuneUINavigator(client)
        self.protocol_version = 0
        self.device_details: dict[str, str] = {}

    async def _async_update_data(self) -> dict[str, str]:
        try:
            data = await self.client.status()
        except DuneHDConnectionError as err:
            # Fully powered off / unplugged: show as "off" instead of unavailable
            _LOGGER.debug("Dune HD unreachable: %s", err)
            return {"player_state": STATE_UNREACHABLE}
        except DuneHDError as err:
            raise UpdateFailed(str(err)) from err
        self.remember(data)
        return data

    def remember(self, data: dict[str, str]) -> None:
        """Keep protocol version and device info across offline periods."""
        if (pv := data.get("protocol_version", "")).isdigit():
            self.protocol_version = int(pv)
        for key in _DEVICE_KEYS:
            if data.get(key):
                self.device_details[key] = data[key]
