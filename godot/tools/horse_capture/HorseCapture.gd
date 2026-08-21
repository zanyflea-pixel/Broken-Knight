extends SceneTree


const HORSE_PATH := "res://assets/animals/riverwatch_horse_awesome.bkglb"
const VIEW_SIZE := Vector2i(960, 960)

var capture_viewport: SubViewport
var camera: Camera3D
var horse: Node3D
var horse_bounds := AABB()
var output_dir := ""

var capture_labels: Array[String] = []
var capture_failures: Array[String] = []

var mesh_node_count := 0
var surface_count := 0
var vertex_count := 0
var triangle_count := 0

var material_names: Array[String] = []
var animation_names: Array[String] = []
var bone_names: Array[String] = []


func _init() -> void:
    call_deferred("_run")


func _run() -> void:
    output_dir = OS.get_environment("BK_HORSE_CAPTURE_DIR")

    if output_dir.is_empty():
        _fail("BK_HORSE_CAPTURE_DIR was not supplied.")
        return

    var mkdir_error := DirAccess.make_dir_recursive_absolute(output_dir)

    if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
        _fail("Could not create capture output directory.")
        return

    print("HORSE_CAPTURE|START")
    print("HORSE_CAPTURE|OUTPUT=", output_dir)
    print("HORSE_CAPTURE|SOURCE=", HORSE_PATH)

    _build_capture_world()

    var horse_result := _load_horse()

    if horse_result != OK:
        _fail("Could not load Blender runtime horse. Error=%s" % horse_result)
        return

    await process_frame
    await process_frame

    _freeze_idle_pose()

    await process_frame

    horse_bounds = _calculate_combined_aabb(horse)

    if horse_bounds.size.length_squared() <= 0.000001:
        _fail("Horse geometry produced an empty AABB.")
        return

    _collect_model_metrics(horse)
    _build_floor()

    await process_frame

    var center := horse_bounds.position + horse_bounds.size * 0.5
    var max_dimension := maxf(
        horse_bounds.size.x,
        maxf(
            horse_bounds.size.y,
            horse_bounds.size.z
        )
    )

    var full_distance := max_dimension * 2.05

    print("HORSE_CAPTURE|AABB=", horse_bounds)
    print("HORSE_CAPTURE|CENTER=", center)
    print("HORSE_CAPTURE|MAX_DIMENSION=", max_dimension)

    # ========================================================
    # MAIN 360 DEGREE STUDIO ORBIT
    # 16 views, every 22.5 degrees
    # ========================================================

    for index in range(16):
        var yaw := float(index) * 22.5

        var label := "orbit_%03d" % int(round(yaw))

        var success := await _capture_view(
            label,
            center + Vector3.UP * horse_bounds.size.y * 0.04,
            yaw,
            10.0,
            full_distance,
            36.0
        )

        if not success:
            capture_failures.append(label)

    # ========================================================
    # ELEVATED ORBIT
    # 8 views
    # ========================================================

    for index in range(8):
        var yaw := float(index) * 45.0

        var label := "elevated_%03d" % int(round(yaw))

        var success := await _capture_view(
            label,
            center + Vector3.UP * horse_bounds.size.y * 0.03,
            yaw,
            28.0,
            full_distance * 1.03,
            38.0
        )

        if not success:
            capture_failures.append(label)

    # ========================================================
    # DETAIL TARGETS FROM ACTUAL RIG BONES
    # ========================================================

    var head_target := _get_bone_position(
        "head",
        center + Vector3.UP * horse_bounds.size.y * 0.22
    )

    var body_target := _get_bone_position(
        "body",
        center
    )

    var tail_target := _get_bone_position(
        "tail.1",
        center
    )

    var head_distance := max_dimension * 0.72
    var body_distance := max_dimension * 0.82
    var tail_distance := max_dimension * 0.70

    var details := [
        {
            "label": "closeup_head_a",
            "target": head_target,
            "yaw": 45.0,
            "elevation": 8.0,
            "distance": head_distance,
            "fov": 31.0,
        },
        {
            "label": "closeup_head_b",
            "target": head_target,
            "yaw": 315.0,
            "elevation": 8.0,
            "distance": head_distance,
            "fov": 31.0,
        },
        {
            "label": "closeup_saddle_a",
            "target": body_target + Vector3.UP * horse_bounds.size.y * 0.18,
            "yaw": 65.0,
            "elevation": 18.0,
            "distance": body_distance,
            "fov": 32.0,
        },
        {
            "label": "closeup_saddle_b",
            "target": body_target + Vector3.UP * horse_bounds.size.y * 0.18,
            "yaw": 295.0,
            "elevation": 24.0,
            "distance": body_distance,
            "fov": 32.0,
        },
        {
            "label": "closeup_rump_tail_a",
            "target": tail_target + Vector3.UP * horse_bounds.size.y * 0.04,
            "yaw": 20.0,
            "elevation": 8.0,
            "distance": tail_distance,
            "fov": 32.0,
        },
        {
            "label": "closeup_rump_tail_b",
            "target": tail_target + Vector3.UP * horse_bounds.size.y * 0.04,
            "yaw": 340.0,
            "elevation": 12.0,
            "distance": tail_distance,
            "fov": 32.0,
        },
    ]

    for detail in details:
        var success := await _capture_view(
            str(detail.label),
            detail.target,
            float(detail.yaw),
            float(detail.elevation),
            float(detail.distance),
            float(detail.fov)
        )

        if not success:
            capture_failures.append(str(detail.label))

    _write_reports()

    print("HORSE_CAPTURE|CAPTURES=", capture_labels.size())
    print("HORSE_CAPTURE|FAILURES=", capture_failures.size())
    print("HORSE_CAPTURE|SUCCESS")

    quit(0)


