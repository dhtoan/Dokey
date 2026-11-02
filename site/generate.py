#!/usr/bin/env python3
# Generates the Dokey website (Vietnamese, English and Korean pages, sitemap, robots,
# llms.txt) from one set of content, so the visible FAQ and the schema.org
# FAQPage data always match. Run: python3 site/generate.py
#
# Copyright (c) 2026 Do Huy Toan (dhtoan). All rights reserved. See LICENSE.
import html
import json
import os
import re

BASE = "https://dhtoan.github.io/Dokey/"
REPO = "https://github.com/dhtoan/Dokey"
RELEASES = REPO + "/releases/latest"
VERSION = "0.4.0"
QR_BANK = "https://img.vietqr.io/image/TCB-6868686139-compact.svg?addInfo=dokey&amp;accountName=App+Dokey"
HERE = os.path.dirname(os.path.abspath(__file__))

with open(os.path.join(HERE, "..", "CMakeLists.txt"), encoding="utf-8") as f:
    m = re.search(r"project\(DokeyCore VERSION ([0-9.]+)", f.read())
    if m:
        VERSION = m.group(1)

CONTENT = {
    "vi": {
        "path": "",
        "lang": "vi",
        "title": "Dokey – Bộ gõ tiếng Việt cho Mac và Windows, không nhảy chữ, không mất chữ",
        "description": "Dokey là bộ gõ tiếng Việt miễn phí cho macOS và Windows: Telex, VNI, kiểm tra chính tả, "
                       "không nhảy chữ trong Chrome, Edge, ChatGPT, Claude. Gõ tắt, Quick Telex, giữ nguyên từ tiếng Anh.",
        "nav": [("#tinh-nang", "Tính năng"), ("#tai-ve", "Tải về"), ("#hoi-dap", "Hỏi đáp"), ("#ung-ho", "Ủng hộ")],
        "h1": "Bộ gõ tiếng Việt gõ đúng ngay lần đầu",
        "lead": "Dokey là bộ gõ tiếng Việt miễn phí cho macOS và Windows. Không nhảy chữ, không mất chữ, "
                "kể cả trong Chrome, Edge, ChatGPT, Claude và các ứng dụng Electron. Từ tiếng Anh được giữ nguyên.",
        "cta": ("Tải Dokey miễn phí", "Xem mã nguồn"),
        "chips": ["macOS 10.13+ · Intel & Apple Silicon", "Windows 10/11", "Telex · VNI", f"Phiên bản {VERSION}"],
        "shot_alt": "Bảng điều khiển của bộ gõ Dokey trên macOS",
        "features_title": "Vì sao chọn Dokey?",
        "features_sub": "Viết lại từ con số 0 để giải quyết tận gốc những lỗi khó chịu nhất khi gõ tiếng Việt.",
        "features": [
            ("⚡", "Không nhảy chữ, không mất chữ", "Phím sửa chữ được chèn ngay tại chỗ, luôn đi trước phím bạn gõ tiếp. Trong trình duyệt và Electron, Dokey bôi đen rồi gõ đè cả cụm."),
            ("📖", "Hiểu chính tả tiếng Việt", "Kiểm tra với 3.964 âm tiết. Dấu chỉ được thêm khi kết quả là tiếng Việt hợp lệ."),
            ("🔤", "Giữ nguyên tiếng Anh", "windows, chrome, github, password, session… không bị thêm dấu hay mất chữ."),
            ("✍️", "Gõ dấu tự do", "tieengs, tienges, tiengse đều ra “tiếng”. Gõ xong từ, bấm Backspace để quay lại sửa dấu."),
            ("🚀", "Gõ nhanh", "Gõ tắt (vn → Việt Nam), Quick Telex (cc → ch, nn → ng), hoàn tác bằng Esc."),
            ("🔒", "Riêng tư, nhẹ", "Chạy hoàn toàn trên máy, không kết nối mạng, không thu thập dữ liệu, không lưu phím gõ."),
        ],
        "examples_title": "Gõ thử Telex và VNI",
        "examples": [("Telex", "dduowngf → đường · nguoiwf → người · Haxy → Hãy · DDawks Lawks → Đắk Lắk"),
                     ("VNI", "d9u7o7ng2 → đường · Vie65t Nam → Việt Nam")],
        "download_title": "Tải về",
        "download_sub": "Miễn phí cho người dùng cá nhân.",
        "mac": ("🍎 macOS", "Mở Terminal, chạy lệnh dưới đây rồi bật Dokey trong Cài đặt › Quyền riêng tư & Bảo mật › Trợ năng. Hoặc tải file .dmg ở trang Releases."),
        "win": ("🪟 Windows", "Tải Dokey-<phiên bản>-Windows-Setup.exe ở trang Releases (x86, x64, ARM64). Nếu SmartScreen cảnh báo, chọn More info → Run anyway."),
        "faq_title": "Câu hỏi thường gặp",
        "faq": [
            ("Bộ gõ tiếng Việt nào tốt cho Mac?",
             "Dokey là bộ gõ tiếng Việt miễn phí cho macOS 10.13 trở lên, chạy trên cả Intel và Apple Silicon. Dokey hỗ trợ Telex, VNI, kiểm tra chính tả, giữ nguyên từ tiếng Anh, và được thiết kế để không nhảy chữ trong Chrome, Edge, Safari, ChatGPT, Claude, Notion và VS Code."),
            ("Vì sao gõ tiếng Việt trên Chrome hay bị nhảy chữ, và Dokey sửa thế nào?",
             "Chrome và các ứng dụng Electron xử lý phím ở một tiến trình riêng, nên phím xoá và chữ mới có thể đến lệch thứ tự hoặc bị bỏ qua. Dokey chèn phím sửa ngay tại vị trí bắt phím, bôi đen chữ cũ rồi gõ đè cả cụm trong một lần, và không dùng mã phím của phím bạn đang giữ."),
            ("Gõ tiếng Việt trong ChatGPT hoặc Claude bị mất chữ (Hãy thành Hy) phải làm sao?",
             "Đây là lỗi thường gặp với các ô soạn thảo kiểu ProseMirror khi bộ gõ gửi phím Backspace và chữ thay thế. Dokey 0.3.2 trở lên đã sửa lỗi này; chỉ cần cài Dokey và cấp quyền Trợ năng."),
            ("Dokey có miễn phí không?",
             "Có. Dokey miễn phí cho người dùng cá nhân, không quảng cáo và không có bản trả phí. Người dùng có thể ủng hộ tự nguyện để Dokey có chữ ký số của Apple."),
            ("Dokey có an toàn không, có ghi lại phím gõ không?",
             "Dokey chạy hoàn toàn trên máy, không kết nối mạng và không lưu phím gõ. Dokey cần quyền Trợ năng trên macOS vì mọi bộ gõ kiểu bắt phím đều cần quyền này để sửa chữ."),
            ("Dokey có gõ được Telex và VNI không?",
             "Có. Dokey hỗ trợ Telex và VNI, Unicode dựng sẵn và Unicode tổ hợp, đặt dấu kiểu mới (hoà, khoẻ) hoặc kiểu cũ (hòa, khỏe)."),
            ("Dokey có dùng mã nguồn của Unikey hay OpenKey không?",
             "Không. Dokey được viết mới hoàn toàn với lõi Dokey Core bằng C++17 và không chứa mã của bộ gõ nào khác."),
            ("Làm sao chuyển nhanh giữa tiếng Việt và tiếng Anh?",
             "Trên Mac bấm rồi thả Control + Shift (⌃⇧), trên Windows bấm Ctrl + Shift. Dokey còn nhớ chế độ Anh/Việt riêng cho từng ứng dụng."),
        ],
        "sponsor_title": "Ủng hộ Dokey",
        "sponsor_text": "Dokey luôn miễn phí. Nếu Dokey giúp bạn gõ tiếng Việt dễ chịu hơn, mời tác giả một ly cà phê. "
                        "Mục tiêu 99 USD/năm (khoảng 2.600.000 đ) cho tài khoản Apple Developer, để Dokey cài không cảnh báo "
                        "và không phải cấp lại quyền Trợ năng sau mỗi lần cập nhật.",
        "qr": [("Chuyển khoản ngân hàng", "Techcombank · App Dokey · nội dung dokey", QR_BANK),
               ("Ví MoMo", "Quét bằng MoMo hoặc app ngân hàng", "assets/momo.png")],
        "footer": "© 2026 Đỗ Huy Toàn (dhtoan). Phần mềm độc quyền, cấm sao chép, sửa đổi, phân phối lại.",
    },
    "en": {
        "path": "en/",
        "lang": "en",
        "title": "Dokey – Vietnamese input method for Mac and Windows, no jumbled or lost letters",
        "description": "Dokey is a free Vietnamese input method (keyboard) for macOS and Windows: Telex, VNI, spell checking, "
                       "no jumbled letters in Chrome, Edge, ChatGPT or Claude. Text shortcuts, Quick Telex, English words kept.",
        "nav": [("#features", "Features"), ("#download", "Download"), ("#faq", "FAQ"), ("#support", "Support")],
        "h1": "Vietnamese typing, right the first time",
        "lead": "Dokey is a free Vietnamese input method for macOS and Windows. No jumbled or lost letters, even in "
                "Chrome, Edge, ChatGPT, Claude and Electron apps. English words stay as typed.",
        "cta": ("Download Dokey free", "View the source"),
        "chips": ["macOS 10.13+ · Intel & Apple Silicon", "Windows 10/11", "Telex · VNI", f"Version {VERSION}"],
        "shot_alt": "The Dokey Vietnamese input method control panel on macOS",
        "features_title": "Why Dokey?",
        "features_sub": "Rewritten from scratch to fix the most annoying Vietnamese typing bugs at the root.",
        "features": [
            ("⚡", "No jumbled or lost letters", "Corrections are inserted right where keys are captured, always ahead of your next key. In browsers and Electron apps Dokey selects and types over the whole replacement."),
            ("📖", "Understands Vietnamese spelling", "Checks against 3,964 syllables; marks are only added when the result is valid Vietnamese."),
            ("🔤", "Keeps English words", "windows, chrome, github, password, session… get no accents and lose no letters."),
            ("✍️", "Free mark placement", "tieengs, tienges and tiengse all give “tiếng”. After a word, press Backspace to go back and fix its marks."),
            ("🚀", "Quick typing", "Text shortcuts (vn → Việt Nam), Quick Telex (cc → ch, nn → ng), undo with Esc."),
            ("🔒", "Private and light", "Runs entirely on your machine: no network, no data collection, no keystroke logging."),
        ],
        "examples_title": "Telex and VNI examples",
        "examples": [("Telex", "dduowngf → đường · nguoiwf → người · Haxy → Hãy · DDawks Lawks → Đắk Lắk"),
                     ("VNI", "d9u7o7ng2 → đường · Vie65t Nam → Việt Nam")],
        "download_title": "Download",
        "download_sub": "Free for personal use.",
        "mac": ("🍎 macOS", "Open Terminal, run the command below, then enable Dokey in System Settings › Privacy & Security › Accessibility. Or download the .dmg from Releases."),
        "win": ("🪟 Windows", "Download Dokey-<version>-Windows-Setup.exe from Releases (x86, x64, ARM64). If SmartScreen warns, choose More info → Run anyway."),
        "faq_title": "FAQ",
        "faq": [
            ("What is a good Vietnamese input method for Mac?",
             "Dokey is a free Vietnamese input method for macOS 10.13 and later, on Intel and Apple Silicon. It supports Telex and VNI, spell checking, keeps English words as typed, and is built to avoid jumbled letters in Chrome, Edge, Safari, ChatGPT, Claude, Notion and VS Code."),
            ("Why does Vietnamese typing jumble letters in Chrome, and how does Dokey fix it?",
             "Chrome and Electron apps handle keys in a separate process, so the delete keys and the new text can arrive out of order or be dropped. Dokey inserts corrections right at the capture point, selects the old letters and types the whole replacement in one go, and never uses the code of a key that is still held."),
            ("Typing Vietnamese in ChatGPT or Claude loses letters (Hãy becomes Hy). What can I do?",
             "This is a common problem with ProseMirror-style editors when an input method sends Backspaces and replacement text. Dokey 0.3.2 and later fix it; install Dokey and grant Accessibility permission."),
            ("Is Dokey free?",
             "Yes. Dokey is free for personal use, with no ads and no paid tier. Users can support it voluntarily so Dokey can be signed by Apple."),
            ("Is Dokey safe? Does it record keystrokes?",
             "Dokey runs entirely on your machine, makes no network connections and stores no keystrokes. It needs Accessibility permission on macOS because every key-capturing input method does."),
            ("Does Dokey support Telex and VNI?",
             "Yes: Telex and VNI, precomposed and combining Unicode, modern (hoà, khoẻ) or traditional (hòa, khỏe) tone placement."),
            ("Does Dokey use Unikey or OpenKey code?",
             "No. Dokey is written entirely from scratch around its own C++17 engine, Dokey Core, and contains no code from any other input method."),
            ("How do I switch between Vietnamese and English?",
             "On Mac press and release Control + Shift (⌃⇧); on Windows press Ctrl + Shift. Dokey also remembers the mode for each app."),
        ],
        "sponsor_title": "Support Dokey",
        "sponsor_text": "Dokey is and will stay free. If it makes your Vietnamese typing nicer, buy the author a coffee. "
                        "The goal is 99 USD a year for an Apple Developer account, so Dokey installs without warnings "
                        "and keeps its Accessibility permission across updates.",
        "qr": [("Bank transfer (Vietnam)", "Techcombank · App Dokey · note dokey", QR_BANK),
               ("MoMo wallet", "Scan with MoMo or a banking app", "../assets/momo.png")],
        "footer": "© 2026 Do Huy Toan (dhtoan). Proprietary software: copying, modification and redistribution prohibited.",
    },
    "ko": {
        "path": "ko/",
        "lang": "ko",
        "title": "Dokey – 글자가 씹히지 않는 맥(macOS) 한글 입력기 · 두벌식",
        "description": "Dokey는 macOS용 무료 한글 입력기입니다. 두벌식 자판으로 조합 중 밑줄 없이 바로 완성된 글자를 입력해, "
                       "Chrome, Claude, ChatGPT, Notion에서도 한글이 씹히거나 자모가 분리되지 않도록 설계했습니다. 베트남어도 지원합니다.",
        "nav": [("#features", "기능"), ("#download", "다운로드"), ("#faq", "자주 묻는 질문")],
        "h1": "글자가 씹히지 않는 맥 한글 입력기",
        "lead": "Dokey는 macOS용 무료 입력기입니다. 두벌식으로 입력하면 조합 중인 글자에 밑줄 없이 바로 완성된 글자가 나타납니다. "
                "Chrome, Edge, Claude, ChatGPT, Notion 같은 웹·Electron 앱에서도 한글이 씹히거나 자모가 분리되지 않도록 만들었습니다.",
        "cta": ("Dokey 무료 다운로드", "소스 보기"),
        "chips": ["macOS 10.13+ · Intel & Apple Silicon", "두벌식", "한국어 베타", f"버전 {VERSION}"],
        "shot_alt": "Dokey 한글 입력기 제어판 (macOS)",
        "shot": "ko-dashboard.png",
        "gallery": [("ko-typing.png", "Dokey 입력 방식 설정: 한국어 두벌식, 베트남어 Telex·VNI")],
        "social": "assets/ko-social.png",
        "features_title": "왜 Dokey인가요?",
        "features_sub": "웹과 Electron 앱에서 자주 겪는 한글 입력 문제를 처음부터 다시 설계해 해결했습니다.",
        "features": [
            ("⚡", "글자 씹힘 방지", "키를 누를 때마다 음절 전체를 다시 조합하고, 바뀐 글자만 입력 위치에서 바로 고칩니다."),
            ("✍️", "밑줄 없는 즉시 입력", "조합 중 밑줄(마크드 텍스트)을 쓰지 않아, Enter를 눌러도 마지막 글자가 두 번 입력되지 않도록 설계했습니다."),
            ("⌨️", "표준 두벌식", "키 위치로 읽기 때문에 키보드 배열과 관계없이 정확합니다. Shift + q w e r t로 ㅃ ㅉ ㄸ ㄲ ㅆ."),
            ("⌫", "자모 단위 지우기", "Backspace는 한 자모씩 지웁니다: 한 → 하 → ㅎ."),
            ("🇻🇳", "베트남어도 함께", "Telex·VNI 베트남어 입력과 맞춤법 검사를 같은 앱에서. 메뉴 막대에서 바로 전환하세요."),
            ("🔒", "개인정보 보호", "모든 처리는 Mac 안에서만 이루어집니다. 네트워크 연결도, 키 입력 기록도 없습니다."),
        ],
        "examples_title": "입력 예시",
        "examples": [("두벌식", "dkssudgktpdy → 안녕하세요 · rkatkgkqslek → 감사합니다 · gksrnr → 한국"),
                     ("베트남어 Telex", "Vieetj Nam → Việt Nam · dduowngf → đường")],
        "download_title": "다운로드",
        "download_sub": "개인 사용자는 무료입니다.",
        "mac": ("🍎 macOS", "터미널에서 아래 명령을 실행한 뒤 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 Dokey를 켜세요. "
                           "그다음 메뉴 막대의 Dokey 아이콘 › 입력 언어 › 한국어를 고르고, macOS 입력 소스는 ABC로 두세요."),
        "win": ("🪟 Windows", "Windows용 Dokey는 현재 베트남어를 지원합니다. 한국어 지원은 준비 중입니다."),
        "faq_title": "자주 묻는 질문",
        "faq": [
            ("맥에서 Chrome이나 Claude를 쓸 때 한글이 씹히는 이유는 무엇인가요?",
             "Chrome과 Electron 앱은 키 입력을 별도 프로세스에서 처리하기 때문에, 입력기가 보낸 수정 키와 새 글자가 어긋나거나 사라질 수 있습니다. "
             "Dokey는 수정할 글자만 입력 위치에서 바로 선택해 덮어쓰고, 사용자가 누르고 있는 키의 코드를 쓰지 않아 글자 씹힘을 줄였습니다."),
            ("Enter를 누르면 마지막 글자가 중복되거나 자모가 분리돼요. Dokey는 어떤가요?",
             "이 문제는 보통 조합 중인 글자(밑줄 표시)를 앱이 제대로 확정하지 못해 생깁니다. Dokey는 조합 중 밑줄을 쓰지 않고 항상 완성된 글자를 바로 입력하므로, "
             "이런 유형의 문제가 생기지 않도록 설계되었습니다."),
            ("Dokey는 무료인가요?",
             "네. 개인 사용자는 무료로 사용할 수 있고, 광고나 유료 버전이 없습니다."),
            ("Dokey는 안전한가요? 키 입력을 기록하나요?",
             "Dokey는 Mac 안에서만 동작하며 네트워크에 연결하지 않고 키 입력을 저장하지도 않습니다. macOS에서 키를 받아 고치려면 모든 입력기와 마찬가지로 손쉬운 사용 권한이 필요합니다."),
            ("어떤 자판을 지원하나요?",
             "한국어는 표준 두벌식을 지원합니다. 세벌식은 아직 지원하지 않습니다. 베트남어는 Telex와 VNI를 지원합니다."),
            ("한글과 영문은 어떻게 전환하나요?",
             "Control + Shift(⌃⇧)를 눌렀다 떼면 한글과 영문이 바뀝니다. 다른 단축키로 바꿀 수 있고, 앱마다 마지막 모드를 기억합니다."),
            ("macOS 기본 한글 입력기와 함께 써도 되나요?",
             "Dokey를 쓸 때는 macOS 입력 소스를 ABC(또는 U.S.)로 두세요. 기본 2벌식 입력 소스가 켜져 있으면 두 입력기가 동시에 조합하게 됩니다."),
        ],
        "sponsor_title": "Dokey 응원하기",
        "sponsor_text": "Dokey는 앞으로도 무료입니다. 마음에 드셨다면 GitHub에 ⭐를 눌러 주시고, 주변에 소개해 주세요. "
                        "버그나 잘 안 되는 앱이 있으면 GitHub Issues로 알려 주시면 바로 고치겠습니다.",
        "qr": [],
        "footer": "© 2026 Do Huy Toan (dhtoan). 독점 소프트웨어: 복제, 수정, 재배포를 금지합니다.",
    },
}

