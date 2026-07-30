"""Refresh only warrior actions and staff geometry after pose tuning."""

import os
import runpy


SCRIPT_DIR = os.path.dirname(__file__)
for script_name in ("add_warrior_animations.py", "refine_combat_animation_pass.py", "build_royal_staff.py"):
    print(f"WEAPON_POSE_STAGE|{script_name}")
    runpy.run_path(os.path.join(SCRIPT_DIR, script_name), run_name="__main__")