func _build_capture_world() -> void:
    capture_viewport = SubViewport.new()
    capture_viewport.name = "HorseCaptureViewport"
    capture_viewport.size = VIEW_SIZE
    capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    capture_viewport.own_world_3d = true
    capture_viewport.transparent_bg = false

    root.add_child(capture_viewport)

    var environment_node := WorldEnvironment.new()
    var environment := Environment.new()

    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(
        0.105,
        0.115,
        0.135,
        1.0
    )

    environment_node.environment = environment

    capture_viewport.add_child(environment_node)

    # Main sunlight
    var key_light := DirectionalLight3D.new()

    key_light.name = "Studio Key"
    key_light.light_energy = 1.65
    key_light.shadow_enabled = true
    key_light.rotation_degrees = Vector3(
        -48.0,
        -36.0,
        0.0
    )

    capture_viewport.add_child(key_light)

    # Softer opposing fill
    var fill_light := DirectionalLight3D.new()

    fill_light.name = "Studio Fill"
    fill_light.light_energy = 0.72
    fill_light.shadow_enabled = false
    fill_light.rotation_degrees = Vector3(
        -26.0,
        138.0,
        0.0
    )

    capture_viewport.add_child(fill_light)

    # Rim light helps mane / tail silhouettes read.
    var rim_light := DirectionalLight3D.new()

    rim_light.name = "Studio Rim"
    rim_light.light_energy = 0.90
    rim_light.shadow_enabled = false
    rim_light.rotation_degrees = Vector3(
        -12.0,
        218.0,
        0.0
    )

    capture_viewport.add_child(rim_light)

    camera = Camera3D.new()
    camera.name = "Horse Review Camera"
    camera.current = true
    camera.near = 0.025
    camera.far = 250.0

    capture_viewport.add_child(camera)


func _load_horse() -> int:
    if not FileAccess.file_exists(HORSE_PATH):
        return ERR_FILE_NOT_FOUND

    var raw_bytes := FileAccess.get_file_as_bytes(
        HORSE_PATH
    )

    if raw_bytes.is_empty():
        return ERR_FILE_CORRUPT

    var document := GLTFDocument.new()
    var state := GLTFState.new()

    var load_error := document.append_from_buffer(
        raw_bytes,
        HORSE_PATH.get_base_dir(),
        state
    )

    if load_error != OK:
        return load_error

    var generated := document.generate_scene(
        state,
        30.0,
        false,
        true
    )

    if not generated is Node3D:
        return ERR_CANT_CREATE

    horse = generated as Node3D
    horse.name = "Horse Review Model"

    capture_viewport.add_child(horse)

    return OK


func _freeze_idle_pose() -> void:
    var animation_player := _find_animation_player(
        horse
    )

    if animation_player == null:
        return

    for animation_name in animation_player.get_animation_list():
        var text := str(animation_name)

        if text == "Idle" or text.ends_with("|Idle"):
            animation_player.play(
                animation_name
            )

            animation_player.seek(
                0.25,
                true
            )

            animation_player.pause()

            animation_names.append(
                text
            )

            return

    for animation_name in animation_player.get_animation_list():
        animation_names.append(
            str(animation_name)
        )


