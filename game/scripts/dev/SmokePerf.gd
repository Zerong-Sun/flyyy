extends SceneTree
## Headless performance baseline for the 1080p globe roam target
## (PRD §27 item 20 / v1.0_GATE 性能: 1080p 地球漫游 ≈60 FPS).
##
## Headless mode uses the dummy render/audio drivers, so TIME_FPS here measures
## the CPU-side frame budget (scene build + marker/LOD updates), NOT GPU fill.
## Real GPU validation remains a manual 1080p Profiler step (see docs/performance.md);
## this script gives a repeatable CPU baseline and catches regressions (e.g. an
## accidental 500-city loop that ruins frame time).
##
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://scripts/dev/SmokePerf.gd

const WARMUP_FRAMES := 60
const SAMPLE_FRAMES := 180


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors: PackedStringArray = []

	var globe_script: GDScript = load("res://scripts/render/GlobeController.gd") as GDScript
	var globe_scene := load("res://scenes/globe/globe.tscn") as PackedScene
	if globe_script == null:
		errors.append("GlobeController.gd failed to load")
	if globe_scene == null:
		errors.append("globe.tscn failed to load")
	if not errors.is_empty():
		_finish(errors)
		return

	var build_start := Time.get_ticks_msec()
	var globe := globe_scene.instantiate()
	root.add_child(globe)
	# Let _ready() build earth mesh, grid overlay and 500 airport pins.
	for i in 30:
		await process_frame
	var build_ms := Time.get_ticks_msec() - build_start

	# Steady-state FPS sampling (post-warmup).
	for i in WARMUP_FRAMES:
		await process_frame
	var samples: Array[float] = []
	for i in SAMPLE_FRAMES:
		await process_frame
		samples.append(Performance.get_monitor(Performance.TIME_FPS))

	# Use the trailing half (warmest) for the baseline number.
	var n := samples.size() / 2
	var tail := samples.slice(n)
	var avg := 0.0
	for v in tail:
		avg += v
	avg /= tail.size()
	var min_fps := 9999.0
	for v in tail:
		min_fps = minf(min_fps, v)

	print("PERF_GLOBE_BUILD_MS=%d (scene + 500-pin build)" % build_ms)
	print("PERF_BASELINE_FPS=%.1f (headless CPU frame budget; min %.1f, %d samples)" % [avg, min_fps, tail.size()])

	# CPU-side budget gate. 60 FPS needs ~16.7ms/frame; allow headless slack.
	var frame_budget := 1000.0 / avg
	print("PERF_FRAME_BUDGET_MS=%.2f" % frame_budget)
	if build_ms > 2000:
		errors.append("globe build too slow: %d ms" % build_ms)
	if avg < 20.0:
		errors.append("headless baseline FPS too low: %.1f" % avg)

	globe.queue_free()
	_finish(errors)


func _finish(errors: PackedStringArray) -> void:
	if errors.is_empty():
		print("SMOKE_PERF_OK")
		quit(0)
	else:
		print("SMOKE_PERF_FAIL")
		for e in errors:
			printerr("  - ", e)
		quit(1)
