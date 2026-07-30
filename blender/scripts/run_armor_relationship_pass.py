"""Apply the repeatable post-build stages for the current armor iteration."""

import os
import runpy


SCRIPT_DIR = os.path.dirname(__file__)
for script_name in (
    "polish_royal_hero_visuals.py",
    "refresh_rig_animations.py",
    "add_warrior_animations.py",
    "refine_combat_animation_pass.py",
    "build_royal_staff.py",
):
    print(f"ARMOR_PASS_STAGE|{script_name}")
    runpy.run_path(os.path.join(SCRIPT_DIR, script_name), run_name="__main__")
