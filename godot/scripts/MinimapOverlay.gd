extends Control


var _player:Node3D
var _director:Node
var _enemy_positions:Array[Vector3]=[]
var _redraw_accumulator:=0.0
var _enemy_accumulator:=0.0
var view_radius:=650.0


func configure(player:Node3D,director:Node)->void:
    _player=player
    _director=director
    _refresh_enemies()
    queue_redraw()


func _process(delta:float)->void:
    if not visible:return
    _redraw_accumulator+=delta
    _enemy_accumulator+=delta
    if _enemy_accumulator>=.25:
        _enemy_accumulator=0.0
        _refresh_enemies()
    if _redraw_accumulator>=.125:
        _redraw_accumulator=0.0
        queue_redraw()


func _draw()->void:
    if not is_instance_valid(_player):return
    var center:=size*.5
    var radius:=minf(size.x,size.y)*.455
    for ring in [.33,.66,1.0]:draw_arc(center,radius*ring,0,TAU,72,Color(.20,.13,.05,.22),1.0)
    _draw_enemies(center,radius)
    _draw_player(center)
    draw_arc(center,radius,0,TAU,112,Color(.19,.11,.035),4.0,true)
    draw_arc(center,radius-6,0,TAU,112,Color(.76,.57,.24),1.5,true)
    _cardinal("N",center+Vector2(-5,-radius+16))
    _cardinal("E",center+Vector2(radius-17,5))
    _cardinal("S",center+Vector2(-4,radius-7))
    _cardinal("W",center+Vector2(-radius+8,5))
    _draw_scale_bar(center,radius)


func _draw_enemies(center:Vector2,radius:float)->void:
    var player_pos:=Vector2(_player.global_position.x,_player.global_position.z)
    var shown:=0
    for position in _enemy_positions:
        var p:=center+(Vector2(position.x,position.z)-player_pos)/view_radius*radius
        if p.distance_to(center)<radius:
            draw_circle(p,3.5,Color(.32,.02,.015))
            draw_circle(p,2.2,Color(.88,.08,.035))
            shown+=1
            if shown>=16:return


func _draw_player(center:Vector2)->void:
    var visual:=_player.get_node_or_null("Visual") as Node3D
    var world_yaw:=visual.global_rotation.y if visual else _player.global_rotation.y
    var facing:=PI-world_yaw
    var silhouette:=PackedVector2Array([
        center+Vector2(0,-14).rotated(facing),center+Vector2(-3.8,-4).rotated(facing),
        center+Vector2(-6,2).rotated(facing),center+Vector2(-4,8).rotated(facing),
        center+Vector2(0,5).rotated(facing),center+Vector2(4,8).rotated(facing),
        center+Vector2(6,2).rotated(facing),center+Vector2(3.8,-4).rotated(facing),
    ])
    draw_colored_polygon(silhouette,Color(.16,.105,.035,.98))
    var closed:=silhouette.duplicate();closed.append(silhouette[0])
    draw_polyline(closed,Color(.84,.61,.18,.98),2.0,true)
    var visor:=PackedVector2Array([
        center+Vector2(0,-10.5).rotated(facing),center+Vector2(-3,-2.5).rotated(facing),
        center+Vector2(0,3).rotated(facing),center+Vector2(3,-2.5).rotated(facing),
    ])
    draw_colored_polygon(visor,Color(.86,.90,.88,.98))
    var closed_visor:=visor.duplicate();closed_visor.append(visor[0])
    draw_polyline(closed_visor,Color(.24,.29,.30,.96),1.0,true)


func _refresh_enemies()->void:
    if is_instance_valid(_director) and _director.has_method("get_minion_positions"):
        _enemy_positions=_director.get_minion_positions()


func _cardinal(text:String,position:Vector2)->void:
    draw_string(ThemeDB.fallback_font,position,text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color(.18,.09,.025))


func _draw_scale_bar(center:Vector2,radius:float)->void:
    var length:=250.0/view_radius*radius
    var start:=center+Vector2(-length*.5,radius*.66)
    var finish:=start+Vector2(length,0)
    draw_line(start,finish,Color(.16,.08,.02,.9),2.0)
    draw_line(start-Vector2(0,3),start+Vector2(0,3),Color(.16,.08,.02,.9),1.5)
    draw_line(finish-Vector2(0,3),finish+Vector2(0,3),Color(.16,.08,.02,.9),1.5)
    draw_string(ThemeDB.fallback_font,start+Vector2(length*.5-12,-4),"250m",HORIZONTAL_ALIGNMENT_LEFT,-1,9,Color(.17,.09,.025))