INSTALL = "gh release download -R dhtoan/Dokey --pattern install-macos.sh --dir /tmp --clobber &amp;&amp; bash /tmp/install-macos.sh"


LANGS = [("vi", "", "Tiếng Việt"), ("en", "en/", "English"), ("ko", "ko/", "한국어")]
LOCALES = {"vi": "vi_VN", "en": "en_US", "ko": "ko_KR"}


def page(c):
    url = BASE + c["path"]
    up = "" if c["path"] == "" else "../"
    switch = "".join(f'<a href="{up}{p}" hreflang="{l}">{name}</a>' for l, p, name in LANGS if l != c["lang"])
    hreflang = "\n".join(f'<link rel="alternate" hreflang="{l}" href="{BASE}{p}">' for l, p, _ in LANGS)
    social = BASE + c.get("social", "assets/social.png")
    assets = "assets/" if c["path"] == "" else "../assets/"
    e = html.escape
    software = {
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": "Dokey",
        "alternateName": "Bộ gõ tiếng Việt Dokey",
        "description": c["description"],
        "applicationCategory": "UtilitiesApplication",
        "applicationSubCategory": "Vietnamese input method",
        "operatingSystem": "macOS 10.13+, Windows 10, Windows 11",
        "softwareVersion": VERSION,
        "inLanguage": ["vi", "en", "ko"],
        "url": BASE,
        "downloadUrl": RELEASES,
        "image": social,
        "screenshot": BASE + "assets/dashboard.png",
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "VND"},
        "author": {"@type": "Person", "name": "Do Huy Toan", "alternateName": "dhtoan", "url": "https://github.com/dhtoan"},
        "subjectOf": {"@type": "ScholarlyArticle", "name": "Dokey: A Vietnamese Input Method That Rebuilds the Whole Word on Every Keystroke", "url": "https://doi.org/10.5281/zenodo.23888629", "datePublished": "2026-11-02"},
        "keywords": ("맥 한글 입력기, macOS 한글 입력기, 두벌식, 한글 씹힘, 자모 분리, Korean input method, Mac"
                     if c["lang"] == "ko" else
                     "bộ gõ tiếng Việt, gõ tiếng Việt trên Mac, Telex, VNI, Vietnamese keyboard, Vietnamese input method, macOS, Windows"),
    }
    faq = {
        "@context": "https://schema.org",
        "@type": "FAQPage",
        "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in c["faq"]],
    }
    ld = lambda o: '<script type="application/ld+json">' + json.dumps(o, ensure_ascii=False) + "</script>"
    ids = {"vi": ("tinh-nang", "tai-ve", "hoi-dap", "ung-ho"), "en": ("features", "download", "faq", "support"),
           "ko": ("features", "download", "faq", "support")}[c["lang"]]

    feats = "\n".join(f'<div class="card"><span class="ic" aria-hidden="true">{i}</span><h3>{e(t)}</h3><p>{e(d)}</p></div>'
                      for i, t, d in c["features"])
    examples = "\n".join(f"<tr><th>{e(k)}</th><td><code>{e(v)}</code></td></tr>" for k, v in c["examples"])
    faqs = "\n".join(f"<details><summary>{e(q)}</summary><p>{e(a)}</p></details>" for q, a in c["faq"])
    qrs = "\n".join(f'<div class="qr"><img src="{src}" alt="{e(title)}" loading="lazy"><b>{e(title)}</b><br>{e(note)}</div>'
                    for title, note, src in c["qr"])
    nav = "".join(f'<a href="{h}">{e(t)}</a>' for h, t in c["nav"])
    gallery = "\n".join(f'    <img src="{assets}{src}" alt="{e(alt)}" loading="lazy">'
                         for src, alt in c.get("gallery", [("typing.png", "Dokey: Telex, VNI"), ("windows.jpg", "Dokey Windows")]))
    return f"""<!doctype html>
<html lang="{c['lang']}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(c['title'])}</title>
<meta name="description" content="{e(c['description'])}">
<meta name="author" content="Do Huy Toan (dhtoan)">
<meta name="robots" content="index, follow, max-image-preview:large">
<link rel="canonical" href="{url}">
{hreflang}
<link rel="alternate" hreflang="x-default" href="{BASE}">
<link rel="icon" href="{assets}icon.png">
<link rel="apple-touch-icon" href="{assets}icon.png">
<meta name="theme-color" content="#4f1c9e">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Dokey">
<meta property="og:locale" content="{LOCALES[c['lang']]}">
<meta property="og:title" content="{e(c['title'])}">
<meta property="og:description" content="{e(c['description'])}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{social}">
<meta property="og:image:width" content="1280">
<meta property="og:image:height" content="640">
<meta property="og:image:alt" content="{e(c['shot_alt'])}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{e(c['title'])}">
<meta name="twitter:description" content="{e(c['description'])}">
<meta name="twitter:image" content="{social}">
<link rel="stylesheet" href="{'style.css' if c['path'] == '' else '../style.css'}">
{ld(software)}
{ld(faq)}
</head>
<body>
<div class="wrap">
<nav aria-label="Main">
  <a class="brand" href="{url}"><img src="{assets}icon.png" alt="" width="34" height="34">Dokey</a>
  <div class="links">{nav}{switch}</div>
</nav>

<header class="hero">
  <div>
    <h1>{e(c['h1'])}</h1>
    <p class="lead">{e(c['lead'])}</p>
    <div class="btns">
      <a class="btn primary" href="#{ids[1]}">⬇ {e(c['cta'][0])}</a>
      <a class="btn ghost" href="{REPO}">{e(c['cta'][1])}</a>
    </div>
    <div class="chips">{''.join(f'<span class="chip">{e(x)}</span>' for x in c['chips'])}</div>
  </div>
  <img class="shot" src="{assets}{c.get('shot', 'dashboard.png')}" alt="{e(c['shot_alt'])}" width="1458" height="918">
</header>

<main>
<section id="{ids[0]}">
  <h2>{e(c['features_title'])}</h2>
  <p class="sub">{e(c['features_sub'])}</p>
  <div class="grid">
{feats}
  </div>
</section>

<section>
  <h2>{e(c['examples_title'])}</h2>
  <table>{examples}</table>
  <div class="two" style="margin-top:18px">
{gallery}
  </div>
</section>

<section id="{ids[1]}">
  <h2>{e(c['download_title'])}</h2>
  <p class="sub">{e(c['download_sub'])} <a href="{RELEASES}">GitHub Releases</a></p>
  <div class="two">
    <div class="card"><h3>{e(c['mac'][0])}</h3><p>{e(c['mac'][1])}</p><pre><code>{INSTALL}</code></pre></div>
    <div class="card"><h3>{e(c['win'][0])}</h3><p>{e(c['win'][1])}</p><p style="margin-top:14px"><a class="btn primary" href="{RELEASES}">⬇ Setup.exe</a></p></div>
  </div>
</section>

<section id="{ids[2]}">
  <h2>{e(c['faq_title'])}</h2>
{faqs}
</section>

<section id="{ids[3]}">
  <h2>{e(c['sponsor_title'])}</h2>
  <div class="sponsor"{' style="display:block"' if not c['qr'] else ''}>
{qrs}
    <p class="sub">{e(c['sponsor_text'])}</p>
  </div>
</section>
</main>

<footer>{e(c['footer'])} · <a href="{REPO}">GitHub</a> · <a href="{REPO}/blob/main/LICENSE">License</a> · <a href="https://doi.org/10.5281/zenodo.23888629">Paper (DOI)</a></footer>
</div>
</body>
</html>
"""


