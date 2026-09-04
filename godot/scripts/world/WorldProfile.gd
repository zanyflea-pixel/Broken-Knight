extends RefCounted

const PROFILE_PATH := "res://data/world/profile.json"


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
            _author_north_frontier(profile)
        "glacial_range":
            _author_glacial_range(profile)
        "east_marches":
            _author_eastern_marches(profile)
        "western_reaches":
            _author_western_reaches(profile)
        "stormbreak_highlands":
            _author_stormbreak_highlands(profile)
        "skeld_coast":
            _author_skeld_coast(profile)
        "sunscar_drylands":
            _author_sunscar_drylands(profile)
        _:
            profile["zone_id"]="starting_realm"
            profile["zone_name"]="Riverwatch Realm - Starting Zone"
            profile.merge({"biome_id":"temperate_riverlands","climate":"mild temperate","danger_tier":1,"recommended_level":[1,8],"difficulty_multiplier":1.0,"snow_line":10000.0,"snow_strength":0.0},true)
            _author_starting_north_seam(profile)
            profile["zone_exits"]=[
                {"edge":"north","target":"north_frontier","entry":"south","seamless":true},
                {"edge":"east","target":"east_marches","entry":"west","seamless":true},
                {"edge":"west","target":"western_reaches","entry":"east","seamless":true},
                {"edge":"south","target":"sunscar_drylands","entry":"north","seamless":true},
            ]
    return profile


func _author_starting_north_seam(profile:Dictionary)->void:
    profile["region_origin"]=Vector2.ZERO
    profile["seam_edges"]=[{
        "edge":"south","key":"north_frontier_pass","blend_width":620.0,
        "base_height":13.5,"junction_key":"riverwatch_northwest_junction",
        "junction_along":-3600.0,"junction_height":18.5,"junction_blend":680.0,
        "junctions":[{"key":"riverwatch_northeast_junction","along":3600.0,"height":17.0,"blend":680.0}],
    },{
        "edge":"north","key":"sunscar_gate_pass","blend_width":620.0,
        "base_height":14.5,"junction_key":"riverwatch_southwest_junction",
        "junction_along":-3600.0,"junction_height":14.8,"junction_blend":680.0,
        "junctions":[{"key":"riverwatch_southeast_junction","along":3600.0,"height":15.2,"blend":680.0}],
        "river_crossings":[
            {"name":"Sunrun Headwater","along":300.0,"width":72.0,"bed_height":6.714},
        ],
    },{
        "edge":"west","key":"western_reaches_pass","blend_width":620.0,
        "base_height":15.0,"junction_key":"riverwatch_northwest_junction",
        "junction_along":-3600.0,"junction_height":18.5,"junction_blend":680.0,
        "junctions":[{"key":"riverwatch_southwest_junction","along":3600.0,"height":14.8,"blend":680.0}],
    },{
        "edge":"east","key":"eastern_marches_pass","blend_width":620.0,
        "base_height":16.0,"junction_key":"riverwatch_northeast_junction",
        "junction_along":-3600.0,"junction_height":17.0,"junction_blend":680.0,
        "junctions":[{"key":"riverwatch_southeast_junction","along":3600.0,"height":15.2,"blend":680.0}],
        "river_crossings":[
            {"name":"Redstone Headwater","along":-3560.0,"width":52.0,"bed_height":10.544},
            {"name":"Eastreach Emberwash","along":2850.0,"width":46.0,"bed_height":10.543},
        ],
    }]
    profile["road_corridors"].append({
        "name":"Crownspire North Road","route_class":"major",
        "purpose":"continuous realm road from Crownspire into the North Frontier",
        "destinations":["Crownspire","Pinewatch"],"width":18.0,
        "terrain_width":235.0,"terrain_relief":4.0,
        "points":[
            Vector2(250,-2450),Vector2(410,-2650),Vector2(540,-2920),
            Vector2(500,-3220),Vector2(420,-3440),Vector2(360,-3600),
        ],
    })
    profile["road_corridors"].append({
        "name":"Sunward Realmroad","route_class":"major",
        "purpose":"continuous southern road from Highfield into the Sunscar caravan country",
        "destinations":["Highfield","Sundown Gate","Emberwell"],"width":18.0,
        "terrain_width":235.0,"terrain_relief":4.0,"grade_limit":.070,
        "points":[
            Vector2(-550,1680),Vector2(-520,2080),Vector2(-470,2500),
            Vector2(-390,2920),Vector2(-350,3300),Vector2(-420,3600),
        ],
    })
    profile["road_corridors"].append({
        "name":"Eastern March Road","route_class":"major",
        "purpose":"continuous realmway from Eastreach into the Eastern Marches",
        "destinations":["Eastreach","Dawnford"],"width":18.0,
        "terrain_width":235.0,"terrain_relief":4.0,"grade_limit":.065,
        "points":[
            Vector2(2380,980),Vector2(2660,990),Vector2(2920,1010),
            Vector2(3180,1030),Vector2(3420,1040),Vector2(3600,1050),
        ],
    })
    profile["road_corridors"].append({
        "name":"Western Reach Road","route_class":"major",
        "purpose":"continuous road from Westmere to the western maritime pass",
        "destinations":["Westmere","Oakrest"],"width":17.0,
        "terrain_width":230.0,"terrain_relief":4.0,
        "points":[
            Vector2(-2500,-950),Vector2(-2850,-820),Vector2(-3200,-620),
            Vector2(-3450,-470),Vector2(-3600,-400),
        ],
    })
    # This is the visible downstream continuation of the frontier watershed.
    # Its final tangent matches the upstream region so the liquid never ends at
    # the streaming boundary or kinks when the adjacent terrain appears.
    profile["river_corridors"].append({
        "name":"Crownspire Headwater","width":44.0,
        "points":_catmull_rom_points([
            Vector2(900,-3600),Vector2(1000,-3400),Vector2(1220,-3180),
            Vector2(1500,-2920),Vector2(1820,-2660),Vector2(2160,-2420),
            Vector2(2530,-2200),
        ],6),
    })
    # A visible receiving reach joins the dryland watershed to Northwood's
    # existing tributary. Both tiles share the 8.4 m grade at the seam, so the
    # channel and liquid remain continuous instead of ending at the map edge.
    profile["river_corridors"].append({
        "name":"Sunrun Headwater","width":48.0,"source_width":72.0,"mouth_width":48.0,
        "source_height":8.4,"mouth_height":5.3,
        "source_kind":"Sunscar mountain runoff","source_landmark":"Sunrun Cascades",
        "termination":"the Northwood Tributary",
        "points":_catmull_rom_points([
            Vector2(300,3600),Vector2(240,3440),Vector2(120,3260),
            Vector2(-70,3090),Vector2(-300,2940),Vector2(-570,2805),
        ],6),
    })


func _author_sunscar_drylands(profile:Dictionary)->void:
    profile["zone_id"]="sunscar_drylands"
    profile["zone_name"]="Sunscar Drylands"
    profile["biome_id"]="semi_arid_drylands"
    profile["climate"]="hot semi-arid river country"
    profile["danger_tier"]=3
    profile["recommended_level"]=[8,18]
    profile["difficulty_multiplier"]=1.52
    profile["snow_line"]=10000.0
    profile["snow_strength"]=0.0
    profile["population_scale"]=0.25
    profile["meadow_samples_per_chunk"]=265
    profile["streamed_population"]=true
    profile["streamed_heightmap_collision"]=true
    profile["region_origin"]=Vector2(0,7200)
    profile["seam_edges"]=[{
        "edge":"south","key":"sunscar_gate_pass","blend_width":620.0,
        "base_height":14.5,"junction_key":"riverwatch_southwest_junction",
        "junction_along":-3600.0,"junction_height":14.8,"junction_blend":680.0,
        "junctions":[{"key":"riverwatch_southeast_junction","along":3600.0,"height":15.2,"blend":680.0}],
        "river_crossings":[
            {"name":"Sunrun River","along":300.0,"width":72.0,"bed_height":6.714},
        ],
    }]
    profile["zone_exits"]=[
        {"edge":"north","target":"starting_realm","entry":"south","seamless":true},
    ]
    profile["spawn_site"]={
        "name":"Sundown Gate","position":Vector2(-500,-2850),"radius":174.0,
        "ground_height":18.0,"ground_inner_ratio":.82,"starter":false,
        "architecture_set":"marcher_stone",
        "role":"northern caravan gate, water customs post, and dryland provisioning town",
        "siting_reason":"a firm gravel shelf above the Sunrun flood channel where the realmroad leaves Riverwatch",
        "connections":["Highfield","Emberwell","Red Mesa Hold"],
    }
    profile["town_sites"]=[
        {
            "name":"Emberwell","position":Vector2(1500,420),"radius":188.0,
            "ground_height":39.0,"ground_inner_ratio":.82,"architecture_set":"marcher_timber",
            "role":"oasis market, irrigated garden town, and central caravan exchange",
            "siting_reason":"a broad alluvial bench above the spring pool and below the eastern escarpment",
            "connections":["Sundown Gate","Red Mesa Hold","Copper Hollow"],
        },{
            "name":"Red Mesa Hold","position":Vector2(-1050,1880),"radius":166.0,
            "ground_height":43.0,"ground_inner_ratio":.80,"architecture_set":"marcher_stone",
            "role":"southern road ward controlling the pass between the mesas",
            "siting_reason":"a defensible sandstone shoulder beside the only low-gradient caravan route south",
            "connections":["Emberwell","Sundown Gate","Southroad Pass"],
        },{
            "name":"Copper Hollow","position":Vector2(2440,230),"radius":142.0,
            "ground_height":48.0,"ground_inner_ratio":.80,"architecture_set":"marcher_stone",
            "role":"small mining settlement serving the copper and iron shelves",
            "siting_reason":"a stable bench below exposed eastern geology and well above flash-flood channels",
            "connections":["Emberwell","Copper Shelf Mine"],
        },
    ]
    profile["camp_sites"]=[
        {"name":"Northbound Caravan Camp","position":Vector2(-610,-2380),"radius":46.0},
        {"name":"Red Mesa Drovers Camp","position":Vector2(-1370,1530),"radius":42.0},
        {"name":"Sunrun Survey Camp","position":Vector2(1740,2060),"radius":40.0},
    ]
    profile["map_sites"]=[
        {"name":"Sunspire Mesa","kind":"watchtower","position":Vector2(-2320,420),"radius":52.0,"elevation_lift":28.0,"elevation_inner":74.0,"elevation_radius":310.0,"elevation_role":"the red mesa visible from Sundown Gate and most of the north road"},
        {"name":"Sunrun Span","kind":"bridge","position":Vector2(430,-620),"radius":34.0,"elevation_role":"the realmroad's necessary crossing of the Sunrun"},
        {"name":"Emberwell Spring","kind":"lake","position":Vector2(1260,890),"radius":148.0,"elevation_role":"the permanent spring basin supporting Emberwell"},
        {"name":"Sunrun Cascades","kind":"headwater","position":Vector2(2130,2690),"radius":40.0,"elevation_lift":16.0,"elevation_inner":52.0,"elevation_radius":220.0,"elevation_role":"mountain runoff gathering into the Sunrun River"},
        {"name":"Copper Shelf Mine","kind":"ruin","position":Vector2(2860,-120),"radius":34.0,"first_destination":true,"elevation_role":"the first dangerous destination east of Emberwell"},
        {"name":"Southroad Pass","kind":"waystation","position":Vector2(-1220,3220),"radius":34.0,"first_destination":true,"elevation_role":"the graded exit between the southern mesas"},
    ]
    profile["landmark_sites"]=[
        {"name":"Sunspire Sandstone Crown","kind":"outcrop","position":Vector2(-2320,420),"radius":126.0,"count":30,"rotation":.18},
        {"name":"Copper Shelf Ribs","kind":"outcrop","position":Vector2(2750,-40),"radius":112.0,"count":26,"rotation":-.34},
        {"name":"Red Mesa Gate Teeth","kind":"outcrop","position":Vector2(-1430,1960),"radius":92.0,"count":22,"rotation":.28},
        {"name":"Sunrun Gorge Stones","kind":"outcrop","position":Vector2(1720,2100),"radius":96.0,"count":20,"rotation":-.16},
        {"name":"Emberwell Date Grove","kind":"grove","species":"willow","position":Vector2(1190,760),"radius":112.0,"count":28},
        {"name":"North Sunrun Tamarisk","kind":"grove","species":"willow","position":Vector2(170,-1720),"radius":76.0,"count":15},
        {"name":"Sundown Gate Waystone","kind":"waystone","position":Vector2(-450,-3310),"radius":10.0,"rotation":.04},
        {"name":"Southroad Cairn","kind":"cairn","position":Vector2(-1200,3160),"radius":9.0,"scale":1.25,"rotation":-.12},
    ]
    profile["ecology_sites"]=[
        {"name":"Emberwell Reed Garden","kind":"bracken","position":Vector2(1190,910),"radius":250.0,"count":180},
        {"name":"Sunrun Green Ribbon","kind":"bracken","position":Vector2(300,-1260),"radius":310.0,"count":165},
        {"name":"Sundown Sage Flats","kind":"bracken","position":Vector2(-820,-2420),"radius":280.0,"count":130},
        {"name":"Copper Shelf Scrub","kind":"bracken","position":Vector2(2380,120),"radius":250.0,"count":120},
    ]
    profile["encounter_sites"]=[
        {"name":"Sundown Road Ashfangs","position":Vector2(-900,-1900),"enemy":"ashfang","count":5,"radius":66.0,"rank":3},
        {"name":"Sunrun Span Raiders","position":Vector2(630,-460),"enemy":"imp","count":6,"radius":70.0,"rank":4},
        {"name":"Copper Shelf Ashscales","position":Vector2(2780,-80),"enemy":"ashscale_basilisk","count":4,"radius":82.0,"rank":5},
        {"name":"Red Mesa Grave Patrol","position":Vector2(-1680,2280),"enemy":"gravebound","count":6,"radius":76.0,"rank":5},
    ]
    profile["wildlife_sites"]=[
        {"name":"Sunrun Deer","position":Vector2(660,300),"species":"deer","count":7,"radius":430.0},
        {"name":"Sage Flat Hares","position":Vector2(-980,-1400),"species":"hare","count":10,"radius":420.0},
        {"name":"Mesa Grouse","position":Vector2(-1850,800),"species":"grouse","count":8,"radius":390.0},
    ]
    profile["secret_sites"]=[
        {"name":"Sundown Smuggler Cache","position":Vector2(-820,-2740),"kind":"hidden_cache","loot_table":"marcher_supplies"},
        {"name":"Sunspire Survey Chest","position":Vector2(-2260,500),"kind":"hidden_cache","loot_table":"marcher_relics"},
        {"name":"Copper Shelf Foreman's Cache","position":Vector2(2880,-90),"kind":"hidden_cache","loot_table":"cinderwatch_gear"},
    ]
    profile["lore_sites"]=[
        {"name":"Sundown Customs Ledger","position":Vector2(-520,-2820),"kind":"book","entry":"sundown_ledger"},
        {"name":"The Sunrun Covenant","position":Vector2(470,-590),"kind":"inscription","entry":"sunrun_covenant"},
        {"name":"Emberwell Water Book","position":Vector2(1520,450),"kind":"book","entry":"emberwell_water_book"},
    ]
    profile["field_boundaries"]=[
        {"name":"Emberwell North Garden","points":[Vector2(1320,650),Vector2(1530,760),Vector2(1710,610),Vector2(1480,500),Vector2(1320,650)]},
        {"name":"Emberwell South Garden","points":[Vector2(1540,210),Vector2(1760,330),Vector2(1880,170),Vector2(1640,60),Vector2(1540,210)]},
    ]
    profile["forest_regions"]=[
        {"name":"Emberwell Oasis Grove","center":Vector2(1150,760),"radius":520.0,"density":.62},
        {"name":"Sunrun Riparian Belt","center":Vector2(320,-1340),"radius":430.0,"density":.38},
    ]
    profile["mountain_chains"]=[
        {"name":"Sunrun Source Range","center":Vector2(2500,3050),"angle":-.34,"length":1800.0,"width":600.0,"height":110.0,"snow_line":10000.0},
        {"name":"Western Redwall","center":Vector2(-2800,1000),"angle":.20,"length":1800.0,"width":550.0,"height":70.0,"snow_line":10000.0},
        {"name":"Copper Shelf Escarpment","center":Vector2(3300,100),"angle":-.10,"length":1400.0,"width":430.0,"height":70.0,"snow_line":10000.0},
    ]
    profile["ocean_basins"]=[]
    profile["flat_regions"]=[]
    profile["landform_regions"]=[
        {"name":"Sundown Gravel Shelf","kind":"upland","center":Vector2(-500,-2700),"radius":1120.0,"aspect":.72,"angle":.04,"amplitude":11.0},
        {"name":"Sunrun Vale","kind":"valley","center":Vector2(560,-600),"length":6100.0,"width":760.0,"angle":-.18,"amplitude":5.0},
        {"name":"Emberwell Basin","kind":"basin","center":Vector2(1080,720),"radius":1060.0,"aspect":.76,"angle":.20,"amplitude":10.0},
        {"name":"Red Mesa Shoulder","kind":"ridge","center":Vector2(-1320,1780),"length":2100.0,"width":600.0,"angle":.18,"amplitude":20.0},
        {"name":"Southroad Rolling Country","kind":"rolling","center":Vector2(-500,2640),"radius":1600.0,"aspect":.84,"angle":-.08,"amplitude":18.0,"wavelength":560.0},
    ]
    profile["terrain_palette_regions"]=[
        {"name":"Sundown Scrub","center":Vector2(-520,-2500),"radius":1650.0,"aspect":.78,"angle":.02,"strength":.76,"color":[.37,.31,.18],"secondary_color":[.25,.27,.15],"cover_color":[.42,.34,.16],"cover_count":390},
        {"name":"Sunrun Alluvium","center":Vector2(420,-650),"radius":2100.0,"aspect":.34,"angle":-.18,"strength":.78,"color":[.30,.28,.17],"secondary_color":[.24,.31,.18],"cover_color":[.32,.35,.17],"cover_count":420},
        {"name":"Emberwell Green","center":Vector2(1040,690),"radius":1050.0,"aspect":.78,"angle":.16,"strength":.82,"color":[.30,.34,.18],"secondary_color":[.19,.31,.16],"cover_color":[.37,.40,.18],"cover_count":420},
        {"name":"Western Red Sandstone","center":Vector2(-2260,1080),"radius":1800.0,"aspect":.62,"angle":.18,"strength":.80,"color":[.46,.29,.17],"secondary_color":[.34,.24,.16],"cover_color":[.49,.34,.19],"cover_count":300},
        {"name":"Copper Shelf Stone","center":Vector2(2450,240),"radius":1550.0,"aspect":.68,"angle":-.12,"strength":.78,"color":[.43,.36,.27],"secondary_color":[.30,.28,.23],"cover_color":[.39,.32,.22],"cover_count":260},
        {"name":"Southroad Ochre","center":Vector2(-420,2650),"radius":1750.0,"aspect":.80,"angle":-.06,"strength":.72,"color":[.44,.34,.20],"secondary_color":[.29,.28,.17],"cover_color":[.47,.38,.20],"cover_count":320},
    ]
    profile["pond_sites"]=[
        {"name":"Emberwell Spring","position":Vector2(1260,890),"radius":148.0,"water_height":34.5},
        {"name":"Sage Mirror","position":Vector2(-1750,-760),"radius":82.0,"water_height":14.4},
    ]
    profile["waterfall_sites"]=[
        {"name":"Sunrun Cascades","position":Vector2(2020,2420),"width":24.0,"drop":4.2},
    ]
    profile["river_corridors"]=[{
        "name":"Sunrun River","width":36.0,"source_width":14.0,"mouth_width":72.0,
        "source_height":52.0,"mouth_height":8.4,
        "source_kind":"seasonal snow-free mountain runoff and sandstone springs","source_landmark":"Sunrun Cascades",
        "termination":"the Sunrun Headwater in Riverwatch and ultimately the Kingsflow",
        "points":_catmull_rom_points([
            Vector2(2200,2820),Vector2(2100,2600),Vector2(2020,2420),
            Vector2(1830,2170),Vector2(1560,1870),Vector2(1310,1510),
            Vector2(1100,1120),Vector2(900,650),Vector2(700,170),
            Vector2(520,-260),Vector2(430,-620),Vector2(350,-1040),
            Vector2(280,-1520),Vector2(330,-2050),Vector2(290,-2600),
            Vector2(310,-3150),Vector2(300,-3600),
        ],6),
    },{
        "name":"Emberwell Spring Run","width":16.0,"source_width":10.0,"mouth_width":16.0,
        "source_height":35.95,"mouth_height":34.8,
        "source_kind":"permanent oasis spring","source_landmark":"Emberwell Spring",
        "termination":"the Sunrun River",
        "points":_catmull_rom_points([
            Vector2(1260,890),Vector2(1190,820),Vector2(1080,760),Vector2(900,650),
        ],6),
    }]
    profile["road_corridors"]=[{
        "name":"Sunward Realmroad","route_class":"major",
        "purpose":"the continuous caravan road from Riverwatch through the dryland towns and toward the southern passes",
        "destinations":["Highfield","Sundown Gate","Red Mesa Hold","Southroad Pass"],
        "width":18.0,"terrain_width":235.0,"terrain_relief":4.0,"grade_limit":.070,
        "points":[
            Vector2(-420,-3600),Vector2(-460,-3300),Vector2(-500,-2850),
            Vector2(-430,-2400),Vector2(-500,-1900),Vector2(-480,-1450),
            Vector2(-400,-1050),Vector2(-250,-750),Vector2(-220,-300),
            Vector2(-320,180),Vector2(-500,680),Vector2(-720,1160),
            Vector2(-900,1540),
            Vector2(-1050,1880),Vector2(-1180,2320),Vector2(-1260,2780),Vector2(-1220,3220),Vector2(-1200,3600),
        ],
    },{
        "name":"Emberwell Caravan Road","route_class":"secondary",
        "purpose":"the single engineered crossing from the Sunward road to the oasis market",
        "destinations":["Sunward Realmroad","Sunrun Span","Emberwell"],
        "width":12.5,"terrain_width":185.0,"terrain_relief":3.3,"grade_limit":.085,
        "points":[
            Vector2(-250,-750),Vector2(-80,-650),Vector2(430,-620),
            Vector2(800,-560),Vector2(1110,-350),Vector2(1350,-20),Vector2(1500,420),
        ],
    },{
        "name":"Copper Shelf Road","route_class":"secondary",
        "purpose":"a contour freight road from Emberwell to the eastern mine settlement",
        "destinations":["Emberwell","Copper Hollow","Copper Shelf Mine"],
        "width":12.0,"terrain_width":180.0,"terrain_relief":3.3,"grade_limit":.090,
        "points":[Vector2(1500,420),Vector2(1740,380),Vector2(2010,330),Vector2(2260,280),Vector2(2440,230),Vector2(2700,80),Vector2(2860,-120)],
    },{
        "name":"Sunspire Overlook Road","route_class":"secondary",
        "purpose":"a gradual shelf road from Red Mesa Hold to the Sunspire overlook",
        "destinations":["Red Mesa Hold","Sunspire Mesa"],
        "width":10.5,"terrain_width":170.0,"terrain_relief":3.0,"grade_limit":.095,
        "points":[Vector2(-1050,1880),Vector2(-1320,1640),Vector2(-1580,1360),Vector2(-1810,1040),Vector2(-2020,720),Vector2(-2220,500)],
    }]
    profile["ford_sites"]=[{
        "name":"Sunrun Span","position":Vector2(430,-620),
        "radius":44.0,"standalone":false,"bridge_width":11.0,"bank_guard":true,
        "crossing_class":"major",
        "purpose":"the single necessary crossing carrying the Sunward Realmroad to Emberwell",
    }]
    profile["trail_corridors"]=[
        {"name":"Sunrun Cascade Track","route_class":"local","purpose":"walkable approach from the eastern road to the river source overlook","width":4.8,"engineered_grade":true,"points":[Vector2(2440,230),Vector2(2350,720),Vector2(2240,1240),Vector2(2160,1780),Vector2(2020,2420)]},
        {"name":"Emberwell Shore Path","route_class":"local","purpose":"short angler path from the market to the spring's walkable bank","width":3.5,"engineered_grade":true,"points":[Vector2(1500,420),Vector2(1430,580),Vector2(1380,720),Vector2(1365,790)]},
        {"name":"Smuggler Shelf Track","route_class":"local","purpose":"concealed footpath from Sundown Gate to the western cache shelf","width":4.4,"engineered_grade":true,"points":[Vector2(-500,-2850),Vector2(-650,-2820),Vector2(-820,-2740)]},
    ]


