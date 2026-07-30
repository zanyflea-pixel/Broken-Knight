"""Add dedicated royal Warrior stance and melee actions to the existing rig."""
import bpy, importlib.util, os

script_dir=os.path.dirname(__file__)
spec=importlib.util.spec_from_file_location("hero_rig_builder",os.path.join(script_dir,"rig_hero_for_godot.py"))
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
arm=bpy.data.objects["HeroRig"];arm.animation_data_create()

for name in ("WarriorIdle","WarriorWalk","SwordSlash","ShieldBash","Death"):
    old=bpy.data.actions.get(name)
    if old:bpy.data.actions.remove(old)

def warrior_guard_pose(base_pose,phase=0):
    """Weight-bearing shield guard with the sword beside the right shoulder."""
    pose=dict(base_pose)
    sway=(-1.5,-.7,.4,1.0,1.5,.7,-.4,-1.0)[phase%8]
    pose.update({
        # Abduct both upper arms in mirrored local-Y directions.  The rejected
        # revision used the same Y sign on both sides, pulling the sword elbow
        # into the ribs even though the arm appeared more twisted.
        "clavicle.L":{"rot":(-3.0,-2.0,-6.0)},
        "upper_arm.L":{"rot":(-31.0+.12*sway,34.0,-18.0)},
        "forearm.L":{"rot":(-80.0+.26*sway,-18.0,12.0)},
        "hand.L":{"rot":(-2.0,-7.0,8.0)},
        "clavicle.R":{"rot":(-2.0,2.0,6.0)},
        "upper_arm.R":{"rot":(-16.0-.10*sway,-34.0,6.0)},
        "forearm.R":{"rot":(-88.0-.22*sway,18.0,-9.0)},
        "hand.R":{"rot":(4.0,-7.0,-13.0)},
    })
    return pose


warrior_idle=bpy.data.actions.new("WarriorIdle");arm.animation_data.action=warrior_idle
guard=warrior_guard_pose({
    "root":{"loc":(0,-.010,0)},
    "pelvis":{"rot":(2.5,-4.0,-.5)},
    "spine":{"rot":(2.2,2.5,.4)},
    "chest":{"rot":(-1.0,3.0,-.4)},
    "neck":{"rot":(-2.0,-1.0,.2)},
    "head":{"rot":(-3.0,1.2,-.2)},
    "thigh.L":{"rot":(-4.0,0,-2.0)},
    "thigh.R":{"rot":(-3.0,0,2.0)},
    "shin.L":{"rot":(9.0,0,0)},
    "shin.R":{"rot":(7.0,0,0)},
})
builder.key_pose(arm,1,guard)
ready=warrior_guard_pose(dict(guard),1)
ready.update({
    "root":{"loc":(-.003,-.008,0)},
    "pelvis":{"rot":(2.2,-3.2,-.35)},
    "spine":{"rot":(2.5,2.0,.35)},
    "chest":{"rot":(-1.4,2.5,-.35),"scale":(1.004,1.002,1.004)},
    "head":{"rot":(-3.3,.8,-.15)},
    "thigh.L":{"rot":(-3.5,0,-2.0)},
    "shin.L":{"rot":(8.0,0,0)},
})
builder.key_pose(arm,13,ready)
breathe=warrior_guard_pose(dict(guard),2)
breathe.update({
    "root":{"loc":(-.005,-.004,0)},
    "pelvis":{"rot":(1.6,-2.0,.2)},
    "spine":{"rot":(3.0,1.2,.45)},
    "chest":{"rot":(-2.0,1.5,-.5),"scale":(1.007,1.003,1.007)},
    "neck":{"rot":(-1.2,-.2,.2)},
    "head":{"rot":(-2.2,.2,-.2)},
    "thigh.L":{"rot":(-2.5,0,-2.0)},
    "thigh.R":{"rot":(-4.0,0,2.0)},
    "shin.L":{"rot":(6.0,0,0)},
    "shin.R":{"rot":(9.0,0,0)},
})
builder.key_pose(arm,25,breathe)
settle=warrior_guard_pose(dict(guard),4)
settle.update({
    "root":{"loc":(.003,-.011,0)},
    "pelvis":{"rot":(2.8,-.5,-.1)},
    "spine":{"rot":(2.0,.5,.25)},
    "chest":{"rot":(-.8,.8,-.25)},
    "head":{"rot":(-3.0,1.6,.1)},
    "thigh.L":{"rot":(-4.5,0,-2.0)},
    "thigh.R":{"rot":(-2.5,0,2.0)},
    "shin.L":{"rot":(10.0,0,0)},
    "shin.R":{"rot":(6.0,0,0)},
})
builder.key_pose(arm,37,settle)
watch=warrior_guard_pose(dict(guard),5)
watch.update({
    "pelvis":{"rot":(1.2,1.5,-.3)},
    "chest":{"rot":(-1.2,-2.0,.5)},
    "neck":{"rot":(-.8,-2.2,-.2)},
    "head":{"rot":(-1.4,2.8,.2)},
})
builder.key_pose(arm,49,watch)
builder.key_pose(arm,61,ready)
builder.key_pose(arm,73,guard)
warrior_idle.frame_start=1;warrior_idle.frame_end=73

