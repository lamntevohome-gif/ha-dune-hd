"""Config flow for Dune HD."""
from __future__ import annotations

import logging
from typing import Any

import voluptuous as vol

from homeassistant.config_entries import ConfigFlow, ConfigFlowResult
from homeassistant.const import CONF_HOST, CONF_NAME, CONF_PORT
from homeassistant.helpers.aiohttp_client import async_get_clientsession

from .api import DuneHDClient, DuneHDConnectionError, DuneHDError
from .const import DEFAULT_NAME, DEFAULT_PORT, DOMAIN

_LOGGER = logging.getLogger(__name__)

STEP_USER_SCHEMA = vol.Schema(
    {
        vol.Required(CONF_HOST): str,
        vol.Required(CONF_PORT, default=DEFAULT_PORT): vol.All(
            vol.Coerce(int), vol.Range(min=1, max=65535)
        ),
        vol.Optional(CONF_NAME): str,
    }
)


class DuneHDConfigFlow(ConfigFlow, domain=DOMAIN):
    """Handle a config flow for Dune HD."""

    VERSION = 1

    async def async_step_user(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        errors: dict[str, str] = {}

        if user_input is not None:
            host = user_input[CONF_HOST].strip()
            port = user_input[CONF_PORT]
            client = DuneHDClient(async_get_clientsession(self.hass), host, port)
            try:
                status = await client.status()
            except DuneHDConnectionError:
                errors["base"] = "cannot_connect"
            except DuneHDError:
                errors["base"] = "invalid_response"
            except Exception:  # noqa: BLE001
                _LOGGER.exception("Unexpected error talking to Dune HD")
                errors["base"] = "unknown"
            else:
                if "player_state" not in status:
                    errors["base"] = "invalid_response"
                else:
                    unique_id = status.get("serial_number") or f"{host}:{port}"
                    await self.async_set_unique_id(unique_id)
                    self._abort_if_unique_id_configured(
                        updates={CONF_HOST: host, CONF_PORT: port}
                    )
                    title = (
                        user_input.get(CONF_NAME)
                        or status.get("product_name")
                        or DEFAULT_NAME
                    )
                    return self.async_create_entry(
                        title=title, data={CONF_HOST: host, CONF_PORT: port}
                    )

        return self.async_show_form(
            step_id="user",
            data_schema=self.add_suggested_values_to_schema(
                STEP_USER_SCHEMA, user_input
            ),
            errors=errors,
        )
