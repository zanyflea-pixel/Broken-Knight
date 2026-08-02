extends SceneTree

const HERO_SCENE:PackedScene=preload("res://assets/hero/hero_base_body.glb")
const REQUIRED_SLOTS:=["head","chest","shoulders","hands","feet","pants"]
const REQUIRED_SLOT_MINIMUMS:={"head":1,"chest":8,"shoulders":12,"hands":6,"feet":10,"pants":5}
const REQUIRED_ACTIONS:=["Idle","Walk","Jump","Roll"]
const REQUIRED_CLOSED_PARTS:=["RoyalArmor_head_ApexUnifiedConnectedHelmet","RoyalArmor_chest_ApexWaistedCuirass","RoyalArmor_chest_ApexIntegralPlackartOverlay","RoyalArmor_chest_ApexIntegralRearPlackartOverlay","RoyalArmor_chest_ApexUnifiedGorgetMantle","RoyalArmor_chest_ApexArticulatedFauld","RoyalArmor_chest_ApexUnifiedFrontCodpiece","RoyalArmor_shoulders_ApexGrandPauldronL","RoyalArmor_shoulders_ApexGrandPauldronR","RoyalArmor_shoulders_ApexRerebraceL","RoyalArmor_shoulders_ApexRerebraceR","RoyalArmor_pants_ApexCuisseL","RoyalArmor_pants_ApexCuisseR","RoyalArmor_chest_ApexTassetL0","RoyalArmor_chest_ApexTassetR0","RoyalArmor_chest_ApexUnifiedRearCulet"]
const FORBIDDEN_FLOATING_PARTS:=["ApexContinuousVisor","ApexContinuousBevor","ApexVisorBrowRail","ApexHingedTemple","ApexChin","ApexUpperGorget","ApexFrontShoulderBridge","ApexRearShoulderBridge","ApexBreastFlute","ApexBackFlute","ApexBackSpine","ApexTapulKeel","ApexGorgetLame","ApexCrownEmblem","ApexCrownRuby","ApexTassetRivet","ApexSpaulderLame","ApexBackhand","ApexKnuckle","ApexElbowBoss","ApexVambraceRidge","ApexCuisseFlute","ApexCuisseTopRoll","ApexGreaveRivet","ApexPoleynBoss","ApexSabatonGilt","ApexShinKeel","ApexPoleynWing"]

func find_animation_player(node:Node)->AnimationPlayer:
    if node is AnimationPlayer:return node as AnimationPlayer
    for child in node.get_children():
        var found:=find_animation_player(child)
        if found:return found
    return null

func inspect(node:Node,state:Dictionary)->void:
    var node_name:=String(node.name)
    for part in REQUIRED_CLOSED_PARTS:
        if node_name==part:state.closed_parts[part]=true
    for part in FORBIDDEN_FLOATING_PARTS:
        if node_name.contains(part):state.floating_parts.append(node_name)
    if node_name.begins_with("RoyalArmor_"):
        state.total=int(state.total)+1
        for slot in REQUIRED_SLOTS:
            if node_name.begins_with("RoyalArmor_%s_"%slot):
                state.slots[slot]=int(state.slots.get(slot,0))+1
                break
    if node is Skeleton3D:
        state.skeletons=int(state.skeletons)+1
        state.bones=maxi(int(state.bones),(node as Skeleton3D).get_bone_count())
    if node is MeshInstance3D:
        var mesh_instance:=node as MeshInstance3D
        if mesh_instance.mesh:
            for surface in range(mesh_instance.mesh.get_surface_count()):
                var material:=mesh_instance.get_active_material(surface)
                if material is StandardMaterial3D and (material as StandardMaterial3D).albedo_texture:
                    state.textured=true
    for child in node.get_children():inspect(child,state)

func _initialize()->void:
    var hero:=HERO_SCENE.instantiate()
    root.add_child(hero)
    await process_frame
    var state:={
        "total":0,
        "slots":{},
        "skeletons":0,
        "bones":0,
        "textured":false,
        "closed_parts":{},
        "floating_parts":[],
    }
    inspect(hero,state)
    var animation_player:=find_animation_player(hero)
    var missing_actions:Array[String]=[]
    for action in REQUIRED_ACTIONS:
        if not animation_player or not animation_player.has_animation(action):
            missing_actions.append(action)
    var slots_ok:=true
    for slot in REQUIRED_SLOTS:
        var minimum_pieces:int=int(REQUIRED_SLOT_MINIMUMS[slot])
        if int(state.slots.get(slot,0))<minimum_pieces:slots_ok=false
    var closed_ok:bool=int(state.closed_parts.size())==REQUIRED_CLOSED_PARTS.size()
    var passed:bool=int(state.total)>=50 and slots_ok and closed_ok and Array(state.floating_parts).is_empty() and int(state.skeletons)==1 and int(state.bones)>=20 and bool(state.textured) and missing_actions.is_empty()
    print("ROYAL_ARMOR_ASSET|pieces=%d|slots=%s|closed=%d/%d|floating=%s|skeletons=%d|bones=%d|textured=%s|missing_actions=%s"%[state.total,state.slots,state.closed_parts.size(),REQUIRED_CLOSED_PARTS.size(),state.floating_parts,state.skeletons,state.bones,state.textured,missing_actions])
    print("ROYAL_ARMOR_ASSET_VERIFY|%s"%("PASS" if passed else "FAIL"))
    hero.queue_free()
    await process_frame
    quit(0 if passed else 1)
