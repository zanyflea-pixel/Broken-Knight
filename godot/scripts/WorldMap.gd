extends Control

signal teleport_requested(world_point: Vector2)

var _profile: Dictionary = {}
var _player: Node3D
var _director: Node
var _terrain_texture: ImageTexture
var _terrain_height_sampler:Callable
var _terrain_heights:=PackedFloat32Array()
var _terrain_build_image:Image
var _terrain_sample_row:=-1
var _terrain_color_row:=-1
const TERRAIN_RESOLUTION:=512
var _parchment: Texture2D
var _teleport_mode := false
var _teleport_button: Button
var _full_detail:=true
var _map_label_rects:Array[Rect2]=[]
var _map_features:Array[Dictionary]=[]
var _map_cache_path:=""
var _map_cache_enabled:=true
var _terrain_background_tick:=0
var _last_draw_player_position:=Vector2(INF,INF)
var _last_draw_player_heading:=INF


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    _parchment = load("res://assets/ui/cartographer_parchment_v1.png")
    _teleport_button = Button.new()
    _teleport_button.text = "TELEPORT: OFF"
    _teleport_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _teleport_button.position = Vector2(-176, 16)
    _teleport_button.size = Vector2(160, 32)
    _teleport_button.toggle_mode = true
    _teleport_button.flat=true
    _teleport_button.add_theme_color_override("font_color",Color(.13,.085,.025))
    _teleport_button.add_theme_color_override("font_hover_color",Color(.55,.17,.05))
    _teleport_button.add_theme_color_override("font_pressed_color",Color(.72,.12,.045))
    _teleport_button.pressed.connect(_toggle_teleport_mode)
    add_child(_teleport_button)
    visibility_changed.connect(_on_visibility_changed)


func configure(profile: Dictionary, player: Node3D, director: Node = null, height_sampler: Callable = Callable()) -> void:
    _profile = profile
    _player = player
    _director = director
    if height_sampler.is_valid():
        _begin_terrain_texture_build(height_sampler)
    queue_redraw()


func _process(delta: float) -> void:
    # A missing 512px survey used to perform 4096 terrain queries every frame
    # during ordinary play. Build slowly in the background and immediately at
    # full speed only while the paused map is actually visible.
    if _terrain_sample_row>=0:
        if visible:_advance_terrain_samples(8)
        else:
            _terrain_background_tick=(_terrain_background_tick+1)%6
            if _terrain_background_tick==0:_advance_terrain_samples(1)
    elif _terrain_color_row>=0:
        _advance_terrain_colors(16 if visible else 2)
    if visible and is_instance_valid(_player):
        var player_position:=Vector2(_player.global_position.x,_player.global_position.z)
        var heading:=_player_map_heading()
        if player_position.distance_squared_to(_last_draw_player_position)>.25 or absf(angle_difference(heading,_last_draw_player_heading))>.012:
            _last_draw_player_position=player_position
            _last_draw_player_heading=heading
            queue_redraw()
    if not visible and _terrain_sample_row<0 and _terrain_color_row<0:set_process(false)


func _on_visibility_changed()->void:
    if visible:
        set_process(true)
        _last_draw_player_position=Vector2(INF,INF)
        _last_draw_player_heading=INF
        queue_redraw()


func _begin_terrain_texture_build(height_sampler:Callable)->void:
    _terrain_height_sampler=height_sampler
    set_process(true)
    _map_cache_enabled=OS.get_environment("BROKEN_KNIGHT_DISABLE_MAP_CACHE")!="1"
    var signature:=var_to_str([
        TERRAIN_RESOLUTION,_profile.get("world_size",7200.0),
        _profile.get("landform_regions",[]),_profile.get("mountain_chains",[]),
        _profile.get("terrain_palette_regions",[]),_profile.get("river_corridors",[]),
        _profile.get("forest_regions",[]),
    ]).hash()
    _map_cache_path="user://illustrated_world_v8_%s.png"%str(signature)
    if _map_cache_enabled and FileAccess.file_exists(_map_cache_path):
        var cached:=Image.new()
        if cached.load(_map_cache_path)==OK and cached.get_width()==TERRAIN_RESOLUTION:
            _terrain_texture=ImageTexture.create_from_image(cached)
            _terrain_sample_row=-1
            _terrain_color_row=-1
            return
    _terrain_heights.resize(TERRAIN_RESOLUTION*TERRAIN_RESOLUTION)
    _terrain_sample_row=0
    _terrain_color_row=-1


func _advance_terrain_samples(rows:int)->void:
    var world_size: float = _profile.get("world_size", 7200.0)
    var last_row:=mini(TERRAIN_RESOLUTION,_terrain_sample_row+rows)
    for y in range(_terrain_sample_row,last_row):
        for x in range(TERRAIN_RESOLUTION):
            var world_x:=(float(x)/float(TERRAIN_RESOLUTION-1)-.5)*world_size
            var world_z:=(float(y)/float(TERRAIN_RESOLUTION-1)-.5)*world_size
            _terrain_heights[y*TERRAIN_RESOLUTION+x]=_terrain_height_sampler.call(world_x,world_z).y
    _terrain_sample_row=last_row
    if _terrain_sample_row>=TERRAIN_RESOLUTION:
        _terrain_sample_row=-1
        _terrain_build_image=Image.create(TERRAIN_RESOLUTION,TERRAIN_RESOLUTION,false,Image.FORMAT_RGBA8)
        _terrain_color_row=0


func _advance_terrain_colors(rows:int)->void:
    var world_size:float=_profile.get("world_size",7200.0)
    var last_row:=mini(TERRAIN_RESOLUTION,_terrain_color_row+rows)
    for y in range(_terrain_color_row,last_row):
        for x in range(TERRAIN_RESOLUTION):
            var index:=y*TERRAIN_RESOLUTION+x
            var h:=_terrain_heights[index]
            var left:=_terrain_heights[y*TERRAIN_RESOLUTION+maxi(0,x-1)]
            var right:=_terrain_heights[y*TERRAIN_RESOLUTION+mini(TERRAIN_RESOLUTION-1,x+1)]
            var up:=_terrain_heights[maxi(0,y-1)*TERRAIN_RESOLUTION+x]
            var down:=_terrain_heights[mini(TERRAIN_RESOLUTION-1,y+1)*TERRAIN_RESOLUTION+x]
            # Broad north-west light makes hills read as physical land rather
            # than concentric contour rings.
            var slope_light:=(left-right)*.020+(up-down)*.017
            var slope_strength:=minf(1.0,(absf(left-right)+absf(up-down))*.055)
            var shade:=clampf(.98+slope_light-slope_strength*.08,.62,1.23)
            var world_point := Vector2(
                (float(x) / float(TERRAIN_RESOLUTION - 1) - 0.5) * world_size,
                (float(y) / float(TERRAIN_RESOLUTION - 1) - 0.5) * world_size
            )
            var color := _survey_color(h, world_point)
            var contour_step := 20.0 if h < 70.0 else 32.0
            if floorf(h / contour_step) != floorf(right / contour_step) or floorf(h / contour_step) != floorf(down / contour_step):
                shade *= 0.93
            _terrain_build_image.set_pixel(x,y,Color(color.r*shade,color.g*shade,color.b*shade,1.0))
    _terrain_color_row=last_row
    if _terrain_color_row>=TERRAIN_RESOLUTION:
        _terrain_texture=ImageTexture.create_from_image(_terrain_build_image)
        if _map_cache_enabled and not _map_cache_path.is_empty():_terrain_build_image.save_png(_map_cache_path)
        _terrain_build_image=null
        _terrain_color_row=-1
        queue_redraw()


