extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var world:=Node3D.new();root.add_child(world)
    for child_name in ["TerrainRoot","RiverRoot","RoadRoot","BridgeRoot","TownRoot","PropsRoot"]:
        var child:=Node3D.new();child.name=child_name;world.add_child(child)
    var profile:=WorldProfile.new().make_zone_profile("skeld_coast")
    var result:=TerrainBuilder.new().generate_world(world.get_node("TerrainRoot"),profile)
    WorldPreviewBuilder.new().populate(world,profile,result)
    var bridge_descriptions:Array[String]=[]
    for child in world.get_node("BridgeRoot").get_children():
        bridge_descriptions.append("%s@%s"%[child.name,str((child as Node3D).position if child is Node3D else Vector3.ZERO)])
    var skeld_nodes:Array[String]=[]
    for node in _descendants(world):
        if "Hall" in str(node.name) or "CapeKeld" in str(node.name) or "FrostharborDock" in str(node.name) or "Whalebone" in str(node.name) or "Tide Cutter" in str(node.name) or "Netter" in str(node.name):
            skeld_nodes.append("%s:%s"%[node.get_path(),node.get_class()])
    var longhouse_sites:=0
    for site in profile.get("landmark_sites",[]):
        if str(site.get("kind",""))=="skeld_longhouse":longhouse_sites+=1
    print("SKELD_RENDER_AUDIT|bridges=%d|bridge_nodes=%s|longhouse_sites=%d|skeld_nodes=%d|nodes=%s"%[
        bridge_descriptions.size(),str(bridge_descriptions),longhouse_sites,skeld_nodes.size(),str(skeld_nodes),
    ])
    quit()


func _descendants(node:Node)->Array[Node]:
    var result:Array[Node]=[]
    var stack:Array[Node]=[]
    stack.assign(node.get_children())
    while not stack.is_empty():
        var current:Node=stack.pop_back() as Node
        result.append(current)
        stack.append_array(current.get_children())
    return result
