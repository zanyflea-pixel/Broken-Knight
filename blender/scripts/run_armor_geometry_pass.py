"""Rebuild and polish armor geometry without touching accepted animations."""

import os
import runpy


SCRIPT_DIR = os.path.dirname(__file__)
for script_name in ("build_royal_armor.py", "polish_royal_hero_visuals.py"):
    print(f"ARMOR_GEOMETRY_STAGE|{script_name}")
    runpy.run_path(os.path.join(SCRIPT_DIR, script_name), run_name="__main__")
