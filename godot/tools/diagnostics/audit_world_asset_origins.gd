extends SceneTree


const ASSETS := [
    "res://assets/vegetation/meadow_grass_clump.glb",
    "res://assets/vegetation/realistic_broadleaf_v1.glb",
    "res://assets/vegetation/realistic_birch_v1.glb",
    "res://assets/vegetation/realistic_maple_v1.glb",
    "res://assets/vegetation/realistic_pine_v1.glb",
    "res://assets/vegetation/realistic_willow_v1.glb",
    "res://assets/vegetation/bracken_patch_v1.glb",
    "res://assets/vegetation/cattail_cluster_v1.glb",
    "res://assets/vegetation/dry_stone_wall_segment_v1.glb",
    "res://assets/vegetation/roadside_cairn_v1.glb",
    "res://assets/vegetation/forest_deadwood_cluster_v1.glb",
    "res://assets/vegetation/woodland_flower_patch_v1.glb",
    "res://assets/vegetation/highland_outcrop_v1.glb",
    "res://assets/vegetation/roadside_verge_cluster_v1.glb",
]


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:=0
    for path in ASSETS:
        var packed:=load(path) as PackedScene
        if packed==null:
            push_error("missing world asset: %s"%path)
            failures+=1
            continue
        var source:=packed.instantiate()
        var bounds:=_node_bounds(source,Transform3D.IDENTITY)
        if not bounds.valid:
            push_error("world asset has no mesh bounds: %s"%path)
            failures+=1
        print("WORLD_ASSET_ORIGIN|asset=%s|min_y=%.4f|max_y=%.4f|height=%.4f|meshes=%d"%[
            path,float(bounds.minimum),float(bounds.maximum),float(bounds.maximum)-float(bounds.minimum),int(bounds.meshes),
        ])
        source.free()
    print("WORLD_ASSET_ORIGINS|assets=%d|failures=%d"%[ASSETS.size(),failures])
    quit(0 if failures==0 else 1)


func _node_bounds(node:Node,parent_transform:Transform3D)->Dictionary:
    var local_transform:=parent_transform
    if node is Node3D:local_transform=parent_transform*(node as Node3D).transform
    var minimum:=INF
    var maximum:=-INF
    var meshes:=0
    if node is MeshInstance3D and (node as MeshInstance3D).mesh!=null:
        var aabb: AABB=(node as MeshInstance3D).mesh.get_aabb()
        for endpoint in range(8):
            var point:=local_transform*aabb.get_endpoint(endpoint)
            minimum=minf(minimum,point.y)
            maximum=maxf(maximum,point.y)
        meshes+=1
    for child in node.get_children():
        var child_bounds:=_node_bounds(child,local_transform)
        if child_bounds.valid:
            minimum=minf(minimum,float(child_bounds.minimum))
            maximum=maxf(maximum,float(child_bounds.maximum))
            meshes+=int(child_bounds.meshes)
    return {"valid":meshes>0,"minimum":minimum,"maximum":maximum,"meshes":meshes}
