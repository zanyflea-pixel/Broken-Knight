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
const TERRAIN_RESOLUTION:=288
var _parchment: Texture2D
var _teleport_mode := false
var _teleport_button: Button
var _redraw_accumulator := 0.0
var _map_label_rects:Array[Rect2]=[]


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    _parchment = load("res://assets/ui/cartographer_parchment_v1.png")
    _teleport_button = Button.new()
    _teleport_button.text = "TELEPORT MODE"
    _teleport_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _teleport_button.position = Vector2(-252, 22)
    _teleport_button.size = Vector2(215, 42)
    _teleport_button.toggle_mode = true
    _teleport_button.tooltip_text = "Enable, then click anywhere on the map to teleport."
    _teleport_button.pressed.connect(_toggle_teleport_mode)
    add_child(_teleport_button)


func configure(profile: Dictionary, player: Node3D, director: Node = null, height_sampler: Callable = Callable()) -> void:
    _profile = profile
    _player = player
    _director = director
    if height_sampler.is_valid():
        _begin_terrain_texture_build(height_sampler)
    queue_redraw()


func _process(delta: float) -> void:
    # Build the expensive topographic survey over many cheap frames. It is
    # ready before most players first open the map without stalling startup.
    if _terrain_sample_row>=0:_advance_terrain_samples(4)
    elif _terrain_color_row>=0:_advance_terrain_colors(8)
    if not visible:
        return
    _redraw_accumulator += delta
    if _redraw_accumulator >= 0.20:
        _redraw_accumulator = 0.0
        queue_redraw()


func _begin_terrain_texture_build(height_sampler:Callable)->void:
    _terrain_height_sampler=height_sampler
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
            var shade := clampf(0.96 + (left - right) * 0.018 + (up - down) * 0.012, 0.68, 1.18)
            var world_point := Vector2(
                (float(x) / float(TERRAIN_RESOLUTION - 1) - 0.5) * world_size,
                (float(y) / float(TERRAIN_RESOLUTION - 1) - 0.5) * world_size
            )
            var color := _survey_color(h, world_point)
            var contour_step := 12.0 if h < 48.0 else 24.0
            if floorf(h / contour_step) != floorf(right / contour_step) or floorf(h / contour_step) != floorf(down / contour_step):
                shade *= 0.86
            _terrain_build_image.set_pixel(x,y,Color(color.r*shade,color.g*shade,color.b*shade,1.0))
    _terrain_color_row=last_row
    if _terrain_color_row>=TERRAIN_RESOLUTION:
        _terrain_texture=ImageTexture.create_from_image(_terrain_build_image)
        _terrain_build_image=null
        _terrain_color_row=-1
        queue_redraw()


func _survey_color(height: float, world_point: Vector2) -> Color:
    # Mirror the broad biome rules used by TerrainBuilder so the map describes
    # the ground the player actually sees instead of recoloring everything as
    # the same green elevation band.
    var world_size: float = _profile.get("world_size", 7200.0)
    var variation := sin(world_point.x * .017) * sin(world_point.y * .014) * 0.022
    var color := Color(0.43, 0.54, 0.28)
    var warp:=sin(world_point.x*.0027+world_point.y*.0019)*world_size*.038+sin(world_point.y*.0041-world_point.x*.0013)*world_size*.021
    var east:=smoothstep(world_size*.07+warp,world_size*.27+warp,world_point.x)
    var west:=1.0-smoothstep(-world_size*.31+warp,-world_size*.11+warp,world_point.x)
    var north:=smoothstep(world_size*.08-warp,world_size*.29-warp,world_point.y)
    var south:=1.0-smoothstep(-world_size*.29-warp,-world_size*.09-warp,world_point.y)
    color=color.lerp(Color(.49,.49,.27),east*.82)
    color=color.lerp(Color(.34,.47,.27),west*.82)
    color=color.lerp(Color(.29,.46,.39),north*.36)
    color=color.lerp(Color(.57,.43,.25),south*.42)
    if height < 0.0:
        color = color.lerp(Color(0.38, 0.39, 0.24), 0.34)
    elif height > 45.0:
        color = color.lerp(Color(0.48, 0.46, 0.40), clampf((height - 45.0) / 85.0, 0.0, 0.86))
    if height > 115.0:
        color = color.lerp(Color(0.67, 0.66, 0.61), 0.72)
    return Color(color.r + variation, color.g + variation, color.b + variation)


