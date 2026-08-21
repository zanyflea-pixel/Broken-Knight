extends Control


const MAP_REFRESH_DISTANCE:=64.0

var _profile:Dictionary={}
var _player:Node3D
var _director:Node
var _height_sampler:Callable
var _map_layer:Control
var _overlay:Control
var _terrain_texture:ImageTexture
var _pending_row:=-1
var _pending_color_row:=-1


func _ready()->void:
    texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
    _map_layer=Control.new()
    _map_layer.name="CachedMapLayer"
    _map_layer.set_script(load("res://scripts/Minimap.gd"))
    _map_layer.call("enable_cached_layer_mode")
    _map_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _map_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
    add_child(_map_layer)

    _overlay=Control.new()
    _overlay.name="LiveOverlay"
    _overlay.set_script(load("res://scripts/MinimapOverlay.gd"))
    _overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
    add_child(_overlay)
    queue_redraw()


func configure(profile:Dictionary,player:Node3D,director:Node=null,height_sampler:Callable=Callable())->void:
    _profile=profile
    _player=player
    _director=director
    _height_sampler=height_sampler
    _map_layer.call("configure",profile,player,director,height_sampler)
    _overlay.call("configure",player,director)
    queue_redraw()


func _process(_delta:float)->void:
    if not visible or not is_instance_valid(_player) or not is_instance_valid(_map_layer):return
    var player_pos:=Vector2(_player.global_position.x,_player.global_position.z)
    var anchor:Vector2=_map_layer.call("get_draw_anchor")
    if not is_finite(anchor.x):anchor=player_pos
    var radius:=minf(size.x,size.y)*.455
    _map_layer.position=(anchor-player_pos)/float(_map_layer.get("view_radius"))*radius
    var pending_row:int=int(_map_layer.get("_pending_row"))
    var pending_color_row:int=int(_map_layer.get("_pending_color_row"))
    _pending_row=pending_row
    _pending_color_row=pending_color_row
    if player_pos.distance_to(anchor)>=MAP_REFRESH_DISTANCE and pending_row<0 and pending_color_row<0:
        _map_layer.call("_begin_terrain_refresh",player_pos)
    _terrain_texture=_map_layer.get("_terrain_texture")


func _draw()->void:
    var center:=size*.5
    var radius:=minf(size.x,size.y)*.455
    draw_circle(center,radius+10,Color(.025,.030,.038,.98))
    draw_circle(center,radius+7,Color(.64,.43,.16,1.0))
    draw_circle(center,radius+3,Color(.13,.16,.19,1.0))
    draw_circle(center,radius,Color(.42,.52,.28,1.0))


func _begin_terrain_refresh(center:Vector2)->void:
    _map_layer.call("_begin_terrain_refresh",center)
    _pending_row=0
    _pending_color_row=-1


func reset_draw_profile()->void:
    _map_layer.call("reset_draw_profile")


func get_draw_profile()->Dictionary:
    return _map_layer.call("get_draw_profile")
