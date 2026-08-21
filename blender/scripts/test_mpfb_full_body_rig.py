"""Temporary proof that the continuous MPFB body can be fitted and weighted."""

import bpy
from bl_ext.user_default.mpfb.services.humanservice import HumanService


human = bpy.data.objects["HeroProfessionalTopology"]
for modifier in list(human.modifiers):
    if modifier.type == "SUBSURF":
        human.modifiers.remove(modifier)
rig = HumanService.add_builtin_rig(human, "game_engine", import_weights=True)
print(f"MPFB_RIG_TEST|rig={rig.name}|bones={len(rig.data.bones)}|groups={len(human.vertex_groups)}|mods={[(m.type,m.object.name if m.type=='ARMATURE' and m.object else '') for m in human.modifiers]}")
for name in ("Root","pelvis","spine_01","spine_02","spine_03","neck_01","head","clavicle_l","upperarm_l","lowerarm_l","hand_l","thigh_l","calf_l","foot_l","ball_l"):
    bone=rig.data.bones.get(name)
    if bone:
        print(f"MPFB_BONE|{name}|head={tuple(round(v,5) for v in bone.head_local)}|tail={tuple(round(v,5) for v in bone.tail_local)}|length={bone.length:.5f}")
minimum = 10.0
maximum = 0.0
unweighted = 0
for vertex in human.data.vertices:
    total = sum(membership.weight for membership in vertex.groups if human.vertex_groups[membership.group].name in rig.data.bones)
    minimum = min(minimum, total)
    maximum = max(maximum, total)
    if total < 0.999:
        unweighted += 1
print(f"MPFB_RIG_WEIGHTS|min={minimum:.6f}|max={maximum:.6f}|unweighted={unweighted}")
