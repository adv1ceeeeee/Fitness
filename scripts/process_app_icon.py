"""
Extract the Sportify app icon (rounded square) from the AI-generated JPG.

Strategy (v5):
  1) Classify pixels coarsely: background (flattened transparency checker) vs
     foreground (icon). Background = neutral grey with mx<=110 and spread<=18.
  2) For each row/column, count foreground pixels. Tight bbox = first/last
     row/col whose count exceeds a ratio of image width (20%). This filters
     out stray JPG-artefact speckles outside the real icon.
  3) Centre the bbox on a square (use the longer side).
  4) Crop, resize to 1024x1024, apply an iOS-style rounded-rectangle mask
     (22% corner radius) to get clean edges.
  5) Outputs:
       assets/icon/icon.png         — 1024x1024 RGBA, transparent corners
       assets/icon/icon_padded.png  — 1024x1024 RGB,  brand-blue background
"""
from __future__ import annotations
import os
from PIL import Image, ImageDraw, ImageFilter

SRC = r"C:\Users\lihop\Downloads\logo_icon.jpg"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "icon")
OUT = os.path.join(OUT_DIR, "icon.png")
OUT_PADDED = os.path.join(OUT_DIR, "icon_padded.png")
os.makedirs(OUT_DIR, exist_ok=True)

src = Image.open(SRC).convert("RGB")
W, H = src.size
pix = src.load()


def is_bg(r: int, g: int, b: int) -> bool:
    """Flattened transparency-checker = dark + neutral grey."""
    mx, mn = max(r, g, b), min(r, g, b)
    return mx <= 110 and (mx - mn) <= 18


# --- count foreground pixels per row / column ------------------------------
row_count = [0] * H
col_count = [0] * W
for y in range(H):
    for x in range(W):
        r, g, b = pix[x, y]
        if not is_bg(r, g, b):
            row_count[y] += 1
            col_count[x] += 1

THRESH_W = int(W * 0.20)
THRESH_H = int(H * 0.20)
top = next((y for y in range(H) if row_count[y] >= THRESH_W), 0)
bottom = next((y for y in range(H - 1, -1, -1) if row_count[y] >= THRESH_W), H - 1)
left = next((x for x in range(W) if col_count[x] >= THRESH_H), 0)
right = next((x for x in range(W - 1, -1, -1) if col_count[x] >= THRESH_H), W - 1)
bbox = (left, top, right + 1, bottom + 1)
print(f"tight bbox: {bbox}   size: {bbox[2]-bbox[0]} x {bbox[3]-bbox[1]}")

# inset bbox 10px to strip the shadow/halo ring around the icon
INSET = 10
bbox = (bbox[0] + INSET, bbox[1] + INSET, bbox[2] - INSET, bbox[3] - INSET)

# square bbox centred on the detected rectangle
cx = (bbox[0] + bbox[2]) // 2
cy = (bbox[1] + bbox[3]) // 2
side = max(bbox[2] - bbox[0], bbox[3] - bbox[1])
half = side // 2
sq = (cx - half, cy - half, cx - half + side, cy - half + side)
sq = (max(0, sq[0]), max(0, sq[1]), min(W, sq[2]), min(H, sq[3]))
print(f"inset bbox: {bbox}   square bbox: {sq}")

cropped = src.crop(sq)
TARGET = 1024
resized = cropped.resize((TARGET, TARGET), Image.LANCZOS)

# iOS-style rounded-rectangle mask
RADIUS = int(TARGET * 0.22)
mask = Image.new("L", (TARGET, TARGET), 0)
ImageDraw.Draw(mask).rounded_rectangle(
    [(0, 0), (TARGET - 1, TARGET - 1)],
    radius=RADIUS,
    fill=255,
)
mask = mask.filter(ImageFilter.GaussianBlur(radius=0.7))

rgba = resized.convert("RGBA")
rgba.putalpha(mask)
rgba.save(OUT, "PNG", optimize=True)

# padded RGB version
top_band = resized.crop((TARGET // 2 - 60, 30, TARGET // 2 + 60, 150))
blues = [c for c in top_band.getdata() if c[2] > c[0] + 30 and c[2] > 150]
if blues:
    bg = (
        sum(c[0] for c in blues) // len(blues),
        sum(c[1] for c in blues) // len(blues),
        sum(c[2] for c in blues) // len(blues),
    )
else:
    bg = (0, 102, 255)
print(f"sampled bg blue: {bg}  ({len(blues)} px)")

padded = Image.new("RGB", (TARGET, TARGET), bg)
padded.paste(rgba, (0, 0), rgba.split()[3])
padded.save(OUT_PADDED, "PNG", optimize=True)

print(f"OK  icon.png         {os.path.getsize(OUT)//1024} KB")
print(f"OK  icon_padded.png  {os.path.getsize(OUT_PADDED)//1024} KB")