func _author_eastern_marches(profile:Dictionary)->void:
    profile["zone_id"]="east_marches"
    profile["zone_name"]="Eastern Marches"
    profile["biome_id"]="continental_marches"
    profile["climate"]="warm continental upland"
    profile["danger_tier"]=3
    profile["recommended_level"]=[8,18]
    profile["difficulty_multiplier"]=1.48
    profile["snow_line"]=10000.0
    profile["snow_strength"]=0.0
    profile["population_scale"]=0.29
    # Batched meadow patches are inexpensive, but the old global default left
    # the broad March terraces almost empty at player height.
    profile["meadow_samples_per_chunk"]=360
    profile["streamed_population"]=true
    profile["streamed_heightmap_collision"]=true
    profile["region_origin"]=Vector2(7200,0)
    # Keep the east/west join last on both neighboring profiles. Seam blends
    # overlap at atlas corners, and matching evaluation order keeps the shared
    # vertical edge numerically watertight rather than merely visually close.
    profile["seam_edges"]=[{
        "edge":"south","key":"north_frontier_pass","blend_width":620.0,
        "base_height":13.5,"junction_key":"riverwatch_northeast_junction",
        "junction_along":3600.0,"junction_height":17.0,"junction_blend":680.0,
    },{
        "edge":"west","key":"eastern_marches_pass","blend_width":620.0,
        "base_height":16.0,"junction_key":"riverwatch_northeast_junction",
        "junction_along":-3600.0,"junction_height":17.0,"junction_blend":680.0,
        "river_crossings":[
            {"name":"Redstone Headwater","along":-3560.0,"width":52.0,"bed_height":10.544},
            {"name":"Eastreach Emberwash","along":2850.0,"width":46.0,"bed_height":10.543},
        ],
    }]
    profile["zone_exits"]=[
        {"edge":"west","target":"starting_realm","entry":"east","seamless":true},
    ]
    profile["spawn_site"]={
        "name":"Dawnford","position":Vector2(-2700,1000),"radius":174.0,
        "ground_height":19.0,"ground_inner_ratio":.82,"starter":false,
        "architecture_set":"marcher_stone",
        "role":"western gate market and caravan customs town",
        "siting_reason":"a broad dry loess shelf where the Riverwatch realmway enters the open marches",
        "connections":["Eastreach","Amberfield","March Keep"],
    }
    profile["town_sites"]=[
        {
            "name":"Amberfield","position":Vector2(-1120,420),"radius":166.0,
            "ground_height":26.0,"ground_inner_ratio":.82,"architecture_set":"marcher_timber",
            "role":"grain town and central caravan exchange",
            "siting_reason":"fertile wind-blown soil on a terrace above the Emberwash floodplain",
            "connections":["Dawnford","March Keep","Glassmere"],
        },{
            "name":"March Keep","position":Vector2(980,420),"radius":184.0,
            "ground_height":46.0,"ground_inner_ratio":.80,"architecture_set":"marcher_stone",
            "role":"fortified eastern road ward overlooking the only dependable crossing",
            "siting_reason":"a basalt shoulder above Ember Span controlling the road into the volcanic uplands",
            "connections":["Amberfield","Cinderwatch","Saltwatch"],
        },{
            "name":"Saltwatch","position":Vector2(-480,2300),"radius":142.0,
            "ground_height":31.0,"ground_inner_ratio":.80,"architecture_set":"marcher_timber",
            "role":"salt-meadow village and northern trailhead",
            "siting_reason":"firm ground between Glassmere's reed basin and the northern chalk ridges",
            "connections":["Amberfield","Glassmere"],
        },
    ]
    profile["camp_sites"]=[
        {"name":"Dawnway Caravan Camp","position":Vector2(-3320,1080),"radius":44.0},
        {"name":"Cinderwatch Survey Camp","position":Vector2(2260,-1740),"radius":42.0},
        {"name":"Glassmere Reed Camp","position":Vector2(1400,2300),"radius":40.0},
    ]
    profile["map_sites"]=[
        {"name":"March Keep","kind":"fortress","position":Vector2(1040,350),"radius":50.0,"elevation_lift":14.0,"elevation_inner":62.0,"elevation_radius":245.0,"elevation_role":"fortress landmark visible along the central realmway"},
        {"name":"Ember Span","kind":"bridge","position":Vector2(120,-70),"radius":36.0,"elevation_role":"the sole major-road crossing of the Emberwash"},
        {"name":"Saltmeadow Bridge","kind":"bridge","position":Vector2(-1449,1527),"radius":24.0,"elevation_role":"a smaller market-road crossing linking Amberfield to Saltwatch"},
        {"name":"Cinderwatch Beacon","kind":"watchtower","position":Vector2(2360,-1840),"radius":30.0,"elevation_lift":18.0,"elevation_inner":54.0,"elevation_radius":230.0,"elevation_role":"high road beacon below Embercrag"},
        {"name":"Embercrag","kind":"volcano","position":Vector2(2920,-2640),"radius":170.0,"elevation_role":"dormant volcanic massif defining the eastern skyline"},
        {"name":"Glassmere","kind":"lake","position":Vector2(1780,2460),"radius":138.0,"elevation_role":"spring-fed upland mere feeding a tributary of the Emberwash"},
        {"name":"Ashstep Falls","kind":"waterfall","position":Vector2(2100,-1720),"radius":34.0,"elevation_role":"the Emberwash descending from the volcanic highlands"},
    ]
    profile["landmark_sites"]=[
        {"name":"Dawn Gate Stones","kind":"outcrop","position":Vector2(-3010,920),"radius":66.0,"count":16,"rotation":.16},
        {"name":"March Keep Basalt Teeth","kind":"outcrop","position":Vector2(1320,170),"radius":82.0,"count":20,"rotation":.48},
        {"name":"Embercrag Black Scree","kind":"outcrop","position":Vector2(2700,-2450),"radius":118.0,"count":30,"rotation":-.26},
        {"name":"Glassknife Chalk Ribs","kind":"outcrop","position":Vector2(2140,2720),"radius":98.0,"count":24,"rotation":.20},
        {"name":"Cinderwatch Beacon","kind":"cinderwatch_beacon","position":Vector2(2360,-1840),"radius":34.0,"scale":1.35,"rotation":.18},
        {"name":"Cinderwatch Signal Yard","kind":"cinderwatch_signal_yard","position":Vector2(2310,-1785),"radius":24.0,"scale":.98,"rotation":.18},
        {"name":"Cinderwatch East Shelf","kind":"outcrop","position":Vector2(2490,-1760),"radius":46.0,"count":10,"rotation":.34},
        {"name":"Cinderwatch West Shelf","kind":"outcrop","position":Vector2(2160,-1920),"radius":38.0,"count":8,"rotation":-.22},
        {"name":"Embercrag Basalt Crown","kind":"embercrag_crown","position":Vector2(2920,-2640),"radius":72.0,"scale":1.26,"rotation":-.10},
        {"name":"Dawnford Elm Grove","kind":"grove","species":"oak","position":Vector2(-2380,1260),"radius":86.0,"count":22},
        {"name":"Glassmere Willows","kind":"grove","species":"willow","position":Vector2(1430,2370),"radius":92.0,"count":24},
        {"name":"Glassmere North Willows","kind":"grove","species":"willow","position":Vector2(1690,2650),"radius":58.0,"count":13},
        {"name":"Glassmere South Copse","kind":"grove","species":"willow","position":Vector2(1880,2260),"radius":52.0,"count":11},
        {"name":"Glassmere West Stones","kind":"outcrop","position":Vector2(1570,2520),"radius":34.0,"count":8,"rotation":-.18},
        {"name":"Glassmere South Stones","kind":"outcrop","position":Vector2(1880,2265),"radius":28.0,"count":6,"rotation":.32},
        {"name":"Amberfield Windbreak","kind":"grove","species":"maple","position":Vector2(-1280,800),"radius":78.0,"count":20},
        {"name":"Dawnway Elm Avenue","kind":"grove","species":"oak","position":Vector2(-2050,980),"radius":126.0,"count":34},
        {"name":"Amber Orchard","kind":"grove","species":"maple","position":Vector2(-720,760),"radius":108.0,"count":30},
        {"name":"Saltwatch Poplars","kind":"grove","species":"willow","position":Vector2(-760,2460),"radius":104.0,"count":28},
        {"name":"Ashstep Junipers","kind":"grove","species":"pine","position":Vector2(1740,-1280),"radius":116.0,"count":32},
        {"name":"March Road Waystone","kind":"waystone","position":Vector2(-3400,1060),"radius":10.0,"rotation":.08},
        {"name":"Ashstep Pilgrim Cairn","kind":"cairn","position":Vector2(2020,-1580),"radius":8.0,"scale":1.14,"rotation":.20},
    ]
    profile["ecology_sites"]=[
        {"name":"Dawnford Sage Verge","kind":"bracken","position":Vector2(-2450,1180),"radius":250.0,"count":175},
        {"name":"Amberfield Dry Ferns","kind":"bracken","position":Vector2(-980,620),"radius":235.0,"count":155},
        {"name":"Glassmere Reed Meadow","kind":"bracken","position":Vector2(1540,2300),"radius":280.0,"count":210},
        {"name":"Glassmere North Wet Meadow","kind":"bracken","position":Vector2(1700,2660),"radius":150.0,"count":120},
        {"name":"Glassmere South Wet Meadow","kind":"bracken","position":Vector2(1850,2260),"radius":135.0,"count":105},
        {"name":"Cinderwatch Fireweed Pockets","kind":"bracken","position":Vector2(2470,-1680),"radius":170.0,"count":120},
        {"name":"Ashstep Fireweed","kind":"bracken","position":Vector2(1900,-1480),"radius":220.0,"count":145},
    ]
    profile["encounter_sites"]=[
        {"name":"Dawnway Ashfang Pack","position":Vector2(-2050,1380),"enemy":"ashfang","count":5,"radius":64.0,"rank":3},
        {"name":"Amber Barrow Dead","position":Vector2(-840,-1120),"enemy":"gravebound","count":6,"radius":72.0,"rank":4},
        {"name":"Ember Span Raiders","position":Vector2(420,120),"enemy":"imp","count":7,"radius":68.0,"rank":4},
        {"name":"Cinderwatch Ashscale Brood","position":Vector2(2240,-1520),"enemy":"ashscale_basilisk","count":5,"radius":82.0,"rank":5},
        {"name":"Glassknife Wraiths","position":Vector2(2480,2640),"enemy":"bramble_wraith","count":6,"radius":78.0,"rank":5},
    ]
    profile["wildlife_sites"]=[
        {"name":"Dawnford Deer Run","position":Vector2(-2320,1650),"species":"deer","count":8,"radius":450.0},
        {"name":"Amberfield Hares","position":Vector2(-950,850),"species":"hare","count":11,"radius":390.0},
        {"name":"Glassmere Grouse","position":Vector2(1460,2620),"species":"grouse","count":10,"radius":400.0},
        {"name":"Ashstep Red Deer","position":Vector2(1740,-1380),"species":"deer","count":6,"radius":420.0},
    ]
    profile["secret_sites"]=[
        {"name":"Dawn Tollmaster's Cache","position":Vector2(-2820,1120),"kind":"hidden_cache","loot_table":"marcher_supplies"},
        {"name":"Amber Barrow Reliquary","position":Vector2(-920,-1060),"kind":"hidden_cache","loot_table":"marcher_relics"},
        {"name":"Cinderwatch Signal Chest","position":Vector2(2400,-1880),"kind":"hidden_cache","loot_table":"cinderwatch_gear"},
    ]
    profile["lore_sites"]=[
        {"name":"Dawnford Toll Ledger","position":Vector2(-2740,970),"kind":"book","entry":"dawnford_ledger"},
        {"name":"The Oath of Ember Span","position":Vector2(180,-30),"kind":"inscription","entry":"ember_span_oath"},
        {"name":"Cinderwatch Ash Record","position":Vector2(2330,-1800),"kind":"book","entry":"cinderwatch_record"},
    ]
    profile["field_boundaries"]=[]
    profile["forest_regions"]=[
        {"name":"Dawnwood","center":Vector2(-2480,1480),"radius":850.0,"density":.68},
        {"name":"Amberfield Coppice","center":Vector2(-980,920),"radius":690.0,"density":.55},
        {"name":"Glassmere Willowwood","center":Vector2(1540,2380),"radius":760.0,"density":.66},
        {"name":"Ashstep Juniper Wood","center":Vector2(1760,-1320),"radius":720.0,"density":.48},
    ]
    profile["mountain_chains"]=[
        {"name":"Embercrag Massif","center":Vector2(2860,-2500),"angle":.44,"length":2600.0,"width":980.0,"height":248.0,"snow_line":10000.0},
        {"name":"Glassknife Ridge","center":Vector2(2580,2460),"angle":-.32,"length":2500.0,"width":720.0,"height":154.0,"snow_line":10000.0},
        {"name":"South March Escarpment","center":Vector2(-250,3000),"angle":.08,"length":2900.0,"width":680.0,"height":108.0,"snow_line":10000.0},
    ]
    profile["ocean_basins"]=[]
    profile["flat_regions"]=[]
    profile["landform_regions"]=[
        {"name":"Dawnway Shelf","kind":"upland","center":Vector2(-2500,1040),"radius":1040.0,"aspect":.70,"angle":.04,"amplitude":13.0},
        {"name":"Amber Plains","kind":"rolling","center":Vector2(-900,500),"radius":1500.0,"aspect":.82,"angle":.12,"amplitude":15.0,"wavelength":520.0},
        {"name":"Emberwash Vale","kind":"valley","center":Vector2(250,320),"length":5700.0,"width":780.0,"angle":-.72,"amplitude":34.0},
        {"name":"March Keep Shoulder","kind":"ridge","center":Vector2(1050,420),"length":1750.0,"width":520.0,"angle":.30,"amplitude":30.0},
        {"name":"Cinderwatch Steps","kind":"rolling","center":Vector2(2050,-1650),"radius":1380.0,"aspect":.70,"angle":.45,"amplitude":23.0,"wavelength":440.0},
        {"name":"Glassmere Basin","kind":"basin","center":Vector2(1680,2400),"radius":980.0,"aspect":.76,"angle":-.18,"amplitude":18.0},
    ]
    profile["terrain_palette_regions"]=[
        {"name":"Dawnway Loess","center":Vector2(-2600,1050),"radius":1500.0,"aspect":.72,"angle":.05,"strength":.70,"color":[.40,.34,.18],"secondary_color":[.28,.31,.15],"cover_color":[.39,.35,.14],"cover_count":420},
        {"name":"Amber Grassland","center":Vector2(-850,500),"radius":1780.0,"aspect":.82,"angle":.10,"strength":.68,"color":[.43,.36,.13],"secondary_color":[.29,.33,.14],"cover_color":[.47,.38,.12],"cover_count":520},
        {"name":"Emberwash Alluvium","center":Vector2(120,260),"radius":1700.0,"aspect":.40,"angle":-.72,"strength":.66,"color":[.32,.31,.18],"secondary_color":[.38,.28,.14],"cover_color":[.24,.33,.15],"cover_count":390},
        {"name":"Cinderwatch Basalt","center":Vector2(2200,-1750),"radius":1520.0,"aspect":.72,"angle":.42,"strength":.76,"color":[.31,.28,.25],"secondary_color":[.44,.29,.17],"cover_color":[.35,.27,.17],"cover_count":320},
        {"name":"Glassknife Chalk","center":Vector2(2200,2450),"radius":1500.0,"aspect":.70,"angle":-.28,"strength":.66,"color":[.46,.44,.32],"secondary_color":[.30,.35,.22],"cover_color":[.34,.37,.21],"cover_count":350},
    ]
    profile["pond_sites"]=[
        {"name":"Glassmere","position":Vector2(1780,2460),"radius":138.0,"water_height":36.5},
        {"name":"Amberfield Mere","position":Vector2(-1540,1080),"radius":92.0,"water_height":22.0},
    ]
    profile["waterfall_sites"]=[
        {"name":"Ashstep Falls","position":Vector2(2100,-1720),"width":28.0,"drop":4.4},
    ]
    profile["river_corridors"]=[{
        "name":"Emberwash River","width":46.0,"source_width":14.0,"mouth_width":20.0,
        # Eastfall's 2.6 m downstream grade break is already reflected in the
        # receiving Eastreach endpoint, so the cross-region water datum is 12.23.
        "source_height":58.0,"mouth_height":12.23,
        "source_kind":"volcanic spring and upland storm runoff","source_landmark":"Embercrag Spring",
        "termination":"the Eastreach Tributary at the Riverwatch boundary",
        "points":_catmull_rom_points([
            Vector2(2840,-2500),Vector2(2480,-2180),Vector2(2100,-1720),
            Vector2(1780,-1360),Vector2(1450,-980),Vector2(1100,-620),
            Vector2(760,-380),Vector2(420,-180),Vector2(120,-70),
            Vector2(-220,220),Vector2(-620,620),Vector2(-1050,1080),
            Vector2(-1500,1580),Vector2(-2050,2080),Vector2(-2700,2530),
            # Mirror the Eastreach endpoint tangent across the seam so channel
            # shoulders, not only the centerline, meet without a lip.
            Vector2(-3200,3150),Vector2(-3400,3000),Vector2(-3600,2850),
        ],6),
    },{
        "name":"Glassmere Run","width":16.0,"source_width":10.0,"mouth_width":16.0,
        "source_height":36.5,"mouth_height":25.0,
        "source_kind":"spring-fed upland mere","source_landmark":"Glassmere",
        "termination":"the Emberwash River",
        "points":_catmull_rom_points([
            Vector2(1780,2460),Vector2(1500,2200),Vector2(1120,1980),
            Vector2(680,1770),Vector2(220,1570),Vector2(-300,1390),Vector2(-1050,1080),
        ],6),
    },{
        "name":"Redstone Headwater","width":52.0,"source_width":15.0,"mouth_width":24.0,
        # The receiving Redstone corridor carries its authored 2.6 m waterfall
        # grade break upstream to the boundary; match that datum exactly.
        "source_height":61.0,"mouth_height":12.23,
        "source_kind":"Embercrag north-slope runoff","source_landmark":"Embercrag North Spring",
        "termination":"the Redstone Tributary at the Riverwatch boundary",
        "points":_catmull_rom_points([
            Vector2(2780,-2760),Vector2(2260,-2940),Vector2(1660,-3120),
            Vector2(980,-3270),Vector2(240,-3380),Vector2(-520,-3460),
            Vector2(-1320,-3510),Vector2(-2160,-3540),Vector2(-2920,-3560),
            Vector2(-3400,-3560),Vector2(-3600,-3560),
        ],6),
    }]
    profile["road_corridors"]=[
        {
            "name":"Dawnway Realmroad","route_class":"major",
            "purpose":"continuous eastbound road from Eastreach through the march towns to Cinderwatch",
            "destinations":["Eastreach","Dawnford","Amberfield","Ember Span","March Keep","Cinderwatch"],
            "width":18.0,"terrain_width":235.0,"terrain_relief":4.2,"grade_limit":.070,
            "points":[
                Vector2(-3600,1050),Vector2(-3320,1040),Vector2(-3000,1020),Vector2(-2700,1000),
                Vector2(-2320,900),Vector2(-1940,760),Vector2(-1540,560),Vector2(-1120,420),
                Vector2(-720,180),Vector2(-420,-120),Vector2(-250,-320),Vector2(120,-70),
                Vector2(500,260),Vector2(980,420),Vector2(1280,100),Vector2(1550,-350),
                Vector2(1800,-850),Vector2(2100,-1400),Vector2(2360,-1840),
            ],
        },{
            "name":"Saltwatch Road","route_class":"secondary",
            "purpose":"graded market road between Amberfield and the northern salt meadows",
            "destinations":["Amberfield","Saltwatch","Glassmere"],
            "width":12.5,"terrain_width":180.0,"terrain_relief":3.2,"grade_limit":.095,
            # Stay on the western shoulder of Glassmere Run. The former direct
            # diagonal crossed the same tributary twice and generated two
            # purposeless bridges before reaching Saltwatch.
            "points":[
                Vector2(-1120,420),Vector2(-1280,760),Vector2(-1410,1120),
                Vector2(-1460,1500),Vector2(-1320,1840),Vector2(-980,2140),
                Vector2(-680,2260),Vector2(-480,2300),
            ],
        },{
            "name":"Glassmere Survey Road","route_class":"secondary",
            "purpose":"contour road from Saltwatch to Glassmere without climbing the chalk ridge directly",
            "destinations":["Saltwatch","Glassmere"],
            "width":11.0,"terrain_width":170.0,"terrain_relief":3.1,"grade_limit":.10,
            "points":[Vector2(-480,2300),Vector2(-100,2440),Vector2(320,2500),Vector2(740,2490),Vector2(1160,2440),Vector2(1500,2410)],
        },
    ]
    profile["ford_sites"]=[{
        "name":"Ember Span","position":Vector2(120,-70),
        "radius":50.0,"standalone":false,"bridge_width":12.0,"bank_guard":true,
        "crossing_class":"major",
        "purpose":"the Dawnway's single necessary crossing of the Emberwash River",
    },{
        "name":"Saltmeadow Bridge","position":Vector2(-1449,1527),
        "radius":34.0,"standalone":false,"bridge_width":9.0,"bank_guard":true,
        "crossing_class":"secondary",
        "purpose":"the smaller Saltwatch market-road crossing of the lower Emberwash",
    }]
    profile["trail_corridors"]=[
        {"name":"Ashstep Falls Track","route_class":"local","purpose":"safe foot approach from Cinderwatch to the waterfall overlook","width":5.0,"engineered_grade":true,"points":[Vector2(2360,-1840),Vector2(2240,-1810),Vector2(2100,-1720)]},
        # End on the west walking bank. The former final point sat well inside
        # Glassmere and rendered as a rectangular dirt pier across the water.
        {"name":"Glassmere Shore Path","route_class":"local","purpose":"angler path from the survey road to Glassmere","width":3.4,"engineered_grade":true,"points":[Vector2(1500,2410),Vector2(1538,2430),Vector2(1574,2428),Vector2(1608,2440)]},
        {"name":"Amber Barrow Track","route_class":"local","purpose":"burial track from Amberfield to the southern barrows","width":4.8,"engineered_grade":true,"points":[Vector2(-1120,420),Vector2(-1080,20),Vector2(-1030,-380),Vector2(-980,-760),Vector2(-900,-1080)]},
    ]


