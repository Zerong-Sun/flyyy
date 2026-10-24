extends SceneTree
## Headless performance baseline for the 1080p globe roam target
## (PRD §27 item 20 / v1.0_GATE 性能: 1080p 地球漫游 ≈60 FPS).
##
## Headless frame intervals include scene/script scheduling, NOT GPU fill.
## Real GPU validation remains a manual 1080p Profiler step (see docs/performance.md);
## this script gives a repeatable CPU baseline and catches regressions (e.g. an
## accidental 500-city loop that ruins frame time).
##
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://scripts/dev/SmokePerf.gd

const WARMUP_FRAMES := 60
const SAMPLE_FRAMES := 180


func _initialize() -> void:
	# The shipped game is capped at 60 FPS for thermals. This headless smoke test
	# deliberately removes that cap to measure CPU-side headroom.
	Engine.max_fps = 0
	call_deferred("_run")


func _run() -> void:
	var errors: PackedStringArray = []
	if int(ProjectSettings.get_setting("application/run/max_fps", 0)) != 60:
		errors.append("application/run/max_fps must be 60")
	if int(ProjectSettings.get_setting("display/window/vsync/vsync_mode", 0)) != 1:
		errors.append("display/window/vsync/vsync_mode must be enabled")

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
	await process_frame
	var build_ms := Time.get_ticks_msec() - build_start

	# TIME_FPS updates on a coarse interval and is not a per-frame sample.
	# Measure actual intervals; keep the units explicit and report tail latency.
	for i in WARMUP_FRAMES:
		await process_frame
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for i in SAMPLE_FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(maxf(0.001, (now - previous) / 1000.0))
		previous = now
	var frame_budget := 0.0
	for sample in samples:
		frame_budget += sample
	frame_budget /= samples.size()
	samples.sort()
	var avg := 1000.0 / frame_budget
	var p95 := samples[int(ceil(samples.size() * 0.95)) - 1]
	print("PERF_GLOBE_BUILD_MS=%d" % build_ms)
	print("PERF_BASELINE_FPS=%.1f (headless interval throughput, %d samples)" % [avg, samples.size()])
	print("PERF_FRAME_BUDGET_MS=%.3f p50=%.3f p95=%.3f p99=%.3f" % [frame_budget,
		samples[int(ceil(samples.size() * 0.5)) - 1], p95, samples[int(ceil(samples.size() * 0.99)) - 1]])
	if build_ms > 2000:
		errors.append("globe build too slow: %d ms" % build_ms)
	if avg < 20.0:
		errors.append("headless baseline FPS too low: %.1f" % avg)
	if p95 > 50.0:
		errors.append("headless p95 frame interval too high: %.3f ms" % p95)

	globe.queue_free()
	await process_frame
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