func _build_floor() -> void:
    var floor_mesh := PlaneMesh.new()

    var floor_size := maxf(
        horse_bounds.size.x,
        horse_bounds.size.z
    ) * 4.0

    floor_mesh.size = Vector2(
        floor_size,
        floor_size
    )

    var floor_material := StandardMaterial3D.new()

    floor_material.albedo_color = Color(
        0.185,
        0.195,
        0.205,
        1.0
    )

    floor_material.roughness = 0.92

    floor_mesh.material = floor_material

    var floor_object := MeshInstance3D.new()

    floor_object.name = "Studio Floor"
    floor_object.mesh = floor_mesh

    var center := horse_bounds.position + horse_bounds.size * 0.5

    floor_object.position = Vector3(
        center.x,
        horse_bounds.position.y - 0.018,
        center.z
    )

    capture_viewport.add_child(
        floor_object
    )


func _capture_view(
    label: String,
    target: Vector3,
    yaw_degrees: float,
    elevation_degrees: float,
    distance: float,
    fov: float
) -> bool:
    camera.fov = fov

    var yaw := deg_to_rad(
        yaw_degrees
    )

    var elevation := deg_to_rad(
        elevation_degrees
    )

    var horizontal_distance := (
        distance
        * cos(elevation)
    )

    var vertical_distance := (
        distance
        * sin(elevation)
    )

    camera.global_position = target + Vector3(
        sin(yaw) * horizontal_distance,
        vertical_distance,
        cos(yaw) * horizontal_distance
    )

    camera.look_at(
        target,
        Vector3.UP
    )

    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw

    var image := capture_viewport.get_texture().get_image()

    if image.is_empty():
        print(
            "HORSE_CAPTURE|EMPTY_IMAGE|",
            label
        )

        return false

    var path := output_dir.path_join(
        label + ".png"
    )

    var save_error := image.save_png(
        path
    )

    if save_error != OK:
        print(
            "HORSE_CAPTURE|SAVE_ERROR|",
            label,
            "|",
            save_error
        )

        return false

    capture_labels.append(
        label
    )

    print(
        "HORSE_CAPTURE|SAVED|",
        path
    )

    return true


func _calculate_combined_aabb(
    node: Node
) -> AABB:
    var points: Array[Vector3] = []

    _collect_aabb_points(
        node,
        points
    )

    if points.is_empty():
        return AABB()

    var minimum := points[0]
    var maximum := points[0]

    for point in points:
        minimum.x = minf(
            minimum.x,
            point.x
        )

        minimum.y = minf(
            minimum.y,
            point.y
        )

        minimum.z = minf(
            minimum.z,
            point.z
        )

        maximum.x = maxf(
            maximum.x,
            point.x
        )

        maximum.y = maxf(
            maximum.y,
            point.y
        )

        maximum.z = maxf(
            maximum.z,
            point.z
        )

    return AABB(
        minimum,
        maximum - minimum
    )


func _collect_aabb_points(
    node: Node,
    points: Array[Vector3]
) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D

        if mesh_instance.mesh != null:
            var bounds := mesh_instance.mesh.get_aabb()

            for xi in range(2):
                for yi in range(2):
                    for zi in range(2):
                        var local_point := bounds.position + Vector3(
                            bounds.size.x * float(xi),
                            bounds.size.y * float(yi),
                            bounds.size.z * float(zi)
                        )

                        points.append(
                            mesh_instance.global_transform
                            * local_point
                        )

    for child in node.get_children():
        _collect_aabb_points(
            child,
            points
        )


func _collect_model_metrics(
    node: Node
) -> void:
    mesh_node_count = 0
    surface_count = 0
    vertex_count = 0
    triangle_count = 0

    material_names.clear()
    bone_names.clear()

    _collect_mesh_metrics(
        node
    )

    var skeleton := _find_skeleton(
        node
    )

    if skeleton != null:
        for bone_index in range(
            skeleton.get_bone_count()
        ):
            bone_names.append(
                skeleton.get_bone_name(
                    bone_index
                )
            )

    var animation_player := _find_animation_player(
        node
    )

    if animation_player != null:
        animation_names.clear()

        for animation_name in animation_player.get_animation_list():
            animation_names.append(
                str(animation_name)
            )