func _author_north_frontier(profile:Dictionary)->void:
    profile["zone_id"]="north_frontier"
    profile["zone_name"]="North Frontier"
    profile["biome_id"]="alpine_frontier"
    profile["climate"]="cold highland"
    profile["danger_tier"]=2
    profile["recommended_level"]=[5,14]
    profile["difficulty_multiplier"]=1.45
    profile["snow_line"]=112.0
    profile["snow_strength"]=1.0
    # The adjacent region is populated during play. MultiMesh scatter still
    # keeps it visually rich at this density while substantially reducing the
    # height sampling and transform work performed during northbound travel.
    # Western woodland is intentionally denser than the exposed frontier but
    # remains comfortably below the starter region's full population budget.
    profile["population_scale"]=0.28
    profile["streamed_population"]=true
    profile["streamed_heightmap_collision"]=true
    profile["region_origin"]=Vector2(0,-7200)
    profile["seam_edges"]=[
        {
            "edge":"north","key":"north_frontier_pass","blend_width":620.0,
            "base_height":13.5,"junction_key":"riverwatch_northwest_junction",
            "junction_along":-3600.0,"junction_height":18.5,"junction_blend":680.0,
        },
        {
            "edge":"south","key":"glacial_pass","blend_width":620.0,
            "base_height":28.0,"junction_key":"stormbreak_glacial_junction",
            "junction_along":-3600.0,"junction_height":26.0,"junction_blend":680.0,
        },
        {
            "edge":"west","key":"stormbreak_greyfen_pass","blend_width":620.0,
            "base_height":22.0,"junction_key":"riverwatch_northwest_junction",
            "junction_along":-3600.0,"junction_height":18.5,"junction_blend":680.0,
            "junctions":[{"key":"stormbreak_glacial_junction","along":-10800.0,"height":26.0,"blend":680.0}],
        },
    ]
    profile["zone_exits"]=[
        {"edge":"south","target":"starting_realm","entry":"north","seamless":true},
        {"edge":"north","target":"glacial_range","entry":"south","seamless":true},
        {"edge":"west","target":"stormbreak_highlands","entry":"east","seamless":true},
        {"edge":"east","target":"east_marches","entry":"north"},
    ]
    profile["spawn_site"]={
        "name":"Pinewatch","position":Vector2(-470,-2120),"radius":154.0,
        "ground_height":18.0,"ground_inner_ratio":.84,"starter":false,
        "role":"frontier pass and timber settlement",
        "siting_reason":"a dry shelf above the headwater road where the mountain pass opens",
        "connections":["Highfield","Frostmere"],
    }
    profile["town_sites"]=[
        {
            "name":"Frostmere","position":Vector2(980,120),"radius":168.0,
            "ground_height":26.0,"ground_inner_ratio":.80,
            "role":"high-valley lake market",
            "siting_reason":"a broad defensible terrace between the realm road and Frostmere Tarn",
            "connections":["Pinewatch","Greyfen"],
        },
        {
            "name":"Greyfen","position":Vector2(-1320,1760),"radius":142.0,
            "ground_height":21.0,"ground_inner_ratio":.80,
            "role":"western moor and mining town",
            "siting_reason":"firm ground at the mouth of a mineral-bearing side valley",
            "connections":["Frostmere"],
        },
    ]
    profile["camp_sites"]=[
        {"name":"Passwarden Camp","position":Vector2(-730,-2850),"radius":46.0},
        {"name":"Snowmelt Camp","position":Vector2(720,1800),"radius":44.0},
    ]
    profile["map_sites"]=[
        {
            "name":"Pinewatch Beacon","kind":"watchtower","position":Vector2(-350,-2240),
            "radius":18.0,"elevation_lift":9.0,"elevation_inner":42.0,
            "elevation_radius":180.0,"elevation_role":"frontier pass landmark",
        },
        {
            "name":"Frostmere Waystation","kind":"waystation","position":Vector2(560,-320),
            "radius":48.0,"ground_height":23.0,"usable_ground":true,
        },
        {
            "name":"The White Crown","kind":"ruin","position":Vector2(420,2780),
            "radius":30.0,"elevation_lift":22.0,"elevation_inner":58.0,
            "elevation_radius":260.0,"elevation_role":"far northern overlook",
        },
        {
            "name":"Crownfall Snowmelt","kind":"headwater","position":Vector2(430,2630),
            "radius":24.0,"elevation_role":"visible snowmelt source of the Crownfall River",
        },
    ]
    profile["landmark_sites"]=[
        {"name":"Pass Sentinel Pines","kind":"grove","species":"pine","position":Vector2(-920,-2920),"radius":72.0,"count":20},
        {"name":"Frostmere Birch Stand","kind":"grove","species":"birch","position":Vector2(1330,430),"radius":64.0,"count":18},
        {"name":"Greyfen Standing Stones","kind":"outcrop","position":Vector2(-1620,1540),"radius":42.0,"count":11,"rotation":.44},
        {"name":"White Crown Crags","kind":"outcrop","position":Vector2(420,2680),"radius":58.0,"count":15,"rotation":.18},
        {"name":"Crownfall Headwall","kind":"outcrop","position":Vector2(300,2740),"radius":78.0,"count":18,"rotation":.35},
        {"name":"North Realm Waystone","kind":"waystone","position":Vector2(-560,-3280),"radius":10.0,"rotation":.1},
    ]
    profile["ecology_sites"]=[
        {"name":"Pinewatch Bracken","kind":"bracken","position":Vector2(-820,-1900),"radius":210.0,"count":150},
        {"name":"Frostmere Ferns","kind":"bracken","position":Vector2(1280,40),"radius":190.0,"count":140},
        {"name":"Greyfen Heather","kind":"bracken","position":Vector2(-1600,1820),"radius":175.0,"count":115},
    ]
    profile["encounter_sites"]=[
        {"name":"Northgate Imp Scouts","position":Vector2(-980,-1420),"enemy":"imp","count":4,"radius":44.0,"rank":2},
        {"name":"Frostmere Ashfang Den","position":Vector2(1510,760),"enemy":"ashfang","count":4,"radius":52.0,"rank":3},
        {"name":"Greyfen Grave Patrol","position":Vector2(-1960,1320),"enemy":"gravebound","count":5,"radius":64.0,"rank":3},
        {"name":"White Crown Wraithwood","position":Vector2(920,2140),"enemy":"bramble_wraith","count":5,"radius":58.0,"rank":4},
    ]
    profile["wildlife_sites"]=[
        {"name":"Pinewatch Deer Range","position":Vector2(-1240,-2080),"species":"deer","count":6,"radius":410.0},
        {"name":"Frostmere Hare Ground","position":Vector2(1320,220),"species":"hare","count":10,"radius":360.0},
        {"name":"Greyfen Grouse Moor","position":Vector2(-1680,1720),"species":"grouse","count":8,"radius":330.0},
    ]
    profile["secret_sites"]=[
        {"name":"The Warden's Frozen Cache","position":Vector2(690,2510),"kind":"hidden_cache","loot_table":"white_crown_relics"},
        {"name":"Greyfen Smuggler Crevice","position":Vector2(-2280,1610),"kind":"hidden_cache","loot_table":"greyfen_ore"},
    ]
    profile["lore_sites"]=[
        {"name":"Pinewatch Muster Roll","position":Vector2(-440,-2070),"kind":"book","entry":"pinewatch_muster"},
        {"name":"Tablet of the First Thaw","position":Vector2(520,2450),"kind":"inscription","entry":"first_thaw"},
    ]
    profile["field_boundaries"]=[]
    profile["forest_regions"]=[
        {"name":"Northgate Pines","center":Vector2(-1050,-2580),"radius":760.0,"density":.82},
        {"name":"Frostmere Forest","center":Vector2(1510,-120),"radius":820.0,"density":.76},
        {"name":"Greyfen Wood","center":Vector2(-1740,1280),"radius":700.0,"density":.72},
        {"name":"White Crown Pines","center":Vector2(650,2440),"radius":740.0,"density":.68},
    ]
    profile["mountain_chains"]=[
        {"name":"West Pass Wall","center":Vector2(-1900,-2500),"angle":.18,"length":2100.0,"width":620.0,"height":150.0,"snow_line":124.0},
        {"name":"East Pass Wall","center":Vector2(1550,-2350),"angle":-.20,"length":1900.0,"width":580.0,"height":142.0,"snow_line":126.0},
        {"name":"White Crown Range","center":Vector2(450,2600),"angle":.05,"length":2300.0,"width":760.0,"height":205.0,"snow_line":108.0},
        {"name":"Greyfen Crags","center":Vector2(-2500,1250),"angle":.48,"length":1300.0,"width":520.0,"height":126.0},
    ]
    profile["ocean_basins"]=[]
    profile["flat_regions"]=[]
    profile["landform_regions"]=[
        {"name":"Northgate Pass","kind":"valley","center":Vector2(-300,-2550),"length":2200.0,"width":620.0,"angle":1.48,"amplitude":22.0},
        {"name":"Pinewatch Shelf","kind":"upland","center":Vector2(-470,-2050),"radius":760.0,"aspect":.72,"angle":.12,"amplitude":13.0},
        {"name":"Frostmere Vale","kind":"basin","center":Vector2(920,180),"radius":1120.0,"aspect":.74,"angle":-.18,"amplitude":14.0},
        {"name":"Greyfen Folds","kind":"rolling","center":Vector2(-1280,1540),"radius":980.0,"aspect":.70,"angle":.42,"amplitude":16.0,"wavelength":440.0},
        {"name":"White Crown Ascent","kind":"ridge","center":Vector2(380,2380),"length":1700.0,"width":460.0,"angle":1.48,"amplitude":34.0},
    ]
    profile["terrain_palette_regions"]=[
        {"name":"Northgate Moss","center":Vector2(-420,-2400),"radius":1250.0,"aspect":.72,"angle":.10,"strength":.38,"color":[.10,.22,.14],"secondary_color":[.18,.28,.15],"cover_color":[.12,.29,.16],"cover_count":360},
        {"name":"Frostmere Grass","center":Vector2(900,180),"radius":1350.0,"aspect":.76,"angle":-.18,"strength":.36,"color":[.18,.29,.20],"secondary_color":[.25,.34,.20],"cover_color":[.18,.32,.18],"cover_count":380},
        {"name":"Greyfen Moor","center":Vector2(-1450,1500),"radius":1150.0,"aspect":.72,"angle":.36,"strength":.42,"color":[.24,.25,.16],"secondary_color":[.16,.22,.15],"cover_color":[.31,.29,.14],"cover_count":340},
        {"name":"White Crown Scree","center":Vector2(450,2550),"radius":1150.0,"aspect":.64,"angle":.04,"strength":.46,"color":[.31,.32,.29],"secondary_color":[.22,.27,.23],"cover_color":[.25,.28,.22],"cover_count":280},
    ]
    profile["pond_sites"]=[
        {"name":"Frostmere Tarn","position":Vector2(1180,420),"radius":138.0,"water_height":4.10},
        {"name":"Greyfen Pool","position":Vector2(-1760,2020),"radius":88.0,"water_height":3.25},
    ]
    profile["waterfall_sites"]=[
        {"name":"Crownfall","position":Vector2(420,2360),"width":42.0,"drop":4.8},
    ]
    profile["river_corridors"]=[
        {
            "name":"Crownfall River","width":44.0,"source_width":32.0,"mouth_width":44.0,
            "source_kind":"snowmelt confluence","source_landmark":"Crownfall Snowmelt","termination":"Crownspire Headwater",
            "points":_catmull_rom_points([
                Vector2(430,2630),Vector2(420,2360),Vector2(360,2050),
                Vector2(220,1680),Vector2(40,1260),Vector2(-90,820),
                Vector2(-150,340),Vector2(-210,-180),Vector2(-50,-720),
                Vector2(160,-1320),Vector2(380,-1900),Vector2(610,-2520),
                Vector2(1220,-3180),Vector2(1000,-3400),Vector2(900,-3600),
            ],6),
        },
        {
            "name":"Rimewater Tributary","width":30.0,"source_width":26.0,"mouth_width":32.0,
            "base_lift":4.8,
            "source_kind":"glacial outflow","source_landmark":"Rimewater Glacier",
            "termination":"Crownfall River confluence","tributary_of":"Crownfall River",
            "points":_catmull_rom_points([
                Vector2(180,3600),Vector2(220,3440),Vector2(300,3230),
                Vector2(365,3020),Vector2(430,2810),Vector2(430,2630),
            ],6),
        },
    ]
    profile["road_corridors"]=[
        {
            "name":"Northbound Realmway","route_class":"major",
            "purpose":"continuous north-south road through the frontier pass",
            "destinations":["Highfield","Pinewatch","Frostmere","Greyfen"],
            "width":18.0,"terrain_width":235.0,"terrain_relief":4.0,
            "points":[
                Vector2(360,-3600),Vector2(250,-3390),Vector2(100,-3140),
                Vector2(-120,-2830),Vector2(-300,-2480),Vector2(-470,-2120),
                Vector2(-250,-1710),Vector2(10,-1250),Vector2(220,-820),
                Vector2(500,-430),Vector2(760,-140),Vector2(980,120),
            ],
        },
        {
            "name":"Greyfen Road","route_class":"secondary",
            "purpose":"moor road from Frostmere to Greyfen","destinations":["Frostmere","Greyfen"],
            "width":14.0,"terrain_width":175.0,"terrain_relief":3.0,
            "points":[Vector2(980,120),Vector2(620,430),Vector2(180,750),Vector2(-280,1050),Vector2(-760,1360),Vector2(-1320,1760)],
        },
        {
            "name":"White Crown Road","route_class":"secondary",
            "purpose":"high road from Frostmere through the northern ruin to the glacial pass","destinations":["Frostmere","The White Crown","Icewatch Hold"],
            "width":13.0,"terrain_width":180.0,"terrain_relief":3.8,
            "points":[
                Vector2(980,120),Vector2(1120,620),Vector2(1050,1080),
                Vector2(840,1510),Vector2(610,1940),Vector2(420,2480),
                Vector2(300,2840),Vector2(100,3180),Vector2(-220,3440),Vector2(-520,3600),
            ],
        },
        {
            "name":"Greyfen Highland Road","route_class":"secondary",
            "purpose":"engineered moor road from Greyfen into the Stormbreak Highlands",
            "destinations":["Greyfen","Stormbreak Hold"],
            "width":13.0,"terrain_width":182.0,"terrain_relief":3.4,"grade_limit":.095,
            "points":[
                Vector2(-1320,1760),Vector2(-1880,1630),Vector2(-2440,1510),
                Vector2(-3020,1410),Vector2(-3600,1320),
            ],
        },
    ]
    profile["ford_sites"]=[{
        "name":"Frontier Crownfall Bridge","position":Vector2(81.7,-1103.2),
        "radius":54.0,"standalone":true,"bridge_width":11.5,"bank_guard":true,
        "purpose":"the Northbound Realmway crossing of the Crownfall River",
    }]
    profile["trail_corridors"]=[
        {"name":"Crownfall Footpath","route_class":"local","purpose":"waterfall overlook access","width":5.5,"engineered_grade":true,"points":[Vector2(610,1940),Vector2(760,2110),Vector2(670,2280),Vector2(520,2390)]},
        {"name":"Greyfen Pool Track","route_class":"local","purpose":"local fishing access","width":5.0,"engineered_grade":true,"points":[Vector2(-1320,1760),Vector2(-1510,1880),Vector2(-1760,2020)]},
    ]
    _mirror_authored_zone_z(profile)


