extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")
const SITE_FRAMES:=90
const SITES:=[
    {"zone":"starting_realm","point":Vector2(0.0,360.0),"yaw":0.0},
    {"zone":"north_frontier","point":Vector2(0.0,-7200.0),"yaw":PI},
    {"zone":"glacial_range","point":Vector2(0.0,-14400.0),"yaw":PI},
    {"zone":"stormbreak_highlands","point":Vector2(-7200.0,-7200.0),"yaw":-PI*.5},
    {"zone":"skeld_coast","point":Vector2(-7200.0,-14400.0),"yaw":PI},
    {"zone":"western_reaches","point":Vector2(-7200.0,0.0),"yaw":-PI*.5},
    {"zone":"east_marches","point":Vector2(7200.0,0.0),"yaw":PI*.5},
]


func _initialize()->void:
    call_deferred("_run")


func _percentile(values:Array[float],fraction:float)->float:
    if values.is_empty():return 0.0
    return values[clampi(roundi(float(values.size()-1)*fraction),0,values.size()-1)]


func _memory_sample(label:String,main:Node)->Dictionary:
    RenderingServer.force_sync()
    var static_bytes:=int(Performance.get_monitor(Performance.MEMORY_STATIC))
    var static_peak_bytes:=int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX))
    var vram_bytes:=0
    var texture_bytes:=0
    var buffer_bytes:=0
    var rendering_device:=RenderingServer.get_rendering_device()
    if rendering_device!=null and rendering_device.has_method("get_memory_usage"):
        texture_bytes=int(rendering_device.get_memory_usage(RenderingDevice.MEMORY_TEXTURES))
        buffer_bytes=int(rendering_device.get_memory_usage(RenderingDevice.MEMORY_BUFFERS))
        vram_bytes=int(rendering_device.get_memory_usage(RenderingDevice.MEMORY_TOTAL))
    var loaded:=0
    for zone_id in main.get("_region_contexts").keys():
        if str(zone_id)!="starting_realm":loaded+=1
    var sample:={
        "label":label,"static":static_bytes,"static_peak":static_peak_bytes,
        "vram":vram_bytes,"textures":texture_bytes,"buffers":buffer_bytes,"loaded":loaded,
    }
    print("RENDERED_ATLAS_MEMORY_STAGE|label=%s|loaded=%d|static_mb=%.1f|static_peak_mb=%.1f|vram_mb=%.1f|textures_mb=%.1f|buffers_mb=%.1f|objects=%d"%[
        label,loaded,float(static_bytes)/1048576.0,float(static_peak_bytes)/1048576.0,
        float(vram_bytes)/1048576.0,float(texture_bytes)/1048576.0,float(buffer_bytes)/1048576.0,
        int(Performance.get_monitor(Performance.OBJECT_COUNT)),
    ])
    return sample


func _activate_site(main:Node,player:CharacterBody3D,site:Dictionary,load_if_needed:bool)->Array[float]:
    var zone_id:=str(site.zone)
    if zone_id!="starting_realm" and load_if_needed:
        await main._ensure_streamed_region_loaded(zone_id)
    var point:Vector2=site.point
    player.global_position=main._sample_global_height(point.x,point.y)+Vector3.UP*.08
    if zone_id!=str(main.get("_active_zone_id")):
        await main._activate_streamed_gameplay_region(zone_id)
    main._update_region_visual_residency(point.x,point.y)
    player.set("_yaw",float(site.yaw))
    player.get_node("CameraPivot").rotation.y=float(site.yaw)
    var samples:Array[float]=[]
    for frame_index in range(SITE_FRAMES):
        var phase:=float(frame_index)*.071
        var travel_point:=point+Vector2(cos(phase),sin(phase))*36.0
        player.global_position=main._sample_global_height(travel_point.x,travel_point.y)+Vector3.UP*.08
        main._update_region_streaming(.25)
        var started:=Time.get_ticks_usec()
        await process_frame
        samples.append(float(Time.get_ticks_usec()-started)/1000.0)
    return samples


func _run()->void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps=0
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var player:=main.get_node("Player") as CharacterBody3D
    var horses:=get_nodes_in_group("rideable_horse")
    if not horses.is_empty():player.mount_horse(horses[0])
    for _warmup in range(120):await process_frame

    var memory_samples:Array[Dictionary]=[]
    memory_samples.append(_memory_sample("starter_warm",main))
    var frame_samples:Array[float]=[]
    # First pass makes every authored region renderer-visible at least once,
    # rather than measuring only CPU-resident packed scenes or hidden tiles.
    for site in SITES.slice(1):
        frame_samples.append_array(await _activate_site(main,player,site,true))
        memory_samples.append(_memory_sample("loaded_%s"%str(site.zone),main))

    # Revisit the complete footprint after all seven regions are resident.
    # This models a long play session and verifies that residency suspension
    # does not require duplicate GPU resources when a retained tile wakes.
    for site in SITES:
        frame_samples.append_array(await _activate_site(main,player,site,false))
        memory_samples.append(_memory_sample("revisit_%s"%str(site.zone),main))

    frame_samples.sort()
    var baseline:Dictionary=memory_samples[0]
    var final_sample:Dictionary=memory_samples[-1]
    var peak_static:=0
    var peak_vram:=0
    for sample in memory_samples:
        peak_static=maxi(peak_static,int(sample.static_peak))
        peak_vram=maxi(peak_vram,int(sample.vram))
    var visible_zones:Array[String]=[]
    for zone_id in main.get("_region_contexts").keys():
        var context:Dictionary=main.get("_region_contexts")[zone_id]
        var region_root:=context.get("root") as Node3D
        if not is_instance_valid(region_root):continue
        if str(zone_id)=="starting_realm":
            var starter_towns:=region_root.get_node_or_null("TownRoot") as Node3D
            if is_instance_valid(starter_towns) and starter_towns.visible:visible_zones.append(str(zone_id))
        elif region_root.visible:
            visible_zones.append(str(zone_id))
    print("RENDERED_ATLAS_MEMORY_SUMMARY|adapter=%s|loaded=%d|visible=%s|mounted=%s|baseline_static_mb=%.1f|final_static_mb=%.1f|retained_static_mb=%.1f|peak_static_mb=%.1f|final_vram_mb=%.1f|peak_vram_mb=%.1f|p95_ms=%.2f|p99_ms=%.2f|max_ms=%.2f"%[
        RenderingServer.get_video_adapter_name(),int(final_sample.loaded),",".join(visible_zones),str(player.is_mounted()),
        float(baseline.static)/1048576.0,float(final_sample.static)/1048576.0,
        float(int(final_sample.static)-int(baseline.static))/1048576.0,float(peak_static)/1048576.0,
        float(final_sample.vram)/1048576.0,float(peak_vram)/1048576.0,
        _percentile(frame_samples,.95),_percentile(frame_samples,.99),frame_samples[-1],
    ])
    main.free()
    for _cleanup in range(8):await process_frame
    quit()
