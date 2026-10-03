"""Constants for the Dune HD IP Control integration."""
from __future__ import annotations

from typing import Final

DOMAIN: Final = "dune_hd"

DEFAULT_NAME: Final = "Dune HD"
DEFAULT_PORT: Final = 80  # Google-certified ATV models use 11080
SCAN_INTERVAL_SECONDS: Final = 5
HTTP_TIMEOUT: Final = 30  # seconds, client side
PLAYER_COMMAND_TIMEOUT: Final = 10  # seconds, "timeout" param sent to the player

# Pseudo state used when the player cannot be reached (fully powered off / offline)
STATE_UNREACHABLE: Final = "unreachable"

# player_state values from the IP Control protocol
PLAYER_STATE_STANDBY: Final = "standby"
PLAYER_STATE_NAVIGATOR: Final = "navigator"
PLAYER_STATE_BLACK_SCREEN: Final = "black_screen"
PLAYBACK_PLAYER_STATES: Final = frozenset(
    {"file_playback", "dvd_playback", "bluray_playback"}
)
OFF_PLAYER_STATES: Final = frozenset({PLAYER_STATE_STANDBY, STATE_UNREACHABLE})

# Minimum protocol versions for optional features
PROTOCOL_VOLUME: Final = 2  # volume / mute via set_playback_state
PROTOCOL_LAUNCH_MEDIA_URL: Final = 3  # launch_media_url (auto-detect file/DVD/BD)
PROTOCOL_OPEN_PATH: Final = 4  # open_path
PROTOCOL_PLAYBACK_ACTION: Final = 5  # playback_action stop/prev/next, JSON, captions

# Remote control IR codes (NEC, bytes reversed) as listed in the IP Control docs.
# More codes: http://dune-hd.com/support/rc  (reverse byte order, e.g. 00 BF 18 E7 -> E718BF00)
IR_CODES: Final[dict[str, str]] = {
    "up": "EA15BF00",
    "down": "E916BF00",
    "left": "E817BF00",
    "right": "E718BF00",
    "enter": "EB14BF00",
    "return": "FB04BF00",
    "top_menu": "AE51BF00",
    "popup_menu": "F807BF00",
    "power": "BC43BF00",
    "mute": "B946BF00",
    "volume_up": "AD52BF00",
    "volume_down": "AC53BF00",
    "audio": "BB44BF00",
    "7": "EE11BF00",
}

# Commands accepted by remote.send_command that map to dedicated API calls
API_SCREEN_COMMANDS: Final = frozenset({"main_screen", "black_screen", "standby"})
API_PLAYBACK_ACTIONS: Final = frozenset({"stop", "prev", "next"})

SERVICE_OPEN_PATH: Final = "open_path"
SERVICE_BLACK_SCREEN: Final = "black_screen"
ATTR_URL: Final = "url"