func _author_glacial_range(profile:Dictionary)->void:
    profile["zone_id"]="glacial_range"
    profile["zone_name"]="Crownfall Glacial Range"
    profile["biome_id"]="glacial_alpine"
    profile["climate"]="subarctic glacial highland"
    profile["danger_tier"]=4
    profile["recommended_level"]=[14,26]
    profile["difficulty_multiplier"]=2.15
    profile["snow_line"]=55.0
    profile["snow_strength"]=0.92
    profile["population_scale"]=0.15
    profile["streamed_population"]=true
    profile["streamed_heightmap_collision"]=true
    profile["region_origin"]=Vector2(0,-14400)
    # Positive local Z is this region's southern edge. The shared key makes
    # both independently cached heightfields meet vertex-for-vertex.
    profile["seam_edges"]=[{
        "edge":"north","key":"glacial_pass","blend_width":620.0,
        "base_height":28.0,"junction_key":"stormbreak_glacial_junction",
        "junction_along":-3600.0,"junction_height":26.0,"junction_blend":680.0,
    },{
        "edge":"west","key":"skeld_rimepass","blend_width":620.0,
        "base_height":34.0,"junction_key":"stormbreak_glacial_junction",
        "junction_along":-10800.0,"junction_height":26.0,"junction_blend":680.0,
    }]
    profile["zone_exits"]=[
        {"edge":"south","target":"north_frontier","entry":"north","seamless":true},
        {"edge":"west","target":"skeld_coast","entry":"east","seamless":true},
    ]
    profile["spawn_site"]={
        "name":"Icewatch Hold","position":Vector2(-360,-2100),"radius":176.0,
        "ground_height":36.0,"ground_inner_ratio":.82,"starter":false,
        "architecture_set":"icewatch_hold",
        "role":"fortified glacial-pass refuge and expedition base",
        "siting_reason":"a wind-sheltered rock shelf above the Rimewater floodplain",
        "connections":["The White Crown","Rimegate"],
    }
    profile["town_sites"]=[{
        "name":"Rimegate","position":Vector2(560,520),"radius":152.0,
        "ground_height":44.0,"ground_inner_ratio":.80,
        "architecture_set":"rimegate_lodge",
        "role":"ice-road mining and survey settlement",
        "siting_reason":"the only broad moraine terrace between the glacier walls",
        "connections":["Icewatch Hold","Frozen Observatory"],
    }]
    profile["camp_sites"]=[
        {"name":"South Moraine Camp","position":Vector2(-120,-2980),"radius":44.0},
        {"name":"Frostline Refuge Camp","position":Vector2(-455,-1370),"radius":40.0},
        {"name":"Observatory Survey Camp","position":Vector2(-730,1560),"radius":38.0},
        {"name":"Last Light Expedition","position":Vector2(-140,2430),"radius":42.0},
    ]
    profile["map_sites"]=[
        {
            "name":"Icewatch Signal Tower","kind":"watchtower","position":Vector2(-510,-2010),
            "radius":18.0,"elevation_lift":10.0,"elevation_inner":42.0,
            "elevation_radius":180.0,"elevation_role":"southern glacial-pass beacon",
        },
        {
            "name":"Frozen Observatory","kind":"ruin","position":Vector2(-1050,1880),
            "radius":40.0,"elevation_lift":18.0,"elevation_inner":62.0,
            "elevation_radius":260.0,"elevation_role":"high western navigation landmark",
        },
        {
            "name":"Rimewater Glacier","kind":"glacier","position":Vector2(850,3070),
            "radius":170.0,"elevation_role":"visible source of the Rimewater watershed",
        },
        {
            "name":"The Blue Maw","kind":"crevasse","position":Vector2(1760,2050),
            "radius":88.0,"elevation_role":"dangerous eastern ice-field landmark",
        },
        {
            "name":"Frostline Refuge","kind":"waystation","position":Vector2(-435,-1340),
            "radius":24.0,"elevation_role":"shelter on the exposed Icebound Realmway",
        },
        {
            "name":"Last Light Expedition","kind":"camp","position":Vector2(-140,2430),
            "radius":24.0,"elevation_role":"final staffed shelter below Rimefall",
        },
        {
            "name":"Lower Rime Burrow","kind":"lair","position":Vector2(1260,-180),
            "radius":18.0,"elevation_role":"crawler colony off the lower ice road",
        },
        {
            "name":"Blue Maw Brood Ground","kind":"lair","position":Vector2(1460,1850),
            "radius":20.0,"elevation_role":"high crawler colony beside the Blue Maw track",
        },
    ]
    profile["landmark_sites"]=[
        {"name":"Icewatch Windbreak","kind":"grove","species":"pine","position":Vector2(-760,-2280),"radius":74.0,"count":18},
        {"name":"Rimegate Moraine","kind":"outcrop","position":Vector2(840,720),"radius":72.0,"count":18,"rotation":.34},
        {"name":"Observatory Teeth","kind":"outcrop","position":Vector2(-1200,1720),"radius":62.0,"count":16,"rotation":.18},
        {"name":"Frozen Observatory Structure","kind":"frozen_observatory","position":Vector2(-1050,1880),"radius":34.0,"scale":1.45,"rotation":.16},
        {"name":"Glacier Sentinel","kind":"waystone","position":Vector2(310,2730),"radius":10.0,"rotation":.08},
        {"name":"Rimewater Glacier Terminus","kind":"glacier_terminus","position":Vector2(850,3147),"radius":180.0,"scale":1.85,"rotation":.25},
        {"name":"Crown Ice Needles","kind":"ice_spire","position":Vector2(1360,2360),"radius":20.0,"scale":1.55,"rotation":-.18},
        {"name":"Observatory Ice Needle","kind":"ice_spire","position":Vector2(-690,2220),"radius":16.0,"scale":1.20,"rotation":.31},
        {"name":"Rimegate Terminal Moraine","kind":"moraine_cluster","position":Vector2(1040,1050),"radius":18.0,"scale":1.35,"rotation":.48},
        {"name":"South Moraine Stones","kind":"moraine_cluster","position":Vector2(410,-2710),"radius":16.0,"scale":1.08,"rotation":-.22},
        {"name":"Icewatch Deadfall","kind":"frozen_deadfall","position":Vector2(-920,-1940),"radius":10.0,"scale":1.08,"rotation":.44},
        {"name":"Lower Rime Deadfall","kind":"frozen_deadfall","position":Vector2(1190,-720),"radius":10.0,"scale":.94,"rotation":-1.04},
        {"name":"Frostline Refuge Structure","kind":"frostline_refuge","position":Vector2(-435,-1340),"radius":22.0,"scale":1.0,"rotation":.04},
        {"name":"Observatory Survey Shelter","kind":"survey_shelter","position":Vector2(-692,1520),"radius":14.0,"scale":1.05,"rotation":-.16},
        {"name":"Last Light Shelter","kind":"survey_shelter","position":Vector2(-115,2400),"radius":14.0,"scale":1.08,"rotation":.18},
        {"name":"Lower Rimecrawler Nest","kind":"rimecrawler_nest","position":Vector2(1260,-180),"radius":18.0,"scale":1.18,"rotation":.30},
        {"name":"Blue Maw Brood Ground","kind":"rimecrawler_nest","position":Vector2(1460,1850),"radius":20.0,"scale":1.34,"rotation":-.18},
    ]
    profile["ecology_sites"]=[
        {"name":"Icewatch Juniper","kind":"bracken","position":Vector2(-720,-1950),"radius":190.0,"count":90},
        {"name":"Rimegate Lichen","kind":"bracken","position":Vector2(760,430),"radius":160.0,"count":72},
    ]
    profile["encounter_sites"]=[
        {"name":"Moraine Troll","position":Vector2(780,-980),"enemy":"frost_troll","count":2,"radius":66.0,"rank":5},
        {"name":"Lower Rimecrawler Burrow","position":Vector2(1260,-180),"enemy":"rimecrawler","count":3,"radius":58.0,"rank":5},
        {"name":"Observatory Dead","position":Vector2(-1320,1680),"enemy":"gravebound","count":5,"radius":72.0,"rank":5},
        {"name":"Blue Maw Crawler Colony","position":Vector2(1460,1850),"enemy":"rimecrawler","count":4,"radius":72.0,"rank":6},
        {"name":"Blue Maw Trolls","position":Vector2(1650,2100),"enemy":"frost_troll","count":3,"radius":82.0,"rank":6},
        {"name":"Glacier Wraiths","position":Vector2(610,2760),"enemy":"bramble_wraith","count":4,"radius":76.0,"rank":6},
    ]
    profile["wildlife_sites"]=[
        {"name":"Icewatch Deer Shelf","position":Vector2(-1040,-2360),"species":"deer","count":5,"radius":390.0},
        {"name":"Rimegate Hares","position":Vector2(980,480),"species":"hare","count":9,"radius":340.0},
        {"name":"Observatory Grouse","position":Vector2(-1180,1510),"species":"grouse","count":7,"radius":320.0},
    ]
    profile["secret_sites"]=[
        {"name":"Cartographer's Ice Vault","position":Vector2(-980,2110),"kind":"hidden_cache","loot_table":"glacial_relics"},
        {"name":"Rimefall Emergency Cache","position":Vector2(430,2700),"kind":"hidden_cache","loot_table":"glacial_supplies"},
        {"name":"Troll King's Tribute","position":Vector2(1880,2230),"kind":"hidden_cache","loot_table":"blue_maw_hoard"},
    ]
    profile["lore_sites"]=[
        {"name":"Icewatch Expedition Ledger","position":Vector2(-310,-2040),"kind":"book","entry":"icewatch_ledger"},
        {"name":"Frostline Warden Notes","position":Vector2(-432,-1332),"kind":"book","entry":"frostline_notes"},
        {"name":"Last Survey of the Crown","position":Vector2(-1010,1840),"kind":"inscription","entry":"last_glacial_survey"},
        {"name":"Last Light Survey Order","position":Vector2(-130,2410),"kind":"book","entry":"last_light_order"},
    ]
    profile["field_boundaries"]=[]
    profile["forest_regions"]=[
        {"name":"Icewatch Black Pines","center":Vector2(-900,-2260),"radius":680.0,"density":.58},
        {"name":"Lower Rime Pines","center":Vector2(1210,-420),"radius":600.0,"density":.43},
    ]
    profile["mountain_chains"]=[
        {"name":"Western Ice Wall","center":Vector2(-2250,-450),"angle":1.50,"length":6100.0,"width":720.0,"height":245.0,"snow_line":50.0},
        {"name":"Eastern Ice Wall","center":Vector2(2240,-200),"angle":1.48,"length":6250.0,"width":760.0,"height":265.0,"snow_line":48.0},
        {"name":"Crown Glacier","center":Vector2(780,2890),"angle":.14,"length":2200.0,"width":980.0,"height":295.0,"snow_line":28.0},
        {"name":"Observatory Ridge","center":Vector2(-1260,1920),"angle":.42,"length":1750.0,"width":590.0,"height":190.0,"snow_line":34.0},
    ]
    profile["ocean_basins"]=[]
    profile["flat_regions"]=[]
    profile["landform_regions"]=[
        {"name":"Southern Moraine Pass","kind":"valley","center":Vector2(-120,-2700),"length":2000.0,"width":650.0,"angle":1.48,"amplitude":24.0},
        {"name":"Icewatch Shelf","kind":"upland","center":Vector2(-360,-2050),"radius":760.0,"aspect":.70,"angle":.10,"amplitude":15.0},
        {"name":"Rimewater Valley","kind":"valley","center":Vector2(340,350),"length":4300.0,"width":740.0,"angle":1.52,"amplitude":32.0},
        {"name":"Rimegate Moraine","kind":"rolling","center":Vector2(580,520),"radius":1080.0,"aspect":.72,"angle":-.20,"amplitude":19.0,"wavelength":390.0},
        {"name":"Glacier Bowl","kind":"basin","center":Vector2(760,2700),"radius":1100.0,"aspect":.78,"angle":.12,"amplitude":26.0},
    ]
    profile["terrain_palette_regions"]=[
        {"name":"South Tundra","center":Vector2(-220,-2450),"radius":1250.0,"aspect":.72,"angle":.08,"strength":.40,"color":[.25,.30,.25],"secondary_color":[.36,.36,.29],"cover_color":[.24,.34,.25],"cover_count":230},
        {"name":"Rimegate Heather","center":Vector2(520,320),"radius":1350.0,"aspect":.75,"angle":-.16,"strength":.38,"color":[.25,.29,.27],"secondary_color":[.36,.34,.29],"cover_color":[.30,.34,.31],"cover_count":210},
        {"name":"Observatory Scree","center":Vector2(-1240,1780),"radius":1150.0,"aspect":.68,"angle":.34,"strength":.48,"color":[.39,.41,.41],"secondary_color":[.26,.29,.30],"cover_color":[.31,.34,.33],"cover_count":130},
        {"name":"Crown Icefield","center":Vector2(760,2780),"radius":1350.0,"aspect":.72,"angle":.10,"strength":.58,"color":[.65,.71,.73],"secondary_color":[.42,.49,.51],"cover_color":[.54,.61,.62],"cover_count":85},
        {"name":"Glacier Forefield","center":Vector2(850,3060),"radius":720.0,"aspect":.72,"angle":.12,"strength":.86,"color":[.58,.65,.66],"secondary_color":[.38,.44,.45],"cover_color":[.48,.53,.53],"cover_count":54},
    ]
    profile["pond_sites"]=[]
    profile["waterfall_sites"]=[
        {"name":"Rimefall","position":Vector2(720,2680),"width":18.0,"drop":7.5},
    ]
    profile["river_corridors"]=[{
        "name":"Rimewater River","width":30.0,"source_width":12.0,"mouth_width":26.0,
        "base_lift":4.8,
        "source_kind":"glacier runoff","source_landmark":"Rimewater Glacier","termination":"Rimewater Tributary and Crownfall River",
        "points":_catmull_rom_points([
            Vector2(850,3070),Vector2(760,2780),Vector2(650,2460),
            Vector2(480,2060),Vector2(310,1600),Vector2(230,1120),
            Vector2(420,690),Vector2(500,300),Vector2(330,-120),
            Vector2(130,-620),Vector2(60,-1120),Vector2(170,-1650),
            Vector2(260,-2220),Vector2(220,-2820),Vector2(180,-3300),Vector2(180,-3600),
        ],6),
    }]
    profile["road_corridors"]=[
        {
            "name":"Icebound Realmway","route_class":"major",
            "purpose":"continuous engineered pass between the White Crown and Icewatch",
            "destinations":["The White Crown","Icewatch Hold","Rimegate","Frozen Observatory"],
            "width":17.0,"terrain_width":230.0,"terrain_relief":4.0,
            "points":[
                Vector2(-520,-3600),Vector2(-430,-3290),Vector2(-290,-2940),
                Vector2(-240,-2550),Vector2(-360,-2100),Vector2(-470,-1640),
                Vector2(-360,-1180),Vector2(-150,-690),Vector2(120,-220),
                Vector2(500,300),Vector2(560,520),
            ],
        },
        {
            "name":"Observatory Road","route_class":"secondary",
            "purpose":"sheltered switchback from Rimegate to the western observatory",
            "destinations":["Rimegate","Frozen Observatory"],
            "width":12.0,"terrain_width":175.0,"terrain_relief":3.5,
            "points":[
                Vector2(560,520),Vector2(290,820),Vector2(-40,1050),
                Vector2(-350,1250),Vector2(-620,1470),Vector2(-810,1710),Vector2(-1050,1880),
            ],
        },
        {
            "name":"Glacier Survey Road","route_class":"secondary",
            "purpose":"high expedition route from Rimegate toward the glacier overlook",
            "destinations":["Rimegate","Rimewater Glacier"],
            "width":11.0,"terrain_width":165.0,"terrain_relief":3.6,
            "points":[
                Vector2(560,520),Vector2(500,300),Vector2(420,690),
                Vector2(360,1120),Vector2(260,1510),Vector2(120,1890),
                Vector2(-40,2220),Vector2(-140,2430),
            ],
        },
        {
            "name":"Skeld Ice Road","route_class":"major",
            "purpose":"engineered westbound route from Icewatch to the Skeld Coast",
            "destinations":["Icewatch Hold","Rimegate","Vardholm","Frostharbor"],
            "width":15.0,"terrain_width":215.0,"terrain_relief":4.0,"grade_limit":.078,
            "points":[
                Vector2(-360,-2100),Vector2(-760,-1880),Vector2(-1180,-1620),
                Vector2(-1640,-1420),Vector2(-2140,-1240),Vector2(-2640,-1100),
                Vector2(-3140,-980),Vector2(-3600,-900),
            ],
        },
    ]
    profile["ford_sites"]=[{
        "name":"Rimegate Bridge","position":Vector2(500,300),
        "radius":48.0,"standalone":true,"bridge_width":10.5,"bank_guard":true,
        "purpose":"the Icebound Realmway crossing of the Rimewater River",
    }]
    profile["trail_corridors"]=[
        {"name":"Glacier Footpath","route_class":"local","purpose":"safe final approach to the Rimefall overlook","width":5.0,"engineered_grade":true,"points":[Vector2(-140,2430),Vector2(90,2540),Vector2(360,2660),Vector2(650,2780)]},
        {"name":"Blue Maw Track","route_class":"local","purpose":"dangerous hunter route to the eastern crevasse","width":4.8,"engineered_grade":true,"points":[Vector2(560,520),Vector2(900,870),Vector2(1210,1260),Vector2(1450,1650),Vector2(1760,2050)]},
    ]
    _mirror_authored_zone_z(profile)


