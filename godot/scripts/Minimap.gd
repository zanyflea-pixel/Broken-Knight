extends Control

var _profile: Dictionary = {}
var _player: Node3D
var _director: Node
var _height_sampler: Callable
var _terrain_texture: ImageTexture
var _terrain_center := Vector2(INF, INF)
var _pending_center:=Vector2.ZERO
var _pending_heights:=PackedFloat32Array()
var _pending_row:=-1
var _pending_color_row:=-1
var _terrain_image:Image
const TERRAIN_RESOLUTION:=64
var view_radius := 650.0
var _redraw_accumulator := 0.0
var _draw_profile_totals:Dictionary={}
var _draw_profile_counts:Dictionary={}
var _bridge_draw_cache:Array[Dictionary]=[]
var _volcanic_terrain_cache:Array[Dictionary]=[]
var _interaction_marker_cache:Array[Dictionary]=[]
var _story_marker_cache:Array[Dictionary]=[]
var _enemy_position_cache:Array[Vector3]=[]
var _enemy_cache_accumulator:=0.0
var _cached_layer_mode:=false
var _draw_anchor:=Vector2(INF,INF)


func _ready() -> void:
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func enable_cached_layer_mode()->void:
    _cached_layer_mode=true


func configure(profile: Dictionary, player: Node3D, director: Node = null, height_sampler: Callable = Callable()) -> void:
    _profile = profile
    _player = player
    _director = director
    _height_sampler = height_sampler
    if _cached_layer_mode and is_instance_valid(_player):
        _draw_anchor=Vector2(_player.global_position.x,_player.global_position.z)
    _prepare_draw_caches()
    if is_instance_valid(_player):
        _begin_terrain_refresh(Vector2(_player.global_position.x,_player.global_position.z))
    queue_redraw()


func _process(delta: float) -> void:
    if not visible:
        return
    if _cached_layer_mode:
        if _pending_row>=0:_advance_terrain_refresh(1)
        elif _pending_color_row>=0:_advance_terrain_color_refresh(2)
        return
    if _pending_row>=0:
        # Spread height sampling across more frames. The finished image keeps
        # the same 64x64 detail, but walking no longer receives a burst of 384
        # terrain queries on each refresh frame.
        _advance_terrain_refresh(1)
    elif _pending_color_row>=0:
        # Shade a few rows per frame as well. Previously all 4,096 pixels were
        # calculated and a new GPU texture was allocated on one movement frame.
        _advance_terrain_color_refresh(2)
    _enemy_cache_accumulator+=delta
    if _enemy_cache_accumulator>=.25:
        _enemy_cache_accumulator=0.0
        _refresh_dynamic_marker_cache()
    _redraw_accumulator += delta
    if _redraw_accumulator < 0.125:
        return
    _redraw_accumulator = 0.0
    if _pending_row<0 and _pending_color_row<0 and is_instance_valid(_player) and not _inside_dungeon():
        var player_pos:=Vector2(_player.global_position.x,_player.global_position.z)
        if player_pos.distance_to(_terrain_center)>=64.0:_begin_terrain_refresh(player_pos)
    queue_redraw()


func _begin_terrain_refresh(center:Vector2)->void:
    if not _height_sampler.is_valid():return
    _pending_center=center
    _pending_heights.resize(TERRAIN_RESOLUTION*TERRAIN_RESOLUTION)
    _pending_row=0
    _pending_color_row=-1
    _refresh_interaction_cache()


func _advance_terrain_refresh(rows:int)->void:
    if _pending_row<0:return
    var last_row:=mini(TERRAIN_RESOLUTION,_pending_row+rows)
    for y in range(_pending_row,last_row):
        for x in range(TERRAIN_RESOLUTION):
            var uv:=Vector2(float(x)/(TERRAIN_RESOLUTION-1),float(y)/(TERRAIN_RESOLUTION-1))*2.0-Vector2.ONE
            var world_point:=_pending_center+uv*view_radius
            _pending_heights[y*TERRAIN_RESOLUTION+x]=_height_sampler.call(world_point.x,world_point.y).y
    _pending_row=last_row
    if _pending_row>=TERRAIN_RESOLUTION:
        _pending_row=-1
        _terrain_image=Image.create(TERRAIN_RESOLUTION,TERRAIN_RESOLUTION,false,Image.FORMAT_RGBA8)
        _pending_color_row=0


func _advance_terrain_color_refresh(rows:int)->void:
    if _pending_color_row<0 or _terrain_image==null:return
    var last_row:=mini(TERRAIN_RESOLUTION,_pending_color_row+rows)
    for y in range(_pending_color_row,last_row):
        for x in range(TERRAIN_RESOLUTION):
            var uv := Vector2(float(x) / (TERRAIN_RESOLUTION - 1), float(y) / (TERRAIN_RESOLUTION - 1)) * 2.0 - Vector2.ONE
            if uv.length() > 1.0:
                _terrain_image.set_pixel(x, y, Color(0, 0, 0, 0))
                continue
            var h := _pending_heights[y * TERRAIN_RESOLUTION + x]
            var left := _pending_heights[y * TERRAIN_RESOLUTION + maxi(0, x - 1)]
            var right := _pending_heights[y * TERRAIN_RESOLUTION + mini(TERRAIN_RESOLUTION - 1, x + 1)]
            var up := _pending_heights[maxi(0, y - 1) * TERRAIN_RESOLUTION + x]
            var down := _pending_heights[mini(TERRAIN_RESOLUTION - 1, y + 1) * TERRAIN_RESOLUTION + x]
            var slope_light:=(left-right)*.020+(up-down)*.017
            var slope_strength:=minf(1.0,(absf(left-right)+absf(up-down))*.055)
            var shade:=clampf(.98+slope_light-slope_strength*.08,.64,1.22)
            var color := _terrain_color(h, _pending_center + uv * view_radius)
            if floorf(h / 24.0) != floorf(right / 24.0) or floorf(h / 24.0) != floorf(down / 24.0):
                shade *= 0.93
            _terrain_image.set_pixel(x, y, Color(color.r * shade, color.g * shade, color.b * shade, 0.97))
    _pending_color_row=last_row
    if _pending_color_row>=TERRAIN_RESOLUTION:_finish_terrain_refresh()


func _finish_terrain_refresh()->void:
    if _terrain_texture==null:
        _terrain_texture=ImageTexture.create_from_image(_terrain_image)
    else:
        _terrain_texture.update(_terrain_image)
    _terrain_center=_pending_center
    if _cached_layer_mode:_draw_anchor=_pending_center
    _pending_color_row=-1
    queue_redraw()


