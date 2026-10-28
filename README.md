# Dokey Core

[![CI](https://github.com/dhtoan/Dokey/actions/workflows/ci.yml/badge.svg)](https://github.com/dhtoan/Dokey/actions/workflows/ci.yml)

Engine gõ tiếng Việt thế hệ mới của **Dokey**, viết mới hoàn toàn bằng C++17. Engine dùng chung cho Dokey trên macOS, Windows, Linux và Android.

## Điểm khác biệt

- **Tính lại cả từ sau mỗi phím.** Engine giữ các phím đã gõ của từ hiện tại và dựng lại toàn bộ từ sau mỗi lần nhấn. Không có trạng thái tích luỹ nên không thể lệch với chữ trên màn hình.
- **Chỉ gửi phím khi thực sự cần.** Khi phím gõ không làm thay đổi chữ nào, engine báo cho nền tảng để phím gốc đi qua, không phát sinh sự kiện tổng hợp. Nhờ vậy giảm tối đa nguy cơ nhảy chữ trong Chrome, Edge và các ứng dụng Electron.
- **Kiểm tra chính tả bằng từ điển âm tiết.** Hơn 3.700 âm tiết được dựng từ bảng phụ âm đầu và vần chuẩn của tiếng Việt. Engine chỉ thêm dấu khi kết quả vẫn có thể thành một âm tiết hợp lệ, và giữ nguyên các từ tiếng Anh như `windows`, `chrome`, `github`, `use`.
- **Gõ dấu tự do.** Dấu mũ và dấu thanh có thể gõ ở bất kỳ đâu trong từ (`tienges`, `tiengse` → tiếng). Gõ lặp phím dấu để huỷ (`aaa` → aa, `ass` → as).
- **Tự sửa khi kết thúc từ.** Ví dụ `thuowr` → thuở: chữ `ươ` không được đứng cuối âm tiết nên được chuyển thành `uơ`.
- **API C gọn nhẹ** cho Swift, Win32 và Kotlin/JNI (`include/dokey/dokey.h`).

## Hỗ trợ

| | |
|---|---|
| Kiểu gõ | Telex, VNI |
| Bảng mã | Unicode dựng sẵn; Unicode tổ hợp (dấu thanh dạng ký tự kết hợp) |
| Vị trí dấu | Kiểu mới (hoà, khoẻ, thuý) hoặc kiểu cũ (hòa, khỏe, thúy) |

## Build và kiểm thử

```bash
cmake -S . -B build && cmake --build build && ctest --test-dir build
```

Nếu máy không có CMake:

```bash
clang++ -std=c++17 -Iinclude src/*.cpp tests/engine_tests.cpp -o dokey_tests && ./dokey_tests
```

Bộ kiểm thử gồm hai phần:
- các ca viết tay với kết quả mong đợi cho từ thông dụng, phím huỷ, từ tiếng Anh, VNI và Backspace;
- phép thử khứ hồi: gõ toàn bộ 3.759 âm tiết với cả 6 thanh, tổng cộng **18.494 ca**.

CI chạy kiểm thử trên Linux, macOS và Windows sau mỗi lần push.

## Tài liệu

- [SPEC.md](SPEC.md): đặc tả hành vi đầy đủ (quy tắc gõ, chính tả, vị trí dấu, Backspace, API).

## Lộ trình

| Giai đoạn | Nội dung | Trạng thái |
|---|---|---|
| 0 | Đặc tả và bộ kiểm thử | ✅ |
| 1 | Engine C++ mới | ✅ |
| 2 | Ứng dụng macOS mới (Swift + AppKit, macOS 10.13+) | ⏳ |
| 3 | Ứng dụng Windows mới (Win32, x86/x64/ARM64) | 🗓️ |
| 4 | Gõ tắt, chuyển mã, bảng mã cũ (TCVN3, VNI Windows, CP1258), bộ biểu tượng mới | 🗓️ |
| 5 | Ký số, notarize, phát hành | 🗓️ |

## Bản quyền

© 2026 Do Huy Toan. All rights reserved.