func _author_western_reaches(profile:Dictionary)->void:
    profile["zone_id"]="western_reaches"
    profile["zone_name"]="Western Reaches"
    profile["biome_id"]="rainy_woodland"
    profile["climate"]="cool maritime"
    profile["danger_tier"]=2
    profile["recommended_level"]=[6,15]
    profile["difficulty_multiplier"]=1.30
    profile["snow_line"]=10000.0
    profile["snow_strength"]=0.0
    profile["population_scale"]=0.20
    profile["streamed_population"]=true
    profile["streamed_heightmap_collision"]=true
    profile["region_origin"]=Vector2(-7200,0)
    profile["seam_edges"]=[{
        "edge":"east","key":"western_reaches_pass","blend_width":620.0,
        "base_height":15.0,"junction_key":"riverwatch_northwest_junction",
        "junction_along":-3600.0,"junction_height":18.5,"junction_blend":680.0,
    },{
        "edge":"south","key":"stormbreak_galehorn_pass","blend_width":620.0,
        "base_height":23.0,"junction_key":"riverwatch_northwest_junction",
        "junction_along":-3600.0,"junction_height":18.5,"junction_blend":680.0,
    }]
    profile["zone_exits"]=[
        {"edge":"east","target":"starting_realm","entry":"west","seamless":true},
        {"edge":"north","target":"stormbreak_highlands","entry":"south","seamless":true},
    ]
    profile["spawn_site"]={
        "name":"Oakrest","position":Vector2(2450,-180),"radius":166.0,
        "ground_height":20.0,"ground_inner_ratio":.82,"starter":false,
        "architecture_set":"rainward_timber",
        "role":"eastern timber market and gate to the rain country",
        "siting_reason":"a dry gravel shelf above the Rainfall floodplain where the realmway leaves the pass",
        "connections":["Westmere","Rainhaven","Galehorn Watch"],
    }
    profile["town_sites"]=[
        {
            "name":"Rainhaven","position":Vector2(-1080,380),"radius":182.0,
            "ground_height":18.0,"ground_inner_ratio":.82,
            "architecture_set":"rainward_timber",
            "role":"river-port market and western road ward",
            "siting_reason":"a broad alluvial terrace above the north bank, safely outside the seasonal channel",
            "connections":["Oakrest","Rainveil Falls","Mossglass Wood"],
        },
        {
            "name":"Stonecross","position":Vector2(1600,1500),"radius":146.0,
            "ground_height":23.0,"ground_inner_ratio":.80,
            "architecture_set":"rainward_stone",
            "role":"quarry village and southern upland junction",
            "siting_reason":"firm high ground where the quarry track reaches the gentler southern downs",
            "connections":["Oakrest","Warden's Span"],
        },
    ]
    profile["camp_sites"]=[
        {"name":"Reachwarden Camp","position":Vector2(3180,-330),"radius":44.0},
        {"name":"Rainveil Camp","position":Vector2(-1430,1120),"radius":42.0},
        {"name":"Galehorn Survey Camp","position":Vector2(2670,-1760),"radius":40.0},
    ]
    profile["map_sites"]=[
        {
            "name":"Galehorn Watch","kind":"watchtower","position":Vector2(2720,-2200),
            "radius":24.0,"elevation_lift":17.0,"elevation_inner":52.0,
            "elevation_radius":240.0,"elevation_role":"western skyline landmark visible from Oakrest",
        },
        {
            "name":"Rainward Waystation","kind":"waystation","position":Vector2(3180,-330),
            "radius":46.0,"ground_height":17.0,"usable_ground":true,
        },
        {
            "name":"Rainveil Falls","kind":"waterfall","position":Vector2(-1160,800),
            "radius":34.0,"elevation_role":"the Rainfall River's descent toward the western lowlands",
        },
        {
            "name":"Old Rainward Abbey","kind":"ruin","position":Vector2(-2350,-720),
            "radius":42.0,"elevation_lift":8.0,"elevation_inner":54.0,
            "elevation_radius":210.0,"elevation_role":"ruined abbey overlooking Mossglass Wood",
        },
        {
            "name":"Galehorn Gate","kind":"river_landmark","position":Vector2(2240,-2810),
            "radius":26.0,"elevation_role":"the upper river entering the rain country below Galehorn Ridge",
        },
    ]
    profile["landmark_sites"]=[
        {"name":"Oakrest Gate Grove","kind":"grove","species":"oak","position":Vector2(2840,-520),"radius":78.0,"count":22},
        {"name":"Mossglass Ancient Oaks","kind":"grove","species":"oak","position":Vector2(-2100,-1420),"radius":96.0,"count":28},
        {"name":"Rainhaven Alder Stand","kind":"grove","species":"birch","position":Vector2(-1450,70),"radius":72.0,"count":20},
        {"name":"Galehorn Teeth","kind":"outcrop","position":Vector2(2480,-2460),"radius":70.0,"count":18,"rotation":.20},
        {"name":"Stonecross Quarry Face","kind":"outcrop","position":Vector2(1940,1860),"radius":68.0,"count":17,"rotation":.46},
        {"name":"Rainveil Standing Stones","kind":"outcrop","position":Vector2(-1480,940),"radius":44.0,"count":10,"rotation":.22},
        {"name":"Western Realm Waystone","kind":"waystone","position":Vector2(3340,-365),"radius":10.0,"rotation":-.10},
        {"name":"Abbey Pilgrim Cairn","kind":"cairn","position":Vector2(-2140,-540),"radius":8.0,"scale":1.12,"rotation":.28},
        {"name":"Galehorn Watch Structure","kind":"galehorn_watch","position":Vector2(2720,-2200),"radius":28.0,"scale":1.12,"rotation":.08},
        {"name":"Rainward Waystation Structure","kind":"rainward_waystation","position":Vector2(3180,-330),"radius":20.0,"scale":1.0,"rotation":-.12},
        {"name":"Old Rainward Abbey Structure","kind":"rainward_abbey","position":Vector2(-2350,-720),"radius":42.0,"scale":1.10,"rotation":.18},
    ]
    profile["ecology_sites"]=[
        {"name":"Oakrest Fern Verge","kind":"bracken","position":Vector2(2240,-420),"radius":230.0,"count":180},
        {"name":"Rainhaven Reedbanks","kind":"bracken","position":Vector2(-720,850),"radius":220.0,"count":165},
        {"name":"Mossglass Fern Floor","kind":"bracken","position":Vector2(-2080,-1260),"radius":260.0,"count":210},
        {"name":"Stonecross Heather","kind":"bracken","position":Vector2(1720,1700),"radius":190.0,"count":135},
    ]
    profile["encounter_sites"]=[
        {"name":"Rainward Ashfang Pack","position":Vector2(2820,260),"enemy":"ashfang","count":4,"radius":58.0,"rank":2},
        {"name":"Mossglass Wraithwood","position":Vector2(-1940,-1230),"enemy":"bramble_wraith","count":5,"radius":70.0,"rank":3},
        {"name":"Rainveil Grave Patrol","position":Vector2(-1580,1180),"enemy":"gravebound","count":5,"radius":64.0,"rank":3},
        {"name":"Galehorn Imp Lookouts","position":Vector2(2860,-2010),"enemy":"imp","count":5,"radius":56.0,"rank":3},
        {"name":"Stonecross Ashfang Den","position":Vector2(2200,2050),"enemy":"ashfang","count":5,"radius":66.0,"rank":3},
    ]
    profile["wildlife_sites"]=[
        {"name":"Oakrest Deer Wood","position":Vector2(1960,-640),"species":"deer","count":7,"radius":430.0},
        {"name":"Rainhaven Hare Meadows","position":Vector2(-650,120),"species":"hare","count":10,"radius":360.0},
        {"name":"Mossglass Grouse Cover","position":Vector2(-2150,-1180),"species":"grouse","count":9,"radius":350.0},
        {"name":"Stonecross Deer Range","position":Vector2(2150,1510),"species":"deer","count":6,"radius":390.0},
    ]
    profile["secret_sites"]=[
        {"name":"Abbot's Flooded Reliquary","position":Vector2(-2470,-850),"kind":"hidden_cache","loot_table":"rainward_relics"},
        {"name":"Galehorn Signal Cache","position":Vector2(2810,-2290),"kind":"hidden_cache","loot_table":"warden_supplies"},
        {"name":"Rainveil Smuggler Hollow","position":Vector2(-1660,790),"kind":"hidden_cache","loot_table":"rainhaven_trade"},
    ]
    profile["lore_sites"]=[
        {"name":"Oakrest Road Ledger","position":Vector2(2405,-150),"kind":"book","entry":"oakrest_ledger"},
        {"name":"The Bell beneath Rain","position":Vector2(-2320,-690),"kind":"inscription","entry":"rainward_abbey"},
        {"name":"Galehorn Warden's Log","position":Vector2(2710,-2170),"kind":"book","entry":"galehorn_watch"},
    ]
    profile["field_boundaries"]=[]
    profile["forest_regions"]=[
        {"name":"Oakrest Wood","center":Vector2(2250,-520),"radius":900.0,"density":.80},
        {"name":"Mossglass Wood","center":Vector2(-2050,-1150),"radius":1080.0,"density":.92},
        {"name":"Rainhaven Alders","center":Vector2(-1150,350),"radius":720.0,"density":.73},
        {"name":"Stonecross Coppice","center":Vector2(2050,1580),"radius":730.0,"density":.66},
        {"name":"Galehorn Pines","center":Vector2(2640,-2420),"radius":760.0,"density":.70},
    ]
    profile["mountain_chains"]=[
        {"name":"Galehorn Ridge","center":Vector2(1500,-2860),"angle":.03,"length":3800.0,"width":760.0,"height":172.0,"snow_line":10000.0},
        {"name":"Stormbreak Escarpment","center":Vector2(-2850,-950),"angle":1.22,"length":2500.0,"width":660.0,"height":118.0,"snow_line":10000.0},
        {"name":"Stonecross Downs","center":Vector2(1900,2600),"angle":.18,"length":2400.0,"width":720.0,"height":112.0,"snow_line":10000.0},
    ]
    profile["ocean_basins"]=[]
    profile["flat_regions"]=[]
    profile["landform_regions"]=[
        {"name":"Rainward Pass","kind":"valley","center":Vector2(2860,-360),"length":1650.0,"width":620.0,"angle":.05,"amplitude":20.0},
        {"name":"Oakrest Shelf","kind":"upland","center":Vector2(2380,-180),"radius":880.0,"aspect":.70,"angle":-.08,"amplitude":14.0},
        {"name":"Rainfall Vale","kind":"valley","center":Vector2(-350,520),"length":5200.0,"width":740.0,"angle":.08,"amplitude":30.0},
        {"name":"Mossglass Folds","kind":"rolling","center":Vector2(-1880,-930),"radius":1320.0,"aspect":.76,"angle":.40,"amplitude":18.0,"wavelength":410.0},
        {"name":"Stonecross Uplands","kind":"rolling","center":Vector2(1650,1650),"radius":1220.0,"aspect":.72,"angle":-.22,"amplitude":16.0,"wavelength":460.0},
        {"name":"Galehorn Approach","kind":"ridge","center":Vector2(2700,-1850),"length":1700.0,"width":480.0,"angle":1.48,"amplitude":28.0},
    ]
    profile["terrain_palette_regions"]=[
        {"name":"Rainward Verges","center":Vector2(2740,-300),"radius":1250.0,"aspect":.72,"angle":.04,"strength":.34,"color":[.19,.30,.18],"secondary_color":[.31,.32,.19],"cover_color":[.16,.34,.17],"cover_count":390},
        {"name":"Mossglass Floor","center":Vector2(-1950,-1050),"radius":1500.0,"aspect":.78,"angle":.34,"strength":.46,"color":[.12,.22,.15],"secondary_color":[.24,.27,.18],"cover_color":[.12,.29,.15],"cover_count":460},
        {"name":"Rainfall Alluvium","center":Vector2(-380,650),"radius":1550.0,"aspect":.42,"angle":.08,"strength":.42,"color":[.22,.27,.16],"secondary_color":[.33,.29,.18],"cover_color":[.20,.31,.17],"cover_count":360},
        {"name":"Stonecross Heather","center":Vector2(1700,1750),"radius":1320.0,"aspect":.74,"angle":-.18,"strength":.40,"color":[.27,.27,.16],"secondary_color":[.18,.25,.17],"cover_color":[.35,.30,.16],"cover_count":350},
        {"name":"Galehorn Stone","center":Vector2(2500,-2600),"radius":1180.0,"aspect":.66,"angle":.02,"strength":.48,"color":[.33,.35,.32],"secondary_color":[.20,.26,.22],"cover_color":[.24,.30,.23],"cover_count":250},
    ]
    profile["pond_sites"]=[
        {"name":"Mossglass Tarn","position":Vector2(-2380,-1680),"radius":132.0,"water_height":3.1},
        {"name":"Stonecross Quarry Pool","position":Vector2(2160,1940),"radius":86.0,"water_height":4.0},
    ]
    profile["waterfall_sites"]=[
        {"name":"Rainveil Falls","position":Vector2(-1160,800),"width":30.0,"drop":3.8},
    ]
    profile["river_corridors"]=[{
        "name":"Rainfall River","width":34.0,"source_width":30.0,"mouth_width":38.0,
        "source_height":14.0,"mouth_height":1.1,
        "source_kind":"highland outflow","source_landmark":"Galehorn Run",
        "termination":"the storm coast beyond the western boundary",
        "points":_catmull_rom_points([
            Vector2(2240,-3600),Vector2(2210,-3300),Vector2(2240,-2810),
            Vector2(2100,-2500),Vector2(1950,-2200),
            Vector2(1800,-1820),Vector2(1640,-1430),Vector2(1490,-1050),
            Vector2(1370,-680),Vector2(1250,-300),Vector2(1120,-40),
            Vector2(860,260),Vector2(520,420),Vector2(140,520),
            Vector2(-260,610),Vector2(-680,690),Vector2(-1040,760),
            Vector2(-1160,800),Vector2(-1340,840),Vector2(-1750,900),
            Vector2(-2180,1020),Vector2(-2600,1190),Vector2(-3060,1390),
            Vector2(-3400,1500),Vector2(-3600,1540),
        ],6),
    }]
    profile["road_corridors"]=[
        {
            "name":"Rainward Realmway","route_class":"major",
            "purpose":"continuous westbound road from Westmere through Oakrest to Rainhaven",
            "destinations":["Westmere","Oakrest","Warden's Span","Rainhaven"],
            "width":17.0,"terrain_width":230.0,"terrain_relief":4.0,"grade_limit":.065,
            "points":[
                Vector2(3600,-400),Vector2(3320,-360),Vector2(3050,-300),
                Vector2(2760,-230),Vector2(2450,-180),Vector2(2150,-120),
                Vector2(1800,-50),Vector2(1540,60),Vector2(1380,100),
                Vector2(1120,-40),Vector2(860,-180),Vector2(620,-120),
                Vector2(340,80),Vector2(70,260),Vector2(-320,420),
                Vector2(-720,470),Vector2(-1080,380),
            ],
        },
        {
            "name":"Stonecross Road","route_class":"secondary",
            "purpose":"graded quarry road from the realmway bridge to Stonecross",
            "destinations":["Warden's Span","Stonecross"],
            "width":13.0,"terrain_width":178.0,"terrain_relief":3.2,"grade_limit":.10,
            "points":[
                Vector2(1540,60),Vector2(1640,320),Vector2(1710,590),
                Vector2(1730,880),Vector2(1710,1180),Vector2(1600,1500),
            ],
        },
        {
            "name":"Galehorn Watchroad","route_class":"secondary",
            "purpose":"switchback watch road from Oakrest to the ridge beacon",
            "destinations":["Oakrest","Galehorn Watch"],
            "width":12.0,"terrain_width":175.0,"terrain_relief":3.5,"grade_limit":.10,
            "points":[
                Vector2(2450,-180),Vector2(2680,-520),Vector2(2840,-900),
                Vector2(2900,-1280),Vector2(2840,-1640),Vector2(2760,-1940),
                Vector2(2720,-2200),Vector2(2700,-2750),Vector2(2720,-3200),Vector2(2720,-3600),
            ],
        },
        {
            "name":"Mossglass Timber Road","route_class":"secondary",
            "purpose":"working woodland road from Rainhaven to Mossglass Wood",
            "destinations":["Rainhaven","Old Rainward Abbey","Mossglass Wood"],
            "width":11.5,"terrain_width":165.0,"terrain_relief":3.0,"grade_limit":.11,
            "points":[
                Vector2(-1080,380),Vector2(-1260,170),Vector2(-1450,-30),
                Vector2(-1660,-180),Vector2(-1880,-420),Vector2(-2140,-540),Vector2(-2350,-720),
            ],
        },
    ]
    profile["ford_sites"]=[{
        "name":"Warden's Span","position":Vector2(1120,-40),
        "radius":50.0,"standalone":false,"bridge_width":11.0,"bank_guard":true,
        "purpose":"the Rainward Realmway's necessary crossing of the Rainfall River",
    }]
    profile["trail_corridors"]=[
        {"name":"Rainveil Footpath","route_class":"local","purpose":"walkable riverbank approach to Rainveil Falls","width":5.2,"engineered_grade":true,"points":[Vector2(-1080,380),Vector2(-1210,570),Vector2(-1320,760),Vector2(-1430,900),Vector2(-1430,1120)]},
        {"name":"Mossglass Tarn Track","route_class":"local","purpose":"angler and forester access to Mossglass Tarn","width":4.8,"engineered_grade":true,"points":[Vector2(-2140,-540),Vector2(-2220,-900),Vector2(-2300,-1280),Vector2(-2380,-1680)]},
        {"name":"Quarry Shelf Path","route_class":"local","purpose":"short working path from Stonecross to the quarry pool","width":4.6,"engineered_grade":true,"points":[Vector2(1600,1500),Vector2(1840,1690),Vector2(2160,1940)]},
    ]


