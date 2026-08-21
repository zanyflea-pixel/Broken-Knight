import os
import bpy

target = os.environ.get("BK_SAVE_AS")
if not target:
    raise RuntimeError("BK_SAVE_AS is required")
bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(target), check_existing=False)
print("SAVED_AS|" + os.path.abspath(target))
