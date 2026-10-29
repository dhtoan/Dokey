<div align="center">

# Dokey

**Bộ gõ tiếng Việt thế hệ mới: nhanh, chính xác, đa nền tảng**

*The next-generation Vietnamese input method*

[![CI](https://github.com/dhtoan/Dokey/actions/workflows/ci.yml/badge.svg)](https://github.com/dhtoan/Dokey/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/dhtoan/Dokey?include_prereleases&label=release&color=0A84FF)](https://github.com/dhtoan/Dokey/releases)
![C++17](https://img.shields.io/badge/C%2B%2B-17-00599C?logo=cplusplus&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-AppKit-F05138?logo=swift&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Windows%20%7C%20Linux-6E6E73)
![Tests](https://img.shields.io/badge/tests-18%2C500%20passing-2EA44F)

[Giới thiệu](#giới-thiệu) •
[Tính năng](#tính-năng) •
[Ứng dụng macOS](#ứng-dụng-macos) •
[Ứng dụng Windows](#ứng-dụng-windows) •
[Bắt đầu nhanh](#bắt-đầu-nhanh) •
[Tích hợp](#tích-hợp-vào-ứng-dụng) •
[Kiến trúc](#kiến-trúc) •
[Lộ trình](#lộ-trình)

</div>

---

## Giới thiệu

**Dokey** là bộ gõ tiếng Việt được xây dựng lại từ đầu, hướng tới một mục tiêu: gõ đúng ngay lần đầu, ở mọi ứng dụng, trên mọi máy.

Repo này chứa:
- **Dokey Core**, bộ não xử lý tiếng Việt dùng chung cho các ứng dụng Dokey trên macOS, Windows, Linux và Android. Dokey Core là một thư viện C++17 độc lập, không phụ thuộc thư viện ngoài, có API C ổn định để tích hợp vào Swift, Win32 hay Kotlin.
- **Dokey cho macOS** (`apps/macos/`), ứng dụng bộ gõ trên thanh menu, viết bằng Swift + AppKit.
- **Dokey cho Windows** (`apps/windows/`), ứng dụng bộ gõ ở khay hệ thống, viết bằng C++ Win32, kèm bộ cài `Setup.exe`.

```console
$ dokey "Xin chaof cacs banj, Dokey gox tieengs Vieetj khoong nhayr chuwx."
Xin chào các bạn, Dokey gõ tiếng Việt không nhảy chữ.
```

## Tính năng

| | |
|---|---|
| ⚡ **Gửi phím tối thiểu** | Khi phím gõ không làm thay đổi chữ, Dokey để phím gốc đi qua. Sự kiện tổng hợp chỉ phát sinh khi thật sự phải sửa chữ, giảm tối đa tình trạng nhảy chữ trong Chrome, Edge và các ứng dụng Electron. |
| 🧠 **Không lệch trạng thái** | Mỗi phím, từ hiện tại được dựng lại từ đầu bằng một hàm thuần. Không có trạng thái tích luỹ, nên chữ trên màn hình và trong bộ gõ luôn khớp nhau. |
| 📖 **Hiểu chính tả tiếng Việt** | Từ điển 3.759 âm tiết, dựng từ hệ thống phụ âm đầu và vần chuẩn. Dấu chỉ được thêm khi kết quả là tiếng Việt hợp lệ. |
| 🔤 **Giữ nguyên tiếng Anh** | `windows`, `chrome`, `github`, `use`… không bị biến thành chữ có dấu. |
| ✍️ **Gõ dấu tự do** | Dấu mũ và dấu thanh gõ ở đâu trong từ cũng được: `tieengs`, `tienges`, `tiengse` đều ra **tiếng**. Gõ lặp phím dấu để huỷ (`aaa` → aa). |
| 🪄 **Tự hoàn thiện từ** | Sửa chữ khi kết thúc từ, ví dụ `thuowr` → **thuở**. |
| 🎯 **Đặt dấu chuẩn** | Hỗ trợ kiểu mới (hoà, khoẻ, thuý) và kiểu cũ (hòa, khỏe, thúy). |
| 🌐 **Đa nền tảng** | macOS (Intel và Apple Silicon), Windows (x64, ARM64), Linux. |

### Kiểu gõ và bảng mã

| Kiểu gõ | Ví dụ |
|---|---|
| **Telex** | `dduowngf` → đường · `nguoiwf` → người · `quyeets` → quyết |
| **VNI** | `d9u7o7ng2` → đường · `Vie65t` → Việt |

| Bảng mã | Mô tả |
|---|---|
| **Unicode dựng sẵn** | Mặc định, tương thích mọi ứng dụng hiện đại |
| **Unicode tổ hợp** | Dấu thanh dạng ký tự kết hợp (U+0300–U+0323) |

## Ứng dụng macOS

**Dokey 0.2** là ứng dụng bộ gõ đầu tiên chạy trên Dokey Core. Đây là một tệp Universal: chạy trên Intel từ macOS 10.13, trên Apple Silicon từ macOS 11.

- Biểu tượng **V/E** trên thanh menu; chuyển Anh/Việt bằng ⌃⇧ (hoặc ⌥Z, ⌃Space, ⌘⇧Space).
- Telex/VNI, Unicode dựng sẵn/tổ hợp, kiểm tra chính tả, đặt dấu kiểu mới/cũ.
- Nhớ chế độ Anh/Việt theo từng ứng dụng; khởi động cùng macOS.
- **Chống nhảy chữ trong Chrome, Edge, Claude và ứng dụng Electron:** event tap chạy trên luồng riêng; ứng dụng được chia thành ba nhóm (trình duyệt, Electron/IDE, thường); với hai nhóm đầu, Dokey gửi từng ký tự và nghỉ ngắn giữa các phím. Có chế độ **Tương thích máy chậm**.
- Tự bật lại event tap khi macOS tắt nó; giữ phím (autorepeat) thì bắt đầu từ mới.
- **0.3.1:**
  - Bảng điều khiển mở ra khi bấm vào Dokey.app.
  - Sửa lỗi mất chữ (`Hãy` → `Hy`) trong ô chat Claude, trình soạn thảo ProseMirror và thanh địa chỉ: Dokey bôi đen chữ cũ rồi gõ đè, không chờ giữa các phím.
  - Cài không cảnh báo bằng `install-macos.sh`.
- **0.3.2:**
  - Hết mất chữ khi gõ nhanh (`Haxy` → `Hy`): chữ thay thế không còn gửi kèm mã phím A, phím có thể vẫn đang được giữ.
  - Gõ `dduocwj` ra "được" mà chữ không nhảy qua lại `đ` ↔ `dd`.
- **0.3.3:** bảng điều khiển thiết kế lại theo phong cách CleanMyMac: thẻ kính mờ, biểu tượng 3D, nút tròn phát sáng, thống kê số từ đã thêm dấu.

Build bằng Command Line Tools, không cần Xcode:

```bash
apps/macos/build.sh --dmg
```

Chi tiết cách cài, cấp quyền Trợ năng và cơ chế hoạt động: [apps/macos/README.md](apps/macos/README.md).

### Đã kiểm thử đến đâu

| Hạng mục | Trạng thái |
|---|---|
| `build.sh` tạo `Dokey.app` Universal (x86_64 + arm64) và `.dmg` trên MacBook Intel, macOS 14, chỉ có Command Line Tools | ✅ Đã chạy |
| `Dokey --self-test`: gọi engine qua API C từ Swift (Telex, VNI, giữ từ tiếng Anh, tự sửa cuối từ, kiểu dấu cũ), phân loại ứng dụng, vẽ biểu tượng | ✅ Chạy trong mỗi lần build và trên CI (macOS 14, Apple Silicon) |
| Ứng dụng khởi động và chạy không lỗi khi chưa có quyền Trợ năng; các trang của bảng điều khiển được vẽ ra ảnh để xem lại (`Dokey --render-panel`) | ✅ Máy Intel, macOS 14 |
| Gõ bằng bản 0.3.0 (có quyền Trợ năng), phím giả lập ở mức HID, 8–120 ms/phím, đọc lại chữ: TextEdit, Terminal, textarea và contenteditable trong Edge | ✅ Đúng hết (`Hãy Việt tiếng đường người`) |
| Bản 0.3.0 trong trình soạn thảo ProseMirror (trên Edge) và thanh địa chỉ Edge | ❌ Lỗi: ProseMirror bỏ qua Backspace tổng hợp (`Hayãy`); thanh địa chỉ đôi khi ra `Haãy` |
| Cách gửi phím của 0.3.1 (bôi đen rồi gõ đè), thử bằng chuỗi sự kiện y hệt: ProseMirror, textarea, contenteditable, thanh địa chỉ Edge | ✅ Đúng hết (`Hãy`) |
| Bản 0.3.1 cài vào `/Applications`, có quyền Trợ năng, gõ giả lập 8–80 ms/phím: TextEdit, textarea và contenteditable trên Edge | ✅ Đúng hết (`Hãy Việt tiếng đường người thuở windows`) |
| Bản 0.3.1 trong ProseMirror trên Edge | ✅ 6/7 lượt đúng hết. Lượt sai: từ đầu tiên ngay sau khi trang vừa tải (lúc đó trình duyệt chưa phát `beforeinput` cho cả chữ thường); từ thứ hai trở đi luôn đúng |
| Bản 0.3.1 ở thanh địa chỉ Edge | ⚠️ Mới đọc lại được một lần (`Việt Nam`, đúng); cách đọc tự động chưa tin cậy |
| Bản 0.3.1 (không chờ giữa các phím) gõ thật trong ô chat Claude Desktop | ✅ Câu dài có `chữ thì còn mỗi Hãy khảo cách của` ra đúng hết, đối chiếu với nhật ký Dokey |
| `install-macos.sh` với `.dmg` mang cờ cách ly như tải từ trình duyệt | ✅ Cài xong không còn cờ cách ly, không cảnh báo |
| Gõ nhanh, phím nguyên âm chưa nhả khi bấm phím dấu (`Haxy`, `maf`) trong ô chat Claude Desktop | ✅ Sau khi đổi mã phím: `Hãy hãy mà và hãy mà ô kìa…` đúng hết (trước đó `Hy`, `m`) |
| Chrome, VS Code | ❌ Chưa thử trực tiếp |
| Chống nhảy chữ trên máy chậm (MacBook Pro 2015, 8 GB RAM) | ❌ Chưa kiểm thử. Khoảng nghỉ hiện tại là ước lượng ban đầu, sẽ chỉnh theo kết quả gõ thật |
| Chạy trên macOS 10.13 – 10.15 và trên máy Apple Silicon thật | ❌ Chưa kiểm thử. Bản build có thư viện Swift cho macOS cũ, nhưng chưa thử trên máy thật |
| Khởi động cùng macOS, nhớ chế độ theo ứng dụng, các phím chuyển | ❌ Chưa kiểm thử bằng tay |

Hạn chế đã biết: trong ứng dụng Electron có cửa sổ dòng lệnh (terminal của VS Code), Shift+← không bôi đen chữ, nên có thể gõ sai dấu ở đó. Với bảng mã Unicode tổ hợp, Dokey vẫn dùng Backspace.

## Ứng dụng Windows

> ⚠️ **Chưa được thử trên máy Windows thật.** Dokey cho Windows được viết trên macOS. Mọi kiểm thử dưới đây chạy trên máy ảo GitHub Actions (Windows Server 2022, x64). Bản x86 và ARM64 mới chỉ được build, chưa chạy lần nào.

**Dokey 0.3** thêm ứng dụng cho Windows 10/11, một bộ cài cho cả x86, x64 và ARM64: `Dokey-<phiên bản>-Windows-Setup.exe`.

- Biểu tượng **V/E** ở khay hệ thống; chuyển Anh/Việt bằng Ctrl+Shift hoặc Alt+Z, hoặc bấm vào biểu tượng.
- Telex/VNI, kiểm tra chính tả, đặt dấu kiểu mới/cũ, khởi động cùng Windows.
- **Chống nhảy chữ:** hook `WH_KEYBOARD_LL` nhẹ trên luồng riêng; mỗi lần sửa chữ là một lần `SendInput` duy nhất (xoá + chèn Unicode); phím gõ tiếp trong lúc chờ được xếp hàng sau chữ của Dokey nên không vượt lên trước được. Với Chrome, Edge và ứng dụng Electron (`Chrome_WidgetWin_*`) có thêm khoảng nghỉ ngắn giữa phím xoá và chữ mới.
- Tự đứng ngoài khi bộ gõ Trung/Nhật/Hàn đang bật; đặt lại từ khi click chuột, đổi cửa sổ, bấm phím mũi tên.
- Không cần quyền quản trị, không cần cài Visual C++ Redistributable.

### Đã kiểm thử đến đâu

| Hạng mục | Trạng thái |
|---|---|
| Build `Dokey.exe` cho x86, x64, ARM64 (MSVC, CRT tĩnh) và kiểm tra kiến trúc từng tệp | ✅ Mỗi lần CI |
| Unit test: dựng chuỗi sự kiện `SendInput`, gắn `dwExtraInfo`, hợp đồng với engine | ✅ CI, x64 và x86 |
| `Dokey.exe --self-test`: cài và gỡ hook bàn phím/chuột | ✅ CI, x64 và x86 |
| **Gõ thật vào Notepad**: phím giả lập bằng `SendInput`, gõ thường (40 ms/phím) và gõ dồn hết tốc độ, đọc lại chữ trong Notepad: `Việt Nam đường windows Tôi yêu tiếng Việt` | ✅ CI, x64 (máy ảo) |
| Bộ cài: cài im lặng, chọn đúng bản x64, có lối tắt Start menu, gỡ cài đặt sạch | ✅ CI, x64 (máy ảo) |
| Gõ trong Chrome, Edge, VS Code, Word… | ❌ Chưa kiểm thử |
| Máy thật Windows 10/11, máy chậm, máy ARM64, bản x86 trên Windows 32-bit | ❌ Chưa kiểm thử |
| Giao diện khay, menu, phím tắt chuyển Anh/Việt, khởi động cùng Windows | ❌ Chưa kiểm thử bằng tay |

Bộ cài chưa ký số nên SmartScreen có thể cảnh báo: chọn **More info → Run anyway**. Chi tiết: [apps/windows/README.md](apps/windows/README.md).

## Bắt đầu nhanh

### Tải bản dựng sẵn

Tải gói cho hệ điều hành của bạn tại trang [**Releases**](https://github.com/dhtoan/Dokey/releases). Mỗi gói gồm:
- công cụ dòng lệnh `dokey`;
- thư viện tĩnh `dokey_core`;
- thư mục header `include/dokey/`;
- tài liệu.

### Dùng công cụ dòng lệnh

```bash
dokey "Vieetj Nam"                 # Việt Nam
echo "chaof buooir sangs" | dokey  # chào buổi sáng
dokey --vni "Vie65t Nam"           # Việt Nam
dokey --old-tone "hoaf binhf"      # hòa bình
dokey --help
```

### Build từ mã nguồn

Cần CMake 3.16 trở lên và trình biên dịch C++17 (Clang, GCC hoặc MSVC).

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
ctest --test-dir build -C Release
```

## Tích hợp vào ứng dụng

Lớp nền tảng chỉ cần chuyển từng phím cho engine, rồi thực hiện phép sửa mà engine trả về.

```c
#include <dokey/dokey.h>

dokey_options opt = { DOKEY_TELEX, DOKEY_UNICODE, /*modern*/ 1, /*spell*/ 1 };
dokey_engine* engine = dokey_create(&opt);

dokey_edit edit;
if (dokey_key(engine, typedChar, &edit)) {
    // Nuốt phím gốc, xoá edit.backspaces ký tự, rồi chèn edit.text (UTF-16).
} else {
    // Để phím gốc đi qua, không cần làm gì thêm.
}

// Khi người dùng bấm Backspace:
dokey_backspace(engine);
// Khi click chuột, đổi ứng dụng, bấm phím mũi tên:
dokey_reset(engine);

dokey_destroy(engine);
```

Ứng dụng C++ có thể dùng trực tiếp lớp `dokey::Engine` trong `include/dokey/engine.hpp`.

## Kiến trúc

```
 phím ──▶ dokey_key() ──▶ chuỗi phím của từ hiện tại
                                │
                                ▼
                     Parser: Telex / VNI ──▶ chữ cái + dấu + thanh
                                │
                                ▼
                     Kiểm tra từ điển âm tiết ──▶ hợp lệ? hiển thị : giữ nguyên phím đã gõ
                                │
                                ▼
                     So với chữ đang hiển thị ──▶ { số ký tự cần xoá, chuỗi cần chèn }
```

| Thư mục | Nội dung |
|---|---|
| `include/dokey/` | API công khai: C (`dokey.h`) và C++ (`engine.hpp`) |
| `src/` | Parser, quy tắc đặt dấu, từ điển âm tiết, bảng ký tự Unicode |
| `tools/` | Công cụ dòng lệnh `dokey` |
| `tests/` | Bộ kiểm thử |
| `apps/macos/` | Ứng dụng macOS (Swift + AppKit) và script build |
| `apps/windows/` | Ứng dụng Windows (C++ Win32), bộ cài Inno Setup |
| `SPEC.md` | Đặc tả hành vi đầy đủ |

## Chất lượng

- **18.500 ca kiểm thử** chạy tự động trên Linux, macOS và Windows sau mỗi lần thay đổi:
  - các ca viết tay cho từ thông dụng, phím huỷ, từ tiếng Anh, VNI và Backspace;
  - phép thử khứ hồi: gõ toàn bộ 3.759 âm tiết với cả 6 thanh.
- Mã biên dịch sạch, không có cảnh báo với `-Wall -Wextra -Wpedantic`.

## Lộ trình

| Phiên bản | Nội dung | Trạng thái |
|---|---|---|
| **0.1** | Dokey Core: Telex, VNI, kiểm tra chính tả, API C/C++, công cụ dòng lệnh | ✅ Phát hành |
| **0.2** | Ứng dụng macOS (Swift + AppKit, macOS 10.13+, Intel và Apple Silicon) | ✅ Phát hành cùng 0.3 |
| **0.3** | Ứng dụng Windows (Windows 10/11, x86, x64, ARM64), bộ cài Setup.exe | 🧪 Đã phát hành, chưa thử trên máy Windows thật |
| 0.4 | Gõ tắt, công cụ chuyển mã, bảng mã TCVN3, VNI Windows, CP1258 | 🗓️ Kế hoạch |
| 1.0 | Bộ biểu tượng mới, ký số và notarize, phát hành chính thức | 🗓️ Kế hoạch |

## Bản quyền

© 2026 Do Huy Toan. All rights reserved.
