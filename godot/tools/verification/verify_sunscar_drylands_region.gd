extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profiles:=WorldProfile.new()
    var start:Dictionary=profiles.make_zone_profile("starting_realm")
    var south:Dictionary=profiles.make_zone_profile("sunscar_drylands")
    if str(south.get("biome_id",""))!="semi_arid_drylands":failures.append("Sunscar biome identity is missing")
    if south.get("town_sites",[]).size()!=3:failures.append("Sunscar needs three supporting settlements")
    if south.get("road_corridors",[]).size()!=4:failures.append("Sunscar road hierarchy is incomplete")
    if south.get("river_corridors",[]).size()!=2:failures.append("Sunscar drainage needs a river and oasis tributary")
    if south.get("ford_sites",[]).size()!=1:failures.append("Sunscar should have exactly one necessary bridge")
    if south.get("mountain_chains",[]).size()<3:failures.append("Sunscar regional elevation structure is incomplete")

    var start_root:=Node3D.new();root.add_child(start_root)
    var south_root:=Node3D.new();root.add_child(south_root)
    var start_result:Dictionary=TerrainBuilder.new().generate_world(start_root,start)
    var south_result:Dictionary=TerrainBuilder.new().generate_world(south_root,south)
    var half_size:=float(start.get("world_size",7200.0))*.5
    var seam_gap:=0.0
    var approach_step:=0.0
    var approach_along:=0.0
    var approach_side:=""
    var worst_along:=0.0
    for sample_index in range(161):
        var along:=lerpf(-half_size,half_size,float(sample_index)/160.0)
        var start_edge:float=start_result.terrain_height_sampler.call(along,half_size).y
        var south_edge:float=south_result.terrain_height_sampler.call(along,-half_size).y
        var gap:=absf(start_edge-south_edge)
        if gap>seam_gap:
            seam_gap=gap;worst_along=along
        var start_step:=absf(start_edge-start_result.terrain_height_sampler.call(along,half_size-45.0).y)
        var south_step:=absf(south_edge-south_result.terrain_height_sampler.call(along,-half_size+45.0).y)
        if start_step>approach_step:approach_step=start_step;approach_along=along;approach_side="starting"
        if south_step>approach_step:approach_step=south_step;approach_along=along;approach_side="sunscar"
    if seam_gap>.02:failures.append("Riverwatch/Sunscar terrain seam has a %.4fm crack"%seam_gap)
    # The only remaining rise is the outer, dry riverbank at roughly a ten
    # percent walking grade. Reject actual cliff lips, not that intentional
    # transition from the shared submerged support onto land.
    if approach_step>5.0:failures.append("Sunscar seam approach jumps %.2fm inside 45m"%approach_step)
    if approach_step>5.0:
        print("SUNSCAR_SEAM_DIAGNOSTIC|x=%.1f|start_edge=%.3f|start_inner=%.3f|south_edge=%.3f|south_inner=%.3f"%[
            approach_along,start_result.terrain_height_sampler.call(approach_along,half_size).y,
            start_result.terrain_height_sampler.call(approach_along,half_size-45.0).y,
            south_result.terrain_height_sampler.call(approach_along,-half_size).y,
            south_result.terrain_height_sampler.call(approach_along,-half_size+45.0).y,
        ])

    var offset:Vector2=south.get("region_origin",Vector2.ZERO)
    var start_road:=_find_corridor(start.get("road_corridors",[]),"Sunward Realmroad")
    var south_road:=_find_corridor(south.get("road_corridors",[]),"Sunward Realmroad")
    var road_gap:=INF
    if not start_road.is_empty() and not south_road.is_empty():
        road_gap=Vector2(start_road.points[-1]).distance_to(Vector2(south_road.points[0])+offset)
    if road_gap>.01:failures.append("Sunward Realmroad has a %.2fm boundary gap"%road_gap)

    var receiving:=_find_corridor(start.get("river_corridors",[]),"Sunrun Headwater")
    var sunrun:=_find_corridor(south.get("river_corridors",[]),"Sunrun River")
    var seam_river_gap:=INF
    if not receiving.is_empty() and not sunrun.is_empty():
        seam_river_gap=Vector2(receiving.points[0]).distance_to(Vector2(sunrun.points[-1])+offset)
    if seam_river_gap>.01:failures.append("Sunrun has a %.2fm boundary gap"%seam_river_gap)
    if absf(float(receiving.get("source_height",0.0))-float(sunrun.get("mouth_height",0.0)))>.001:
        failures.append("Sunrun water grades disagree at the seam")
    if float(sunrun.get("source_height",0.0))<=float(sunrun.get("mouth_height",0.0)):
        failures.append("Sunrun does not descend from its mountain source")
    var northwood:=_find_corridor(start.get("river_corridors",[]),"Northwood Tributary")
    var receiving_gap:=INF
    if not receiving.is_empty() and not northwood.is_empty():
        receiving_gap=Vector2(receiving.points[-1]).distance_to(Vector2(northwood.points[0]))
    if receiving_gap>.01:failures.append("Sunrun receiving reach does not join Northwood")

    var bridge:Dictionary=south.get("ford_sites",[])[0]
    var bridge_point:Vector2=bridge.get("position",Vector2.ZERO)
    var bridge_road:=_nearest_corridor(bridge_point,south.get("road_corridors",[]))
    var bridge_river:=_nearest_corridor(bridge_point,south.get("river_corridors",[]))
    var bridge_road_gap:=float(bridge_road.get("distance",INF))
    var bridge_river_gap:=float(bridge_river.get("distance",INF))
    var crossing_dot:=absf(Vector2(bridge_road.get("direction",Vector2.RIGHT)).dot(Vector2(bridge_river.get("direction",Vector2.DOWN))))
    if bridge_road_gap>.25 or bridge_river_gap>.25:failures.append("Sunrun Span misses its road or river")
    if crossing_dot>.45:failures.append("Sunrun Span crosses at an unsafe shallow angle (%.3f)"%crossing_dot)

    var flooded_towns:=0
    for site in [south.spawn_site]+south.town_sites:
        var center:Vector2=site.position
        var center_height:float=south_result.height_sampler.call(center.x,center.y).y
        if center_height<=float(south_result.water_level)+1.0:flooded_towns+=1
    if flooded_towns>0:failures.append("%d Sunscar settlements are flooded"%flooded_towns)
    var worst_road_grade:=0.0
    var worst_road_segment:=""
    for corridor in south.get("road_corridors",[]):
        var points:Array=corridor.get("points",[])
        for index in range(points.size()-1):
            var a:=Vector2(points[index]);var b:=Vector2(points[index+1])
            var distance:=a.distance_to(b)
            if distance<.01:continue
            var ha:float=south_result.height_sampler.call(a.x,a.y).y
            var hb:float=south_result.height_sampler.call(b.x,b.y).y
            var grade:=absf(hb-ha)/distance
            if grade>.10:print("SUNSCAR_ROAD_GRADE_DIAGNOSTIC|road=%s|segment=%d|a=%s@%.2f|b=%s@%.2f|grade=%.3f"%[str(corridor.get("name","road")),index,str(a),ha,str(b),hb,grade])
            if grade>worst_road_grade:worst_road_grade=grade;worst_road_segment="%s:%d"%[str(corridor.get("name","road")),index]
    if worst_road_grade>.16:failures.append("Sunscar road network reaches an unsafe %.3f grade"%worst_road_grade)

    var all_profiles:Array=[]
    for zone_id in ["starting_realm","north_frontier","glacial_range","western_reaches","stormbreak_highlands","skeld_coast","east_marches","sunscar_drylands"]:
        var local_profile:Dictionary=profiles.make_zone_profile(zone_id)
        all_profiles.append(profiles.offset_profile(local_profile,local_profile.get("region_origin",Vector2.ZERO)))
    var atlas:Dictionary=profiles.make_world_atlas(all_profiles)
    var ids:Array=[]
    for summary in atlas.get("region_summaries",[]):ids.append(str(summary.get("zone_id","")))
    if "sunscar_drylands" not in ids:failures.append("Sunscar is absent from the world atlas")
    if Vector2(atlas.get("map_extent",Vector2.ZERO)).distance_to(Vector2(21600,28800))>.1:
        failures.append("Eight-region atlas footprint is incorrect")

    print("SUNSCAR_DRYLANDS_REGION|seam_gap=%.5f@%.1f|approach_step=%.3f@%.1f:%s|road_gap=%.3f|river_gap=%.3f|receiving_gap=%.3f|bridge=%.3f/%.3f/dot%.3f|road_grade=%.3f:%s|towns_dry=%s|atlas_regions=%d|atlas_extent=%s|failures=%d"%[
        seam_gap,worst_along,approach_step,approach_along,approach_side,road_gap,seam_river_gap,receiving_gap,
        bridge_road_gap,bridge_river_gap,crossing_dot,worst_road_grade,worst_road_segment,str(flooded_towns==0),ids.size(),
        str(atlas.get("map_extent",Vector2.ZERO)),failures.size(),
    ])
    for failure in failures:push_error("SUNSCAR_DRYLANDS_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)


func _find_corridor(corridors:Array,name_value:String)->Dictionary:
    for corridor_value in corridors:
        if corridor_value is Dictionary and str(corridor_value.get("name",""))==name_value:return corridor_value
    return {}


func _nearest_corridor(point:Vector2,corridors:Array)->Dictionary:
    var result:Dictionary={}
    var best:=INF
    for corridor_value in corridors:
        if not corridor_value is Dictionary:continue
        var points:Array=corridor_value.get("points",[])
        for index in range(points.size()-1):
            var a:=Vector2(points[index]);var b:=Vector2(points[index+1])
            var segment:=b-a
            if segment.length_squared()<.0001:continue
            var closest:=Geometry2D.get_closest_point_to_segment(point,a,b)
            var distance:=point.distance_to(closest)
            if distance<best:
                best=distance
                result={"distance":distance,"direction":segment.normalized(),"closest":closest}
    return result
