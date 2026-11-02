// Dokey for Windows - the control panel window: a violet gradient, an icon
// sidebar and frosted glass cards with glossy emblems. Everything is drawn
// with GDI+ at the monitor's DPI; there are no image resources.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#include "panel.h"

#include <algorithm>
#include <cmath>
#include <cwctype>
#include <string>
#include <vector>

#include <objidl.h>
#include <dwmapi.h>
#include <commctrl.h>
#include <shellapi.h>
#include <windowsx.h>
namespace Gdiplus {
using std::max;
using std::min;
}
#include <gdiplus.h>

#include "dokey/dokey.h"
#include "keyboard.h"
#include "resource.h"
#include "version.h"

using namespace Gdiplus;

namespace dokey_win {

namespace {

const wchar_t kPanelClass[] = L"DokeyPanelWindow";
constexpr float kWidth = 860, kHeight = 500, kSidebar = 68;
constexpr UINT_PTR kRefreshTimer = 1;
constexpr UINT_PTR kMacroSaveTimer = 2;  // saves the macro list shortly after the last edit
constexpr UINT kRefreshMs = 1500;
constexpr DWORD kSlowPauseMs = 30;  // "slow machine" pause in Chromium windows
const COLORREF kWellColor = RGB(78, 37, 140);  // the "Gõ thử" well, also the edit box background

enum Page { PAGE_DASHBOARD, PAGE_TYPING, PAGE_QUICK, PAGE_APPS, PAGE_ABOUT, PAGE_COUNT };
const wchar_t* Title(int page) {
    switch (page) {
        case PAGE_DASHBOARD: return Tr(L"Bảng điều khiển", L"제어판");
        case PAGE_TYPING: return Tr(L"Kiểu gõ", L"입력 방식");
        case PAGE_QUICK: return Tr(L"Gõ nhanh", L"빠른 입력");
        case PAGE_APPS: return Tr(L"Ứng dụng", L"앱");
        default: return Tr(L"Giới thiệu", L"정보");
    }
}

enum HotId {
    HOT_NONE = 0,
    HOT_PAGE = 1,  // HOT_PAGE + page index
    HOT_MODE = HOT_PAGE + PAGE_COUNT,
    HOT_ORB,
    HOT_TELEX,
    HOT_VNI,
    HOT_SPELLING,
    HOT_TONE,
    HOT_CTRL_SHIFT,
    HOT_ALT_Z,
    HOT_SLOW,
    HOT_STARTUP,
    HOT_GITHUB,
    HOT_MACROS,
    HOT_QUICK_TELEX,
    HOT_ESC_UNDO,
    HOT_EXCLUDE_ADD,
    HOT_LANG_VIETNAMESE,
    HOT_LANG_KOREAN,
    HOT_EXCLUDE_FIRST,  // + index in the excluded list; keep last
};

struct HotArea {
    RectF rect;
    int id;
};

HINSTANCE g_instance = nullptr;
ULONG_PTR g_gdiplusToken = 0;
Settings* g_settings = nullptr;
PanelCallbacks g_callbacks = {};
HWND g_panel = nullptr;
HWND g_tryEdit = nullptr;  // the "Gõ thử" box on the dashboard
HFONT g_tryFont = nullptr;
HWND g_macroEdit = nullptr;  // the macro list on the "Gõ nhanh" page
HFONT g_macroFont = nullptr;
HBRUSH g_wellBrush = nullptr;
int g_page = PAGE_DASHBOARD;
int g_hover = HOT_NONE;
bool g_trackingMouse = false;
std::vector<HotArea> g_hot;  // in 96-DPI units, rebuilt by every Render()

// ---- colours -----------------------------------------------------------------------

Color Rgb(int r, int g, int b, int a = 255) {
    return Color(static_cast<BYTE>(a), static_cast<BYTE>(r), static_cast<BYTE>(g), static_cast<BYTE>(b));
}
Color White(int a) { return Rgb(255, 255, 255, a); }
Color WithAlpha(const Color& c, int a) { return Rgb(c.GetR(), c.GetG(), c.GetB(), a); }

const Color kBackgroundTop = Rgb(0x29, 0x10, 0x61);
const Color kBackgroundMiddle = Rgb(0x4F, 0x1C, 0x9E);
const Color kBackgroundBottom = Rgb(0x73, 0x26, 0xB3);
const Color kGlowPink = Rgb(237, 77, 217);
const Color kGlowBlue = Rgb(77, 115, 255);
const Color kAccentStart = Rgb(250, 92, 217);
const Color kAccentEnd = Rgb(153, 56, 242);
const Color kSuccess = Rgb(0x61, 0xE6, 0x8C);
const Color kWarning = Rgb(255, 189, 89);
const int kSecondaryAlpha = 158;  // 62% white

// ---- drawing helpers ---------------------------------------------------------------

void AddRoundRect(GraphicsPath& path, const RectF& r, float radius) {
    float d = std::min(radius * 2, std::min(r.Width, r.Height));
    path.AddArc(r.X, r.Y, d, d, 180, 90);
    path.AddArc(r.GetRight() - d, r.Y, d, d, 270, 90);
    path.AddArc(r.GetRight() - d, r.GetBottom() - d, d, d, 0, 90);
    path.AddArc(r.X, r.GetBottom() - d, d, d, 90, 90);
    path.CloseFigure();
}

PointF Lerp(const PointF& a, const PointF& b, float t) { return PointF(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t); }

// A polygon whose corners are rounded with Bézier curves `corner` long.
void AddRoundedPolygon(GraphicsPath& path, const std::vector<PointF>& points, float corner) {
    const size_t n = points.size();
    for (size_t i = 0; i < n; i++) {
        const PointF& prev = points[(i + n - 1) % n];
        const PointF& cur = points[i];
        const PointF& next = points[(i + 1) % n];
        auto toward = [&](const PointF& other) {
            float dx = other.X - cur.X, dy = other.Y - cur.Y;
            float len = std::sqrt(dx * dx + dy * dy);
            float t = len > 0 ? std::min(corner / len, 0.5f) : 0;
            return Lerp(cur, other, t);
        };
        PointF a = toward(prev), b = toward(next);
        path.AddBezier(a, Lerp(a, cur, 0.6f), Lerp(b, cur, 0.6f), b);  // GDI+ joins the edges with lines
    }
    path.CloseFigure();
}

enum class Weight { Regular, Semibold, Bold, Mono };

// GDI+ has no font fallback: Segoe UI and Consolas have no Hangul, so Hangul
// is drawn with Malgun Gothic (Korean text never needs Vietnamese letters, and
// mixed lines are split into runs below).
bool IsHangul(wchar_t c) {
    return (c >= 0x1100 && c <= 0x11FF) || (c >= 0x3130 && c <= 0x318F) || (c >= 0xAC00 && c <= 0xD7A3);
}

struct FontSpec {
    FontFamily family;
    Font font;
    FontSpec(Weight weight, bool hangul, float size)
        : family(hangul                       ? L"Malgun Gothic"
                 : weight == Weight::Semibold ? L"Segoe UI Semibold"
                 : weight == Weight::Mono     ? L"Consolas"
                                              : L"Segoe UI"),
          font(family.IsAvailable() ? &family : FontFamily::GenericSansSerif(), size,
               weight == Weight::Bold || (hangul && weight == Weight::Semibold) ? FontStyleBold : FontStyleRegular,
               UnitPixel) {}
};

// Splits text into runs of Hangul and of everything else; spaces and ASCII
// punctuation join the run they are in.
std::vector<std::pair<std::wstring, bool>> HangulRuns(const std::wstring& text) {
    std::vector<std::pair<std::wstring, bool>> runs;
    for (wchar_t c : text) {
        const bool neutral = c < 0x80 && !iswalnum(static_cast<wint_t>(c));
        const bool hangul = IsHangul(c);
        if (runs.empty() || (!neutral && runs.back().second != hangul)) runs.push_back({std::wstring(), hangul});
        runs.back().first.push_back(c);
    }
    return runs;
}

float RunWidth(Graphics& g, const std::wstring& text, const Font& font) {
    StringFormat format(StringFormat::GenericTypographic());
    format.SetFormatFlags(format.GetFormatFlags() | StringFormatFlagsMeasureTrailingSpaces | StringFormatFlagsNoWrap);
    RectF box;
    g.MeasureString(text.c_str(), -1, &font, PointF(0, 0), &format, &box);
    return box.Width;
}

void Label(Graphics& g, const std::wstring& text, const RectF& r, float size, Weight weight, const Color& color,
           StringAlignment horizontal = StringAlignmentNear, StringAlignment vertical = StringAlignmentNear,
           bool wrap = false) {
    SolidBrush brush(color);
    auto runs = HangulRuns(text);
    if (runs.size() <= 1 || wrap) {
        bool hangul = false;
        for (const auto& run : runs) hangul = hangul || run.second;
        FontSpec spec(weight, hangul, size);
        StringFormat format;
        format.SetAlignment(horizontal);
        format.SetLineAlignment(vertical);
        format.SetTrimming(StringTrimmingEllipsisCharacter);
        if (!wrap) format.SetFormatFlags(StringFormatFlagsNoWrap);
        g.DrawString(text.c_str(), -1, &spec.font, r, &format, &brush);
        return;
    }
    // Mixed Hangul and Vietnamese on one line: draw run after run.
    float total = 0;
    std::vector<float> widths;
    for (const auto& run : runs) {
        FontSpec spec(weight, run.second, size);
        widths.push_back(RunWidth(g, run.first, spec.font));
        total += widths.back();
    }
    float x = horizontal == StringAlignmentCenter ? r.X + (r.Width - total) / 2
              : horizontal == StringAlignmentFar  ? r.GetRight() - total
                                                  : r.X;
    StringFormat format(StringFormat::GenericTypographic());
    format.SetLineAlignment(vertical);
    // GenericTypographic has LineLimit, which hides a line that does not fit the
    // box entirely: Malgun Gothic's line is taller than Segoe UI's.
    format.SetFormatFlags((format.GetFormatFlags() & ~StringFormatFlagsLineLimit) |
                          StringFormatFlagsMeasureTrailingSpaces | StringFormatFlagsNoWrap | StringFormatFlagsNoClip);
    for (size_t i = 0; i < runs.size(); i++) {
        FontSpec spec(weight, runs[i].second, size);
        const float width = std::max(widths[i] + 4, r.GetRight() - x);
        g.DrawString(runs[i].first.c_str(), -1, &spec.font, RectF(x, r.Y, width, r.Height), &format, &brush);
        x += widths[i];
    }
}

float TextWidth(Graphics& g, const std::wstring& text, float size, Weight weight) {
    float total = 0;
    for (const auto& run : HangulRuns(text)) {
        FontSpec spec(weight, run.second, size);
        total += RunWidth(g, run.first, spec.font);
    }
    return total;
}

void FillAccent(Graphics& g, GraphicsPath& path, const RectF& r) {
    LinearGradientBrush brush(PointF(r.X - 1, r.Y), PointF(r.GetRight() + 1, r.GetBottom()), kAccentStart, kAccentEnd);
    g.FillPath(&brush, &path);
}

// A soft round glow fading out to the edge of `r`.
void FillGlow(Graphics& g, const RectF& r, const Color& color, int alpha) {
    GraphicsPath ellipse;
    ellipse.AddEllipse(r);
    PathGradientBrush brush(&ellipse);
    brush.SetCenterColor(WithAlpha(color, alpha));
    Color surround = WithAlpha(color, 0);
    INT count = 1;
    brush.SetSurroundColors(&surround, &count);
    g.FillEllipse(&brush, r);
}

// ---- emblems: glossy 3D badges drawn in code -----------------------------------------

enum class Shape { Circle, Hexagon, Shield, Squircle };
enum class Symbol { Text, Check, Bolt, Keycap, Grid };

struct Emblem {
    Shape shape;
    Color top, bottom;
    Symbol symbol;
    const wchar_t* text;
};

const Emblem kModeOn = {Shape::Squircle, Rgb(250, 115, 219), Rgb(158, 41, 204), Symbol::Text, L"V"};
const Emblem kModeKorean = {Shape::Squircle, Rgb(110, 160, 255), Rgb(40, 70, 200), Symbol::Text, L"\uD55C"};  // 한
const Emblem kModeOff = {Shape::Squircle, Rgb(150, 160, 190), Rgb(80, 85, 120), Symbol::Text, L"E"};
const Emblem kReady = {Shape::Shield, Rgb(102, 235, 158), Rgb(13, 140, 102), Symbol::Check, nullptr};
const Emblem kPaused = {Shape::Shield, Rgb(255, 199, 102), Rgb(230, 102, 26), Symbol::Text, L"!"};
const Emblem kMethod = {Shape::Hexagon, Rgb(255, 173, 102), Rgb(217, 77, 51), Symbol::Keycap, nullptr};
const Emblem kApps = {Shape::Hexagon, Rgb(107, 158, 255), Rgb(46, 64, 217), Symbol::Grid, nullptr};
const Emblem kCount = {Shape::Circle, Rgb(89, 242, 230), Rgb(13, 140, 179), Symbol::Bolt, nullptr};
const Emblem kAbout = {Shape::Squircle, Rgb(250, 115, 219), Rgb(115, 51, 242), Symbol::Text, L"đ"};
const Emblem kAppIcon = {Shape::Squircle, Rgb(0xE8, 0x3A, 0x2F), Rgb(0xB0, 0x1E, 0x17), Symbol::Text, L"Đ"};

void AddShape(GraphicsPath& path, Shape shape, const RectF& r) {
    const float w = r.Width, h = r.Height, cx = r.X + w / 2, cy = r.Y + h / 2;
    switch (shape) {
        case Shape::Circle:
            path.AddEllipse(r);
            break;
        case Shape::Squircle:
            AddRoundRect(path, r, w * 0.28f);
            break;
        case Shape::Hexagon: {  // pointy top
            std::vector<PointF> points;
            const float radius = h / 2;
            for (int i = 0; i < 6; i++) {
                double a = -3.14159265358979 / 2 + i * 3.14159265358979 / 3;
                points.emplace_back(cx + static_cast<float>(std::cos(a)) * radius,
                                    cy + static_cast<float>(std::sin(a)) * radius);
            }
            AddRoundedPolygon(path, points, w * 0.13f);
            break;
        }
        case Shape::Shield: {
            const float l = r.X, t = r.Y, rt = r.GetRight(), b = r.GetBottom();
            path.AddBezier(PointF(cx, t), PointF(cx + w * 0.22f, t + h * 0.09f), PointF(rt - w * 0.06f, t + h * 0.10f),
                           PointF(rt, t + h * 0.14f));
            path.AddLine(PointF(rt, t + h * 0.14f), PointF(rt, t + h * 0.46f));
            path.AddBezier(PointF(rt, t + h * 0.46f), PointF(rt, t + h * 0.74f), PointF(cx + w * 0.22f, t + h * 0.90f),
                           PointF(cx, b));
            path.AddBezier(PointF(cx, b), PointF(cx - w * 0.22f, t + h * 0.90f), PointF(l, t + h * 0.74f),
                           PointF(l, t + h * 0.46f));
            path.AddLine(PointF(l, t + h * 0.46f), PointF(l, t + h * 0.14f));
            path.AddBezier(PointF(l, t + h * 0.14f), PointF(l + w * 0.06f, t + h * 0.10f), PointF(cx - w * 0.22f, t + h * 0.09f),
                           PointF(cx, t));
            path.CloseFigure();
            break;
        }
    }
}

void DrawSymbol(Graphics& g, const Emblem& e, const RectF& body, const Color& color) {
    const float w = body.Width, h = body.Height, x = body.X, y = body.Y;
    auto at = [&](float fx, float fy) { return PointF(x + w * fx, y + h * fy); };
    switch (e.symbol) {
        case Symbol::Text: {
            float size = h * (e.text && e.text[0] == L'!' ? 0.56f : 0.58f);
            RectF r(x, y + (e.shape == Shape::Shield ? -h * 0.04f : 0), w, h);
            Label(g, e.text ? e.text : L"", r, size, Weight::Bold, color, StringAlignmentCenter, StringAlignmentCenter);
            break;
        }
        case Symbol::Check: {
            Pen pen(color, w * 0.10f);
            pen.SetStartCap(LineCapRound);
            pen.SetEndCap(LineCapRound);
            pen.SetLineJoin(LineJoinRound);
            PointF points[] = {at(0.30f, 0.47f), at(0.45f, 0.62f), at(0.71f, 0.34f)};
            g.DrawLines(&pen, points, 3);
            break;
        }
        case Symbol::Bolt: {
            PointF points[] = {at(0.56f, 0.16f), at(0.30f, 0.55f), at(0.48f, 0.55f), at(0.43f, 0.85f),
                               at(0.71f, 0.43f), at(0.53f, 0.43f), at(0.60f, 0.16f)};
            SolidBrush brush(color);
            g.FillPolygon(&brush, points, 7);
            break;
        }
        case Symbol::Keycap: {
            GraphicsPath key;
            AddRoundRect(key, RectF(x + w * 0.25f, y + h * 0.31f, w * 0.50f, h * 0.38f), w * 0.08f);
            Pen pen(color, w * 0.055f);
            g.DrawPath(&pen, &key);
            Label(g, L"Aa", RectF(x, y + h * 0.01f, w, h), h * 0.19f, Weight::Bold, color, StringAlignmentCenter,
                     StringAlignmentCenter);
            break;
        }
        case Symbol::Grid: {
            SolidBrush brush(color);
            const float cell = w * 0.19f, gap = w * 0.06f, left = x + (w - cell * 2 - gap) / 2,
                        top = y + (h - cell * 2 - gap) / 2;
            for (int i = 0; i < 4; i++) {
                GraphicsPath square;
                AddRoundRect(square, RectF(left + (i % 2) * (cell + gap), top + (i / 2) * (cell + gap), cell, cell),
                             cell * 0.28f);
                g.FillPath(&brush, &square);
            }
            break;
        }
    }
}

// Draws an emblem filling `box`: glow, gradient body, glossy cap, rim, symbol.
// Everything stays inside `box`, so nothing is clipped by the card.
void DrawEmblem(Graphics& g, const Emblem& e, const RectF& box, bool glow = true) {
    const float inset = glow ? box.Width * 0.08f : 0;
    RectF body(box.X + inset, box.Y + inset, box.Width - inset * 2, box.Height - inset * 2);
    if (glow) {
        FillGlow(g, box, e.bottom, 115);
    }

    GraphicsPath path;
    AddShape(path, e.shape, body);
    // Vertical gradient: a slanted one would wrap around (tile) in the far corner.
    LinearGradientBrush fill(PointF(0, body.Y - 1), PointF(0, body.GetBottom() + 1), e.top, e.bottom);
    g.FillPath(&fill, &path);

    // Glossy cap over the upper half and a faint light from below.
    Region old;
    g.GetClip(&old);
    g.SetClip(&path, CombineModeIntersect);
    RectF cap(body.X - body.Width * 0.18f, body.Y - body.Height * 0.62f, body.Width * 1.36f, body.Height * 1.10f);
    LinearGradientBrush gloss(PointF(0, cap.Y), PointF(0, cap.GetBottom() + 1), White(66), White(4));
    g.FillEllipse(&gloss, cap);
    RectF under(body.X + body.Width * 0.1f, body.Y + body.Height * 0.72f, body.Width * 0.8f, body.Height * 0.5f);
    FillGlow(g, under, White(255), 28);
    g.SetClip(&old);

    Pen rim(White(71), std::max(1.0f, body.Width * 0.016f));
    g.DrawPath(&rim, &path);

    // The symbol with a soft drop shadow.
    RectF shadowBody(body.X, body.Y + body.Height * 0.02f, body.Width, body.Height);
    DrawSymbol(g, e, shadowBody, Rgb(40, 0, 60, 70));
    DrawSymbol(g, e, body, White(255));
}

// ---- controls ----------------------------------------------------------------------

void AddHot(const RectF& r, int id) { g_hot.push_back({r, id}); }

void DrawCard(Graphics& g, const RectF& r, bool hover = false) {
    GraphicsPath path;
    AddRoundRect(path, r, 16);
    SolidBrush fill(White(hover ? 28 : 18));
    g.FillPath(&fill, &path);
    Region old;
    g.GetClip(&old);
    g.SetClip(&path, CombineModeIntersect);
    RectF sheen(r.X, r.Y, r.Width, r.Height * 0.45f);
    LinearGradientBrush brush(PointF(0, sheen.Y - 1), PointF(0, sheen.GetBottom() + 1), White(18), White(0));
    g.FillRectangle(&brush, sheen);
    g.SetClip(&old);
    Pen border(White(hover ? 52 : 28), 1);
    g.DrawPath(&border, &path);
}

// "✓ text" in green or "● text" in orange; the marks are drawn, not font glyphs.
void DrawStatus(Graphics& g, float x, float y, float width, const std::wstring& text, bool ok) {
    const Color color = ok ? kSuccess : kWarning;
    if (ok) {
        Pen pen(color, 1.8f);
        pen.SetStartCap(LineCapRound);
        pen.SetEndCap(LineCapRound);
        PointF points[] = {PointF(x + 1, y + 9.5f), PointF(x + 4, y + 12.5f), PointF(x + 10, y + 5.5f)};
        g.DrawLines(&pen, points, 3);
    } else {
        SolidBrush brush(color);
        g.FillEllipse(&brush, RectF(x + 1.5f, y + 5.5f, 7, 7));
    }
    Label(g, text, RectF(x + 18, y, width - 18, 18), 12, Weight::Semibold, color, StringAlignmentNear,
             StringAlignmentCenter);
}

void DrawToggle(Graphics& g, float right, float cy, bool on, int id) {
    RectF r(right - 44, cy - 12, 44, 24);
    GraphicsPath track;
    AddRoundRect(track, r, 12);
    if (on) {
        FillAccent(g, track, r);
    } else {
        SolidBrush off(White(g_hover == id ? 66 : 52));
        g.FillPath(&off, &track);
    }
    float knobX = on ? r.GetRight() - 22 : r.X + 2;
    SolidBrush shadow(Rgb(30, 0, 60, 60));
    g.FillEllipse(&shadow, RectF(knobX, r.Y + 3, 20, 20));
    SolidBrush knob(White(255));
    g.FillEllipse(&knob, RectF(knobX, r.Y + 2, 20, 20));
    AddHot(r, id);
}

void DrawPills(Graphics& g, float right, float cy, float width, const wchar_t* const* options, int count,
               int selected, int firstId) {
    RectF r(right - width, cy - 14, width, 28);
    GraphicsPath track;
    AddRoundRect(track, r, 14);
    SolidBrush trackBrush(White(26));
    g.FillPath(&trackBrush, &track);
    const float segment = (r.Width - 4) / count;
    for (int i = 0; i < count; i++) {
        RectF s(r.X + 2 + i * segment, r.Y + 2, segment, r.Height - 4);
        if (i == selected) {
            GraphicsPath pill;
            AddRoundRect(pill, s, 12);
            FillAccent(g, pill, s);
        } else if (g_hover == firstId + i) {
            GraphicsPath pill;
            AddRoundRect(pill, s, 12);
            SolidBrush hover(White(20));
            g.FillPath(&hover, &pill);
        }
        Label(g, options[i], s, 12.5f, Weight::Semibold, i == selected ? White(255) : White(175),
                 StringAlignmentCenter, StringAlignmentCenter);
        AddHot(s, firstId + i);
    }
}

void DrawAccentButton(Graphics& g, const RectF& r, const wchar_t* text, int id) {
    GraphicsPath path;
    AddRoundRect(path, r, r.Height / 2);
    FillAccent(g, path, r);
    if (g_hover == id) {
        SolidBrush hover(White(30));
        g.FillPath(&hover, &path);
    }
    Label(g, text, r, 13, Weight::Semibold, White(255), StringAlignmentCenter, StringAlignmentCenter);
    AddHot(r, id);
}

// The round on/off button at the bottom: glow, pulse ring, glossy body.
void DrawOrb(Graphics& g, const RectF& box, bool on) {
    const bool hover = g_hover == HOT_ORB;
    const float cx = box.X + box.Width / 2, cy = box.Y + box.Height / 2;
    FillGlow(g, box, on ? kAccentStart : Rgb(170, 150, 220), hover ? 150 : 115);
    Pen ring(White(on ? 95 : 55), 2);
    g.DrawEllipse(&ring, RectF(cx - 39, cy - 39, 78, 78));

    RectF body(cx - 32, cy - 32, 64, 64);
    GraphicsPath path;
    path.AddEllipse(body);
    LinearGradientBrush fill(PointF(0, body.Y - 1), PointF(0, body.GetBottom() + 1),
                             on ? kAccentStart : Rgb(140, 120, 190), on ? kAccentEnd : Rgb(80, 60, 130));
    g.FillPath(&fill, &path);
    Region old;
    g.GetClip(&old);
    g.SetClip(&path, CombineModeIntersect);
    RectF cap(body.X - 8, body.Y - 40, body.Width + 16, 70);
    LinearGradientBrush gloss(PointF(0, cap.Y), PointF(0, cap.GetBottom() + 1), White(120), White(8));
    g.FillEllipse(&gloss, cap);
    g.SetClip(&old);
    Pen rim(White(165), 1.6f);
    g.DrawEllipse(&rim, body);
    Label(g, on ? Tr(L"Tắt", L"끄기") : Tr(L"Bật", L"켜기"), body, 15, Weight::Semibold, White(255), StringAlignmentCenter,
             StringAlignmentCenter);
    AddHot(body, HOT_ORB);
}

// ---- sidebar -----------------------------------------------------------------------

void DrawSidebarIcon(Graphics& g, int page, const RectF& r, const Color& color) {
    const float cx = r.X + r.Width / 2, cy = r.Y + r.Height / 2;
    SolidBrush brush(color);
    Pen pen(color, 1.7f);
    pen.SetLineJoin(LineJoinRound);
    switch (page) {
        case PAGE_DASHBOARD:
            for (int i = 0; i < 4; i++) {
                GraphicsPath square;
                AddRoundRect(square, RectF(cx - 9 + (i % 2) * 10, cy - 9 + (i / 2) * 10, 8, 8), 2.5f);
                g.FillPath(&brush, &square);
            }
            break;
        case PAGE_TYPING: {
            GraphicsPath key;
            AddRoundRect(key, RectF(cx - 10, cy - 7, 20, 14), 3);
            g.DrawPath(&pen, &key);
            for (int i = 0; i < 4; i++) g.FillRectangle(&brush, RectF(cx - 6.5f + i * 3.8f, cy - 3.5f, 2, 2));
            g.FillRectangle(&brush, RectF(cx - 5, cy + 2, 10, 1.8f));
            break;
        }
        case PAGE_QUICK: {
            PointF bolt[] = {PointF(cx + 1.5f, cy - 10), PointF(cx - 6.5f, cy + 1.5f), PointF(cx - 0.5f, cy + 1.5f),
                             PointF(cx - 2, cy + 10), PointF(cx + 6.5f, cy - 2), PointF(cx + 0.5f, cy - 2),
                             PointF(cx + 2.5f, cy - 10)};
            g.FillPolygon(&brush, bolt, 7);
            break;
        }
        case PAGE_APPS:
            for (int i = 0; i < 9; i++) g.FillEllipse(&brush, RectF(cx - 8.5f + (i % 3) * 6.5f, cy - 8.5f + (i / 3) * 6.5f, 4, 4));
            break;
        case PAGE_ABOUT:
            g.DrawEllipse(&pen, RectF(cx - 9, cy - 9, 18, 18));
            g.FillEllipse(&brush, RectF(cx - 1.2f, cy - 5.2f, 2.4f, 2.4f));
            g.FillRectangle(&brush, RectF(cx - 0.9f, cy - 1.5f, 1.8f, 6.5f));
            break;
        default:
            break;
    }
}

void DrawSidebar(Graphics& g) {
    RectF bar(0, 0, kSidebar, kHeight);
    LinearGradientBrush shade(PointF(0, -1), PointF(0, kHeight + 1), Rgb(0, 0, 0, 56), Rgb(0, 0, 0, 26));
    g.FillRectangle(&shade, bar);
    DrawEmblem(g, kAppIcon, RectF((kSidebar - 34) / 2, 20, 34, 34), false);
    for (int i = 0; i < PAGE_COUNT; i++) {
        RectF r((kSidebar - 38) / 2, 82 + i * 46.0f, 38, 38);
        const bool selected = i == g_page, hover = g_hover == HOT_PAGE + i;
        if (selected || hover) {
            GraphicsPath path;
            AddRoundRect(path, r, 10);
            SolidBrush fill(White(selected ? 36 : 16));
            g.FillPath(&fill, &path);
        }
        DrawSidebarIcon(g, i, r, selected ? kAccentStart : White(hover ? 230 : 185));
        AddHot(r, HOT_PAGE + i);
    }
}

void DrawBackground(Graphics& g) {
    RectF all(0, 0, kWidth, kHeight);
    LinearGradientBrush brush(all, kBackgroundTop, kBackgroundBottom, 55.0f, TRUE);
    Color colors[] = {kBackgroundTop, kBackgroundMiddle, kBackgroundBottom};
    REAL positions[] = {0.0f, 0.55f, 1.0f};
    brush.SetInterpolationColors(colors, positions, 3);
    g.FillRectangle(&brush, all);
    const float rp = kWidth * 0.45f, rb = kWidth * 0.40f;
    FillGlow(g, RectF(kWidth * 0.85f - rp, kHeight * 0.85f - rp, rp * 2, rp * 2), kGlowPink, 89);
    FillGlow(g, RectF(kWidth * 0.25f - rb, kHeight * 0.05f - rb, rb * 2, rb * 2), kGlowBlue, 89);
}

// ---- pages ---------------------------------------------------------------------------

// The page area: above the orb on the dashboard, down to the bottom elsewhere.
RectF ContentRect(int page) {
    const float top = 36, bottom = page == PAGE_DASHBOARD ? kHeight - 106 : kHeight - 20;
    return RectF(kSidebar + 22, top, kWidth - kSidebar - 22 - 24, bottom - top);
}

std::wstring HotkeyText() { return g_settings->hotkey == HOTKEY_ALT_Z ? L"Alt+Z" : L"Ctrl+Shift"; }

// A dashboard card: emblem on the left, then caption, value and status line.
void DrawStatCard(Graphics& g, const RectF& r, const wchar_t* caption, const std::wstring& value, float valueSize,
                  const std::wstring& status, bool ok, const Emblem& emblem, float emblemSize, int id = HOT_NONE) {
    DrawCard(g, r, id != HOT_NONE && g_hover == id);
    DrawEmblem(g, emblem, RectF(r.X + 10, r.Y + (r.Height - emblemSize) / 2, emblemSize, emblemSize));

    const float x = r.X + 10 + emblemSize + 10, width = r.GetRight() - 14 - x;
    const float captionHeight = 17, valueHeight = std::round(valueSize * 1.34f), statusHeight = 18;
    float y = r.Y + (r.Height - (captionHeight + 2 + valueHeight + 4 + statusHeight)) / 2;
    Label(g, caption, RectF(x, y, width, captionHeight), 12, Weight::Semibold, White(kSecondaryAlpha),
          StringAlignmentNear, StringAlignmentCenter);
    y += captionHeight + 2;
    Label(g, value, RectF(x - 1, y, width + 1, valueHeight), valueSize, Weight::Bold, White(255), StringAlignmentNear,
          StringAlignmentCenter);
    y += valueHeight + 4;
    DrawStatus(g, x, y, width, status, ok);
    if (id != HOT_NONE) AddHot(r, id);
}

// The "Gõ thử" card's dark well, where the live panel puts an edit box.
RectF TryWell() {
    const RectF c = ContentRect(PAGE_DASHBOARD);
    return RectF(c.X + 12, c.Y + 112 + 12 + 92 + 12 + 34, c.Width - 24, 46);
}

bool Korean() { return g_settings->language == LANGUAGE_KOREAN; }

const wchar_t* TryPlaceholder() {
    return Korean() ? Tr(L"Gõ thử tiếng Hàn ở đây, ví dụ: dkssudgktpdy → 안녕하세요",
                         L"여기에 입력해 보세요. 예: dkssudgktpdy → 안녕하세요")
                    : Tr(L"Gõ thử ở đây, ví dụ: Vieetj Nam, dduowngf, Haxy…",
                         L"여기에 입력해 보세요. 예: Vieetj Nam, dduowngf, Haxy…");
}

void DrawDashboard(Graphics& g, const RectF& c, const PanelStatus& st) {
    const Settings& s = *g_settings;
    const bool korean = Korean();
    const float stateWidth = (c.Width - 12) / 2.25f, modeWidth = c.Width - 12 - stateWidth;
    RectF mode(c.X, c.Y, modeWidth, 112), state(c.X + modeWidth + 12, c.Y, stateWidth, 112);
    const wchar_t* language = korean ? Tr(L"Tiếng Hàn", L"한국어") : Tr(L"Tiếng Việt", L"베트남어");
    DrawStatCard(g, mode, Tr(L"Chế độ gõ", L"입력 모드"), s.vietnamese ? language : Tr(L"Tiếng Anh", L"영어"), 28,
                 (s.vietnamese ? Tr(L"Đang bật · ", L"켜짐 · ") : Tr(L"Đang tắt · ", L"꺼짐 · ")) + HotkeyText() +
                     Tr(L" để chuyển", L"로 전환"),
                 s.vietnamese, !s.vietnamese ? kModeOff : korean ? kModeKorean : kModeOn, 96, HOT_MODE);
    const wchar_t* stateCaption = Tr(L"Trạng thái", L"상태");
    if (IsExcluded(s, st.appExe)) {
        std::wstring why = UiKorean() ? L"제외된 앱: " + st.appName : L"Không gõ tiếng Việt trong " + st.appName;
        DrawStatCard(g, state, stateCaption, Tr(L"Tạm nghỉ", L"일시 중지"), 22, why, false, kPaused, 80);
    } else if (st.imeActive) {
        DrawStatCard(g, state, stateCaption, Tr(L"Tạm nghỉ", L"일시 중지"), 22,
                     Tr(L"Bộ gõ Trung/Nhật/Hàn đang bật", L"다른 입력기(중국어/일본어/한국어) 사용 중"), false, kPaused,
                     80);
    } else {
        DrawStatCard(g, state, stateCaption, Tr(L"Sẵn sàng", L"준비됨"), 22,
                     Tr(L"Dokey đang nghe bàn phím", L"Dokey가 키보드를 듣고 있습니다"), true, kReady, 80);
    }

    const float w = (c.Width - 24) / 3, y = c.Y + 124, h = 92;
    if (korean) {
        DrawStatCard(g, RectF(c.X, y, w, h), Tr(L"Kiểu gõ", L"입력 방식"), L"두벌식", 19,
                     Tr(L"Theo vị trí phím", L"키 위치 기준"), true, kMethod, 60);
    } else {
        DrawStatCard(g, RectF(c.X, y, w, h), Tr(L"Kiểu gõ", L"입력 방식"), s.method == DOKEY_VNI ? L"VNI" : L"Telex",
                     19, Tr(L"Unicode dựng sẵn", L"유니코드 완성형"), true, kMethod, 60);
    }
    const wchar_t* appCaption = Tr(L"Ứng dụng", L"앱");
    if (st.appName.empty()) {
        DrawStatCard(g, RectF(c.X + w + 12, y, w, h), appCaption, L"—", 19, Tr(L"Chưa có", L"없음"), false, kApps, 60);
    } else {
        DrawStatCard(g, RectF(c.X + w + 12, y, w, h), appCaption, st.appName, 19,
                     st.appChromium ? Tr(L"Nhóm: trình duyệt", L"유형: 브라우저")
                                    : Tr(L"Nhóm: ứng dụng thường", L"유형: 일반 앱"),
                     true, kApps, 60);
    }
    const std::wstring count = std::to_wstring(st.markedWords) + Tr(L" từ", L"개");
    DrawStatCard(g, RectF(c.X + (w + 12) * 2, y, w, h),
                 korean ? Tr(L"Đã ghép chữ", L"조합한 단어") : Tr(L"Đã thêm dấu", L"성조를 붙인 단어"), count, 19,
                 Tr(L"từ lúc mở Dokey", L"Dokey 실행 후"), true, kCount, 60);

    RectF tryCard(c.X, y + h + 12, c.Width, 92);
    DrawCard(g, tryCard);
    Label(g, Tr(L"Gõ thử", L"입력 테스트"), RectF(tryCard.X + 16, tryCard.Y + 10, 200, 20), 12, Weight::Semibold, White(kSecondaryAlpha),
          StringAlignmentNear, StringAlignmentCenter);
    const RectF well = TryWell();
    GraphicsPath wellPath;
    AddRoundRect(wellPath, well, 10);
    SolidBrush wellBrush(Rgb(kWellColor & 0xFF, (kWellColor >> 8) & 0xFF, (kWellColor >> 16) & 0xFF));
    g.FillPath(&wellBrush, &wellPath);
    if (!g_tryEdit) {  // rendering to a file: no edit box, show its placeholder
        Label(g, TryPlaceholder(), RectF(well.X + 14, well.Y, well.Width - 28, well.Height), 17, Weight::Regular,
              White(120), StringAlignmentNear, StringAlignmentCenter);
    }
}

// A page header: emblem on the left, big title and subtitle.
void DrawHero(Graphics& g, const RectF& r, const wchar_t* title, const wchar_t* subtitle, const Emblem& emblem) {
    DrawCard(g, r);
    const float size = 80;
    DrawEmblem(g, emblem, RectF(r.X + 10, r.Y + (r.Height - size) / 2, size, size));
    const float x = r.X + 10 + size + 12;
    Label(g, title, RectF(x, r.Y + 16, r.GetRight() - x - 16, 32), 22, Weight::Bold, White(255), StringAlignmentNear,
          StringAlignmentCenter);
    Label(g, subtitle, RectF(x + 1, r.Y + 50, r.GetRight() - x - 16, 20), 13, Weight::Regular, White(kSecondaryAlpha),
          StringAlignmentNear, StringAlignmentCenter);
}

struct Row {
    const wchar_t* title;
    const wchar_t* detail;
};

constexpr float kRowHeight = 48;  // 9 px padding, title, detail, 9 px padding

// A glass card of rows; returns the vertical centre of each row for its control.
std::vector<float> DrawSettingsCard(Graphics& g, const RectF& r, const std::vector<Row>& rows) {
    DrawCard(g, r);
    std::vector<float> centres;
    for (size_t i = 0; i < rows.size(); i++) {
        const float top = r.Y + 3 + i * kRowHeight;
        if (i > 0) {
            SolidBrush line(White(18));
            g.FillRectangle(&line, RectF(r.X + 1, top, r.Width - 2, 1));
        }
        Label(g, rows[i].title, RectF(r.X + 18, top + 8, r.Width - 280, 19), 13, Weight::Semibold, White(255));
        Label(g, rows[i].detail, RectF(r.X + 18, top + 26, r.Width - 280, 17), 11, Weight::Regular,
              White(kSecondaryAlpha));
        centres.push_back(top + kRowHeight / 2);
    }
    return centres;
}

RectF SettingsCardRect(const RectF& c, size_t rows) { return RectF(c.X, c.Y + 88 + 12, c.Width, rows * kRowHeight + 6); }

void DrawTypingPage(Graphics& g, const RectF& c) {
    const Settings& s = *g_settings;
    const bool korean = Korean();
    DrawHero(g, RectF(c.X, c.Y, c.Width, 88), Tr(L"Kiểu gõ", L"입력 방식"),
             Tr(L"Chọn ngôn ngữ, cách gõ và cách Dokey xử lý chữ.", L"언어와 입력 방식을 고르세요."),
             korean ? kModeKorean : kMethod);
    const Row language = {Tr(L"Ngôn ngữ", L"언어"),
                          Tr(L"Tiếng Việt (Telex, VNI) hoặc tiếng Hàn (두벌식)", L"베트남어(Telex, VNI) 또는 한국어(두벌식)")};
    const wchar_t* const languages[] = {Tr(L"Tiếng Việt", L"베트남어"), L"한국어"};
    const wchar_t* const hotkeys[] = {L"Ctrl + Shift", L"Alt + Z"};

    if (korean) {
        RectF card = SettingsCardRect(c, 3);
        std::vector<float> y = DrawSettingsCard(g, card, {
            language,
            {Tr(L"Bàn phím", L"자판"),
             Tr(L"두벌식 (KS X 5002), đọc theo vị trí phím: gksrnr → 한국", L"두벌식 (KS X 5002), 키 위치 기준: gksrnr → 한국")},
            {Tr(L"Phím chuyển Anh/Hàn", L"한/영 전환 키"),
             Tr(L"Dùng được ở mọi ứng dụng; phím 한/영 cũng chuyển được", L"모든 앱에서 사용 가능, 한/영 키도 사용 가능")},
        });
        const float right = card.GetRight() - 18;
        DrawPills(g, right, y[0], 200, languages, 2, 1, HOT_LANG_VIETNAMESE);
        DrawPills(g, right, y[2], 200, hotkeys, 2, s.hotkey == HOTKEY_ALT_Z ? 1 : 0, HOT_CTRL_SHIFT);
        Label(g, L"dkssudgktpdy → 안녕하세요   ·   gksrnr → 한국   ·   rkatkgkqslek → 감사합니다   ·   dlTdjdy → 있어요",
              RectF(c.X + 2, card.GetBottom() + 12, c.Width - 4, 20), 13, Weight::Semibold, White(225));
        Label(g,
              Tr(L"Giữ bố cục bàn phím English (US) của Windows; không cần bật bộ gõ tiếng Hàn của Microsoft. "
                 L"Chữ hiện ra ngay, không có chữ đang ghép dở, nên bấm Enter không làm mất âm tiết cuối.",
                 L"Windows 키보드는 영어(미국) 그대로 두세요. Microsoft 한국어 입력기는 켤 필요가 없습니다. "
                 L"조합 중인 글자 없이 바로 입력되므로 Enter를 눌러도 마지막 글자가 사라지지 않습니다."),
              RectF(c.X + 2, card.GetBottom() + 40, c.Width - 4, 40), 12, Weight::Regular, White(kSecondaryAlpha),
              StringAlignmentNear, StringAlignmentNear, true);
        return;
    }

    RectF card = SettingsCardRect(c, 5);
    std::vector<float> y = DrawSettingsCard(g, card, {
        language,
        {Tr(L"Kiểu gõ", L"베트남어 입력 방식"),
         Tr(L"Gõ dấu bằng chữ cái (Telex) hoặc chữ số (VNI)", L"문자(Telex) 또는 숫자(VNI)로 성조 입력")},
        {Tr(L"Kiểm tra chính tả", L"맞춤법 검사"),
         Tr(L"Giữ nguyên từ không phải tiếng Việt: windows, chrome…", L"베트남어가 아닌 단어는 그대로: windows, chrome…")},
        {Tr(L"Đặt dấu kiểu mới", L"새 성조 위치"),
         Tr(L"Bật: hoà, khoẻ, thuý · Tắt: hòa, khỏe, thúy", L"켜기: hoà, khoẻ, thuý · 끄기: hòa, khỏe, thúy")},
        {Tr(L"Phím chuyển Anh/Việt", L"전환 단축키"), Tr(L"Dùng được ở mọi ứng dụng", L"모든 앱에서 사용 가능")},
    });
    const float right = card.GetRight() - 18;
    DrawPills(g, right, y[0], 200, languages, 2, 0, HOT_LANG_VIETNAMESE);
    const wchar_t* const methods[] = {L"Telex", L"VNI"};
    DrawPills(g, right, y[1], 164, methods, 2, s.method == DOKEY_VNI ? 1 : 0, HOT_TELEX);
    DrawToggle(g, right, y[2], s.checkSpelling, HOT_SPELLING);
    DrawToggle(g, right, y[3], s.modernTone, HOT_TONE);
    DrawPills(g, right, y[4], 200, hotkeys, 2, s.hotkey == HOTKEY_ALT_Z ? 1 : 0, HOT_CTRL_SHIFT);

    const wchar_t* examples =
        s.method == DOKEY_VNI
            ? L"Ví dụ VNI:  Vie65t Nam → Việt Nam   ·   d9u7o7ng2 → đường   ·   1–5 = sắc huyền hỏi ngã nặng, "
              L"6 = mũ, 7 = móc, 8 = trăng, 9 = đ"
            : L"Ví dụ Telex:  Vieetj Nam → Việt Nam   ·   dduowngf → đường   ·   s f r x j = sắc huyền hỏi ngã nặng, "
              L"aa ee oo = â ê ô, aw ow uw = ă ơ ư, dd = đ";
    Label(g, examples, RectF(c.X + 2, card.GetBottom() + 12, c.Width - 4, 40), 12, Weight::Regular,
          White(kSecondaryAlpha), StringAlignmentNear, StringAlignmentNear, true);
}

// The macro list's well on the "Gõ nhanh" page, where the live panel puts a multi-line edit box.
RectF MacroWell() {
    const RectF c = ContentRect(PAGE_QUICK);
    return RectF(c.X, SettingsCardRect(c, 3).GetBottom() + 32, c.Width, 118);
}

void DrawQuickPage(Graphics& g, const RectF& c) {
    const Settings& s = *g_settings;
    DrawHero(g, RectF(c.X, c.Y, c.Width, 88), Tr(L"Gõ nhanh", L"빠른 입력"),
             Korean() ? Tr(L"Các tính năng này dành cho tiếng Việt.", L"이 기능은 베트남어 입력에 적용됩니다.")
                      : Tr(L"Gõ tắt, Quick Telex và hoàn tác bằng Esc.", L"약어, Quick Telex, Esc로 되돌리기"),
             kCount);
    RectF card = SettingsCardRect(c, 3);
    std::vector<float> y = DrawSettingsCard(g, card, {
        {Tr(L"Gõ tắt", L"약어"),
         Tr(L"Gõ từ tắt rồi dấu cách: vn → Việt Nam, ko → không", L"약어 입력 후 스페이스: vn → Việt Nam, ko → không")},
        {L"Quick Telex", Tr(L"cc → ch, gg → gi, kk → kh, nn → ng, pp → ph, qq → qu, tt → th (đầu từ)",
                            L"단어 첫머리: cc → ch, gg → gi, kk → kh, nn → ng, pp → ph, qq → qu, tt → th")},
        {Tr(L"Hoàn tác bằng Esc", L"Esc로 되돌리기"),
         Tr(L"Bấm Esc khi đang gõ để trả từ về đúng phím đã gõ: tiếng → tieesng",
            L"입력 중 Esc: 입력한 키 그대로 되돌림 (tiếng → tieesng)")},
    });
    const float right = card.GetRight() - 18;
    DrawToggle(g, right, y[0], s.macrosEnabled, HOT_MACROS);
    DrawToggle(g, right, y[1], s.quickTelex, HOT_QUICK_TELEX);
    DrawToggle(g, right, y[2], s.escUndo, HOT_ESC_UNDO);

    const RectF well = MacroWell();
    Label(g, Tr(L"Danh sách gõ tắt (mỗi dòng: từ tắt = nội dung; dòng bắt đầu bằng # là ghi chú)",
                L"약어 목록 (한 줄에 하나씩: 약어 = 내용, #으로 시작하면 주석)"),
          RectF(c.X + 2, well.Y - 22, c.Width - 4, 18), 12, Weight::Semibold, White(kSecondaryAlpha));
    GraphicsPath wellPath;
    AddRoundRect(wellPath, well, 10);
    SolidBrush wellBrush(Rgb(kWellColor & 0xFF, (kWellColor >> 8) & 0xFF, (kWellColor >> 16) & 0xFF));
    g.FillPath(&wellBrush, &wellPath);
    if (!g_macroEdit) {  // rendering to a file: show the list itself
        Label(g, s.macros, RectF(well.X + 12, well.Y + 8, well.Width - 24, well.Height - 16), 13, Weight::Mono,
              White(225), StringAlignmentNear, StringAlignmentNear, true);
    }
    Label(g, Tr(L"Mẹo: gõ \"xin\", dấu cách rồi Backspace là quay lại sửa dấu từ đó (\"f\" ra \"xìn\"). "
                L"Xoá phụ âm cuối thì dấu thanh tự về đúng chỗ.",
                L"팁: 단어와 스페이스를 입력한 뒤 Backspace를 누르면 그 단어의 성조를 다시 고칠 수 있습니다."),
          RectF(c.X + 2, well.GetBottom() + 8, c.Width - 4, 34), 12, Weight::Regular, White(kSecondaryAlpha),
          StringAlignmentNear, StringAlignmentNear, true);
}

void DrawAppsPage(Graphics& g, const RectF& c, const PanelStatus& st) {
    const Settings& s = *g_settings;
    DrawHero(g, RectF(c.X, c.Y, c.Width, 88), Tr(L"Ứng dụng", L"앱"),
             Tr(L"Dokey tự nhận biết trình duyệt, Electron và ứng dụng thường.",
                L"Dokey는 브라우저, Electron, 일반 앱을 자동으로 구분합니다."),
             kApps);
    RectF card = SettingsCardRect(c, 3);
    std::vector<float> y = DrawSettingsCard(g, card, {
        {Tr(L"Tương thích máy chậm", L"느린 PC 호환"),
         Tr(L"Nghỉ lâu hơn giữa phím xoá và chữ mới trong Chrome, Edge, Electron",
            L"Chrome, Edge, Electron에서 지우기와 새 글자 사이에 더 오래 대기")},
        {Tr(L"Khởi động cùng Windows", L"Windows 시작 시 실행"), Tr(L"Tự chạy Dokey khi đăng nhập", L"로그인할 때 Dokey 자동 실행")},
        {Tr(L"Ứng dụng loại trừ", L"제외할 앱"),
         Tr(L"Luôn gõ tiếng Anh trong các ứng dụng này; bấm phím chuyển ở đó để bỏ loại trừ",
            L"이 앱에서는 항상 영어로 입력, 그 앱에서 전환 키를 누르면 해제")},
    });
    const float right = card.GetRight() - 18;
    DrawToggle(g, right, y[0], s.chromiumPauseMs >= kSlowPauseMs, HOT_SLOW);
    DrawToggle(g, right, y[1], IsStartupEnabled(), HOT_STARTUP);
    if (!st.appExe.empty() && !IsExcluded(s, st.appExe)) {
        std::wstring text = Tr(L"Thêm ", L"추가: ") + st.appName;
        const float width = std::min(220.0f, TextWidth(g, text, 13, Weight::Semibold) + 32);
        DrawAccentButton(g, RectF(right - width, y[2] - 14, width, 28), text.c_str(), HOT_EXCLUDE_ADD);
    }

    // The excluded apps as chips; clicking one removes it.
    float x = c.X, top = card.GetBottom() + 10;
    if (s.excludedApps.empty()) {
        Label(g, Tr(L"Chưa loại trừ ứng dụng nào.", L"제외된 앱이 없습니다."), RectF(x + 2, top, c.Width, 26), 12, Weight::Regular,
              White(kSecondaryAlpha), StringAlignmentNear, StringAlignmentCenter);
    }
    for (size_t i = 0; i < s.excludedApps.size(); i++) {
        const std::wstring& exe = s.excludedApps[i];
        const float width = TextWidth(g, exe, 12, Weight::Semibold) + 40;
        if (x + width > c.GetRight()) break;
        RectF chip(x, top, width, 26);
        const int id = HOT_EXCLUDE_FIRST + static_cast<int>(i);
        GraphicsPath path;
        AddRoundRect(path, chip, 13);
        SolidBrush fill(White(g_hover == id ? 46 : 26));
        g.FillPath(&fill, &path);
        Label(g, exe, RectF(chip.X + 12, chip.Y, width - 30, chip.Height), 12, Weight::Semibold, White(235),
              StringAlignmentNear, StringAlignmentCenter);
        Pen cross(White(200), 1.5f);
        const float cx = chip.GetRight() - 14, cy = chip.Y + 13;
        g.DrawLine(&cross, cx - 3.5f, cy - 3.5f, cx + 3.5f, cy + 3.5f);
        g.DrawLine(&cross, cx - 3.5f, cy + 3.5f, cx + 3.5f, cy - 3.5f);
        AddHot(chip, id);
        x += width + 8;
    }

    const wchar_t* note = Tr(
        L"Trình duyệt và ứng dụng Electron (Chrome, Edge, Cốc Cốc, VS Code, Zalo…): Dokey nghỉ một chút giữa phím "
        L"xoá và chữ mới để trang web kịp xử lý. Google Docs, Sheets, Slides: Dokey gửi từng phím một. "
        L"Ứng dụng thường (Notepad, Word, Excel…): Dokey xoá và gõ chữ mới trong một lần gửi phím.",
        L"브라우저와 Electron 앱(Chrome, Edge, Whale, VS Code, KakaoTalk 등): 지우기와 새 글자 사이에 잠시 기다려 "
        L"웹 페이지가 처리할 시간을 줍니다. Google Docs, Sheets, Slides: 한 번에 한 키씩 보냅니다. "
        L"일반 앱(메모장, Word, Excel 등): 지우기와 새 글자를 한 번에 보냅니다.");
    RectF noteRect(c.X + 2, top + 38, c.Width - 4, 54);
    Label(g, note, noteRect, 12, Weight::Regular, White(kSecondaryAlpha), StringAlignmentNear, StringAlignmentNear,
          true);
    if (!st.appName.empty()) {
        std::wstring line = Tr(L"Ứng dụng vừa dùng: ", L"최근 사용한 앱: ") + st.appName +
                            (st.appChromium ? Tr(L" (trình duyệt, Electron).", L" (브라우저, Electron)")
                                            : Tr(L" (ứng dụng thường).", L" (일반 앱)"));
        Label(g, line, RectF(c.X + 2, noteRect.GetBottom() + 6, c.Width - 4, 20), 12, Weight::Regular,
              White(kSecondaryAlpha));
    }
}

void DrawAboutPage(Graphics& g, const RectF& c) {
    const float cx = c.X + c.Width / 2;
    DrawEmblem(g, kAbout, RectF(cx - 60, c.Y + 6, 120, 120));
    float y = c.Y + 130;
    Label(g, L"Dokey", RectF(c.X, y, c.Width, 42), 30, Weight::Bold, White(255), StringAlignmentCenter);
    y += 42;
    Label(g, std::wstring(Tr(L"Phiên bản ", L"버전 ")) + DOKEY_APP_VERSION_W, RectF(c.X, y, c.Width, 20), 13, Weight::Regular,
          White(kSecondaryAlpha), StringAlignmentCenter);
    y += 30;
    Label(g,
          Tr(L"Bộ gõ tiếng Việt và tiếng Hàn cho Windows, chạy trên lõi Dokey Core.\n"
             L"Mỗi phím, Dokey dựng lại cả từ và kiểm tra chính tả với 3.759 âm tiết,\n"
             L"nên gõ đúng ngay lần đầu và giữ nguyên các từ tiếng Anh.",
             L"Dokey Core 기반의 Windows용 베트남어·한국어 입력기입니다.\n"
             L"한국어는 두벌식 자판을 키 위치로 읽어 조합 중인 글자 없이 바로 입력합니다.\n"
             L"어떤 키보드 배열에서도 동작합니다."),
          RectF(c.X + c.Width * 0.1f, y, c.Width * 0.8f, 64), 13, Weight::Regular, White(kSecondaryAlpha),
          StringAlignmentCenter, StringAlignmentNear, true);
    y += 76;
    DrawAccentButton(g, RectF(cx - 110, y, 220, 32), Tr(L"Trang dự án trên GitHub", L"GitHub 프로젝트 페이지"), HOT_GITHUB);
    y += 46;
    Label(g, L"© 2026 Do Huy Toan. All rights reserved.", RectF(c.X, y, c.Width, 18), 11, Weight::Regular,
          White(115), StringAlignmentCenter);
}

// Draws the whole panel in 96-DPI units (the caller scales the Graphics).
void Render(Graphics& g, const PanelStatus& st) {
    g.SetSmoothingMode(SmoothingModeAntiAlias);
    g.SetPixelOffsetMode(PixelOffsetModeHalf);
    g.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);
    g.SetCompositingQuality(CompositingQualityHighQuality);
    g_hot.clear();

