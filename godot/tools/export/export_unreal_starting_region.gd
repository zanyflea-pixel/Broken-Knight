extends SceneTree

const WorldProfileScript = preload("res://scripts/world/WorldProfile.gd")
const TerrainBuilderScript = preload("res://scripts/world/TerrainBuilder.gd")

const OUTPUT_DIR := "C:/Users/Jimmy/Desktop/Broken Knight Unreal/SourceData/StartingRegion"
const EXPORT_RESOLUTION := 1009
# Keep Unreal migration generation isolated from the playable Godot cache.
# Reusing that cache allowed an older terrain bake to be mislabeled with the
# current source checksums, leaving river profiles and terrain out of sync.
const EXPORT_CACHE_REVISION := 1


func _initialize() -> void:
	call_deferred("_export_starting_region")


func _export_starting_region() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var profile: Dictionary = WorldProfileScript.new().make_zone_profile("starting_realm")
	var generation_profile: Dictionary = profile.duplicate(true)
	generation_profile["zone_id"] = "%s_unreal_export_v%d" % [
		str(profile.get("zone_id", "starting_realm")),
		EXPORT_CACHE_REVISION,
	]
	var terrain_builder = TerrainBuilderScript.new()
	var source_resolution: int = int(generation_profile.get("grid_resolution", 320))
	var world_size: float = float(generation_profile.get("world_size", 7200.0))
	var cache_path: String = terrain_builder.call("_terrain_cache_path", generation_profile)
	var cache: Dictionary = terrain_builder.call(
		"_load_heightfield_cache",
		cache_path,
		(source_resolution + 1) * (source_resolution + 1)
	)
	if cache.is_empty():
		var terrain_root := Node3D.new()
		get_root().add_child(terrain_root)
		terrain_builder.generate_world(terrain_root, generation_profile)
		cache = terrain_builder.call(
			"_load_heightfield_cache",
			cache_path,
			(source_resolution + 1) * (source_resolution + 1)
		)
		terrain_root.queue_free()
	if cache.is_empty():
		push_error("Unable to load or generate the authoritative starting-region heightfield.")
		quit(2)
		return

	var source_heights: PackedFloat32Array = cache.get("heights", PackedFloat32Array())
	var export_heights := PackedFloat32Array()
	export_heights.resize(EXPORT_RESOLUTION * EXPORT_RESOLUTION)
	var minimum_height := INF
	var maximum_height := -INF
	for row in range(EXPORT_RESOLUTION):
		var z := lerpf(-world_size * 0.5, world_size * 0.5, float(row) / float(EXPORT_RESOLUTION - 1))
		for column in range(EXPORT_RESOLUTION):
			var x := lerpf(-world_size * 0.5, world_size * 0.5, float(column) / float(EXPORT_RESOLUTION - 1))
			var height: float = terrain_builder.call(
				"_sample_heightfield", x, z, source_heights, world_size, source_resolution
			)
			# Reassert the river after all coarse Godot settlement and slope
			# stabilization passes. The playable cache intentionally prioritizes
			# collision repair, but its broad town feather could refill a channel
			# before export. Unreal receives a denser 1009-sample Landscape, so the
			# final river bed can be clean, continuous and naturally banked here.
			height = _apply_unreal_river_export_carve(
				height, Vector2(x, z), generation_profile, terrain_builder
			)
			var index := row * EXPORT_RESOLUTION + column
			export_heights[index] = height
			minimum_height = minf(minimum_height, height)
			maximum_height = maxf(maximum_height, height)

	var raw_height_path := OUTPUT_DIR.path_join("starting_region_height_1009.r16")
	var raw_file := FileAccess.open(raw_height_path, FileAccess.WRITE)
	raw_file.big_endian = false
	var height_range := maxf(maximum_height - minimum_height, 0.001)
	for height in export_heights:
		var normalized := clampf((height - minimum_height) / height_range, 0.0, 1.0)
		raw_file.store_16(int(round(normalized * 65535.0)))
	raw_file.close()

	_append_unreal_water_samples(profile, generation_profile, terrain_builder)
	_export_layout_masks(profile, world_size)
	var profile_file := FileAccess.open(OUTPUT_DIR.path_join("starting_region_profile.json"), FileAccess.WRITE)
	profile_file.store_string(JSON.stringify(_json_safe(profile), "  "))
	profile_file.close()

	var exported_files := {
		"heightmap": "starting_region_height_1009.r16",
		"profile": "starting_region_profile.json",
		"road_mask": "starting_region_roads.png",
		"river_mask": "starting_region_rivers.png",
		"settlement_mask": "starting_region_settlements.png",
		"forest_mask": "starting_region_forests.png",
	}
	var exported_checksums := {}
	for file_key in exported_files:
		exported_checksums[file_key] = FileAccess.get_sha256(
			OUTPUT_DIR.path_join(exported_files[file_key])
		)
	var manifest := {
		"schema": "broken_knight_unreal_region_source_v1",
		"zone_id": "starting_realm",
		"zone_name": profile.get("zone_name", "Riverwatch Realm - Starting Zone"),
		"coordinate_conversion": {
			"unreal_x_cm": "godot_x_m * 100",
			"unreal_y_cm": "-godot_z_m * 100",
			"unreal_z_cm": "godot_y_m * 100",
			"heightmap_row_zero": "godot z = -world_size/2 (north)",
		},
		"world_size_m": world_size,
		"source_grid_resolution": source_resolution,
		"landscape_resolution": EXPORT_RESOLUTION,
		"landscape_section_size_quads": 63,
		"landscape_subsections_per_component": 2,
		"landscape_component_size_quads": 126,
		"landscape_components_per_axis": 8,
		"landscape_xy_scale_cm": world_size * 100.0 / float(EXPORT_RESOLUTION - 1),
		"minimum_height_m": minimum_height,
		"maximum_height_m": maximum_height,
		"height_range_m": height_range,
		"landscape_z_scale_percent": height_range * 100.0 / 512.0,
		"landscape_actor_z_cm": (minimum_height + maximum_height) * 50.0,
		"water_level_m": float(profile.get("water_level", -1.4)),
		"files": exported_files,
		"sha256": exported_checksums,
		"authoritative_sources": {
			"profile": "C:/Users/Jimmy/Desktop/Broken Knight/godot/scripts/world/WorldProfile.gd",
			"terrain": "C:/Users/Jimmy/Desktop/Broken Knight/godot/scripts/world/TerrainBuilder.gd",
			"base_profile": "C:/Users/Jimmy/Desktop/Broken Knight/godot/data/world/profile.json",
		},
		"authoritative_source_sha256": {
			"profile": FileAccess.get_sha256("res://scripts/world/WorldProfile.gd"),
			"terrain": FileAccess.get_sha256("res://scripts/world/TerrainBuilder.gd"),
			"base_profile": FileAccess.get_sha256("res://data/world/profile.json"),
		},
	}
	var manifest_file := FileAccess.open(OUTPUT_DIR.path_join("starting_region_manifest.json"), FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify(manifest, "  "))
	manifest_file.close()
	print(
		"UNREAL_STARTING_REGION_EXPORT|resolution=%d|world=%.1fm|min=%.3f|max=%.3f|roads=%d|rivers=%d|towns=%d|output=%s"
		% [
			EXPORT_RESOLUTION,
			world_size,
			minimum_height,
			maximum_height,
			profile.get("road_corridors", []).size(),
			profile.get("river_corridors", []).size(),
			profile.get("town_sites", []).size(),
			OUTPUT_DIR,
		]
	)
	quit()