def warrior_walk_pose(phase):
    pose=warrior_guard_pose(builder.walk_pose(phase),phase)
    # A guarded advance keeps the weapon platform quieter than the hips while
    # retaining a forward commitment through the sternum and head.
    pose["spine"]={"rot":(3.6,-.28*pose["pelvis"]["rot"][1],-.22*pose["pelvis"]["rot"][2])}
    pose["chest"]={"rot":(4.8,-.38*pose["pelvis"]["rot"][1],-.20*pose["pelvis"]["rot"][2])}
    pose["neck"]={"rot":(-3.0,0,0)}
    pose["head"]={"rot":(-4.0,0,0)}
    shield_lift=(1.5,.5,-.7,-1.2,-1.5,-.5,.7,1.2)[phase%8]
    sword_inertia=(-1.0,-.4,.6,1.1,1.0,.4,-.6,-1.1)[phase%8]
    pose["upper_arm.L"]={"rot":(-31.0+.10*shield_lift,34.0,-18.0+.35*shield_lift)}
    pose["forearm.L"]={"rot":(-80.0+.32*shield_lift,-18.0,12.0)}
    pose["upper_arm.R"]={"rot":(-16.0-.12*sword_inertia,-34.0,6.0+.35*sword_inertia)}
    pose["forearm.R"]={"rot":(-88.0-.28*sword_inertia,18.0,-9.0)}
    return pose


warrior_walk=bpy.data.actions.new("WarriorWalk");arm.animation_data.action=warrior_walk
for phase,frame in enumerate((1,4,7,10,13,16,19,22)):
    pose=warrior_walk_pose(phase)
    builder.key_pose(arm,frame,pose)
builder.key_pose(arm,25,warrior_walk_pose(0))
warrior_walk.frame_start=1;warrior_walk.frame_end=25

def merged_pose(base,updates):
    result=dict(base)
    result.update(updates)
    return result


