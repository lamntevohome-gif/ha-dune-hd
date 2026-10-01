"""Async client for the Dune HD IP Control protocol (cgi-bin/do)."""
from __future__ import annotations

import asyncio
import logging
from urllib.parse import quote
import xml.etree.ElementTree as ET

import aiohttp
from yarl import URL

from .const import DEFAULT_PORT, HTTP_TIMEOUT, PLAYER_COMMAND_TIMEOUT

_LOGGER = logging.getLogger(__name__)


class DuneHDError(Exception):
    """Base error for Dune HD."""


class DuneHDConnectionError(DuneHDError):
    """The player could not be reached."""


class DuneHDCommandError(DuneHDError):
    """The player answered command_status=failed."""

    def __init__(self, cmd: str, error_kind: str, description: str) -> None:
        super().__init__(f"'{cmd}' failed: {error_kind} {description}".strip())
        self.error_kind = error_kind


class DuneHDClient:
    """Minimal async client for Dune HD IP Control."""

    def __init__(
        self, session: aiohttp.ClientSession, host: str, port: int = DEFAULT_PORT
    ) -> None:
        self._session = session
        self.host = host
        self.port = port
        self.base_url = f"http://{host}:{port}"
        # Serialize commands so IR sequences arrive in order
        self._lock = asyncio.Lock()

    def _build_url(self, cmd: str, params: dict[str, object]) -> URL:
        query = {"cmd": cmd, **{k: v for k, v in params.items() if v is not None}}
        # Encode every value fully (spaces -> %20, not '+'), as the player expects
        qs = "&".join(f"{k}={quote(str(v), safe='')}" for k, v in query.items())
        return URL(f"{self.base_url}/cgi-bin/do?{qs}", encoded=True)

    async def command(self, cmd: str, **params: object) -> dict[str, str]:
        """Send a command and return the parsed <param> values."""
        url = self._build_url(cmd, params)
        async with self._lock:
            try:
                async with asyncio.timeout(HTTP_TIMEOUT):
                    async with self._session.get(url) as resp:
                        resp.raise_for_status()
                        text = await resp.text()
            except (aiohttp.ClientError, TimeoutError) as err:
                raise DuneHDConnectionError(
                    f"Cannot reach Dune HD at {self.host}:{self.port}: {err}"
                ) from err

        data = self._parse(text)
        status = data.get("command_status")
        if status == "failed":
            raise DuneHDCommandError(
                cmd, data.get("error_kind", "unknown"), data.get("error_description", "")
            )
        if status == "timeout":
            # Player keeps executing the command; next status poll will show the result
            _LOGGER.debug("Dune HD command '%s' returned timeout", cmd)
        return data

    @staticmethod
    def _parse(text: str) -> dict[str, str]:
        try:
            root = ET.fromstring(text.strip())
        except ET.ParseError as err:
            raise DuneHDError(f"Invalid response from player: {err}") from err
        return {
            name: param.get("value", "")
            for param in root.iter("param")
            if (name := param.get("name"))
        }

    # ---- Convenience wrappers -------------------------------------------------

    async def status(self) -> dict[str, str]:
        return await self.command("status")

    async def main_screen(self) -> dict[str, str]:
        return await self.command("main_screen")

    async def black_screen(self) -> dict[str, str]:
        return await self.command("black_screen")

    async def standby(self) -> dict[str, str]:
        return await self.command("standby")

    async def ir_code(self, code: str) -> dict[str, str]:
        return await self.command("ir_code", ir_code=code.upper())

    async def set_playback_state(self, **params: object) -> dict[str, str]:
        return await self.command("set_playback_state", **params)

    async def playback_action(self, action: str) -> dict[str, str]:
        """stop | prev | next (protocol 5+)."""
        return await self.command("playback_action", action=action)

    async def start_file_playback(self, media_url: str) -> dict[str, str]:
        return await self.command(
            "start_file_playback", media_url=media_url, timeout=PLAYER_COMMAND_TIMEOUT
        )

    async def launch_media_url(self, media_url: str) -> dict[str, str]:
        """Auto-detect file / DVD / Blu-ray (protocol 3+)."""
        return await self.command(
            "launch_media_url", media_url=media_url, timeout=PLAYER_COMMAND_TIMEOUT
        )

    async def open_path(self, url: str) -> dict[str, str]:
        """Open a GUI path, e.g. root://applications (protocol 4+)."""
        return await self.command("open_path", url=url)

    def get_file_url(self, path: str) -> str:
        """URL that returns a picture file from the player (protocol 5+)."""
        return str(self._build_url("get_file", {"path": path}))
