"""Build the Royal Vanguard magic staff directly onto the hero's right-hand rig."""
import math
import os
import bpy
from mathutils import Vector

ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),"..",".."))
RIGGED=os.path.join(ROOT,"blender","BrokenKnight_Hero_Master.blend")
PREFIX="RoyalStaff_"
GRIP_X=.345
GRIP_Y=-.006

def material(name,color,metallic,roughness,emission=None,strength=0.0):
    mat=bpy.data.materials.get(name) or bpy.data.materials.new(name);mat.diffuse_color=color;mat.use_nodes=True
    mat["export_metallic"]=metallic;mat["export_roughness"]=roughness
    if emission:mat["export_emission"]=emission;mat["export_emission_strength"]=strength
    bsdf=mat.node_tree.nodes.get("Principled BSDF");bsdf.inputs["Base Color"].default_value=color;bsdf.inputs["Metallic"].default_value=metallic;bsdf.inputs["Roughness"].default_value=roughness
    if emission:bsdf.inputs["Emission Color"].default_value=emission;bsdf.inputs["Emission Strength"].default_value=strength
    return mat

def skin(obj,arm,mat,smooth=True):
    bpy.context.view_layer.objects.active=obj;obj.select_set(True);bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    if smooth:
        for p in obj.data.polygons:p.use_smooth=True
    obj.data.materials.append(mat);group=obj.vertex_groups.new(name="hand.R");group.add(list(range(len(obj.data.vertices))),1.0,"REPLACE")
    mod=obj.modifiers.new("RoyalStaffRig","ARMATURE");mod.object=arm;obj.parent=arm;obj.select_set(False);return obj

def cylinder(name,z,radius,depth,mat,arm,vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=(GRIP_X,GRIP_Y,z));o=bpy.context.object;o.name=PREFIX+name;return skin(o,arm,mat)

def torus(name,z,major,minor,mat,arm):
    bpy.ops.mesh.primitive_torus_add(major_radius=major,minor_radius=minor,major_segments=28,minor_segments=10,location=(GRIP_X,GRIP_Y,z));o=bpy.context.object;o.name=PREFIX+name;return skin(o,arm,mat)

def sphere(name,loc,scale,mat,arm,segments=24,rings=14):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,location=loc);o=bpy.context.object;o.name=PREFIX+name;o.scale=scale;return skin(o,arm,mat)

def cone_between(name,start,end,r1,r2,mat,arm,vertices=18):
    start,end=Vector(start),Vector(end);delta=end-start
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r1,radius2=r2,depth=delta.length,location=(start+end)*.5);o=bpy.context.object;o.name=PREFIX+name;o.rotation_mode="QUATERNION";o.rotation_quaternion=Vector((0,0,1)).rotation_difference(delta.normalized());return skin(o,arm,mat)

def box(name,loc,size,mat,arm,rotation=(0,0,0),bevel=.005):
    bpy.ops.mesh.primitive_cube_add(location=loc,rotation=rotation);o=bpy.context.object;o.name=PREFIX+name;o.scale=Vector(size)*.5;skin(o,arm,mat,False)
    if bevel:mod=o.modifiers.new("ForgedEdges","BEVEL");mod.width=bevel;mod.segments=2
    return o

def gemstone(name,center,radius,height,mat,arm):
    z=center[2]
    cone_between(name+"Lower",(center[0],center[1],z-height*.5),(center[0],center[1],z),.002,radius,mat,arm,8)
    cone_between(name+"Upper",(center[0],center[1],z),(center[0],center[1],z+height*.5),radius,.002,mat,arm,8)

arm=bpy.data.objects.get("HeroRig")
if arm is None:raise RuntimeError("HeroRig was not found")
for obj in list(bpy.data.objects):
    if obj.name.startswith(PREFIX):bpy.data.objects.remove(obj,do_unlink=True)

blue=material("Royal Staff Blue Enamel",(.025,.075,.255,1),.84,.23)
gold=material("Royal Staff Aged Gold",(.71,.335,.045,1),.92,.23)
steel=material("Royal Staff Dark Steel",(.035,.045,.060,1),.90,.31)
leather=material("Royal Staff Oxblood Leather",(.105,.020,.018,1),.05,.82)
ruby=material("Royal Staff Ruby Focus",(.42,.006,.014,1),.46,.20,(.75,.004,.008,1),.65)
rune=material("Royal Staff Azure Runes",(.015,.18,.75,1),.35,.28,(.010,.08,.40,1),.38)

# Reinforced lower shaft, leather grip and enameled upper stave.
cylinder("LowerShaft",.390,.029,.690,steel,arm)
cylinder("GripCore",.835,.034,.360,steel,arm)
cylinder("UpperShaft",1.275,.047,.570,blue,arm)
cylinder("BlueButtSleeve",.125,.045,.160,blue,arm)
for index,z in enumerate((.035,.105,.205,.645,.665,1.010,1.035,1.555)):
    torus(f"GoldCollar{index}",z,.047 if z<.30 else (.054 if z<1.1 else .064),.009,gold,arm)