sword=bpy.data.actions.new("SwordSlash");arm.animation_data.action=sword
builder.key_pose(arm,1,guard)
builder.key_pose(arm,4,merged_pose(guard,{
    "root":{"loc":(-.010,-.020,-.020)},
    "pelvis":{"rot":(4,-13,-2)},"spine":{"rot":(3,-18,2)},"chest":{"rot":(-2,-24,3)},
    "neck":{"rot":(-2,8,-1)},"head":{"rot":(-3,10,-1)},
    "thigh.L":{"rot":(-7,0,-2)},"thigh.R":{"rot":(-2,0,2)},"shin.L":{"rot":(15,0,0)},"shin.R":{"rot":(6,0,0)},
    "upper_arm.R":{"rot":(26,-34,44)},"forearm.R":{"rot":(-108,18,-18)},"hand.R":{"rot":(14,-8,-26)},
    "upper_arm.L":{"rot":(-33,44,-18)},"forearm.L":{"rot":(-86,-22,14)},
}))
builder.key_pose(arm,6,merged_pose(guard,{
    "root":{"loc":(0,-.016,.012)},
    "pelvis":{"rot":(3,-4,-1)},"spine":{"rot":(0,-6,1)},"chest":{"rot":(-4,-8,1.5)},
    "neck":{"rot":(0,3,-.5)},"head":{"rot":(-1,4,-.5)},
    "upper_arm.R":{"rot":(-18,-34,12)},"forearm.R":{"rot":(-72,16,-10)},"hand.R":{"rot":(2,-8,-8)},
    "upper_arm.L":{"rot":(-33,46,-19)},"forearm.L":{"rot":(-86,-23,14)},
}))
builder.key_pose(arm,8,merged_pose(guard,{
    "root":{"loc":(.012,-.012,.060)},
    "pelvis":{"rot":(2,8,1.2)},"spine":{"rot":(-5,12,-1.7)},"chest":{"rot":(-9,15,-2.5)},
    "neck":{"rot":(4,-5,1.2)},"head":{"rot":(2,-7,1.2)},
    "thigh.L":{"rot":(-2,0,-2)},"thigh.R":{"rot":(-10,0,2)},"shin.L":{"rot":(6,0,0)},"shin.R":{"rot":(18,0,0)},
    "upper_arm.R":{"rot":(-82,-30,-32)},"forearm.R":{"rot":(-24,12,10)},"hand.R":{"rot":(-14,-8,20)},
    "upper_arm.L":{"rot":(-34,50,-19)},"forearm.L":{"rot":(-86,-25,14)},
}))
builder.key_pose(arm,11,merged_pose(guard,{
    "root":{"loc":(.006,-.008,.040)},
    "pelvis":{"rot":(2,4,.6)},"spine":{"rot":(-3,7,-1.1)},"chest":{"rot":(-6,8,-1.5)},
    "upper_arm.R":{"rot":(-64,-32,-23)},"forearm.R":{"rot":(-36,14,8)},"hand.R":{"rot":(-10,-5,14)},
    "upper_arm.L":{"rot":(-33,46,-18)},"forearm.L":{"rot":(-84,-23,14)},
}))
builder.key_pose(arm,16,warrior_guard_pose(dict(guard),6))
builder.key_pose(arm,19,guard)
sword.frame_start=1;sword.frame_end=19

shield=bpy.data.actions.new("ShieldBash");arm.animation_data.action=shield
builder.key_pose(arm,1,guard)
builder.key_pose(arm,4,merged_pose(guard,{
    "root":{"loc":(0,-.055,-.025)},"pelvis":{"rot":(10,-3,0)},"spine":{"rot":(8,2,0)},"chest":{"rot":(5,3,0)},
    "thigh.L":{"rot":(-15,0,-2)},"thigh.R":{"rot":(-12,0,2)},"shin.L":{"rot":(30,0,0)},"shin.R":{"rot":(25,0,0)},
    "upper_arm.L":{"rot":(-48,32,-25)},"forearm.L":{"rot":(-112,-18,22)},"hand.L":{"rot":(-8,-8,16)},
    "upper_arm.R":{"rot":(-12,-50,24)},"forearm.R":{"rot":(-104,26,-10)},
}))
builder.key_pose(arm,6,merged_pose(guard,{
    "root":{"loc":(0,-.040,.030)},"pelvis":{"rot":(5,-1,0)},"spine":{"rot":(2,1,0)},"chest":{"rot":(-2,1,0)},
    "upper_arm.L":{"rot":(-62,30,-21)},"forearm.L":{"rot":(-86,-16,15)},"hand.L":{"rot":(-5,-6,12)},
    "upper_arm.R":{"rot":(-18,-50,29)},"forearm.R":{"rot":(-108,26,-12)},
}))
builder.key_pose(arm,8,merged_pose(guard,{
    "root":{"loc":(0,-.020,.105)},"pelvis":{"rot":(-6,2,0)},"spine":{"rot":(-11,-2,0)},"chest":{"rot":(-16,-3,0)},
    "neck":{"rot":(6,1,0)},"head":{"rot":(4,1,0)},
    "thigh.L":{"rot":(-4,0,-2)},"thigh.R":{"rot":(-9,0,2)},"shin.L":{"rot":(10,0,0)},"shin.R":{"rot":(17,0,0)},
    "upper_arm.L":{"rot":(-78,27,-16)},"forearm.L":{"rot":(-54,-12,8)},"hand.L":{"rot":(-2,-4,8)},
    "upper_arm.R":{"rot":(-24,-50,32)},"forearm.R":{"rot":(-110,26,-14)},
}))
builder.key_pose(arm,11,merged_pose(guard,{
    "root":{"loc":(0,-.010,.050)},"pelvis":{"rot":(-2,1,0)},"spine":{"rot":(-4,-1,0)},"chest":{"rot":(-6,-1,0)},
    "upper_arm.L":{"rot":(-58,30,-20)},"forearm.L":{"rot":(-72,-15,12)},
    "upper_arm.R":{"rot":(-20,-50,24)},"forearm.R":{"rot":(-104,26,-11)},
}))
builder.key_pose(arm,16,warrior_guard_pose(dict(guard),3))
builder.key_pose(arm,19,guard)
shield.frame_start=1;shield.frame_end=19

