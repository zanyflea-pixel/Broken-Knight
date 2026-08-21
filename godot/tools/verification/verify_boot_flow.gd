extends SceneTree

const BOOT_SCENE := preload("res://scenes/Boot.tscn")
const TIMEOUT_MSEC := 30000


func _init() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var boot := BOOT_SCENE.instantiate()
	root.add_child(boot)
	var started_at := Time.get_ticks_msec()
	var last_progress := -1.0
	var saw_progress_after_open := false

	while Time.get_ticks_msec() - started_at < TIMEOUT_MSEC:
		await process_frame
		var progress_bar := boot.get_node_or_null("Overlay/Panel/VBox/ProgressBar") as ProgressBar
		if progress_bar == null:
			push_error("BOOT_FLOW_FAIL|missing progress bar")
			quit(1)
			return
		if progress_bar.value != last_progress:
			if progress_bar.value < last_progress:
				push_error("BOOT_FLOW_FAIL|progress moved backwards|from=%.1f|to=%.1f" % [last_progress, progress_bar.value])
				quit(1)
				return
			last_progress = progress_bar.value
			if last_progress > 2.0:
				saw_progress_after_open = true
		if not boot.get_node("Overlay/Panel").visible:
			if not saw_progress_after_open or last_progress < 100.0:
				push_error("BOOT_FLOW_FAIL|splash closed before loading completed|progress=%.1f" % last_progress)
				quit(1)
				return
			print("BOOT_FLOW_PASS|elapsed_ms=%d|progress=%.1f" % [Time.get_ticks_msec() - started_at, last_progress])
			quit(0)
			return

	push_error("BOOT_FLOW_FAIL|timeout|progress=%.1f" % last_progress)
	quit(1)
