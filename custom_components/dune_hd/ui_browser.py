"""Mirror the Dune HD on-screen menu (cmd=ui_state) for the HA media browser.

Works like the official Dune HD phone app: read the current screen with
ui_state, open items with ui_action_enter, go back with ui_action_return.
Browsing therefore also moves the menu on the TV.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Any
from urllib.parse import quote, unquote

from .api import DuneHDClient
from .const import UI_PREFIX

_LOGGER = logging.getLogger(__name__)

CHANGE_TIMEOUT = 6.0  # seconds to wait for the screen to change after ENTER
SETTLE_TIMEOUT = 4.0  # seconds to wait for the screen to settle after RETURN
POLL_INTERVAL = 0.35

Signature = tuple[Any, ...]


def encode_path(path: list[str]) -> str:
    """Item-id path from the main screen -> media_content_id."""
    return UI_PREFIX + "/".join(quote(p, safe="") for p in path)


def decode_path(content_id: str) -> list[str]:
    rest = content_id[len(UI_PREFIX):]
    return [unquote(p) for p in rest.split("/")] if rest else []


def screen_of(state: dict[str, Any]) -> dict[str, Any]:
    return (state.get("ui_state") or {}).get("screen") or {}


def is_navigator(state: dict[str, Any]) -> bool:
    return screen_of(state).get("type") == "navigator"


def _signature(state: dict[str, Any]) -> Signature:
    ui = state.get("ui_state") or {}
    screen = ui.get("screen") or {}
    return (
        state.get("player_state"),
        state.get("android_app_active"),
        screen.get("type"),
        screen.get("folder_id"),
        tuple(item.get("id") for item in screen.get("items") or []),
        len(ui.get("dialogs") or []),
    )


class DuneUINavigator:
    """Keeps track of where the TV menu is, so browsing deeper is one ENTER."""

    def __init__(self, client: DuneHDClient) -> None:
        self._client = client
        self._lock = asyncio.Lock()
        self._path: list[str] | None = None  # path of the screen we last showed
        self._sig: Signature | None = None

    def _forget(self) -> None:
        self._path = None
        self._sig = None

    async def _wait_change(self, before: Signature) -> dict[str, Any]:
        loop = asyncio.get_running_loop()
        start = loop.time()
        state: dict[str, Any] = {}
        while loop.time() - start < CHANGE_TIMEOUT:
            await asyncio.sleep(POLL_INTERVAL)
            state = await self._client.ui_state()
            sig = _signature(state)
            if sig == before:
                continue
            # A folder may first appear empty while it is still loading
            if sig[2] == "navigator" and not sig[4] and loop.time() - start < CHANGE_TIMEOUT / 2:
                continue
            return state
        _LOGGER.debug("Dune HD UI did not change within %ss", CHANGE_TIMEOUT)
        return state or await self._client.ui_state()

    async def _settle(self) -> dict[str, Any]:
        loop = asyncio.get_running_loop()
        start = loop.time()
        state = await self._client.ui_state()
        while loop.time() - start < SETTLE_TIMEOUT:
            await asyncio.sleep(POLL_INTERVAL)
            new = await self._client.ui_state()
            if _signature(new) == _signature(state) and screen_of(new).get("items"):
                return new
            state = new
        return state

    async def _enter_chain(
        self, ids: list[str], base: list[str], state: dict[str, Any]
    ) -> dict[str, Any]:
        path = list(base)
        for item_id in ids:
            before = _signature(state)
            await self._client.ui_action_enter(item_id)
            state = await self._wait_change(before)
            path.append(item_id)
            if not is_navigator(state):
                # Item launched an app / started playback: we are out of the menu
                self._forget()
                return state
        self._path = path
        self._sig = _signature(state)
        return state

    async def _show_unlocked(self, path: list[str]) -> dict[str, Any]:
        state = await self._client.ui_state()
        if self._path is not None and _signature(state) == self._sig:
            if path == self._path:
                return state
            if path[: len(self._path)] == self._path:
                # Going deeper from where the TV already is
                return await self._enter_chain(path[len(self._path):], self._path, state)
        # Otherwise start again from the main screen
        await self._client.ui_action_return(-1)
        state = await self._settle()
        return await self._enter_chain(path, [], state)

    async def show(self, path: list[str]) -> dict[str, Any]:
        """Make the TV show the folder at `path`; return the ui_state result."""
        async with self._lock:
            return await self._show_unlocked(path)

    async def activate(self, path: list[str]) -> dict[str, Any]:
        """Open the item at `path` (launch app, play file, open folder)."""
        if not path:
            raise ValueError("Empty path")
        async with self._lock:
            state = await self._show_unlocked(path[:-1])
            return await self._enter_chain([path[-1]], path[:-1], state)
