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
const TERRAIN_RESOLUTION:=64
var view_radius := 650.0
var _redraw_accumulator := 0.0


func _ready() -> void:
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func configure(profile: Dictionary, player: Node3D, director: Node = null, height_sampler: Callable = Callable()) -> void:
    _profile = profile
    _player = player
    _director = director
    _height_sampler = height_sampler
    if is_instance_valid(_player):
        _begin_terrain_refresh(Vector2(_player.global_position.x,_player.global_position.z))
    queue_redraw()


func _process(delta: float) -> void:
    if not visible:
        return
    if _pending_row>=0:
        # Spread height sampling across more frames. The finished image keeps
        # the same 64x64 detail, but walking no longer receives a burst of 384
        # terrain queries on each refresh frame.
        _advance_terrain_refresh(1)
    _redraw_accumulator += delta
    if _redraw_accumulator < 0.10:
        return
    _redraw_accumulator = 0.0
    if _pending_row<0 and is_instance_valid(_player) and not _inside_dungeon():
        var player_pos:=Vector2(_player.global_position.x,_player.global_position.z)
        if player_pos.distance_to(_terrain_center)>=64.0:_begin_terrain_refresh(player_pos)
    queue_redraw()


func _begin_terrain_refresh(center:Vector2)->void:
    if not _height_sampler.is_valid():return
    _pending_center=center
    _pending_heights.resize(TERRAIN_RESOLUTION*TERRAIN_RESOLUTION)
    _pending_row=0


func _advance_terrain_refresh(rows:int)->void:
    if _pending_row<0:return
    var last_row:=mini(TERRAIN_RESOLUTION,_pending_row+rows)
    for y in range(_pending_row,last_row):
        for x in range(TERRAIN_RESOLUTION):
            var uv:=Vector2(float(x)/(TERRAIN_RESOLUTION-1),float(y)/(TERRAIN_RESOLUTION-1))*2.0-Vector2.ONE
            var world_point:=_pending_center+uv*view_radius
            _pending_heights[y*TERRAIN_RESOLUTION+x]=_height_sampler.call(world_point.x,world_point.y).y
    _pending_row=last_row
    if _pending_row>=TERRAIN_RESOLUTION:_finish_terrain_refresh()


func _finish_terrain_refresh()->void:
    var image:=Image.create(TERRAIN_RESOLUTION,TERRAIN_RESOLUTION,false,Image.FORMAT_RGBA8)
    for y in range(TERRAIN_RESOLUTION):
        for x in range(TERRAIN_RESOLUTION):
            var uv := Vector2(float(x) / (TERRAIN_RESOLUTION - 1), float(y) / (TERRAIN_RESOLUTION - 1)) * 2.0 - Vector2.ONE
            if uv.length() > 1.0:
                image.set_pixel(x, y, Color(0, 0, 0, 0))
                continue
            var h := _pending_heights[y * TERRAIN_RESOLUTION + x]
            var left := _pending_heights[y * TERRAIN_RESOLUTION + maxi(0, x - 1)]
            var right := _pending_heights[y * TERRAIN_RESOLUTION + mini(TERRAIN_RESOLUTION - 1, x + 1)]
            var up := _pending_heights[maxi(0, y - 1) * TERRAIN_RESOLUTION + x]
            var down := _pending_heights[mini(TERRAIN_RESOLUTION - 1, y + 1) * TERRAIN_RESOLUTION + x]
            var shade := clampf(0.96 + (left - right) * 0.025 + (up - down) * 0.018, 0.68, 1.20)
            var color := _terrain_color(h, _pending_center + uv * view_radius)
            if floorf(h / 15.0) != floorf(right / 15.0) or floorf(h / 15.0) != floorf(down / 15.0):
                shade *= 0.80
            image.set_pixel(x, y, Color(color.r * shade, color.g * shade, color.b * shade, 0.97))
    _terrain_texture = ImageTexture.create_from_image(image)
    _terrain_center=_pending_center
    _pending_row=-1
    queue_redraw()


func _terrain_color(height: float, world_point: Vector2) -> Color:
    var world_size: float = _profile.get("world_size",7200.0)
    var color := Color(.41,.53,.27)
    if world_point.x > world_size*.16:
        color=Color(.48,.48,.25)
    elif world_point.x < -world_size*.20:
        color=Color(.33,.46,.26)
    if world_point.y > world_size*.18:
        color=color.lerp(Color(.28,.45,.38),.36)
    elif world_point.y < -world_size*.18:
        color=color.lerp(Color(.56,.42,.24),.42)
    if height>45.0:
        color=color.lerp(Color(.47,.45,.39),clampf((height-45.0)/85.0,0.0,.86))
    return color


