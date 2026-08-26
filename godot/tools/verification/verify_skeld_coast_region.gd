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
    var west:Dictionary=profiles.make_zone_profile("western_reaches")
    var storm:Dictionary=profiles.make_zone_profile("stormbreak_highlands")
    var glacial:Dictionary=profiles.make_zone_profile("glacial_range")
    var coast:Dictionary=profiles.make_zone_profile("skeld_coast")
    if str(coast.get("biome_id",""))!="subarctic_coast":failures.append("Skeld biome identity is missing")
    if int(coast.get("danger_tier",0))!=5:failures.append("Skeld Coast does not provide tier-five progression")
    if coast.get("town_sites",[]).size()!=2:failures.append("Skeld Coast needs two supporting settlements around Frostharbor")
    if coast.get("ocean_basins",[]).size()!=1:failures.append("Skeld Coast needs one coherent ocean basin")
    if coast.get("river_corridors",[]).size()!=1:failures.append("Skeld Coast needs one mountain-to-sea river")
    if coast.get("road_corridors",[]).size()!=3:failures.append("Skeld road hierarchy is incomplete")
    if coast.get("ford_sites",[]).size()!=1:failures.append("Skeld Coast should have one necessary road bridge")

    var storm_root:=Node3D.new();root.add_child(storm_root)
    var glacial_root:=Node3D.new();root.add_child(glacial_root)
    var coast_root:=Node3D.new();root.add_child(coast_root)
    var storm_result:Dictionary=TerrainBuilder.new().generate_world(storm_root,storm)
    var glacial_result:Dictionary=TerrainBuilder.new().generate_world(glacial_root,glacial)
    var coast_result:Dictionary=TerrainBuilder.new().generate_world(coast_root,coast)
    var half_size:=float(coast.get("world_size",7200.0))*.5
    var south_gap:=0.0
    var east_gap:=0.0
    for sample_index in range(129):
        var along:=lerpf(-half_size,half_size,float(sample_index)/128.0)
        south_gap=maxf(south_gap,absf(
            coast_result.terrain_height_sampler.call(along,half_size).y-
            storm_result.terrain_height_sampler.call(along,-half_size).y
        ))
        east_gap=maxf(east_gap,absf(
            coast_result.terrain_height_sampler.call(half_size,along).y-
            glacial_result.terrain_height_sampler.call(-half_size,along).y
        ))
    if south_gap>.02:failures.append("Skeld/Stormbreak terrain seam has a %.4fm crack"%south_gap)
    if east_gap>.02:failures.append("Skeld/Glacial terrain seam has a %.4fm crack"%east_gap)

    var coast_offset:Vector2=coast.get("region_origin",Vector2.ZERO)
    var storm_offset:Vector2=storm.get("region_origin",Vector2.ZERO)
    var glacial_offset:Vector2=glacial.get("region_origin",Vector2.ZERO)
    var coast_road:Dictionary=coast.road_corridors[0]
    var storm_road:=_find_corridor(storm.road_corridors,"Skeld Pass Road")
    var glacial_road:=_find_corridor(glacial.road_corridors,"Skeld Ice Road")
    var storm_road_gap:=INF
    var glacial_road_gap:=INF
    if not storm_road.is_empty():storm_road_gap=(Vector2(coast_road.points[0])+coast_offset).distance_to(Vector2(storm_road.points[-1])+storm_offset)
    if not glacial_road.is_empty():glacial_road_gap=(Vector2(coast_road.points[-1])+coast_offset).distance_to(Vector2(glacial_road.points[-1])+glacial_offset)
    if storm_road_gap>.01:failures.append("Stormbreak/Skeld road has a %.2fm boundary gap"%storm_road_gap)
    if glacial_road_gap>.01:failures.append("Glacial/Skeld road has a %.2fm boundary gap"%glacial_road_gap)

    var basin:Dictionary=coast.ocean_basins[0]
    var river:Dictionary=coast.river_corridors[0]
    var river_mouth:=Vector2(river.points[-1])
    var coast_x:=_coastline_x_at_z(river_mouth.y,basin.get("coast_points",[]))
    if absf(river_mouth.x-coast_x)>3.0:failures.append("Skeld River mouth does not meet the authored coastline")
    var rendered_mouth_height:=float(river.get("mouth_height",0.0))-2.8+float(coast.get("river_water_lift",1.35))
    var sea_height:=float(basin.get("water_height",-.6))
    if absf(rendered_mouth_height-sea_height)>.03:failures.append("Skeld River is %.2fm out of level with the Grey Sea"%absf(rendered_mouth_height-sea_height))
    var worst_shore_gap:=0.0
    var worst_shore_point:=Vector2.ZERO
    var worst_seafloor_protrusion:=0.0
    for coast_point_value in basin.get("coast_points",[]):
        var coast_point:=Vector2(coast_point_value)
        if coast_point.x<=-half_size+40.0:continue
        var shore_y:float=coast_result.terrain_height_sampler.call(coast_point.x,coast_point.y).y
        var seaward_y:float=coast_result.terrain_height_sampler.call(coast_point.x-80.0,coast_point.y).y
        var shore_gap:=absf(shore_y-(sea_height+.10))
        if shore_gap>worst_shore_gap:
            worst_shore_gap=shore_gap
            worst_shore_point=coast_point
        worst_seafloor_protrusion=maxf(worst_seafloor_protrusion,seaward_y-sea_height)
    if worst_shore_gap>1.2:failures.append("Skeld shoreline has a %.2fm terrain/water discontinuity"%worst_shore_gap)
    if worst_shore_gap>1.2:
        print("SKELD_SHORE_DIAGNOSTIC|point=%s|sampled_coast_x=%.3f|terrain_y=%.3f|target_y=%.3f"%[
            str(worst_shore_point),_coastline_x_at_z(worst_shore_point.y,basin.get("coast_points",[])),
            coast_result.terrain_height_sampler.call(worst_shore_point.x,worst_shore_point.y).y,sea_height+.10,
        ])
    if worst_seafloor_protrusion>.05:failures.append("Skeld seafloor protrudes %.2fm above ocean water"%worst_seafloor_protrusion)
    if coast_result.walkable_sampler.call(coast_x-120.0,river_mouth.y):failures.append("Deep ocean is incorrectly walkable")

    var bridge_point:Vector2=coast.ford_sites[0].position
    var bridge_road:=_nearest_corridor(bridge_point,coast.road_corridors)
    var bridge_river:=_nearest_corridor(bridge_point,coast.river_corridors)
    if float(bridge_road.get("distance",INF))>.25 or float(bridge_river.get("distance",INF))>.25:
        failures.append("Skeld Bridge misses road/river (%.2fm/%.2fm)"%[float(bridge_road.get("distance",INF)),float(bridge_river.get("distance",INF))])
    elif absf(Vector2(bridge_road.direction).dot(Vector2(bridge_river.direction)))>.42:
        failures.append("Skeld Bridge meets the river at an unsafe shallow angle")

    var atlas:=profiles.make_world_atlas([
        profiles.offset_profile(start,start.get("region_origin",Vector2.ZERO)),
        profiles.offset_profile(north,north.get("region_origin",Vector2.ZERO)),
        profiles.offset_profile(glacial,glacial.get("region_origin",Vector2.ZERO)),
        profiles.offset_profile(west,west.get("region_origin",Vector2.ZERO)),
        profiles.offset_profile(storm,storm.get("region_origin",Vector2.ZERO)),
        profiles.offset_profile(coast,coast.get("region_origin",Vector2.ZERO)),
    ])
    var ids:Array=[]
    for summary in atlas.get("region_summaries",[]):ids.append(str(summary.get("zone_id","")))
    if "skeld_coast" not in ids:failures.append("Skeld Coast is absent from the world atlas")
    if Vector2(atlas.get("map_extent",Vector2.ZERO)).distance_to(Vector2(14400,21600))>.1:failures.append("Six-region atlas footprint is incorrect")
    if atlas.get("ocean_basins",[]).size()!=1:failures.append("Atlas did not retain the Grey Sea coastline")

    print("SKELD_COAST_REGION|south_gap=%.5f|east_gap=%.5f|roads=%.3f/%.3f|mouth=%.3f|shore_gap=%.2f|shore_point=%s|atlas_regions=%d|failures=%d"%[
        south_gap,east_gap,storm_road_gap,glacial_road_gap,absf(rendered_mouth_height-sea_height),worst_shore_gap,str(worst_shore_point),ids.size(),failures.size(),
    ])
    for failure in failures:push_error("SKELD_COAST_REGION_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)


func _find_corridor(corridors:Array,name_value:String)->Dictionary:
    for corridor_value in corridors:
        if corridor_value is Dictionary and str(corridor_value.get("name",""))==name_value:return corridor_value
    return {}


func _coastline_x_at_z(z:float,points:Array)->float:
    if points.is_empty():return -INF
    var first:=Vector2(points[0])
    if z<=first.y:return first.x
    for index in range(points.size()-1):
        var a:=Vector2(points[index]);var b:=Vector2(points[index+1])
        if z>=minf(a.y,b.y) and z<=maxf(a.y,b.y):
            var span:=b.y-a.y
            return lerpf(a.x,b.x,0.0 if absf(span)<.001 else clampf((z-a.y)/span,0.0,1.0))
    return Vector2(points[-1]).x


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
