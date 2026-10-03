"""Media player entity for Dune HD."""
from __future__ import annotations

from typing import Any

import voluptuous as vol

from homeassistant.components import media_source
from homeassistant.components.media_player import (
    BrowseError,
    BrowseMedia,
    MediaClass,
    MediaPlayerEntity,
    MediaPlayerEntityFeature,
    MediaPlayerState,
    MediaType,
    async_process_play_media_url,
)
from homeassistant.core import HomeAssistant, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import config_validation as cv, entity_platform
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.util import dt as dt_util

from .api import DuneHDError
from .const import (
    ATTR_URL,
    BROWSE_ROOT_ID,
    IR_CODES,
    OFF_PLAYER_STATES,
    PLAYBACK_PLAYER_STATES,
    PLAYER_STATE_BLACK_SCREEN,
    PROTOCOL_LAUNCH_MEDIA_URL,
    PROTOCOL_OPEN_PATH,
    PROTOCOL_PLAYBACK_ACTION,
    PROTOCOL_UI_STATE,
    SERVICE_BLACK_SCREEN,
    SERVICE_OPEN_PATH,
    UI_CONTENT_TYPE,
    UI_PREFIX,
)
from .coordinator import DuneHDConfigEntry, DuneHDCoordinator
from .entity import DuneHDEntity
from .ui_browser import decode_path, encode_path, is_navigator, screen_of

BASE_FEATURES = (
    MediaPlayerEntityFeature.TURN_ON
    | MediaPlayerEntityFeature.TURN_OFF
    | MediaPlayerEntityFeature.PLAY
    | MediaPlayerEntityFeature.PAUSE
    | MediaPlayerEntityFeature.STOP
    | MediaPlayerEntityFeature.SEEK
    | MediaPlayerEntityFeature.VOLUME_SET
    | MediaPlayerEntityFeature.VOLUME_STEP
    | MediaPlayerEntityFeature.VOLUME_MUTE
    | MediaPlayerEntityFeature.PLAY_MEDIA
    | MediaPlayerEntityFeature.BROWSE_MEDIA
)


def _int(value: str | None) -> int | None:
    try:
        return int(value) if value not in (None, "") else None
    except ValueError:
        return None


