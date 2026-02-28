#!/usr/bin/env python3
"""Generate synthetic test photos for Photon XCUITest E2E tests.

Creates 16 JPEG images in scripts/test_photos/:
  - 8 near-duplicates (similar_01..08): Same gradient with tiny brightness shifts.
    Should cluster as near-duplicates → keepBest interaction mode.
  - 4 blurry images (blurry_01..04): Heavy Gaussian blur (radius=20).
    Laplacian variance < 50 → deleteAll interaction mode.
  - 4 normal images (normal_01..04): Sharp, distinct images as controls.
"""

import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_photos")
SIZE = (640, 640)


def create_gradient(width: int, height: int, r_base: int, g_base: int, b_base: int) -> Image.Image:
    """Create a diagonal gradient image with the given base color."""
    img = Image.new("RGB", (width, height))
    pixels = img.load()
    for y in range(height):
        for x in range(width):
            t = (x + y) / (width + height)
            r = min(255, int(r_base + t * 80))
            g = min(255, int(g_base + t * 60))
            b = min(255, int(b_base + t * 100))
            pixels[x, y] = (r, g, b)
    return img


def generate_near_duplicates(count: int = 8) -> None:
    """Generate near-duplicate images with tiny brightness shifts (±1-3)."""
    base = create_gradient(SIZE[0], SIZE[1], 100, 60, 140)

    # Add some structure so embeddings are more meaningful
    draw = ImageDraw.Draw(base)
    draw.ellipse([150, 150, 490, 490], fill=(180, 120, 200))
    draw.rectangle([200, 200, 440, 440], fill=(140, 90, 170))

    for i in range(count):
        img = base.copy()
        pixels = img.load()
        # Tiny brightness shift: ±1 to ±3 per channel
        shift = (i % 3) - 1  # -1, 0, 1 cycling
        for y in range(0, SIZE[1], 2):  # Every other row for speed
            for x in range(0, SIZE[0], 2):
                r, g, b = pixels[x, y]
                pixels[x, y] = (
                    max(0, min(255, r + shift + (i % 2))),
                    max(0, min(255, g + shift)),
                    max(0, min(255, b + shift - (i % 2))),
                )
        filename = f"similar_{i + 1:02d}.jpg"
        img.save(os.path.join(OUTPUT_DIR, filename), "JPEG", quality=95)
        print(f"  Created {filename}")


def generate_blurry(count: int = 4) -> None:
    """Generate heavily blurred images. Laplacian variance should be < 50."""
    colors = [
        (200, 80, 80),   # Red-ish
        (80, 200, 80),   # Green-ish
        (80, 80, 200),   # Blue-ish
        (200, 200, 80),  # Yellow-ish
    ]
    for i in range(count):
        r, g, b = colors[i % len(colors)]
        img = create_gradient(SIZE[0], SIZE[1], r, g, b)

        # Add some shapes before blurring
        draw = ImageDraw.Draw(img)
        draw.rectangle([100, 100, 540, 540], fill=(r + 30, g + 30, b + 30))
        draw.ellipse([200, 200, 440, 440], fill=(r - 30, g - 30, b - 30))

        # Heavy Gaussian blur (radius=20) → Laplacian variance well below 50
        img = img.filter(ImageFilter.GaussianBlur(radius=20))

        filename = f"blurry_{i + 1:02d}.jpg"
        img.save(os.path.join(OUTPUT_DIR, filename), "JPEG", quality=90)
        print(f"  Created {filename}")


def generate_normal(count: int = 4) -> None:
    """Generate sharp, visually distinct images (control group)."""
    configs = [
        {"bg": (30, 30, 80), "shapes": "circles", "label": "A"},
        {"bg": (80, 30, 30), "shapes": "rectangles", "label": "B"},
        {"bg": (30, 80, 30), "shapes": "diamonds", "label": "C"},
        {"bg": (80, 80, 30), "shapes": "stripes", "label": "D"},
    ]
    for i in range(count):
        cfg = configs[i % len(configs)]
        img = Image.new("RGB", SIZE, cfg["bg"])
        draw = ImageDraw.Draw(img)

        if cfg["shapes"] == "circles":
            for j in range(5):
                offset = j * 80
                draw.ellipse(
                    [80 + offset, 80 + offset, 200 + offset, 200 + offset],
                    fill=(200 - j * 30, 100 + j * 20, 50 + j * 40),
                    outline=(255, 255, 255),
                    width=3,
                )
        elif cfg["shapes"] == "rectangles":
            for j in range(5):
                offset = j * 80
                draw.rectangle(
                    [60 + offset, 100 + offset, 180 + offset, 220 + offset],
                    fill=(50 + j * 40, 200 - j * 30, 100 + j * 20),
                    outline=(255, 255, 255),
                    width=3,
                )
        elif cfg["shapes"] == "diamonds":
            for j in range(4):
                cx, cy = 160 + j * 100, 320
                size = 60
                draw.polygon(
                    [(cx, cy - size), (cx + size, cy), (cx, cy + size), (cx - size, cy)],
                    fill=(100 + j * 40, 50 + j * 30, 200 - j * 20),
                    outline=(255, 255, 255),
                )
        elif cfg["shapes"] == "stripes":
            for j in range(0, SIZE[0], 40):
                color_val = (j * 3) % 256
                draw.rectangle(
                    [j, 0, j + 20, SIZE[1]],
                    fill=(color_val, 255 - color_val, 128),
                )

        # Add a large letter label for visual distinction
        draw.text((280, 280), cfg["label"], fill=(255, 255, 255))

        filename = f"normal_{i + 1:02d}.jpg"
        img.save(os.path.join(OUTPUT_DIR, filename), "JPEG", quality=95)
        print(f"  Created {filename}")


def main() -> None:
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Clean previous run
    for f in os.listdir(OUTPUT_DIR):
        if f.endswith(".jpg"):
            os.remove(os.path.join(OUTPUT_DIR, f))

    print("Generating near-duplicate images (8)...")
    generate_near_duplicates(8)

    print("Generating blurry images (4)...")
    generate_blurry(4)

    print("Generating normal images (4)...")
    generate_normal(4)

    total = len([f for f in os.listdir(OUTPUT_DIR) if f.endswith(".jpg")])
    print(f"\nDone! {total} test photos saved to {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