func _survey_color(height: float, world_point: Vector2) -> Color:
    # Mirror the broad biome rules used by TerrainBuilder so the map describes
    # the ground the player actually sees instead of recoloring everything as
    # the same green elevation band.
    var world_size: float = _profile.get("world_size", 7200.0)
    var fine:=sin(world_point.x*.021)*sin(world_point.y*.017)
    var broad:=sin(world_point.x*.0031+world_point.y*.0022)*sin(world_point.y*.0043-world_point.x*.0015)
    var variation:=fine*.012+broad*.020
    var color:=Color(.36,.48,.25)
    var warp:=sin(world_point.x*.0027+world_point.y*.0019)*world_size*.038+sin(world_point.y*.0041-world_point.x*.0013)*world_size*.021
    var east:=smoothstep(world_size*.07+warp,world_size*.27+warp,world_point.x)
    var west:=1.0-smoothstep(-world_size*.31+warp,-world_size*.11+warp,world_point.x)
    var north:=smoothstep(world_size*.08-warp,world_size*.29-warp,world_point.y)
    var south:=1.0-smoothstep(-world_size*.29-warp,-world_size*.09-warp,world_point.y)
    color=color.lerp(Color(.56,.48,.24),east*.72)
    color=color.lerp(Color(.25,.40,.25),west*.66)
    color=color.lerp(Color(.27,.43,.38),north*.30)
    color=color.lerp(Color(.58,.39,.21),south*.34)
    var forest_influence:=0.0
    for forest in _profile.get("forest_regions",[]):
        var forest_center:Vector2=forest.get("center",Vector2.ZERO)
        var forest_radius:float=maxf(1.0,float(forest.get("radius",300.0)))
        forest_influence=maxf(forest_influence,1.0-smoothstep(forest_radius*.66,forest_radius*1.06,world_point.distance_to(forest_center)))
    color=color.lerp(Color(.105,.275,.17),forest_influence*.52)
    color=_apply_survey_palette(color,world_point,height)
    if height < -3.0:
        color=color.lerp(Color(.31,.40,.29),.28)
    elif height>34.0:
        color=color.lerp(Color(.43,.39,.29),clampf((height-34.0)/92.0,0.0,.68))
    if height>82.0:
        color=color.lerp(Color(.39,.38,.34),clampf((height-82.0)/70.0,0.0,.68))
    if height>145.0:
        color=color.lerp(Color(.62,.61,.56),clampf((height-145.0)/55.0,0.0,.55))
    return Color(color.r + variation, color.g + variation, color.b + variation)


func _apply_survey_palette(base:Color,point:Vector2,height:float)->Color:
    var result:=base
    var highland_protection:=1.0-smoothstep(34.0,76.0,height)
    for region in _profile.get("terrain_palette_regions",[]):
        var center:Vector2=region.get("center",Vector2.ZERO)
        var radius:float=maxf(1.0,float(region.get("radius",900.0)))
        var aspect:float=maxf(.25,float(region.get("aspect",1.0)))
        var angle:float=float(region.get("angle",0.0))
        var delta:=point-center
        var local:=Vector2(delta.x*cos(-angle)-delta.y*sin(-angle),delta.x*sin(-angle)+delta.y*cos(-angle))
        var normalized:=Vector2(local.x/radius,local.y/(radius*aspect))
        var edge_warp:=sin(point.x*.0047+point.y*.0031)*.055+sin(point.y*.009-point.x*.002)*.025
        var weight:float=(1.0-smoothstep(.58,1.04,normalized.length()+edge_warp))*float(region.get("strength",.25))*highland_protection
        if weight<=0.0:continue
        var raw:Array=region.get("color",[result.r,result.g,result.b])
        var secondary:Array=region.get("secondary_color",raw)
        if raw.size()<3:continue
        var tint:=Color(float(raw[0]),float(raw[1]),float(raw[2]))
        if secondary.size()>=3:
            var mottle:=(sin(point.x*.013+center.x*.0017)*sin(point.y*.011-center.y*.0013)+1.0)*.5
            tint=tint.lerp(Color(float(secondary[0]),float(secondary[1]),float(secondary[2])),smoothstep(.28,.78,mottle)*.58)
        result=result.lerp(tint,clampf(weight*1.18,0.0,.56))
    return result


func _draw() -> void:
    if _profile.is_empty():
        return
    var panel := _map_panel()
    var world_size: float = _profile.get("world_size", 7200.0)
    _map_label_rects=[
        Rect2(Vector2(8,6),Vector2(260,44)),
        Rect2(Vector2(panel.end.x-190,6),Vector2(182,48)),
        Rect2(Vector2(panel.end.x-112,58),Vector2(100,106)),
        Rect2(Vector2(panel.end.x-180,panel.end.y-54),Vector2(170,48)),
    ]
    _map_features=[]
    draw_rect(Rect2(Vector2.ZERO,size),Color(.10,.105,.10,1.0),true)
    draw_rect(panel,Color(.50,.46,.34),true)
    if _terrain_texture:
        draw_texture_rect(_terrain_texture,panel,false,Color(1.03,1.01,.94))
    else:
        draw_rect(panel,Color(.42,.50,.29),true)
    _draw_ground_detail(panel,world_size)
    _draw_forests(panel, world_size)
    _draw_mountains(panel, world_size)
    _draw_field_parcels(panel,world_size)
    _draw_settlement_footprints(panel, world_size)
    _draw_town_detail(panel,world_size)
    _draw_corridors(_profile.get("river_corridors", []), panel, world_size, "river")
    _draw_corridors(_profile.get("road_corridors", []), panel, world_size, "road")
    _draw_corridors(_profile.get("trail_corridors", []), panel, world_size, "trail")
    _draw_field_boundaries(panel,world_size)
    _draw_corridor_names(panel, world_size)
    _draw_bridges(panel, world_size)
    _draw_water_sites(panel, world_size)
    _draw_waterfalls(panel, world_size)
    _draw_sites(panel, world_size)
    _draw_caves(panel, world_size)
    if _full_detail:
        _draw_landmark_sites(panel,world_size)
        _draw_special_map_sites(panel,world_size)
        _draw_services(panel,world_size)
    _draw_crafting_sites(panel,world_size)
    _draw_live_markers(panel, world_size)
    _draw_compass(panel)
    _draw_scale_bar(panel, world_size)
    draw_rect(panel,Color(.16,.12,.065,.76),false,2.0)
    _label(str(_profile.get("zone_name","BROKEN KNIGHT")).to_upper(),Vector2(16,30),18,Color(.13,.11,.065))
    _label("M / ESC CLOSE   |   HOVER FOR DETAILS",Vector2(16,panel.end.y-16),11,Color(.16,.11,.055))
    _draw_feature_tooltip(panel)
    if _teleport_mode:
        _draw_teleport_cursor(panel, world_size)
        _label("TELEPORT ACTIVE - CLICK MAP",Vector2(panel.end.x-260,72),13,Color(.68,.10,.035))


func _draw_crafting_sites(panel:Rect2,world_size:float)->void:
    if not is_instance_valid(_director) or not _director.has_method("get_world_interaction_markers"):return
    for marker in _director.get_world_interaction_markers():
        if marker.get("action","")!="craft":continue
        var position:Vector3=marker.position
        var p:=_map_point(Vector2(position.x,position.z),panel,world_size)
        draw_circle(p,6.2,Color(.22,.12,.035,.94))
        draw_rect(Rect2(p-Vector2(3.3,3.3),Vector2(6.6,6.6)),Color(.94,.58,.12),true)
        draw_line(p+Vector2(-4.2,4.2),p+Vector2(4.2,-4.2),Color(.24,.12,.03),1.7)
        _register_map_feature(p,7.0,"Town Crafting Yard","Crafting",Vector2(position.x,position.z))


func _draw_realm_crest(panel:Rect2)->void:
    var sidebar:=_left_sidebar(panel)
    var c:=sidebar.position+Vector2(sidebar.size.x*.5,94.0)
    var gold:=Color(.66,.40,.12,.92)
    var river:=Color(.24,.46,.58,.92)
    draw_line(c+Vector2(-20,-1),c+Vector2(20,-1),gold,3.0)
    draw_line(c+Vector2(-17,-1),c+Vector2(-14,-13),gold,4.0)
    draw_line(c+Vector2(17,-1),c+Vector2(14,-13),gold,4.0)
    draw_line(c+Vector2(-3,-1),c+Vector2(-4,-10),gold,4.0)
    draw_line(c+Vector2(-20,9),c+Vector2(0,17),river,3.0)
    draw_line(c+Vector2(0,17),c+Vector2(20,9),river,3.0)
    var title_size:=clampi(roundi(sidebar.size.x*.080),15,24)
    _label(str(_profile.get("zone_name","BROKEN KNIGHT")).to_upper(),sidebar.position+Vector2(12,28),title_size,Color(.12,.16,.16))
    _label("ROYAL COMPLETE SURVEY",sidebar.position+Vector2(13,49),12,Color(.26,.26,.22))
    _label("FULL REALM REVEALED",sidebar.position+Vector2(13,67),11,Color(.55,.19,.08))


func _toggle_teleport_mode() -> void:
    _teleport_mode = not _teleport_mode
    _teleport_button.text = "TELEPORT: ON" if _teleport_mode else "TELEPORT: OFF"
    _teleport_button.button_pressed = _teleport_mode
    queue_redraw()


func set_teleport_mode(enabled: bool) -> void:
    _teleport_mode = enabled
    if is_instance_valid(_teleport_button):
        _teleport_button.text = "TELEPORT: ON" if enabled else "TELEPORT: OFF"
        _teleport_button.button_pressed = enabled
    queue_redraw()


func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        # Tooltips and the teleport crosshair follow the pointer on demand;
        # the entire illustrated map no longer redraws five times per second.
        queue_redraw()
        return
    if not _teleport_mode or not (event is InputEventMouseButton):
        return
    if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
        return
    var panel := _map_panel()
    if not panel.has_point(event.position):
        return
    var normalized: Vector2 = (event.position - panel.position) / panel.size
    var world_size: float = _profile.get("world_size", 7200.0)
    var destination: Vector2 = (normalized - Vector2(0.5, 0.5)) * world_size
    set_teleport_mode(false)
    teleport_requested.emit(destination)
    accept_event()