func _draw() -> void:
    if _profile.is_empty():
        return
    var panel := _map_panel()
    var world_size: float = _profile.get("world_size", 7200.0)
    _map_label_rects=[
        Rect2(panel.position+Vector2(10,6),Vector2(minf(550.0,panel.size.x*.52),68)),
        Rect2(panel.position+Vector2(panel.size.x-112,70),Vector2(100,100)),
        Rect2(panel.position+Vector2(12,panel.size.y-202),Vector2(250,182)),
        Rect2(panel.position+Vector2(panel.size.x-270,12),Vector2(250,58)),
        Rect2(panel.position+Vector2(panel.size.x-190,panel.size.y-72),Vector2(180,62)),
        Rect2(panel.position+Vector2(panel.size.x*.5-38,5),Vector2(76,58)),
    ]
    draw_rect(panel, Color(0.55,0.49,0.36), true)
    if _terrain_texture:
        draw_texture_rect(_terrain_texture, panel, false, Color(1.0, 0.98, 0.90))
    _draw_forests(panel, world_size)
    _draw_mountains(panel, world_size)
    _draw_settlement_footprints(panel, world_size)
    _draw_corridors(_profile.get("river_corridors", []), panel, world_size, "river")
    _draw_corridors(_profile.get("road_corridors", []), panel, world_size, "road")
    _draw_corridors(_profile.get("trail_corridors", []), panel, world_size, "trail")
    _draw_corridor_names(panel, world_size)
    _draw_bridges(panel, world_size)
    _draw_water_sites(panel, world_size)
    _draw_waterfalls(panel, world_size)
    _draw_sites(panel, world_size)
    _draw_caves(panel, world_size)
    _draw_crafting_sites(panel,world_size)
    _draw_live_markers(panel, world_size)
    _draw_compass(panel)
    _draw_realm_crest(panel)
    _draw_legend(panel)
    _draw_scale_bar(panel, world_size)
    var title_plate:=Rect2(panel.position+Vector2(14,10),Vector2(minf(540.0,panel.size.x*.52),58))
    draw_rect(title_plate,Color(.86,.80,.65,.88),true)
    draw_rect(title_plate,Color(.20,.27,.28,.94),false,2.0)
    _label(str(_profile.get("zone_name","THE REALM OF BROKEN KNIGHT")).to_upper(), panel.position + Vector2(24, 34), 24, Color(0.12, 0.16, 0.16))
    _label("ROYAL TOPOGRAPHIC TRAVEL SURVEY", panel.position + Vector2(26, 56), 13, Color(0.27, 0.32, 0.31))
    _label("M / Esc to close", panel.end - Vector2(175, 18), 14, Color(0.25, 0.15, 0.06))
    if _teleport_mode:
        _draw_teleport_cursor(panel, world_size)
        var status:=Rect2(panel.position+Vector2(panel.size.x*.5-178,panel.size.y-48),Vector2(356,32))
        draw_rect(status,Color(.12,.075,.025,.91),true)
        _label("TELEPORT ACTIVE - CLICK ANYWHERE",status.position+Vector2(21,22),15,Color(1.0,.84,.37))


func _draw_crafting_sites(panel:Rect2,world_size:float)->void:
    if not is_instance_valid(_director) or not _director.has_method("get_world_interaction_markers"):return
    for marker in _director.get_world_interaction_markers():
        if marker.get("action","")!="craft":continue
        var position:Vector3=marker.position
        var p:=_map_point(Vector2(position.x,position.z),panel,world_size)
        draw_circle(p,6.2,Color(.22,.12,.035,.94))
        draw_rect(Rect2(p-Vector2(3.3,3.3),Vector2(6.6,6.6)),Color(.94,.58,.12),true)
        draw_line(p+Vector2(-4.2,4.2),p+Vector2(4.2,-4.2),Color(.24,.12,.03),1.7)


func _draw_realm_crest(panel:Rect2)->void:
    var c:=panel.position+Vector2(panel.size.x*.5,35.0)
    var gold:=Color(.66,.40,.12,.92)
    var river:=Color(.24,.46,.58,.92)
    draw_line(c+Vector2(-20,-1),c+Vector2(20,-1),gold,3.0)
    draw_line(c+Vector2(-17,-1),c+Vector2(-14,-13),gold,4.0)
    draw_line(c+Vector2(17,-1),c+Vector2(14,-13),gold,4.0)
    draw_line(c+Vector2(-3,-1),c+Vector2(-4,-10),gold,4.0)
    draw_line(c+Vector2(-20,9),c+Vector2(0,17),river,3.0)
    draw_line(c+Vector2(0,17),c+Vector2(20,9),river,3.0)


func _toggle_teleport_mode() -> void:
    _teleport_mode = not _teleport_mode
    _teleport_button.text = "CANCEL TELEPORT" if _teleport_mode else "TELEPORT MODE"
    _teleport_button.button_pressed = _teleport_mode
    queue_redraw()


