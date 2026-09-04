extends SceneTree

const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")
const ZONES:=[
    "starting_realm","north_frontier","glacial_range","western_reaches",
    "stormbreak_highlands","skeld_coast","east_marches",
]


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var river_surfaces:=0
    var still_surfaces:=0
    var cascades:=0
    var foam_pools:=0
    var profile_source:=WorldProfile.new()
    for zone_id in ZONES:
        var profile:Dictionary=profile_source.make_old_world_profile() if zone_id=="starting_realm" else profile_source.make_zone_profile(zone_id)
        var bake_path:=WorldPreviewBuilder.STARTING_VISUAL_BAKE_PATH if zone_id=="starting_realm" else WorldPreviewBuilder.streamed_visual_bake_path(zone_id)
        var packed:=load(bake_path) as PackedScene
        if packed==null:
            failures.append("%s visual bake is missing"%zone_id)
            continue
        var bake:=packed.instantiate()
        root.add_child(bake)
        var river_root:=bake.get_node_or_null("RiverRoot")
        if river_root==null:
            failures.append("%s has no RiverRoot"%zone_id)
            bake.free()
            continue
        for river_value in profile.get("river_corridors",[]):
            var river:Dictionary=river_value
            var node:=river_root.find_child("%s_Water"%str(river.get("name","River")),true,false) as MeshInstance3D
            if node==null:
                failures.append("%s/%s has no water surface"%[zone_id,str(river.get("name","River"))])
                continue
            river_surfaces+=1
            var material:=node.material_override as ShaderMaterial
            if material==null:
                failures.append("%s/%s does not use the water shader"%[zone_id,node.name])
                continue
            if float(material.get_shader_parameter("flow_strength"))<.99:
                failures.append("%s/%s has no downstream current cue"%[zone_id,node.name])
            var code:=material.shader.code
            if "UV.y * 4.1 - TIME * 2.45" not in code or "water_depth" not in code:
                failures.append("%s/%s omits directional flow or depth shading"%[zone_id,node.name])
            if node.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
                failures.append("%s/%s casts a detached water shadow"%[zone_id,node.name])
        for pond_value in profile.get("pond_sites",[]):
            var pond:Dictionary=pond_value
            var pond_node:=river_root.find_child("%s_Water"%str(pond.get("name","Pond")),true,false) as MeshInstance3D
            if pond_node==null:continue
            still_surfaces+=1
            var pond_material:=pond_node.material_override as ShaderMaterial
            if pond_material and float(pond_material.get_shader_parameter("flow_strength"))>.01:
                failures.append("%s/%s incorrectly uses river-direction stripes"%[zone_id,pond_node.name])
        cascades+=river_root.find_children("*_Cascade_*","MeshInstance3D",true,false).size()
        foam_pools+=river_root.find_children("Waterfall Foam","MeshInstance3D",true,false).size()
        bake.free()
    if river_surfaces<13:failures.append("only %d river surfaces were verified"%river_surfaces)
    if still_surfaces<7:failures.append("only %d still pond/lake surfaces were verified"%still_surfaces)
    if cascades<9 or foam_pools<6:failures.append("waterfall foam coverage is incomplete (%d cascades, %d foam pools)"%[cascades,foam_pools])
    print("WATER_SURFACE_VISUAL|rivers=%d|still_water=%d|cascades=%d|foam_pools=%d|failures=%d"%[
        river_surfaces,still_surfaces,cascades,foam_pools,failures.size(),
    ])
    for failure in failures:push_error("WATER_SURFACE_VISUAL_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
