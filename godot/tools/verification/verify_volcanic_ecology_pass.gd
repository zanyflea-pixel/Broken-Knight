extends SceneTree

const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")
const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const EXPECTED_MESHES:=[
    "RopeyLavaShelf","ObsidianShardCluster","FumaroleVentCluster",
    "CharredVolcanicSnag","AshScrubCluster","FireweedPatch",
]


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var kit_scene:=load("res://assets/world/volcanic_ecology_kit_v1.glb") as PackedScene
    if kit_scene==null:
        push_error("VOLCANIC_ECOLOGY_FAILURE|kit could not be loaded")
        quit(1)
        return
    var kit:=kit_scene.instantiate();root.add_child(kit)
    var mesh_names:Dictionary={}
    var stack:Array[Node]=[kit]
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        for child in node.get_children():stack.append(child)
        if node is MeshInstance3D:mesh_names[str(node.name)]=true
    for mesh_name in EXPECTED_MESHES:
        if not mesh_names.has(mesh_name):failures.append("source kit missing %s"%mesh_name)
    kit.free()

    var counts:Dictionary={}
    var collision_count:=0
    var out_of_bounds:=0
    var apron_radius:=0.0
    for zone_id in ["starting_realm","east_marches"]:
        var world:=Node3D.new();root.add_child(world)
        for child_name in ["TerrainRoot","RiverRoot","RoadRoot","BridgeRoot","TownRoot","PropsRoot"]:
            var child:=Node3D.new();child.name=child_name;world.add_child(child)
        var profile:Dictionary=WorldProfile.new().make_zone_profile(zone_id)
        var terrain:Dictionary=TerrainBuilder.new().generate_world(world.get_node("TerrainRoot"),profile)
        var preview:=WorldPreviewBuilder.new();preview.begin_population(world,profile)
        preview.call("_build_regional_geology",world.get_node("PropsRoot"),profile,terrain)
        var props:=world.get_node("PropsRoot")
        var terrain_mesh:=world.get_node_or_null("TerrainRoot/TerrainMesh") as MeshInstance3D
        var terrain_material:ShaderMaterial=null if terrain_mesh==null else terrain_mesh.material_override as ShaderMaterial
        if terrain_material==null:failures.append("%s terrain material is missing"%zone_id)
        var zone_count:=int(props.get_meta("volcanic_ecology_count",0))
        if zone_id=="starting_realm":
            if zone_count!=0:failures.append("volcanic ecology leaked into the starter region")
            if terrain_material!=null and (terrain_material.get_shader_parameter("volcanic_center") as Vector2).length()<50000.0:
                failures.append("volcanic terrain apron leaked into the starter material")
        if zone_id=="east_marches":
            if terrain_material!=null:
                var apron_center:=terrain_material.get_shader_parameter("volcanic_center") as Vector2
                apron_radius=float(terrain_material.get_shader_parameter("volcanic_radius"))
                if apron_center.distance_to(Vector2(2920.0,-2640.0))>.1:failures.append("volcanic terrain apron center is not Embercrag")
                if apron_radius<1200.0:failures.append("volcanic terrain apron is too small: %.1f"%apron_radius)
            counts=props.get_meta("volcanic_ecology_kind_counts",{})
            var collision_body:=props.get_node_or_null("VolcanicEcologyCollision")
            collision_count=0 if collision_body==null else collision_body.get_child_count()
            var playable_half_extent:=float(profile.get("world_size",7200.0))*.5-119.0
            var prop_stack:Array[Node]=[props]
            while not prop_stack.is_empty():
                var prop_node:Node=prop_stack.pop_back()
                for child in prop_node.get_children():prop_stack.append(child)
                if not prop_node is MultiMeshInstance3D or not prop_node.has_meta("volcanic_ecology_kind"):continue
                var volcanic_instance:=prop_node as MultiMeshInstance3D
                for instance_index in range(volcanic_instance.multimesh.instance_count):
                    var local_transform:=volcanic_instance.multimesh.get_instance_transform(instance_index)
                    var world_point:=volcanic_instance.global_transform*local_transform.origin
                    if absf(world_point.x)>playable_half_extent or absf(world_point.z)>playable_half_extent:out_of_bounds+=1
            if zone_count<8:failures.append("Eastern volcanic field is too sparse: %d"%zone_count)
            if out_of_bounds>0:failures.append("%d volcanic placements are outside the playable terrain mesh"%out_of_bounds)
            if collision_count!=int(counts.get("ObsidianShardCluster",0))+int(counts.get("FumaroleVentCluster",0))+int(counts.get("CharredVolcanicSnag",0)):
                failures.append("volcanic collision count does not match solid formations")
            for mesh_name in EXPECTED_MESHES:
                if int(counts.get(mesh_name,0))<1:failures.append("no accepted %s placements"%mesh_name)
        world.free()
    var total:=0
    for mesh_name in EXPECTED_MESHES:total+=int(counts.get(mesh_name,0))
    print("VOLCANIC_ECOLOGY_PASS|total=%d|lava=%d|obsidian=%d|vents=%d|snags=%d|scrub=%d|fireweed=%d|collisions=%d|out_of_bounds=%d|apron_radius=%.1f|source_meshes=%d|failures=%d"%[
        total,int(counts.get("RopeyLavaShelf",0)),int(counts.get("ObsidianShardCluster",0)),
        int(counts.get("FumaroleVentCluster",0)),int(counts.get("CharredVolcanicSnag",0)),
        int(counts.get("AshScrubCluster",0)),int(counts.get("FireweedPatch",0)),
        collision_count,out_of_bounds,apron_radius,mesh_names.size(),failures.size(),
    ])
    for failure in failures:push_error("VOLCANIC_ECOLOGY_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
