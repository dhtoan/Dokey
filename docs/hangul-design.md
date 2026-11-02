# Thiết kế: Dokey Core nhiều ngôn ngữ, gói tiếng Hàn (두벌식)

Trạng thái: **bản thử**. Bộ ghép Hangul (`src/hangul.cpp`, `include/dokey/hangul.hpp`) đã có kèm bài kiểm thử (`tests/hangul_tests.cpp`). Bộ ghép đã được nối vào app macOS sau một khoá ẩn (xem mục 8), còn bản Windows thì chưa. Engine tiếng Việt (`engine.cpp`, `vietnamese.cpp`) chưa bị sửa dòng nào. Khi chưa đặt khoá, app macOS gõ tiếng Việt như cũ.

## 1. Vì sao làm tiếng Hàn

Bộ gõ tiếng Hàn của Apple dùng *marked text*: âm tiết đang ghép nằm ở trạng thái "chưa chốt" trong ô nhập. Khi bấm Enter, ứng dụng nhận cùng lúc lệnh chốt chữ và phím Enter. Chrome, các ứng dụng Electron (VS Code, Claude Desktop) và các TUI chạy trong terminal (Claude Code, Warp) hay xử lý Enter trước khi chữ được chốt, nên âm tiết cuối bị mất hoặc bị lặp. Kho `anthropics/claude-code` có khoảng 157 issue về bộ gõ tiếng Hàn.

Dokey không dùng marked text. Chữ trên màn hình luôn là chữ thật, và Dokey sửa nó bằng Backspace hoặc bằng cách bôi đen rồi gõ đè. Nếu tiếng Hàn đi theo cùng cách này, lúc người dùng bấm Enter thì không còn gì "đang ghép" để chốt. Đây mới là **suy luận**. Mục 6 ghi rõ phần nào đã kiểm chứng và phần nào chưa.

## 2. Hiện trạng: phần nào dùng chung được

`Engine` (`src/engine.cpp`) đang làm hai việc trộn vào nhau:

| Dùng chung cho mọi ngôn ngữ | Riêng tiếng Việt |
|---|---|
| Giữ phím của từ đang gõ (`raw_`, `typed_`, `display_`) | `Parser` (Telex/VNI), bảng âm tiết, vị trí dấu thanh |
| Tính phép sửa bằng phần đầu chung (`commit`) và quy tắc `handled = false` khi chỉ cần chèn đúng phím vừa gõ | Kiểm tra chính tả, trả lại phím gốc cho từ tiếng Anh |
| Ký tự ngắt từ kết thúc từ | Sửa cuối từ (`thuowr` → thuở), quy tắc từ tiếng Anh có chữ lặp |
| Gõ tắt, mở lại từ sau một dấu cách, hoàn tác bằng Esc, `reset` | Quick Telex, chữ số đầu từ không phải là từ |
| Backspace: nền tảng có thể nhận phép sửa (`backspaceEdit`) | Dựng lại phím từ chữ đang hiển thị (`encodeKeys`) |
| API C, `simulate`, toàn bộ lớp nền tảng macOS/Windows | |

## 3. Đề xuất: engine chung + gói quy tắc

```cpp
// Một gói quy tắc là một hàm thuần từ phím ra chữ, cộng vài cờ hành vi.
class RulePack {
public:
    virtual ~RulePack() = default;
    virtual bool isWordKey(char32_t ch) const = 0;
    // Thuần hàm: cùng phím luôn cho cùng chữ. `typed` là phím đúng như đã gõ
    // (tiếng Việt cần nó để trả lại từ tiếng Anh); wordEnded: sắp có ký tự ngắt.
    virtual std::u16string render(const std::u16string& raw, const std::u16string& typed,
                                  bool wordEnded) const = 0;
    // Backspace: tiếng Việt dựng lại phím từ chữ hiển thị; tiếng Hàn bỏ phím cuối.
    enum class Backspace { RebuildFromText, DropLastKey };
    virtual Backspace backspaceRule() const = 0;
    virtual bool encodeKeys(const std::u16string& text, std::u16string& keys) const { return false; }
    virtual bool reopenAfterSpace() const = 0;   // Việt: có; Hàn: không (bộ gõ Hàn không làm vậy)
    virtual size_t maxWordKeys() const = 0;      // Việt: 32; Hàn: 256
};
```

