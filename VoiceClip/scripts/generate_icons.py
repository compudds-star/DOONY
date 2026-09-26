#!/usr/bin/env python3
"""Draws VoiceClip's icons (a microphone over a speech-bubble-orange ground)
with no dependencies, and writes the extension PNGs plus the 1024 px app
icon. Re-run after changing the drawing:  python3 scripts/generate_icons.py
"""
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "VoiceClipExtension", "Resources")
APPICON = os.path.join(ROOT, "VoiceClip", "Assets.xcassets", "AppIcon.appiconset")

ORANGE = (255, 149, 0)
WHITE = (255, 255, 255)
BLACK = (0, 0, 0)


def write_png(path, size, pixels):
    raw = b"".join(b"\x00" + bytes(pixels[y * size * 4:(y + 1) * size * 4]) for y in range(size))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def sd_round_rect(x, y, cx, cy, hw, hh, r):
    dx = abs(x - cx) - (hw - r)
    dy = abs(y - cy) - (hh - r)
    return math.hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0) - r


def mic_coverage(u, v):
    """Signed distance (in unit coords, 0..1) to the microphone glyph."""
    capsule = sd_round_rect(u, v, 0.5, 0.40, 0.12, 0.20, 0.12)
    # U-shaped holder: ring segment below the capsule's center.
    ring = abs(math.hypot(u - 0.5, v - 0.44) - 0.20) - 0.035
    if v < 0.44:
        ring = max(ring, 0.44 - v)
    stem = sd_round_rect(u, v, 0.5, 0.715, 0.035, 0.07, 0.0)
    base = sd_round_rect(u, v, 0.5, 0.78, 0.13, 0.035, 0.035)
    return min(capsule, ring, stem, base)


def render(size, background, fg, rounded, supersample=3):
    px = bytearray(size * size * 4)
    n = supersample
    for y in range(size):
        for x in range(size):
            bg_hits = fg_hits = 0
            for sy in range(n):
                for sx in range(n):
                    u = (x + (sx + 0.5) / n) / size
                    v = (y + (sy + 0.5) / n) / size
                    inside_bg = background is not None and (
                        not rounded or sd_round_rect(u, v, 0.5, 0.5, 0.5, 0.5, 0.22) <= 0
                    )
                    if mic_coverage(u, v) <= 0:
                        fg_hits += 1
                    elif inside_bg:
                        bg_hits += 1
            total = n * n
            a_fg = fg_hits / total
            a_bg = bg_hits / total
            alpha = a_fg + a_bg
            i = (y * size + x) * 4
            if alpha == 0:
                continue
            for c in range(3):
                bgc = background[c] if background else 0
                px[i + c] = round((fg[c] * a_fg + bgc * a_bg) / alpha)
            px[i + 3] = round(alpha * 255)
    return px


def main():
    for s in (48, 96, 128, 256, 512):
        write_png(os.path.join(RES, f"icon-{s}.png"), s, render(s, ORANGE, WHITE, rounded=True))
    # Toolbar icons: template-style glyph Safari tints.
    for s in (16, 32):
        write_png(os.path.join(RES, f"toolbar-{s}.png"), s, render(s, None, BLACK, rounded=False, supersample=6))
    os.makedirs(APPICON, exist_ok=True)
    # App Store icons must be opaque and square; iOS applies the mask.
    write_png(os.path.join(APPICON, "icon-1024.png"), 1024, render(1024, ORANGE, WHITE, rounded=False, supersample=1))


if __name__ == "__main__":
    main()
