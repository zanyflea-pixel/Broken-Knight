extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profiles:=WorldProfile.new()
    var start:Dictionary=profiles.make_zone_profile("starting_realm")
    var east:Dictionary=profiles.make_zone_profile("east_marches")
    if str(east.get("biome_id",""))!="continental_marches":failures.append("Eastern biome identity is missing")
    if east.get("town_sites",[]).size()!=3:failures.append("Eastern Marches needs three supporting settlements")
    if east.get("road_corridors",[]).size()!=3:failures.append("Eastern road hierarchy is incomplete")
    if east.get("river_corridors",[]).size()!=3:failures.append("Eastern drainage needs Emberwash, Glassmere Run, and the Redstone headwater")
    if east.get("ford_sites",[]).size()!=2:failures.append("Eastern Marches should have one major and one secondary bridge")
    var major_crossings:=0
    for ford in east.get("ford_sites",[]):
        if str(ford.get("crossing_class","major"))=="major":major_crossings+=1
    if major_crossings!=1:failures.append("Eastern Marches should have exactly one major-road bridge")
    if east.get("mountain_chains",[]).size()<3:failures.append("Eastern skyline lacks authored regional structure")

    var start_root:=Node3D.new();root.add_child(start_root)
    var east_root:=Node3D.new();root.add_child(east_root)
    var start_result:Dictionary=TerrainBuilder.new().generate_world(start_root,start)
    var east_result:Dictionary=TerrainBuilder.new().generate_world(east_root,east)
    var half_size:=float(east.get("world_size",7200.0))*.5
    var seam_gap:=0.0
    var worst_seam_along:=0.0
    for sample_index in range(129):
        var along:=lerpf(-half_size,half_size,float(sample_index)/128.0)
        var sampled_gap:=absf(
            start_result.terrain_height_sampler.call(half_size,along).y-
            east_result.terrain_height_sampler.call(-half_size,along).y
        )
        if sampled_gap>seam_gap:
            seam_gap=sampled_gap
            worst_seam_along=along
    if seam_gap>.02:failures.append("Riverwatch/Eastern Marches terrain seam has a %.4fm crack"%seam_gap)
    if seam_gap>.02:
        for diagnostic_along in [2790.0,2812.5,2840.0,2850.0,2868.75,2890.0,2910.0]:
            print("EAST_SEAM_DIAGNOSTIC|along=%.2f|start=%.5f|east=%.5f|gap=%.5f"%[
                diagnostic_along,
                start_result.terrain_height_sampler.call(half_size,diagnostic_along).y,
                east_result.terrain_height_sampler.call(-half_size,diagnostic_along).y,
                absf(start_result.terrain_height_sampler.call(half_size,diagnostic_along).y-east_result.terrain_height_sampler.call(-half_size,diagnostic_along).y),
            ])

    var east_offset:Vector2=east.get("region_origin",Vector2.ZERO)
    var start_road:=_find_corridor(start.road_corridors,"Eastern March Road")
    var east_road:=_find_corridor(east.road_corridors,"Dawnway Realmroad")
    var road_gap:=INF
    if not start_road.is_empty() and not east_road.is_empty():
        road_gap=(Vector2(start_road.points[-1])).distance_to(Vector2(east_road.points[0])+east_offset)
    if road_gap>.01:failures.append("Eastreach/Dawnway realmroad has a %.2fm boundary gap"%road_gap)

    var start_river:=_find_corridor(start.river_corridors,"Eastreach Tributary")
    var emberwash:=_find_corridor(east.river_corridors,"Emberwash River")
    var river_gap:=INF
    if not start_river.is_empty() and not emberwash.is_empty():
        river_gap=Vector2(start_river.points[0]).distance_to(Vector2(emberwash.points[-1])+east_offset)
    if river_gap>.01:failures.append("Emberwash/Eastreach river has a %.2fm boundary gap"%river_gap)
    if float(emberwash.get("source_height",0.0))<=float(emberwash.get("mouth_height",0.0)):
        failures.append("Emberwash does not descend toward Riverwatch")

    var glassrun:=_find_corridor(east.river_corridors,"Glassmere Run")
    var tributary_gap:=INF
    if not glassrun.is_empty() and not emberwash.is_empty():
        tributary_gap=Vector2(glassrun.points[-1]).distance_to(Vector2(-1050,1080))
    if tributary_gap>.01:failures.append("Glassmere Run does not join the Emberwash")
    var start_redstone:=_find_corridor(start.river_corridors,"Redstone Tributary")
    var east_redstone:=_find_corridor(east.river_corridors,"Redstone Headwater")
    var redstone_gap:=INF
    if not start_redstone.is_empty() and not east_redstone.is_empty():
        redstone_gap=Vector2(start_redstone.points[0]).distance_to(Vector2(east_redstone.points[-1])+east_offset)
    if redstone_gap>.01:failures.append("Redstone headwater has a %.2fm boundary gap"%redstone_gap)

    var bridge_point:Vector2=east.ford_sites[0].position
    var bridge_road:=_nearest_corridor(bridge_point,east.road_corridors)
    var bridge_river:=_nearest_corridor(bridge_point,east.river_corridors)
    var bridge_road_gap:=float(bridge_road.get("distance",INF))
    var bridge_river_gap:=float(bridge_river.get("distance",INF))
    if bridge_road_gap>.25 or bridge_river_gap>.25:
        failures.append("Ember Span misses road/river (%.2fm/%.2fm)"%[bridge_road_gap,bridge_river_gap])
    elif absf(Vector2(bridge_road.direction).dot(Vector2(bridge_river.direction)))>.48:
        failures.append("Ember Span meets the river at an unsafe shallow angle")
    var salt_bridge:Dictionary=east.ford_sites[1]
    var salt_road:=_nearest_corridor(Vector2(salt_bridge.position),east.road_corridors)
    var salt_river:=_nearest_corridor(Vector2(salt_bridge.position),east.river_corridors)
    if float(salt_road.get("distance",INF))>4.0 or float(salt_river.get("distance",INF))>4.0:
        failures.append("Saltmeadow Bridge is not centered on its market-road crossing")

    var flooded_towns:=0
    var worst_road_grade:=0.0
    for site in [east.spawn_site]+east.town_sites:
        var center:Vector2=site.position
        var center_height:float=east_result.height_sampler.call(center.x,center.y).y
        if center_height<=float(east_result.water_level)+1.0:flooded_towns+=1
    for corridor in east.road_corridors:
        var points:Array=corridor.get("points",[])
        for index in range(points.size()-1):
            var a:=Vector2(points[index]);var b:=Vector2(points[index+1])
            var distance:=a.distance_to(b)
            if distance<.01:continue
            var ha:float=east_result.height_sampler.call(a.x,a.y).y
            var hb:float=east_result.height_sampler.call(b.x,b.y).y
            worst_road_grade=maxf(worst_road_grade,absf(hb-ha)/distance)
    if flooded_towns>0:failures.append("%d Eastern settlements are flooded"%flooded_towns)
    if worst_road_grade>.16:failures.append("Eastern road network reaches an unsafe %.3f grade"%worst_road_grade)

    var all_profiles:Array=[]
    for zone_id in ["starting_realm","north_frontier","glacial_range","western_reaches","stormbreak_highlands","skeld_coast","east_marches"]:
        var local_profile:Dictionary=profiles.make_zone_profile(zone_id)
        all_profiles.append(profiles.offset_profile(local_profile,local_profile.get("region_origin",Vector2.ZERO)))
    var atlas:=profiles.make_world_atlas(all_profiles)
    var ids:Array=[]
    for summary in atlas.get("region_summaries",[]):ids.append(str(summary.get("zone_id","")))
    if "east_marches" not in ids:failures.append("Eastern Marches is absent from the world atlas")
    if Vector2(atlas.get("map_extent",Vector2.ZERO)).distance_to(Vector2(21600,21600))>.1:
        failures.append("Seven-region atlas footprint is incorrect")

    var start_edge_height:float=start_result.terrain_height_sampler.call(half_size,worst_seam_along).y
    var east_edge_height:float=east_result.terrain_height_sampler.call(-half_size,worst_seam_along).y
    print("EASTERN_MARCHES_REGION|seam_gap=%.5f@%.1f(%.3f/%.3f)|road_gap=%.3f|river_gap=%.3f|redstone_gap=%.3f|tributary_gap=%.3f|bridge=%.3f/%.3f|road_grade=%.3f|towns_dry=%s|atlas_regions=%d|failures=%d"%[
        seam_gap,worst_seam_along,start_edge_height,east_edge_height,road_gap,river_gap,redstone_gap,tributary_gap,bridge_road_gap,bridge_river_gap,worst_road_grade,str(flooded_towns==0),ids.size(),failures.size(),
    ])
    for failure in failures:push_error("EASTERN_MARCHES_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)


func _find_corridor(corridors:Array,name_value:String)->Dictionary:
    for corridor_value in corridors:
        if corridor_value is Dictionary and str(corridor_value.get("name",""))==name_value:return corridor_value
    return {}


func _nearest_corridor(point:Vector2,corridors:Array)->Dictionary:
    var result:Dictionary={}
    var best:=INF
    for corridor in corridors:
        var points:Array=corridor.get("points",[])
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