`Engine` giữ toàn bộ cột trái của bảng ở mục 2 và gọi gói đang chọn. `VietnamesePack` nhận nguyên `Parser`, `render`, `encodeKeys` và Quick Telex từ `engine.cpp`. Gói này chỉ là chỗ chuyển code sang, không viết lại logic. `HangulPack` gọi `hangul::compose()`.

API C (đã làm trong bản thử) có thêm hàm `dokey_set_language(engine, DOKEY_LANG_VIETNAMESE | DOKEY_LANG_KOREAN)`, chứ không thêm trường vào `dokey_options`. Lý do: bản Swift tạo `dokey_options` bằng hàm khởi tạo liệt kê đủ các trường, nên mỗi trường mới buộc phải sửa mọi chỗ gọi. Với tiếng Hàn, `dokey_key`, `dokey_backspace_edit` và `dokey_reset` chạy qua `HangulEngine`; `dokey_undo` và gõ tắt không có tác dụng. Khi tách gói thật, có thể cho `method` mang nghĩa bố cục (`DOKEY_HANGUL_2SET = 0`, để chỗ cho 세벌식).

### Giữ tiếng Việt y hệt từng byte

Bản thử chưa đụng tới engine tiếng Việt. Khi tách gói (một PR riêng), cần chặn thay đổi hành vi bằng hai lớp:

1. Toàn bộ `tests/engine_tests.cpp` phải qua (hiện tại 20.635/20.635).
2. Thêm một công cụ "golden": chạy engine **trước khi tách** trên bộ từ có sẵn cùng khoảng một triệu chuỗi phím ngẫu nhiên, với mọi tổ hợp tuỳ chọn (Telex/VNI, kiểu dấu, chính tả, tổ hợp, Quick Telex, gõ tắt), có xen Backspace và Esc. Ghi lại từng phép sửa (`handled`, `backspaces`, `insert`) rồi băm. Sau khi tách, mã băm phải trùng khớp. Công cụ này chưa được viết.

## 4. Gói tiếng Hàn 두벌식: quy tắc

`hangul::compose(keys)` là hàm thuần. Nó nhận các phím chữ Latin theo vị trí của bố cục 두벌식 (KS X 5002) trên bàn phím US/ABC, rồi trả về chữ.

- **Bảng phím:** `q w e r t y u i o p` → ㅂ ㅈ ㄷ ㄱ ㅅ ㅛ ㅕ ㅑ ㅐ ㅔ; `a s d f g h j k l` → ㅁ ㄴ ㅇ ㄹ ㅎ ㅗ ㅓ ㅏ ㅣ; `z x c v b n m` → ㅋ ㅌ ㅊ ㅍ ㅠ ㅜ ㅡ. Shift chỉ có tác dụng với `Q W E R T O P` → ㅃ ㅉ ㄸ ㄲ ㅆ ㅒ ㅖ; các chữ hoa khác gõ như chữ thường.
- **Âm tiết:** phụ âm đầu + nguyên âm (+ phụ âm cuối), mã hoá thành `U+AC00 + (đầu × 21 + giữa) × 28 + cuối`, luôn là ký tự dựng sẵn (U+AC00–U+D7A3).
- **Nguyên âm ghép:** ㅗ+ㅏ ㅐ ㅣ → ㅘ ㅙ ㅚ; ㅜ+ㅓ ㅔ ㅣ → ㅝ ㅞ ㅟ; ㅡ+ㅣ → ㅢ.
- **Phụ âm cuối kép:** ㄳ ㄵ ㄶ ㄺ ㄻ ㄼ ㄽ ㄾ ㄿ ㅀ ㅄ. ㄲ và ㅆ làm phụ âm cuối được (gõ bằng Shift). ㄸ ㅃ ㅉ không bao giờ làm phụ âm cuối.
- **Tách âm tiết:** nguyên âm đứng sau phụ âm cuối sẽ lấy phụ âm đó làm phụ âm đầu: 갑+ㅏ → 가바, 있+ㅓ → 이써. Nếu là phụ âm kép thì chỉ lấy phụ âm sau: 값+ㅣ → 갑시, 닭+ㅣ → 달기.
- **Jamo đứng riêng:** jamo không ghép được thì hiện dạng compatibility jamo (U+3131–U+3163): ㄱㄱ, ㅏㄱ, 아ㄸ. Hai phụ âm đứng riêng không gộp thành phụ âm kép (ㄱ+ㅅ → ㄱㅅ).
- **Ký tự ngắt** (dấu cách, Enter, Tab, chữ số, dấu câu): kết thúc từ và đi qua nguyên vẹn. Engine **không bao giờ** báo `handled` cho các phím này, vì không còn gì phải chốt.
- **Backspace** bỏ phím cuối của từ đang gõ rồi tính lại: 한 ⌫ → 하, 과 ⌫ → 고, 값 ⌫ → 갑. Nếu Backspace thường đã cho đúng chữ thì phím đi qua; nếu không, nền tảng nuốt Backspace và áp phép sửa. Sau ký tự ngắt, chữ trước đó là chữ thường: `한␣⌫ㅏ` → 한ㅏ.
- **Từ dài:** sau 256 phím, từ mới bắt đầu. Âm tiết ở chỗ nối không tách ngược nữa. Bộ gõ Hàn thật cũng không ghép qua chỗ này.