# Cross-laced leather wrap, visibly practical rather than painted onto the shaft.
for index in range(8):
    z=.690+index*.041
    box(f"GripWrapA{index}",(GRIP_X-.002,GRIP_Y-.036,z),(.064,.012,.016),leather,arm,rotation=(0,(.38 if index%2==0 else -.38),0),bevel=.0025)
    box(f"GripWrapB{index}",(GRIP_X+.002,GRIP_Y+.036,z),(.064,.012,.016),leather,arm,rotation=(0,(-.38 if index%2==0 else .38),0),bevel=.0025)

# Lower butt spike and protective gold shoulders.
# A compact ferrule keeps the planted staff above the terrain throughout the
# walk cycle; the former long spike visibly sank below the floor on passing.
cone_between("ButtSpike",(GRIP_X,GRIP_Y,.045),(GRIP_X,GRIP_Y,-.020),.038,.003,steel,arm,16)
for side in (-1,1):
    cone_between(f"ButtGoldFlange{side}",(GRIP_X+side*.033,GRIP_Y,.180),(GRIP_X+side*.060,GRIP_Y,.080),.012,.004,gold,arm,14)

# Lion seal and small glowing runes on the upper enamel shaft.
sphere("LionBody",(GRIP_X,GRIP_Y-.053,1.315),(.030,.010,.044),gold,arm,18,10)
sphere("LionHead",(GRIP_X,GRIP_Y-.055,1.360),(.023,.010,.022),gold,arm,18,10)
for idx,(a,b) in enumerate((((-.020,1.330),(-.055,1.350)),((-.018,1.290),(-.048,1.260)),((.018,1.290),(.048,1.260)),((.018,1.330),(.052,1.350)))):
    cone_between(f"LionLimb{idx}",(GRIP_X+a[0],GRIP_Y-.055,a[1]),(GRIP_X+b[0],GRIP_Y-.057,b[1]),.007,.003,gold,arm,10)
for idx,z in enumerate((1.120,1.190,1.430,1.500)):
    sphere(f"Rune{idx}",(GRIP_X+(idx%2*2-1)*.020,GRIP_Y-.052,z),(.008,.005,.015),rune,arm,12,8)

# Shield-like head housing, four gold claws, blue rune blades and faceted ruby focus.
sphere("HeadGoldBase",(GRIP_X,GRIP_Y,1.590),(.105,.075,.085),gold,arm,22,14)
sphere("HeadBlueInset",(GRIP_X,GRIP_Y-.010,1.600),(.086,.066,.067),blue,arm,22,14)
box("HeadShield",(GRIP_X,GRIP_Y-.071,1.605),(.140,.018,.150),blue,arm,bevel=.015)
sphere("HeadLion",(GRIP_X,GRIP_Y-.084,1.610),(.042,.009,.045),gold,arm,18,10)

gemstone("RubyFocus",(GRIP_X,GRIP_Y,1.855),.105,.300,ruby,arm)
for side in (-1,1):
    # Outer rune blade.
    cone_between(f"BlueBladeLower{side}",(GRIP_X+side*.065,GRIP_Y,1.585),(GRIP_X+side*.155,GRIP_Y,1.745),.028,.040,blue,arm,16)
    cone_between(f"BlueBladeUpper{side}",(GRIP_X+side*.155,GRIP_Y,1.745),(GRIP_X+side*.135,GRIP_Y,1.995),.040,.006,blue,arm,16)
    cone_between(f"GoldBladeEdgeLower{side}",(GRIP_X+side*.085,GRIP_Y-.018,1.605),(GRIP_X+side*.176,GRIP_Y-.018,1.755),.010,.010,gold,arm,12)
    cone_between(f"GoldBladeEdgeUpper{side}",(GRIP_X+side*.176,GRIP_Y-.018,1.755),(GRIP_X+side*.145,GRIP_Y-.018,2.005),.010,.003,gold,arm,12)
    # Inner crystal claw.
    cone_between(f"CrystalClawLower{side}",(GRIP_X+side*.052,GRIP_Y-.040,1.620),(GRIP_X+side*.096,GRIP_Y-.040,1.765),.018,.014,gold,arm,14)
    cone_between(f"CrystalClawUpper{side}",(GRIP_X+side*.096,GRIP_Y-.040,1.765),(GRIP_X+side*.075,GRIP_Y-.040,1.965),.014,.003,gold,arm,14)
    for index,z in enumerate((1.715,1.795,1.875)):
        sphere(f"HeadRune{side}_{index}",(GRIP_X+side*(.125+index*.005),GRIP_Y-.040,z),(.009,.006,.016),rune,arm,12,8)

torus("FocusLowerCollar",1.690,.083,.012,gold,arm)
torus("FocusUpperRing",1.780,.101,.009,gold,arm)

bpy.ops.wm.save_as_mainfile(filepath=RIGGED)
print("ROYAL_STAFF_BUILT|%s|parts=%d"%(RIGGED,len([o for o in bpy.data.objects if o.name.startswith(PREFIX)])))
