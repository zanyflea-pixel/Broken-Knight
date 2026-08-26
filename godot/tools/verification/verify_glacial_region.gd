extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profiles:=WorldProfile.new()
    var start:Dictionary=profiles.make_zone_profile("starting_realm")
    var north:Dictionary=profiles.make_zone_profile("north_frontier")
    var glacial:Dictionary=profiles.make_zone_profile("glacial_range")
    if str(glacial.get("biome_id",""))!="glacial_alpine":failures.append("glacial biome identity is missing")
    if int(glacial.get("danger_tier",0))<4:failures.append("glacial danger progression is missing")
    if glacial.get("mountain_chains",[]).size()<4:failures.append("glacial landform structure is incomplete")
    if glacial.get("encounter_sites",[]).filter(func(site:Dictionary)->bool:return site.get("enemy","")=="frost_troll").size()<2:
        failures.append("distinct frost-troll encounters are missing")
    if glacial.get("map_sites",[]).filter(func(site:Dictionary)->bool:return site.get("kind","")=="glacier").is_empty():
        failures.append("Rimewater has no mapped glacier source")

    var north_root:=Node3D.new();root.add_child(north_root)
    var glacial_root:=Node3D.new();root.add_child(glacial_root)
    var north_result:Dictionary=TerrainBuilder.new().generate_world(north_root,north)
    var glacial_result:Dictionary=TerrainBuilder.new().generate_world(glacial_root,glacial)
    var half_size:=float(north.get("world_size",7200.0))*.5
    var maximum_gap:=0.0
    for sample_index in range(65):
        var x:=lerpf(-half_size,half_size,float(sample_index)/64.0)
        var north_y:float=north_result.terrain_height_sampler.call(x,-half_size).y
        var glacial_y:float=glacial_result.terrain_height_sampler.call(x,half_size).y
        maximum_gap=maxf(maximum_gap,absf(north_y-glacial_y))
    if maximum_gap>.015:failures.append("frontier/glacial terrain seam has a %.3fm crack"%maximum_gap)

    var north_offset:Vector2=north.get("region_origin",Vector2.ZERO)
    var glacial_offset:Vector2=glacial.get("region_origin",Vector2.ZERO)
    var north_road:Array=north.road_corridors[2].points
    var glacial_road:Array=glacial.road_corridors[0].points
    var road_gap:=Vector2(north_road[-1]).distance_to(Vector2(glacial_road[0])+glacial_offset-north_offset)
    if road_gap>.01:failures.append("Icebound Realmway has a %.2fm boundary gap"%road_gap)
    var north_river:Array=north.river_corridors[1].points
    var glacial_river:Array=glacial.river_corridors[0].points
    var river_gap:=Vector2(north_river[0]).distance_to(Vector2(glacial_river[-1])+glacial_offset-north_offset)
    if river_gap>.01:failures.append("Rimewater has a %.2fm boundary gap"%river_gap)
    var bridge_point:Vector2=glacial.ford_sites[0].position
    var bridge_road_gap:=_corridor_distance(bridge_point,glacial.road_corridors)
    var bridge_river_gap:=_corridor_distance(bridge_point,glacial.river_corridors)
    if bridge_road_gap>12.0 or bridge_river_gap>12.0:
        failures.append("Rimegate Bridge misses road or river")

    var atlas:=profiles.make_world_atlas([
        profiles.offset_profile(start,Vector2.ZERO),
        profiles.offset_profile(north,north_offset),
        profiles.offset_profile(glacial,glacial_offset),
    ])
    var extent:Vector2=atlas.get("map_extent",Vector2.ZERO)
    var center:Vector2=atlas.get("map_center",Vector2.ZERO)
    if extent.distance_to(Vector2(7200,21600))>.1:failures.append("three-region atlas is not 7200 x 21600")
    if center.distance_to(Vector2(0,-7200))>.1:failures.append("three-region atlas center is incorrect")
    var troll_scene:=load("res://assets/enemies/frost_troll_v1.glb") as PackedScene
    if troll_scene==null:failures.append("Frost Troll Blender asset failed to import")
    else:
        var troll:=troll_scene.instantiate()
        if troll.find_child("ArmPivotL",true,false)==null or troll.find_child("ClubPivot",true,false)==null:
            failures.append("Frost Troll asset lacks its animation pivots")
        troll.free()

    print("GLACIAL_REGION|edge_gap=%.4f|road_gap=%.3f|river_gap=%.3f|atlas=%dx%d|failures=%d"%[
        maximum_gap,road_gap,river_gap,roundi(extent.x),roundi(extent.y),failures.size(),
    ])
    for failure in failures:push_error("GLACIAL_REGION_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)


func _corridor_distance(point:Vector2,corridors:Array)->float:
    var best:=INF
    for corridor in corridors:
        var points:Array=corridor.get("points",[])
        for index in range(points.size()-1):
            best=minf(best,point.distance_to(Geometry2D.get_closest_point_to_segment(point,points[index],points[index+1])))
    return best