### Điểm khác bộ gõ Apple, cần người Hàn xác nhận

- `가바 ⌫`: Dokey ra **갑**, vì nó bỏ phím cuối rồi ghép lại. Bộ gõ Apple và libhangul ra **가ㅂ**, vì chúng chỉ xoá jamo khỏi âm tiết đang ghép. Muốn ra 가ㅂ thì phải giữ trạng thái ngoài chuỗi phím, mất tính thuần hàm.
- Bộ gõ Hàn không mở lại từ sau dấu cách. Gói Hàn nên tắt tính năng này.
- Hoàn tác bằng Esc có thể dùng làm "gõ nhầm chế độ": 한국 ⎋ → gksrnr. Engine chung đã có sẵn phần này, chỉ cần gói Hàn trả về `typed`.

## 5. Kết quả kiểm thử (trên Windows, lõi C++)

Biên dịch bằng zig c++ 0.16 (clang), `-std=c++17 -Wall -Wextra`:

- `dokey_tests` (tiếng Việt, có sẵn): **20.635/20.635**, giống lúc chưa thêm gói Hàn.
- `dokey_hangul_tests` (mới): **53.204/53.204**, gồm:
  - 86 ca viết tay: từ thông dụng (한국, 안녕하세요, 감사합니다, 있습니다, 읽어, 않아, 밟아, 깎아, 화이팅), nguyên âm ghép, tách âm tiết, jamo đứng riêng, Backspace, từ dài.
  - **Toàn bộ 11.172 âm tiết**, phím được dựng từ bảng viết riêng trong file test: mỗi âm tiết gõ một mình, thêm ㅇㅏ phía sau (phụ âm cuối giữ nguyên), và thêm ㅏ phía sau (phụ âm cuối tách đúng).
  - 20.000 từ ngẫu nhiên (250.522 phím). Sau mỗi phím, chữ trên "màn hình" (áp các phép sửa) phải đúng bằng `compose()` của các phím đã gõ, và mọi ký tự phải là Hangul. **Enter không bao giờ bị engine xử lý.**
  - API C: chuyển sang tiếng Hàn, gõ, Backspace, Enter, rồi chuyển lại tiếng Việt (`aa` → â).
- Thử đột biến: bỏ cặp ㄹ+ㄱ → ㄺ thì 801 kiểm tra hỏng, nghĩa là bài test bắt được lỗi quy tắc thật.

Thống kê cách gửi phím: **100% phím tiếng Hàn phải viết lại** (phím Latin sinh ra jamo, nên không bao giờ "để phím gốc đi qua" được). Trung bình mỗi phím cần 0,33 lần xoá và 1,04 ký tự chèn. Với tiếng Việt, phần lớn phím đi qua nguyên vẹn.

## 6. Có tránh được lỗi Enter không

**Đã kiểm chứng (ở lõi):** sau mỗi phím, chữ trên màn hình đã là chữ cuối cùng. Khi gặp Enter, engine trả "không xử lý": event tap để phím Enter gốc đi qua, không gửi phép sửa và không gửi lại bản sao của Enter (tiếng Việt thì có thể phải làm cả hai, ví dụ `thuowr` → thuở). Ứng dụng không nhận `setMarkedText`, `compositionstart` hay `compositionend`; với ứng dụng, mọi phím đều có `isComposing = false`.

**Chưa kiểm chứng (cần máy Mac):**