# Full-body collapse shared by every equipment state. The first beat loses the
# knees, the second catches on one hand, and the final pose settles on the side
# without stretching the neck or driving the face into the ground.
death=bpy.data.actions.new("Death");arm.animation_data.action=death
builder.key_pose(arm,1,{})
builder.key_pose(arm,4,{"root":{"loc":(0,.01,-.01)},"pelvis":{"rot":(4,0,3)},"spine":{"rot":(-3,0,-4)},"chest":{"rot":(-6,0,-6)},"neck":{"rot":(4,0,2)},"head":{"rot":(7,0,3)},"thigh.L":{"rot":(-4,0,-2)},"thigh.R":{"rot":(-8,0,4)},"shin.L":{"rot":(10,0,0)},"shin.R":{"rot":(18,0,0)},"upper_arm.L":{"rot":(-22,8,-18)},"forearm.L":{"rot":(-62,-8,6)},"upper_arm.R":{"rot":(12,-8,15)},"forearm.R":{"rot":(-54,8,-6)}})
builder.key_pose(arm,7,{"root":{"loc":(0,0,-.03)},"pelvis":{"rot":(12,0,8)},"spine":{"rot":(10,0,-6)},"chest":{"rot":(-8,0,-9)},"head":{"rot":(5,0,4)},"thigh.L":{"rot":(-10,0,-5)},"thigh.R":{"rot":(-20,0,8)},"shin.L":{"rot":(28,0,0)},"shin.R":{"rot":(42,0,0)},"upper_arm.L":{"rot":(-48,0,-28)},"forearm.L":{"rot":(-75,0,0)},"upper_arm.R":{"rot":(25,0,20)},"forearm.R":{"rot":(-35,0,0)}})
builder.key_pose(arm,11,{"root":{"loc":(0,.035,-.12),"rot":(-8,0,-7)},"pelvis":{"rot":(7,0,4)},"spine":{"rot":(2,0,-8)},"chest":{"rot":(-16,0,-11)},"neck":{"rot":(9,0,3)},"head":{"rot":(13,0,6)},"thigh.L":{"rot":(-2,0,-6)},"thigh.R":{"rot":(-28,0,10)},"shin.L":{"rot":(42,0,0)},"shin.R":{"rot":(58,0,0)},"upper_arm.L":{"rot":(-62,0,-24)},"forearm.L":{"rot":(-52,0,0)},"upper_arm.R":{"rot":(38,0,25)},"forearm.R":{"rot":(-24,0,0)}})
builder.key_pose(arm,16,{"root":{"loc":(0,.10,-.28),"rot":(-32,0,-18)},"pelvis":{"rot":(-18,0,-15)},"spine":{"rot":(-24,0,-12)},"chest":{"rot":(-30,0,-10)},"neck":{"rot":(16,0,4)},"head":{"rot":(20,0,8)},"thigh.L":{"rot":(18,0,-8)},"thigh.R":{"rot":(-38,0,12)},"shin.L":{"rot":(58,0,0)},"shin.R":{"rot":(72,0,0)},"upper_arm.L":{"rot":(-74,0,-18)},"forearm.L":{"rot":(-28,0,0)},"upper_arm.R":{"rot":(52,0,32)},"forearm.R":{"rot":(-12,0,0)}})
builder.key_pose(arm,22,{"root":{"loc":(0,.185,-.51),"rot":(-63,0,-22)},"pelvis":{"rot":(-15,0,-12)},"spine":{"rot":(-16,0,-8)},"chest":{"rot":(-21,0,-6)},"neck":{"rot":(14,0,3)},"head":{"rot":(18,0,7)},"thigh.L":{"rot":(24,0,-8)},"thigh.R":{"rot":(-29,0,11)},"shin.L":{"rot":(68,0,0)},"shin.R":{"rot":(68,0,0)},"upper_arm.L":{"rot":(-82,0,-14)},"forearm.L":{"rot":(-19,0,0)},"upper_arm.R":{"rot":(59,0,30)},"forearm.R":{"rot":(-9,0,0)}})
builder.key_pose(arm,27,{"root":{"loc":(0,.22,-.62),"rot":(-76,0,-22)},"pelvis":{"rot":(-12,0,-10)},"spine":{"rot":(-10,0,-5)},"chest":{"rot":(-14,0,-4)},"neck":{"rot":(12,0,2)},"head":{"rot":(16,0,5)},"thigh.L":{"rot":(26,0,-8)},"thigh.R":{"rot":(-22,0,10)},"shin.L":{"rot":(72,0,0)},"shin.R":{"rot":(62,0,0)},"upper_arm.L":{"rot":(-85,0,-12)},"forearm.L":{"rot":(-15,0,0)},"upper_arm.R":{"rot":(62,0,28)},"forearm.R":{"rot":(-8,0,0)}})
builder.key_pose(arm,31,{"root":{"loc":(0,.235,-.64),"rot":(-80,0,-22)},"pelvis":{"rot":(-10,0,-9)},"spine":{"rot":(-8,0,-4)},"chest":{"rot":(-12,0,-3)},"neck":{"rot":(10,0,2)},"head":{"rot":(12,0,4)},"thigh.L":{"rot":(25,0,-8)},"thigh.R":{"rot":(-21,0,10)},"shin.L":{"rot":(70,0,0)},"shin.R":{"rot":(61,0,0)},"upper_arm.L":{"rot":(-84,0,-11)},"forearm.L":{"rot":(-14,0,0)},"upper_arm.R":{"rot":(61,0,27)},"forearm.R":{"rot":(-8,0,0)}})
builder.key_pose(arm,34,{"root":{"loc":(0,.24,-.65),"rot":(-79,0,-22)},"head":{"rot":(13,0,4)},"upper_arm.L":{"rot":(-82,0,-10)},"upper_arm.R":{"rot":(60,0,26)}})
death.frame_start=1;death.frame_end=34

actions=[a for a in bpy.data.actions if a.name in ("Idle","Walk","TorchIdle","TorchWalk","StaffIdle","StaffWalk","Jump","Land","Roll","Death","Spark","Nova","Blink","Orb","StaffSpark","StaffNova","StaffBlink","StaffOrb","WarriorIdle","WarriorWalk","SwordSlash","ShieldBash")]
builder.stash_actions(arm,*sorted(actions,key=lambda a:a.name))
arm.animation_data.action=None;bpy.context.scene.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print("HERO_COMBAT_ANIMATIONS|WarriorIdle,WarriorWalk,SwordSlash,ShieldBash,Death")
