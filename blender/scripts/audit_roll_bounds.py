import bpy
from mathutils import Vector

scene=bpy.context.scene
arm=bpy.data.objects["HeroRig"]
arm.animation_data.action=bpy.data.actions["Roll"]
for frame in (1,4,7,10,13,16,19):
    scene.frame_set(frame);bpy.context.view_layer.update()
    obj=bpy.data.objects["ConnectedBody"]
    evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    points=[evaluated.matrix_world@Vector(corner) for corner in evaluated.bound_box]
    low=Vector((min(p.x for p in points),min(p.y for p in points),min(p.z for p in points)))
    high=Vector((max(p.x for p in points),max(p.y for p in points),max(p.z for p in points)))
    center=(low+high)*.5
    print("ROLL_BOUNDS|frame=%d|center=%.3f,%.3f,%.3f|minz=%.3f|maxz=%.3f"%(frame,center.x,center.y,center.z,low.z,high.z))
