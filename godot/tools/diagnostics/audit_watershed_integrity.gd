extends SceneTree

const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")


func _init()->void:
    call_deferred("_run")


func _run()->void:
    var profile:Dictionary=WorldProfile.new().make_zone_profile("starting_realm")
    var terrain_root:=Node3D.new();root.add_child(terrain_root)
    var terrain_builder:=TerrainBuilder.new()
    var world:Dictionary=terrain_builder.generate_world(terrain_root,profile)
    var preview:=WorldPreviewBuilder.new()
    var terrain:Callable=world.terrain_height_sampler
    var land:Callable=world.land_surface_sampler
    var river_bed:Callable=world.river_height_sampler
    var exposed:=0
    var flooded_banks:=0
    var samples:=0
    var minimum_clearance:=INF
    var minimum_bank_margin:=INF
    var worst_clearance_site:={"river":"","point":Vector2.ZERO,"fraction":0.0}
    var worst_bank_site:={"river":"","point":Vector2.ZERO}
    var max_water_grade:=0.0
    var max_bank_grade:=0.0
    var grid_step:float=float(profile.get("world_size",7200.0))/maxf(1.0,float(profile.get("grid_resolution",320)))
    var river_reports:Array=[]
    var previous_mouth_y:=NAN
    for river_index in range(profile.get("river_corridors",[]).size()):
        var river:Dictionary=profile.river_corridors[river_index]
        var points:Array=preview.call("_subdivide_polyline",river.get("points",[]),1)
        var half_water:=float(river.get("width",48.0))*.84*.5
        var river_exposed:=0
        var river_flooded:=0
        var last_center:=Vector3.ZERO
        var has_last:=false
        for segment_index in range(points.size()-1):
            var a:Vector2=points[segment_index]
            var b:Vector2=points[segment_index+1]
            var length:=a.distance_to(b)
            var steps:=maxi(1,ceili(length/12.0))
            var tangent:Vector2=(b-a).normalized()
            var normal:=Vector2(-tangent.y,tangent.x)
            for step in range(steps):
                var center:=a.lerp(b,(float(step)+.5)/float(steps))
                var center_water:Vector3=river_bed.call(center.x,center.y)+Vector3.UP*2.35
                if has_last:
                    var horizontal:=Vector2(last_center.x,last_center.z).distance_to(center)
                    max_water_grade=maxf(max_water_grade,absf(center_water.y-last_center.y)/maxf(.001,horizontal))
                last_center=center_water;has_last=true
                for fraction in [-1.0,-.66,-.33,0.0,.33,.66,1.0]:
                    var q:=center+normal*half_water*float(fraction)
                    var water_y:float=(river_bed.call(q.x,q.y) as Vector3).y+2.35
                    var ground_y:float=(terrain.call(q.x,q.y) as Vector3).y
                    var clearance:=water_y-ground_y
                    if clearance<minimum_clearance:
                        minimum_clearance=clearance
                        worst_clearance_site={"river":river.get("name","River"),"point":q,"fraction":fraction}
                    if clearance<.025:
                        exposed+=1;river_exposed+=1
                    samples+=1
                for side in [-1.0,1.0]:
                    var outer_distance:=half_water+grid_step*1.65+10.0
                    var bank:=center+normal*outer_distance*float(side)
                    var bank_water_y:float=(river_bed.call(bank.x,bank.y) as Vector3).y+2.35
                    var bank_floor:=center_water.y+.14
                    var bank_cap:=bank_floor+maxf(2.0,(outer_distance-half_water-8.0)*.48)
                    var bank_y:float=clampf((land.call(bank.x,bank.y) as Vector3).y+.06,bank_floor,bank_cap)
                    var margin:=bank_y-center_water.y
                    max_bank_grade=maxf(max_bank_grade,absf(bank_y-(center_water.y+.255))/maxf(1.0,outer_distance-half_water-8.0))
                    if margin<minimum_bank_margin:
                        minimum_bank_margin=margin
                        worst_bank_site={"river":river.get("name","River"),"point":bank}
                    if margin<.08:
                        flooded_banks+=1;river_flooded+=1
        var mouth:Vector2=points[-1]
        var mouth_y:float=(river_bed.call(mouth.x,mouth.y) as Vector3).y+2.35
        if river_index==0:previous_mouth_y=mouth_y
        river_reports.append({"name":river.get("name","River"),"exposed":river_exposed,"flooded":river_flooded,"mouth_y":mouth_y})

    var pond_land_patches:=0
    var pond_samples:=0
    var shallowest_pond:=INF
    for pond in profile.get("pond_sites",[]):
        var center:Vector2=pond.get("position",Vector2.ZERO)
        var radius:float=float(pond.get("radius",70.0))*1.18
        var water_y:float=float(pond.get("water_height",1.2))+.055
        for ring in [0.0,.32,.58,.76]:
            for index in range(24):
                var angle:=float(index)/24.0*TAU
                var irregularity:=1.0+sin(angle*3.0+center.x*.0017)*.11+sin(angle*7.0+center.y*.0011)*.055
                var point:=center+Vector2(cos(angle),sin(angle))*radius*irregularity*float(ring)
                var depth:=water_y-(terrain.call(point.x,point.y) as Vector3).y
                shallowest_pond=minf(shallowest_pond,depth)
                if depth<.025:pond_land_patches+=1
                pond_samples+=1

    var waterfall_error:=0.0
    for waterfall in profile.get("waterfall_sites",[]):
        var point:Vector2=waterfall.get("position",Vector2.ZERO)
        var river_y:float=(river_bed.call(point.x,point.y) as Vector3).y+2.35
        var authored_top:float=float(terrain_builder.call("_river_grade",point.x))-.60
        waterfall_error=maxf(waterfall_error,absf(river_y-authored_top))

    print("WATERSHED_AUDIT|samples=%d|exposed=%d|min_clearance=%.3f|flooded_banks=%d|min_bank_margin=%.3f|max_water_grade=%.3f|max_bank_grade=%.3f|pond_samples=%d|pond_land=%d|pond_min_depth=%.3f|waterfall_error=%.3f"%[
        samples,exposed,minimum_clearance,flooded_banks,minimum_bank_margin,max_water_grade,max_bank_grade,
        pond_samples,pond_land_patches,shallowest_pond,waterfall_error,
    ])
    print("WATERSHED_WORST|water=%s@%s|fraction=%.2f|bank=%s@%s"%[
        worst_clearance_site.river,str(worst_clearance_site.point),float(worst_clearance_site.fraction),
        worst_bank_site.river,str(worst_bank_site.point),
    ])
    for report in river_reports:print("WATERSHED_RIVER|%s|exposed=%d|flooded_banks=%d|mouth_y=%.3f"%[report.name,report.exposed,report.flooded,report.mouth_y])
    var failures:=0
    if exposed>0:failures+=1
    if flooded_banks>0:failures+=1
    if max_water_grade>.085:failures+=1
    if pond_land_patches>0:failures+=1
    if waterfall_error>.16:failures+=1
    terrain_root.free()
    quit(0 if failures==0 else 1)
