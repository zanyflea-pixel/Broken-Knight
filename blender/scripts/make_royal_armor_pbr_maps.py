"""Derive tiled normal and roughness maps from the generated filigree texture."""

from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
TEXTURES = ROOT / "godot" / "assets" / "hero" / "textures"
SOURCE = TEXTURES / "royal_cobalt_filigree_v1.png"
NORMAL = TEXTURES / "royal_cobalt_filigree_normal_v1.png"
ROUGHNESS = TEXTURES / "royal_cobalt_filigree_roughness_v1.png"

image = Image.open(SOURCE).convert("RGB")
gray_image = image.convert("L").filter(ImageFilter.GaussianBlur(radius=0.7))
height = np.asarray(gray_image, dtype=np.float32) / 255.0

# Wrap derivatives at the texture edges so the generated maps remain tileable.
dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 3.2
dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 3.2
nx = -dx
ny = dy
nz = np.ones_like(height) * 0.72
length = np.sqrt(nx * nx + ny * ny + nz * nz)
normal = np.stack((nx / length, ny / length, nz / length), axis=2)
normal = np.clip((normal * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
Image.fromarray(normal, mode="RGB").save(NORMAL)

# Dark engraved recesses are rougher; brighter worn/gilt marks are smoother.
local = height - np.asarray(
    gray_image.filter(ImageFilter.GaussianBlur(radius=6.0)), dtype=np.float32
) / 255.0
roughness = np.clip(168.0 - local * 185.0, 92.0, 220.0).astype(np.uint8)
Image.fromarray(roughness, mode="L").save(ROUGHNESS)

print(f"ROYAL_PBR_MAPS|normal={NORMAL}|roughness={ROUGHNESS}|size={image.size}")
