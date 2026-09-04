extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")


func _initialize()->void:
    call_deferred("_build")


func _build()->void:
    OS.set_environment("BROKEN_KNIGHT_REBUILD_ENGINEERED_ROUTES","1")
    var profiles:=WorldProfile.new()
    var failures:=0
    for zone_id in ["starting_realm","north_frontier","glacial_range","western_reaches","stormbreak_highlands","skeld_coast","east_marches","sunscar_drylands"]:
        var profile:Dictionary=profiles.make_zone_profile(zone_id)
        var builder:=TerrainBuilder.new()
        var started:=Time.get_ticks_usec()
        builder.call("_prepare_bridge_cache",profile)
        builder.call("_prepare_river_segment_cache",profile)
        builder.call("_prepare_engineered_route_cache",profile)
        var save_error:Error=builder.save_engineered_route_bake(profile)
        if save_error!=OK:
            failures+=1
            push_error("Unable to save engineered route bake for %s: %s"%[zone_id,error_string(save_error)])
            continue
        var path:=builder.engineered_route_bake_path(profile)
        print("ENGINEERED_ROUTE_BAKE|zone=%s|path=%s|size_kb=%.1f|build_ms=%.1f|signature=%s"%[
            zone_id,path,float(FileAccess.get_file_as_bytes(path).size())/1024.0,
            float(Time.get_ticks_usec()-started)/1000.0,builder.engineered_route_bake_signature(profile),
        ])
    OS.set_environment("BROKEN_KNIGHT_REBUILD_ENGINEERED_ROUTES","")
    quit(0 if failures==0 else 1)