func _map_panel() -> Rect2:
    return Rect2(Vector2.ZERO,Vector2(maxf(1.0,size.x),maxf(1.0,size.y)))


func _left_sidebar(panel:Rect2)->Rect2:
    return Rect2(Vector2(14,14),Vector2(minf(270.0,panel.size.x*.22),minf(440.0,panel.size.y-28.0)))


func _right_sidebar(panel:Rect2)->Rect2:
    var width:=minf(268.0,panel.size.x*.22)
    return Rect2(Vector2(panel.end.x-width-14.0,14.0),Vector2(width,minf(690.0,panel.size.y-28.0)))


func _draw_side_panels(panel:Rect2)->void:
    var parchment:=Color(.87,.80,.64,.88)
    for sidebar in [_left_sidebar(panel),_right_sidebar(panel)]:
        draw_rect(sidebar,parchment,true)
        draw_rect(sidebar,Color(.20,.15,.075,.96),false,2.0)


func _draw_grid(panel: Rect2) -> void:
    for i in range(1, 10):
        var gx := panel.position.x + panel.size.x * i / 10.0
        var gy := panel.position.y + panel.size.y * i / 10.0
        draw_line(Vector2(gx, panel.position.y), Vector2(gx, panel.end.y), Color(0.17, 0.12, 0.06, 0.16), 1.0)
        draw_line(Vector2(panel.position.x, gy), Vector2(panel.end.x, gy), Color(0.17, 0.12, 0.06, 0.16), 1.0)
    for i in range(10):
        # The title occupies the north-west corner; begin column lettering
        # after it so cartographic labels never print through the heading.
        if i >= 3:
            _label(char(65 + i), Vector2(panel.position.x + panel.size.x * (i + 0.5) / 10.0 - 4, panel.position.y + 16), 11, Color(0.23, 0.14, 0.06))
        _label(str(i + 1), Vector2(panel.position.x + 10, panel.position.y + panel.size.y * (i + 0.5) / 10.0 + 4), 11, Color(0.23, 0.14, 0.06))


func _draw_landform_regions(panel:Rect2,world_size:float)->void:
    for region_index in range(_profile.get("landform_regions",[]).size()):
        var region:Dictionary=_profile.get("landform_regions",[])[region_index]
        var center:Vector2=region.get("center",Vector2.ZERO)
        var center_px:=_map_point(center,panel,world_size)
        var angle:float=float(region.get("angle",0.0))
        var kind:=str(region.get("kind","rolling"))
        var length:float=float(region.get("length",float(region.get("radius",600.0))*2.0))
        var width:float=float(region.get("width",float(region.get("radius",600.0))*float(region.get("aspect",.75))*2.0))
        var rx:=length*.5/world_size*panel.size.x
        var ry:=width*.5/world_size*panel.size.y
        var tint:=Color(.24,.19,.11,.16)
        if kind=="valley":tint=Color(.10,.29,.23,.17)
        elif kind=="ridge" or kind=="upland":tint=Color(.34,.27,.19,.18)
        elif kind=="basin":tint=Color(.18,.30,.22,.14)
        var outline:=_ellipse_polygon(center_px,rx,ry,angle,48)
        draw_polyline(outline,tint,1.1,true)
        if kind=="knolls":
            var count:int=int(region.get("count",5))
            for i in range(count):
                var knoll_angle:=angle+float(i)*2.399963
                var knoll_center:=center_px+Vector2(cos(knoll_angle)*rx*.42,sin(knoll_angle)*ry*.42)
                draw_arc(knoll_center,maxf(2.0,minf(rx,ry)*(.10+float(i%3)*.018)),0,TAU,20,Color(.33,.25,.15,.20),.8)
        if _full_detail and region_index%2==0:
            _map_label(region.get("name","Landform"),center_px+Vector2(5,-4),9,Color(.24,.22,.18,.88),panel)


func _draw_field_boundaries(panel:Rect2,world_size:float)->void:
    if not _full_detail:return
    for boundary in _profile.get("field_boundaries",[]):
        var points:=PackedVector2Array()
        for world_point in boundary.get("points",[]):points.append(_map_point(world_point,panel,world_size))
        if points.size()<2:continue
        draw_polyline(points,Color(.20,.16,.09,.88),2.1,true)
        draw_polyline(points,Color(.66,.61,.46,.72),.75,true)
        var middle:=points[points.size()/2]
        _register_map_feature(middle,5.0,str(boundary.get("name","Field wall")),"Field boundary",boundary.get("points",[])[boundary.get("points",[]).size()/2])


func _draw_field_parcels(panel:Rect2,world_size:float)->void:
    for site in _profile.get("town_sites",[]):
        if site.get("capital",false):continue
        var center:Vector2=site.get("position",Vector2.ZERO)
        var radius:float=float(site.get("radius",140.0))
        var road:=_nearest_corridor_segment(center,_profile.get("road_corridors",[]))
        if road.is_empty():continue
        var direction:Vector2=road.get("direction",Vector2(0,1)).normalized()
        var normal:=Vector2(-direction.y,direction.x)
        for side_value in [-1.0,1.0]:
            var side:float=side_value
            for strip in range(3):
                var field_center:=center-direction*radius*(.72+float(strip)*.27)+normal*side*radius*(.54+float(strip%2)*.19)
                var half_length:=34.0+float(strip%2)*8.0
                var half_width:=20.0+float((strip+1)%2)*5.0
                var corners:=PackedVector2Array([
                    _map_point(field_center-direction*half_length-normal*half_width,panel,world_size),
                    _map_point(field_center+direction*half_length-normal*half_width,panel,world_size),
                    _map_point(field_center+direction*half_length+normal*half_width,panel,world_size),
                    _map_point(field_center-direction*half_length+normal*half_width,panel,world_size),
                ])
                var field_tint:=Color(.68,.52,.14,.52) if (strip+int(side>0.0))%2==0 else Color(.47,.34,.11,.48)
                draw_colored_polygon(corners,field_tint)
                draw_polyline(corners,Color(.28,.20,.07,.68),1.0,true)
                for row in range(1,6):
                    var across:float=lerpf(-half_width,half_width,float(row)/6.0)
                    draw_line(
                        _map_point(field_center-direction*half_length+normal*across,panel,world_size),
                        _map_point(field_center+direction*half_length+normal*across,panel,world_size),
                        Color(.43,.30,.08,.56),.85,true
                    )
                _register_map_feature(_map_point(field_center,panel,world_size),6.0,"%s Croft"%str(site.get("name","Town")),"Farm field",field_center)


func _draw_town_detail(panel:Rect2,world_size:float)->void:
    if not _full_detail:return
    for site in _profile.get("town_sites",[]):
        var center:Vector2=site.get("position",Vector2.ZERO)
        if site.get("capital",false):
            _draw_crownspire_detail(center,panel,world_size)
        else:
            var radius:float=site.get("radius",135.0)
            var road:=_nearest_corridor_segment(center,_profile.get("road_corridors",[]))
            var direction:Vector2=road.get("direction",Vector2(0,1)).normalized()
            var normal:=Vector2(-direction.y,direction.x)
            var town_center:=_map_point(center,panel,world_size)
            draw_line(_map_point(center-direction*radius*.82,panel,world_size),_map_point(center+direction*radius*.82,panel,world_size),Color(.76,.59,.30,.82),2.2,true)
            draw_line(_map_point(center-normal*radius*.68,panel,world_size),_map_point(center+normal*radius*.68,panel,world_size),Color(.76,.59,.30,.74),1.8,true)
            draw_arc(town_center,radius*.78/world_size*panel.size.x,0,TAU,48,Color(.28,.18,.08,.44),.9)
            for i in range(14):
                var ring:=radius*(.37 if i<7 else .62)
                var angle:=float(i%7)*TAU/7.0+(.18 if i<7 else .55)
                var point:=center+Vector2(cos(angle),sin(angle))*ring
                _draw_map_building(point,Vector2(10.0+float(i%3)*1.8,8.5+float((i+1)%2)*2.0),angle+PI,panel,world_size,Color(.48,.25,.10,.90))
            _draw_map_building(center+Vector2(radius*.18,radius*.28),Vector2(18,12),PI,panel,world_size,Color(.56,.28,.10,.94))
        var market:=_map_point(center+(Vector2(0,38) if site.get("capital",false) else Vector2.ZERO),panel,world_size)
        draw_circle(market,4.0,Color(.83,.66,.31,.82))
        _register_map_feature(market,5.0,"%s Market"%str(site.get("name","Town")),"Market",center)


