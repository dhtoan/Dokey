# Dokey: đã kiểm thử đến đâu

Trang này ghi lại trung thực những gì đã và chưa được kiểm thử, kể cả các lỗi đã gặp và cách sửa. Bảng của bản Windows nằm trong [README](../README.md#-windows).

## macOS

| Hạng mục | Trạng thái |
|---|---|
| `build.sh` tạo `Dokey.app` Universal (x86_64 + arm64) và `.dmg` trên MacBook Intel, macOS 14, chỉ có Command Line Tools | ✅ Đã chạy |
| `Dokey --self-test`: gọi engine qua API C từ Swift (Telex, VNI, giữ từ tiếng Anh, tự sửa cuối từ, kiểu dấu cũ), phân loại ứng dụng, vẽ biểu tượng | ✅ Chạy trong mỗi lần build và trên CI (macOS 15, Apple Silicon) |
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
| Chrome | ❌ Chưa thử trực tiếp |
| Tiếng Hàn (두벌식) trong VS Code 1.144 (Electron), gõ giả lập ở mức HID | ✅ Trình soạn thảo: đúng hết ở 90, 25 và 10 ms/phím. Ô chat: đúng hết ở 90 và 25 ms/phím. Terminal tích hợp (zsh): đúng ở 25, 40 và 90 ms/phím; ⚠️ lỗi ở 10–15 ms/phím (nhanh hơn người gõ thật) |
| Chống nhảy chữ trên máy chậm (MacBook Pro 2015, 8 GB RAM) | ❌ Chưa kiểm thử. Khoảng nghỉ hiện tại là ước lượng ban đầu, sẽ chỉnh theo kết quả gõ thật |
| Chạy trên macOS 10.13 – 10.15 và trên máy Apple Silicon thật | ❌ Chưa kiểm thử. Bản build có thư viện Swift cho macOS cũ, nhưng chưa thử trên máy thật |
| Khởi động cùng macOS, nhớ chế độ theo ứng dụng, các phím chuyển | ❌ Chưa kiểm thử bằng tay |

Hạn chế đã biết: trong ứng dụng Electron có cửa sổ dòng lệnh (terminal của VS Code), Shift+← không bôi đen chữ, nên có thể gõ sai dấu ở đó. Với bảng mã Unicode tổ hợp, Dokey vẫn dùng Backspace.
| Bảng điều khiển 0.3.3 / 0.3.4 | ✅ Vẽ ra ảnh bằng `Dokey --render-marketing` (ảnh trong `docs/images/`); chưa thử trên macOS 10.13–10.15 |
| 0.4: mở lại từ, Backspace đặt lại dấu, ư+o → ươ, Đắk Lắk, gõ tắt, Quick Telex, hoàn tác (lõi) | ✅ Bài kiểm thử tự động `editing()` và API C trong `tests/engine_tests.cpp` |
| 0.4: bộ hồi quy 1.171 từ tiếng Anh/lập trình + 30 câu tiếng Việt | ✅ `corpus()`; 1.097 từ giữ nguyên, 74 từ là âm tiết tiếng Việt (liệt kê trong `tests/data/english_known.txt`) |
| Phím dấu gõ đôi giữa từ theo quy ước Telex (`tesst` → test, `marrketing` → marketing), đồng thời giữ chữ đôi tiếng Anh trước nguyên âm và ở cuối từ (`message`, `pass`) | ✅ `editing()` và `corpus()`; quét 12.518 từ có `ss/ff/rr` trong từ điển macOS: chữ đôi trước phụ âm (`offline`, `passport`) cần gõ ba lần (`offfline`) |
| Tự cập nhật (0.5.1): bản thử 0.4.9 chạy `--check-updates`, đọc bản v0.5.0 thật trên GitHub, hiện ghi chú phát hành, tải `.dmg`, kiểm tra SHA-256 và chữ ký, thay ứng dụng rồi tự mở lại | ✅ Máy Intel, macOS 14. Thông báo nền (UNUserNotificationCenter) chưa thử bằng tay |
| 0.4 trên macOS: Backspace và Esc qua event tap, Spotlight, Google Docs, kiểm tra cập nhật | ❌ Chưa gõ thử thật (cần cài bản mới và cấp lại quyền Trợ năng) |

