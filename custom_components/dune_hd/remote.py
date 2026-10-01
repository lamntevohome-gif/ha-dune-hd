"""Remote entity for Dune HD: send IR codes and named commands."""
from __future__ import annotations

import asyncio
from collections.abc import Iterable
import re
from typing import Any

from homeassistant.components.remote import (
    ATTR_DELAY_SECS,
    ATTR_NUM_REPEATS,
    DEFAULT_DELAY_SECS,
    DEFAULT_NUM_REPEATS,
    RemoteEntity,
)
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import API_PLAYBACK_ACTIONS, API_SCREEN_COMMANDS, IR_CODES
from .coordinator import DuneHDConfigEntry, DuneHDCoordinator
from .entity import DuneHDEntity

_HEX_CODE = re.compile(r"^[0-9A-Fa-f]{8}$")


async def async_setup_entry(
    hass: HomeAssistant,
    entry: DuneHDConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    async_add_entities([DuneHDRemote(entry.runtime_data)])


class DuneHDRemote(DuneHDEntity, RemoteEntity):
    """Dune HD remote."""

    _attr_name = "Remote"

    def __init__(self, coordinator: DuneHDCoordinator) -> None:
        super().__init__(coordinator, "remote")

    @property
    def is_on(self) -> bool:
        return self._player_on

    async def async_turn_on(self, **kwargs: Any) -> None:
        await self._async_run(self._client.main_screen)

    async def async_turn_off(self, **kwargs: Any) -> None:
        await self._async_run(self._client.standby)

    async def async_send_command(self, command: Iterable[str], **kwargs: Any) -> None:
        """Accepts: named IR keys (up, enter, ...), raw 8-hex IR codes,
        main_screen / black_screen / standby, and stop / prev / next."""
        repeats = kwargs.get(ATTR_NUM_REPEATS, DEFAULT_NUM_REPEATS)
        delay = kwargs.get(ATTR_DELAY_SECS, DEFAULT_DELAY_SECS)
        commands = [c.strip() for c in command]

        # Validate everything first so a typo doesn't send half a sequence
        for cmd in commands:
            key = cmd.lower()
            if not (
                key in IR_CODES
                or key in API_SCREEN_COMMANDS
                or key in API_PLAYBACK_ACTIONS
                or _HEX_CODE.match(cmd)
            ):
                raise ServiceValidationError(f"Unknown Dune HD command: {cmd}")

        first = True
        for _ in range(repeats):
            for cmd in commands:
                if not first and delay:
                    await asyncio.sleep(delay)
                first = False
                key = cmd.lower()
                if key in IR_CODES:
                    await self._async_run(self._client.ir_code, IR_CODES[key])
                elif key in API_SCREEN_COMMANDS:
                    await self._async_run(getattr(self._client, key))
                elif key in API_PLAYBACK_ACTIONS:
                    await self._async_run(self._client.playback_action, key)
                else:
                    await self._async_run(self._client.ir_code, cmd)