def main():
    for c in CONTENT.values():
        out = os.path.join(HERE, c["path"], "index.html")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "w", encoding="utf-8") as f:
            f.write(page(c))
    with open(os.path.join(HERE, "sitemap.xml"), "w", encoding="utf-8") as f:
        f.write(f"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
  <url><loc>{BASE}</loc><xhtml:link rel="alternate" hreflang="en" href="{BASE}en/"/><xhtml:link rel="alternate" hreflang="ko" href="{BASE}ko/"/></url>
  <url><loc>{BASE}en/</loc><xhtml:link rel="alternate" hreflang="vi" href="{BASE}"/><xhtml:link rel="alternate" hreflang="ko" href="{BASE}ko/"/></url>
  <url><loc>{BASE}ko/</loc><xhtml:link rel="alternate" hreflang="vi" href="{BASE}"/><xhtml:link rel="alternate" hreflang="en" href="{BASE}en/"/></url>
</urlset>
""")
    with open(os.path.join(HERE, "robots.txt"), "w", encoding="utf-8") as f:
        f.write(f"User-agent: *\nAllow: /\n\nSitemap: {BASE}sitemap.xml\n")
    vi = CONTENT["vi"]
    with open(os.path.join(HERE, "llms.txt"), "w", encoding="utf-8") as f:
        f.write(f"""# Dokey

> Dokey is a free Vietnamese and Korean input method (bộ gõ tiếng Việt, 한글 입력기) for macOS 10.13+ (Intel and Apple Silicon) and
> Windows 10/11, by Do Huy Toan (dhtoan). Telex and VNI, spell checking against 3,964 Vietnamese syllables,
> English words kept as typed, and no jumbled or lost letters in Chrome, Edge, ChatGPT, Claude and Electron apps.
> Current version {VERSION}. Proprietary, free for personal use. Written from scratch (no Unikey/OpenKey code).

## Key facts
- Install on macOS: `gh release download -R dhtoan/Dokey --pattern install-macos.sh --dir /tmp --clobber && bash /tmp/install-macos.sh`, then enable Accessibility permission.
- Install on Windows: Dokey-<version>-Windows-Setup.exe from {RELEASES}.
- Switch Vietnamese/English: Control+Shift (Mac), Ctrl+Shift (Windows). Mode remembered per app.
- Korean (macOS, beta): standard 2-beolsik (두벌식) layout, chosen in the menu bar (입력 언어 › 한국어); keep the macOS input source on ABC. Composes without marked text (no underline), so web and Electron apps get finished syllables.
- Features: text shortcuts (vn → Việt Nam), Quick Telex (cc → ch), undo with Esc, Backspace reopens the previous word, Google Docs and Spotlight handling, excluded apps.
- Privacy: runs locally, no network, no keystroke storage.

## Links
- [Website (Vietnamese)]({BASE})
- [Website (English)]({BASE}en/)
- [Website (한국어)]({BASE}ko/)
- [Source and README]({REPO})
- [Releases]({RELEASES})
- [Paper: Dokey: A Vietnamese Input Method That Rebuilds the Whole Word on Every Keystroke (DOI 10.5281/zenodo.23888629)](https://doi.org/10.5281/zenodo.23888629)

## FAQ
""" + "\n".join(f"- **{q}** {a}" for q, a in CONTENT['en']['faq']) + "\n")
    # The same file at the repository root, where AI crawlers of GitHub repos look.
    with open(os.path.join(HERE, "llms.txt"), encoding="utf-8") as src, \
            open(os.path.join(HERE, "..", "llms.txt"), "w", encoding="utf-8") as dst:
        dst.write(src.read())


if __name__ == "__main__":
    main()