func _terrain_color(height: float, world_point: Vector2) -> Color:
    if _point_inside_ocean(world_point):
        var sea_variation:=sin(world_point.x*.0041+world_point.y*.0033)*.018
        return Color(.12+sea_variation,.34+sea_variation,.48+sea_variation*.7)
    var world_size: float = _profile.get("world_size",7200.0)
    var local_point:=world_point-_nearest_region_origin_for_point(world_point)
    var fine:=sin(world_point.x*.021)*sin(world_point.y*.017)
    var broad:=sin(world_point.x*.0031+world_point.y*.0022)*sin(world_point.y*.0043-world_point.x*.0015)
    var variation:=fine*.012+broad*.020
    var color:=Color(.36,.48,.25)
    if local_point.x > world_size*.16:
        color=Color(.56,.48,.24)
    elif local_point.x < -world_size*.20:
        color=Color(.25,.40,.25)
    if local_point.y > world_size*.18:
        color=color.lerp(Color(.27,.43,.38),.30)
    elif local_point.y < -world_size*.18:
        color=color.lerp(Color(.58,.39,.21),.34)
    var forest_influence:=0.0
    for forest in _profile.get("forest_regions",[]):
        var forest_center:Vector2=forest.get("center",Vector2.ZERO)
        var forest_radius:float=maxf(1.0,float(forest.get("radius",300.0)))
        forest_influence=maxf(forest_influence,1.0-smoothstep(forest_radius*.66,forest_radius*1.06,world_point.distance_to(forest_center)))
    color=color.lerp(Color(.105,.275,.17),forest_influence*.52)
    if height>34.0:color=color.lerp(Color(.43,.39,.29),clampf((height-34.0)/92.0,0.0,.68))
    if height>82.0:color=color.lerp(Color(.39,.38,.34),clampf((height-82.0)/70.0,0.0,.68))
    for volcano_value in _volcanic_terrain_cache:
        var volcano_center:Vector2=volcano_value.center
        var volcano_radius:float=volcano_value.radius
        var warped_distance:=world_point.distance_to(volcano_center)+sin(world_point.x*.0041+world_point.y*.0032)*90.0
        var ash_weight:=1.0-smoothstep(volcano_radius*.48,volcano_radius,warped_distance)
        color=color.lerp(Color(.285,.275,.235),ash_weight*.48)
    var snow_weight:=_snow_weight(world_point,height)
    if snow_weight>0.0:color=color.lerp(Color(.87,.91,.90),snow_weight)
    return Color(color.r+variation,color.g+variation,color.b+variation)


func _point_inside_ocean(world_point:Vector2)->bool:
    for basin_value in _profile.get("ocean_basins",[]):
        if not basin_value is Dictionary:continue
        var basin:Dictionary=basin_value
        if str(basin.get("kind",""))!="coast" or str(basin.get("edge","west"))!="west":continue
        var points:Array=basin.get("coast_points",[])
        if points.size()<2:continue
        if world_point.x<=_coastline_x_at_z(world_point.y,points):return true
    return false


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


func _nearest_region_origin_for_point(world_point:Vector2)->Vector2:
    var nearest:=Vector2.ZERO
    var best:=INF
    for summary_value in _profile.get("region_summaries",[]):
        if not summary_value is Dictionary:continue
        var origin:Vector2=summary_value.get("origin",Vector2.ZERO)
        var distance:=world_point.distance_squared_to(origin)
        if distance<best:best=distance;nearest=origin
    return nearest


func _snow_weight(world_point:Vector2,height:float)->float:
    var weight:=0.0
    for chain_value in _profile.get("mountain_chains",[]):
        if not chain_value is Dictionary:continue
        var chain:Dictionary=chain_value
        if not chain.has("snow_line"):continue
        var center:Vector2=chain.get("center",Vector2.ZERO)
        var delta:Vector2=(world_point-center).rotated(-float(chain.get("angle",0.0)))
        var half_length:=maxf(1.0,float(chain.get("length",1000.0))*.5)
        var half_width:=maxf(1.0,float(chain.get("width",500.0))*.72)
        var footprint:=1.0-smoothstep(.76,1.08,Vector2(delta.x/half_length,delta.y/half_width).length())
        var altitude:=smoothstep(float(chain.get("snow_line",120.0))-8.0,float(chain.get("snow_line",120.0))+32.0,height)
        weight=maxf(weight,footprint*altitude*.88)
    return weight


func _draw() -> void:
    if _profile.is_empty() or not is_instance_valid(_player):
        return
    var center := size * 0.5
    var radius := minf(size.x, size.y) * 0.455
    if not _cached_layer_mode:
        draw_circle(center,radius+10,Color(.025,.030,.038,.98))
        draw_circle(center,radius+7,Color(.64,.43,.16,1.0))
        draw_circle(center,radius+3,Color(.13,.16,.19,1.0))
        draw_circle(center,radius,Color(.42,.52,.28,1.0))
    if _inside_dungeon():
        _draw_dungeon_minimap(center,radius)
        draw_arc(center,radius,0,TAU,112,Color(.19,.11,.035),4.0,true)
        draw_arc(center,radius-6,0,TAU,112,Color(.76,.57,.24),1.5,true)
        return
    if _terrain_texture:
        var player_pos:=_draw_anchor if _cached_layer_mode and is_finite(_draw_anchor.x) else Vector2(_player.global_position.x,_player.global_position.z)
        var cache_offset:=(_terrain_center-player_pos)/view_radius*radius
        draw_texture_rect(_terrain_texture, Rect2(center - Vector2.ONE * radius + cache_offset, Vector2.ONE * radius * 2.0), false)
    if not _cached_layer_mode:
        for ring in [0.33, 0.66, 1.0]:
            draw_arc(center, radius * ring, 0, TAU, 72, Color(0.20, 0.13, 0.05, 0.22), 1.0)
    _profile_draw_call("forests",func():_draw_local_forests(center,radius))
    _profile_draw_call("rivers",func():_corridors(_profile.get("river_corridors",[]),center,radius,"river"))
    _profile_draw_call("roads",func():_corridors(_profile.get("road_corridors",[]),center,radius,"road"))
    _profile_draw_call("trails",func():_corridors(_profile.get("trail_corridors",[]),center,radius,"trail"))
    _profile_draw_call("water",func():_draw_water_sites(center,radius))
    _profile_draw_call("waterfalls",func():_draw_waterfalls(center,radius))
    _profile_draw_call("bridges",func():_draw_bridges(center,radius))
    _profile_draw_call("settlements",func():_draw_settlements(center,radius))
    _profile_draw_call("geology",func():_draw_major_geology_sites(center,radius))
    _profile_draw_call("map_sites",func():_draw_starter_map_sites(center,radius))
    _profile_draw_call("caves_camps",func():_draw_caves_and_camps(center,radius))
    _profile_draw_call("interactions",func():_draw_interactions(center,radius))
    _profile_draw_call("story",func():_draw_story_markers(center,radius))
    if not _cached_layer_mode:
        _profile_draw_call("enemies",func():_draw_enemies(center,radius))
        _draw_player(center)
        draw_arc(center, radius, 0, TAU, 112, Color(0.19, 0.11, 0.035), 4.0, true)
        draw_arc(center, radius - 6, 0, TAU, 112, Color(0.76, 0.57, 0.24), 1.5, true)
        _cardinal("N", center + Vector2(-5, -radius + 16))
        _cardinal("E", center + Vector2(radius - 17, 5))
        _cardinal("S", center + Vector2(-4, radius - 7))
        _cardinal("W", center + Vector2(-radius + 8, 5))
        _draw_scale_bar(center,radius)


