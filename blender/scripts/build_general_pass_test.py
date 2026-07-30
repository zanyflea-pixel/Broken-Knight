import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_hero_restart as hero

hero.OUT = os.path.abspath(os.path.join(HERE, "..", "hero_general_pass_test.blend"))
hero.build()
