extends SceneTree

const DRAGON_SCENE:PackedScene=preload("res://assets/enemies/cave_dragon.glb")
const REQUIRED_ANIMATIONS:=["Idle","Walk","Attack","Roar","FireBreath","Death"]

func collect_nodes(node:Node,type_name:String,result:Array[Node])->void:
    if node.is_class(type_name):result.append(node)
    for child in node.get_children():collect_nodes(child,type_name,result)

func find_animation_player(node:Node)->AnimationPlayer:
    if node is AnimationPlayer:return node as AnimationPlayer
    for child in node.get_children():
        var found:=find_animation_player(child)
        if found:return found
    return null

func _initialize()->void:
    var dragon:=DRAGON_SCENE.instantiate()
    root.add_child(dragon)
    await process_frame
    var skeletons:Array[Node]=[]
    var meshes:Array[Node]=[]
    collect_nodes(dragon,"Skeleton3D",skeletons)
    collect_nodes(dragon,"MeshInstance3D",meshes)
    var animation_player:=find_animation_player(dragon)
    var missing:Array[String]=[]
    if animation_player:
        for clip in REQUIRED_ANIMATIONS:
            if not animation_player.has_animation(clip):missing.append(clip)
    else:
        missing.assign(REQUIRED_ANIMATIONS)
    var skeleton:=skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
    var deform_ok:=false
    var walk_length:=0.0
    if animation_player and skeleton and animation_player.has_animation("Walk"):
        walk_length=animation_player.get_animation("Walk").length
        var thigh_index:=skeleton.find_bone("thigh.L")
        if thigh_index>=0:
            animation_player.play("Walk")
            animation_player.seek(0.0,true)
            var first:=skeleton.get_bone_pose(thigh_index)
            animation_player.seek(minf(.50,walk_length*.5),true)
            var second:=skeleton.get_bone_pose(thigh_index)
            deform_ok=first.basis.get_rotation_quaternion().angle_to(second.basis.get_rotation_quaternion())>.08
    var bone_count:=skeleton.get_bone_count() if skeleton else 0
    var passed:=skeletons.size()==1 and bone_count>=30 and meshes.size()>=18 and missing.is_empty() and deform_ok
    print("CAVE_DRAGON_ASSET|skeletons=%d|bones=%d|meshes=%d|animations=%s|missing=%s|walk_length=%.3f|walk_deforms=%s"%[skeletons.size(),bone_count,meshes.size(),animation_player.get_animation_list() if animation_player else [],missing,walk_length,deform_ok])
    print("CAVE_DRAGON_ASSET_VERIFY|%s"%("PASS" if passed else "FAIL"))
    dragon.queue_free()
    await process_frame
    quit(0 if passed else 1)