func _profile_draw_call(label:String,callback:Callable)->void:
    if OS.get_environment("BROKEN_KNIGHT_PROFILE_MINIMAP")!="1":
        callback.call()
        return
    var started:=Time.get_ticks_usec()
    callback.call()
    _draw_profile_totals[label]=int(_draw_profile_totals.get(label,0))+Time.get_ticks_usec()-started
    _draw_profile_counts[label]=int(_draw_profile_counts.get(label,0))+1


func get_draw_profile()->Dictionary:
    var result:Dictionary={}
    for label in _draw_profile_totals:
        result[label]=float(_draw_profile_totals[label])/float(maxi(1,int(_draw_profile_counts.get(label,0))))
    return result


func reset_draw_profile()->void:
    _draw_profile_totals.clear()
    _draw_profile_counts.clear()


func _inside_dungeon()->bool:
    # Dungeon rooms historically lived beyond X=7800, but the seamless world
    # now extends through that range into the Eastern Marches. Interior mode is
    # the authoritative state; coordinates are no longer a valid classifier.
    return is_instance_valid(_player) and _player.has_method("is_interior_mode") and _player.is_interior_mode()


func _draw_dungeon_minimap(center:Vector2,radius:float)->void:
    draw_circle(center,radius,Color(.065,.060,.052))
    var player_pos:=Vector2(_player.global_position.x,_player.global_position.z)
    var base:=Vector2(8000,0)
    var title:="RIVERWATCH WELL"
    var half_size:=Vector2(42,66)
    if player_pos.x>8600:
        base=Vector2(8700,0);title="BARROWFEN OSSUARY";half_size=Vector2(54,88)
    elif player_pos.x>8310:
        base=Vector2(8420,0);title="EAST CAVERN";half_size=Vector2(64,95)
    elif player_pos.x>8100:
        base=Vector2(8200,0);title="WEST CAVERN";half_size=Vector2(64,95)
    var scale:=minf((radius-20.0)/half_size.x,(radius-24.0)/half_size.y)
    var room_rect:=Rect2(center-half_size*scale,half_size*2.0*scale)
    draw_rect(room_rect,Color(.21,.19,.16),true)
    draw_rect(room_rect,Color(.70,.55,.29),false,2.0)
    if title=="BARROWFEN OSSUARY":
        for z in [50.0,15.0,-22.0,-58.0]:
            var wall_y:float=center.y+(z-(player_pos.y-base.y))*scale
            draw_line(Vector2(room_rect.position.x+3,wall_y),Vector2(room_rect.end.x-3,wall_y),Color(.58,.51,.35),2.0)
        for chamber in [Vector2(-37,36),Vector2(38,-1),Vector2(-36,-38),Vector2(0,-74)]:
            var chamber_point:=center+Vector2(chamber.x-(player_pos.x-base.x),chamber.y-(player_pos.y-base.y))*scale
            draw_circle(chamber_point,4.0,Color(.30,.55,.62));draw_circle(chamber_point,4.0,Color(.82,.68,.30),false,1.0)
    elif title!="RIVERWATCH WELL":
        for z in [52.0,14.0,-32.0,-72.0]:
            var room_center:=center+Vector2(0,(z-(player_pos.y-base.y))*scale)
            var room_size:=Vector2(half_size.x*1.62,16.0)*scale
            draw_rect(Rect2(room_center-room_size*.5,room_size),Color(.30,.27,.22),true)
            draw_rect(Rect2(room_center-room_size*.5,room_size),Color(.62,.47,.25),false,1.2)
        for door_z in [52.0]:
            var door_y:float=center.y+(door_z-(player_pos.y-base.y))*scale
            draw_line(Vector2(center.x-7,door_y),Vector2(center.x+7,door_y),Color(1.0,.62,.16),3.0)
    else:
        var route_cells:=[Vector2i(4,12),Vector2i(4,11),Vector2i(4,10),Vector2i(3,10),Vector2i(2,10),Vector2i(1,10),Vector2i(1,9),Vector2i(1,8),Vector2i(1,7),Vector2i(2,7),Vector2i(3,7),Vector2i(4,7),Vector2i(5,7),Vector2i(6,7),Vector2i(7,7),Vector2i(7,6),Vector2i(7,5),Vector2i(7,4),Vector2i(6,4),Vector2i(5,4),Vector2i(4,4),Vector2i(3,4),Vector2i(3,3),Vector2i(3,2),Vector2i(3,1),Vector2i(4,1),Vector2i(5,1),Vector2i(3,0),Vector2i(4,0),Vector2i(5,0),Vector2i(0,8),Vector2i(4,8),Vector2i(5,8),Vector2i(8,5),Vector2i(2,4),Vector2i(1,4)]
        for cell in route_cells:
            var world_cell:=Vector2(-36.0+float(cell.x)*9.0,-54.0+float(cell.y)*9.0)
            var p:=center+Vector2(world_cell.x-(player_pos.x-base.x),world_cell.y-(player_pos.y-base.y))*scale
            var cell_size:=Vector2.ONE*8.9*scale
            draw_rect(Rect2(p-cell_size*.5,cell_size),Color(.39,.35,.28),true)
            draw_rect(Rect2(p-cell_size*.5,cell_size),Color(.72,.58,.32),false,.8)
        var gate_y:float=center.y+(-40.5-(player_pos.y-base.y))*scale
        var gate_x:float=center.x+(-9.0-(player_pos.x-base.x))*scale
        draw_line(Vector2(gate_x-4.2*scale,gate_y),Vector2(gate_x+4.2*scale,gate_y),Color(1.0,.62,.16),3.0)
    if is_instance_valid(_director):
        for enemy_position in _director.get_minion_positions():
            if absf(enemy_position.x-base.x)>half_size.x+3.0 or absf(enemy_position.z-base.y)>half_size.y+3.0:continue
            var relative:=Vector2(enemy_position.x-player_pos.x,enemy_position.z-player_pos.y)*scale
            var p:=center+relative
            if p.distance_to(center)<radius-6.0:draw_circle(p,2.6,Color(.92,.12,.035))
    _draw_player(center)
    var title_position:=center+Vector2(-radius*.66,-radius*.73)
    draw_string(ThemeDB.fallback_font,title_position+Vector2(1,1),title,HORIZONTAL_ALIGNMENT_CENTER,radius*1.32,11,Color(.02,.015,.01,.95))
    draw_string(ThemeDB.fallback_font,title_position,title,HORIZONTAL_ALIGNMENT_CENTER,radius*1.32,11,Color(.98,.82,.44))
    var subtitle_position:=center+Vector2(-radius*.66,radius*.72)
    draw_string(ThemeDB.fallback_font,subtitle_position+Vector2(1,1),"DUNGEON MAP",HORIZONTAL_ALIGNMENT_CENTER,radius*1.32,9,Color(.02,.015,.01,.95))
    draw_string(ThemeDB.fallback_font,subtitle_position,"DUNGEON MAP",HORIZONTAL_ALIGNMENT_CENTER,radius*1.32,9,Color(.84,.77,.67))


