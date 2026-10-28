# Dokey cho Windows

> ⚠️ **Chưa được thử trên máy Windows thật.** Ứng dụng được viết trên macOS và chỉ được build, chạy unit test, self-test và thử cài/gỡ trên máy ảo GitHub Actions (`windows-2022`). Hãy thử kỹ trước khi dùng hằng ngày và báo lỗi tại Issues.

Bộ gõ tiếng Việt cho Windows 10/11 (x86, x64, ARM64), viết bằng C++ Win32, dùng lõi [Dokey Core](../../README.md) qua C API `include/dokey/dokey.h`.

## Cài đặt

Tải `Dokey-<phiên bản>-Windows-Setup.exe` ở trang [Releases](https://github.com/dhtoan/Dokey/releases) rồi chạy. Bộ cài:
- tự chọn bản x86, x64 hoặc ARM64 hợp với máy;
- mặc định cài cho người dùng hiện tại (không cần quyền quản trị), có thể chọn cài cho mọi người dùng;
- tạo lối tắt trong Start menu, tuỳ chọn khởi động cùng Windows;
- có trình gỡ cài đặt (Settings → Apps, hoặc "Uninstall Dokey" trong Start menu).

Bộ cài chưa được ký số, nên Windows SmartScreen có thể cảnh báo: bấm **More info → Run anyway**.

## Sử dụng

- Biểu tượng **V** (đỏ) / **E** (xám) ở khay hệ thống: bấm chuột trái để chuyển Việt/Anh, chuột phải để mở menu.
- Phím tắt chuyển Việt/Anh: **Ctrl+Shift** (bấm rồi thả) hoặc **Alt+Z**, chọn trong menu.
- Menu: kiểu gõ Telex/VNI, kiểm tra chính tả, dấu kiểu mới (hoà, khoẻ) hay kiểu cũ (hòa, khỏe), khởi động cùng Windows.
- Cài đặt lưu ở `HKCU\Software\Dokey`.

## Cách hoạt động

| | |
|---|---|
| Bắt phím | `WH_KEYBOARD_LL` trên một luồng riêng. Hook chỉ chạy engine rồi xếp việc vào hàng đợi, không bao giờ chờ, để Windows không gỡ hook. |
| Gửi chữ | Khi `dokey_key` trả 1: xoá và chèn chữ (`KEYEVENTF_UNICODE`) bằng **một lần `SendInput`** trên luồng gửi. Khi trả 0: phím gốc đi qua. |
| Không nhảy chữ | Mỗi sự kiện Dokey gửi đều gắn `dwExtraInfo`. Từ lúc xếp việc tới lúc hook thấy sự kiện cuối của nó quay về, các phím người dùng gõ tiếp được xếp sau, nên không thể vượt lên trước chữ của Dokey. |
| Chrome, Edge, Electron | Nhận ra cửa sổ lớp `Chrome_WidgetWin_*` và nghỉ ngắn (mặc định 12 ms, `ChromiumPauseMs` trong registry) giữa phím xoá và chữ mới. |
| Đặt lại từ | Khi click chuột, đổi cửa sổ, phím mũi tên/Home/End/Delete/Esc, phím tắt Ctrl/Alt/Win. |
| Bộ gõ khác | Nếu bộ gõ Trung/Nhật/Hàn (hoặc Telex của Microsoft) đang bật, Dokey tạm đứng ngoài. Trạng thái được hỏi bằng `SendMessageTimeout` trên luồng giao diện và lưu tạm. |
| Bàn phím | Ký tự được lấy theo bố cục bàn phím của cửa sổ đang gõ (`ToUnicodeEx`), nên bố cục không phải Latin sẽ không bị biến đổi. |

Giới hạn đã biết:
- Không gõ được vào cửa sổ chạy quyền Administrator khi Dokey chạy quyền thường (Windows chặn, UIPI).
- Thanh địa chỉ Chrome có gợi ý tự hoàn thành có thể vẫn lệch; cần thử trên máy thật.

## Build

Cần Visual Studio 2022 (có công cụ ARM64 nếu build ARM64) và CMake 3.16+.

```bat
cmake -S apps/windows -B build/x64 -A x64
cmake --build build/x64 --config Release
ctest --test-dir build/x64 -C Release
```

Thay `-A x64` bằng `-A Win32` hoặc `-A ARM64` cho kiến trúc khác. Bộ cài: `iscc /DAppVersion=0.1.0 /DBinDir=<thư mục có x86\, x64\, arm64\> apps\windows\installer\Dokey.iss`.

CI ([`windows-app.yml`](../../.github/workflows/windows-app.yml)) build cả ba kiến trúc, chạy unit test, `Dokey.exe --self-test` (cài và gỡ hook), thử gõ vào Notepad, đóng gói bộ cài rồi thử cài/gỡ im lặng.

Biểu tượng ứng dụng được vẽ bằng [`tools/make_icon.py`](tools/make_icon.py); biểu tượng V/E ở khay được vẽ lúc chạy, đúng kích thước màn hình.

Copyright © 2026 Do Huy Toan.