async def async_setup_entry(
    hass: HomeAssistant,
    entry: DuneHDConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    async_add_entities([DuneHDMediaPlayer(entry.runtime_data)])

    platform = entity_platform.async_get_current_platform()
    platform.async_register_entity_service(
        SERVICE_OPEN_PATH, {vol.Required(ATTR_URL): cv.string}, "async_open_path"
    )
    platform.async_register_entity_service(
        SERVICE_BLACK_SCREEN, {}, "async_black_screen"
    )


class DuneHDMediaPlayer(DuneHDEntity, MediaPlayerEntity):
    """Dune HD as a media player."""

    _attr_name = None
    _attr_media_image_remotely_accessible = False

    def __init__(self, coordinator: DuneHDCoordinator) -> None:
        super().__init__(coordinator, "media_player")
        self._attr_media_position_updated_at = dt_util.utcnow()

    @callback
    def _handle_coordinator_update(self) -> None:
        self._attr_media_position_updated_at = dt_util.utcnow()
        super()._handle_coordinator_update()

    # ---- State ---------------------------------------------------------------

    @property
    def supported_features(self) -> MediaPlayerEntityFeature:
        features = BASE_FEATURES
        if self.coordinator.protocol_version >= PROTOCOL_PLAYBACK_ACTION:
            features |= (
                MediaPlayerEntityFeature.NEXT_TRACK
                | MediaPlayerEntityFeature.PREVIOUS_TRACK
            )
        return features

    @property
    def state(self) -> MediaPlayerState:
        s = self._status
        player_state = s.get("player_state")
        if player_state is None or player_state in OFF_PLAYER_STATES:
            return MediaPlayerState.OFF
        if player_state in PLAYBACK_PLAYER_STATES:
            if s.get("playback_is_buffering") == "1":
                return MediaPlayerState.BUFFERING
            if _int(s.get("playback_speed")) == 0:
                return MediaPlayerState.PAUSED
            return MediaPlayerState.PLAYING
        if player_state == PLAYER_STATE_BLACK_SCREEN:
            return MediaPlayerState.IDLE
        return MediaPlayerState.ON  # navigator (menu)

    @property
    def _is_playing_media(self) -> bool:
        return self._status.get("player_state") in PLAYBACK_PLAYER_STATES

    @property
    def volume_level(self) -> float | None:
        vol_ = _int(self._status.get("playback_volume"))
        return None if vol_ is None else max(0, min(vol_, 100)) / 100

    @property
    def is_volume_muted(self) -> bool | None:
        mute = self._status.get("playback_mute")
        return None if mute is None else mute == "1"

    @property
    def media_content_type(self) -> MediaType | None:
        if not self._is_playing_media:
            return None
        return MediaType.MUSIC if self._status.get("is_video") == "0" else MediaType.VIDEO

    @property
    def media_content_id(self) -> str | None:
        return self._status.get("playback_url") if self._is_playing_media else None

    @property
    def media_duration(self) -> int | None:
        dur = _int(self._status.get("playback_duration"))
        return dur if self._is_playing_media and dur and dur > 0 else None

    @property
    def media_position(self) -> int | None:
        pos = _int(self._status.get("playback_position"))
        return pos if self._is_playing_media and pos is not None and pos >= 0 else None

    @property
    def media_title(self) -> str | None:
        if not self._is_playing_media:
            return None
        return self._status.get("playback_caption") or None

    @property
    def media_artist(self) -> str | None:
        if not self._is_playing_media:
            return None
        return self._status.get("playback_extra_caption") or None

    @property
    def media_image_url(self) -> str | None:
        pic = self._status.get("playback_picture") if self._is_playing_media else None
        if not pic:
            return None
        if pic.startswith(("http://", "https://")):
            return pic
        return self._client.get_file_url(pic)

    # ---- Commands --------------------------------------------------------------

    async def async_turn_on(self) -> None:
        await self._async_run(self._client.main_screen)

    async def async_turn_off(self) -> None:
        await self._async_run(self._client.standby)

    async def async_media_play(self) -> None:
        await self._async_run(self._client.set_playback_state, speed=256)

    async def async_media_pause(self) -> None:
        await self._async_run(self._client.set_playback_state, speed=0)

    async def async_media_stop(self) -> None:
        if self.coordinator.protocol_version >= PROTOCOL_PLAYBACK_ACTION:
            await self._async_run(self._client.playback_action, "stop")
        else:
            await self._async_run(self._client.main_screen)

    async def async_media_next_track(self) -> None:
        await self._async_run(self._client.playback_action, "next")

    async def async_media_previous_track(self) -> None:
        await self._async_run(self._client.playback_action, "prev")

    async def async_media_seek(self, position: float) -> None:
        await self._async_run(self._client.set_playback_state, position=int(position))

    async def async_set_volume_level(self, volume: float) -> None:
        await self._async_run(
            self._client.set_playback_state, volume=int(round(volume * 100))
        )

    async def async_volume_up(self) -> None:
        await self._async_run(self._client.ir_code, IR_CODES["volume_up"])

    async def async_volume_down(self) -> None:
        await self._async_run(self._client.ir_code, IR_CODES["volume_down"])

    async def async_mute_volume(self, mute: bool) -> None:
        await self._async_run(self._client.set_playback_state, mute=1 if mute else 0)

    async def async_play_media(
        self, media_type: MediaType | str, media_id: str, **kwargs: Any
    ) -> None:
        """Play a URL (nfs://, smb://, http://, storage_name://...), a media_source
        item, or an item of the Dune on-screen menu (dune_ui://...)."""
        if media_id.startswith(UI_PREFIX):
            try:
                await self.coordinator.ui.activate(decode_path(media_id))
            except (DuneHDError, ValueError) as err:
                raise HomeAssistantError(f"Dune HD: {err}") from err
            await self.coordinator.async_request_refresh()
            return
        if media_source.is_media_source_id(media_id):
            item = await media_source.async_resolve_media(
                self.hass, media_id, self.entity_id
            )
            media_id = item.url
        media_id = async_process_play_media_url(self.hass, media_id)

        if self.coordinator.protocol_version >= PROTOCOL_LAUNCH_MEDIA_URL:
            await self._async_run(self._client.launch_media_url, media_id)
        else:
            await self._async_run(self._client.start_file_playback, media_id)

    async def async_browse_media(
        self,
        media_content_type: MediaType | str | None = None,
        media_content_id: str | None = None,
    ) -> BrowseMedia:
        if media_content_id in (None, BROWSE_ROOT_ID):
            return self._browse_root()
        if media_content_id.startswith(UI_PREFIX):
            return await self._browse_ui(decode_path(media_content_id))
        return await media_source.async_browse_media(
            self.hass,
            media_content_id,
            content_filter=lambda item: item.media_content_type.startswith(
                ("video/", "audio/", "image/")
            ),
        )

    def _browse_root(self) -> BrowseMedia:
        children: list[BrowseMedia] = []
        if self.coordinator.protocol_version >= PROTOCOL_UI_STATE:
            children.append(
                BrowseMedia(
                    media_class=MediaClass.DIRECTORY,
                    media_content_id=UI_PREFIX,
                    media_content_type=UI_CONTENT_TYPE,
                    title="Menu Dune HD",
                    can_play=False,
                    can_expand=True,
                )
            )
        children.append(
            BrowseMedia(
                media_class=MediaClass.DIRECTORY,
                media_content_id="media-source://",
                media_content_type="",
                title="Media (Home Assistant)",
                can_play=False,
                can_expand=True,
            )
        )
        return BrowseMedia(
            media_class=MediaClass.DIRECTORY,
            media_content_id=BROWSE_ROOT_ID,
            media_content_type="",
            title=self.coordinator.config_entry.title,
            can_play=False,
            can_expand=True,
            children=children,
            children_media_class=MediaClass.DIRECTORY,
        )

    async def _browse_ui(self, path: list[str]) -> BrowseMedia:
        """Show the Dune menu screen at `path` (this also moves the TV menu)."""
        try:
            state = await self.coordinator.ui.show(path)
        except DuneHDError as err:
            raise BrowseError(f"Dune HD: {err}") from err

        content_id = encode_path(path)
        if not is_navigator(state):
            # The item launched an app or started playback
            await self.coordinator.async_request_refresh()
            return BrowseMedia(
                media_class=MediaClass.APP,
                media_content_id=content_id,
                media_content_type=UI_CONTENT_TYPE,
                title="Đã mở trên Dune HD",
                can_play=False,
                can_expand=True,
                children=[],
            )

        screen = screen_of(state)
        children: list[BrowseMedia] = []
        for item in screen.get("items") or []:
            item_id = item.get("id")
            if not item_id:
                continue
            child_id = encode_path([*path, item_id])
            icon = item.get("icon")
            children.append(
                BrowseMedia(
                    media_class=MediaClass.DIRECTORY,
                    media_content_id=child_id,
                    media_content_type=UI_CONTENT_TYPE,
                    title=item.get("caption") or item_id,
                    can_play=True,  # play button = open on the TV
                    can_expand=True,  # click = browse into it
                    thumbnail=(
                        self.get_browse_image_url(UI_CONTENT_TYPE, child_id, icon)
                        if icon
                        else None
                    ),
                )
            )

        title = " / ".join(screen.get("navigator_path") or []) or "Menu Dune HD"
        total = screen.get("items_total_count")
        if isinstance(total, int) and total > len(children):
            title += f" ({len(children)}/{total})"
        return BrowseMedia(
            media_class=MediaClass.DIRECTORY,
            media_content_id=content_id,
            media_content_type=UI_CONTENT_TYPE,
            title=title,
            can_play=False,
            can_expand=True,
            children=children,
            children_media_class=MediaClass.DIRECTORY,
        )

    async def async_get_browse_image(
        self,
        media_content_type: MediaType | str,
        media_content_id: str,
        media_image_id: str | None = None,
    ) -> tuple[bytes | None, str | None]:
        """Serve Dune menu icons through Home Assistant."""
        if not media_image_id:
            return None, None
        try:
            return await self._client.get_file(media_image_id)
        except DuneHDError:
            return None, None

    # ---- Entity services -------------------------------------------------------

    async def async_open_path(self, url: str) -> None:
        if self.coordinator.protocol_version < PROTOCOL_OPEN_PATH:
            raise HomeAssistantError("open_path requires IP Control protocol 4+")
        await self._async_run(self._client.open_path, url)

    async def async_black_screen(self) -> None:
        await self._async_run(self._client.black_screen)