func set_teleport_mode(enabled: bool) -> void:
    _teleport_mode = enabled
    if is_instance_valid(_teleport_button):
        _teleport_button.text = "CANCEL TELEPORT" if enabled else "TELEPORT MODE"
        _teleport_button.button_pressed = enabled
    queue_redraw()


func _gui_input(event: InputEvent) -> void:
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
            draw_polyline(points, Color(0.29, 0.19, 0.08, 0.92), maxf(1.5, pixels), true)


func _draw_corridor_names(panel: Rect2, world_size: float) -> void:
    for corridor in _profile.get("river_corridors", []):
        var points: Array = corridor.get("points", [])
        if points.size() > 2:
            var p := _map_point(points[points.size() / 2], panel, world_size)
            _map_label(corridor.get("name", "River"), p + Vector2(10, -8), 12, Color(0.08, 0.24, 0.29),panel)
    for corridor in _profile.get("road_corridors", []):
        var points: Array = corridor.get("points", [])
        if points.size() > 3:
            var p := _map_point(points[points.size() - 2], panel, world_size)
            _map_label(corridor.get("name", "Road"), p + Vector2(7, -7), 10, Color(0.28, 0.15, 0.055),panel)


func _draw_forests(panel: Rect2, world_size: float) -> void:
    for region in _profile.get("forest_regions", []):
        var center: Vector2 = region.get("center", Vector2.ZERO)
        var radius: float = region.get("radius", 300.0)
        var density: float = region.get("density", .65)
        var center_px := _map_point(center, panel, world_size)
        var radius_px := radius / world_size * panel.size.x
        # Forests are represented by tree symbols only. Filled region circles
        # looked like artificial green zones and obscured terrain contours.
        var tree_count := clampi(roundi(12.0 + density * 17.0), 16, 30)
        for i in range(tree_count):
            var angle := i * 2.399963
            var r := radius * sqrt((float(i) + .6) / float(tree_count + 1)) * .88
            var p := _map_point(center + Vector2(cos(angle), sin(angle)) * r, panel, world_size)
            var s := 2.7 + float(i % 3) * .65
            draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(-s * 0.72, s * 0.58), p + Vector2(s * 0.72, s * 0.58)]), Color(0.10, 0.29, 0.13, 0.84))


func _draw_mountains(panel: Rect2, world_size: float) -> void:
    for chain in _profile.get("mountain_chains", []):
        var center: Vector2 = chain.get("center", Vector2.ZERO)
        var angle: float = chain.get("angle", 0.0)
        var length: float = chain.get("length", 500.0)
        var chain_width: float = chain.get("width", 300.0)
        var center_px := _map_point(center, panel, world_size)
        var footprint_size := Vector2(length, chain_width) / world_size * panel.size.x
        draw_set_transform(center_px, angle, Vector2.ONE)
        draw_ellipse(Vector2.ZERO, footprint_size.x * .5, footprint_size.y * .5, Color(0.38, 0.31, 0.23, .14))
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        var count := clampi(roundi(length / 180.0), 4, 11)
        for i in range(count):
            var offset := (float(i) / maxf(1.0, count - 1) - 0.5) * length
            var p := _map_point(center + Vector2(cos(angle), sin(angle)) * offset, panel, world_size)
            var s := 6.0 + float((i * 3) % 4)
            var mountain := PackedVector2Array([p + Vector2(-s, s * 0.65), p + Vector2(0, -s), p + Vector2(s, s * 0.65)])
            draw_colored_polygon(mountain, Color(0.49, 0.43, 0.34, 0.92))
            draw_polyline(mountain, Color(0.25, 0.18, 0.10), 1.4, true)


func _draw_settlement_footprints(panel: Rect2, world_size: float) -> void:
    var sites: Array = [_profile.get("spawn_site", {})]
    sites.append_array(_profile.get("town_sites", []))
    for site in sites:
        if site.is_empty():
            continue
        var center := _map_point(site.get("position", Vector2.ZERO), panel, world_size)
        var radius_px := maxf(5.0, float(site.get("radius", 80.0)) / world_size * panel.size.x)
        var tint := Color(0.73, 0.55, 0.30, .17) if not site.get("capital", false) else Color(0.68, 0.45, 0.24, .25)
        draw_circle(center, radius_px, tint)
        draw_arc(center, radius_px, 0, TAU, 40, Color(0.29, 0.16, 0.06, .50), 1.0)