func _corridors(corridors: Array, center: Vector2, radius: float, kind: String) -> void:
    if kind=="river":
        for corridor in corridors:
            var authored_width:=float(corridor.get("width",48.0))
            var source_width:=float(corridor.get("source_width",authored_width))
            var mouth_width:=float(corridor.get("mouth_width",authored_width))
            var pixels:=maxf(1.5,lerpf(source_width,mouth_width,.5)*.66/view_radius*radius)
            for run in _corridor_runs(corridor.get("points",[]),center,radius):
                draw_polyline(run,Color(.08,.20,.23,.98),pixels+3.0,true)
                draw_polyline(run,Color(.30,.69,.78,1.0),pixels,true)
                draw_polyline(run,Color(.70,.90,.91,.42),maxf(1.0,pixels*.16),true)
        return
    if kind=="road":
        for route_class in ["secondary","major"]:
            for corridor in corridors:
                if str(corridor.get("route_class","secondary"))!=route_class:continue
                var physical_width:=float(corridor.get("width",14.0))*.48
                var pixel_floor:=3.3 if route_class=="major" else 2.0
                var pixels:=maxf(pixel_floor,physical_width/view_radius*radius)
                var outline:=Color(.16,.075,.022,.98) if route_class=="major" else Color(.18,.11,.045,.92)
                var fill:=Color(.92,.64,.25,1.0) if route_class=="major" else Color(.68,.47,.24,.97)
                for run in _corridor_runs(corridor.get("points",[]),center,radius):
                    draw_polyline(run,outline,pixels+(2.8 if route_class=="major" else 2.1),true)
                    draw_polyline(run,fill,pixels,true)
                    if route_class=="major":draw_polyline(run,Color(.99,.83,.48,.52),maxf(1.0,pixels*.20),true)
        return
    for corridor in corridors:
        var pixels:=maxf(1.5,float(corridor.get("width",5.0))*.48/view_radius*radius)
        for run in _corridor_runs(corridor.get("points",[]),center,radius):
            draw_polyline(run,Color(.13,.075,.025,.66),pixels+1.2,true)
            draw_polyline(run,Color(.72,.52,.26,.82),maxf(1.0,pixels*.58),true)


func _corridor_runs(world_points:Array,center:Vector2,radius:float)->Array[PackedVector2Array]:
    var result:Array[PackedVector2Array]=[]
    if world_points.size()<2:return result
    var points:Array[Vector2]=[]
    for point in world_points:points.append(_local_point(point,center,radius))
    var current:=PackedVector2Array()
    for index in range(points.size()-1):
        var clipped:=_clip_segment_to_circle(points[index],points[index+1],center,radius)
        if clipped.is_empty():
            if current.size()>1:result.append(current)
            current=PackedVector2Array()
            continue
        var a:Vector2=clipped[0]
        var b:Vector2=clipped[1]
        if current.is_empty() or not current[-1].is_equal_approx(a):
            if current.size()>1:result.append(current)
            current=PackedVector2Array([a])
        current.append(b)
    if current.size()>1:result.append(current)
    return result


func _draw_dashed_segment(a:Vector2,b:Vector2,color:Color,width:float,dash_length:float,gap_length:float)->void:
    var segment:=b-a
    var length:=segment.length()
    if length<=.01:return
    var direction:=segment/length
    var cursor:=0.0
    while cursor<length:
        var dash_end:=minf(cursor+dash_length,length)
        draw_line(a+direction*cursor,a+direction*dash_end,color,width,true)
        cursor+=dash_length+gap_length


func _clip_segment_to_circle(a: Vector2, b: Vector2, center: Vector2, radius: float) -> Array[Vector2]:
    var inside_a := a.distance_to(center) <= radius
    var inside_b := b.distance_to(center) <= radius
    if not inside_a and not inside_b:
        var closest := Geometry2D.get_closest_point_to_segment(center, a, b)
        if closest.distance_to(center) > radius:
            return []
    if not inside_a:
        a = center + (a - center).normalized() * radius
    if not inside_b:
        b = center + (b - center).normalized() * radius
    return [a, b]


func _draw_local_forests(center: Vector2, radius: float) -> void:
    for region_index in range(_profile.get("forest_regions",[]).size()):
        var region:Dictionary=_profile.get("forest_regions",[])[region_index]
        var region_center: Vector2 = region.get("center", Vector2.ZERO)
        var region_radius: float = region.get("radius", 300.0)
        var region_pixel_radius:=region_radius/view_radius*radius
        var p:=_local_point(region_center,center,radius)
        if p.distance_to(center)>radius+region_pixel_radius:
            continue

        # One readable canopy footprint replaces hundreds of individual tree
        # circles. Rebuilding those tiny commands every minimap tick was the
        # largest source of walking-frame spikes after detailed world passes.
        # Only submit a filled polygon when its whole radial footprint is
        # inside the circular map. Projecting every outer vertex onto the map
        # edge produced invalid polygons; triangulating each wedge avoided the
        # error but multiplied canvas commands during a walking refresh.
        if p.distance_to(center)+region_pixel_radius<=radius-4.0:
            var footprint:=PackedVector2Array()
            for edge_index in range(18):
                var angle:=TAU*float(edge_index)/18.0+float(region_index)*.31
                var irregularity:=.86+sin(angle*3.0+float(region_index))*.10+sin(angle*7.0)*.04
                footprint.append(p+Vector2(cos(angle),sin(angle))*region_pixel_radius*irregularity)
            draw_colored_polygon(footprint,Color(.055,.205,.085,.68))
            var closed_footprint:=footprint.duplicate()
            closed_footprint.append(footprint[0])
            draw_polyline(closed_footprint,Color(.035,.115,.050,.72),1.2,true)

        # Sparse crowns keep forests legible as forests without turning the
        # minimap into a recurring draw-command generator.
        for tree_index in range(6):
            var angle:=float(tree_index)*2.399963+float(region_index)*.43
            var spread:=region_pixel_radius*sqrt((float(tree_index)+.5)/7.0)*.63
            var tree_p:=p+Vector2(cos(angle),sin(angle))*spread
            if tree_p.distance_to(center)>=radius-6.0:
                continue
            var tree_size:=1.45+float(tree_index%3)*.28
            draw_circle(tree_p+Vector2(.45,.55),tree_size,Color(.015,.055,.022,.36))
            draw_circle(tree_p,tree_size*.82,Color(.11,.35,.13,.88))


