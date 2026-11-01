#!/usr/bin/env python3
# Generates the Dokey website (Vietnamese and English pages, sitemap, robots,
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
        "switch": ("en/", "English"),
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
        "switch": ("../", "Tiếng Việt"),
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
}

INSTALL = "gh release download -R dhtoan/Dokey --pattern install-macos.sh --dir /tmp --clobber &amp;&amp; bash /tmp/install-macos.sh"


def page(c):
    url = BASE + c["path"]
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
        "inLanguage": ["vi", "en"],
        "url": BASE,
        "downloadUrl": RELEASES,
        "image": BASE + "assets/social.png",
        "screenshot": BASE + "assets/dashboard.png",
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "VND"},
        "author": {"@type": "Person", "name": "Do Huy Toan", "alternateName": "dhtoan", "url": "https://github.com/dhtoan"},
        "keywords": "bộ gõ tiếng Việt, gõ tiếng Việt trên Mac, Telex, VNI, Vietnamese keyboard, Vietnamese input method, macOS, Windows",
    }
    faq = {
        "@context": "https://schema.org",
        "@type": "FAQPage",
        "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in c["faq"]],
    }
    ld = lambda o: '<script type="application/ld+json">' + json.dumps(o, ensure_ascii=False) + "</script>"
    ids = {"vi": ("tinh-nang", "tai-ve", "hoi-dap", "ung-ho"), "en": ("features", "download", "faq", "support")}[c["lang"]]

    feats = "\n".join(f'<div class="card"><span class="ic" aria-hidden="true">{i}</span><h3>{e(t)}</h3><p>{e(d)}</p></div>'
                      for i, t, d in c["features"])
    examples = "\n".join(f"<tr><th>{e(k)}</th><td><code>{e(v)}</code></td></tr>" for k, v in c["examples"])
    faqs = "\n".join(f"<details><summary>{e(q)}</summary><p>{e(a)}</p></details>" for q, a in c["faq"])
    qrs = "\n".join(f'<div class="qr"><img src="{src}" alt="{e(title)}" loading="lazy"><b>{e(title)}</b><br>{e(note)}</div>'
                    for title, note, src in c["qr"])
    nav = "".join(f'<a href="{h}">{e(t)}</a>' for h, t in c["nav"])
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
<link rel="alternate" hreflang="vi" href="{BASE}">
<link rel="alternate" hreflang="en" href="{BASE}en/">
<link rel="alternate" hreflang="x-default" href="{BASE}">
<link rel="icon" href="{assets}icon.png">
<link rel="apple-touch-icon" href="{assets}icon.png">
<meta name="theme-color" content="#4f1c9e">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Dokey">
<meta property="og:locale" content="{'vi_VN' if c['lang'] == 'vi' else 'en_US'}">
<meta property="og:title" content="{e(c['title'])}">
<meta property="og:description" content="{e(c['description'])}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{BASE}assets/social.png">
<meta property="og:image:width" content="1280">
<meta property="og:image:height" content="640">
<meta property="og:image:alt" content="{e(c['shot_alt'])}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{e(c['title'])}">
<meta name="twitter:description" content="{e(c['description'])}">
<meta name="twitter:image" content="{BASE}assets/social.png">
<link rel="stylesheet" href="{'style.css' if c['path'] == '' else '../style.css'}">
{ld(software)}
{ld(faq)}
</head>
<body>
<div class="wrap">
<nav aria-label="Main">
  <a class="brand" href="{url}"><img src="{assets}icon.png" alt="" width="34" height="34">Dokey</a>
  <div class="links">{nav}<a href="{c['switch'][0]}" hreflang="{'en' if c['lang'] == 'vi' else 'vi'}">{e(c['switch'][1])}</a></div>
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
  <img class="shot" src="{assets}dashboard.png" alt="{e(c['shot_alt'])}" width="1458" height="918">
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
    <img src="{assets}typing.png" alt="Dokey: Telex, VNI" loading="lazy">
    <img src="{assets}windows.jpg" alt="Dokey Windows" loading="lazy">
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
  <div class="sponsor">
{qrs}
    <p class="sub">{e(c['sponsor_text'])}</p>
  </div>
</section>
</main>

<footer>{e(c['footer'])} · <a href="{REPO}">GitHub</a> · <a href="{REPO}/blob/main/LICENSE">License</a></footer>
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
  <url><loc>{BASE}</loc><xhtml:link rel="alternate" hreflang="en" href="{BASE}en/"/></url>
  <url><loc>{BASE}en/</loc><xhtml:link rel="alternate" hreflang="vi" href="{BASE}"/></url>
</urlset>
""")
    with open(os.path.join(HERE, "robots.txt"), "w", encoding="utf-8") as f:
        f.write(f"User-agent: *\nAllow: /\n\nSitemap: {BASE}sitemap.xml\n")
    vi = CONTENT["vi"]
    with open(os.path.join(HERE, "llms.txt"), "w", encoding="utf-8") as f:
        f.write(f"""# Dokey

> Dokey is a free Vietnamese input method (bộ gõ tiếng Việt) for macOS 10.13+ (Intel and Apple Silicon) and
> Windows 10/11, by Do Huy Toan (dhtoan). Telex and VNI, spell checking against 3,964 Vietnamese syllables,
> English words kept as typed, and no jumbled or lost letters in Chrome, Edge, ChatGPT, Claude and Electron apps.
> Current version {VERSION}. Proprietary, free for personal use. Written from scratch (no Unikey/OpenKey code).

## Key facts
- Install on macOS: `gh release download -R dhtoan/Dokey --pattern install-macos.sh --dir /tmp --clobber && bash /tmp/install-macos.sh`, then enable Accessibility permission.
- Install on Windows: Dokey-<version>-Windows-Setup.exe from {RELEASES}.
- Switch Vietnamese/English: Control+Shift (Mac), Ctrl+Shift (Windows). Mode remembered per app.
- Features: text shortcuts (vn → Việt Nam), Quick Telex (cc → ch), undo with Esc, Backspace reopens the previous word, Google Docs and Spotlight handling, excluded apps.
- Privacy: runs locally, no network, no keystroke storage.

## Links
- [Website (Vietnamese)]({BASE})
- [Website (English)]({BASE}en/)
- [Source and README]({REPO})
- [Releases]({RELEASES})

## FAQ
""" + "\n".join(f"- **{q}** {a}" for q, a in CONTENT['en']['faq']) + "\n")
    # The same file at the repository root, where AI crawlers of GitHub repos look.
    with open(os.path.join(HERE, "llms.txt"), encoding="utf-8") as src, \
            open(os.path.join(HERE, "..", "llms.txt"), "w", encoding="utf-8") as dst:
        dst.write(src.read())


if __name__ == "__main__":
    main()
