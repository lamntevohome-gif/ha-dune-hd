# EvoKNX

Phần mềm thiết kế và điều khiển giao diện nhà thông minh KNX của Evohome.

## Cấu trúc

```
apps/evoknx_app/     App điều khiển (Flutter, Android; iOS sau)
apps/evoknx_editor/   Ứng dụng Editor cho Windows (Flutter)
packages/evoknx_ui/   Giao diện dùng chung: thẻ, biểu tượng MDI, font Inter
packages/knx_core/    Thư viện KNX: KNXnet/IP tunneling, cEMI, DPT (Dart thuần, dùng chung với App mobile)
packages/knx_config/  File dự án .evoknx, nâng cấp phiên bản, nhập ETS (.knxproj, CSV, XML)
.github/workflows/    Tự động build bản Windows
```

## Lấy bản cài đặt Windows

1. Mỗi lần đưa code lên nhánh `main`, GitHub tự build (tab **Actions**).
2. Mở lần chạy mới nhất có dấu ✓ xanh, kéo xuống mục **Artifacts**, tải **EvoKNX-Editor-Windows**.
3. Giải nén, chạy `EvoKNX-Editor/evoknx_editor.exe`. Không cần cài đặt thêm.

## Chạy trên máy lập trình

```
cd apps/evoknx_editor
flutter config --enable-windows-desktop
flutter create --platforms=windows --project-name evoknx_editor --org vn.evohome .
flutter run -d windows
```

## Kiểm tra thư viện

```
cd packages/knx_core && dart run tool/selftest.dart
cd packages/knx_config && dart run tool/selftest.dart
```