func _draw_water_sites(center: Vector2, radius: float) -> void:
    for pond in _profile.get("pond_sites", []):
        var pond_center: Vector2 = pond.get("position", Vector2.ZERO)
        var p := _local_point(pond_center, center, radius)
        if p.distance_to(center) < radius:
            var pond_radius := maxf(3.5, float(pond.get("radius", 60.0)) * 1.18 / view_radius * radius)
            var outline := PackedVector2Array()
            for i in range(24):
                var angle := TAU * float(i) / 24.0
                var irregularity := 1.0 + sin(angle * 3.0 + pond_center.x * 0.0017) * 0.11 + sin(angle * 7.0 + pond_center.y * 0.0011) * 0.055
                outline.append(p + Vector2(cos(angle), sin(angle)) * pond_radius * irregularity)
            draw_colored_polygon(outline, Color(0.26, 0.62, 0.70))


func _draw_waterfalls(center:Vector2,radius:float)->void:
    for waterfall in _profile.get("waterfall_sites",[]):
        var world_point:Vector2=waterfall.get("position",Vector2.ZERO)
        var p:=_local_point(world_point,center,radius)
        if p.distance_to(center)>=radius-5.0:continue
        var segment:=_nearest_corridor_segment(world_point,_profile.get("river_corridors",[]))
        var tangent:Vector2=segment.get("direction",Vector2(1,0))
        var normal:=Vector2(-tangent.y,tangent.x)
        for offset in [-2.4,0.0,2.4]:
            var tip:=p+tangent*(float(offset)+1.7)
            draw_line(p+tangent*float(offset)-normal*2.5,tip,Color(.78,.93,.94),1.35,true)
            draw_line(p+tangent*float(offset)+normal*2.5,tip,Color(.12,.42,.52),1.35,true)


func _draw_caves_and_camps(center:Vector2,radius:float)->void:
    for camp in _profile.get("camp_sites",[]):
        var p:=_local_point(camp.get("position",Vector2.ZERO),center,radius)
        if p.distance_to(center)<radius-8.0:
            draw_colored_polygon(PackedVector2Array([p+Vector2(0,-4),p+Vector2(-4,4),p+Vector2(4,4)]),Color(.90,.40,.10))
    for cave_data in [[Vector2(-2700,1700),"W"],[Vector2(2620,-1800),"E"]]:
        var p:=_local_point(cave_data[0],center,radius)
        if p.distance_to(center)<radius-8.0:
            draw_arc(p,5.0,PI,TAU,14,Color(.10,.055,.02),2.5)


func _draw_bridges(center: Vector2, radius: float) -> void:
    for bridge in _bridge_draw_cache:
        var world_point:Vector2=bridge.get("position",Vector2.ZERO)
        var p := _local_point(world_point, center, radius)
        if p.distance_to(center) < radius - 4:
            var tangent:Vector2=bridge.get("tangent",Vector2(0,1))
            var normal:=Vector2(-tangent.y,tangent.x)
            var half_span:=maxf(5.0,float(bridge.get("span",46.0))/view_radius*radius*.5)
            var half_width:=3.0
            var corners:=PackedVector2Array([p-tangent*half_span-normal*half_width,p+tangent*half_span-normal*half_width,p+tangent*half_span+normal*half_width,p-tangent*half_span+normal*half_width])
            draw_colored_polygon(corners,Color(.25,.12,.035))
            draw_polyline(corners,Color(.95,.76,.31),1.3,true)


func _nearest_corridor_segment(point:Vector2,corridors:Array)->Dictionary:
    var nearest:Dictionary={}
    var best:=INF
    for corridor in corridors:
        var points:Array=corridor.get("points",[])
        for i in range(points.size()-1):
            var a:Vector2=points[i];var b:Vector2=points[i+1]
            var closest:=Geometry2D.get_closest_point_to_segment(point,a,b)
            var distance:=point.distance_squared_to(closest)
            if distance<best:
                best=distance;nearest={"direction":(b-a).normalized(),"width":float(corridor.get("width",10.0))}
    return nearest


func _draw_settlements(center: Vector2, radius: float) -> void:
    var sites: Array = [_profile.get("spawn_site", {})]
    sites.append_array(_profile.get("town_sites", []))
    for site in sites:
        var p := _local_point(site.get("position", Vector2.ZERO), center, radius)
        var distance := p.distance_to(center)
        if distance < radius - 10:
            var footprint:=maxf(3.0,float(site.get("radius",75.0))/view_radius*radius)
            if site.get("capital", false):
                if distance<radius-footprint-5.0:
                    _draw_local_crownspire(site.get("position",Vector2.ZERO),center,radius)
                else:
                    draw_rect(Rect2(p-Vector2(5,4),Vector2(10,8)),Color(.58,.15,.08,.96),true)
            elif site.get("starter",false):
                _draw_local_riverwatch(site,center,radius)
            else:
                draw_circle(p,footprint,Color(.69,.50,.27,.20))
                draw_arc(p,footprint,0,TAU,32,Color(.25,.13,.04,.48),1.0)
                for i in range(10):
                    var angle:=float(i)*TAU/10.0+.27
                    var house:=p+Vector2(cos(angle),sin(angle))*footprint*.60
                    draw_rect(Rect2(house-Vector2(1.8,1.3),Vector2(3.6,2.6)),Color(.53,.24,.08,.94),true)
                draw_rect(Rect2(p - Vector2(3.5, 3), Vector2(7, 6)), Color(0.78, 0.25, 0.09), true)
            if distance > 30.0 and distance < radius * 0.76:
                _small_label(site.get("name", "Town"), p + Vector2(7, 3))
        else:
            var edge := center + (p - center).normalized() * (radius - 10)
            draw_colored_polygon(PackedVector2Array([edge + Vector2(0, -5), edge + Vector2(-4, 4), edge + Vector2(4, 4)]), Color(0.78, 0.25, 0.09))