func _collect_mesh_metrics(
    node: Node
) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D

        if mesh_instance.mesh != null:
            mesh_node_count += 1

            var mesh := mesh_instance.mesh

            surface_count += mesh.get_surface_count()

            for surface_index in range(
                mesh.get_surface_count()
            ):
                var surface_material := mesh.surface_get_material(
                    surface_index
                )

                if surface_material != null:
                    var material_name := surface_material.resource_name

                    if material_name.is_empty():
                        material_name = "Unnamed material"

                    if not material_names.has(
                        material_name
                    ):
                        material_names.append(
                            material_name
                        )

                if mesh is ArrayMesh:
                    var array_mesh := mesh as ArrayMesh

                    var arrays := array_mesh.surface_get_arrays(
                        surface_index
                    )

                    if arrays.size() > Mesh.ARRAY_VERTEX:
                        var vertices = arrays[
                            Mesh.ARRAY_VERTEX
                        ]

                        if vertices != null:
                            vertex_count += vertices.size()

                    if arrays.size() > Mesh.ARRAY_INDEX:
                        var indices = arrays[
                            Mesh.ARRAY_INDEX
                        ]

                        if indices != null and indices.size() > 0:
                            triangle_count += int(
                                indices.size() / 3
                            )

    for child in node.get_children():
        _collect_mesh_metrics(
            child
        )


func _get_bone_position(
    bone_name: String,
    fallback: Vector3
) -> Vector3:
    var skeleton := _find_skeleton(
        horse
    )

    if skeleton == null:
        return fallback

    var bone_index := skeleton.find_bone(
        bone_name
    )

    if bone_index < 0:
        return fallback

    var bone_pose := skeleton.get_bone_global_pose(
        bone_index
    )

    return skeleton.global_transform * bone_pose.origin


func _find_skeleton(
    node: Node
) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D

    for child in node.get_children():
        var result := _find_skeleton(
            child
        )

        if result != null:
            return result

    return null


func _find_animation_player(
    node: Node
) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer

    for child in node.get_children():
        var result := _find_animation_player(
            child
        )

        if result != null:
            return result

    return null


