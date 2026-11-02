# Bộ bài chia sẻ Dokey

Bài viết soạn sẵn để giới thiệu Dokey ở từng nơi. Đăng lần lượt từng nơi, cách nhau vài ngày, và trả lời bình luận trong vài giờ đầu: đó là lúc bài dễ được đẩy lên nhất.

**Ảnh dùng kèm**
- `docs/images/social.png` (1280×640): ảnh chính cho mọi bài.
- `docs/images/dashboard.png`, `docs/images/typing.png`: ảnh phụ.
- Video ngắn 15–30 giây gõ "Hãy" trong ChatGPT hoặc Claude, so sánh trước và sau, thường được chia sẻ nhiều hơn ảnh tĩnh.

**Đường dẫn**
- Trang web: https://dhtoan.github.io/dokey/ (sau khi bật GitHub Pages)
- Mã nguồn và tải về: https://github.com/dhtoan/Dokey

> Trước khi đăng: chuyển repo sang công khai và bật trang web, nếu không người đọc sẽ gặp lỗi 404.

---

## 1. Facebook: nhóm Mac, Apple, lập trình

Các nhóm phù hợp: nhóm người dùng macOS và MacBook Việt Nam, nhóm lập trình viên, nhóm dùng ChatGPT/AI.

> **Gõ tiếng Việt trên Mac hay bị nhảy chữ trong Chrome, mất chữ trong ChatGPT ("Hãy" thành "Hy")? Mình viết Dokey để sửa đúng chuyện đó.**
>
> Dokey là bộ gõ tiếng Việt **miễn phí** cho macOS (Intel và Apple Silicon) và Windows, viết lại từ đầu:
> ✅ Không nhảy chữ, không mất chữ trong Chrome, Edge, ChatGPT, Claude, Notion, VS Code
> ✅ Telex, VNI, kiểm tra chính tả, giữ nguyên từ tiếng Anh (windows, github, password…)
> ✅ Gõ xong từ, bấm Backspace để quay lại sửa dấu; gõ tắt `vn` → Việt Nam; Quick Telex
> ✅ Chạy hoàn toàn trên máy, không kết nối mạng, không lưu phím gõ
>
> Cài trên Mac bằng một dòng lệnh (không bị cảnh báo), hướng dẫn ở đây: https://github.com/dhtoan/Dokey
>
> Mọi người dùng thử và báo lỗi giúp mình nhé. Ứng dụng nào còn gõ sai, cứ bình luận tên app và chữ bị sai, mình sửa ngay. 🙏

## 2. Tinh tế, Voz (mục Apple / phần mềm)

**Tiêu đề:** [Chia sẻ] Dokey: bộ gõ tiếng Việt mới cho Mac và Windows, sửa lỗi nhảy chữ trong Chrome và ChatGPT

> Chào anh em,
>
> Mình hay gặp lỗi gõ tiếng Việt bị nhảy chữ trong Chrome và mất chữ trong ô chat ChatGPT/Claude (gõ "Hãy" ra "Hy"), nên viết lại một bộ gõ từ đầu: **Dokey**.
>
> **Vì sao không nhảy chữ:** mỗi phím, Dokey dựng lại cả từ từ chuỗi phím đã gõ; khi cần sửa, nó chèn phím sửa ngay tại chỗ bắt phím. Trong trình duyệt và ứng dụng Electron, nó bôi đen chữ cũ rồi gõ đè cả cụm, và không dùng mã phím của phím bạn đang giữ (đây là nguyên nhân mất chữ khi gõ nhanh).
>
> **Tính năng:** Telex/VNI, kiểm tra chính tả 3.964 âm tiết, giữ từ tiếng Anh, gõ tắt, Quick Telex, hoàn tác bằng Esc, nhớ chế độ Anh/Việt theo ứng dụng, xử lý riêng Google Docs và Spotlight.
>
> **Kiểm thử:** hơn 20.000 ca tự động, kể cả 1.171 từ tiếng Anh phải giữ nguyên và câu tiếng Việt thật.
>
> Miễn phí, chạy cục bộ, không thu thập dữ liệu. Tải: https://github.com/dhtoan/Dokey
>
> Rất mong anh em góp ý, nhất là trên máy cũ và các app ít phổ biến.

## 3. Reddit (r/vietnam, r/macapps, r/MacOS)

**Title:** I built Dokey, a free Vietnamese input method for Mac & Windows that doesn't jumble or drop letters in Chrome/ChatGPT

> Typing Vietnamese on a Mac often goes wrong in Chrome and Electron apps: letters get jumbled, or "Hãy" turns into "Hy" in the ChatGPT/Claude chat box. I wrote **Dokey** from scratch to fix that:
>
> - Rebuilds the whole word on every keystroke, so screen and input method never drift apart
> - Corrections are posted at the event-tap position; in browsers it selects and types over the word
> - Never sends text with the key code of a key you are still holding (this was the cause of the lost letters)
> - Telex/VNI, spell checking, English words kept, text shortcuts, Quick Telex, Esc to undo
> - macOS 10.13+ (Universal) and Windows 10/11, runs locally, no telemetry
>
> Free for personal use: https://github.com/dhtoan/Dokey. Feedback welcome, especially apps where it still misbehaves.

## 4. X (Twitter), Threads

> Gõ tiếng Việt trên Mac không còn nhảy chữ trong Chrome, không mất chữ trong ChatGPT 🎉
> Dokey: bộ gõ tiếng Việt miễn phí cho Mac và Windows, viết lại từ đầu. Telex, VNI, gõ tắt, giữ nguyên từ tiếng Anh.
> 👉 https://github.com/dhtoan/Dokey
> #BoGoTiengViet #macOS #Telex #Vietnamese

## 5. Product Hunt

- **Name:** Dokey
- **Tagline (60 ký tự):** Vietnamese typing for Mac & Windows, without jumbled letters
- **Topics:** Mac, Windows, Productivity, Languages
- **Mô tả:** dùng lại đoạn Reddit ở trên, kèm 3 ảnh: social.png, dashboard.png, typing.png.
- **Lời đầu tiên của tác giả:** kể ngắn vì sao bạn viết Dokey (bị mất chữ khi chat với AI), và mời góp ý.

## 6. Những nơi khác nên gửi

- Các danh sách phần mềm Mac hay (awesome-mac, awesome-macos): gửi pull request thêm Dokey vào mục bàn phím / ngôn ngữ.
- AlternativeTo: đăng Dokey như một lựa chọn thay thế cho Unikey, EVKey, OpenKey, GoTiengViet.
- Homebrew Cask (khi repo công khai và có bản ký số): giúp cài bằng `brew install --cask dokey`.

## Mẹo để được chia sẻ nhiều

- Mở đầu bằng **vấn đề người đọc đang gặp** ("Hãy" thành "Hy"), không phải bằng tên phần mềm.
- Luôn kèm **ảnh hoặc video**. Bài có hình ảnh được chia sẻ nhiều hơn hẳn.
- Nói rõ **miễn phí, riêng tư, không thu dữ liệu**. Với bộ gõ (thứ đọc được mọi phím bấm), đây là điều người đọc quan tâm nhất.
- Trả lời mọi bình luận, kể cả chê, và sửa nhanh lỗi được báo. Người được phản hồi thường quay lại chia sẻ tiếp.
- Không đăng cùng một bài vào nhiều nhóm trong một ngày: dễ bị coi là spam.
