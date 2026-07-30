extends RefCounted

const PROFILE_PATH := "res://data/world_profile.json"


func make_old_world_profile() -> Dictionary:
    var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
    if file == null:
        push_warning("World profile file missing, using empty fallback.")
        return {}

    var raw_text: String = file.get_as_text()
    var parsed: Variant = JSON.parse_string(raw_text)
    if typeof(parsed) != TYPE_DICTIONARY:
        push_warning("World profile JSON was invalid, using empty fallback.")
        return {}

    return _normalize_profile(parsed)


func make_zone_profile(zone_id:String)->Dictionary:
    var profile:=make_old_world_profile()
    profile["zone_id"]=zone_id
    match zone_id:
        "north_frontier":
            _transform_zone(profile,PI,true)
            _rename_zone(profile,"North Frontier",["Frostmere","Pinehold","Greyfen","Northgate","Old Crown"])
            profile["zone_exits"]=[{"edge":"south","target":"starting_realm","entry":"north"},{"edge":"east","target":"east_marches","entry":"north"}]
        "east_marches":
            _transform_zone(profile,PI*.5,false)
            _rename_zone(profile,"Eastern Marches",["Dawnford","Amberfield","Saltwatch","Red Hollow","March Keep"])
            profile["zone_exits"]=[{"edge":"west","target":"starting_realm","entry":"east"},{"edge":"north","target":"north_frontier","entry":"east"}]
        "western_reaches":
            _transform_zone(profile,-PI*.5,true)
            _rename_zone(profile,"Western Reaches",["Oakrest","Rainhaven","Stonecross","Mossbank","Reach Keep"])
            profile["zone_exits"]=[{"edge":"east","target":"starting_realm","entry":"west"}]
        _:
            profile["zone_id"]="starting_realm"
            profile["zone_name"]="Riverwatch Realm - Starting Zone"
            profile["zone_exits"]=[{"edge":"north","target":"north_frontier","entry":"south"},{"edge":"east","target":"east_marches","entry":"west"},{"edge":"west","target":"western_reaches","entry":"east"}]
    return profile


func _rename_zone(profile:Dictionary,zone_name:String,town_names:Array)->void:
    profile["zone_name"]=zone_name
    for i in range(profile.get("town_sites",[]).size()):
        profile.town_sites[i]["name"]=town_names[i] if i<town_names.size() else "%s Outpost"%zone_name
        profile.town_sites[i].erase("capital")
    for i in range(profile.get("river_corridors",[]).size()):profile.river_corridors[i]["name"]="%s Waterway %d"%[zone_name,i+1]


func _transform_zone(profile:Dictionary,angle:float,mirror_x:bool)->void:
    var transform_point:=func(point:Vector2)->Vector2:
        var p:=Vector2(-point.x,point.y) if mirror_x else point
        return p.rotated(angle)
    profile.spawn_site.position=transform_point.call(profile.spawn_site.position)
    for key in ["town_sites","camp_sites","pond_sites","waterfall_sites","ford_sites"]:
        for site in profile.get(key,[]):site.position=transform_point.call(site.position)
    for key in ["flat_regions","forest_regions","mountain_chains","ocean_basins"]:
        for region in profile.get(key,[]):
            region.center=transform_point.call(region.center)
            if region.has("angle"):region.angle=float(region.angle)*(-1.0 if mirror_x else 1.0)+angle
    for key in ["river_corridors","road_corridors","trail_corridors"]:
        for corridor in profile.get(key,[]):
            var transformed:Array=[]
            for point in corridor.get("points",[]):transformed.append(transform_point.call(point))
            corridor.points=transformed


func _normalize_profile(raw: Dictionary) -> Dictionary:
    var profile: Dictionary = raw.duplicate(true)
    profile["spawn_site"] = _normalize_site(profile.get("spawn_site", {}))
    profile["town_sites"] = _normalize_sites(profile.get("town_sites", []))
    profile["camp_sites"] = _normalize_sites(profile.get("camp_sites", []))
    profile["pond_sites"] = _normalize_sites(profile.get("pond_sites", []))
    profile["waterfall_sites"] = _normalize_sites(profile.get("waterfall_sites", []))
    profile["ford_sites"] = _normalize_sites(profile.get("ford_sites", []))
    profile["flat_regions"] = _normalize_regions(profile.get("flat_regions", []))
    profile["forest_regions"] = _normalize_regions(profile.get("forest_regions", []))
    profile["mountain_chains"] = _normalize_centered_entries(profile.get("mountain_chains", []))
    profile["ocean_basins"] = _normalize_centered_entries(profile.get("ocean_basins", []))
    profile["river_corridors"] = _normalize_corridors(profile.get("river_corridors", []))
    for river in profile["river_corridors"]:
        # Keep the terrain query path compact. Visible water and banks add their
        # own render-only smoothing in WorldPreviewBuilder, so terrain creation
        # does not scan hundreds of extra river segments for every grid point.
        river["points"] = _catmull_rom_points(river.get("points", []), 6)
    profile["road_corridors"] = _normalize_corridors(profile.get("road_corridors", []))
    profile["trail_corridors"] = _normalize_corridors(profile.get("trail_corridors", []))
    _apply_layout_scale(profile, float(profile.get("layout_scale", 1.0)))
    return profile