func _write_reports() -> void:
    var size := horse_bounds.size

    var largest := maxf(
        size.x,
        maxf(
            size.y,
            size.z
        )
    )

    var smallest := minf(
        size.x,
        minf(
            size.y,
            size.z
        )
    )

    var report_lines: Array[String] = []

    report_lines.append(
        "BROKEN KNIGHT HORSE CAPTURE REVIEW"
    )

    report_lines.append(
        "=================================="
    )

    report_lines.append(
        ""
    )

    report_lines.append(
        "SOURCE=" + HORSE_PATH
    )

    report_lines.append(
        "CAPTURE_COUNT=%d" % capture_labels.size()
    )

    report_lines.append(
        "CAPTURE_FAILURES=%d" % capture_failures.size()
    )

    report_lines.append(
        ""
    )

    report_lines.append(
        "MODEL METRICS"
    )

    report_lines.append(
        "-------------"
    )

    report_lines.append(
        "BOUNDING_WIDTH_X=%.4f" % size.x
    )

    report_lines.append(
        "BOUNDING_HEIGHT_Y=%.4f" % size.y
    )

    report_lines.append(
        "BOUNDING_LENGTH_Z=%.4f" % size.z
    )

    report_lines.append(
        "LARGEST_DIMENSION=%.4f" % largest
    )

    report_lines.append(
        "SMALLEST_DIMENSION=%.4f" % smallest
    )

    if size.y > 0.00001:
        report_lines.append(
            "WIDTH_TO_HEIGHT=%.4f" % (
                size.x / size.y
            )
        )

        report_lines.append(
            "LENGTH_TO_HEIGHT=%.4f" % (
                size.z / size.y
            )
        )

    report_lines.append(
        "MESH_NODE_COUNT=%d" % mesh_node_count
    )

    report_lines.append(
        "SURFACE_COUNT=%d" % surface_count
    )

    report_lines.append(
        "VERTEX_COUNT_APPROX=%d" % vertex_count
    )

    report_lines.append(
        "TRIANGLE_COUNT_APPROX=%d" % triangle_count
    )

    report_lines.append(
        ""
    )

    report_lines.append(
        "MATERIALS"
    )

    report_lines.append(
        "---------"
    )

    for material_name in material_names:
        report_lines.append(
            material_name
        )

    report_lines.append(
        ""
    )

    report_lines.append(
        "ANIMATIONS"
    )

    report_lines.append(
        "----------"
    )

    for animation_name in animation_names:
        report_lines.append(
            animation_name
        )

    report_lines.append(
        ""
    )

    report_lines.append(
        "RIG BONES"
    )

    report_lines.append(
        "---------"
    )

    for bone_name in bone_names:
        report_lines.append(
            bone_name
        )

    report_lines.append(
        ""
    )

    report_lines.append(
        "CAPTURE FILES"
    )

    report_lines.append(
        "-------------"
    )

    for capture_label in capture_labels:
        report_lines.append(
            capture_label + ".png"
        )

    report_lines.append(
        ""
    )

    report_lines.append(
        "NEXT HORSE PASS REVIEW CHECKLIST"
    )

    report_lines.append(
        "-------------------------------"
    )

    report_lines.append(
        "1. SIDE SILHOUETTE: inspect orbit_090 and orbit_270 for chest, back, belly, rump, leg proportions."
    )

    report_lines.append(
        "2. RUMP: inspect rear three-quarter orbit views for roundness, croup slope and tail-root transition."
    )

    report_lines.append(
        "3. MANE: inspect dark silhouette against the neck; it should read as one flowing crest rather than separate tubes."
    )

    report_lines.append(
        "4. TAIL: inspect closeup_rump_tail_a/b for one continuous root, volume through the middle and a natural taper."
    )

    report_lines.append(
        "5. SADDLE: inspect closeup_saddle_a/b for seat curvature, pommel/cantle proportions, blanket fit and whether anything floats."
    )

    report_lines.append(
        "6. HEAD: inspect closeup_head_a/b for muzzle taper, cheek/jaw structure, ear size, eye placement and forehead shape."
    )

    report_lines.append(
        "7. LEGS: inspect side and three-quarter views for knee/hock anatomy, cannon-bone thickness and hoof angle."
    )

    report_lines.append(
        "8. FRONT/REAR SYMMETRY: use opposing orbit angles to spot asymmetrical floating tack or geometry."
    )

    report_lines.append(
        "9. TACK SCALE: saddle, bags, reins and stirrups should support the horse rather than dominate its silhouette."
    )

    report_lines.append(
        "10. OVERALL READ: the horse should still look convincingly equine when viewed only as a silhouette."
    )

    report_lines.append(
        ""
    )

    report_lines.append(
        "BEST FILES TO SEND CHATGPT"
    )

    report_lines.append(
        "--------------------------"
    )

    report_lines.append(
        "contact_sheet.png"
    )

    report_lines.append(
        "horse_capture_report.txt"
    )

    report_lines.append(
        "horse_capture_metrics.json"
    )

    report_lines.append(
        "Then send individual closeups only if a specific area needs more inspection."
    )

    var report_path := output_dir.path_join(
        "horse_capture_report.txt"
    )

    var report_file := FileAccess.open(
        report_path,
        FileAccess.WRITE
    )

    if report_file != null:
        report_file.store_string(
            "\n".join(report_lines)
        )

        report_file.close()

    var metrics := {
        "source": HORSE_PATH,
        "capture_count": capture_labels.size(),
        "capture_failures": capture_failures,
        "bounds": {
            "width_x": size.x,
            "height_y": size.y,
            "length_z": size.z,
        },
        "mesh_nodes": mesh_node_count,
        "surfaces": surface_count,
        "vertices_approx": vertex_count,
        "triangles_approx": triangle_count,
        "materials": material_names,
        "animations": animation_names,
        "bones": bone_names,
        "captures": capture_labels,
    }

    var metrics_path := output_dir.path_join(
        "horse_capture_metrics.json"
    )

    var metrics_file := FileAccess.open(
        metrics_path,
        FileAccess.WRITE
    )

    if metrics_file != null:
        metrics_file.store_string(
            JSON.stringify(
                metrics,
                "\t"
            )
        )

        metrics_file.close()


func _fail(message: String) -> void:
    print(
        "HORSE_CAPTURE|FAILED|",
        message
    )

    if not output_dir.is_empty():
        var failure_file := FileAccess.open(
            output_dir.path_join(
                "CAPTURE_FAILED.txt"
            ),
            FileAccess.WRITE
        )

        if failure_file != null:
            failure_file.store_string(
                message
            )

            failure_file.close()

    quit(1)