func _apply_unreal_river_export_carve(
	input_height: float,
	point: Vector2,
	profile: Dictionary,
	terrain_builder: RefCounted
) -> float:
	var nearest_variant: Variant = terrain_builder.call(
		"_nearest_cached_river_segment", point, profile
	)
	if not nearest_variant is Dictionary:
		return input_height
	var nearest: Dictionary = nearest_variant
	if nearest.is_empty():
		return input_height
	var width := float(nearest.get("width", 0.0))
	var distance := float(nearest.get("distance", INF))
	if width <= 0.0:
		return input_height
	var visible_half := width * 0.42
	var bank_outer := visible_half + maxf(18.0, width * 0.45)
	if distance >= bank_outer:
		return input_height
	var closest := Vector2(nearest.get("closest_point", point))
	var channel_grade := float(terrain_builder.call(
		"_river_centerline_grade", closest, profile
	))
	var water_surface := (
		channel_grade - 2.8 + float(profile.get("river_water_lift", 1.35))
	)
	var center_bed := water_surface - 0.34
	var water_edge_bed := water_surface - 0.045
	if distance <= visible_half:
		var shelf_t := smoothstep(visible_half * 0.62, visible_half, distance)
		return minf(input_height, lerpf(center_bed, water_edge_bed, shelf_t))
	var bank_t := smoothstep(visible_half, bank_outer, distance)
	return minf(input_height, lerpf(water_edge_bed, input_height, bank_t))


