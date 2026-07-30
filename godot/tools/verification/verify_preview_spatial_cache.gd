extends SceneTree

const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")
const WorldProfile=preload("res://scripts/world/WorldProfile.gd")


func _init()->void:
    call_deferred("_run")


func _run()->void:
    var profile:Dictionary=WorldProfile.new().make_zone_profile("starting_realm")
    var builder:=WorldPreviewBuilder.new()
    builder._prepare_corridor_spatial_cache(profile)
    var cached:Dictionary=builder.get("_corridor_segment_buckets")
    var rng:=RandomNumberGenerator.new()
    rng.seed=92641
    var points:Array[Vector2]=[]
    var world_size:=float(profile.get("world_size",7200.0))
    for _index in range(12000):
        points.append(Vector2(
            rng.randf_range(-world_size*.48,world_size*.48),
            rng.randf_range(-world_size*.48,world_size*.48)
        ))
    var cases:Array[Dictionary]=[]
    for case_data in [
        ["river_corridors",58.0],
        ["river_corridors",50.0],
        ["road_corridors",26.0],
        ["road_corridors",2.0],
        ["trail_corridors",1.5],
    ]:
        var corridors:Array=profile.get(case_data[0],[])
        var cached_values:=PackedByteArray()
        cached_values.resize(points.size())
        for index in range(points.size()):
            cached_values[index]=1 if builder._is_too_close_to_corridors(points[index],corridors,case_data[1]) else 0
        cases.append({"corridors":corridors,"extra":case_data[1],"cached":cached_values})
    builder.set("_corridor_segment_buckets",{})
    var failures:=0
    for case in cases:
        for index in range(points.size()):
            var reference:=builder._is_too_close_to_corridors(points[index],case.corridors,case.extra)
            if reference!=(case.cached[index]==1):failures+=1
    builder.set("_corridor_segment_buckets",cached)
    print("PREVIEW_CACHE_PASS|checks=%d|failures=%d"%[points.size()*cases.size(),failures])
    quit(0 if failures==0 else 22)