func _draw_sites(panel: Rect2, world_size: float) -> void:
    var sites: Array = [_profile.get("spawn_site", {})]
    sites.append_array(_profile.get("town_sites", []))
    for site in sites:
        var p := _map_point(site.get("position", Vector2.ZERO), panel, world_size)
        draw_circle(p, 10.0 if site.get("capital", false) else 8.0, Color(0.24, 0.13, 0.05, 0.9))
        if site.get("capital", false):
            draw_rect(Rect2(p - Vector2(8, 5), Vector2(16, 11)), Color(0.66, 0.17, 0.07), true)
            for tower_x in [-7.0, 7.0]:
                draw_rect(Rect2(p + Vector2(tower_x - 2.5, -9), Vector2(5, 14)), Color(0.56, 0.12, 0.05), true)
            draw_rect(Rect2(p + Vector2(-2.0, 0), Vector2(4, 6)), Color(0.96, 0.72, 0.25), true)
        else:
            draw_rect(Rect2(p - Vector2(5, 4), Vector2(10, 8)), Color(0.76, 0.26, 0.10), true)
        var label_offset := Vector2(13, 19) if site.get("name", "") == "Riverwatch" else Vector2(11, 5)
        _map_label(site.get("name", "Settlement"), p + label_offset, 14, Color(0.18, 0.09, 0.025),panel)
    for camp in _profile.get("camp_sites", []):
        var p := _map_point(camp.get("position", Vector2.ZERO), panel, world_size)
        draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(-5, 5), p + Vector2(5, 5)]), Color(0.88, 0.39, 0.10))
        _map_label(camp.get("name", "Camp"), p + Vector2(8, 4), 11, Color(0.24, 0.12, 0.04),panel)


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
        _map_label(pond.get("name", "Pond"), p + Vector2(radius_px + 4, 4), 11, Color(0.10, 0.24, 0.25),panel)


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
        _map_label(waterfall.get("name", "Falls"), p + normal * 10.0 + Vector2(3,-2), 10, Color(0.08, 0.25, 0.29),panel)


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
        _map_label(bridge.get("name", "Bridge"), p + normal * 8.0 + Vector2(4, -3), 11, Color(0.21, 0.11, 0.035),panel)


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


func _draw_live_markers(panel: Rect2, world_size: float) -> void:
    # Enemy locations intentionally belong to the close-range minimap only.
    # The parchment world map remains useful for navigation and exploration.
    if is_instance_valid(_player):
        var p := _map_point(Vector2(_player.global_position.x, _player.global_position.z), panel, world_size)
        var heading := _player_map_heading()
        draw_circle(p, 15.0, Color(1.0, 0.88, 0.38, 0.82))
        draw_circle(p, 12.0, Color(0.18, 0.10, 0.035, 0.95))
        var arrow := PackedVector2Array([p + Vector2(0, -13).rotated(heading), p + Vector2(-8, 9).rotated(heading), p, p + Vector2(8, 9).rotated(heading)])
        draw_colored_polygon(arrow, Color(0.88, 0.12, 0.055))
        draw_polyline(arrow, Color.WHITE, 1.8, true)
        _map_label("YOU", p + Vector2(15, -12), 12, Color(0.18, 0.08, 0.025),panel)


func _player_map_heading() -> float:
    var visual := _player.get_node_or_null("Visual") as Node3D
    var world_yaw := visual.global_rotation.y if visual else _player.global_rotation.y
    return PI - world_yaw


func _draw_compass(panel: Rect2) -> void:
    var c := panel.position + Vector2(panel.size.x - 63, 120)
    draw_circle(c,38,Color(.18,.10,.035,.92));draw_circle(c,34,Color(.90,.79,.57,.94))
    draw_arc(c,34,0,TAU,64,Color(.42,.24,.07),2.0)
    draw_arc(c,27,0,TAU,64,Color(.38,.24,.10,.65),1.0)
    draw_colored_polygon(PackedVector2Array([c+Vector2(0,-30),c+Vector2(-7,1),c,c+Vector2(7,1)]),Color(.70,.11,.05))
    draw_colored_polygon(PackedVector2Array([c+Vector2(0,30),c+Vector2(-7,-1),c,c+Vector2(7,-1)]),Color(.26,.18,.10))
    draw_colored_polygon(PackedVector2Array([c+Vector2(30,0),c+Vector2(-1,-6),c,c+Vector2(-1,6)]),Color(.54,.39,.17))
    draw_colored_polygon(PackedVector2Array([c+Vector2(-30,0),c+Vector2(1,-6),c,c+Vector2(1,6)]),Color(.54,.39,.17))
    draw_circle(c,3.5,Color(.90,.66,.18))
    _label("N",c+Vector2(-5,-40),14,Color(.18,.06,.02))


func _draw_legend(panel: Rect2) -> void:
    var r := Rect2(panel.position + Vector2(18, panel.size.y - 194), Vector2(238, 168))
    draw_rect(r, Color(0.91, 0.80, 0.60, 0.92), true)
    draw_rect(r, Color(0.28, 0.17, 0.06), false, 1.5)
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
