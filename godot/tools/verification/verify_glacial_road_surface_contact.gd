extends SceneTree

const WORLD_PROFILE_SCRIPT:Script=preload("res://scripts/world/WorldProfile.gd")
const TERRAIN_BUILDER_SCRIPT:Script=preload("res://scripts/world/TerrainBuilder.gd")
const WORLD_PREVIEW_BUILDER_SCRIPT:Script=preload("res://scripts/world/WorldPreviewBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _resample(points:Array,spacing:float)->Array[Vector2]:
    var result:Array[Vector2]=[]
    for index in range(points.size()-1):
        var a:Vector2=points[index]
        var b:Vector2=points[index+1]
        var steps:=maxi(1,ceili(a.distance_to(b)/spacing))
        for step in range(steps):result.append(a.lerp(b,float(step)/float(steps)))
    if not points.is_empty():result.append(points[-1])
    return result


func _run()->void:
    var profile_source:RefCounted=WORLD_PROFILE_SCRIPT.new()
    var profile:Dictionary=profile_source.make_zone_profile("glacial_range")
    var terrain_root:=Node3D.new();root.add_child(terrain_root)
    var terrain_builder:RefCounted=TERRAIN_BUILDER_SCRIPT.new()
    var preview_builder:RefCounted=WORLD_PREVIEW_BUILDER_SCRIPT.new()
    var terrain:Dictionary=terrain_builder.generate_world(terrain_root,profile)
    var sampler:Callable=terrain.terrain_height_sampler
    var failures:Array[String]=[]
    var global_min_clearance:=INF
    var global_buried_samples:=0
    for road_value in profile.get("road_corridors",[]):
        var road:Dictionary=road_value
        var rendered:Array=preview_builder.call("_surface_fitted_polyline",road.get("points",[]),sampler,.18,4.0,1.0)
        var road_min:=INF
        var buried:=0
        for index in range(rendered.size()-1):
            var a:Vector2=rendered[index]
            var b:Vector2=rendered[index+1]
            var a_y:float=sampler.call(a.x,a.y).y+.18
            var b_y:float=sampler.call(b.x,b.y).y+.18
            var probe_count:=8
            for probe in range(probe_count+1):
                var t:=float(probe)/float(probe_count)
                var point:=a.lerp(b,t)
                var mesh_y:=lerpf(a_y,b_y,t)
                var ground_y:float=sampler.call(point.x,point.y).y
                var clearance:=mesh_y-ground_y
                road_min=minf(road_min,clearance)
                if clearance<.015:buried+=1
        global_min_clearance=minf(global_min_clearance,road_min)
        global_buried_samples+=buried
        print("GLACIAL_ROAD_CONTACT|road=%s|min_clearance=%.4f|buried_samples=%d"%[road.get("name","Road"),road_min,buried])
        if road_min<-.01:failures.append("%s road ribbon enters terrain by %.3f m"%[road.get("name","Road"),-road_min])
    print("GLACIAL_ROAD_CONTACT_PASS|min_clearance=%.4f|buried_samples=%d|failures=%d"%[global_min_clearance,global_buried_samples,failures.size()])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)
