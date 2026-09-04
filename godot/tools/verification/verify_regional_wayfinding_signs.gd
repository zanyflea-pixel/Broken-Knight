extends SceneTree

const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")
const MINIMUM_SIGNS:={
    "starting_realm":5,
    "north_frontier":3,
    "glacial_range":2,
    "western_reaches":3,
    "stormbreak_highlands":3,
    "skeld_coast":3,
    "east_marches":4,
}


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var total_signs:=0
    var total_labels:=0
    var region_counts:Array[String]=[]
    for zone_id_value in MINIMUM_SIGNS.keys():
        var zone_id:=str(zone_id_value)
        var bake_path:=WorldPreviewBuilder.STARTING_VISUAL_BAKE_PATH if zone_id=="starting_realm" else WorldPreviewBuilder.streamed_visual_bake_path(zone_id)
        var packed:=load(bake_path) as PackedScene
        if packed==null:
            failures.append("Missing visual bake for %s"%zone_id)
            continue
        var bake_root:=packed.instantiate()
        root.add_child(bake_root)
        var road_root:=bake_root.get_node_or_null("RoadRoot")
        if road_root==null:
            failures.append("%s bake has no RoadRoot"%zone_id)
            bake_root.free()
            continue
        var signs:Array[Node]=[]
        for candidate in road_root.find_children("*","Node3D",true,false):
            if candidate.has_meta("regional_travel_sign"):signs.append(candidate)
        if signs.size()<int(MINIMUM_SIGNS[zone_id]):
            failures.append("%s has only %d regional signs (expected at least %d)"%[zone_id,signs.size(),int(MINIMUM_SIGNS[zone_id])])
        region_counts.append("%s:%d"%[zone_id,signs.size()])
        total_signs+=signs.size()
        for sign in signs:
            var labels:=sign.find_children("*","Label3D",true,false)
            var expected_labels:=int(sign.get_meta("destination_count",0))
            if labels.size()!=expected_labels:
                failures.append("%s/%s has %d labels for %d destinations"%[zone_id,sign.name,labels.size(),expected_labels])
            if sign.find_children("*","StaticBody3D",true,false).is_empty():
                failures.append("%s/%s has no physical sign collision"%[zone_id,sign.name])
            for label_value in labels:
                var label:=label_value as Label3D
                total_labels+=1
                if label.double_sided:failures.append("%s/%s label is readable through its wooden back"%[zone_id,sign.name])
                if label.billboard!=BaseMaterial3D.BILLBOARD_DISABLED:failures.append("%s/%s label billboards instead of staying attached"%[zone_id,sign.name])
                if " KM" not in label.text and " M" not in label.text:failures.append("%s/%s omits useful distance"%[zone_id,sign.name])
                if "HIGHFIELD  NORTH\nWESTMERE" in label.text:failures.append("%s still carries the obsolete universal Riverwatch board"%zone_id)
        bake_root.free()
    print("REGIONAL_WAYFINDING|signs=%d|labels=%d|regions=%s|failures=%d"%[
        total_signs,total_labels,",".join(region_counts),failures.size(),
    ])
    for failure in failures:push_error("REGIONAL_WAYFINDING_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
