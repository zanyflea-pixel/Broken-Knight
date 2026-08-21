extends SceneTree

const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldProfile=preload("res://scripts/world/WorldProfile.gd")


func _init()->void:
    call_deferred("_run")


func _run()->void:
    var profile:Dictionary=WorldProfile.new().make_zone_profile("starting_realm")
    var terrain_root:=Node3D.new()
    root.add_child(terrain_root)
    var builder:=TerrainBuilder.new()
    var world:Dictionary=builder.generate_world(terrain_root,profile)
    var sampler:Callable=world.terrain_height_sampler
    var walk_sampler:Callable=world.height_sampler

    for site_value in [profile.get("spawn_site",{})]+profile.get("town_sites",[]):
        var site:Dictionary=site_value
        var center:Vector2=site.get("position",Vector2.ZERO)
        var radius:float=float(site.get("radius",100.0))*.68
        var minimum:=INF
        var maximum:=-INF
        for ring in [0.0,.45,.82]:
            for index in range(16):
                var angle:=float(index)/16.0*TAU
                var point:=center+Vector2(cos(angle),sin(angle))*radius*float(ring)
                var height:float=(sampler.call(point.x,point.y) as Vector3).y
                minimum=minf(minimum,height)
                maximum=maxf(maximum,height)
        print("ELEVATION_TOWN|%s|height=%.2f|pad_delta=%.3f"%[site.get("name","Town"),(sampler.call(center.x,center.y) as Vector3).y,maximum-minimum])

    var sites:Array=[]
    sites.append_array(profile.get("landmark_sites",[]))
    sites.append_array(profile.get("map_sites",[]))
    for site_value in sites:
        var site:Dictionary=site_value
        if str(site.get("kind","")) not in ["outcrop","ruin","watchtower","castle","windmill"]:continue
        var center:Vector2=site.get("position",Vector2.ZERO)
        var radius:float=float(site.get("elevation_radius",site.get("radius",120.0)))
        radius=maxf(radius,90.0)
        var center_height:float=(sampler.call(center.x,center.y) as Vector3).y
        var ring_total:=0.0
        for index in range(16):
            var angle:=float(index)/16.0*TAU
            var point:=center+Vector2(cos(angle),sin(angle))*radius
            ring_total+=(sampler.call(point.x,point.y) as Vector3).y
        var prominence:=center_height-ring_total/16.0
        print("ELEVATION_SITE|%s|kind=%s|height=%.2f|prominence=%.2f|radius=%.1f"%[site.get("name","Site"),site.get("kind",""),center_height,prominence,radius])

    for region_value in profile.get("landform_regions",[]):
        var region:Dictionary=region_value
        if str(region.get("kind",""))!="ridge":continue
        var center:Vector2=region.get("center",Vector2.ZERO)
        var normal:=Vector2(0.0,1.0).rotated(float(region.get("angle",0.0)))
        var flank_distance:=float(region.get("width",260.0))*.88
        var crown:float=(sampler.call(center.x,center.y) as Vector3).y
        var left:Vector2=center-normal*flank_distance
        var right:Vector2=center+normal*flank_distance
        var flank_average:=((sampler.call(left.x,left.y) as Vector3).y+(sampler.call(right.x,right.y) as Vector3).y)*.5
        print("ELEVATION_RIDGE|%s|crown=%.2f|flanks=%.2f|prominence=%.2f"%[region.get("name","Ridge"),crown,flank_average,crown-flank_average])

    for site_value in builder.get("_bridge_sites_cache"):
        var site:Dictionary=site_value
        var center:Vector2=site.get("position",Vector2.ZERO)
        var direction:Vector2=site.get("direction",Vector2.UP)
        var river_width:float=float(site.get("river_width",52.0))
        var road_width:float=float(site.get("road_width",10.0))
        var half_run:=maxf(river_width+10.0,road_width*2.15)*.5+8.0
        var local_step:=0.0
        var last_height:=0.0
        for index in range(13):
            var point:=center+direction*lerpf(-half_run,half_run,float(index)/12.0)
            var height:float=(walk_sampler.call(point.x,point.y) as Vector3).y
            if index>0:local_step=maxf(local_step,absf(height-last_height))
            last_height=height
        print("ELEVATION_BRIDGE|%s|max_step=%.3f"%[site.get("name","Bridge"),local_step])

    terrain_root.free()
    quit()
