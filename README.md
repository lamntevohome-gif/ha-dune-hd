# Dune HD IP Control cho Home Assistant

Custom integration (cài qua HACS) để điều khiển đầu phát **Dune HD** qua giao thức
**IP Control** (`http://<ip>/cgi-bin/do?cmd=...`).

## Tính năng

| Entity / dịch vụ | Chức năng | Lệnh IP Control |
|---|---|---|
| `media_player` bật / tắt | Thoát standby về menu chính / vào standby | `main_screen` / `standby` |
| Play / Pause / Seek | Tiếp tục, tạm dừng, tua tới giây | `set_playback_state` (`speed`, `position`) |
| Stop | Dừng phát | `playback_action=stop` (protocol 5+), nếu cũ hơn dùng `main_screen` |
| Next / Previous | Bài/tập kế tiếp, trước | `playback_action=next/prev` (protocol 5+) |
| Âm lượng | Đặt mức, tắt tiếng; tăng/giảm bằng mã IR V+/V- | `set_playback_state` (`volume`, `mute`), `ir_code` |
| `media_player.play_media` | Phát URL `nfs://`, `smb://`, `http://`, `storage_name://`, hoặc file từ Media của HA | `launch_media_url` (protocol 3+) / `start_file_playback` |
| Thông tin đang phát | Trạng thái, thời lượng, vị trí, tiêu đề, ảnh bìa | `status` (poll 5 giây) |
| `remote.send_command` | Giả lập phím remote | `ir_code` |
| `dune_hd.open_path` | Mở menu / ứng dụng / thư mục | `open_path` (protocol 4+) |
| `dune_hd.black_screen` | Dừng phát, chuyển màn hình đen | `black_screen` |

Tính năng phụ thuộc phiên bản protocol của firmware (đọc từ `protocol_version`);
next/previous chỉ hiện khi đầu phát hỗ trợ protocol 5+.

## Cài đặt qua HACS (custom repository)

1. Đẩy toàn bộ thư mục này lên một repo GitHub **public**, ví dụ `ha-dune-hd`.
   Sửa `lamntevohome-gif` trong `custom_components/dune_hd/manifest.json`.
2. Tạo một **Release** trên GitHub (ví dụ tag `v0.1.0`) để HACS hiển thị phiên bản.
3. Trong Home Assistant: **HACS → ⋮ (góc phải) → Custom repositories**
   - Repository: `https://github.com/<user>/ha-dune-hd`
   - Type: **Integration** → **Add**
4. Tìm "Dune HD IP Control" trong HACS → **Download** → **khởi động lại Home Assistant**.
5. **Settings → Devices & services → Add integration → Dune HD IP Control**,
   nhập IP (xem trên đầu phát ở *Setup → Information*), cổng `80`
   (các mẫu ATV như BOXY, Homatics Box R 4K Plus, Premier 4K Pro dùng `11080`
   và cần cài app Dune HD Media Center).

Cài thủ công không qua HACS: chép `custom_components/dune_hd` vào
`/config/custom_components/` rồi khởi động lại.

## Ví dụ sử dụng

```yaml
# Điều hướng menu bằng phím remote
action: remote.send_command
target:
  entity_id: remote.dune_hd_remote
data:
  command: [down, down, enter]
  delay_secs: 0.2
```

Lệnh được chấp nhận trong `remote.send_command`:

- Tên phím: `up`, `down`, `left`, `right`, `enter`, `return`, `top_menu`,
  `popup_menu`, `power`, `mute`, `volume_up`, `volume_down`, `audio`, `7`
- Mã IR thô 8 ký tự hex, ví dụ `E718BF00` (lấy ở http://dune-hd.com/support/rc,
  **đảo thứ tự byte**: `00 BF 18 E7` → `E718BF00`)
- Lệnh trạng thái: `main_screen`, `black_screen`, `standby`
- Điều khiển phát (protocol 5+): `stop`, `prev`, `next`

```yaml
# Phát phim từ NAS (NFS)
action: media_player.play_media
target:
  entity_id: media_player.dune_hd
data:
  media_content_type: video
  media_content_id: "nfs://192.168.1.10:/VideoStorage:/Movies/film.mkv"
```

```yaml
# Mở mục Ứng dụng
action: dune_hd.open_path
target:
  entity_id: media_player.dune_hd
data:
  url: "root://applications"
```

```yaml
# Bật chế độ REPEAT (chuỗi phím theo tài liệu Dune)
action: remote.send_command
target:
  entity_id: remote.dune_hd_remote
data:
  command: [audio, popup_menu, up, enter, "7", popup_menu, popup_menu]
  delay_secs: 0.1
```

## Gợi ý khi dùng như thiết bị phát nhúng

Đặt *Setup → Misc → Power Management → Power on* = *Black screen* để Dune không
hiện menu khi khởi động; dùng `dune_hd.black_screen` để dừng phát.

## Ghi chú

- Khi đầu phát tắt hẳn hoặc mất mạng, entity hiển thị **off** (không phải
  unavailable). Lệnh bật chỉ hoạt động khi đầu phát đang ở standby và còn mạng.
- Domain là `dune_hd`, không trùng với integration `dunehd` có sẵn trong Home Assistant.
- Chưa bao gồm các lệnh của plugin "remote-control" (HTTP API bổ sung).
