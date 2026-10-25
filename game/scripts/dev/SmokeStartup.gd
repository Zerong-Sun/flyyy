extends SceneTree
## Exercise the real loading scene; starting a game directly misses menu layout races.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	change_scene_to_file("res://scenes/loading.tscn")
	while current_scene == null or current_scene.name != "Main":
		await process_frame
	for frame in range(5):
		await process_frame
	await create_timer(0.5).timeout
	var ui: Control = current_scene.get_node("UI")
	var panel: Control = ui.get("_new_game_panel")
	assert(panel.is_visible_in_tree())
	assert(panel.position.x >= 0 and panel.position.y >= 0, "Opening menu must remain on screen")
	assert(panel.get_rect().end.x <= ui.size.x and panel.get_rect().end.y <= ui.size.y, "Opening menu must fit the viewport")
	var buttons := 0
	for n in panel.find_children("*", "Button", true, false):
		if n.is_visible_in_tree():
			assert(panel.get_global_rect().encloses(n.get_global_rect()), "Opening buttons must remain inside the menu")
			buttons += 1
	assert(buttons >= 5, "Mode and start buttons must be visible")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/flyyy-startup.png")
	ui._start_selected()
	await process_frame
	assert(root.get_node("AppState").game_started)
	assert(not panel.visible)
	print("SMOKE_STARTUP_OK")
	quit(0)
