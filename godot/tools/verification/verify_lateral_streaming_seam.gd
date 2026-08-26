extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profiles:=WorldProfile.new()
    var starting:Dictionary=profiles.make_zone_profile("starting_realm")
    var western:Dictionary=profiles.make_zone_profile("western_reaches")
    var shared_seam:={"key":"western_reaches_pass","blend_width":620.0,"base_height":15.0}
    starting["region_origin"]=Vector2.ZERO
    starting["seam_edges"].append(shared_seam.merged({"edge":"west"},true))
    western["region_origin"]=Vector2(-7200,0)
    western["seam_edges"]=[shared_seam.merged({"edge":"east"},true)]
    # This test isolates the land join. River continuity receives its own
    # corridor-end acceptance test when the western watershed is authored.
    starting["river_corridors"]=[]
    western["river_corridors"]=[]

    var start_root:=Node3D.new();root.add_child(start_root)
    var west_root:=Node3D.new();root.add_child(west_root)
    var start_result:Dictionary=TerrainBuilder.new().generate_world(start_root,starting)
    var west_result:Dictionary=TerrainBuilder.new().generate_world(west_root,western)
    var half_size:=float(starting.get("world_size",7200.0))*.5
    var maximum_gap:=0.0
    var maximum_approach_step:=0.0
    var maximum_approach_z:=0.0
    var maximum_approach_side:=""
    for sample_index in range(129):
        var z:=lerpf(-half_size,half_size,float(sample_index)/128.0)
        var start_edge:float=start_result.terrain_height_sampler.call(-half_size,z).y
        var west_edge:float=west_result.terrain_height_sampler.call(half_size,z).y
        maximum_gap=maxf(maximum_gap,absf(start_edge-west_edge))
        var start_inward:float=start_result.terrain_height_sampler.call(-half_size+45.0,z).y
        var west_inward:float=west_result.terrain_height_sampler.call(half_size-45.0,z).y
        var starting_step:=absf(start_edge-start_inward)
        var western_step:=absf(west_edge-west_inward)
        if starting_step>maximum_approach_step:
            maximum_approach_step=starting_step
            maximum_approach_z=z
            maximum_approach_side="starting"
        if western_step>maximum_approach_step:
            maximum_approach_step=western_step
            maximum_approach_z=z
            maximum_approach_side="western"
    if maximum_gap>.015:failures.append("western terrain boundary has a %.4fm crack"%maximum_gap)
    if maximum_approach_step>3.0:failures.append("western seam approaches jump by %.2fm inside 45m"%maximum_approach_step)

    print("LATERAL_STREAMING_SEAM|gap=%.5f|approach_step=%.3f@%.1f:%s|samples=129|failures=%d"%[
        maximum_gap,maximum_approach_step,maximum_approach_z,maximum_approach_side,failures.size(),
    ])
    for failure in failures:push_error("LATERAL_SEAM_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
