# Dokey cho macOS

Ứng dụng bộ gõ tiếng Việt trên thanh menu, viết bằng Swift + AppKit, chạy trên lõi [Dokey Core](../../README.md).

- macOS 10.13 trở lên trên Intel; macOS 11 trở lên trên Apple Silicon (một tệp Universal).
- Giao diện dựng hoàn toàn bằng mã, không dùng storyboard hay xib.
- Gọi engine qua API C `include/dokey/dokey.h`.

## Build

Chỉ cần **Command Line Tools** (`xcode-select --install`), không cần Xcode:

```bash
apps/macos/build.sh          # -> apps/macos/build/Dokey.app
apps/macos/build.sh --dmg    # thêm apps/macos/build/Dokey-0.2.0.dmg
```

Script biên dịch Dokey Core bằng `clang++` cho từng kiến trúc, biên dịch app bằng `swiftc`, gộp bằng `lipo`, vẽ biểu tượng, nhúng thư viện Swift cho macOS 10.13 – 10.14.3, ký ad-hoc, rồi chạy `Dokey --self-test`.

Biến môi trường: `VERSION` (mặc định `0.2.0`), `ARCHS` (mặc định `"x86_64 arm64"`).

## Cài đặt và cấp quyền

1. Kéo `Dokey.app` vào thư mục Applications rồi mở.
   Bản ký ad-hoc chưa được Apple công chứng (notarize). Lần đầu mở: chuột phải vào Dokey.app, chọn **Open**, rồi chọn **Open** lần nữa. Hoặc chạy `xattr -dr com.apple.quarantine /Applications/Dokey.app`.
2. Dokey mở cửa sổ hướng dẫn cấp quyền **Trợ năng** (System Settings › Privacy & Security › Accessibility). Bật Dokey trong danh sách; Dokey tự nhận quyền, không cần mở lại.
3. Sau khi cập nhật bản mới mà không gõ được dấu: xoá Dokey khỏi danh sách Trợ năng rồi thêm lại. Mỗi bản ký ad-hoc có chữ ký khác nhau nên macOS coi là ứng dụng mới.

## Menu

| Mục | Tác dụng |
|---|---|
| Gõ tiếng Việt | Bật/tắt. Biểu tượng: **V** (nền đặc) = tiếng Việt, **E** (viền) = tiếng Anh |
| Kiểu gõ | Telex hoặc VNI |
| Bảng mã | Unicode dựng sẵn hoặc Unicode tổ hợp |
| Kiểm tra chính tả | Giữ nguyên từ không phải tiếng Việt (`windows`, `chrome`) |
| Đặt dấu kiểu mới | hoà, khoẻ, thuý (tắt: hòa, khỏe, thúy) |
| Phím chuyển Anh/Việt | ⌃⇧ (bấm rồi thả, mặc định), ⌥Z, ⌃Space, ⌘⇧Space |
| Nhớ chế độ theo ứng dụng | Mỗi ứng dụng giữ chế độ Anh/Việt riêng |
| Tương thích máy chậm | Tăng khoảng nghỉ giữa các phím gửi đi |
| Khởi động cùng macOS | SMAppService trên macOS 13+, LaunchAgent trên bản cũ hơn |

## Cách hoạt động

```
phím ─▶ CGEventTap (session, luồng riêng) ─▶ dokey_key()
                                         ├─ 0: để phím gốc đi qua
                                         └─ 1: nuốt phím gốc, gửi N Backspace + chữ mới (UTF-16)
```

- **Luồng riêng cho event tap.** Tap chạy trên run loop của một luồng riêng, nên menu hay cửa sổ đang mở không làm chậm việc gõ.
- **Thứ tự sự kiện.** Phím tổng hợp được chèn bằng `CGEventTapPostEvent` ngay sau tap. Chúng luôn đến ứng dụng trước phím tiếp theo của người dùng.
- **Đánh dấu sự kiện của chính mình.** Mọi phím Dokey gửi đi mang giá trị `eventSourceUserData` riêng, nên tap không xử lý lại. Nguồn sự kiện ở trạng thái riêng (`privateState`) và cờ phím bị xoá, nên phím Shift đang giữ không biến Backspace thành Shift-Backspace.
- **Ba nhóm ứng dụng.** Dokey nhớ ứng dụng đang ở trước mỗi khi đổi ứng dụng, rồi phân loại theo bundle id. Với ứng dụng lạ, Dokey xem thư mục `Contents/Frameworks` có `Electron Framework.framework` hay framework Chromium không.

  | Nhóm | Ví dụ | Cách gửi phím |
  |---|---|---|
  | Trình duyệt | Chrome, Edge, Brave, Cốc Cốc, Arc, Firefox | 1 ký tự mỗi sự kiện, nghỉ 1,5 ms mỗi phím và 4 ms sau loạt Backspace |
  | Electron/IDE | Claude, VS Code, Cursor, Slack, Zalo, JetBrains | 1 ký tự mỗi sự kiện, nghỉ 1 ms và 3 ms |
  | Thường | TextEdit, Notes, Pages… | tối đa 20 ký tự mỗi sự kiện, không nghỉ |

  Bật **Tương thích máy chậm** để nhân đôi các khoảng nghỉ.
- **Từ mới.** Dokey gọi `dokey_reset` khi: click chuột, phím mũi tên/Home/End/Page, Esc, Forward Delete, phím tắt có ⌘ ⌃ ⌥, đổi ứng dụng, và khi giữ phím (autorepeat).
- **Backspace** đi qua nguyên vẹn; engine chỉ cập nhật từ đang gõ (`dokey_backspace`).
- **Enter và Tab** kết thúc từ: nếu engine cần sửa từ (ví dụ `thuowr` → thuở), Dokey sửa trước rồi mới gửi lại phím Enter/Tab.
- **Watchdog.** Khi macOS tắt tap (`kCGEventTapDisabledByTimeout`), Dokey bật lại ngay trong callback. Một bộ đếm giờ 2 giây kiểm tra thêm, và tự tạo tap ngay khi người dùng vừa cấp quyền.

## Mã nguồn

| Tệp | Nội dung |
|---|---|
| `Sources/KeyboardTap.swift` | Event tap, xử lý phím, gửi phím tổng hợp |
| `Sources/Engine.swift` | Lớp bọc API C, an toàn khi dùng từ nhiều luồng |
| `Sources/AppClassifier.swift` | Phân loại trình duyệt / Electron / thường, khoảng nghỉ |
| `Sources/AppDelegate.swift` | Thanh menu, chế độ theo ứng dụng, watchdog |
| `Sources/Settings.swift` | Tuỳ chọn người dùng, phím chuyển |
| `Sources/PermissionWindow.swift` | Cửa sổ hướng dẫn cấp quyền Trợ năng |
| `Sources/LoginItem.swift` | Khởi động cùng macOS |
| `Sources/StatusIcon.swift` | Biểu tượng V/E trên thanh menu, vẽ bằng mã |
| `Sources/SelfTest.swift` | `Dokey --self-test`, chạy trong CI |
| `tools/make_icon.swift` | Vẽ biểu tượng ứng dụng |

© 2026 Do Huy Toan. All rights reserved.
