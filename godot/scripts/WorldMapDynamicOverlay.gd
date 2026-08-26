extends Control

var _last_mouse:=Vector2(INF,INF)


func _ready()->void:
    mouse_filter=Control.MOUSE_FILTER_IGNORE
    process_mode=Node.PROCESS_MODE_ALWAYS
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta:float)->void:
    if not is_visible_in_tree():return
    var mouse:=get_local_mouse_position()
    if mouse.distance_squared_to(_last_mouse)>.25:
        _last_mouse=mouse
        queue_redraw()


func refresh()->void:
    _last_mouse=Vector2(INF,INF)
    queue_redraw()


func _draw()->void:
    var map:=get_parent() as Control
    if not is_instance_valid(map):return
    var panel:=Rect2(Vector2.ZERO,size)
    var mouse:=get_local_mouse_position()
    _draw_player(map,panel)
    if not panel.has_point(mouse):return
    _draw_feature_tooltip(map,panel,mouse)
    if bool(map.get("_teleport_mode")):
        _draw_teleport_cursor(map,panel,mouse)


func _draw_player(map:Control,panel:Rect2)->void:
    var player:=map.get("_player") as Node3D
    if not is_instance_valid(player):return
    var extent:Vector2=map.call("_map_extent")
    var center:Vector2=map.call("_map_center")
    var world_point:=Vector2(player.global_position.x,player.global_position.z)
    var p:=panel.position+((world_point-center)/extent+Vector2(.5,.5))*panel.size
    if not panel.grow(18.0).has_point(p):return
    var heading:float=map.call("_player_map_heading")
    var silhouette:=PackedVector2Array([
        p+Vector2(0,-16).rotated(heading),p+Vector2(-4,-5).rotated(heading),
        p+Vector2(-7,2).rotated(heading),p+Vector2(-4.5,9).rotated(heading),
        p+Vector2(0,6).rotated(heading),p+Vector2(4.5,9).rotated(heading),
        p+Vector2(7,2).rotated(heading),p+Vector2(4,-5).rotated(heading),
    ])
    draw_colored_polygon(silhouette,Color(.16,.105,.035,.98))
    draw_polyline(silhouette,Color(.84,.61,.18,.98),2.2,true)
    var visor:=PackedVector2Array([
        p+Vector2(0,-12).rotated(heading),p+Vector2(-3.2,-3).rotated(heading),
        p+Vector2(0,3.5).rotated(heading),p+Vector2(3.2,-3).rotated(heading),
    ])
    draw_colored_polygon(visor,Color(.86,.90,.88,.98))
    draw_polyline(visor,Color(.24,.29,.30,.96),1.0,true)


func _draw_feature_tooltip(map:Control,panel:Rect2,mouse:Vector2)->void:
    var nearest:Dictionary={}
    var best:=INF
    for feature_value in map.get("_map_features"):
        if not feature_value is Dictionary:continue
        var feature:Dictionary=feature_value
        var distance:float=mouse.distance_to(Vector2(feature.get("screen",Vector2.ZERO)))
        if distance<=float(feature.get("radius",4.0))+7.0 and distance<best:
            best=distance;nearest=feature
    if nearest.is_empty():return
    var world_point:Vector2=nearest.get("world",Vector2.ZERO)
    var title:=str(nearest.get("label","Location"))
    var subtitle:="%s   X %d  Z %d"%[
        str(nearest.get("category","Feature")),roundi(world_point.x),roundi(world_point.y),
    ]
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


func _draw_teleport_cursor(map:Control,panel:Rect2,cursor:Vector2)->void:
    draw_line(cursor-Vector2(13,0),cursor+Vector2(13,0),Color(1.0,.82,.26,.95),2.0)
    draw_line(cursor-Vector2(0,13),cursor+Vector2(0,13),Color(1.0,.82,.26,.95),2.0)
    draw_circle(cursor,6.0,Color(.22,.08,.02,.9),false,2.0)
    var normalized:=(cursor-panel.position)/panel.size
    var extent:Vector2=map.call("_map_extent")
    var center:Vector2=map.call("_map_center")
    var world_point:Vector2=(normalized-Vector2(.5,.5))*extent+center
    var readout:="X %d   Z %d"%[roundi(world_point.x),roundi(world_point.y)]
    var box:=Rect2(cursor+Vector2(15,-26),Vector2(124,24))
    if box.end.x>panel.end.x:box.position.x=cursor.x-box.size.x-15
    draw_rect(box,Color(.15,.08,.025,.88),true)
    _label(readout,box.position+Vector2(7,17),11,Color(1.0,.84,.37))
    _label("TELEPORT ACTIVE - CLICK MAP",Vector2(panel.end.x-260,72),13,Color(.68,.10,.035))


func _label(text:String,position:Vector2,font_size:int,color:Color)->void:
    var halo:=Color(.97,.89,.71,.96) if color.get_luminance()<.48 else Color(.07,.045,.02,.92)
    for offset in [Vector2(-2,0),Vector2(2,0),Vector2(0,-2),Vector2(0,2)]:
        draw_string(ThemeDB.fallback_font,position+offset,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,halo)
    draw_string(ThemeDB.fallback_font,position,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
