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

from .const import (
    API_PLAYBACK_ACTIONS,
    API_SCREEN_COMMANDS,
    API_SMART_COMMANDS,
    IR_CODES,
    KEY_ALIASES,
    OFF_PLAYER_STATES,
    SEEK_STEP_SECONDS,
)
from .coordinator import DuneHDConfigEntry, DuneHDCoordinator
from .entity import DuneHDEntity

_HEX_CODE = re.compile(r"^[0-9A-Fa-f]{8}$")


def _normalize(cmd: str) -> str:
    """Map any accepted spelling to a Dune HD command name (or raw hex code)."""
    raw = cmd.strip()
    if _HEX_CODE.match(raw) and raw.lower() not in IR_CODES:
        return raw.upper()
    key = raw.lower()
    if key.startswith("keycode_"):
        key = key[len("keycode_"):]
    return KEY_ALIASES.get(key, key)


def _is_known(name: str) -> bool:
    return (
        name in IR_CODES
        or name in API_SCREEN_COMMANDS
        or name in API_PLAYBACK_ACTIONS
        or name in API_SMART_COMMANDS
        or bool(_HEX_CODE.match(name))
    )


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
        """Accepts Dune names (up, enter, return, ...), raw 8-hex IR codes,
        main_screen / black_screen / standby, stop / prev / next, and Android TV
        style keys (DPAD_UP, DPAD_CENTER, BACK, HOME, MEDIA_PLAY_PAUSE, ...)."""
        repeats = kwargs.get(ATTR_NUM_REPEATS, DEFAULT_NUM_REPEATS)
        delay = kwargs.get(ATTR_DELAY_SECS, DEFAULT_DELAY_SECS)
        names = [_normalize(c) for c in command]

        # Validate everything first so a typo doesn't send half a sequence
        for original, name in zip(command, names):
            if not _is_known(name):
                raise ServiceValidationError(f"Unknown Dune HD command: {original}")

        first = True
        for _ in range(repeats):
            for name in names:
                if not first and delay:
                    await asyncio.sleep(delay)
                first = False
                await self._send_one(name)

    async def _send_one(self, name: str) -> None:
        client = self._client
        if name in IR_CODES:
            await self._async_run(client.ir_code, IR_CODES[name])
        elif name in API_SCREEN_COMMANDS:
            await self._async_run(getattr(client, name))
        elif name in API_PLAYBACK_ACTIONS:
            await self._async_run(client.playback_action, name)
        elif name in API_SMART_COMMANDS:
            await self._send_smart(name)
        else:
            await self._async_run(client.ir_code, name)

    async def _send_smart(self, name: str) -> None:
        """Commands that depend on the current player state."""
        client = self._client
        status = self._status
        speed = status.get("playback_speed")
        if name == "power_on":
            await self._async_run(client.main_screen)
        elif name == "power_off":
            await self._async_run(client.standby)
        elif name == "power_toggle":
            if status.get("player_state", "standby") in OFF_PLAYER_STATES:
                await self._async_run(client.main_screen)
            else:
                await self._async_run(client.standby)
        elif name == "play":
            await self._async_run(client.set_playback_state, speed=256)
        elif name == "pause":
            await self._async_run(client.set_playback_state, speed=0)
        elif name == "play_pause":
            paused = speed is not None and speed.lstrip("-").isdigit() and int(speed) == 0
            await self._async_run(client.set_playback_state, speed=256 if paused else 0)
        elif name in ("rewind", "fast_forward"):
            pos = status.get("playback_position", "")
            if not pos.lstrip("-").isdigit() or int(pos) < 0:
                raise ServiceValidationError("Dune HD: nothing is playing to seek")
            step = -SEEK_STEP_SECONDS if name == "rewind" else SEEK_STEP_SECONDS
            await self._async_run(
                client.set_playback_state, position=max(0, int(pos) + step)
            )