func _author_stormbreak_highlands(profile:Dictionary)->void:
    profile["zone_id"]="stormbreak_highlands"
    profile["zone_name"]="Stormbreak Highlands"
    profile["biome_id"]="windswept_highlands"
    profile["climate"]="cold maritime upland"
    profile["danger_tier"]=3
    profile["recommended_level"]=[12,22]
    profile["difficulty_multiplier"]=1.72
    profile["snow_line"]=138.0
    profile["snow_strength"]=0.52
    profile["population_scale"]=0.30
    profile["streamed_population"]=true
    profile["streamed_heightmap_collision"]=true
    profile["region_origin"]=Vector2(-7200,-7200)
    profile["seam_edges"]=[
        {
            "edge":"north","key":"stormbreak_galehorn_pass","blend_width":620.0,
            "base_height":23.0,"junction_key":"riverwatch_northwest_junction",
            "junction_along":-3600.0,"junction_height":18.5,"junction_blend":680.0,
        },
        {
            "edge":"east","key":"stormbreak_greyfen_pass","blend_width":620.0,
            "base_height":22.0,"junction_key":"riverwatch_northwest_junction",
            "junction_along":-3600.0,"junction_height":18.5,"junction_blend":680.0,
            "junctions":[{"key":"stormbreak_glacial_junction","along":-10800.0,"height":26.0,"blend":680.0}],
        },
        {
            "edge":"south","key":"skeld_stormpass","blend_width":620.0,
            "base_height":29.0,"junction_key":"stormbreak_glacial_junction",
            "junction_along":-3600.0,"junction_height":26.0,"junction_blend":680.0,
        },
    ]
    profile["zone_exits"]=[
        {"edge":"south","target":"western_reaches","entry":"north","seamless":true},
        {"edge":"east","target":"north_frontier","entry":"west","seamless":true},
        {"edge":"north","target":"skeld_coast","entry":"south","seamless":true},
    ]
    profile["spawn_site"]={
        "name":"Stormbreak Hold","position":Vector2(-220,-340),"radius":176.0,
        "ground_height":31.0,"ground_inner_ratio":.82,"starter":false,
        "architecture_set":"stormbreak_highland",
        "role":"highland road ward and refuge above Galehorn Run",
        "siting_reason":"a broad rock shelf west of the only reliable crossing between Greyfen and the rain country",
        "connections":["Cairnstead","Moorwatch","Greyfen"],
    }
    profile["town_sites"]=[
        {
            "name":"Cairnstead","position":Vector2(2470,2200),"radius":154.0,
            "ground_height":26.0,"ground_inner_ratio":.80,
            "architecture_set":"stormbreak_highland",
            "role":"southern drovers' town and gate to Galehorn Ridge",
            "siting_reason":"a sheltered shoulder above the river where the high road begins its descent into Oakrest country",
            "connections":["Stormbreak Hold","Galehorn Watch"],
        },
        {
            "name":"Moorwatch","position":Vector2(-2070,1040),"radius":138.0,
            "ground_height":38.0,"ground_inner_ratio":.79,
            "architecture_set":"stormbreak_highland",
            "role":"western peat and shepherd settlement",
            "siting_reason":"firm high ground between the flooded moor and the Stormscar escarpment",
            "connections":["Stormbreak Hold","Stormscar Beacon"],
        },
    ]
    profile["camp_sites"]=[
        {"name":"Greyfen Road Shelter","position":Vector2(2920,-1010),"radius":44.0},
        {"name":"Galehorn Drover Camp","position":Vector2(2660,3030),"radius":42.0},
        {"name":"Blacktarn Survey Camp","position":Vector2(-930,-2260),"radius":40.0},
    ]
    profile["map_sites"]=[
        {
            "name":"Stormscar Beacon","kind":"watchtower","position":Vector2(-2480,-1170),
            "radius":28.0,"elevation_lift":18.0,"elevation_inner":56.0,
            "elevation_radius":250.0,"elevation_role":"a fire beacon visible from every major highland road",
        },
        {
            "name":"Blacktarn Headwater","kind":"headwater","position":Vector2(-1320,-2920),
            "radius":28.0,"elevation_role":"snow and rain runoff feeding Galehorn Run",
        },
        {
            "name":"Galehorn Crossing","kind":"bridge","position":Vector2(780,-300),
            "radius":48.0,
        },
        {
            "name":"Blacktarn Runoff Bridge","kind":"bridge","position":Vector2(-1200,-2800),
            "radius":34.0,
        },
        {
            "name":"The Shattered Choir","kind":"ruin","position":Vector2(-2860,2030),
            "radius":38.0,"elevation_lift":10.0,"elevation_inner":48.0,
            "elevation_radius":205.0,"elevation_role":"a broken stone sanctuary above the western moor",
        },
    ]
    profile["landmark_sites"]=[
        {"name":"Stormscar Beacon Structure","kind":"stormbreak_beacon","position":Vector2(-2480,-1170),"radius":30.0,"scale":1.12,"rotation":.20},
        {"name":"Greyfen Pass Shelter","kind":"stormbreak_shelter","position":Vector2(2920,-1010),"radius":24.0,"scale":1.0,"rotation":-.18},
        {"name":"Shattered Choir Structure","kind":"stormbreak_ruin","position":Vector2(-2860,2030),"radius":40.0,"scale":1.08,"rotation":.34},
        {"name":"Blacktarn Moraine","kind":"moraine_cluster","position":Vector2(-1160,-2700),"radius":62.0,"scale":1.04,"rotation":.26},
        {"name":"Stormbreak Standing Teeth","kind":"outcrop","position":Vector2(-1710,-820),"radius":76.0,"count":19,"rotation":.38},
        {"name":"Cairnstead Windbreak","kind":"outcrop","position":Vector2(2760,1920),"radius":54.0,"count":13,"rotation":-.22},
        {"name":"Galehorn Run Tor","kind":"outcrop","position":Vector2(1260,820),"radius":58.0,"count":14,"rotation":.18},
        {"name":"High Road Slate Ribs","kind":"outcrop","position":Vector2(1540,-1060),"radius":62.0,"count":15,"rotation":-.34},
        {"name":"Moorwatch Western Tor","kind":"outcrop","position":Vector2(-2920,260),"radius":68.0,"count":17,"rotation":.42},
        {"name":"Blacktarn Erratics","kind":"outcrop","position":Vector2(-430,-2380),"radius":66.0,"count":16,"rotation":-.18},
        {"name":"Cairnstead Roadstones","kind":"outcrop","position":Vector2(930,2580),"radius":52.0,"count":12,"rotation":.31},
        {"name":"Greyfen Shoulder Stones","kind":"outcrop","position":Vector2(3100,-280),"radius":56.0,"count":14,"rotation":-.08},
        {"name":"Stormscar Deadfall","kind":"frozen_deadfall","position":Vector2(-2050,-1640),"radius":12.0,"scale":.94,"rotation":.66},
        {"name":"Blacktarn Deadfall","kind":"frozen_deadfall","position":Vector2(-720,-2650),"radius":12.0,"scale":.90,"rotation":-.41},
        {"name":"Moorwatch Rowan Ring","kind":"grove","species":"birch","position":Vector2(-2290,1230),"radius":72.0,"count":20},
        {"name":"High Road Pine Gate","kind":"grove","species":"pine","position":Vector2(2250,-720),"radius":76.0,"count":22},
        {"name":"Galehorn Birch Hollow","kind":"grove","species":"birch","position":Vector2(1470,1560),"radius":70.0,"count":18},
        {"name":"Highland Realm Waystone","kind":"waystone","position":Vector2(3330,-1240),"radius":10.0,"rotation":.08},
        {"name":"Drover Cairn","kind":"cairn","position":Vector2(2540,2740),"radius":8.0,"scale":1.08,"rotation":.18},
    ]
    profile["ecology_sites"]=[
        {"name":"Stormbreak Heather","kind":"bracken","position":Vector2(-470,420),"radius":280.0,"count":210},
        {"name":"Moorwatch Rushes","kind":"bracken","position":Vector2(-1950,1320),"radius":235.0,"count":175},
        {"name":"Cairnstead Gorse","kind":"bracken","position":Vector2(2360,1960),"radius":220.0,"count":160},
        {"name":"Greyfen Pass Ferns","kind":"bracken","position":Vector2(2860,-920),"radius":190.0,"count":130},
        {"name":"Hold Shelf Heather","kind":"bracken","position":Vector2(-620,-620),"radius":250.0,"count":185},
        {"name":"Galehorn Run Rushes","kind":"bracken","position":Vector2(820,220),"radius":240.0,"count":170},
        {"name":"Stormscar Bilberry","kind":"bracken","position":Vector2(-1830,-1380),"radius":225.0,"count":150},
        {"name":"Choir Moor Heather","kind":"bracken","position":Vector2(-2730,1840),"radius":220.0,"count":145},
    ]
    profile["encounter_sites"]=[
        {"name":"Stormscar Ashfangs","position":Vector2(-2240,-1380),"enemy":"ashfang","count":6,"radius":70.0,"rank":4},
        {"name":"Choir Gravebound","position":Vector2(-2750,1910),"enemy":"gravebound","count":6,"radius":72.0,"rank":4},
        {"name":"Blacktarn Frost Trolls","position":Vector2(-880,-2520),"enemy":"frost_troll","count":2,"radius":76.0,"rank":5},
        {"name":"Galehorn Wraithwood","position":Vector2(1710,1420),"enemy":"bramble_wraith","count":6,"radius":74.0,"rank":4},
        {"name":"Greyfen Pass Imps","position":Vector2(2700,-1260),"enemy":"imp","count":6,"radius":64.0,"rank":4},
    ]
    profile["wildlife_sites"]=[
        {"name":"Moorwatch Red Deer","position":Vector2(-1660,900),"species":"deer","count":8,"radius":470.0},
        {"name":"Cairnstead Hares","position":Vector2(2220,2360),"species":"hare","count":10,"radius":370.0},
        {"name":"Stormscar Grouse","position":Vector2(-2180,-760),"species":"grouse","count":10,"radius":390.0},
    ]
    profile["secret_sites"]=[
        {"name":"Beacon Keeper's Strongbox","position":Vector2(-2520,-1110),"kind":"hidden_cache","loot_table":"stormbreak_beacon"},
        {"name":"Choir Undercrypt Cache","position":Vector2(-2920,2090),"kind":"hidden_cache","loot_table":"stormbreak_relics"},
        {"name":"Blacktarn Survey Pack","position":Vector2(-980,-2300),"kind":"hidden_cache","loot_table":"stormbreak_supplies"},
    ]
    profile["lore_sites"]=[
        {"name":"The Stormward Compact","position":Vector2(-180,-310),"kind":"book","entry":"stormward_compact"},
        {"name":"Last Hymn of the Choir","position":Vector2(-2820,1990),"kind":"inscription","entry":"shattered_choir"},
        {"name":"Blacktarn Survey Notes","position":Vector2(-940,-2240),"kind":"book","entry":"blacktarn_notes"},
    ]
    profile["field_boundaries"]=[]
    profile["forest_regions"]=[
        {"name":"Stormbreak Hold Shelterwood","center":Vector2(-520,-520),"radius":720.0,"density":.58},
        {"name":"Greyfen Pass Pines","center":Vector2(2860,-980),"radius":780.0,"density":.68},
        {"name":"Moorwatch Rowan Wood","center":Vector2(-1950,980),"radius":820.0,"density":.65},
        {"name":"Galehorn Upper Wood","center":Vector2(2080,2180),"radius":900.0,"density":.72},
        {"name":"Blacktarn Scrub","center":Vector2(-850,-2340),"radius":690.0,"density":.50},
        {"name":"Choir Windwood","center":Vector2(-2780,2050),"radius":660.0,"density":.54},
    ]
    profile["mountain_chains"]=[
        {"name":"Stormscar Range","center":Vector2(-2260,-2240),"angle":.30,"length":3400.0,"width":820.0,"height":218.0,"snow_line":132.0},
        {"name":"Blacktarn Headwall","center":Vector2(-500,-3040),"angle":-.10,"length":2100.0,"width":650.0,"height":176.0,"snow_line":128.0},
        {"name":"Galehorn Northern Ridge","center":Vector2(2450,2900),"angle":.08,"length":2500.0,"width":720.0,"height":156.0,"snow_line":148.0},
        {"name":"Greyfen Shoulder","center":Vector2(3080,-1530),"angle":1.25,"length":1700.0,"width":580.0,"height":122.0,"snow_line":152.0},
    ]
    profile["ocean_basins"]=[]
    profile["flat_regions"]=[]
    profile["landform_regions"]=[
        {"name":"Stormbreak Saddle","kind":"valley","center":Vector2(2050,-850),"length":3300.0,"width":690.0,"angle":.02,"amplitude":28.0},
        {"name":"Galehorn Run Vale","kind":"valley","center":Vector2(820,500),"length":6000.0,"width":760.0,"angle":1.05,"amplitude":34.0},
        {"name":"Stormbreak Hold Shelf","kind":"upland","center":Vector2(-220,-340),"radius":940.0,"aspect":.74,"angle":.12,"amplitude":18.0},
        {"name":"Moorwatch Folds","kind":"rolling","center":Vector2(-2050,1080),"radius":1260.0,"aspect":.72,"angle":.35,"amplitude":22.0,"wavelength":430.0},
        {"name":"Cairnstead Shoulder","kind":"rolling","center":Vector2(2440,2160),"radius":1180.0,"aspect":.70,"angle":-.18,"amplitude":18.0,"wavelength":470.0},
    ]
    profile["terrain_palette_regions"]=[
        {"name":"Stormbreak Heather Moor","center":Vector2(-1300,650),"radius":1750.0,"aspect":.78,"angle":.22,"strength":.46,"color":[.24,.27,.18],"secondary_color":[.31,.27,.20],"cover_color":[.33,.29,.17],"cover_count":430},
        {"name":"Stormscar Slate","center":Vector2(-2100,-2100),"radius":1580.0,"aspect":.66,"angle":.28,"strength":.52,"color":[.32,.34,.34],"secondary_color":[.22,.27,.26],"cover_color":[.29,.31,.28],"cover_count":300},
        {"name":"Galehorn Run Grass","center":Vector2(1050,760),"radius":1700.0,"aspect":.42,"angle":1.06,"strength":.40,"color":[.17,.29,.19],"secondary_color":[.29,.31,.18],"cover_color":[.18,.33,.19],"cover_count":390},
        {"name":"Greyfen Pass Moss","center":Vector2(2820,-980),"radius":1280.0,"aspect":.72,"angle":-.10,"strength":.39,"color":[.16,.27,.20],"secondary_color":[.24,.30,.19],"cover_color":[.15,.31,.19],"cover_count":330},
        {"name":"Cairnstead Ochre","center":Vector2(2420,2180),"radius":1250.0,"aspect":.72,"angle":-.16,"strength":.38,"color":[.28,.29,.18],"secondary_color":[.36,.31,.19],"cover_color":[.26,.32,.18],"cover_count":330},
    ]
    profile["pond_sites"]=[
        {"name":"Blacktarn","position":Vector2(-1320,-2920),"radius":152.0,"water_height":29.75},
        {"name":"Moorwatch Mere","position":Vector2(-2480,1460),"radius":104.0,"water_height":7.4},
    ]
    profile["waterfall_sites"]=[
        {"name":"Blacktarn Runoff","position":Vector2(-1130,-2710),"width":28.0,"drop":4.2},
    ]
    profile["river_corridors"]=[{
        "name":"Galehorn Run","width":30.0,"source_width":18.0,"mouth_width":30.0,
        "source_height":27.0,"mouth_height":17.8,
        "source_kind":"tarn and snow runoff","source_landmark":"Blacktarn Headwater",
        "termination":"Rainfall River in the Western Reaches",
        "points":_catmull_rom_points([
            Vector2(-1320,-2920),Vector2(-1130,-2710),Vector2(-850,-2380),
            Vector2(-430,-2020),Vector2(-20,-1600),Vector2(330,-1160),
            Vector2(600,-720),Vector2(780,-300),Vector2(980,170),
            Vector2(1220,700),Vector2(1480,1260),Vector2(1740,1840),
            Vector2(1980,2420),Vector2(2140,3000),Vector2(2240,3600),
        ],6),
    }]
    profile["road_corridors"]=[
        {
            "name":"Stormbreak High Road","route_class":"major",
            "purpose":"continuous high road between the rain country and Stormbreak Hold",
            "destinations":["Galehorn Watch","Cairnstead","Galehorn Crossing","Stormbreak Hold"],
            "width":16.0,"terrain_width":220.0,"terrain_relief":4.0,"grade_limit":.075,
            "points":[
                Vector2(2720,3600),Vector2(2660,3030),Vector2(2540,2580),
                Vector2(2470,2200),Vector2(2320,1640),Vector2(2100,980),
                Vector2(1680,250),Vector2(1320,-530),Vector2(780,-300),
                Vector2(300,-90),Vector2(-220,-340),
            ],
        },
        {
            "name":"Greyfen Highland Road","route_class":"major",
            "purpose":"wind-sheltered road from Stormbreak Hold to the Greyfen frontier",
            "destinations":["Stormbreak Hold","Galehorn Crossing","Greyfen"],
            "width":15.0,"terrain_width":210.0,"terrain_relief":3.8,"grade_limit":.078,
            "points":[
                Vector2(-220,-340),Vector2(300,-90),Vector2(780,-300),
                Vector2(1320,-530),Vector2(1880,-650),Vector2(2440,-850),
                Vector2(3020,-1100),Vector2(3600,-1320),
            ],
        },
        {
            "name":"Moorwatch Road","route_class":"secondary",
            "purpose":"graded local road from the hold to the western shepherd country",
            "destinations":["Stormbreak Hold","Moorwatch","The Shattered Choir"],
            "width":12.0,"terrain_width":176.0,"terrain_relief":3.3,"grade_limit":.095,
            "points":[
                Vector2(-220,-340),Vector2(-650,-120),Vector2(-1040,180),
                Vector2(-1420,520),Vector2(-1740,820),Vector2(-2070,1040),
                Vector2(-2450,1450),Vector2(-2860,2030),
            ],
        },
        {
            "name":"Skeld Pass Road","route_class":"secondary",
            "purpose":"weather-sheltered ascent from Stormbreak Hold to the subarctic coast",
            "destinations":["Stormbreak Hold","Blacktarn","Frostharbor"],
            "width":13.0,"terrain_width":190.0,"terrain_relief":3.8,"grade_limit":.085,
            "points":[
                Vector2(-220,-340),Vector2(-520,-760),Vector2(-780,-1220),
                Vector2(-1010,-1720),Vector2(-1130,-2240),Vector2(-1200,-2800),
                Vector2(-1200,-3240),Vector2(-1200,-3600),
            ],
        },
    ]
    profile["ford_sites"]=[{
        "name":"Galehorn Crossing","position":Vector2(780,-300),
        "radius":50.0,"standalone":false,"bridge_width":11.5,"bank_guard":true,
        "purpose":"the main reliable high-road crossing of Galehorn Run",
    },{
        "name":"Blacktarn Runoff Bridge","position":Vector2(-1200,-2800),
        "radius":36.0,"standalone":false,"bridge_width":8.5,"bank_guard":true,
        "purpose":"a narrow upper crossing carrying Skeld Pass Road over the tarn runoff",
    }]
    profile["trail_corridors"]=[
        {"name":"Blacktarn Climb","route_class":"local","purpose":"survey path from Stormbreak Hold to the river source","width":5.2,"engineered_grade":true,"points":[Vector2(-220,-340),Vector2(-480,-820),Vector2(-650,-1340),Vector2(-790,-1840),Vector2(-930,-2260),Vector2(-1130,-2710)]},
        {"name":"Stormscar Beacon Path","route_class":"local","purpose":"warden path from Moorwatch Road to the beacon","width":4.9,"engineered_grade":true,"points":[Vector2(-1420,520),Vector2(-1680,90),Vector2(-1950,-350),Vector2(-2220,-760),Vector2(-2480,-1170)]},
        {"name":"Moorwatch Mere Track","route_class":"local","purpose":"angler and peat-cutter access to Moorwatch Mere","width":4.6,"engineered_grade":true,"points":[Vector2(-2070,1040),Vector2(-2240,1220),Vector2(-2480,1460)]},
    ]