1. **Tranh chấp thứ tự** giữa các sự kiện Dokey tự gửi và phím người dùng gõ tiếp theo, trong Chromium và Electron. Tiếng Việt từng gặp lỗi rơi chữ kiểu này (mục mã phím trong `KeyboardTap.swift`). Tiếng Hàn viết lại mọi phím, nên mức phơi nhiễm lớn hơn nhiều.
2. **Terminal trong VS Code:** nhóm Electron bôi đen bằng Shift+←, nhưng trong xterm.js Shift+← là chuỗi escape (hạn chế đã ghi trong `docs/TESTING.md`). Claude Code thường chạy ở đây. Bản thử chọn cách đơn giản: ở chế độ tiếng Hàn, **cả** VS Code và các bản fork (VSCodium, Cursor, Windsurf) đều xoá bằng Backspace. Chế độ tiếng Việt vẫn giữ như cũ. Cách này cũng áp dụng cho trình soạn thảo và ô chat của tiện ích Claude Code, nên cần thử xem hai nơi đó có bỏ qua Backspace tổng hợp không. Muốn chỉ áp dụng cho terminal thì phải hỏi phần tử đang có focus qua Accessibility, nhưng khi bị hỏi như vậy VS Code có thể tự bật chế độ dành cho trình đọc màn hình.
3. **Đọc phím theo bố cục:** ở chế độ tiếng Hàn, chữ cái được đọc theo mã phím (`kVK_ANSI_*`, xem `KeyCode.usLetter`), nên không phụ thuộc vào bố cục, và Caps Lock bị bỏ qua. Phím không phải chữ (số, dấu câu) vẫn đọc theo bố cục hiện tại. Người dùng vẫn phải đặt nguồn nhập là ABC thay vì bộ gõ Hàn của Apple.
4. **Phím chuyển 한/영:** người Hàn quen dùng Caps Lock, phím Cmd phải hoặc Ctrl+Space. Phím chuyển hiện tại của Dokey là ⌃⇧ hoặc tổ hợp tự đặt.
5. **Warp và các trình soạn thảo riêng:** chưa biết Warp xử lý Backspace tổng hợp và sự kiện mang chuỗi Unicode thế nào.
6. Chưa có Hanja (phím 한자), chưa có 세벌식.

## 7. Thử trên Mac cần những gì

1. ~~Một nhánh nối `HangulEngine` vào `KeyboardTap.swift`, bật bằng một khoá ẩn, đọc phím chữ theo mã phím, và dùng Backspace trong VS Code.~~ Đã làm trên nhánh `hangul-prototype`; cách thử ở mục 8.
2. Một máy Mac: Apple Silicon và macOS 15 là chính, thêm một máy Intel macOS 14 cho cấu hình máy chậm. Cài Claude Code, VS Code, Chrome, Warp, Terminal.app (có iTerm2 càng tốt).
3. **Tái hiện lỗi gốc trước:** gõ bằng bộ gõ 2-Set Korean của Apple trong từng ứng dụng, ghi lại tỉ lệ mất hoặc lặp âm tiết cuối. Không có số đối chứng này thì không chứng minh được Dokey tốt hơn.
4. Bộ câu thử, mỗi câu kết thúc bằng Enter: câu mở (가), có phụ âm cuối (한국), phụ âm cuối kép (값, 닭, 않), ㄲ/ㅆ (깎, 있어요), nguyên âm ghép (과, 의), và một câu dài. Gõ ở 8–120 ms/phím bằng phím giả lập mức HID như các lần thử bản 0.3, khoảng 50 lượt mỗi ứng dụng. Thêm vài lượt do một người Hàn gõ thật với tốc độ nhanh (có chồng phím).
5. Ma trận ứng dụng: Claude Code CLI trong Terminal, Warp và terminal VS Code; ô chat của tiện ích Claude Code trong VS Code; trình soạn thảo VS Code; Chrome (textarea, contenteditable, ProseMirror trên claude.ai, Google Docs, thanh địa chỉ); Claude Desktop.
6. So nội dung thật sự được gửi đi với câu mong đợi. Đối chiếu với nhật ký `debugLog` của Dokey để biết lỗi nằm ở engine hay ở khâu gửi phím.
7. Nhờ một người bản ngữ xem lại quy tắc ở mục 4, nhất là cách Backspace xử lý `가바 ⌫`.

## 8. Cách thử trên Mac

