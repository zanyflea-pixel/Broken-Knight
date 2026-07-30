import os
import bpy
from mathutils import Vector

ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),".."))
OUT=os.path.join(ROOT,"previews","death_checks")
os.makedirs(OUT,exist_ok=True)
scene=bpy.context.scene
scene.render.engine="BLENDER_WORKBENCH"
scene.display.shading.light="STUDIO"
scene.display.shading.color_type="MATERIAL"
scene.display.shading.show_shadows=True
scene.render.resolution_x=260;scene.render.resolution_y=360;scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
scene.world.color=(.025,.025,.030)
for obj in scene.objects:
    for modifier in getattr(obj,"modifiers",[]):
        if modifier.type=="SUBSURF":modifier.levels=0;modifier.render_levels=0
bpy.ops.mesh.primitive_plane_add(size=6,location=(0,0,0))
floor=bpy.context.object
mat=bpy.data.materials.new("DeathCheckFloor");mat.diffuse_color=(.12,.13,.15,1);floor.data.materials.append(mat)
bpy.ops.object.camera_add();camera=bpy.context.object;camera.data.lens=65;scene.camera=camera
camera.location=Vector((-2.75,-3.10,1.30));camera.rotation_euler=(Vector((0,0,0.9))-camera.location).to_track_quat("-Z","Y").to_euler()
arm=bpy.data.objects["HeroRig"]
action=bpy.data.actions.get("Death")
if action is None:raise RuntimeError("Death action missing")
arm.animation_data.action=action
for frame in (1,12,23,34):
    scene.frame_set(frame);scene.render.filepath=os.path.join(OUT,f"Death_{frame:02d}.png");bpy.ops.render.render(write_still=True)
print("DEATH_RENDER|%s"%OUT)
