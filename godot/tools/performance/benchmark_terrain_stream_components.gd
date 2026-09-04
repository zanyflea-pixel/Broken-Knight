extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var profiles:=WorldProfile.new()
    for zone_id in ["north_frontier","glacial_range","western_reaches","stormbreak_highlands","skeld_coast","east_marches"]:
        var profile:Dictionary=profiles.make_zone_profile(zone_id)
        var builder:=TerrainBuilder.new()
        var mark:=Time.get_ticks_usec()
        builder.call("_prepare_bridge_cache",profile)
        var bridge_ms:=float(Time.get_ticks_usec()-mark)/1000.0
        mark=Time.get_ticks_usec()
        builder.call("_prepare_river_segment_cache",profile)
        var river_ms:=float(Time.get_ticks_usec()-mark)/1000.0
        mark=Time.get_ticks_usec()
        builder.call("_prepare_engineered_route_cache",profile)
        var route_ms:=float(Time.get_ticks_usec()-mark)/1000.0
        mark=Time.get_ticks_usec()
        var resolution:=int(profile.get("grid_resolution",220))
        var cache_path:=str(builder.call("_terrain_cache_path",profile))
        var cached:Dictionary=builder.call("_load_heightfield_cache",cache_path,(resolution+1)*(resolution+1))
        var cache_ms:=float(Time.get_ticks_usec()-mark)/1000.0
        print("TERRAIN_STREAM_COMPONENTS|zone=%s|bridge_ms=%.2f|river_ms=%.2f|route_ms=%.2f|cache_ms=%.2f|cached=%s"%[
            zone_id,bridge_ms,river_ms,route_ms,cache_ms,str(not cached.is_empty()),
        ])
    quit()