func _draw_crownspire_detail(center:Vector2,panel:Rect2,world_size:float)->void:
    var wall_half:=190.0
    var stone:=Color(.35,.32,.27,.96)
    var stone_light:=Color(.69,.67,.57,.88)
    var paving:=Color(.72,.68,.57,.56)
    var royal_roof:=Color(.48,.075,.055,.97)
    # Rectangular city enclosure, with the real southern gate left open.
    _draw_world_rect(center,Vector2(380,380),0,panel,world_size,Color(.55,.44,.25,.10),Color.TRANSPARENT)
    draw_line(_map_point(center+Vector2(-wall_half,-wall_half),panel,world_size),_map_point(center+Vector2(wall_half,-wall_half),panel,world_size),stone,2.8,true)
    draw_line(_map_point(center+Vector2(-wall_half,-wall_half),panel,world_size),_map_point(center+Vector2(-wall_half,wall_half),panel,world_size),stone,2.8,true)
    draw_line(_map_point(center+Vector2(wall_half,-wall_half),panel,world_size),_map_point(center+Vector2(wall_half,wall_half),panel,world_size),stone,2.8,true)
    draw_line(_map_point(center+Vector2(-wall_half,wall_half),panel,world_size),_map_point(center+Vector2(-16,wall_half),panel,world_size),stone,2.8,true)
    draw_line(_map_point(center+Vector2(16,wall_half),panel,world_size),_map_point(center+Vector2(wall_half,wall_half),panel,world_size),stone,2.8,true)
    for corner in [Vector2(-wall_half,-wall_half),Vector2(wall_half,-wall_half),Vector2(-wall_half,wall_half),Vector2(wall_half,wall_half)]:
        _draw_world_rect(center+corner,Vector2(20,20),0,panel,world_size,stone_light,stone,1.0)
    for gate_x in [-12.5,12.5]:
        _draw_world_rect(center+Vector2(gate_x,wall_half),Vector2(7,13),0,panel,world_size,stone_light,stone,.9)
    # The authored boulevard, market road, fountain, arches and stalls.
    draw_line(_map_point(center+Vector2(0,-32),panel,world_size),_map_point(center+Vector2(0,260),panel,world_size),paving,4.2,true)
    draw_line(_map_point(center+Vector2(-125,28),panel,world_size),_map_point(center+Vector2(125,28),panel,world_size),paving,3.2,true)
    var market:=_map_point(center+Vector2(0,38),panel,world_size)
    draw_circle(market,7.2,Color(.70,.62,.44,.72))
    draw_circle(_map_point(center+Vector2(0,28),panel,world_size),3.1,Color(.25,.55,.62,.92))
    for side in [-1.0,1.0]:
        _draw_world_rect(center+Vector2(61.0*side,28),Vector2(10,5),0,panel,world_size,stone_light,stone,.8)
    for stall_index in range(6):
        var theta:=float(stall_index)*TAU/6.0
        _draw_world_rect(center+Vector2(0,38)+Vector2(cos(theta),sin(theta))*30.0,Vector2(8,5),theta,panel,world_size,Color(.66,.37,.12,.94),Color(.25,.12,.04,.82),.7)
    # Exact residential and trade plots from the capital builder.
    var plots:Array=[Vector2(-118,-15),Vector2(-82,-20),Vector2(-120,48),Vector2(-80,66),Vector2(82,-18),Vector2(122,-8),Vector2(82,55),Vector2(124,72),Vector2(-132,118),Vector2(-88,132),Vector2(-45,115),Vector2(46,118),Vector2(88,136),Vector2(132,116),Vector2(-145,-88),Vector2(-110,-118),Vector2(112,-112),Vector2(148,-82)]
    for i in range(plots.size()):
        _draw_map_building(center+plots[i],Vector2(12.0+float(i%4)*2.2,9.5+float(i%3)),atan2(-plots[i].x,-plots[i].y),panel,world_size,Color(.43+.035*float(i%3),.19,.075,.96))
    # Crownspire Castle: rectangular inner bailey, four corner towers, open
    # southern gate and the four-storey keep footprint at its real location.
    var castle_center:=center+Vector2(0,-92)
    _draw_world_rect(castle_center,Vector2(142,118),0,panel,world_size,Color(.64,.63,.57,.36),Color.TRANSPARENT)
    draw_line(_map_point(castle_center+Vector2(-71,-59),panel,world_size),_map_point(castle_center+Vector2(71,-59),panel,world_size),stone_light,2.3,true)
    draw_line(_map_point(castle_center+Vector2(-71,-59),panel,world_size),_map_point(castle_center+Vector2(-71,59),panel,world_size),stone_light,2.3,true)
    draw_line(_map_point(castle_center+Vector2(71,-59),panel,world_size),_map_point(castle_center+Vector2(71,59),panel,world_size),stone_light,2.3,true)
    draw_line(_map_point(castle_center+Vector2(-71,59),panel,world_size),_map_point(castle_center+Vector2(-13,59),panel,world_size),stone_light,2.3,true)
    draw_line(_map_point(castle_center+Vector2(13,59),panel,world_size),_map_point(castle_center+Vector2(71,59),panel,world_size),stone_light,2.3,true)
    for corner in [Vector2(-71,-59),Vector2(71,-59),Vector2(-71,59),Vector2(71,59)]:
        _draw_world_rect(castle_center+corner,Vector2(18,18),0,panel,world_size,stone,Color(.15,.12,.08,.96),1.0)
    var keep_center:=castle_center+Vector2(0,-8)
    _draw_world_rect(keep_center,Vector2(58,44),0,panel,world_size,royal_roof,Color(.18,.10,.055,.98),1.4)
    for keep_corner in [Vector2(-29,-22),Vector2(29,-22),Vector2(-29,22),Vector2(29,22)]:
        _draw_world_rect(keep_center+keep_corner,Vector2(9,9),0,panel,world_size,Color(.20,.20,.19,.98),stone_light,.8)
    _register_map_feature(_map_point(castle_center,panel,world_size),16.0,"Crownspire Castle","Castle and inner bailey",castle_center)


func _draw_world_rect(world_center:Vector2,world_size_2d:Vector2,yaw:float,panel:Rect2,world_size:float,fill:Color,outline:Color,line_width:float=1.0)->void:
    var forward:=Vector2(cos(yaw),sin(yaw))
    var side:=Vector2(-forward.y,forward.x)
    var corners:=PackedVector2Array()
    for signs_value in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
        var signs:Vector2=signs_value
        corners.append(_map_point(world_center+side*world_size_2d.x*.5*signs.x+forward*world_size_2d.y*.5*signs.y,panel,world_size))
    if fill.a>0.0:draw_colored_polygon(corners,fill)
    if outline.a>0.0:draw_polyline(corners,outline,line_width,true)


func _draw_map_building(world_center:Vector2,world_size_2d:Vector2,yaw:float,panel:Rect2,world_size:float,color:Color)->void:
    world_size_2d*=2.15
    var forward:=Vector2(cos(yaw),sin(yaw))
    var side:=Vector2(-forward.y,forward.x)
    var corners:=PackedVector2Array()
    for signs_value in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
        var signs:Vector2=signs_value
        var world_corner:Vector2=world_center+side*world_size_2d.x*.5*signs.x+forward*world_size_2d.y*.5*signs.y
        corners.append(_map_point(world_corner,panel,world_size))
    draw_colored_polygon(corners,color)
    draw_polyline(corners,Color(.20,.105,.035,.86),.8,true)
    draw_line((corners[0]+corners[1])*.5,(corners[2]+corners[3])*.5,Color(.92,.66,.30,.64),.7,true)


func _draw_landmark_sites(panel:Rect2,world_size:float)->void:
    for site in _profile.get("landmark_sites",[]):
        var world_point:Vector2=site.get("position",Vector2.ZERO)
        var p:=_map_point(world_point,panel,world_size)
        var kind:=str(site.get("kind","landmark"))
        var radius:float=float(site.get("radius",20.0))/world_size*panel.size.x
        match kind:
            "hedgerow":
                var angle:float=float(site.get("rotation",0.0))
                var tangent:=Vector2(cos(angle),sin(angle))
                draw_line(p-tangent*radius,p+tangent*radius,Color(.10,.31,.12,.88),3.0)
                draw_line(p-tangent*radius,p+tangent*radius,Color(.36,.49,.19,.78),1.0)
            "grove":
                draw_circle(p,maxf(3.5,radius),Color(.08,.28,.13,.18))
                draw_arc(p,maxf(3.5,radius),0,TAU,24,Color(.08,.27,.12,.76),1.0)
                for i in range(4):
                    var q:=p+Vector2(cos(float(i)*TAU/4.0),sin(float(i)*TAU/4.0))*maxf(1.5,radius*.56)
                    _draw_tree_symbol(q,2.1,Color(.08,.27,.12,.92))
            "outcrop":
                for i in range(3):
                    var q:=p+Vector2(float(i-1)*3.2,float(i%2)*1.8)
                    draw_colored_polygon(PackedVector2Array([q+Vector2(-3,3),q+Vector2(0,-3),q+Vector2(3,3)]),Color(.38,.36,.31,.94))
            "waystone":
                draw_colored_polygon(PackedVector2Array([p+Vector2(0,-6),p+Vector2(4,0),p+Vector2(0,6),p+Vector2(-4,0)]),Color(.46,.43,.35,.96))
            "cairn":
                draw_circle(p,4.0,Color(.27,.24,.19,.96));draw_circle(p-Vector2(0,2),2.2,Color(.55,.51,.42,.96))
        _register_map_feature(p,maxf(5.0,radius),str(site.get("name","Landmark")),kind.capitalize(),world_point)