func _draw() -> void:
    if _profile.is_empty() or not is_instance_valid(_player):
        return
    var center := size * 0.5
    var radius := minf(size.x, size.y) * 0.455
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
        var player_pos:=Vector2(_player.global_position.x,_player.global_position.z)
        var cache_offset:=(_terrain_center-player_pos)/view_radius*radius
        draw_texture_rect(_terrain_texture, Rect2(center - Vector2.ONE * radius + cache_offset, Vector2.ONE * radius * 2.0), false)
    for ring in [0.33, 0.66, 1.0]:
        draw_arc(center, radius * ring, 0, TAU, 72, Color(0.20, 0.13, 0.05, 0.22), 1.0)
    _draw_local_forests(center, radius)
    _corridors(_profile.get("river_corridors", []), center, radius, "river")
    _corridors(_profile.get("road_corridors", []), center, radius, "road")
    _corridors(_profile.get("trail_corridors", []), center, radius, "trail")
    _draw_water_sites(center, radius)
    _draw_waterfalls(center,radius)
    _draw_bridges(center, radius)
    _draw_settlements(center, radius)
    _draw_caves_and_camps(center,radius)
    _draw_interactions(center,radius)
    _draw_enemies(center, radius)
    _draw_player(center)
    draw_arc(center, radius, 0, TAU, 112, Color(0.19, 0.11, 0.035), 4.0, true)
    draw_arc(center, radius - 6, 0, TAU, 112, Color(0.76, 0.57, 0.24), 1.5, true)
    _cardinal("N", center + Vector2(-5, -radius + 16))
    _cardinal("E", center + Vector2(radius - 17, 5))
    _cardinal("S", center + Vector2(-4, radius - 7))
    _cardinal("W", center + Vector2(-radius + 8, 5))
    _draw_scale_bar(center,radius)


func _inside_dungeon()->bool:
    return is_instance_valid(_player) and _player.global_position.x>7800.0


func _draw_dungeon_minimap(center:Vector2,radius:float)->void:
    draw_circle(center,radius,Color(.065,.060,.052))
    var player_pos:=Vector2(_player.global_position.x,_player.global_position.z)
    var base:=Vector2(8000,0)
    var title:="RIVERWATCH WELL"
    var half_size:=Vector2(42,66)
    if player_pos.x>8310:
        base=Vector2(8420,0);title="EAST CAVERN";half_size=Vector2(64,95)
    elif player_pos.x>8100:
        base=Vector2(8200,0);title="WEST CAVERN";half_size=Vector2(64,95)
    var scale:=minf((radius-20.0)/half_size.x,(radius-24.0)/half_size.y)
    var room_rect:=Rect2(center-half_size*scale,half_size*2.0*scale)
    draw_rect(room_rect,Color(.21,.19,.16),true)
    draw_rect(room_rect,Color(.70,.55,.29),false,2.0)
    if title!="RIVERWATCH WELL":
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
        var river_segments:Array[Dictionary]=[]
        for corridor in corridors:
            var points:Array[Vector2]=[]
            for point in corridor.get("points",[]):points.append(_local_point(point,center,radius))
            var pixels:=maxf(1.5,float(corridor.get("width",48.0))*.66/view_radius*radius)
            for i in range(points.size()-1):
                var clipped:=_clip_segment_to_circle(points[i],points[i+1],center,radius)
                if not clipped.is_empty():river_segments.append({"a":clipped[0],"b":clipped[1],"width":pixels})
        for segment in river_segments:draw_line(segment.a,segment.b,Color(.08,.20,.23,.98),float(segment.width)+3.0,true)
        for segment in river_segments:draw_line(segment.a,segment.b,Color(.30,.69,.78,1.0),float(segment.width),true)
        for segment in river_segments:draw_line(segment.a,segment.b,Color(.70,.90,.91,.42),maxf(1.0,float(segment.width)*.16),true)
        return
    for corridor in corridors:
        var points: Array[Vector2] = []
        for point in corridor.get("points", []):
            points.append(_local_point(point, center, radius))
        var authored_width: float = corridor.get("width", 12.0)
        var physical_width := authored_width
        if kind == "river":
            physical_width *= 0.66
        elif kind == "road":
            physical_width *= 0.48
        elif kind == "trail":
            physical_width *= 0.48
        var pixels := maxf(1.5, physical_width / view_radius * radius)
        for i in range(points.size() - 1):
            var clipped := _clip_segment_to_circle(points[i], points[i + 1], center, radius)
            if clipped.is_empty():
                continue
            var a: Vector2 = clipped[0]
            var b: Vector2 = clipped[1]
            if kind == "river":
                draw_line(a, b, Color(0.08, 0.20, 0.23, 0.98), pixels + 3.0, true)
                draw_line(a, b, Color(0.30, 0.69, 0.78, 1.0), pixels, true)
                draw_line(a, b, Color(0.70, 0.90, 0.91, 0.42), maxf(1.0, pixels * 0.16), true)
            elif kind == "road":
                draw_line(a, b, Color(0.19, 0.10, 0.035, 0.96), pixels + 2.5, true)
                draw_line(a, b, Color(0.88, 0.61, 0.25, 1.0), pixels, true)
            else:
                draw_line(a, b, Color(0.31, 0.20, 0.08, 0.92), pixels, true)


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
    for region in _profile.get("forest_regions", []):
        var region_center: Vector2 = region.get("center", Vector2.ZERO)
        var region_radius: float = region.get("radius", 300.0)
        for i in range(8):
            var angle := i * 2.399
            var p := _local_point(region_center + Vector2(cos(angle), sin(angle)) * region_radius * 0.48, center, radius)
            if p.distance_to(center) < radius - 4:
                draw_colored_polygon(PackedVector2Array([p + Vector2(0, -4), p + Vector2(-3, 3), p + Vector2(3, 3)]), Color(0.10, 0.29, 0.13, 0.82))


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
        draw_line(p-normal*5.0,p+normal*5.0,Color(.91,.96,.88),2.4)
        draw_line(p-normal*5.0+tangent*2.5,p+normal*5.0+tangent*2.5,Color(.07,.27,.32),1.2)


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
    for bridge in _profile.get("ford_sites", []):
        var world_point:Vector2=bridge.get("position",Vector2.ZERO)
        var p := _local_point(world_point, center, radius)
        if p.distance_to(center) < radius - 4:
            var river_segment:=_nearest_corridor_segment(world_point,_profile.get("river_corridors",[]))
            var road_segment:=_nearest_corridor_segment(world_point,_profile.get("road_corridors",[]))
            var tangent:=Vector2(0,1)
            if bridge.get("standalone",false) and not river_segment.is_empty():
                var river_direction:Vector2=river_segment.direction
                tangent=Vector2(-river_direction.y,river_direction.x).normalized()
            elif not road_segment.is_empty():
                tangent=road_segment.direction
            var normal:=Vector2(-tangent.y,tangent.x)
            var half_span:=maxf(5.0,(float(river_segment.get("width",52.0))*.66+12.0)/view_radius*radius*.5)
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
            draw_circle(p,footprint,Color(.69,.50,.27,.24))
            draw_arc(p,footprint,0,TAU,24,Color(.25,.13,.04,.42),1.0)
            draw_circle(p, 7.5 if site.get("capital", false) else 6.0, Color(0.22, 0.11, 0.035))
            if site.get("capital", false):
                draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(-6, 5), p + Vector2(6, 5)]), Color(0.76, 0.18, 0.08))
            else:
                draw_rect(Rect2(p - Vector2(3.5, 3), Vector2(7, 6)), Color(0.78, 0.25, 0.09), true)
            if distance > 30.0 and distance < radius * 0.76:
                _small_label(site.get("name", "Town"), p + Vector2(7, 3))
        else:
            var edge := center + (p - center).normalized() * (radius - 10)
            draw_colored_polygon(PackedVector2Array([edge + Vector2(0, -5), edge + Vector2(-4, 4), edge + Vector2(4, 4)]), Color(0.78, 0.25, 0.09))


