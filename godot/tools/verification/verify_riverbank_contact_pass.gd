extends SceneTree

const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")
const WorldProfile=preload("res://scripts/world/WorldProfile.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profile:Dictionary=WorldProfile.new().make_zone_profile("starting_realm")
    var terrain_root:=Node3D.new();root.add_child(terrain_root)
    var terrain:Dictionary=TerrainBuilder.new().generate_world(terrain_root,profile)
    var river_root:=Node3D.new();root.add_child(river_root)
    WorldPreviewBuilder.new().call("_build_river_ribbons",river_root,profile.get("river_corridors",[]),terrain,profile)

    var bank_meshes:=0
    var broad_turf_meshes:=0
    var bank_collisions:=0
    for node in _all_descendants(river_root):
        var node_name:=str(node.name)
        if "Natural Shore Blend" in node_name:
            bank_meshes+=1
        if "Turf Blend" in node_name:
            broad_turf_meshes+=1
        if node is CollisionShape3D:
            bank_collisions+=1
    if bank_meshes==0:failures.append("no shoreline contact meshes were generated")
    if broad_turf_meshes>0:failures.append("%d broad turf overlays still duplicate the terrain bank"%broad_turf_meshes)
    if bank_collisions>0:failures.append("%d river overlay collision shapes can block the shoreline"%bank_collisions)

    var blocked_bank_samples:=0
    var checked_bank_samples:=0
    var visible_overlap_failures:=0
    var width_scale:=0.84
    var walkable:Callable=terrain.walkable_sampler
    var world_half:=float(profile.get("world_size",7200.0))*.49
    for river in profile.get("river_corridors",[]):
        var points:Array=river.get("points",[])
        for index in range(1,points.size()-1):
            var tangent:Vector2=(Vector2(points[index+1])-Vector2(points[index-1])).normalized()
            if tangent.length_squared()<.001:continue
            var normal:=Vector2(-tangent.y,tangent.x)
            var progress:=float(index)/maxf(1.0,float(points.size()-1))
            var source_width:=float(river.get("source_width",river.get("width",84.0)))
            var mouth_width:=float(river.get("mouth_width",river.get("width",84.0)))
            var authored_width:=lerpf(source_width,mouth_width,progress)
            var water_half:=authored_width*width_scale*.5
            var blocked_limit:=authored_width*.35
            if water_half<=blocked_limit:
                visible_overlap_failures+=1
            for side in [-1.0,1.0]:
                for offset in [blocked_limit+1.0,water_half+2.0,water_half+8.0,water_half+18.0]:
                    var sample:=Vector2(points[index])+normal*float(side)*float(offset)
                    # walkable_sampler deliberately rejects world-exit samples;
                    # this pass measures shoreline obstruction, not map bounds.
                    if absf(sample.x)>=world_half or absf(sample.y)>=world_half:
                        continue
                    # At confluences this river's bank sample may correctly
                    # enter the deep core of another branch.
                    if _inside_other_channel(sample,str(river.get("name","River")),profile.get("river_corridors",[])):
                        continue
                    checked_bank_samples+=1
                    if not walkable.call(sample.x,sample.y):
                        blocked_bank_samples+=1
    if visible_overlap_failures>0:
        failures.append("%d river samples do not expose a walkable wading margin"%visible_overlap_failures)
    if blocked_bank_samples>0:
        failures.append("%d/%d intended bank samples are blocked"%[blocked_bank_samples,checked_bank_samples])

    print("RIVERBANK_CONTACT|bank_meshes=%d|turf_overlays=%d|bank_collisions=%d|walkable=%d|blocked=%d|overlap_failures=%d|failures=%d"%[
        bank_meshes,broad_turf_meshes,bank_collisions,checked_bank_samples,blocked_bank_samples,visible_overlap_failures,failures.size(),
    ])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)


func _all_descendants(node:Node)->Array[Node]:
    var descendants:Array[Node]=[]
    for child in node.get_children():
        descendants.append(child)
        descendants.append_array(_all_descendants(child))
    return descendants


func _inside_other_channel(point:Vector2,current_name:String,rivers:Array)->bool:
    for river in rivers:
        if str(river.get("name","River"))==current_name:continue
        var points:Array=river.get("points",[])
        for index in range(points.size()-1):
            var closest:=Geometry2D.get_closest_point_to_segment(point,points[index],points[index+1])
            if point.distance_to(closest)<float(river.get("width",84.0))*.35:
                return true
    return false
