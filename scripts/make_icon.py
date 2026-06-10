"""Generate a gold-ring-on-dark ICO file. No external dependencies.

Usage:
    python make_icon.py --out static/gs-icon.ico --bg "#07060a" --ring "#d4af37" --size 32
"""
from __future__ import annotations
import argparse, math, struct
from pathlib import Path


def hex_to_bgra(hex_color: str) -> bytes:
    h = hex_color.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return bytes([b, g, r, 255])


def make_ico(size: int = 32, bg: str = "#07060a", ring: str = "#d4af37") -> bytes:
    BG   = hex_to_bgra(bg)
    GOLD = hex_to_bgra(ring)
    cx = cy = (size - 1) / 2.0
    r_outer, r_inner = size * 0.42, size * 0.22

    def lerp4(a: bytes, b: bytes, t: float) -> bytes:
        t = max(0.0, min(1.0, t))
        return bytes(int(a[i] + (b[i] - a[i]) * t) for i in range(4))

    rows = []
    for y in range(size - 1, -1, -1):
        row = bytearray()
        for x in range(size):
            d = math.hypot(x - cx, y - cy)
            if   d <= r_inner - 0.5: row += BG
            elif d <= r_inner + 0.5: row += lerp4(BG, GOLD, d - (r_inner - 0.5))
            elif d <= r_outer - 0.5: row += GOLD
            elif d <= r_outer + 0.5: row += lerp4(GOLD, BG, d - (r_outer - 0.5))
            else:                    row += BG
        rows.append(bytes(row))

    pixel_data = b"".join(rows)
    and_mask   = bytes(((size + 31) // 32 * 4) * size)
    bih        = struct.pack("<IIIHHIIIIII", 40, size, size * 2, 1, 32, 0, 0, 0, 0, 0, 0)
    image_data = bih + pixel_data + and_mask
    ico_header = struct.pack("<HHH", 0, 1, 1)
    dir_entry  = struct.pack("<BBBBHHII", size, size, 0, 0, 1, 32, len(image_data), 22)
    return ico_header + dir_entry + image_data


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--out",  default="static/gs-icon.ico")
    p.add_argument("--bg",   default="#07060a")
    p.add_argument("--ring", default="#d4af37")
    p.add_argument("--size", type=int, default=32)
    args = p.parse_args()
    dest = Path(args.out)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(make_ico(args.size, args.bg, args.ring))
    print(f"Written: {dest}  ({dest.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