func _apply_layout_scale(profile: Dictionary, scale: float) -> void:
    if is_equal_approx(scale, 1.0):
        return
    # Positions and regional footprints expand with the world. Human-scale
    # features (roads, river channels and settlement pads) stay sensibly sized.
    var physical_scale := minf(scale, 10.0)
    var spawn: Dictionary = profile.get("spawn_site", {})
    _scale_site(spawn, scale, physical_scale)
    for site in profile.get("town_sites", []):
        _scale_site(site, scale, physical_scale)
    for site in profile.get("camp_sites", []):
        _scale_site(site, scale, physical_scale)
    for site in profile.get("ford_sites", []):
        _scale_site(site, scale, physical_scale)
    for region in profile.get("flat_regions", []):
        region["center"] = region.get("center", Vector2.ZERO) * scale
        region["radius"] = float(region.get("radius", 0.0)) * physical_scale * 0.42
    for region in profile.get("forest_regions", []):
        region["center"] = region.get("center", Vector2.ZERO) * scale
        region["radius"] = float(region.get("radius", 0.0)) * scale
    for chain in profile.get("mountain_chains", []):
        chain["center"] = chain.get("center", Vector2.ZERO) * scale
        chain["length"] = float(chain.get("length", 0.0)) * scale
        chain["width"] = float(chain.get("width", 0.0)) * minf(scale, 16.0)
    for basin in profile.get("ocean_basins", []):
        basin["center"] = basin.get("center", Vector2.ZERO) * scale
        basin["inner"] = float(basin.get("inner", 0.0)) * scale
        basin["outer"] = float(basin.get("outer", 0.0)) * scale
    for corridor_key in ["river_corridors", "road_corridors", "trail_corridors"]:
        for corridor in profile.get(corridor_key, []):
            var scaled_points: Array = []
            for point in corridor.get("points", []):
                scaled_points.append(point * scale)
            corridor["points"] = scaled_points
            var width_scale := 1.0 if corridor_key == "river_corridors" else 0.52
            corridor["width"] = float(corridor.get("width", 0.0)) * physical_scale * width_scale


func _scale_site(site: Dictionary, scale: float, physical_scale: float) -> void:
    site["position"] = site.get("position", Vector2.ZERO) * scale
    site["radius"] = float(site.get("radius", 0.0)) * physical_scale * 0.42


func _normalize_sites(raw_sites: Array) -> Array:
    var sites: Array = []
    for raw_site in raw_sites:
        sites.append(_normalize_site(raw_site))
    return sites


func _normalize_site(raw_site: Dictionary) -> Dictionary:
    var site: Dictionary = raw_site.duplicate(true)
    site["position"] = _to_vec2(site.get("position", [0.0, 0.0]))
    return site


func _normalize_regions(raw_regions: Array) -> Array:
    var regions: Array = []
    for raw_region in raw_regions:
        var region: Dictionary = raw_region.duplicate(true)
        region["center"] = _to_vec2(region.get("center", [0.0, 0.0]))
        regions.append(region)
    return regions


func _normalize_centered_entries(raw_entries: Array) -> Array:
    var entries: Array = []
    for raw_entry in raw_entries:
        var entry: Dictionary = raw_entry.duplicate(true)
        entry["center"] = _to_vec2(entry.get("center", [0.0, 0.0]))
        entries.append(entry)
    return entries


func _normalize_corridors(raw_corridors: Array) -> Array:
    var corridors: Array = []
    for raw_corridor in raw_corridors:
        var corridor: Dictionary = raw_corridor.duplicate(true)
        var raw_points: Array = corridor.get("points", [])
        var points: Array = []
        for raw_point in raw_points:
            points.append(_to_vec2(raw_point))
        corridor["points"] = points
        corridors.append(corridor)
    return corridors


func _catmull_rom_points(points: Array, steps_per_segment: int) -> Array:
    if points.size() < 3:
        return points.duplicate()
    var smoothed: Array = []
    var last := points.size() - 1
    for i in range(last):
        var p0: Vector2 = points[maxi(0, i - 1)]
        var p1: Vector2 = points[i]
        var p2: Vector2 = points[i + 1]
        var p3: Vector2 = points[mini(last, i + 2)]
        for step in range(steps_per_segment):
            var t := float(step) / float(steps_per_segment)
            var t2 := t * t
            var t3 := t2 * t
            var point: Vector2 = 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
            smoothed.append(point)
    smoothed.append(points[last])
    return smoothed


func _to_vec2(value: Variant) -> Vector2:
    if value is Vector2:
        return value
    if value is Array and value.size() >= 2:
        return Vector2(float(value[0]), float(value[1]))
    return Vector2.ZERO
