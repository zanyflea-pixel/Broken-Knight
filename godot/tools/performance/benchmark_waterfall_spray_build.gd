extends SceneTree

const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var scene_root:=Node3D.new();root.add_child(scene_root)
    var builder:=WorldPreviewBuilder.new()
    builder.call("_make_waterfall_material")
    for attempt in range(3):
        var started:=Time.get_ticks_usec()
        builder.call("_add_waterfall_spray",scene_root,Vector2(float(attempt)*100.0,0.0),4.0,70.0)
        var elapsed:=float(Time.get_ticks_usec()-started)/1000.0
        print("WATERFALL_SPRAY_BUILD|attempt=%d|elapsed_ms=%.3f"%[attempt+1,elapsed])
        await process_frame
        await RenderingServer.frame_post_draw
    scene_root.free()
    quit()
