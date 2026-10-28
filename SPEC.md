# Đặc tả bộ gõ Dokey Core

Tài liệu này mô tả **hành vi** của engine gõ tiếng Việt Dokey Core. Đặc tả được viết từ quy tắc chính tả tiếng Việt và quy ước Telex/VNI phổ biến (là kiến thức công khai). Đặc tả không dựa trên mã nguồn của bất kỳ bộ gõ nào khác.

## 1. Mô hình hoạt động

- Engine giữ **chuỗi phím thô** (`raw`) của từ đang gõ.
- Sau mỗi phím, engine **tính lại toàn bộ** từ hiển thị từ `raw`, theo cách thuần hàm: cùng một `raw` luôn cho cùng một kết quả.
- Kết quả trả cho nền tảng là một **phép sửa** gồm hai phần: số ký tự cần xoá, và đoạn văn bản cần chèn. Phép sửa được tính bằng phần đầu chung giữa từ đang hiển thị và từ mới.
- Nếu phép sửa chỉ là "chèn đúng phím vừa gõ", engine báo `handled = false`. Khi đó nền tảng để phím gốc đi qua, không gửi sự kiện tổng hợp. Cách này giảm số sự kiện phải gửi xuống mức tối thiểu.
- Các ký tự ngắt từ kết thúc từ hiện tại và đi qua nguyên vẹn. Ký tự ngắt gồm: khoảng trắng, dấu câu, Enter, Tab; ở chế độ Telex, chữ số cũng là ký tự ngắt.

## 2. Kiểu gõ

### Telex
| Phím | Tác dụng |
|---|---|
| `aa` `ee` `oo` | â ê ô (dấu mũ; phím sau có thể gõ cách xa nguyên âm, ví dụ `tienes` → tiến) |
| `aw` `ow` `uw` | ă ơ ư; `uow` → ươ |
| `w` đứng riêng | ư (ví dụ `nhw` → như) |
| `dd` | đ (chỉ áp dụng cho chữ d đứng đầu từ) |
| `s` `f` `r` `x` `j` | dấu sắc, huyền, hỏi, ngã, nặng |
| `z` | xoá dấu thanh |

### VNI
| Phím | Tác dụng |
|---|---|
| `1` `2` `3` `4` `5` | dấu sắc, huyền, hỏi, ngã, nặng |
| `6` | dấu mũ (â ê ô) |
| `7` | móc (ơ ư; `uo7` → ươ) |
| `8` | trăng (ă) |
| `9` | đ |
| `0` | xoá dấu thanh |

### Quy tắc chung
- **Gõ lặp để huỷ:** gõ lại đúng phím dấu vừa áp dụng sẽ bỏ dấu đó và in ra ký tự phím. Ví dụ: `aaa` → `aa`, `ass` → `as`, `ddd` → `dd`. Sau khi huỷ, phím đó được coi là chữ thường cho đến hết từ.
- **Đổi dấu thanh:** gõ phím thanh khác sẽ thay dấu thanh hiện có (`asf` → à).
- **Hoa thường:** giữ theo chữ cái gốc; phím dấu không ảnh hưởng hoa thường (`Aa` → Â, `DDuowngf` → Đường).

## 3. Kiểm tra chính tả và khôi phục

- Một âm tiết hợp lệ có dạng **phụ âm đầu + vần**. Danh sách phụ âm đầu và vần nằm ở `src/syllables.cpp`.
- Các ràng buộc chính tả được kiểm tra:
  - `k`, `gh`, `ngh` chỉ đứng trước e, ê, i, y;
  - `c`, `g`, `ng` không đứng trước e, ê, i;
  - `q` luôn đi cùng `u` (`qu`);
  - `gi` cộng vần bắt đầu bằng `i` thì bỏ bớt một chữ `i` (gì, gìn, giêng);
  - vần `iê` khi không có phụ âm đầu viết là `yê`.
- Vần kết thúc bằng phụ âm tắc (`c`, `ch`, `p`, `t`) chỉ nhận dấu sắc hoặc nặng.
- Một phím dấu chỉ được áp dụng nếu kết quả vẫn là **tiền tố của một âm tiết hợp lệ**. Nếu không, phím đó được in ra như chữ thường.
- Khi bật kiểm tra chính tả: nếu từ hiển thị không còn là tiền tố hợp lệ, engine hiển thị lại **đúng các phím đã gõ**. Nhờ vậy các từ tiếng Anh như `windows`, `master`, `chrome` được giữ nguyên.
- Khi kiểm tra chính tả bị tắt: phím dấu luôn được áp dụng nếu có nguyên âm đích.

## 4. Vị trí dấu thanh

