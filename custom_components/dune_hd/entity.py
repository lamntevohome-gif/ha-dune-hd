"""Base entity for Dune HD."""
from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Any

from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .api import DuneHDError
from .const import DOMAIN, OFF_PLAYER_STATES
from .coordinator import DuneHDCoordinator


class DuneHDEntity(CoordinatorEntity[DuneHDCoordinator]):
    """Common Dune HD entity."""

    _attr_has_entity_name = True

    def __init__(self, coordinator: DuneHDCoordinator, key: str) -> None:
        super().__init__(coordinator)
        entry = coordinator.config_entry
        device_id = entry.unique_id or entry.entry_id
        details = coordinator.device_details
        self._client = coordinator.client
        self._attr_unique_id = f"{device_id}_{key}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, device_id)},
            name=entry.title,
            manufacturer="Dune HD",
            model=details.get("product_name"),
            model_id=details.get("product_id"),
            sw_version=details.get("firmware_version"),
            serial_number=details.get("commercial_serial_number"),
        )

    @property
    def _status(self) -> dict[str, str]:
        return self.coordinator.data or {}

    @property
    def _player_on(self) -> bool:
        return self._status.get("player_state", "standby") not in OFF_PLAYER_STATES

    async def _async_run(
        self, func: Callable[..., Awaitable[dict[str, str]]], *args: Any, **kwargs: Any
    ) -> dict[str, str]:
        """Run a client call; every response carries the full status, use it."""
        try:
            result = await func(*args, **kwargs)
        except DuneHDError as err:
            raise HomeAssistantError(f"Dune HD: {err}") from err
        if result.get("player_state"):
            self.coordinator.remember(result)
            self.coordinator.async_set_updated_data(result)
        return result