func _draw_local_riverwatch(site:Dictionary,center:Vector2,radius:float)->void:
    var town_center:Vector2=site.get("position",Vector2.ZERO)
    var center_px:=_local_point(town_center,center,radius)
    var footprint:=maxf(7.0,float(site.get("radius",96.0))/view_radius*radius)
    draw_circle(center_px,footprint,Color(.69,.50,.27,.16))
    draw_arc(center_px,footprint,0,TAU,32,Color(.25,.13,.04,.43),1.0)
    var offsets:=[Vector2(-40,-58),Vector2(-42,-20),Vector2(-42,78),Vector2(40,-57),Vector2(42,-22),Vector2(40,42),Vector2(42,80)]
    for i in range(offsets.size()):
        var house:=_local_point(town_center+offsets[i],center,radius)
        var house_size:=Vector2(3.6+float(i%3)*.35,2.7+float(i%2)*.3)
        draw_rect(Rect2(house-house_size*.5,house_size),Color(.55,.25,.075,.96),true)
        draw_rect(Rect2(house-house_size*.5,house_size),Color(.20,.105,.03,.82),false,.7)
    var green:=_local_point(town_center+Vector2(-34,30),center,radius)
    draw_circle(green,2.8,Color(.66,.63,.52,.96))
    draw_circle(green,1.3,Color(.20,.49,.57,.98))
    for side in [-1.0,1.0]:
        var field:=_local_point(town_center+Vector2(62.0*float(side),116),center,radius)
        draw_rect(Rect2(field-Vector2(2.4,3.2),Vector2(4.8,6.4)),Color(.50,.43,.13,.74),true)
        draw_rect(Rect2(field-Vector2(2.4,3.2),Vector2(4.8,6.4)),Color(.26,.18,.06,.72),false,.7)


func _draw_starter_map_sites(center:Vector2,radius:float)->void:
    for site_value in _profile.get("map_sites",[]):
        if not site_value is Dictionary:continue
        var site:Dictionary=site_value
        var kind:=str(site.get("kind",""))
        if kind not in ["waystation","watchtower","glacier","crevasse","ruin","lair","volcano"]:continue
        var world_point:Vector2=site.get("position",Vector2.ZERO)
        var p:=_local_point(world_point,center,radius)
        if p.distance_to(center)>=radius-8.0:continue
        if kind=="waystation":
            draw_rect(Rect2(p-Vector2(4.5,3.3),Vector2(9,6.6)),Color(.55,.27,.08,.96),true)
            draw_rect(Rect2(p-Vector2(4.5,3.3),Vector2(9,6.6)),Color(.20,.10,.03,.96),false,1.0)
            draw_line(p+Vector2(5,-6),p+Vector2(5,5),Color(.28,.16,.05,.96),1.4)
            draw_colored_polygon(PackedVector2Array([p+Vector2(5,-6),p+Vector2(10,-4),p+Vector2(5,-1)]),Color(.75,.22,.07,.98))
            if p.distance_to(center)>28.0:_small_label(str(site.get("name","Waystation")),p+Vector2(10,10))
        elif kind=="watchtower":
            draw_rect(Rect2(p-Vector2(3,3),Vector2(6,6)),Color(.43,.35,.23,.98),true)
            draw_colored_polygon(PackedVector2Array([p+Vector2(0,-7),p+Vector2(-5,-2),p+Vector2(5,-2)]),Color(.61,.17,.06,.98))
            draw_circle(p+Vector2(0,-7),1.7,Color(1.0,.48,.08,.96))
        elif kind=="glacier":
            draw_colored_polygon(PackedVector2Array([p+Vector2(-6,5),p+Vector2(-3,-6),p,p+Vector2(3,-7),p+Vector2(7,5)]),Color(.76,.91,.94,.98))
            draw_line(p+Vector2(-3,0),p+Vector2(0,6),Color(.23,.62,.72),1.4,true)
        elif kind=="crevasse":
            draw_polyline(PackedVector2Array([p+Vector2(-1,-7),p+Vector2(3,-3),p+Vector2(-2,1),p+Vector2(3,6)]),Color(.10,.37,.48,.98),2.8,true)
        elif kind=="lair":
            for index in range(6):
                var angle:=TAU*float(index)/6.0+.20
                draw_circle(p+Vector2(cos(angle),sin(angle))*4.3,1.55,Color(.17,.23,.23,.98))
            draw_circle(p,2.0,Color(.31,.72,.77,.98))
        elif kind=="volcano":
            draw_colored_polygon(PackedVector2Array([
                p+Vector2(-7,5),p+Vector2(-4,0),p+Vector2(-2,-6),
                p+Vector2(0,-4),p+Vector2(2,-6),p+Vector2(4,0),p+Vector2(7,5),
            ]),Color(.22,.19,.16,.98))
            draw_line(p+Vector2(-2,-6),p+Vector2(2,-6),Color(.07,.055,.045,.98),1.8,true)
        else:
            draw_polyline(PackedVector2Array([p+Vector2(-5,-4),p+Vector2(5,-4),p+Vector2(4,5),p+Vector2(-5,5)]),Color(.30,.27,.23,.98),1.8,true)


func _major_geology_family(site:Dictionary)->String:
    if str(site.get("kind",""))!="outcrop":return ""
    var site_name:=str(site.get("name","")).to_lower()
    if "sea stack" in site_name or "shore" in site_name:return "coastal"
    if "basalt" in site_name or "ember" in site_name or "cinder" in site_name:return "basalt"
    if "crown" in site_name or "crag" in site_name or "moraine" in site_name:return "glacial"
    return ""


func _draw_major_geology_sites(center:Vector2,radius:float)->void:
    for site_value in _profile.get("landmark_sites",[]):
        if not site_value is Dictionary:continue
        var site:Dictionary=site_value
        var family:=_major_geology_family(site)
        if family.is_empty():continue
        var p:=_local_point(site.get("position",Vector2.ZERO),center,radius)
        if p.distance_to(center)>=radius-7.0:continue
        var ink:=Color(.24,.23,.21,.96)
        match family:
            "basalt":
                for index in range(4):
                    var height:=4.0+float((index*3)%4)
                    draw_rect(Rect2(p+Vector2(-5.0+float(index)*2.7,-height),Vector2(2.0,height+3.0)),ink,true)
            "glacial":
                draw_colored_polygon(PackedVector2Array([p+Vector2(-7,5),p+Vector2(-2,-7),p+Vector2(1,-3),p+Vector2(4,-6),p+Vector2(7,5)]),Color(.48,.55,.56,.98))
                draw_colored_polygon(PackedVector2Array([p+Vector2(-4,-2),p+Vector2(-2,-7),p+Vector2(0,-3),p+Vector2(1,-3),p+Vector2(4,-6),p+Vector2(5,-1)]),Color(.88,.89,.83,.96))
            "coastal":
                draw_polyline(PackedVector2Array([p+Vector2(-6,5),p+Vector2(-5,-2),p+Vector2(0,-7),p+Vector2(5,-2),p+Vector2(6,5)]),ink,2.6,true)
                draw_arc(p+Vector2(0,4),3.8,PI,TAU,14,Color(.64,.61,.52,.92),1.0,true)