func _author_skeld_coast(profile:Dictionary)->void:
    profile["zone_id"]="skeld_coast"
    profile["zone_name"]="Skeld Coast"
    profile["biome_id"]="subarctic_coast"
    profile["climate"]="subarctic maritime"
    profile["danger_tier"]=5
    profile["recommended_level"]=[22,34]
    profile["difficulty_multiplier"]=2.42
    profile["snow_line"]=82.0
    profile["snow_strength"]=0.76
    profile["population_scale"]=0.22
    profile["streamed_population"]=true
    profile["streamed_heightmap_collision"]=true
    profile["region_origin"]=Vector2(-7200,-14400)
    profile["seam_edges"]=[
        {
            "edge":"north","key":"skeld_stormpass","blend_width":620.0,
            "base_height":29.0,"junction_key":"stormbreak_glacial_junction",
            "junction_along":-3600.0,"junction_height":26.0,"junction_blend":680.0,
        },
        {
            "edge":"east","key":"skeld_rimepass","blend_width":620.0,
            "base_height":34.0,"junction_key":"stormbreak_glacial_junction",
            "junction_along":-10800.0,"junction_height":26.0,"junction_blend":680.0,
        },
    ]
    profile["zone_exits"]=[
        {"edge":"south","target":"stormbreak_highlands","entry":"north","seamless":true},
        {"edge":"east","target":"glacial_range","entry":"west","seamless":true},
    ]
    profile["spawn_site"]={
        "name":"Frostharbor","position":Vector2(-720,420),"radius":190.0,
        "ground_height":12.5,"ground_inner_ratio":.82,"starter":false,
        "architecture_set":"skeld_coast",
        "role":"ice-free harbor, fishing market, and western expedition port",
        "siting_reason":"a sheltered gravel terrace behind a hooked natural bay where the Skeld River meets the sea",
        "connections":["Stormbreak Hold","Vardholm","Cape Keld"],
    }
    profile["town_sites"]=[
        {
            "name":"Vardholm","position":Vector2(1650,-2300),"radius":160.0,
            "ground_height":39.0,"ground_inner_ratio":.80,"architecture_set":"skeld_coast",
            "role":"fortified ice-road town guarding the Rimepass",
            "siting_reason":"a defensible moraine shelf between the coast road and the glacial western wall",
            "connections":["Frostharbor","Icewatch Hold","Rimeglass Tarn"],
        },
        {
            "name":"Kelpwick","position":Vector2(-520,2280),"radius":142.0,
            "ground_height":16.0,"ground_inner_ratio":.80,"architecture_set":"skeld_coast",
            "role":"southern fishing village and gate to Stormbreak",
            "siting_reason":"firm raised beach above the southern cove and the only gentle route into the highlands",
            "connections":["Frostharbor","Stormbreak Hold"],
        },
    ]
    profile["camp_sites"]=[
        {"name":"Rimepass Road Shelter","position":Vector2(3020,820),"radius":42.0},
        {"name":"Cape Keld Lightkeeper Camp","position":Vector2(-1520,-2250),"radius":40.0},
        {"name":"South Cove Net Camp","position":Vector2(-980,2940),"radius":38.0},
    ]
    profile["map_sites"]=[
        {"name":"Cape Keld Light","kind":"lighthouse","position":Vector2(-1510,-2310),"radius":32.0,"elevation_lift":14.0,"elevation_inner":52.0,"elevation_radius":220.0,"elevation_role":"a working sea light visible from the harbor and northern headland"},
        {"name":"Frostharbor Docks","kind":"dock","position":Vector2(-1280,500),"radius":48.0,"elevation_role":"the first working ocean harbor"},
        {"name":"Rimeglass Headwater","kind":"headwater","position":Vector2(2420,-2470),"radius":26.0,"elevation_role":"snow and glacier runoff feeding the Skeld River"},
        {"name":"Skeldmouth","kind":"river_landmark","position":Vector2(-1390,1010),"radius":28.0,"elevation_role":"the tidal mouth where the Skeld River reaches the ocean"},
        {"name":"Whalebone Chapel","kind":"ruin","position":Vector2(-1850,1740),"radius":38.0,"elevation_lift":8.0,"elevation_inner":45.0,"elevation_radius":185.0,"elevation_role":"a wind-cut coastal sanctuary above the southern bay"},
    ]
    profile["landmark_sites"]=[
        {"name":"Cape Keld Lighthouse Structure","kind":"skeld_lighthouse","position":Vector2(-1510,-2310),"radius":34.0,"scale":1.18,"rotation":.18},
        {"name":"Frostharbor Pier","kind":"skeld_dock","position":Vector2(-1280,500),"radius":58.0,"scale":1.08,"rotation":1.55},
        {"name":"Frostharbor Tide Cutter","kind":"skeld_boat","position":Vector2(-1405,565),"radius":22.0,"scale":1.02,"rotation":1.28},
        {"name":"Kelpwick Netter","kind":"skeld_boat","position":Vector2(-1425,2320),"radius":20.0,"scale":.88,"rotation":1.72},
        {"name":"Whalebone Chapel Structure","kind":"skeld_chapel","position":Vector2(-1850,1740),"radius":40.0,"scale":1.10,"rotation":.30},
        {"name":"Frostharbor Tide Hall","kind":"skeld_longhouse","position":Vector2(-500,650),"radius":34.0,"scale":1.08,"rotation":.04},
        {"name":"Vardholm Warden Hall","kind":"skeld_longhouse","position":Vector2(1810,-2150),"radius":32.0,"scale":1.0,"rotation":-.16},
        {"name":"Kelpwick Net Hall","kind":"skeld_longhouse","position":Vector2(-320,2460),"radius":31.0,"scale":.94,"rotation":.08},
        {"name":"Vardholm Gate Stones","kind":"outcrop","position":Vector2(1980,-2110),"radius":62.0,"count":15,"rotation":-.25},
        {"name":"Rimeglass Moraine","kind":"moraine_cluster","position":Vector2(2210,-2250),"radius":72.0,"scale":1.18,"rotation":.22},
        {"name":"Skeldmouth Sea Stacks","kind":"outcrop","position":Vector2(-1710,980),"radius":88.0,"count":22,"rotation":.42},
        {"name":"North Headland Ribs","kind":"outcrop","position":Vector2(-1180,-2860),"radius":78.0,"count":19,"rotation":-.18},
        {"name":"Cape Keld Wind Stones","kind":"outcrop","position":Vector2(-1260,-2180),"radius":118.0,"count":28,"rotation":.16},
        {"name":"Whalebone Shore Stones","kind":"outcrop","position":Vector2(-1660,1580),"radius":112.0,"count":24,"rotation":-.22},
        {"name":"Kelpwick Windbreak","kind":"grove","species":"pine","position":Vector2(-120,2470),"radius":78.0,"count":21},
        {"name":"Vardholm Black Pines","kind":"grove","species":"pine","position":Vector2(1240,-2480),"radius":82.0,"count":24},
        {"name":"Cape Keld Krummholz","kind":"grove","species":"pine","position":Vector2(-1010,-2070),"radius":155.0,"count":32},
        {"name":"Chapel Saltwood","kind":"grove","species":"birch","position":Vector2(-1530,1550),"radius":145.0,"count":28},
        {"name":"Skeld Coastal Waystone","kind":"waystone","position":Vector2(3220,900),"radius":10.0,"rotation":.12},
        {"name":"South Cove Cairn","kind":"cairn","position":Vector2(-1020,2860),"radius":8.0,"scale":1.12,"rotation":-.18},
    ]
    profile["ecology_sites"]=[
        {"name":"Frostharbor Dune Grass","kind":"bracken","position":Vector2(-680,680),"radius":255.0,"count":185},
        {"name":"Vardholm Crowberry","kind":"bracken","position":Vector2(1480,-2180),"radius":230.0,"count":160},
        {"name":"Kelpwick Sea Heather","kind":"bracken","position":Vector2(-470,2150),"radius":240.0,"count":175},
        {"name":"Rimeglass Lichen","kind":"bracken","position":Vector2(2160,-2260),"radius":210.0,"count":140},
    ]
    profile["encounter_sites"]=[
        {"name":"Cape Frost Trolls","position":Vector2(-1050,-2640),"enemy":"frost_troll","count":3,"radius":82.0,"rank":7},
        {"name":"Rimepass Crawlers","position":Vector2(2740,520),"enemy":"rimecrawler","count":5,"radius":74.0,"rank":7},
        {"name":"Whalebone Dead","position":Vector2(-1880,1680),"enemy":"gravebound","count":7,"radius":78.0,"rank":7},
        {"name":"Skeldmouth Ashfangs","position":Vector2(-1180,1250),"enemy":"ashfang","count":7,"radius":72.0,"rank":6},
        {"name":"Rimeglass Wraiths","position":Vector2(2050,-2030),"enemy":"bramble_wraith","count":6,"radius":80.0,"rank":7},
    ]
    profile["wildlife_sites"]=[
        {"name":"Kelpwick Red Deer","position":Vector2(180,2130),"species":"deer","count":7,"radius":430.0},
        {"name":"Vardholm Snow Hares","position":Vector2(1300,-2630),"species":"hare","count":11,"radius":390.0},
        {"name":"Cape Keld Grouse","position":Vector2(-900,-2050),"species":"grouse","count":10,"radius":380.0},
    ]
    profile["secret_sites"]=[
        {"name":"Lightkeeper's Storm Chest","position":Vector2(-1550,-2260),"kind":"hidden_cache","loot_table":"skeld_lighthouse"},
        {"name":"Whalebone Reliquary","position":Vector2(-1910,1785),"kind":"hidden_cache","loot_table":"skeld_relics"},
        {"name":"Rimeglass Survey Cache","position":Vector2(2280,-2300),"kind":"hidden_cache","loot_table":"skeld_supplies"},
    ]
    profile["lore_sites"]=[
        {"name":"Frostharbor Tide Ledger","position":Vector2(-700,390),"kind":"book","entry":"frostharbor_tides"},
        {"name":"The Last Light of Keld","position":Vector2(-1480,-2280),"kind":"inscription","entry":"cape_keld_light"},
        {"name":"Whalebone Canticle","position":Vector2(-1810,1710),"kind":"book","entry":"whalebone_canticle"},
    ]
    profile["field_boundaries"]=[]
    profile["forest_regions"]=[
        {"name":"Vardholm Blackwood","center":Vector2(1320,-2540),"radius":820.0,"density":.72},
        {"name":"Kelpwick Shelterwood","center":Vector2(60,2250),"radius":820.0,"density":.66},
        {"name":"Rimepass Pines","center":Vector2(2840,760),"radius":740.0,"density":.60},
        {"name":"Cape Keld Windwood","center":Vector2(-780,-2140),"radius":760.0,"density":.52},
        {"name":"Skeld River Birches","center":Vector2(420,-140),"radius":860.0,"density":.62},
    ]
    profile["mountain_chains"]=[
        {"name":"Western Rimewall","center":Vector2(2920,-1550),"angle":1.48,"length":4300.0,"width":820.0,"height":236.0,"snow_line":72.0},
        {"name":"Cape Keld Headland","center":Vector2(-650,-2860),"angle":.10,"length":2300.0,"width":680.0,"height":158.0,"snow_line":86.0},
        {"name":"South Skeld Heights","center":Vector2(1200,2870),"angle":.02,"length":2700.0,"width":720.0,"height":142.0,"snow_line":98.0},
    ]
    profile["ocean_basins"]=[{
        "name":"The Grey Sea","kind":"coast","edge":"west","water_height":-.60,
        "shelf_width":520.0,"land_blend":210.0,"depth":34.0,
        "coast_points":_monotonic_coast_points([
            Vector2(-1680,-3600),Vector2(-1550,-3000),Vector2(-1900,-2400),
            Vector2(-1750,-1700),Vector2(-1400,-950),Vector2(-1100,-200),
            Vector2(-1280,500),Vector2(-1390,1010),Vector2(-2100,1700),
            Vector2(-1260,2350),Vector2(-1510,3000),Vector2(-3600,3600),
        ],8),
    }]
    profile["flat_regions"]=[]
    profile["landform_regions"]=[
        {"name":"Frostharbor Terrace","kind":"upland","center":Vector2(-650,430),"radius":980.0,"aspect":.66,"angle":.08,"amplitude":13.0},
        {"name":"Skeld River Vale","kind":"valley","center":Vector2(480,-620),"length":4700.0,"width":760.0,"angle":.70,"amplitude":32.0},
        {"name":"Vardholm Moraine Folds","kind":"rolling","center":Vector2(1600,-2320),"radius":1280.0,"aspect":.72,"angle":-.28,"amplitude":20.0,"wavelength":420.0},
        {"name":"Kelpwick Raised Beaches","kind":"rolling","center":Vector2(-280,2360),"radius":1280.0,"aspect":.62,"angle":.10,"amplitude":15.0,"wavelength":510.0},
        {"name":"Rimepass Saddle","kind":"valley","center":Vector2(2860,820),"length":1700.0,"width":620.0,"angle":.05,"amplitude":24.0},
    ]
    profile["terrain_palette_regions"]=[
        {"name":"Skeld Salt Moor","center":Vector2(-360,620),"radius":1900.0,"aspect":.72,"angle":.10,"strength":.44,"color":[.20,.27,.22],"secondary_color":[.34,.33,.24],"cover_color":[.20,.31,.23],"cover_count":420},
        {"name":"Cape Keld Slate","center":Vector2(-650,-2480),"radius":1500.0,"aspect":.68,"angle":.08,"strength":.54,"color":[.34,.38,.39],"secondary_color":[.24,.29,.31],"cover_color":[.29,.33,.32],"cover_count":290},
        {"name":"Vardholm Tundra","center":Vector2(1680,-2320),"radius":1450.0,"aspect":.74,"angle":-.22,"strength":.48,"color":[.25,.31,.26],"secondary_color":[.36,.36,.29],"cover_color":[.24,.34,.27],"cover_count":360},
        {"name":"Kelpwick Heather","center":Vector2(-220,2320),"radius":1420.0,"aspect":.72,"angle":.08,"strength":.43,"color":[.24,.28,.20],"secondary_color":[.37,.31,.25],"cover_color":[.31,.32,.20],"cover_count":350},
        {"name":"Rimewall Scree","center":Vector2(2700,-1500),"radius":1450.0,"aspect":.64,"angle":1.46,"strength":.50,"color":[.37,.40,.41],"secondary_color":[.28,.33,.34],"cover_color":[.32,.35,.35],"cover_count":250},
    ]
    profile["pond_sites"]=[
        {"name":"Rimeglass Tarn","position":Vector2(2420,-2470),"radius":148.0,"water_height":32.2},
        {"name":"Sealwife Mere","position":Vector2(720,2020),"radius":106.0,"water_height":8.2},
    ]
    profile["waterfall_sites"]=[
        {"name":"Rimeglass Fall","position":Vector2(2160,-2240),"width":30.0,"drop":4.8},
    ]
    profile["river_corridors"]=[{
        "name":"Skeld River","width":36.0,"source_width":20.0,"mouth_width":42.0,
        "source_height":33.65,"mouth_height":.85,
        "source_kind":"snowmelt tarn and glacial runoff","source_landmark":"Rimeglass Headwater",
        "termination":"The Grey Sea at Skeldmouth",
        "points":_catmull_rom_points([
            Vector2(2420,-2470),Vector2(2160,-2240),Vector2(1880,-1940),
            Vector2(1560,-1600),Vector2(1270,-1250),Vector2(1030,-900),
            Vector2(820,-540),Vector2(520,-100),Vector2(300,150),
            Vector2(-40,420),Vector2(-420,650),Vector2(-720,781),Vector2(-820,820),
            Vector2(-1120,930),Vector2(-1390,1010),
        ],6),
    }]
    profile["road_corridors"]=[
        {
            "name":"Skeld Coast Road","route_class":"major",
            "purpose":"continuous coastal realmway linking Stormbreak, Frostharbor, Vardholm, and Icewatch",
            "destinations":["Stormbreak Hold","Kelpwick","Frostharbor","Vardholm","Icewatch Hold"],
            "width":16.0,"terrain_width":225.0,"terrain_relief":4.0,"grade_limit":.072,
            "points":[
                Vector2(-1200,3600),Vector2(-930,3120),Vector2(-520,2700),
                Vector2(-520,2280),Vector2(-610,1780),Vector2(-720,1280),
                Vector2(-720,820),Vector2(-720,781),Vector2(-720,420),Vector2(-420,100),
                Vector2(-40,-500),Vector2(420,-1000),Vector2(880,-1550),Vector2(1300,-2050),
                Vector2(1650,-2300),Vector2(2100,-2700),Vector2(2600,-2550),
                Vector2(2900,-1800),Vector2(3100,-900),Vector2(3220,0),Vector2(3400,600),
                Vector2(3600,900),
            ],
        },
        {
            "name":"Cape Keld Road","route_class":"secondary",
            "purpose":"headland road from Frostharbor to the working lighthouse",
            "destinations":["Frostharbor","Cape Keld Light"],
            "width":12.0,"terrain_width":178.0,"terrain_relief":3.4,"grade_limit":.095,
            "points":[
                Vector2(-720,420),Vector2(-690,-40),Vector2(-740,-520),
                Vector2(-850,-980),Vector2(-1010,-1420),Vector2(-1220,-1840),
                Vector2(-1510,-2310),
            ],
        },
        {
            "name":"Rimeglass Survey Road","route_class":"secondary",
            "purpose":"graded supply road from Vardholm to the Skeld River source",
            "destinations":["Vardholm","Rimeglass Tarn"],
            "width":11.5,"terrain_width":175.0,"terrain_relief":3.6,"grade_limit":.10,
            "points":[
                Vector2(1650,-2300),Vector2(1880,-2500),Vector2(2180,-2640),
                Vector2(2460,-2570),Vector2(2500,-2470),
            ],
        },
    ]
    profile["ford_sites"]=[{
        "name":"Skeld Bridge","position":Vector2(-720,781),
        "radius":52.0,"standalone":false,"bridge_width":11.5,"bank_guard":true,
        "purpose":"the coast road's single necessary crossing of the Skeld River",
    }]
    profile["trail_corridors"]=[
        {"name":"Harbor Shore Walk","route_class":"local","purpose":"walkable route from Frostharbor market to the docks","width":5.6,"engineered_grade":true,"points":[Vector2(-720,420),Vector2(-880,450),Vector2(-1040,480),Vector2(-1190,500)]},
        {"name":"Whalebone Pilgrim Track","route_class":"local","purpose":"coastal footpath from Kelpwick to the ruined chapel","width":4.9,"engineered_grade":true,"points":[Vector2(-520,2280),Vector2(-850,2200),Vector2(-1180,2070),Vector2(-1510,1900),Vector2(-1850,1740)]},
        {"name":"Rimeglass Fall Path","route_class":"local","purpose":"safe final foot approach to the headwater overlook","width":4.8,"engineered_grade":true,"points":[Vector2(2110,-2070),Vector2(2160,-2240),Vector2(2320,-2380),Vector2(2420,-2470)]},
    ]


