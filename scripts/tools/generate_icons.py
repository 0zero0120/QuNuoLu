"""Generate 32x32 pixel art PNG icons for cards and potions."""
import zlib
import struct
import os

OUT_DIR = "F:/GodotProjects/毕设游戏项目/assets/icons"
os.makedirs(OUT_DIR, exist_ok=True)


def create_png(width, height, pixels):
    """pixels: list of (r,g,b,a) tuples, row-major."""
    raw = b""
    for y in range(height):
        raw += b"\x00"  # filter: none
        for x in range(width):
            raw += bytes(pixels[y * width + x])

    compressed = zlib.compress(raw)

    def chunk(ct, data):
        c = ct + data
        crc = struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
        return struct.pack(">I", len(data)) + c + crc

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", compressed)
        + chunk(b"IEND", b"")
    )


def scale_nearest(pixels_16, new_size=32):
    """Nearest-neighbor 2x scale from 16x16 to 32x32."""
    result = [(0, 0, 0, 0)] * (new_size * new_size)
    for y in range(16):
        for x in range(16):
            c = pixels_16[y * 16 + x]
            for dy in range(2):
                for dx in range(2):
                    result[(y * 2 + dy) * new_size + (x * 2 + dx)] = c
    return result


def design_to_pixels(design, palette):
    """Convert list-of-strings design + palette dict to 16x16 pixel list."""
    pixels = [(0, 0, 0, 0)] * 256
    for y, row in enumerate(design):
        for x, ch in enumerate(row):
            if ch in palette:
                pixels[y * 16 + x] = palette[ch]
    return pixels


# ── Color palettes ──────────────────────────────────────────

PALETTE_SWORD = {
    "@": (0x7B, 0x1F, 0x18, 255),  # dark outline
    "#": (0xA9, 0x2C, 0x20, 255),  # dark red
    "=": (0xCB, 0x3A, 0x2E, 255),  # mid red
    "-": (0xE8, 0x5D, 0x53, 255),  # light red
    "+": (0xF5, 0xAA, 0xA2, 255),  # highlight
    "o": (0xFF, 0xDC, 0x78, 255),  # gold hilt
    "x": (0xC4, 0x8B, 0x3A, 255),  # brown grip
}

PALETTE_DIAMOND = {
    "@": (0x15, 0x3E, 0x5C, 255),
    "#": (0x1F, 0x5C, 0x8A, 255),
    "=": (0x2C, 0x80, 0xBA, 255),
    "-": (0x5B, 0xAE, 0xDB, 255),
    "+": (0xA8, 0xD8, 0xF0, 255),
}

PALETTE_STAR = {
    "@": (0x11, 0x4D, 0x2A, 255),
    "#": (0x1A, 0x70, 0x3E, 255),
    "=": (0x27, 0xAE, 0x60, 255),
    "-": (0x5C, 0xCC, 0x8A, 255),
    "+": (0xA0, 0xE8, 0xC0, 255),
}

PALETTE_HEALTH = {
    "@": (0x7B, 0x1F, 0x18, 255),
    "#": (0xC0, 0x39, 0x2B, 255),
    "=": (0xE7, 0x4C, 0x3C, 255),
    "-": (0xF1, 0x94, 0x8A, 255),
    "+": (0xFD, 0xD8, 0xD4, 255),
    "w": (0xFD, 0xF2, 0xF0, 255),  # white highlight
}

PALETTE_STRENGTH = {
    "@": (0x93, 0x3A, 0x0A, 255),
    "#": (0xC0, 0x53, 0x0E, 255),
    "=": (0xE6, 0x7E, 0x22, 255),
    "-": (0xF0, 0xA8, 0x6A, 255),
    "+": (0xF8, 0xCD, 0xA8, 255),
}

PALETTE_BLOCK = {
    "@": (0x3D, 0x4F, 0x5F, 255),
    "#": (0x56, 0x6D, 0x7E, 255),
    "=": (0x7F, 0x96, 0xA8, 255),
    "-": (0xA8, 0xBC, 0xC8, 255),
    "+": (0xD0, 0xDD, 0xE4, 255),
}

PALETTE_ENERGY = {
    "@": (0x8C, 0x6D, 0x08, 255),
    "#": (0xB7, 0x95, 0x0B, 255),
    "=": (0xE6, 0xBE, 0x0E, 255),
    "-": (0xF5, 0xD5, 0x47, 255),
    "+": (0xFB, 0xEA, 0x9E, 255),
}

PALETTE_EXPLOSIVE = {
    "@": (0x7B, 0x1F, 0x18, 255),
    "#": (0xC0, 0x39, 0x2B, 255),
    "=": (0xE7, 0x4C, 0x3C, 255),
    "-": (0xF3, 0x9C, 0x12, 255),
    "+": (0xFB, 0xCA, 0x5E, 255),
}

# ── 16x16 Pixel Designs ─────────────────────────────────────
# . = transparent

SWORD_DESIGN = [
    "......++........",
    ".....+--+.......",
    ".....=@@=.......",
    ".....=--=.......",
    ".....=@@=.......",
    ".....=--=.......",
    "....o=@@=o......",
    "...o==--==o.....",
    "..o========o....",
    "....=--=.......",
    "....=--=.......",
    "....=--=.......",
    "....x@@x.......",
    "....x--x.......",
    "....x@@x.......",
    "....x--x.......",
]

