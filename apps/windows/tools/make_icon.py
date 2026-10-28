#!/usr/bin/env python3
"""Draws the Dokey app icon (res/dokey.ico): a red key cap with a white "Đ".

Pure Python (no Pillow): each pixel is supersampled against simple shapes.
Copyright (c) 2026 Do Huy Toan. All rights reserved.

Usage: python3 make_icon.py <output.ico>
"""
import struct
import sys
import zlib

SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]
SS = 4  # supersampling per axis

TOP = (0xE8, 0x3A, 0x2F)
BOTTOM = (0xB0, 0x1E, 0x17)


def rounded_square(x, y, inset=0.03, radius=0.22):
    lo, hi = inset, 1 - inset
    if not (lo <= x <= hi and lo <= y <= hi):
        return False
    cx = min(max(x, lo + radius), hi - radius)
    cy = min(max(y, lo + radius), hi - radius)
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2


def letter(x, y):
    """The "Đ": a D with a crossbar through its stem."""
    x -= 0.02  # optical centring
    def inside_d(left, top, bottom, radius):
        if not (x >= left and top <= y <= bottom):
            return False
        return x <= 0.50 or (x - 0.50) ** 2 + (y - 0.50) ** 2 <= radius ** 2
    outer = inside_d(0.30, 0.24, 0.76, 0.26)
    hole = inside_d(0.42, 0.36, 0.64, 0.14)
    bar = 0.20 <= x <= 0.42 and 0.46 <= y <= 0.545
    return (outer and not hole) or bar


def render(size):
    pixels = []
    for py in range(size):
        row = []
        for px in range(size):
            cover = ink = 0
            for sy in range(SS):
                for sx in range(SS):
                    x = (px + (sx + 0.5) / SS) / size
                    y = (py + (sy + 0.5) / SS) / size
                    if rounded_square(x, y):
                        cover += 1
                        if letter(x, y):
                            ink += 1
            n = SS * SS
            t = (py + 0.5) / size
            base = [TOP[i] + (BOTTOM[i] - TOP[i]) * t for i in range(3)]
            if t < 0.5:  # soft highlight on the upper half of the key cap
                base = [c + (255 - c) * 0.10 * (1 - t / 0.5) for c in base]
            k = ink / cover if cover else 0
            rgb = [round(c * (1 - k) + 255 * k) for c in base]
            row.append((rgb[0], rgb[1], rgb[2], round(255 * cover / n)))
        pixels.append(row)
    return pixels


def png(pixels):
    size = len(pixels)
    raw = b"".join(b"\0" + bytes(c for p in row for c in p) for row in pixels)
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def dib(pixels):
    size = len(pixels)
    header = struct.pack("<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, 0, 0, 0, 0, 0)
    color = b"".join(bytes((p[2], p[1], p[0], p[3])) for row in reversed(pixels) for p in row)
    mask_stride = ((size + 31) // 32) * 4
    mask = b"\0" * (mask_stride * size)
    return header + color + mask


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "dokey.ico"
    images = []
    for size in SIZES:
        pixels = render(size)
        images.append((size, png(pixels) if size >= 256 else dib(pixels)))
    data = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    for size, blob in images:
        dim = 0 if size >= 256 else size
        data += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(blob), offset)
        offset += len(blob)
    data += b"".join(blob for _, blob in images)
    with open(out, "wb") as f:
        f.write(data)
    # A preview for the README / docs.
    with open(out.rsplit(".", 1)[0] + "-256.png", "wb") as f:
        f.write(images[-1][1])


if __name__ == "__main__":
    main()