func _draw_local_crownspire(capital_center:Vector2,center:Vector2,radius:float)->void:
    var scale:=radius/view_radius
    var city:=_local_point(capital_center,center,radius)
    var wall:=Color(.69,.67,.57,.96)
    var paving:=Color(.75,.69,.55,.74)
    var half:=190.0*scale
    var gate:=16.0*scale
    draw_line(city+Vector2(-half,-half),city+Vector2(half,-half),wall,2.2,true)
    draw_line(city+Vector2(-half,-half),city+Vector2(-half,half),wall,2.2,true)
    draw_line(city+Vector2(half,-half),city+Vector2(half,half),wall,2.2,true)
    draw_line(city+Vector2(-half,half),city+Vector2(-gate,half),wall,2.2,true)
    draw_line(city+Vector2(gate,half),city+Vector2(half,half),wall,2.2,true)
    for corner in [Vector2(-half,-half),Vector2(half,-half),Vector2(-half,half),Vector2(half,half)]:
        draw_rect(Rect2(city+corner-Vector2.ONE*2.3,Vector2.ONE*4.6),Color(.34,.31,.27,.98),true)
    draw_line(city+Vector2(0,-32.0*scale),city+Vector2(0,260.0*scale),paving,3.4,true)
    draw_line(city+Vector2(-125.0*scale,28.0*scale),city+Vector2(125.0*scale,28.0*scale),paving,2.8,true)
    draw_circle(city+Vector2(0,38.0*scale),maxf(3.2,7.0*scale),Color(.70,.60,.40,.86))
    var plots:Array=[Vector2(-118,-15),Vector2(-82,-20),Vector2(-120,48),Vector2(-80,66),Vector2(82,-18),Vector2(122,-8),Vector2(82,55),Vector2(124,72),Vector2(-132,118),Vector2(-88,132),Vector2(-45,115),Vector2(46,118),Vector2(88,136),Vector2(132,116),Vector2(-145,-88),Vector2(-110,-118),Vector2(112,-112),Vector2(148,-82)]
    for i in range(plots.size()):
        var plot:Vector2=plots[i]
        var house:Vector2=city+plot*scale
        var house_size:=Vector2(maxf(2.5,(12.0+float(i%4)*2.2)*scale),maxf(2.0,(9.5+float(i%3))*scale))
        draw_rect(Rect2(house-house_size*.5,house_size),Color(.46+.035*float(i%3),.18,.065,.96),true)
    var castle:=city+Vector2(0,-92)*scale
    var bailey_size:=Vector2(142,118)*scale
    draw_rect(Rect2(castle-bailey_size*.5,bailey_size),Color(.65,.63,.56,.38),true)
    draw_rect(Rect2(castle-bailey_size*.5,bailey_size),wall,false,1.6)
    for corner_value in [Vector2(-71,-59),Vector2(71,-59),Vector2(-71,59),Vector2(71,59)]:
        var corner:Vector2=corner_value
        var tower:Vector2=castle+corner*scale
        draw_rect(Rect2(tower-Vector2.ONE*2.2,Vector2.ONE*4.4),Color(.28,.26,.23,.98),true)
    var keep:=castle+Vector2(0,-8)*scale
    var keep_size:=Vector2(maxf(7.0,58.0*scale),maxf(5.5,44.0*scale))
    draw_rect(Rect2(keep-keep_size*.5,keep_size),Color(.48,.075,.055,.98),true)
    draw_rect(Rect2(keep-keep_size*.5,keep_size),Color(.18,.10,.045,.98),false,1.0)


func _draw_enemies(center: Vector2, radius: float) -> void:
    var shown:=0
    for position in _enemy_position_cache:
        var p := _local_point(Vector2(position.x, position.z), center, radius)
        if p.distance_to(center) < radius:
            draw_circle(p, 3.5, Color(0.32, 0.02, 0.015))
            draw_circle(p, 2.2, Color(0.88, 0.08, 0.035))
            shown+=1
            if shown>=16:return


func _draw_interactions(center:Vector2,radius:float)->void:
    for marker in _interaction_marker_cache:
        var position:Vector3=marker.position
        var p:=_local_point(Vector2(position.x,position.z),center,radius)
        if p.distance_to(center)>=radius-5.0:continue
        match marker.action:
            "craft":
                draw_rect(Rect2(p-Vector2(3,3),Vector2(6,6)),Color(.96,.62,.14),true)
                draw_line(p+Vector2(-4,4),p+Vector2(4,-4),Color(.25,.13,.04),1.4)
            "chop":draw_colored_polygon(PackedVector2Array([p+Vector2(0,-4),p+Vector2(-3,3),p+Vector2(3,3)]),Color(.16,.42,.12))
            "gather":draw_circle(p,2.2,Color(.54,.80,.28))


func _draw_story_markers(center:Vector2,radius:float)->void:
    for marker in _story_marker_cache:
        var position:Vector3=marker.get("position",Vector3.ZERO)
        var p:=_local_point(Vector2(position.x,position.z),center,radius)
        var kind:=str(marker.get("kind","story_site"))
        var primary:=bool(marker.get("primary",false))
        # MinimapShell moves this cached cartography layer under a separate
        # live overlay. Keep the primary objective out of the cached texture;
        # otherwise its edge arrow drifts with the terrain anchor.
        if primary and _cached_layer_mode:continue
        var screen_distance:=p.distance_to(center)
        if screen_distance>=radius-7.0:
            if primary:_draw_offscreen_objective(center,radius,Vector2(position.x,position.z))
            continue
        if kind=="story_objective":
            var vertical:=8.0 if primary else 5.0
            var horizontal:=6.5 if primary else 4.2
            var diamond:=PackedVector2Array([p+Vector2(0,-vertical),p+Vector2(horizontal,0),p+Vector2(0,vertical),p+Vector2(-horizontal,0)])
            draw_colored_polygon(diamond,Color(1.0,.70,.10,.98 if primary else .62));draw_polyline(diamond,Color(.18,.08,.02),1.7 if primary else 1.1,true)
            if primary:draw_circle(p,2.2,Color(.20,.06,.015,.96))
        elif kind=="graveyard":
            draw_line(p+Vector2(0,-4),p+Vector2(0,4),Color(.82,.80,.66),1.8);draw_line(p+Vector2(-3,-1),p+Vector2(3,-1),Color(.82,.80,.66),1.8)
        elif kind=="dungeon":draw_arc(p,5,PI,TAU,14,Color(.20,.13,.05),2.5,true)
        else:draw_rect(Rect2(p-Vector2(3.5,3),Vector2(7,6)),Color(.42,.23,.08),true)