func _draw_special_map_sites(panel:Rect2,world_size:float)->void:
    for site in _profile.get("map_sites",[]):
        var world_point:Vector2=site.get("position",Vector2.ZERO)
        var p:=_map_point(world_point,panel,world_size)
        var kind:=str(site.get("kind","landmark"))
        match kind:
            "windmill":
                draw_circle(p,4.5,Color(.35,.20,.08));draw_line(p-Vector2(9,0),p+Vector2(9,0),Color(.25,.14,.05),2.0);draw_line(p-Vector2(0,9),p+Vector2(0,9),Color(.25,.14,.05),2.0);draw_line(p-Vector2(6,6),p+Vector2(6,-6),Color(.56,.39,.13),1.0)
            "ruin":
                draw_polyline(PackedVector2Array([p+Vector2(-8,-6),p+Vector2(7,-6),p+Vector2(7,1),p+Vector2(3,1),p+Vector2(3,7),p+Vector2(-8,7)]),Color(.29,.26,.21,.94),2.4);draw_line(p+Vector2(-8,-1),p+Vector2(-1,7),Color(.57,.52,.42,.72),1.3)
            "shrine":
                draw_colored_polygon(PackedVector2Array([p+Vector2(0,-8),p+Vector2(-7,6),p+Vector2(7,6)]),Color(.58,.45,.22,.94));draw_line(p+Vector2(0,-5),p+Vector2(0,4),Color(.96,.81,.38),2.0);draw_circle(p,2.2,Color(.95,.72,.20))
            "well":
                draw_circle(p,7.0,Color(.27,.18,.08),false,2.3);draw_circle(p,4.2,Color(.18,.48,.59));draw_line(p+Vector2(-7,-5),p+Vector2(7,-5),Color(.34,.20,.08),1.4)
            "castle":
                pass # Crownspire's complete footprint is drawn by _draw_crownspire_detail.
        _register_map_feature(p,10.0,str(site.get("name","Landmark")),kind.capitalize(),world_point)


func _draw_services(panel:Rect2,world_size:float)->void:
    if not is_instance_valid(_director) or not _director.has_method("get_map_service_markers"):return
    for marker in _director.get_map_service_markers():
        var position:Vector3=marker.get("position",Vector3.ZERO)
        if absf(position.x)>world_size*.55 or absf(position.z)>world_size*.55:continue
        var world_point:=Vector2(position.x,position.z)
        var p:=_map_point(world_point,panel,world_size)
        var kind:=str(marker.get("kind","service"))
        if kind=="vendor":
            draw_colored_polygon(PackedVector2Array([p+Vector2(0,-4),p+Vector2(4,0),p+Vector2(0,4),p+Vector2(-4,0)]),Color(.93,.58,.12,.98))
        else:
            draw_rect(Rect2(p-Vector2(3,3),Vector2(6,6)),Color(.22,.14,.05,.96),true)
            draw_line(p+Vector2(-4,4),p+Vector2(4,-4),Color(.94,.66,.18),1.5)
        _register_map_feature(p,5.0,str(marker.get("name","Service")),kind.capitalize(),world_point)


func _draw_tree_symbol(p:Vector2,size_value:float,color:Color)->void:
    draw_colored_polygon(PackedVector2Array([p+Vector2(0,-size_value),p+Vector2(-size_value*.72,size_value*.58),p+Vector2(size_value*.72,size_value*.58)]),color)


func _ellipse_polygon(center:Vector2,rx:float,ry:float,angle:float,segments:int)->PackedVector2Array:
    var points:=PackedVector2Array()
    for i in range(segments+1):
        var theta:=TAU*float(i)/float(segments)
        points.append(center+Vector2(cos(theta)*rx,sin(theta)*ry).rotated(angle))
    return points


func _draw_corridors(corridors: Array, panel: Rect2, world_size: float, kind: String) -> void:
    if kind=="river":
        var river_lines:Array[PackedVector2Array]=[]
        var river_widths:Array[float]=[]
        for corridor in corridors:
            var river_points:=PackedVector2Array()
            for point in corridor.get("points",[]):river_points.append(_map_point(point,panel,world_size))
            if river_points.size()<2:continue
            river_lines.append(river_points)
            river_widths.append(maxf(2.0,float(corridor.get("width",48.0))*.66/world_size*panel.size.x))
        for i in range(river_lines.size()):draw_polyline(river_lines[i],Color(.10,.22,.25,.96),river_widths[i]+3.5,true)
        for i in range(river_lines.size()):draw_polyline(river_lines[i],Color(.29,.67,.76,1.0),river_widths[i],true)
        for i in range(river_lines.size()):draw_polyline(river_lines[i],Color(.67,.88,.88,.42),maxf(1.0,river_widths[i]*.18),true)
        return
    for corridor in corridors:
        var points := PackedVector2Array()
        for point in corridor.get("points", []):
            points.append(_map_point(point, panel, world_size))
        if points.size() < 2:
            continue
        var authored_width: float = corridor.get("width", 12.0)
        var physical_width := authored_width
        if kind == "river":
            physical_width *= 0.66
        elif kind == "road":
            physical_width *= 0.48
        elif kind == "trail":
            physical_width *= 0.48
        var pixels := maxf(2.0, physical_width / world_size * panel.size.x)
        if kind == "river":
            draw_polyline(points, Color(0.10, 0.22, 0.25, 0.96), pixels + 3.5, true)
            draw_polyline(points, Color(0.29, 0.67, 0.76, 1.0), pixels, true)
            draw_polyline(points, Color(0.67, 0.88, 0.88, 0.42), maxf(1.0, pixels * 0.18), true)
        elif kind == "road":
            draw_polyline(points, Color(0.20, 0.12, 0.045, 0.94), pixels + 3.0, true)
            draw_polyline(points, Color(0.84, 0.58, 0.24, 1.0), pixels, true)
        else:
            _draw_dashed_polyline(points,Color(0.24,0.15,0.065,0.88),maxf(1.4,pixels),7.0,5.0)


func _draw_dashed_polyline(points:PackedVector2Array,color:Color,width:float,dash_length:float,gap_length:float)->void:
    for i in range(points.size()-1):
        var a:=points[i]
        var b:=points[i+1]
        var segment:=b-a
        var length:=segment.length()
        if length<=0.01:continue
        var direction:=segment/length
        var cursor:=0.0
        while cursor<length:
            var dash_end:=minf(cursor+dash_length,length)
            draw_line(a+direction*cursor,a+direction*dash_end,color,width,true)
            cursor+=dash_length+gap_length


func _draw_corridor_names(panel: Rect2, world_size: float) -> void:
    for corridor in _profile.get("river_corridors", []):
        var river_name:=str(corridor.get("name", "River"))
        if "tributary" in river_name.to_lower():
            continue
        var points: Array = corridor.get("points", [])
        if points.size() > 2:
            var p := _map_point(points[points.size() / 2], panel, world_size)
            _map_label(river_name, p + Vector2(10, -8), 11, Color(0.07, 0.22, 0.27),panel)


