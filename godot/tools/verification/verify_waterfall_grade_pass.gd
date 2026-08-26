extends SceneTree

const WORLD_PROFILE_SCRIPT:Script=preload("res://scripts/world/WorldProfile.gd")
const TERRAIN_BUILDER_SCRIPT:Script=preload("res://scripts/world/TerrainBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _nearest_tangent(point:Vector2,corridors:Array)->Vector2:
    var best_distance:=INF
    var best_tangent:=Vector2.DOWN
    for corridor in corridors:
        var points:Array=corridor.get("points",[])
        for index in range(points.size()-1):
            var a:Vector2=points[index];var b:Vector2=points[index+1]
            var segment:=b-a
            if segment.length_squared()<=.0001:continue
            var t:=clampf((point-a).dot(segment)/segment.length_squared(),0.0,1.0)
            var distance:=point.distance_to(a+segment*t)
            if distance<best_distance:
                best_distance=distance
                best_tangent=segment.normalized()
    return best_tangent


func _make_root()->Node3D:
    var root_node:=Node3D.new()
    root.add_child(root_node)
    return root_node


func _run()->void:
    var failures:Array[String]=[]
    var world_profile:RefCounted=WORLD_PROFILE_SCRIPT.new()
    var north_profile:Dictionary=world_profile.make_zone_profile("north_frontier")
    var glacial_profile:Dictionary=world_profile.make_zone_profile("glacial_range")
    var north_builder:RefCounted=TERRAIN_BUILDER_SCRIPT.new()
    var glacial_builder:RefCounted=TERRAIN_BUILDER_SCRIPT.new()
    var north_result:Dictionary=north_builder.generate_world(_make_root(),north_profile)
    var glacial_result:Dictionary=glacial_builder.generate_world(_make_root(),glacial_profile)

    var glacial_fall:Dictionary=glacial_profile.waterfall_sites[0]
    var glacial_point:Vector2=glacial_fall.position
    var glacial_tangent:=_nearest_tangent(glacial_point,glacial_profile.river_corridors)
    var glacial_up:Vector3=glacial_result.river_height_sampler.call(glacial_point.x-glacial_tangent.x*34.0,glacial_point.y-glacial_tangent.y*34.0)
    var glacial_down:Vector3=glacial_result.river_height_sampler.call(glacial_point.x+glacial_tangent.x*34.0,glacial_point.y+glacial_tangent.y*34.0)
    var rimefall_drop:=glacial_up.y-glacial_down.y
    if absf(rimefall_drop-float(glacial_fall.drop))>.35:
        failures.append("Rimefall grade mismatch %.3f"%rimefall_drop)

    var north_fall:Dictionary=north_profile.waterfall_sites[0]
    var north_point:Vector2=north_fall.position
    var north_tangent:=_nearest_tangent(north_point,north_profile.river_corridors)
    var north_up:Vector3=north_result.river_height_sampler.call(north_point.x-north_tangent.x*34.0,north_point.y-north_tangent.y*34.0)
    var north_down:Vector3=north_result.river_height_sampler.call(north_point.x+north_tangent.x*34.0,north_point.y+north_tangent.y*34.0)
    var crownfall_drop:=north_up.y-north_down.y
    if absf(crownfall_drop-float(north_fall.drop))>.35:
        failures.append("Crownfall grade mismatch %.3f"%crownfall_drop)

    var glacial_mouth:Vector2=glacial_profile.river_corridors[0].points[-1]
    var north_tributary_source:Vector2=north_profile.river_corridors[1].points[0]
    var glacial_mouth_height:float=glacial_result.river_height_sampler.call(glacial_mouth.x,glacial_mouth.y).y
    var tributary_source_height:float=north_result.river_height_sampler.call(north_tributary_source.x,north_tributary_source.y).y
    var seam_gap:=absf(glacial_mouth_height-tributary_source_height)
    if seam_gap>.03:failures.append("Glacial tributary seam mismatch %.4f"%seam_gap)

    var tributary_mouth:Vector2=north_profile.river_corridors[1].points[-1]
    var crownfall_source:Vector2=north_profile.river_corridors[0].points[0]
    var confluence_gap:=absf(
        north_result.river_height_sampler.call(tributary_mouth.x,tributary_mouth.y).y-
        north_result.river_height_sampler.call(crownfall_source.x,crownfall_source.y).y
    )
    if confluence_gap>.03:failures.append("Crownfall confluence mismatch %.4f"%confluence_gap)

    print("WATERFALL_GRADE_PASS|rimefall_drop=%.3f|crownfall_drop=%.3f|seam_gap=%.4f|confluence_gap=%.4f|failures=%d"%[
        rimefall_drop,crownfall_drop,seam_gap,confluence_gap,failures.size(),
    ])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)