func _append_unreal_water_samples(
	export_profile: Dictionary,
	generation_profile: Dictionary,
	terrain_builder: RefCounted
) -> void:
	var water_lift := float(generation_profile.get("river_water_lift", 1.35))
	for corridor_variant in export_profile.get("river_corridors", []):
		if not corridor_variant is Dictionary:
			continue
		var corridor: Dictionary = corridor_variant
		var samples: Array[float] = []
		for point_variant in corridor.get("points", []):
			var point := Vector2(point_variant)
			var grade := float(terrain_builder.call(
				"_river_centerline_grade", point, generation_profile
			))
			samples.append(grade - 2.8 + water_lift)
		corridor["water_surface_points_m"] = samples
		corridor["visible_width_scale"] = 0.84


func _export_layout_masks(profile: Dictionary, world_size: float) -> void:
	var road_data := PackedByteArray()
	var river_data := PackedByteArray()
	var settlement_data := PackedByteArray()
	var forest_data := PackedByteArray()
	var pixel_count := EXPORT_RESOLUTION * EXPORT_RESOLUTION
	road_data.resize(pixel_count)
	river_data.resize(pixel_count)
	settlement_data.resize(pixel_count)
	forest_data.resize(pixel_count)
	_rasterize_corridors(road_data, profile.get("road_corridors", []), world_size, 2.6)
	_rasterize_corridors(river_data, profile.get("river_corridors", []), world_size, 1.3)
	_rasterize_regions(settlement_data, profile.get("town_sites", []), world_size, 1.0)
	_rasterize_regions(forest_data, profile.get("forest_regions", []), world_size, 0.82)
	_save_l8_png(road_data, "starting_region_roads.png")
	_save_l8_png(river_data, "starting_region_rivers.png")
	_save_l8_png(settlement_data, "starting_region_settlements.png")
	_save_l8_png(forest_data, "starting_region_forests.png")


func _save_l8_png(bytes: PackedByteArray, filename: String) -> void:
	var image := Image.create_from_data(EXPORT_RESOLUTION, EXPORT_RESOLUTION, false, Image.FORMAT_L8, bytes)
	var error := image.save_png(OUTPUT_DIR.path_join(filename))
	if error != OK:
		push_error("Failed to save %s: %s" % [filename, error_string(error)])