    DrawBackground(g);
    DrawSidebar(g);
    Label(g, Title(g_page), RectF(kSidebar, 6, kWidth - kSidebar, 22), 13, Weight::Semibold, White(217),
          StringAlignmentCenter, StringAlignmentCenter);
    const RectF content = ContentRect(g_page);
    switch (g_page) {
        case PAGE_DASHBOARD: DrawDashboard(g, content, st); break;
        case PAGE_TYPING: DrawTypingPage(g, content); break;
        case PAGE_QUICK: DrawQuickPage(g, content); break;
        case PAGE_APPS: DrawAppsPage(g, content, st); break;
        default: DrawAboutPage(g, content); break;
    }
    if (g_page == PAGE_DASHBOARD) {  // the on/off orb lives on the dashboard only
        const float cx = content.X + content.Width / 2;
        DrawOrb(g, RectF(cx - 50, kHeight - 106, 100, 100), g_settings->vietnamese);
    }
}

// ---- window --------------------------------------------------------------------------

UINT DpiOf(HWND hwnd) {
    using GetDpiForWindowFn = UINT(WINAPI*)(HWND);
    static auto fn = reinterpret_cast<GetDpiForWindowFn>(
        reinterpret_cast<void*>(GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow")));
    UINT dpi = fn ? fn(hwnd) : 96;
    return dpi ? dpi : 96;
}

// Outer window rectangle for a 900x600 client area at `dpi`.
SIZE WindowSizeFor(UINT dpi, DWORD style, DWORD exStyle) {
    RECT r = {0, 0, MulDiv(static_cast<int>(kWidth), dpi, 96), MulDiv(static_cast<int>(kHeight), dpi, 96)};
    using AdjustFn = BOOL(WINAPI*)(LPRECT, DWORD, BOOL, DWORD, UINT);
    static auto adjust = reinterpret_cast<AdjustFn>(
        reinterpret_cast<void*>(GetProcAddress(GetModuleHandleW(L"user32.dll"), "AdjustWindowRectExForDpi")));
    if (adjust) {
        adjust(&r, style, FALSE, exStyle, dpi);
    } else {
        AdjustWindowRectEx(&r, style, FALSE, exStyle);
    }
    return {r.right - r.left, r.bottom - r.top};
}

int HitTest(HWND hwnd, int x, int y) {
    const float scale = DpiOf(hwnd) / 96.0f;
    PointF p(x / scale, y / scale);
    for (auto it = g_hot.rbegin(); it != g_hot.rend(); ++it) {
        if (it->rect.Contains(p)) return it->id;
    }
    return HOT_NONE;
}

void Changed() {
    if (g_callbacks.settingsChanged) g_callbacks.settingsChanged();
    RefreshPanel();
}

// Places the "Gõ thử" edit box in its well (physical pixels) and shows it on the dashboard only.
void LayoutTryEdit(HWND hwnd) {
    if (!g_tryEdit) return;
    const float scale = DpiOf(hwnd) / 96.0f;
    auto px = [scale](float v) { return static_cast<int>(std::lround(v * scale)); };
    if (g_tryFont) DeleteObject(g_tryFont);
    g_tryFont = CreateFontW(-px(17), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_TT_PRECIS,
                            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, VARIABLE_PITCH, L"Segoe UI");
    SendMessageW(g_tryEdit, WM_SETFONT, reinterpret_cast<WPARAM>(g_tryFont), TRUE);
    SendMessageW(g_tryEdit, EM_SETMARGINS, EC_LEFTMARGIN | EC_RIGHTMARGIN, 0);
    const RectF well = TryWell();
    const float textHeight = 26;
    SetWindowPos(g_tryEdit, nullptr, px(well.X + 14), px(well.Y + (well.Height - textHeight) / 2), px(well.Width - 28),
                 px(textHeight), SWP_NOZORDER | SWP_NOACTIVATE);
    ShowWindow(g_tryEdit, g_page == PAGE_DASHBOARD ? SW_SHOWNA : SW_HIDE);

    if (!g_macroEdit) return;
    if (g_macroFont) DeleteObject(g_macroFont);
    g_macroFont = CreateFontW(-px(14), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_TT_PRECIS,
                              CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, FIXED_PITCH, L"Consolas");
    SendMessageW(g_macroEdit, WM_SETFONT, reinterpret_cast<WPARAM>(g_macroFont), TRUE);
    SendMessageW(g_macroEdit, EM_SETMARGINS, EC_LEFTMARGIN | EC_RIGHTMARGIN, 0);
    const RectF macros = MacroWell();
    SetWindowPos(g_macroEdit, nullptr, px(macros.X + 12), px(macros.Y + 8), px(macros.Width - 24),
                 px(macros.Height - 16), SWP_NOZORDER | SWP_NOACTIVATE);
    ShowWindow(g_macroEdit, g_page == PAGE_QUICK ? SW_SHOWNA : SW_HIDE);
}

// Reads the macro edit box back into the settings ("\r\n" -> "\n").
void SaveMacros() {
    if (!g_macroEdit) return;
    int length = GetWindowTextLengthW(g_macroEdit);
    std::wstring text(static_cast<size_t>(length) + 1, L'\0');
    GetWindowTextW(g_macroEdit, &text[0], length + 1);
    text.resize(static_cast<size_t>(length));
    std::wstring normalized;
    for (wchar_t c : text) {
        if (c != L'\r') normalized.push_back(c);
    }
    if (normalized != g_settings->macros) {
        g_settings->macros = normalized;
        if (g_callbacks.settingsChanged) g_callbacks.settingsChanged();
    }
}

void SelectPage(int page) {
    if (g_page == PAGE_QUICK && page != PAGE_QUICK) SaveMacros();
    g_page = page;
    if (g_panel) {
        HWND focus = GetFocus();
        if ((page != PAGE_DASHBOARD && focus == g_tryEdit) || (page != PAGE_QUICK && focus == g_macroEdit)) {
            SetFocus(g_panel);
        }
        LayoutTryEdit(g_panel);
    }
    RefreshPanel();
}

void OnClick(int id) {
    Settings& s = *g_settings;
    if (id >= HOT_PAGE && id < HOT_PAGE + PAGE_COUNT) {
        SelectPage(id - HOT_PAGE);
        return;
    }
    switch (id) {
        case HOT_MODE:
        case HOT_ORB: s.vietnamese = !s.vietnamese; break;
        case HOT_TELEX: s.method = DOKEY_TELEX; break;
        case HOT_VNI: s.method = DOKEY_VNI; break;
        case HOT_SPELLING: s.checkSpelling = !s.checkSpelling; break;
        case HOT_TONE: s.modernTone = !s.modernTone; break;
        case HOT_CTRL_SHIFT: s.hotkey = HOTKEY_CTRL_SHIFT; break;
        case HOT_ALT_Z: s.hotkey = HOTKEY_ALT_Z; break;
        case HOT_SLOW: s.chromiumPauseMs = s.chromiumPauseMs >= kSlowPauseMs ? Settings().chromiumPauseMs : kSlowPauseMs; break;
        case HOT_STARTUP:
            SetStartupEnabled(!IsStartupEnabled());
            RefreshPanel();
            return;
        case HOT_GITHUB:
            ShellExecuteW(g_panel, L"open", L"https://github.com/dhtoan/Dokey", nullptr, nullptr, SW_SHOWNORMAL);
            return;
        case HOT_LANG_VIETNAMESE: s.language = LANGUAGE_VIETNAMESE; s.vietnamese = true; break;
        case HOT_LANG_KOREAN: s.language = LANGUAGE_KOREAN; s.vietnamese = true; break;
        case HOT_MACROS: s.macrosEnabled = !s.macrosEnabled; break;
        case HOT_QUICK_TELEX: s.quickTelex = !s.quickTelex; break;
        case HOT_ESC_UNDO: s.escUndo = !s.escUndo; break;
        case HOT_EXCLUDE_ADD:
            if (g_callbacks.status) SetExcluded(s, g_callbacks.status().appExe, true);
            break;
        default:
            if (id >= HOT_EXCLUDE_FIRST && id - HOT_EXCLUDE_FIRST < static_cast<int>(s.excludedApps.size())) {
                s.excludedApps.erase(s.excludedApps.begin() + (id - HOT_EXCLUDE_FIRST));
                break;
            }
            return;
    }
    Changed();
}

void Paint(HWND hwnd) {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(hwnd, &ps);
    RECT client;
    GetClientRect(hwnd, &client);
    const int w = client.right, h = client.bottom;
    if (w > 0 && h > 0) {
        HDC memory = CreateCompatibleDC(dc);
        HBITMAP bitmap = CreateCompatibleBitmap(dc, w, h);
        HGDIOBJ old = SelectObject(memory, bitmap);
        {
            Graphics g(memory);
            const float scale = DpiOf(hwnd) / 96.0f;
            g.ScaleTransform(scale, scale);
            Render(g, g_callbacks.status ? g_callbacks.status() : PanelStatus());
        }
        BitBlt(dc, 0, 0, w, h, memory, 0, 0, SRCCOPY);
        SelectObject(memory, old);
        DeleteObject(bitmap);
        DeleteDC(memory);
    }
    EndPaint(hwnd, &ps);
}

LRESULT CALLBACK PanelProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_CREATE: {
            // Dark title bar in the background's colour (Windows 11; ignored elsewhere).
            BOOL dark = TRUE;
            DwmSetWindowAttribute(hwnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &dark, sizeof(dark));
            COLORREF caption = RGB(0x29, 0x10, 0x61), text = RGB(255, 255, 255);
            DwmSetWindowAttribute(hwnd, 35 /* DWMWA_CAPTION_COLOR */, &caption, sizeof(caption));
            DwmSetWindowAttribute(hwnd, 36 /* DWMWA_TEXT_COLOR */, &text, sizeof(text));
            SetTimer(hwnd, kRefreshTimer, kRefreshMs, nullptr);
            // "Gõ thử": a plain edit box, so Dokey types into it with Backspace like any normal app.
            g_tryEdit = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | ES_AUTOHSCROLL, 0, 0, 10, 10, hwnd, nullptr,
                                        g_instance, nullptr);
            if (g_tryEdit) SendMessageW(g_tryEdit, EM_SETCUEBANNER, TRUE, reinterpret_cast<LPARAM>(TryPlaceholder()));
            // The macro list, edited in place and saved shortly after each change.
            g_macroEdit = CreateWindowExW(0, L"EDIT", L"",
                                          WS_CHILD | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN | ES_NOHIDESEL,
                                          0, 0, 10, 10, hwnd, nullptr, g_instance, nullptr);
            if (g_macroEdit) {
                std::wstring macros;
                for (wchar_t c : g_settings->macros) {
                    if (c == L'\n') macros.push_back(L'\r');
                    macros.push_back(c);
                }
                SetWindowTextW(g_macroEdit, macros.c_str());
                SetMacroEditor(g_macroEdit);
            }
            LayoutTryEdit(hwnd);
            return 0;
        }
        case WM_COMMAND:
            if (reinterpret_cast<HWND>(lParam) == g_macroEdit && HIWORD(wParam) == EN_CHANGE) {
                SetTimer(hwnd, kMacroSaveTimer, 700, nullptr);
            }
            return 0;
        case WM_CTLCOLOREDIT:
            if (reinterpret_cast<HWND>(lParam) == g_tryEdit || reinterpret_cast<HWND>(lParam) == g_macroEdit) {
                HDC dc = reinterpret_cast<HDC>(wParam);
                SetTextColor(dc, RGB(255, 255, 255));
                SetBkColor(dc, kWellColor);
                return reinterpret_cast<LRESULT>(g_wellBrush);
            }
            break;
        case WM_PAINT:
            Paint(hwnd);
            return 0;
        case WM_ERASEBKGND:
            return 1;
        case WM_MOUSEMOVE: {
            if (!g_trackingMouse) {
                TRACKMOUSEEVENT track = {sizeof(track), TME_LEAVE, hwnd, 0};
                g_trackingMouse = TrackMouseEvent(&track) != FALSE;
            }
            int hot = HitTest(hwnd, GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam));
            if (hot != g_hover) {
                g_hover = hot;
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            return 0;
        }
        case WM_MOUSELEAVE:
            g_trackingMouse = false;
            if (g_hover != HOT_NONE) {
                g_hover = HOT_NONE;
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            return 0;
        case WM_SETCURSOR:
            if (LOWORD(lParam) == HTCLIENT && g_hover != HOT_NONE) {
                SetCursor(LoadCursorW(nullptr, IDC_HAND));
                return TRUE;
            }
            break;
        case WM_LBUTTONDOWN: {
            const int x = GET_X_LPARAM(lParam), y = GET_Y_LPARAM(lParam);
            const float scale = DpiOf(hwnd) / 96.0f;
            const PointF p(x / scale, y / scale);
            HWND target = hwnd;
            if (g_page == PAGE_DASHBOARD && g_tryEdit && TryWell().Contains(p)) target = g_tryEdit;
            if (g_page == PAGE_QUICK && g_macroEdit && MacroWell().Contains(p)) target = g_macroEdit;
            SetFocus(target);
            int hot = HitTest(hwnd, x, y);
            if (hot != HOT_NONE) OnClick(hot);
            return 0;
        }
        case WM_KEYDOWN:
            if (wParam == VK_ESCAPE) DestroyWindow(hwnd);
            return 0;
        case WM_TIMER:
            if (wParam == kRefreshTimer && !IsIconic(hwnd)) InvalidateRect(hwnd, nullptr, FALSE);
            if (wParam == kMacroSaveTimer) {
                KillTimer(hwnd, kMacroSaveTimer);
                SaveMacros();
            }
            return 0;
        case WM_DPICHANGED: {
            const RECT* r = reinterpret_cast<const RECT*>(lParam);
            SetWindowPos(hwnd, nullptr, r->left, r->top, r->right - r->left, r->bottom - r->top,
                         SWP_NOZORDER | SWP_NOACTIVATE);
            LayoutTryEdit(hwnd);
            InvalidateRect(hwnd, nullptr, FALSE);
            return 0;
        }
        case WM_DESTROY:
            KillTimer(hwnd, kRefreshTimer);
            KillTimer(hwnd, kMacroSaveTimer);
            SaveMacros();  // the children still exist during WM_DESTROY
            SetMacroEditor(nullptr);
            g_tryEdit = nullptr;  // destroyed with their parent
            g_macroEdit = nullptr;
            if (g_tryFont) DeleteObject(g_tryFont);
            g_tryFont = nullptr;
            if (g_macroFont) DeleteObject(g_macroFont);
            g_macroFont = nullptr;
            g_panel = nullptr;
            g_hover = HOT_NONE;
            g_trackingMouse = false;
            return 0;
        default:
            break;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

bool EncoderFor(const wchar_t* mime, CLSID* clsid) {
    UINT count = 0, size = 0;
    if (GetImageEncodersSize(&count, &size) != Ok || size == 0) return false;
    std::vector<BYTE> buffer(size);
    auto* codecs = reinterpret_cast<ImageCodecInfo*>(buffer.data());
    if (GetImageEncoders(count, size, codecs) != Ok) return false;
    for (UINT i = 0; i < count; i++) {
        if (wcscmp(codecs[i].MimeType, mime) == 0) {
            *clsid = codecs[i].Clsid;
            return true;
        }
    }
    return false;
}

} // namespace

bool InitPanel(HINSTANCE instance, Settings* settings, const PanelCallbacks& callbacks) {
    GdiplusStartupInput input;
    if (GdiplusStartup(&g_gdiplusToken, &input, nullptr) != Ok) return false;
    g_instance = instance;
    g_settings = settings;
    g_callbacks = callbacks;
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = PanelProc;
    wc.hInstance = instance;
    wc.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(IDI_DOKEY));
    wc.hIconSm = static_cast<HICON>(LoadImageW(instance, MAKEINTRESOURCEW(IDI_DOKEY), IMAGE_ICON,
                                               GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0));
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kPanelClass;
    RegisterClassExW(&wc);
    g_wellBrush = CreateSolidBrush(kWellColor);
    return true;
}

void ShowPanel(int page) {
    if (page >= 0 && page < PAGE_COUNT) SelectPage(page);
    if (!g_panel) {
        const DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPCHILDREN;
        const DWORD exStyle = WS_EX_APPWINDOW;
        g_panel = CreateWindowExW(exStyle, kPanelClass, L"Dokey", style, CW_USEDEFAULT, CW_USEDEFAULT, 100, 100, nullptr,
                                  nullptr, g_instance, nullptr);
        if (!g_panel) return;
        // Size for the DPI of the monitor the window landed on, centred in its work area.
        SIZE size = WindowSizeFor(DpiOf(g_panel), style, exStyle);
        MONITORINFO mi = {sizeof(mi)};
        GetMonitorInfoW(MonitorFromWindow(g_panel, MONITOR_DEFAULTTOPRIMARY), &mi);
        const RECT& work = mi.rcWork;
        int x = work.left + std::max(0L, (work.right - work.left - size.cx) / 2);
        int y = work.top + std::max(0L, (work.bottom - work.top - size.cy) / 2);
        SetWindowPos(g_panel, nullptr, x, y, size.cx, size.cy, SWP_NOZORDER | SWP_NOACTIVATE);
        ShowWindow(g_panel, SW_SHOW);
    } else if (IsIconic(g_panel)) {
        ShowWindow(g_panel, SW_RESTORE);
    }
    InvalidateRect(g_panel, nullptr, FALSE);
    SetForegroundWindow(g_panel);
}

void RefreshPanel() {
    if (!g_panel) return;
    if (g_tryEdit) SendMessageW(g_tryEdit, EM_SETCUEBANNER, TRUE, reinterpret_cast<LPARAM>(TryPlaceholder()));
    InvalidateRect(g_panel, nullptr, FALSE);
}

void ShutdownPanel() {
    if (g_panel) DestroyWindow(g_panel);
    if (g_wellBrush) DeleteObject(g_wellBrush);
    g_wellBrush = nullptr;
    if (g_gdiplusToken) GdiplusShutdown(g_gdiplusToken);
    g_gdiplusToken = 0;
}

int RenderPanelImages(const wchar_t* prefix) {
    CLSID png;
    if (!EncoderFor(L"image/png", &png)) return 2;
    PanelStatus demo;
    demo.appName = L"Google Chrome";
    demo.appChromium = true;
    demo.appExe = L"chrome.exe";
    demo.markedWords = 128;
    const Settings saved = *g_settings;
    SetExcluded(*g_settings, L"zalo.exe", true);  // show a chip on the apps page
    struct Shot {
        int page;
        float scale;
        bool english;
        bool ime;
        bool korean;  // Korean user interface, typing Korean
    };
    // The five pages, the dashboard in English with an IME on, at 150% scale,
    // then the Korean user interface: dashboard, typing page, apps page.
    const Shot shots[] = {{0, 1, false, false, false}, {1, 1, false, false, false}, {2, 1, false, false, false},
                          {3, 1, false, false, false}, {4, 1, false, false, false}, {0, 1, true, true, false},
                          {0, 1.5f, false, false, false}, {0, 1, false, false, true}, {1, 1, false, false, true},
                          {3, 1, false, false, true}};
    const bool uiKorean = UiKorean();
    int failures = 0, n = 0;
    for (const Shot& shot : shots) {
        g_page = shot.page;
        g_settings->vietnamese = !shot.english;
        g_settings->language = shot.korean ? LANGUAGE_KOREAN : LANGUAGE_VIETNAMESE;
        SetUiKorean(shot.korean);
        demo.imeActive = shot.ime;
        demo.appName = shot.korean ? L"KakaoTalk" : L"Google Chrome";
        demo.appChromium = !shot.korean;
        Bitmap bitmap(static_cast<INT>(kWidth * shot.scale), static_cast<INT>(kHeight * shot.scale), PixelFormat32bppARGB);
        {
            Graphics g(&bitmap);
            g.ScaleTransform(shot.scale, shot.scale);
            Render(g, demo);
        }
        wchar_t path[MAX_PATH];
        wsprintfW(path, L"%s-%d.png", prefix, ++n);
        if (bitmap.Save(path, &png, nullptr) != Ok) failures++;
    }
    *g_settings = saved;
    SetUiKorean(uiKorean);
    g_page = PAGE_DASHBOARD;
    return failures ? 2 : 0;
}

} // namespace dokey_win
