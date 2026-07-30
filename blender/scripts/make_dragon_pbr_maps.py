"""Derive game-ready normal and roughness maps from the authored dragon scales."""

from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter, ImageOps


ROOT = Path(__file__).resolve().parents[2]
TEXTURES = ROOT / "godot" / "assets" / "enemies" / "textures"
SOURCE = TEXTURES / "cave_dragon_scales_v1.png"
NORMAL = TEXTURES / "cave_dragon_scales_normal_v1.png"
ROUGHNESS = TEXTURES / "cave_dragon_scales_roughness_v1.png"


source = Image.open(SOURCE).convert("RGB")
height_image = ImageOps.grayscale(source).filter(ImageFilter.GaussianBlur(1.15))
height = np.asarray(height_image, dtype=np.float32) / 255.0

gradient_x = np.gradient(height, axis=1)
gradient_y = np.gradient(height, axis=0)
strength = 4.25
normal = np.dstack((-gradient_x * strength, -gradient_y * strength, np.ones_like(height)))
normal /= np.maximum(np.linalg.norm(normal, axis=2, keepdims=True), 1.0e-6)
normal_rgb = np.clip((normal * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
Image.fromarray(normal_rgb, "RGB").save(NORMAL)

# Cracked recesses stay rough while worn scale ridges catch a restrained sheen.
rough = ImageOps.invert(height_image)
rough = ImageEnhance.Contrast(rough).enhance(1.28)
rough_values = np.asarray(rough, dtype=np.float32)
rough_values = np.clip(118.0 + rough_values * 0.43, 0, 255).astype(np.uint8)
Image.fromarray(rough_values, "L").save(ROUGHNESS)

print(f"DRAGON_PBR|source={SOURCE}|normal={NORMAL}|roughness={ROUGHNESS}|size={source.size}")