func _draw_ground_detail(panel:Rect2,world_size:float)->void:
    # Deterministic terrain marks fill otherwise empty country without adding
    # fake places or requiring a textual legend.
    var columns:=42
    var rows:=24
    var cell:=panel.size/Vector2(columns,rows)
    for row in range(rows):
        for column in range(columns):
            var index:=row*columns+column
            var chance:=fposmod(sin(float(index)*12.9898+4.73)*43758.5453,1.0)
            if chance>.48:continue
            var jitter:=Vector2(
                fposmod(sin(float(index)*31.73+1.17)*21653.31,1.0),
                fposmod(sin(float(index)*17.19+8.41)*31627.73,1.0)
            )
            var p:=panel.position+(Vector2(column,row)+jitter)*cell
            var world_point:=(p-panel.position)/panel.size*world_size-Vector2.ONE*world_size*.5
            var forested:=false
            for forest in _profile.get("forest_regions",[]):
                if world_point.distance_to(forest.get("center",Vector2.ZERO))<float(forest.get("radius",300.0))*.92:
                    forested=true;break
            if forested:continue
            var highland:=false
            for chain in _profile.get("mountain_chains",[]):
                var center:Vector2=chain.get("center",Vector2.ZERO)
                var angle:float=float(chain.get("angle",0.0))
                var tangent:=Vector2(cos(angle),sin(angle))
                var normal:=Vector2(-tangent.y,tangent.x)
                var delta:=world_point-center
                var along:=absf(delta.dot(tangent))/maxf(1.0,float(chain.get("length",500.0))*.55)
                var across:=absf(delta.dot(normal))/maxf(1.0,float(chain.get("width",300.0))*.55)
                if along*along+across*across<1.0:
                    highland=true;break
            var rotation:=(chance-.5)*1.8
            if highland:
                var rock:=Color(.22,.20,.16,.50)
                draw_line(p+Vector2(-3,2).rotated(rotation),p+Vector2(0,-2).rotated(rotation),rock,.9,true)
                draw_line(p+Vector2(0,-2).rotated(rotation),p+Vector2(3,2).rotated(rotation),rock,.9,true)
                draw_line(p+Vector2(-1,2).rotated(rotation),p+Vector2(3,2).rotated(rotation),Color(.66,.61,.49,.30),.7,true)
            elif world_point.x>world_size*.18 or world_point.y>world_size*.20:
                var scrub:=Color(.30,.25,.105,.46)
                draw_line(p+Vector2(-2,2),p+Vector2(0,-2),scrub,.8,true)
                draw_line(p+Vector2(0,-2),p+Vector2(2,2),scrub,.8,true)
            else:
                var grass:=Color(.11,.27,.095,.38)
                draw_line(p+Vector2(-2,2),p+Vector2(-1,-1),grass,.75,true)
                draw_line(p+Vector2(0,2),p+Vector2(0,-2),grass,.75,true)
                draw_line(p+Vector2(2,2),p+Vector2(1,-1),grass,.75,true)


func _draw_forests(panel: Rect2, world_size: float) -> void:
    for region_index in range(_profile.get("forest_regions",[]).size()):
        var region:Dictionary=_profile.get("forest_regions",[])[region_index]
        var center: Vector2 = region.get("center", Vector2.ZERO)
        var radius: float = region.get("radius", 300.0)
        var density: float = region.get("density", .65)
        var center_px := _map_point(center, panel, world_size)
        var radius_px := radius / world_size * panel.size.x
        # Overlapping canopy washes break the forest edge into natural lobes.
        # There is deliberately no enclosing oval or region outline.
        for cluster_index in range(32):
            var cluster_angle:=float(cluster_index)*2.399963+float(region_index)*.51
            var cluster_radius:=radius_px*(.045+float((cluster_index*7)%7)*.006)
            var cluster_distance:=radius_px*sqrt((float(cluster_index)+.7)/33.0)*.82
            var cluster_center:=center_px+Vector2(cos(cluster_angle),sin(cluster_angle))*cluster_distance
            draw_circle(cluster_center,cluster_radius,Color(.045,.18+.018*float(cluster_index%4),.085,.15+density*.045))
        var tree_count:=clampi(roundi(45.0+density*58.0),58,92)
        for i in range(tree_count):
            var angle:=float(i)*2.399963+float(region_index)*.43
            var r:=radius*sqrt((float(i)+.4)/float(tree_count+1))*(.78+sin(float(i)*1.71)*.13)
            var p:=_map_point(center+Vector2(cos(angle),sin(angle))*r,panel,world_size)
            var s:=1.7+float(i%5)*.26
            draw_circle(p+Vector2(.8,1.0),s*1.08,Color(.035,.09,.035,.34))
            draw_circle(p,s,Color(.07+.015*float(i%3),.24+.027*float(i%4),.095,.88))
            draw_circle(p-Vector2(.45,.55),s*.48,Color(.25,.40,.16,.54))
            draw_line(p+Vector2(0,s*.35),p+Vector2(0,s*1.65),Color(.17,.105,.045,.70),.7)
        _register_map_feature(center_px,maxf(8.0,radius_px*.74),str(region.get("name","Woodland")),"Forest",center)


func _draw_mountains(panel: Rect2, world_size: float) -> void:
    for chain_index in range(_profile.get("mountain_chains",[]).size()):
        var chain:Dictionary=_profile.get("mountain_chains",[])[chain_index]
        var center: Vector2 = chain.get("center", Vector2.ZERO)
        var angle: float = chain.get("angle", 0.0)
        var length: float = chain.get("length", 500.0)
        var chain_width: float = chain.get("width", 300.0)
        var center_px := _map_point(center, panel, world_size)
        var footprint_size := Vector2(length, chain_width) / world_size * panel.size.x
        var tangent:=Vector2(cos(angle),sin(angle))
        var normal:=Vector2(-tangent.y,tangent.x)
        var screen_normal:=Vector2(normal.x*panel.size.x,normal.y*panel.size.y).normalized()
        var ridge:=PackedVector2Array()
        var ridge_count:=18
        for i in range(ridge_count):
            var progress:=float(i)/float(ridge_count-1)
            var taper:=sin(progress*PI)
            var wobble:=sin(progress*PI*5.0+float(chain_index)*.81)*chain_width*.075*taper
            ridge.append(_map_point(center+tangent*((progress-.5)*length*.90)+normal*wobble,panel,world_size))
        draw_polyline(ridge,Color(.12,.105,.085,.47),4.6,true)
        draw_polyline(ridge,Color(.66,.60,.48,.62),1.4,true)
        for i in range(2,ridge_count-2,2):
            var p:=ridge[i]
            var taper:=sin(float(i)/float(ridge_count-1)*PI)
            var hachure:=(5.0+float((i*5)%7))*taper
            draw_line(p,p+screen_normal*hachure,Color(.18,.16,.13,.52),1.0,true)
            draw_line(p,p-screen_normal*hachure*.62,Color(.73,.68,.55,.38),.8,true)
        _register_map_feature(center_px,maxf(8.0,minf(footprint_size.x,footprint_size.y)*.35),str(chain.get("name","Mountain range")),"Mountain range",center)


func _draw_settlement_footprints(panel: Rect2, world_size: float) -> void:
    var sites: Array = [_profile.get("spawn_site", {})]
    sites.append_array(_profile.get("town_sites", []))
    for site in sites:
        if site.is_empty():
            continue
        if site.get("capital",false):
            continue
        var center := _map_point(site.get("position", Vector2.ZERO), panel, world_size)
        var radius_px := maxf(5.0, float(site.get("radius", 80.0)) / world_size * panel.size.x)
        var tint := Color(0.73, 0.55, 0.30, .19)
        var footprint:=PackedVector2Array()
        for i in range(33):
            var theta:=TAU*float(i)/32.0
            var irregularity:=.82+sin(theta*3.0+center.x*.013)*.13+sin(theta*7.0+center.y*.009)*.055
            footprint.append(center+Vector2(cos(theta),sin(theta))*radius_px*irregularity)
        draw_colored_polygon(footprint,tint)
        draw_polyline(footprint,Color(.29,.16,.06,.42),.8,true)


func _draw_sites(panel: Rect2, world_size: float) -> void:
    var sites: Array = [_profile.get("spawn_site", {})]
    sites.append_array(_profile.get("town_sites", []))
    for site in sites:
        var p := _map_point(site.get("position", Vector2.ZERO), panel, world_size)
        if site.get("capital", false):
            _map_label(site.get("name","Crownspire"),p+Vector2(39,-24),14,Color(.18,.09,.025),panel)
        else:
            draw_circle(p,5.5,Color(.24,.13,.05,.90))
            draw_colored_polygon(PackedVector2Array([p+Vector2(0,-6),p+Vector2(-6,-1),p+Vector2(-5,5),p+Vector2(5,5),p+Vector2(6,-1)]),Color(.76,.26,.10,.96))
            var label_offset := Vector2(13, 19) if site.get("name", "") == "Riverwatch" else Vector2(11, 5)
            _map_label(site.get("name", "Settlement"), p + label_offset, 14, Color(0.18, 0.09, 0.025),panel)
        _register_map_feature(p,12.0,str(site.get("name","Settlement")),"Royal capital" if site.get("capital",false) else "Settlement",site.get("position",Vector2.ZERO))
    for camp in _profile.get("camp_sites", []):
        var p := _map_point(camp.get("position", Vector2.ZERO), panel, world_size)
        draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(-5, 5), p + Vector2(5, 5)]), Color(0.88, 0.39, 0.10))
        draw_circle(p+Vector2(0,7),2.0,Color(.92,.67,.17,.96))
        _register_map_feature(p,7.0,str(camp.get("name","Camp")),"Camp",camp.get("position",Vector2.ZERO))


