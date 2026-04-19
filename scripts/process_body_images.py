"""
Convert male/female body JPGs from Downloads/ into transparent PNGs
for bundling under assets/body/.

Logic:
- Load JPG
- Any pixel close to pure white (mean > ~240) becomes fully transparent
- Remaining dark outline/linework is preserved; we also tint it to a soft
  neutral color (textSecondary) so it blends with the dark theme.
- Auto-crop the visible content so the silhouette fills the frame.
- Save as PNG (with alpha).

Run once:
    python scripts/process_body_images.py
"""
from pathlib import Path
from PIL import Image, ImageChops

SRC = Path(r"C:/Users/lihop/Downloads")
DST = Path(__file__).resolve().parent.parent / "assets" / "body"
DST.mkdir(parents=True, exist_ok=True)

# Near-white threshold — any pixel with all channels >= this is treated as bg.
WHITE_CUTOFF = 235
# Line color (app textSecondary-ish, light slate on dark card)
LINE_RGB = (170, 185, 205)

def process(src_path: Path, dst_path: Path) -> None:
    img = Image.open(src_path).convert("RGBA")
    px = img.load()
    w, h = img.size

    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            # Bg detection: near-white
            if r >= WHITE_CUTOFF and g >= WHITE_CUTOFF and b >= WHITE_CUTOFF:
                px[x, y] = (0, 0, 0, 0)
                continue
            # Keep line pixels; darker = more opaque, lighter gray = partial alpha
            # Brightness 0..255 → alpha 255..0
            bright = (r + g + b) / 3
            alpha = max(0, min(255, int(round((WHITE_CUTOFF - bright) * 255 / WHITE_CUTOFF))))
            # Replace color with our line tone; scale alpha by original darkness
            px[x, y] = (*LINE_RGB, alpha)

    # Auto-crop to the visible silhouette bounds
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)

    # Resize to a reasonable max dimension to keep bundle small
    max_side = 900
    w2, h2 = img.size
    if max(w2, h2) > max_side:
        scale = max_side / max(w2, h2)
        img = img.resize((int(w2 * scale), int(h2 * scale)), Image.LANCZOS)

    img.save(dst_path, "PNG", optimize=True)
    size_kb = dst_path.stat().st_size / 1024
    print(f"  -> {dst_path.name}  {img.size[0]}x{img.size[1]}  {size_kb:.1f} KB")


if __name__ == "__main__":
    pairs = [
        (SRC / "male body.jpg",   DST / "male.png"),
        (SRC / "female body.jpg", DST / "female.png"),
    ]
    for s, d in pairs:
        if not s.exists():
            print(f"! missing: {s}")
            continue
        print(f"Processing {s.name} …")
        process(s, d)
    print("Done.")
