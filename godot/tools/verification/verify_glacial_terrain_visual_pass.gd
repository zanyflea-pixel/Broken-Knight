extends SceneTree

const TERRAIN_SOURCE := "res://scripts/world/TerrainBuilder.gd"


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var failures: Array[String] = []
    var source := FileAccess.get_file_as_string(TERRAIN_SOURCE)
    var required_markers := [
        "stone_uv_cross",
        "glacier_uv_a",
        "glacier_uv_b",
        "glacier_detail",
        "final_glacial_snow_cover",
        "snow_normal_smoothing",
        "EMISSION = vec3(0.0)",
    ]
    for marker in required_markers:
        if source.find(marker) < 0:
            failures.append("terrain shader lost %s" % marker)

    var glacial_start := source.find("if (glacial_biome > 0.5)")
    var glacial_end := source.find("if (marcher_biome > 0.5)", glacial_start)
    if glacial_start < 0 or glacial_end <= glacial_start:
        failures.append("glacial terrain composition block is missing")
    else:
        var glacial_block := source.substr(glacial_start, glacial_end - glacial_start)
        if glacial_block.find("world_position.y") >= 0:
            failures.append("glacial color again depends on coarse triangle height")
        if glacial_block.find("NORMAL.y") >= 0:
            failures.append("glacial color again depends on coarse triangle slope")
        if glacial_block.find("sin(") >= 0:
            failures.append("glacial color again contains long striped sine bands")
        if glacial_block.find("stone_albedo") >= 0:
            failures.append("glacial color again exposes repeated stone photography")

    var captures := [
        "res://artifacts/glacial_terrain_walking_v1.png",
        "res://artifacts/glacial_moraine_walking_v1.png",
    ]
    var capture_bytes := 0
    for capture in captures:
        if not FileAccess.file_exists(capture):
            failures.append("missing walking-height visual proof %s" % capture)
        else:
            capture_bytes += FileAccess.get_file_as_bytes(capture).size()

    print("GLACIAL_TERRAIN_VISUAL_PASS|rotated_fields=3|captures=%d|capture_bytes=%d|failures=%d" % [
        captures.size(), capture_bytes, failures.size(),
    ])
    for failure in failures:
        push_error("GLACIAL_TERRAIN_VISUAL_FAILURE|%s" % failure)
    quit(0 if failures.is_empty() else 1)