func _draw_water_sites(panel: Rect2, world_size: float) -> void:
    for pond in _profile.get("pond_sites", []):
        var center: Vector2 = pond.get("position", Vector2.ZERO)
        var p := _map_point(center, panel, world_size)
        var base_radius := float(pond.get("radius", 70.0)) * 1.18
        var radius_px := maxf(5.0, base_radius / world_size * panel.size.x)
        var outline := PackedVector2Array()
        for i in range(32):
            var angle := TAU * float(i) / 32.0
            var irregularity := 1.0 + sin(angle * 3.0 + center.x * 0.0017) * 0.11 + sin(angle * 7.0 + center.y * 0.0011) * 0.055
            outline.append(p + Vector2(cos(angle), sin(angle)) * radius_px * irregularity)
        draw_colored_polygon(outline, Color(0.25, 0.61, 0.68))
        draw_polyline(outline, Color(0.08, 0.24, 0.27), 1.5, true)
        _register_map_feature(p,maxf(7.0,radius_px),str(pond.get("name","Pond")),"Lake / pond",center)


func _draw_waterfalls(panel: Rect2, world_size: float) -> void:
    for waterfall in _profile.get("waterfall_sites", []):
        var world_point: Vector2 = waterfall.get("position", Vector2.ZERO)
        var p := _map_point(world_point, panel, world_size)
        var river_segment := _nearest_corridor_segment(world_point, _profile.get("river_corridors", []))
        var direction: Vector2 = river_segment.get("direction", Vector2(1,0))
        var screen_direction := Vector2(direction.x * panel.size.x, direction.y * panel.size.y).normalized()
        var normal := Vector2(-screen_direction.y, screen_direction.x)
        draw_line(p - normal * 7.0, p + normal * 7.0, Color(0.90, 0.95, 0.87), 3.0)
        draw_line(p - normal * 7.0 + screen_direction * 3.0, p + normal * 7.0 + screen_direction * 3.0, Color(0.08, 0.30, 0.35), 1.5)
        _register_map_feature(p,8.0,str(waterfall.get("name","Falls")),"Waterfall",world_point)


func _draw_bridges(panel: Rect2, world_size: float) -> void:
    for bridge in _profile.get("ford_sites", []):
        var world_point: Vector2 = bridge.get("position", Vector2.ZERO)
        var p := _map_point(world_point, panel, world_size)
        var river_segment := _nearest_corridor_segment(world_point, _profile.get("river_corridors", []))
        var road_segment := _nearest_corridor_segment(world_point, _profile.get("road_corridors", []))
        var world_direction := Vector2(0, 1)
        if bridge.get("standalone", false) and not river_segment.is_empty():
            var river_direction: Vector2 = river_segment.direction
            world_direction = Vector2(-river_direction.y, river_direction.x).normalized()
        elif not road_segment.is_empty():
            world_direction = road_segment.direction
        var tangent := Vector2(world_direction.x * panel.size.x, world_direction.y * panel.size.y).normalized()
        var normal := Vector2(-tangent.y, tangent.x)
        var river_width: float = float(river_segment.get("width", 52.0)) * .66
        var half_span := maxf(7.0, (river_width + 12.0) / world_size * (panel.size.x + panel.size.y) * .25)
        var half_width := maxf(2.8, float(bridge.get("bridge_width", 10.0)) / world_size * panel.size.x * .5)
        var corners := PackedVector2Array([
            p - tangent * half_span - normal * half_width,
            p + tangent * half_span - normal * half_width,
            p + tangent * half_span + normal * half_width,
            p - tangent * half_span + normal * half_width,
        ])
        draw_colored_polygon(corners, Color(0.31, 0.17, 0.055))
        draw_polyline(corners, Color(0.12, 0.065, 0.02), 1.4, true)
        draw_line(p - tangent * half_span, p + tangent * half_span, Color(0.94, 0.72, 0.26), 2.0)
        _register_map_feature(p,maxf(8.0,half_span),str(bridge.get("name","Bridge")),"Bridge / crossing",world_point)


func _nearest_corridor_segment(point: Vector2, corridors: Array) -> Dictionary:
    var nearest: Dictionary = {}
    var best_distance := INF
    for corridor in corridors:
        var points: Array = corridor.get("points", [])
        for i in range(points.size() - 1):
            var a: Vector2 = points[i]
            var b: Vector2 = points[i + 1]
            var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
            var distance := point.distance_squared_to(closest)
            if distance < best_distance:
                best_distance = distance
                nearest = {"direction":(b-a).normalized(), "width":float(corridor.get("width", 10.0)), "distance":sqrt(distance)}
    return nearest


func _draw_caves(panel: Rect2, world_size: float) -> void:
    for entry in [{"p": Vector2(-2700, 1700), "n": "West Cavern"}, {"p": Vector2(2620, -1800), "n": "East Cavern"}]:
        var p := _map_point(entry.p, panel, world_size)
        draw_arc(p, 7, PI, TAU, 16, Color(0.13, 0.09, 0.04), 3.0)
        _map_label(entry.n, p + Vector2(9, 4), 11, Color(0.20, 0.11, 0.04),panel)
        _register_map_feature(p,8.0,str(entry.n),"Dungeon entrance",entry.p)


func _draw_live_markers(panel: Rect2, world_size: float) -> void:
    # Enemy locations intentionally belong to the close-range minimap only.
    # The parchment world map remains useful for navigation and exploration.
    if is_instance_valid(_player):
        var p := _map_point(Vector2(_player.global_position.x, _player.global_position.z), panel, world_size)
        var heading := _player_map_heading()
        var silhouette:=PackedVector2Array([
            p+Vector2(0,-16).rotated(heading),p+Vector2(-4,-5).rotated(heading),
            p+Vector2(-7,2).rotated(heading),p+Vector2(-4.5,9).rotated(heading),
            p+Vector2(0,6).rotated(heading),p+Vector2(4.5,9).rotated(heading),
            p+Vector2(7,2).rotated(heading),p+Vector2(4,-5).rotated(heading)
        ])
        draw_colored_polygon(silhouette,Color(.16,.105,.035,.98))
        draw_polyline(silhouette,Color(.84,.61,.18,.98),2.2,true)
        var visor:=PackedVector2Array([
            p+Vector2(0,-12).rotated(heading),p+Vector2(-3.2,-3).rotated(heading),
            p+Vector2(0,3.5).rotated(heading),p+Vector2(3.2,-3).rotated(heading)
        ])
        draw_colored_polygon(visor,Color(.86,.90,.88,.98))
        draw_polyline(visor,Color(.24,.29,.30,.96),1.0,true)


func _player_map_heading() -> float:
    var visual := _player.get_node_or_null("Visual") as Node3D
    var world_yaw := visual.global_rotation.y if visual else _player.global_rotation.y
    return PI - world_yaw


func _draw_compass(panel: Rect2) -> void:
    var c:=Vector2(panel.end.x-61.0,109.0)
    draw_circle(c+Vector2(2,2),38,Color(.035,.025,.015,.35))
    draw_circle(c,38,Color(.18,.10,.035,.94))
    draw_circle(c,34,Color(.84,.75,.55,.94))
    draw_arc(c,34,0,TAU,64,Color(.42,.24,.07),2.0)
    draw_arc(c,27,0,TAU,64,Color(.38,.24,.10,.65),1.0)
    draw_colored_polygon(PackedVector2Array([c+Vector2(0,-30),c+Vector2(-7,1),c,c+Vector2(7,1)]),Color(.70,.11,.05))
    draw_colored_polygon(PackedVector2Array([c+Vector2(0,30),c+Vector2(-7,-1),c,c+Vector2(7,-1)]),Color(.26,.18,.10))
    draw_colored_polygon(PackedVector2Array([c+Vector2(30,0),c+Vector2(-1,-6),c,c+Vector2(-1,6)]),Color(.54,.39,.17))
    draw_colored_polygon(PackedVector2Array([c+Vector2(-30,0),c+Vector2(1,-6),c,c+Vector2(1,6)]),Color(.54,.39,.17))
    draw_circle(c,3.5,Color(.90,.66,.18))
    _label("N",c+Vector2(-5,-40),14,Color(.18,.06,.02))


