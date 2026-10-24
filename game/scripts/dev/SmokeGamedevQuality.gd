extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _run() -> void:
	if not "flyyy-godot-" in OS.get_user_data_dir():
		printerr("Run via tools/test_godot.py to protect player saves")
		quit(1)
		return
	var state: Node = root.get_node("AppState")
	var clock: Node = root.get_node("GameClock")
	var data: Node = root.get_node("DataService")
	var saves: Node = root.get_node("SaveSystem")
	var audio: Node = root.get_node("AudioService")
	var events: Node = root.get_node("EventBus")
	var news: GDScript = load("res://scripts/systems/NewsEvents.gd")
	saves.set_process(false)
	state.reset_new_game("pvg")
	clock.set_paused(true)
	check(saves.save_game(), "initial checkpoint")
	clock.unix_time += 600
	saves._process(30.1)
	var persisted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://save_demo.json"))
	check(persisted.unix_time == clock.unix_time, "idle clock gets a periodic checkpoint")
	state.reduced_animations = true
	events.settings_changed.emit()
	saves._process(0.9)
	persisted = JSON.parse_string(FileAccess.get_file_as_string("user://save_demo.json"))
	check(persisted.reduced_animations, "settings signal persists preferences")
	var before_continuous_changes: float = clock.unix_time
	for tick in range(61):
		clock.unix_time += 1.0
		events.cash_changed.emit()
		saves._process(0.5)
	persisted = JSON.parse_string(FileAccess.get_file_as_string("user://save_demo.json"))
	check(float(persisted.unix_time) >= before_continuous_changes + 60.0,
		"continuous changes cannot starve the periodic checkpoint")

	# A directory at the temporary file path simulates a write failure without
	# permissions assumptions (root/admin users can bypass chmod restrictions).
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path("user://save_demo.json.tmp"))
	state.cash_usd -= 1
	events.cash_changed.emit()
	saves._process(0.9)
	check(saves._dirty, "write failure keeps pending progress")
	check(saves._cooldown == saves.RETRY_SECONDS, "write failure backs off")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_demo.json.tmp"))
	saves._process(5.1)
	check(not saves._dirty, "retry succeeds after storage recovers")
	persisted = JSON.parse_string(FileAccess.get_file_as_string("user://save_demo.json"))
	check(persisted.cash_usd == state.cash_usd, "retried checkpoint contains latest progress")
	saves.flight_in_progress = true
	state.cash_usd -= 1
	events.cash_changed.emit()
	saves._process(31.0)
	persisted = JSON.parse_string(FileAccess.get_file_as_string("user://save_demo.json"))
	check(persisted.cash_usd != state.cash_usd, "flight transition suspends checkpoint")
	saves.flight_in_progress = false

	audio.set_bus_volume("SFX", 0.25)
	var snapshot: Dictionary = state.to_dict()
	audio.set_bus_volume("SFX", 0.9)
	state.from_dict(snapshot)
	clock.set_paused(true)
	for bus in ["SFX", "UI", "Transition"]:
		check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus)) - linear_to_db(0.25)) < 0.01,
			"audio restore applies to " + bus)
	audio.set_bgm("bgm_menu")
	await create_timer(0.15).timeout
	var playback: float = audio._bgm_player.get_playback_position()
	audio.set_bgm("bgm_menu")
	check(audio._bgm_player.get_playback_position() >= playback, "same BGM does not restart")
	audio.stop_bgm()
	audio.set_bgm("bgm_menu")
	check(audio._bgm_player.playing, "stopped BGM can be restarted")

	data.tz_offsets["Review/Sparse"] = {"2025-03-01": 1.0, "2025-03-30": 2.0}
	for fixture in [["2025-02-28T12:00:00Z", 1.0], ["2025-03-15T12:00:00Z", 1.0],
		["2025-03-30T12:00:00Z", 2.0], ["2025-04-01T12:00:00Z", 2.0]]:
		clock.unix_time = clock.parse_iso_to_unix(fixture[0])
		check(clock.offset_hours_for("Review/Sparse") == fixture[1], "sparse timezone " + fixture[0])
	data.tz_offsets.erase("Review/Sparse")

	var first: Array = news.active_for_city("istanbul", "2025-03-15", "review-a")
	var original := first.duplicate(true)
	first.append({"bad": true})
	check(news.active_for_city("istanbul", "2025-03-15", "review-a") == original, "caller cannot mutate event cache")
	for context in [["2025-03-16", "review-a"], ["2025-03-16", "review-b"]]:
		var cached: Array = news.active_for_city("istanbul", context[0], context[1])
		check(news._active_context == context, "cache switches date/run")
		news._active_city_cache.clear()
		check(news.active_for_city("istanbul", context[0], context[1]) == cached, "cache equals fresh calculation")

	var panel := VBoxContainer.new()
	root.add_child(panel)
	var disabled := Button.new()
	disabled.disabled = true
	panel.add_child(disabled)
	var hidden := Button.new()
	panel.add_child(hidden)
	hidden.hide()
	var first_button := Button.new()
	panel.add_child(first_button)
	var input := LineEdit.new()
	panel.add_child(input)
	var focus: GDScript = load("res://scripts/ui/FocusNavigation.gd")
	focus.focus_first(panel)
	check(root.gui_get_focus_owner() == first_button, "focus skips hidden/disabled controls")
	input.grab_focus()
	focus.focus_first(panel)
	check(root.gui_get_focus_owner() == input, "existing text focus is preserved")
	panel.queue_free()
	await process_frame

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var hud: Node = main.get_node("UI")
	hud._toggle_pause()
	await process_frame
	var host: Control = hud.get("_panel_host")
	check(root.gui_get_focus_owner() != null and host.is_ancestor_of(root.gui_get_focus_owner()),
		"opened settings panel receives keyboard focus")
	clock.set_paused(true)
	hud._save()
	check(clock.paused, "manual save preserves pause")
	clock.set_paused(false)
	hud._save()
	check(not clock.paused, "manual save preserves running clock")
	clock.set_paused(true)
	main.queue_free()
	await process_frame
	print("SMOKE_GAMEDEV_QUALITY: ", failures)
	quit(0 if failures.is_empty() else 1)