func _draw_offscreen_objective(center:Vector2,radius:float,objective:Vector2)->void:
    var player_position:=_draw_anchor if _cached_layer_mode and is_finite(_draw_anchor.x) else Vector2(_player.global_position.x,_player.global_position.z)
    var delta:=objective-player_position
    if delta.length_squared()<1.0:return
    var direction:=delta.normalized()
    var marker_center:=center+direction*(radius-19.0)
    var tangent:=Vector2(-direction.y,direction.x)
    var arrow:=PackedVector2Array([
        marker_center+direction*8.5,
        marker_center-direction*5.5+tangent*5.2,
        marker_center-direction*2.5,
        marker_center-direction*5.5-tangent*5.2,
    ])
    draw_colored_polygon(arrow,Color(1.0,.71,.10,.98))
    draw_polyline(arrow,Color(.17,.065,.015,.98),1.7,true)
    var metres:=delta.length()
    var distance_text:="%d m"%roundi(metres) if metres<1000.0 else "%.1f km"%(metres/1000.0)
    var label_position:=marker_center-direction*36.0-Vector2(ThemeDB.fallback_font.get_string_size(distance_text,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x*.5,-4)
    _small_label(distance_text,label_position)


func _prepare_draw_caches()->void:
    _bridge_draw_cache.clear()
    _volcanic_terrain_cache.clear()
    for site_value in _profile.get("map_sites",[]):
        if not site_value is Dictionary:continue
        var site:Dictionary=site_value
        if str(site.get("kind",""))!="volcano":continue
        _volcanic_terrain_cache.append({
            "center":site.get("position",Vector2.ZERO),
            "radius":maxf(1200.0,float(site.get("radius",170.0))*8.2),
        })
    for bridge_value in _profile.get("ford_sites",[]):
        var bridge:Dictionary=bridge_value
        var world_point:Vector2=bridge.get("position",Vector2.ZERO)
        var river_segment:=_nearest_corridor_segment(world_point,_profile.get("river_corridors",[]))
        var road_segment:=_nearest_corridor_segment(world_point,_profile.get("road_corridors",[]))
        var tangent:=Vector2(0,1)
        if bridge.get("standalone",false) and not river_segment.is_empty():
            var river_direction:Vector2=river_segment.direction
            tangent=Vector2(-river_direction.y,river_direction.x).normalized()
        elif not road_segment.is_empty():
            tangent=road_segment.direction
        _bridge_draw_cache.append({
            "position":world_point,
            "tangent":tangent,
            "span":float(river_segment.get("width",52.0))*.66+12.0,
        })
    _refresh_interaction_cache()
    _refresh_dynamic_marker_cache()


func _refresh_interaction_cache()->void:
    if is_instance_valid(_director) and _director.has_method("get_world_interaction_markers"):
        _interaction_marker_cache=_director.get_world_interaction_markers()
    if is_instance_valid(_director) and _director.has_method("get_story_map_markers"):
        _story_marker_cache=_director.get_story_map_markers()


func _refresh_dynamic_marker_cache()->void:
    if is_instance_valid(_director) and _director.has_method("get_minion_positions"):
        _enemy_position_cache=_director.get_minion_positions()
    if is_instance_valid(_director) and _director.has_method("get_story_map_markers"):
        _story_marker_cache=_director.get_story_map_markers()


func _draw_player(center: Vector2) -> void:
    var facing := _player_map_heading()
    var silhouette:=PackedVector2Array([
        center+Vector2(0,-14).rotated(facing),center+Vector2(-3.8,-4).rotated(facing),
        center+Vector2(-6,2).rotated(facing),center+Vector2(-4,8).rotated(facing),
        center+Vector2(0,5).rotated(facing),center+Vector2(4,8).rotated(facing),
        center+Vector2(6,2).rotated(facing),center+Vector2(3.8,-4).rotated(facing)
    ])
    draw_colored_polygon(silhouette,Color(.16,.105,.035,.98))
    draw_polyline(silhouette,Color(.84,.61,.18,.98),2.0,true)
    var visor:=PackedVector2Array([
        center+Vector2(0,-10.5).rotated(facing),center+Vector2(-3,-2.5).rotated(facing),
        center+Vector2(0,3).rotated(facing),center+Vector2(3,-2.5).rotated(facing)
    ])
    draw_colored_polygon(visor,Color(.86,.90,.88,.98))
    draw_polyline(visor,Color(.24,.29,.30,.96),1.0,true)


func _local_point(point: Vector2, center: Vector2, radius: float) -> Vector2:
    var player_pos:=_draw_anchor if _cached_layer_mode and is_finite(_draw_anchor.x) else Vector2(_player.global_position.x,_player.global_position.z)
    return center + (point - player_pos) / view_radius * radius


func get_draw_anchor()->Vector2:
    return _draw_anchor


func _player_map_heading() -> float:
    var visual := _player.get_node_or_null("Visual") as Node3D
    var world_yaw := visual.global_rotation.y if visual else _player.global_rotation.y
    return PI - world_yaw


func _small_label(text: String, position: Vector2) -> void:
    for offset in [Vector2(-1.5,0),Vector2(1.5,0),Vector2(0,-1.5),Vector2(0,1.5)]:draw_string(ThemeDB.fallback_font,position+offset,text,HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color(.96,.88,.69,.95))
    draw_string(ThemeDB.fallback_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.18, 0.09, 0.025))


func _cardinal(text: String, position: Vector2) -> void:
    draw_string(ThemeDB.fallback_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.18, 0.09, 0.025))


func _draw_scale_bar(center:Vector2,radius:float)->void:
    var world_length:=250.0
    var length:=world_length/view_radius*radius
    var start:=center+Vector2(-length*.5,radius*.66)
    var finish:=start+Vector2(length,0)
    draw_line(start,finish,Color(.16,.08,.02,.9),2.0)
    draw_line(start-Vector2(0,3),start+Vector2(0,3),Color(.16,.08,.02,.9),1.5)
    draw_line(finish-Vector2(0,3),finish+Vector2(0,3),Color(.16,.08,.02,.9),1.5)
    draw_string(ThemeDB.fallback_font,start+Vector2(length*.5-12,-4),"250m",HORIZONTAL_ALIGNMENT_LEFT,-1,9,Color(.17,.09,.025))