func _draw_legend(panel: Rect2) -> void:
    var sidebar:=_left_sidebar(panel)
    var r:=Rect2(sidebar.position+Vector2(9,132),Vector2(sidebar.size.x-18,minf(238.0,sidebar.size.y-150.0)))
    draw_rect(r,Color(.90,.81,.64,.70),true)
    draw_rect(r,Color(.28,.17,.06),false,1.2)
    _label("MAP KEY", r.position + Vector2(10, 18), 13, Color(0.18, 0.09, 0.025))
    draw_line(r.position + Vector2(12, 35), r.position + Vector2(42, 35), Color(0.84, 0.58, 0.24), 4.0)
    _label("Road", r.position + Vector2(50, 39), 11, Color(0.22, 0.12, 0.04))
    draw_line(r.position + Vector2(12, 53), r.position + Vector2(42, 53), Color(0.29, 0.67, 0.76), 5.0)
    _label("River", r.position + Vector2(50, 57), 11, Color(0.22, 0.12, 0.04))
    draw_line(r.position + Vector2(12, 71), r.position + Vector2(42, 71), Color(0.42, 0.29, 0.12), 2.0)
    _label("Trail", r.position + Vector2(50, 75), 11, Color(0.22, 0.12, 0.04))
    draw_circle(r.position + Vector2(21, 90), 7, Color(0.25, 0.61, 0.68))
    _label("Pond", r.position + Vector2(50, 94), 11, Color(0.22, 0.12, 0.04))
    draw_rect(Rect2(r.position + Vector2(16, 103), Vector2(10, 8)), Color(0.76, 0.26, 0.10))
    _label("Settlement", r.position + Vector2(50, 112), 11, Color(0.22, 0.12, 0.04))
    draw_rect(Rect2(r.position + Vector2(14, 121), Vector2(16, 6)), Color(0.30, 0.18, 0.07))
    _label("Bridge / crossing", r.position + Vector2(50, 129), 11, Color(0.22, 0.12, 0.04))
    draw_circle(r.position + Vector2(21, 145), 7, Color(1.0, 0.87, 0.35))
    _label("Player and facing", r.position + Vector2(50, 149), 11, Color(0.22, 0.12, 0.04))
    draw_colored_polygon(PackedVector2Array([r.position+Vector2(21,157),r.position+Vector2(25,161),r.position+Vector2(21,165),r.position+Vector2(17,161)]),Color(.94,.58,.12))
    _label("Vendor / service",r.position+Vector2(50,165),11,Color(.22,.12,.04))
    _label("Hover any symbol for name + coordinates",sidebar.position+Vector2(12,sidebar.size.y-46),10,Color(.23,.14,.06))
    _label("M / Esc closes map",sidebar.position+Vector2(12,sidebar.size.y-25),11,Color(.23,.14,.06))


func _draw_gazetteer(panel:Rect2)->void:
    var sidebar:=_right_sidebar(panel)
    var x:=sidebar.position.x+12.0
    var y:=sidebar.position.y+224.0
    _label("ROYAL GAZETTEER",Vector2(x,y),14,Color(.17,.095,.03))
    y+=24.0
    var groups:Array=[
        ["SETTLEMENTS",[_profile.get("spawn_site",{})]+_profile.get("town_sites",[])],
        ["WATERS",_profile.get("pond_sites",[])],
        ["CROSSINGS",_profile.get("ford_sites",[])],
        ["DUNGEONS",[{"name":"West Cavern"},{"name":"East Cavern"},{"name":"Riverwatch Well"}]],
    ]
    for group in groups:
        if y>sidebar.end.y-42.0:break
        _label(str(group[0]),Vector2(x,y),10,Color(.44,.22,.055))
        y+=16.0
        for entry in group[1]:
            if y>sidebar.end.y-32.0:break
            if not entry is Dictionary:continue
            _label("• %s"%str(entry.get("name","Site")),Vector2(x+5,y),10,Color(.19,.15,.09))
            y+=14.0
        y+=7.0


func _register_map_feature(screen_position:Vector2,radius:float,label:String,category:String,world_point:Vector2)->void:
    _map_features.append({"screen":screen_position,"radius":maxf(4.0,radius),"label":label,"category":category,"world":world_point})


func _draw_feature_tooltip(panel:Rect2)->void:
    var mouse:=get_local_mouse_position()
    if not panel.has_point(mouse):return
    var nearest:Dictionary={}
    var best:=INF
    for feature in _map_features:
        var distance:float=mouse.distance_to(feature.screen)
        if distance<=float(feature.radius)+7.0 and distance<best:
            best=distance;nearest=feature
    if nearest.is_empty():return
    var world_point:Vector2=nearest.world
    var title:=str(nearest.label)
    var subtitle:="%s   X %d  Z %d"%[str(nearest.category),roundi(world_point.x),roundi(world_point.y)]
    var width:=maxf(190.0,maxf(
        ThemeDB.fallback_font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x,
        ThemeDB.fallback_font.get_string_size(subtitle,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
    )+22.0)
    var box:=Rect2(mouse+Vector2(15,-54),Vector2(width,48))
    if box.end.x>panel.end.x:box.position.x=mouse.x-box.size.x-15
    if box.position.y<panel.position.y:box.position.y=mouse.y+15
    draw_rect(box,Color(.105,.075,.035,.96),true)
    draw_rect(box,Color(.91,.70,.27,.96),false,1.5)
    _label(title,box.position+Vector2(10,19),13,Color(.98,.84,.48))
    _label(subtitle,box.position+Vector2(10,38),10,Color(.87,.81,.67))


func _draw_scale_bar(panel: Rect2, world_size: float) -> void:
    var scale_world := 1000.0
    var length := scale_world / world_size * panel.size.x
    var start := panel.end - Vector2(length + 34.0, 48.0)
    var finish := start + Vector2(length, 0)
    draw_line(start, finish, Color(0.16, 0.09, 0.025), 3.0)
    draw_line(start - Vector2(0,5), start + Vector2(0,5), Color(0.16, 0.09, 0.025), 2.0)
    draw_line(finish - Vector2(0,5), finish + Vector2(0,5), Color(0.16, 0.09, 0.025), 2.0)
    _label("1 km", start + Vector2(length * .5 - 15.0, -8.0), 11, Color(0.18, 0.10, 0.03))


func _draw_teleport_cursor(panel: Rect2, world_size: float) -> void:
    var cursor := get_local_mouse_position()
    if not panel.has_point(cursor):
        return
    draw_line(cursor - Vector2(13,0), cursor + Vector2(13,0), Color(1.0,.82,.26,.95), 2.0)
    draw_line(cursor - Vector2(0,13), cursor + Vector2(0,13), Color(1.0,.82,.26,.95), 2.0)
    draw_circle(cursor, 6.0, Color(.22,.08,.02,.9), false, 2.0)
    var normalized := (cursor - panel.position) / panel.size
    var world_point := (normalized - Vector2(.5,.5)) * world_size
    var readout := "X %d   Z %d" % [roundi(world_point.x),roundi(world_point.y)]
    var box := Rect2(cursor + Vector2(15,-26), Vector2(124,24))
    if box.end.x > panel.end.x:
        box.position.x = cursor.x - box.size.x - 15
    draw_rect(box, Color(.15,.08,.025,.88), true)
    _label(readout, box.position + Vector2(7,17), 11, Color(1.0,.84,.37))


func _label(text: String, position: Vector2, font_size: int, color: Color) -> void:
    var halo:=Color(.97,.89,.71,.96) if color.get_luminance()<.48 else Color(.07,.045,.02,.92)
    for offset in [Vector2(-2,0),Vector2(2,0),Vector2(0,-2),Vector2(0,2),Vector2(-1.4,-1.4),Vector2(1.4,-1.4),Vector2(-1.4,1.4),Vector2(1.4,1.4)]:
        draw_string(ThemeDB.fallback_font,position+offset,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,halo)
    draw_string(ThemeDB.fallback_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _map_label(text_value:Variant,desired:Vector2,font_size:int,color:Color,panel:Rect2)->void:
    var value:=str(text_value)
    var measured:=ThemeDB.fallback_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
    var width:=maxf(18.0,measured.x+8.0)
    var height:=maxf(15.0,measured.y+5.0)
    var candidates:=[
        Vector2.ZERO,Vector2(0,17),Vector2(0,-17),Vector2(16,0),
        Vector2(-width-12,0),Vector2(15,19),Vector2(-width-12,19),
        Vector2(15,-19),Vector2(-width-12,-19),Vector2(0,34),
    ]
    for offset in candidates:
        var baseline:Vector2=desired+Vector2(offset)
        baseline.x=clampf(baseline.x,panel.position.x+8.0,panel.end.x-width-8.0)
        baseline.y=clampf(baseline.y,panel.position.y+height+8.0,panel.end.y-8.0)
        var rect:=Rect2(Vector2(baseline.x-4.0,baseline.y-height+2.0),Vector2(width,height))
        var overlaps:=false
        for occupied in _map_label_rects:
            if rect.grow(5.0).intersects(occupied.grow(2.0)):
                overlaps=true
                break
        if overlaps:continue
        _map_label_rects.append(rect)
        _label(value,baseline,font_size,color)
        return


func _map_point(point: Vector2, panel: Rect2, world_size: float) -> Vector2:
    return panel.position + (point / world_size + Vector2(0.5, 0.5)) * panel.size
