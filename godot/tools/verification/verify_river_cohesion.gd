extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profile:Dictionary=WorldProfile.new().make_old_world_profile()
    var rivers:Array=profile.get("river_corridors",[])
    var ponds:Array=profile.get("pond_sites",[])
    var main_river:Dictionary=_named(rivers,"Kingsflow River")
    var westmere:Dictionary=_named(ponds,"Westmere")
    var north_tarn:Dictionary=_named(ponds,"North Tarn")
    if rivers.size()!=4:failures.append("expected one main stem and three tributaries")
    if main_river.is_empty():failures.append("Kingsflow River is missing")
    if westmere.is_empty():failures.append("Westmere terminal lake is missing")

    var builder:=TerrainBuilder.new()
    var worst_uphill_rise:=0.0
    var connected_tributaries:=0
    var world_half:=float(profile.get("world_size",7200.0))*.5
    for river_value in rivers:
        var river:Dictionary=river_value
        var river_name:=str(river.get("name","River"))
        var points:Array=river.get("points",[])
        if points.size()<2:
            failures.append("%s has no usable route"%river_name)
            continue
        var source_width:=float(river.get("source_width",river.get("width",0.0)))
        var mouth_width:=float(river.get("mouth_width",river.get("width",0.0)))
        if source_width>=mouth_width:failures.append("%s does not widen toward its mouth"%river_name)
        for endpoint_index in [0,points.size()-1]:
            var endpoint:Vector2=points[endpoint_index]
            if not _endpoint_has_receiver(endpoint,river_name,rivers,ponds,world_half):
                failures.append("%s terminates on bare playable terrain at %s"%[river_name,str(endpoint)])
        for index in range(points.size()-1):
            var source_point:Vector2=points[index]
            var downstream_point:Vector2=points[index+1]
            var source_grade:float=builder.call("_river_grade",source_point.x)
            var downstream_grade:float=builder.call("_river_grade",downstream_point.x)
            worst_uphill_rise=maxf(worst_uphill_rise,downstream_grade-source_grade)
            if downstream_grade>source_grade+.025:
                failures.append("%s climbs uphill between route points %d and %d"%[river_name,index,index+1])
                break
        if river_name=="Kingsflow River":
            var mouth:Vector2=points[-1]
            var lake_center:Vector2=westmere.get("position",Vector2.ZERO)
            if mouth.distance_to(lake_center)>float(westmere.get("radius",0.0))*1.18:
                failures.append("Kingsflow does not terminate inside Westmere")
        else:
            var confluence:Vector2=points[-1]
            if _distance_to_polyline(confluence,main_river.get("points",[]))<=4.0:
                connected_tributaries+=1
            else:
                failures.append("%s does not join Kingsflow"%river_name)

    var northwood:Dictionary=_named(rivers,"Northwood Tributary")
    if not northwood.is_empty() and not north_tarn.is_empty():
        var source:Vector2=northwood.get("points",[Vector2.ZERO])[0]
        if source.distance_to(Vector2(north_tarn.get("position",Vector2.ZERO)))>float(north_tarn.get("radius",0.0))*1.18:
            failures.append("Northwood Tributary does not begin at North Tarn")

    var terrain_root:=Node3D.new();root.add_child(terrain_root)
    var terrain:Dictionary=builder.generate_world(terrain_root,profile)
    var river_root:=Node3D.new();root.add_child(river_root)
    WorldPreviewBuilder.new().call("_build_river_ribbons",river_root,rivers,terrain,profile)
    var water_meshes:=0
    var shadow_casting_water:=0
    var bank_collisions:=0
    for child in river_root.get_children():
        if str(child.name).ends_with("_Water"):
            water_meshes+=1
            if int((child as GeometryInstance3D).cast_shadow)!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
                shadow_casting_water+=1
        bank_collisions+=_count_type(child,"CollisionShape3D")
    if water_meshes!=rivers.size():failures.append("not every river produced a continuous water ribbon")
    if shadow_casting_water>0:failures.append("%d river surfaces cast detached shadows"%shadow_casting_water)
    # Riverbank overlays are deliberately render-only. The authoritative
    # terrain heightfield supplies collision, so extra strip collision here
    # would recreate invisible shelves and blocked walkable banks.
    if bank_collisions>0:failures.append("riverbank overlays created %d duplicate collision shapes"%bank_collisions)

    print("RIVER_COHESION|rivers=%d|tributaries_joined=%d|terminal_lakes=%d|water_meshes=%d|bank_collisions=%d|worst_uphill=%.4f|failures=%d"%[
        rivers.size(),connected_tributaries,1 if not westmere.is_empty() else 0,
        water_meshes,bank_collisions,worst_uphill_rise,failures.size(),
    ])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)


func _named(entries:Array,wanted:String)->Dictionary:
    for value in entries:
        if value is Dictionary and str(value.get("name",""))==wanted:return value
    return {}


func _endpoint_has_receiver(endpoint:Vector2,current_name:String,rivers:Array,ponds:Array,world_half:float)->bool:
    if absf(endpoint.x)>=world_half or absf(endpoint.y)>=world_half:return true
    for pond in ponds:
        var center:Vector2=pond.get("position",Vector2.ZERO)
        if endpoint.distance_to(center)<=float(pond.get("radius",0.0))*1.18:return true
    for other in rivers:
        if str(other.get("name","River"))==current_name:continue
        if _distance_to_polyline(endpoint,other.get("points",[]))<=4.0:return true
    return false


func _distance_to_polyline(point:Vector2,points:Array)->float:
    var best:=INF
    for index in range(points.size()-1):
        best=minf(best,point.distance_to(Geometry2D.get_closest_point_to_segment(point,points[index],points[index+1])))
    return best


func _count_type(node:Node,class_name_value:String)->int:
    var count:=1 if node.is_class(class_name_value) else 0
    for child in node.get_children():count+=_count_type(child,class_name_value)
    return count
