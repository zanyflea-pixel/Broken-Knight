extends SceneTree

const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldProfile=preload("res://scripts/world/WorldProfile.gd")


func _init()->void:
    call_deferred("_run")


func _run()->void:
    var profile:Dictionary=WorldProfile.new().make_zone_profile("starting_realm")
    var builder:=TerrainBuilder.new()
    builder._prepare_bridge_cache(profile)
    builder._prepare_river_segment_cache(profile)
    builder._prepare_engineered_route_cache(profile)
    var cached_buckets:Dictionary=builder.get("_river_segment_buckets")
    var world_size:=float(profile.get("world_size",7200.0))
    var water_level:=float(profile.get("water_level",-18.0))
    var samples:Array[Vector2]=[]
    for z_index in range(0,257,4):
        for x_index in range(0,257,4):
            samples.append(Vector2(
                (float(x_index)/256.0-.5)*world_size,
                (float(z_index)/256.0-.5)*world_size
            ))
    for river in profile.get("river_corridors",[]):
        for point_value in river.get("points",[]):
            var point:Vector2=point_value
            for offset in [Vector2.ZERO,Vector2(50,0),Vector2(-50,0),Vector2(0,50),Vector2(0,-50),Vector2(180,0)]:
                samples.append(point+offset)
    var cached_heights:=PackedFloat32Array()
    cached_heights.resize(samples.size())
    for index in range(samples.size()):
        var point:=samples[index]
        cached_heights[index]=builder._sample_controlled_aqueduct_height(point.x,point.y,profile,water_level)
    builder.set("_river_segment_buckets",{})
    var failures:=0
    var max_error:=0.0
    for index in range(samples.size()):
        var point:=samples[index]
        var reference:float=builder._sample_controlled_aqueduct_height(point.x,point.y,profile,water_level)
        var error:=absf(reference-cached_heights[index])
        max_error=maxf(max_error,error)
        if error>.0001:failures+=1
    builder.set("_river_segment_buckets",cached_buckets)
    print("RIVER_CACHE_PASS|samples=%d|max_height_error=%.6f|failures=%d"%[
        samples.size(),
        max_error,
        failures,
    ])
    quit(0 if failures==0 else 21)