func _mirror_authored_zone_z(profile:Dictionary)->void:
    var spawn:Dictionary=profile.get("spawn_site",{})
    if not spawn.is_empty():
        var point:Vector2=spawn.get("position",Vector2.ZERO)
        spawn["position"]=Vector2(point.x,-point.y)
    for key in ["town_sites","camp_sites","pond_sites","waterfall_sites","ford_sites","landmark_sites","ecology_sites","map_sites","encounter_sites","wildlife_sites","secret_sites","lore_sites"]:
        for site in profile.get(key,[]):
            var point:Vector2=site.get("position",Vector2.ZERO)
            site["position"]=Vector2(point.x,-point.y)
    for key in ["flat_regions","forest_regions","mountain_chains","ocean_basins","landform_regions","terrain_palette_regions"]:
        for region in profile.get(key,[]):
            var center:Vector2=region.get("center",Vector2.ZERO)
            region["center"]=Vector2(center.x,-center.y)
            if region.has("angle"):region["angle"]=-float(region.get("angle",0.0))
    for key in ["river_corridors","road_corridors","trail_corridors","field_boundaries"]:
        for corridor in profile.get(key,[]):
            var mirrored:Array=[]
            for point_value in corridor.get("points",[]):
                var point:Vector2=point_value
                mirrored.append(Vector2(point.x,-point.y))
            corridor["points"]=mirrored


func offset_profile(profile:Dictionary,offset:Vector2)->Dictionary:
    var shifted:Dictionary=profile.duplicate(true)
    shifted["region_origin"]=offset
    var spawn:Dictionary=shifted.get("spawn_site",{})
    if not spawn.is_empty():spawn["position"]=Vector2(spawn.get("position",Vector2.ZERO))+offset
    for key in ["town_sites","camp_sites","pond_sites","waterfall_sites","ford_sites","landmark_sites","ecology_sites","map_sites","encounter_sites","wildlife_sites","secret_sites","lore_sites"]:
        for site in shifted.get(key,[]):site["position"]=Vector2(site.get("position",Vector2.ZERO))+offset
    for key in ["flat_regions","forest_regions","mountain_chains","ocean_basins","landform_regions","terrain_palette_regions"]:
        for region in shifted.get(key,[]):
            region["center"]=Vector2(region.get("center",Vector2.ZERO))+offset
            if key=="ocean_basins" and region.has("coast_points"):
                var coast_points:Array=[]
                for coast_point in region.get("coast_points",[]):coast_points.append(Vector2(coast_point)+offset)
                region["coast_points"]=coast_points
    for key in ["river_corridors","road_corridors","trail_corridors","field_boundaries"]:
        for corridor in shifted.get(key,[]):
            var points:Array=[]
            for point in corridor.get("points",[]):points.append(Vector2(point)+offset)
            corridor["points"]=points
    return shifted


func make_world_atlas(global_profiles:Array)->Dictionary:
    if global_profiles.is_empty():return {}
    var atlas:Dictionary=global_profiles[0].duplicate(true)
    atlas["zone_id"]="broken_knight_world_atlas"
    atlas["zone_name"]="Broken Knight World Atlas"
    atlas["region_origins"]=[]
    atlas["region_summaries"]=[]
    for profile_value in global_profiles:
        atlas["region_origins"].append(profile_value.get("region_origin",Vector2.ZERO))
        atlas["region_summaries"].append({
            "zone_id":profile_value.get("zone_id","region"),
            "name":profile_value.get("zone_name","Region"),
            "origin":profile_value.get("region_origin",Vector2.ZERO),
            "biome_id":profile_value.get("biome_id","temperate"),
            "climate":profile_value.get("climate","temperate"),
            "danger_tier":profile_value.get("danger_tier",1),
            "recommended_level":profile_value.get("recommended_level",[1,8]),
            "world_size":profile_value.get("world_size",7200.0),
        })
    for key in ["town_sites","camp_sites","pond_sites","waterfall_sites","ford_sites","landmark_sites","ecology_sites","map_sites","encounter_sites","wildlife_sites","secret_sites","lore_sites","flat_regions","forest_regions","mountain_chains","ocean_basins","landform_regions","terrain_palette_regions","river_corridors","road_corridors","trail_corridors","field_boundaries"]:
        atlas[key]=[]
        for profile_value in global_profiles:
            var source:Dictionary=profile_value
            atlas[key].append_array(source.get(key,[]).duplicate(true))
    # Every streamed profile uses spawn_site as its principal gateway town.
    # Only the starter profile's spawn survives the initial dictionary copy,
    # so promote adjacent region hubs into the atlas settlement layer.
    for profile_index in range(1,global_profiles.size()):
        var regional_spawn:Dictionary=(global_profiles[profile_index] as Dictionary).get("spawn_site",{}).duplicate(true)
        if not regional_spawn.is_empty():atlas["town_sites"].append(regional_spawn)
    var minimum:=Vector2(INF,INF)
    var maximum:=Vector2(-INF,-INF)
    for profile_value in global_profiles:
        var source:Dictionary=profile_value
        var size:float=float(source.get("world_size",7200.0))
        var center:Vector2=source.get("region_origin",Vector2.ZERO)
        minimum.x=minf(minimum.x,center.x-size*.5);minimum.y=minf(minimum.y,center.y-size*.5)
        maximum.x=maxf(maximum.x,center.x+size*.5);maximum.y=maxf(maximum.y,center.y+size*.5)
    atlas["map_center"]=(minimum+maximum)*.5
    atlas["map_extent"]=maximum-minimum
    atlas["atlas_world_size"]=maxf(maximum.x-minimum.x,maximum.y-minimum.y)
    atlas["world_size"]=float(global_profiles[0].get("world_size",7200.0))
    return atlas


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
    for key in ["town_sites","camp_sites","pond_sites","waterfall_sites","ford_sites","landmark_sites","ecology_sites","map_sites","encounter_sites","wildlife_sites","secret_sites","lore_sites"]:
        for site in profile.get(key,[]):site.position=transform_point.call(site.position)
    for key in ["flat_regions","forest_regions","mountain_chains","ocean_basins","landform_regions","terrain_palette_regions"]:
        for region in profile.get(key,[]):
            region.center=transform_point.call(region.center)
            if region.has("angle"):region.angle=float(region.angle)*(-1.0 if mirror_x else 1.0)+angle
    for key in ["river_corridors","road_corridors","trail_corridors","field_boundaries"]:
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
    profile["landmark_sites"] = _normalize_sites(profile.get("landmark_sites", []))
    profile["ecology_sites"] = _normalize_sites(profile.get("ecology_sites", []))
    profile["map_sites"] = _normalize_sites(profile.get("map_sites", []))
    profile["encounter_sites"] = _normalize_sites(profile.get("encounter_sites", []))
    profile["wildlife_sites"] = _normalize_sites(profile.get("wildlife_sites", []))
    profile["secret_sites"] = _normalize_sites(profile.get("secret_sites", []))
    profile["lore_sites"] = _normalize_sites(profile.get("lore_sites", []))
    profile["flat_regions"] = _normalize_regions(profile.get("flat_regions", []))
    profile["forest_regions"] = _normalize_regions(profile.get("forest_regions", []))
    profile["mountain_chains"] = _normalize_centered_entries(profile.get("mountain_chains", []))
    profile["ocean_basins"] = _normalize_centered_entries(profile.get("ocean_basins", []))
    profile["landform_regions"] = _normalize_centered_entries(profile.get("landform_regions", []))
    profile["terrain_palette_regions"] = _normalize_centered_entries(profile.get("terrain_palette_regions", []))
    profile["river_corridors"] = _normalize_corridors(profile.get("river_corridors", []))
    for river in profile["river_corridors"]:
        # Keep the terrain query path compact. Visible water and banks add their
        # own render-only smoothing in WorldPreviewBuilder, so terrain creation
        # does not scan hundreds of extra river segments for every grid point.
        river["points"] = _catmull_rom_points(river.get("points", []), 6)
    profile["road_corridors"] = _normalize_corridors(profile.get("road_corridors", []))
    profile["trail_corridors"] = _normalize_corridors(profile.get("trail_corridors", []))
    profile["field_boundaries"] = _normalize_corridors(profile.get("field_boundaries", []))
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
    for site in profile.get("landmark_sites", []):
        _scale_site(site, scale, physical_scale)
    for site in profile.get("ecology_sites", []):
        _scale_site(site, scale, physical_scale)
    for site in profile.get("map_sites", []):
        _scale_site(site, scale, physical_scale)
    for key in ["encounter_sites","wildlife_sites","secret_sites","lore_sites"]:
        for site in profile.get(key,[]):
            _scale_site(site,scale,physical_scale)
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
        if basin.has("coast_points"):
            var scaled_coast:Array=[]
            for coast_point in basin.get("coast_points",[]):scaled_coast.append(Vector2(coast_point)*scale)
            basin["coast_points"]=scaled_coast
            basin["shelf_width"]=float(basin.get("shelf_width",520.0))*scale
            basin["land_blend"]=float(basin.get("land_blend",210.0))*scale
    for landform in profile.get("landform_regions", []):
        landform["center"] = landform.get("center", Vector2.ZERO) * scale
        landform["radius"] = float(landform.get("radius", 0.0)) * scale
        landform["length"] = float(landform.get("length", 0.0)) * scale
        landform["width"] = float(landform.get("width", 0.0)) * scale
        landform["wavelength"] = float(landform.get("wavelength", 0.0)) * scale
    for palette_region in profile.get("terrain_palette_regions", []):
        palette_region["center"] = palette_region.get("center", Vector2.ZERO) * scale
        palette_region["radius"] = float(palette_region.get("radius", 0.0)) * scale
    for corridor_key in ["river_corridors", "road_corridors", "trail_corridors", "field_boundaries"]:
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


func _monotonic_coast_points(points:Array,steps_per_segment:int)->Array:
    # A coastline is single-valued along north/south for the current west-edge
    # ocean carve. Smooth only its east/west displacement while interpolating
    # latitude linearly; a full 2D spline can briefly reverse latitude and make
    # the terrain sampler choose the wrong branch of the coast.
    if points.size()<3:return points.duplicate()
    var smoothed:Array=[]
    var last:=points.size()-1
    for index in range(last):
        var p0:=Vector2(points[maxi(0,index-1)])
        var p1:=Vector2(points[index])
        var p2:=Vector2(points[index+1])
        var p3:=Vector2(points[mini(last,index+2)])
        for step in range(steps_per_segment):
            var t:=float(step)/float(steps_per_segment)
            var t2:=t*t
            var t3:=t2*t
            var x:=.5*((2.0*p1.x)+(-p0.x+p2.x)*t+(2.0*p0.x-5.0*p1.x+4.0*p2.x-p3.x)*t2+(-p0.x+3.0*p1.x-3.0*p2.x+p3.x)*t3)
            smoothed.append(Vector2(x,lerpf(p1.y,p2.y,t)))
    smoothed.append(Vector2(points[last]))
    return smoothed


func _to_vec2(value: Variant) -> Vector2:
    if value is Vector2:
        return value
    if value is Array and value.size() >= 2:
        return Vector2(float(value[0]), float(value[1]))
    return Vector2.ZERO
