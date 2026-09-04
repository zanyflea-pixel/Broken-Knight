extends Control


var _player:Node3D
var _director:Node
var _enemy_positions:Array[Vector3]=[]
var _primary_objective:Dictionary={}
var _redraw_accumulator:=0.0
var _enemy_accumulator:=0.0
var view_radius:=650.0


func configure(player:Node3D,director:Node)->void:
    _player=player
    _director=director
    _refresh_enemies()
    _refresh_objective()
    queue_redraw()


func _process(delta:float)->void:
    if not visible:return
    _redraw_accumulator+=delta
    _enemy_accumulator+=delta
    if _enemy_accumulator>=.25:
        _enemy_accumulator=0.0
        _refresh_enemies()
        _refresh_objective()
    if _redraw_accumulator>=.125:
        _redraw_accumulator=0.0
        queue_redraw()


func _draw()->void:
    if not is_instance_valid(_player):return
    var center:=size*.5
    var radius:=minf(size.x,size.y)*.455
    for ring in [.33,.66,1.0]:draw_arc(center,radius*ring,0,TAU,72,Color(.20,.13,.05,.22),1.0)
    _draw_enemies(center,radius)
    _draw_primary_objective(center,radius)
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


func _refresh_objective()->void:
    _primary_objective={}
    if is_instance_valid(_director) and _director.has_method("get_primary_story_objective"):
        _primary_objective=_director.get_primary_story_objective()


func _draw_primary_objective(center:Vector2,radius:float)->void:
    if _primary_objective.is_empty():return
    var objective_3d:Vector3=_primary_objective.get("position",Vector3.ZERO)
    var objective:=Vector2(objective_3d.x,objective_3d.z)
    var player_position:=Vector2(_player.global_position.x,_player.global_position.z)
    var delta:=objective-player_position
    if delta.length_squared()<1.0:return
    var map_offset:=delta/view_radius*radius
    if map_offset.length()<radius-13.0:
        var p:=center+map_offset
        var diamond:=PackedVector2Array([p+Vector2(0,-8),p+Vector2(6.5,0),p+Vector2(0,8),p+Vector2(-6.5,0)])
        draw_colored_polygon(diamond,Color(1.0,.70,.10,.98))
        draw_polyline(diamond,Color(.18,.08,.02),1.7,true)
        draw_circle(p,2.2,Color(.20,.06,.015,.96))
        return
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
    var text_width:=ThemeDB.fallback_font.get_string_size(distance_text,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
    var label_position:=marker_center-direction*36.0-Vector2(text_width*.5,-4)
    _small_label(distance_text,label_position)


func _small_label(text:String,position:Vector2)->void:
    for offset in [Vector2(-1.5,0),Vector2(1.5,0),Vector2(0,-1.5),Vector2(0,1.5)]:
        draw_string(ThemeDB.fallback_font,position+offset,text,HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color(.96,.88,.69,.95))
    draw_string(ThemeDB.fallback_font,position,text,HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color(.18,.09,.025))


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