Phần Swift **chưa được biên dịch lần nào** (máy làm bản thử chạy Windows). `build.sh` tự chạy `Dokey --self-test` sau khi build. Bộ self-test có thêm 4 mục cho tiếng Hàn (`korean`, `korean split`, `korean key codes`, `vscode`). Nếu Swift lỗi, lỗi sẽ hiện ngay ở bước build hoặc self-test.

### Build và cài

```bash
git clone https://github.com/dhtoan/Dokey.git && cd Dokey   # hoặc: git fetch origin
git checkout hangul-prototype
apps/macos/build.sh --dmg
bash apps/macos/install.sh apps/macos/build/Dokey-0.4.0.dmg
```

Bản build ký ad-hoc, nên mỗi lần build lại thì macOS coi Dokey là app mới. Nếu gõ không ra gì, cấp lại quyền Trợ năng: `tccutil reset Accessibility com.dhtoan.dokey.mac`, mở lại Dokey, rồi bật Dokey trong Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Trợ năng.

### Bật, tắt tiếng Hàn

```bash
defaults write com.dhtoan.dokey.mac language -string ko    # bật tiếng Hàn (có tác dụng sau tối đa 2 giây, không cần mở lại app)
defaults delete com.dhtoan.dokey.mac language              # về tiếng Việt
defaults write com.dhtoan.dokey.mac debugLog -bool true    # tuỳ chọn: ghi nhật ký vào ~/Library/Logs/Dokey.log
```

- Nguồn nhập của macOS phải là **ABC** (hoặc U.S.), không phải bộ gõ 2-Set Korean của Apple.
- Phím chuyển của Dokey (mặc định ⌃⇧) đóng vai trò 한/영: bật thì gõ tiếng Hàn, tắt thì gõ chữ Latin. Biểu tượng trên thanh menu vẫn là biểu tượng tiếng Việt.
- Bảng điều khiển của Dokey chưa biết gì về tiếng Hàn. Ô "Gõ thử" trong bảng điều khiển vẫn gõ tiếng Hàn được.

### Ca thử (gõ trên bố cục ABC, ⏎ = Enter)

| Phím | Mong đợi | Kiểm tra gì |
|---|---|---|
| `dkssudgktpdy⏎` | 안녕하세요 | Âm tiết mở ở cuối |
| `gksrnr⏎` | 한국 | Phụ âm cuối |
| `rkqt⏎` | 값 | Phụ âm cuối kép |
| `dlTdjdy⏎` | 있어요 | ㅆ, tách âm tiết |
| `rhkwk⏎` | 과자 | Nguyên âm ghép |
| `rkatkgkqslek⏎` | 감사합니다 | Câu dài, nhiều lần tách |
| `gks⌫⏎` | 하 | Backspace bỏ một jamo |
| `gks` ⌃⇧ `abc` ⌃⇧ `rk⏎` | 한abc가 | Phím chuyển 한/영 giữa câu |

Thử mỗi ca khoảng 20 lần trong từng ứng dụng, gõ nhanh. Ghi lại nội dung **thật sự được gửi đi** (tin nhắn trong lịch sử chat, dòng lệnh shell nhận được), không chỉ nhìn ô nhập.

- **Claude Code:** trong Terminal.app, Warp, iTerm2 và terminal tích hợp của VS Code.
- **VS Code:** trình soạn thảo, và ô chat của tiện ích Claude Code. Hai nơi này nay xoá bằng Backspace thay vì bôi đen, cần xem có bị bỏ sót chữ không.
- **Chrome:** chatgpt.com và claude.ai (ProseMirror), một textarea thường, Google Docs, thanh địa chỉ.
- **Claude Desktop.**
- **Ô mật khẩu:** ô đăng nhập trên Chrome/Safari, hoặc `sudo -v` trong Terminal. macOS bật secure input nên Dokey không thấy phím: mong đợi là chữ Latin đúng như gõ, không có jamo. Sau khi rời ô mật khẩu, tiếng Hàn phải chạy lại.
- **Đối chứng:** chuyển nguồn nhập sang 2-Set Korean của Apple, tắt Dokey (⌃⇧), rồi chạy lại các ca có Enter trong cùng ứng dụng. Ghi tỉ lệ mất hoặc lặp âm tiết cuối để so với Dokey.
- **Hồi quy tiếng Việt:** chạy `defaults delete com.dhtoan.dokey.mac language`, rồi gõ `tieengs Vieetj ` và `dduowngf ` trong vài ứng dụng trên. Kết quả phải giống bản 0.4.0.