func _draw_enemies(center: Vector2, radius: float) -> void:
    if not is_instance_valid(_director):
        return
    for position in _director.get_minion_positions():
        var p := _local_point(Vector2(position.x, position.z), center, radius)
        if p.distance_to(center) < radius:
            draw_circle(p, 3.5, Color(0.32, 0.02, 0.015))
            draw_circle(p, 2.2, Color(0.88, 0.08, 0.035))


func _draw_interactions(center:Vector2,radius:float)->void:
    if not is_instance_valid(_director) or not _director.has_method("get_world_interaction_markers"):return
    for marker in _director.get_world_interaction_markers():
        var position:Vector3=marker.position
        var p:=_local_point(Vector2(position.x,position.z),center,radius)
        if p.distance_to(center)>=radius-5.0:continue
        match marker.action:
            "craft":
                draw_rect(Rect2(p-Vector2(3,3),Vector2(6,6)),Color(.96,.62,.14),true)
                draw_line(p+Vector2(-4,4),p+Vector2(4,-4),Color(.25,.13,.04),1.4)
            "chop":draw_colored_polygon(PackedVector2Array([p+Vector2(0,-4),p+Vector2(-3,3),p+Vector2(3,3)]),Color(.16,.42,.12))
            "gather":draw_circle(p,2.2,Color(.54,.80,.28))


func _draw_player(center: Vector2) -> void:
    var facing := _player_map_heading()
    draw_circle(center, 13, Color(1.0, 0.85, 0.30, 0.92))
    draw_circle(center, 10, Color(0.15, 0.075, 0.025, 0.96))
    var arrow := PackedVector2Array([center + Vector2(0, -12).rotated(facing), center + Vector2(-7, 8).rotated(facing), center, center + Vector2(7, 8).rotated(facing)])
    draw_colored_polygon(arrow, Color(0.90, 0.11, 0.045))
    draw_polyline(arrow, Color.WHITE, 1.6, true)


func _local_point(point: Vector2, center: Vector2, radius: float) -> Vector2:
    var player_pos := Vector2(_player.global_position.x, _player.global_position.z)
    return center + (point - player_pos) / view_radius * radius


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