DIAMOND_DESIGN = [
    "................",
    "......@@.......",
    ".....@--@......",
    "....@=--=@.....",
    "...@=====@.....",
    "..@=======@....",
    ".@=========@...",
    ".@=++===++=@...",
    ".@=++===++=@...",
    ".@=========@...",
    "..@=======@....",
    "...@=====@.....",
    "....@===@......",
    ".....@-@.......",
    "......@@.......",
    "................",
]

STAR_DESIGN = [
    "................",
    "......@@.......",
    ".....@--@......",
    "....@=--=@.....",
    "...@=====@.....",
    "..@=@@-@@=@....",
    ".@==@---@==@...",
    ".@=========@...",
    "@=@@-----@@=@..",
    ".@==@---@==@...",
    ".@==@-@-@==@...",
    "..@=@@@@@=@....",
    "...@=====@.....",
    "....@===@......",
    ".....@-@.......",
    "......@........",
]

HEALTH_DESIGN = [
    "................",
    "......@@@......",
    ".....@@@@@.....",
    "....@@www@@....",
    "....@www@@@....",
    "...@@ww@@=@....",
    "...@@w@@==@....",
    "..@@=@@===@....",
    "..@@@=====@....",
    ".@@=@=====@....",
    ".@==@=====@....",
    "...@======@....",
    "...@=====@.....",
    "...@====@......",
    "....@==@.......",
    ".....@@........",
]

# Bottle base shape (shared by all potions)
# @=dark #=mid = = light .=transparent +=highlight w=white
BOTTLE_BASE = [
    "................",
    "......@@@......",
    ".....@+++@.....",
    "....@+++++@....",
    "....@+++++@....",
    "....@+++++@....",
    ".....@+++@.....",
    "......@@@......",
    "......@@@......",
    ".....@+++@.....",
    "....@+++++@....",
    "....@+++++@....",
    "....@+++++@....",
    "....@+++++@....",
    ".....@@@@......",
    "......@@.......",
]

# Strength - bottle with fist/arrow icon inside
STRENGTH_DESIGN = [
    "................",
    "......@@@......",
    ".....@+++@.....",
    "....@++#++@....",
    "....@+#=#+@....",
    "....@+#=#+@....",
    "....++#=#++....",
    ".....+###+.....",
    "......@@@......",
    ".....@+++@.....",
    "....@+++++@....",
    "....@+++++@....",
    "....@+++++@....",
    "....@+++++@....",
    ".....@@@@......",
    "......@@.......",
]

# Block - bottle with shield icon inside
BLOCK_DESIGN = [
    "................",
    "......@@@......",
    ".....@+++@.....",
    "....@+@@@+@....",
    "....@+@#@+@....",
    "....@+@#@+@....",
    "....@+@#@+@....",
    ".....@@@@@.....",
    "......@@@......",
    ".....@+++@.....",
    "....@+++++@....",
    "....@+++++@....",
    "....@+++++@....",
    "....@+++++@....",
    ".....@@@@......",
    "......@@.......",
]

# Energy - bottle with lightning icon inside
ENERGY_DESIGN = [
    "................",
    "......@@@......",
    ".....@+++@.....",
    "....@++#++@....",
    "....@++#=#@....",
    ".....+###+.....",
    "......#=#......",
    ".....+##+......",
    "......@@@......",
    ".....@+++@.....",
    "....@+++++@....",
    "....@+++++@....",
    "....@+++++@....",
    "....@+++++@....",
    ".....@@@@......",
    "......@@.......",
]

# Explosive - bottle with flame/spark inside
EXPLOSIVE_DESIGN = [
    "................",
    "......@@@......",
    ".....@+++@.....",
    "....@+###+@....",
    "....@#####@....",
    ".....@#@#@.....",
    "....@#####@....",
    "....@#@@@#@....",
    "......@@@......",
    ".....@+++@.....",
    "....@+++++@....",
    "....@+++++@....",
    "....@+++++@....",
    "....@+++++@....",
    ".....@@@@......",
    "......@@.......",
]


def generate():
    icons = {
        "icon_attack": (SWORD_DESIGN, PALETTE_SWORD),
        "icon_skill": (DIAMOND_DESIGN, PALETTE_DIAMOND),
        "icon_ability": (STAR_DESIGN, PALETTE_STAR),
        "icon_health_potion": (HEALTH_DESIGN, PALETTE_HEALTH),
        "icon_strength_potion": (STRENGTH_DESIGN, PALETTE_STRENGTH),
        "icon_block_potion": (BLOCK_DESIGN, PALETTE_BLOCK),
        "icon_energy_potion": (ENERGY_DESIGN, PALETTE_ENERGY),
        "icon_explosive_potion": (EXPLOSIVE_DESIGN, PALETTE_EXPLOSIVE),
    }

    for name, (design, palette) in icons.items():
        p16 = design_to_pixels(design, palette)
        p32 = scale_nearest(p16)
        png_data = create_png(32, 32, p32)
        path = os.path.join(OUT_DIR, f"{name}.png")
        with open(path, "wb") as f:
            f.write(png_data)
        print(f"  ✓ {path}")


if __name__ == "__main__":
    generate()
    print("Done — 8 icons generated.")