Xét nhóm nguyên âm của âm tiết. Nhóm này không tính `u` trong `qu` và `i` trong `gi`, trừ khi sau `gi` không còn nguyên âm nào khác.

1. Nếu có nguyên âm mang dấu phụ (ă â ê ô ơ ư), dấu thanh đặt vào nguyên âm đó. Với `ươ`, dấu đặt vào `ơ`.
2. Nếu sau nhóm nguyên âm có phụ âm cuối, dấu đặt vào nguyên âm cuối của nhóm (toán, hoàn, huýt).
3. Nhóm có 3 nguyên âm: dấu đặt vào nguyên âm giữa (ngoài, xoáy).
4. Nhóm có 2 nguyên âm: dấu đặt vào nguyên âm đầu (mía, mùa, tay → táy). Riêng `oa`, `oe`, `uy` ở **kiểu mới** đặt vào nguyên âm sau (hoà, khoẻ, thuý); ở **kiểu cũ** đặt vào nguyên âm đầu (hòa, khỏe, thúy).
5. Nhóm có 1 nguyên âm: dấu đặt vào nguyên âm đó.

## 5. Phím xoá (Backspace)

- Nền tảng để phím Backspace đi qua.
- Engine bỏ ký tự cuối khỏi từ đang hiển thị, rồi dựng lại `raw` từ phần còn lại theo cách gõ chuẩn của kiểu gõ đang dùng.
- Nếu không dựng lại được, engine bắt đầu từ mới.

## 6. Bảng mã đầu ra

- **Unicode dựng sẵn (NFC):** mặc định.
- **Unicode tổ hợp:** chữ có dấu phụ dùng ký tự dựng sẵn; dấu thanh dùng ký tự kết hợp (U+0301, U+0300, U+0309, U+0303, U+0323).
- Các bảng mã cũ (TCVN3, VNI Windows, CP1258) được xử lý ở giai đoạn sau, theo bảng mã công bố của từng chuẩn.

## 7. Giao diện cho nền tảng (C API)

```c
dokey_engine* dokey_create(const dokey_options*);
int  dokey_key(dokey_engine*, uint32_t ch, dokey_edit* out);   // 1 = handled
void dokey_backspace(dokey_engine*);
void dokey_reset(dokey_engine*);   // gọi khi click chuột, đổi ứng dụng, phím mũi tên…
void dokey_destroy(dokey_engine*);
```

## 8. Lớp nền tảng macOS

Ứng dụng `apps/macos/` dùng API ở mục 7 theo các quy tắc sau.

- **Bắt phím:** một `CGEventTap` ở mức phiên (session), đặt ở đầu chuỗi, chạy trên run loop của một luồng riêng. Tap nhận: phím xuống, đổi phím bổ trợ, click chuột.
- **Ký tự gửi cho engine:** chuỗi Unicode của sự kiện phím theo bố cục bàn phím hiện tại, chỉ khi phím sinh đúng một ký tự in được và không có ⌘ ⌃ ⌥.
- **Kết quả `1`:** nuốt phím gốc; gửi `backspaces` lần phím Backspace, rồi gửi `text` bằng sự kiện phím mang chuỗi Unicode. Sự kiện được chèn bằng `CGEventTapPostEvent`, mang dấu `eventSourceUserData` riêng, và không mang cờ phím bổ trợ.
- **Kết quả `0`:** để phím gốc đi qua.
- **Backspace:** gọi `dokey_backspace`, để phím đi qua.
- **Enter, Tab:** gửi cho engine như ký tự ngắt (`\r`, `\t`). Nếu engine sửa từ, gửi phép sửa (bỏ ký tự ngắt ở cuối), rồi gửi lại bản sao của phím gốc.
- **`dokey_reset`:** click chuột, phím mũi tên, Home, End, Page Up/Down, Esc, Forward Delete, phím tắt có ⌘ ⌃ ⌥, phím giữ (autorepeat), đổi ứng dụng, bật/tắt tiếng Việt.
- **Nhóm ứng dụng:** trình duyệt, Electron/IDE, thường (theo bundle id, và theo framework trong `Contents/Frameworks` với ứng dụng lạ). Hai nhóm đầu nhận mỗi sự kiện một ký tự UTF-16 (không tách cặp surrogate), có khoảng nghỉ sau mỗi phím và sau loạt Backspace. Nhóm thường nhận tối đa 20 ký tự mỗi sự kiện, không nghỉ.
- **Tap bị tắt** (`kCGEventTapDisabledByTimeout`, `kCGEventTapDisabledByUserInput`): bật lại ngay và bắt đầu từ mới. Bộ đếm giờ 2 giây kiểm tra lại.