func _rasterize_corridors(bytes: PackedByteArray, corridors: Array, world_size: float, width_multiplier: float) -> void:
	var metres_per_pixel := world_size / float(EXPORT_RESOLUTION - 1)
	for corridor_variant in corridors:
		if not corridor_variant is Dictionary:
			continue
		var corridor: Dictionary = corridor_variant
		var points: Array = corridor.get("points", [])
		if points.size() < 2:
			continue
		var width := maxf(float(corridor.get("width", 10.0)) * width_multiplier, 4.0)
		var margin_pixels := ceili(width / metres_per_pixel) + 1
		for segment_index in range(points.size() - 1):
			var start := Vector2(points[segment_index])
			var finish := Vector2(points[segment_index + 1])
			var start_pixel := _world_to_pixel(start, world_size)
			var finish_pixel := _world_to_pixel(finish, world_size)
			var min_x := maxi(0, floori(minf(start_pixel.x, finish_pixel.x)) - margin_pixels)
			var max_x := mini(EXPORT_RESOLUTION - 1, ceili(maxf(start_pixel.x, finish_pixel.x)) + margin_pixels)
			var min_y := maxi(0, floori(minf(start_pixel.y, finish_pixel.y)) - margin_pixels)
			var max_y := mini(EXPORT_RESOLUTION - 1, ceili(maxf(start_pixel.y, finish_pixel.y)) + margin_pixels)
			for pixel_y in range(min_y, max_y + 1):
				for pixel_x in range(min_x, max_x + 1):
					var point := _pixel_to_world(pixel_x, pixel_y, world_size)
					var distance := _distance_to_segment(point, start, finish)
					if distance > width:
						continue
					var value := 1.0 - smoothstep(width * 0.58, width, distance)
					var data_index := pixel_y * EXPORT_RESOLUTION + pixel_x
					bytes[data_index] = maxi(bytes[data_index], int(round(value * 255.0)))


func _rasterize_regions(bytes: PackedByteArray, regions: Array, world_size: float, radius_multiplier: float) -> void:
	var metres_per_pixel := world_size / float(EXPORT_RESOLUTION - 1)
	for region_variant in regions:
		if not region_variant is Dictionary:
			continue
		var region: Dictionary = region_variant
		var center := Vector2(region.get("position", region.get("center", Vector2.ZERO)))
		var radius := float(region.get("radius", region.get("size", 120.0))) * radius_multiplier
		if radius <= 0.0:
			continue
		var center_pixel := _world_to_pixel(center, world_size)
		var radius_pixels := ceili(radius / metres_per_pixel) + 1
		var min_x := maxi(0, floori(center_pixel.x) - radius_pixels)
		var max_x := mini(EXPORT_RESOLUTION - 1, ceili(center_pixel.x) + radius_pixels)
		var min_y := maxi(0, floori(center_pixel.y) - radius_pixels)
		var max_y := mini(EXPORT_RESOLUTION - 1, ceili(center_pixel.y) + radius_pixels)
		for pixel_y in range(min_y, max_y + 1):
			for pixel_x in range(min_x, max_x + 1):
				var point := _pixel_to_world(pixel_x, pixel_y, world_size)
				var distance := point.distance_to(center)
				if distance > radius:
					continue
				var value := 1.0 - smoothstep(radius * 0.72, radius, distance)
				var data_index := pixel_y * EXPORT_RESOLUTION + pixel_x
				bytes[data_index] = maxi(bytes[data_index], int(round(value * 255.0)))


func _world_to_pixel(point: Vector2, world_size: float) -> Vector2:
	var half_size := world_size * 0.5
	return Vector2(
		(point.x + half_size) / world_size * float(EXPORT_RESOLUTION - 1),
		(point.y + half_size) / world_size * float(EXPORT_RESOLUTION - 1)
	)


func _pixel_to_world(pixel_x: int, pixel_y: int, world_size: float) -> Vector2:
	return Vector2(
		lerpf(-world_size * 0.5, world_size * 0.5, float(pixel_x) / float(EXPORT_RESOLUTION - 1)),
		lerpf(-world_size * 0.5, world_size * 0.5, float(pixel_y) / float(EXPORT_RESOLUTION - 1))
	)


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var delta := finish - start
	var length_squared := delta.length_squared()
	if length_squared <= 0.00001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(delta) / length_squared, 0.0, 1.0)
	return point.distance_to(start + delta * t)


func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_DICTIONARY:
			var converted := {}
			for key in value:
				converted[str(key)] = _json_safe(value[key])
			return converted
		TYPE_ARRAY:
			var converted_array := []
			for item in value:
				converted_array.append(_json_safe(item))
			return converted_array
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var packed_array := []
			for item in value:
				packed_array.append(_json_safe(item))
			return packed_array
		_:
			return value
