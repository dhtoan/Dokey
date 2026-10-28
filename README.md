<div align="center">

# Dokey

**Lõi gõ tiếng Việt thế hệ mới: nhanh, chính xác, đa nền tảng**

*The next-generation Vietnamese input engine*

[![CI](https://github.com/dhtoan/Dokey/actions/workflows/ci.yml/badge.svg)](https://github.com/dhtoan/Dokey/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/dhtoan/Dokey?include_prereleases&label=release&color=0A84FF)](https://github.com/dhtoan/Dokey/releases)
![C++17](https://img.shields.io/badge/C%2B%2B-17-00599C?logo=cplusplus&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Windows%20%7C%20Linux-6E6E73)
![Tests](https://img.shields.io/badge/tests-18%2C494%20passing-2EA44F)

[Giới thiệu](#giới-thiệu) •
[Tính năng](#tính-năng) •
[Bắt đầu nhanh](#bắt-đầu-nhanh) •
[Tích hợp](#tích-hợp-vào-ứng-dụng) •
[Kiến trúc](#kiến-trúc) •
[Lộ trình](#lộ-trình)

</div>

---

## Giới thiệu

**Dokey** là bộ gõ tiếng Việt được xây dựng lại từ đầu, hướng tới một mục tiêu: gõ đúng ngay lần đầu, ở mọi ứng dụng, trên mọi máy.

Repo này chứa **Dokey Core**, bộ não xử lý tiếng Việt dùng chung cho các ứng dụng Dokey trên macOS, Windows, Linux và Android. Dokey Core là một thư viện C++17 độc lập, không phụ thuộc thư viện ngoài, có API C ổn định để tích hợp vào Swift, Win32 hay Kotlin.

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
| `SPEC.md` | Đặc tả hành vi đầy đủ |

## Chất lượng

- **18.494 ca kiểm thử** chạy tự động trên Linux, macOS và Windows sau mỗi lần thay đổi:
  - các ca viết tay cho từ thông dụng, phím huỷ, từ tiếng Anh, VNI và Backspace;
  - phép thử khứ hồi: gõ toàn bộ 3.759 âm tiết với cả 6 thanh.
- Mã biên dịch sạch, không có cảnh báo với `-Wall -Wextra -Wpedantic`.

## Lộ trình

| Phiên bản | Nội dung | Trạng thái |
|---|---|---|
| **0.1** | Dokey Core: Telex, VNI, kiểm tra chính tả, API C/C++, công cụ dòng lệnh | ✅ Phát hành |
| 0.2 | Ứng dụng macOS (Swift + AppKit, macOS 10.13+, Intel và Apple Silicon) | 🚧 Đang phát triển |
| 0.3 | Ứng dụng Windows (Windows 10/11, x86, x64, ARM64) | 🗓️ Kế hoạch |
| 0.4 | Gõ tắt, công cụ chuyển mã, bảng mã TCVN3, VNI Windows, CP1258 | 🗓️ Kế hoạch |
| 1.0 | Bộ biểu tượng mới, ký số và notarize, phát hành chính thức | 🗓️ Kế hoạch |

## Bản quyền

© 2026 Do Huy Toan. All rights reserved.
