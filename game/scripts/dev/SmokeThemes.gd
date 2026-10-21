extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var colors: GDScript = load("res://themes/DemoColors.gd")
	var factory: GDScript = load("res://themes/ThemeFactory.gd")
	var state: Node = root.get_node("AppState")
	for mode in ["dark", "light"]:
		state.set_theme_mode(mode)
		colors.call("apply_mode", mode)
		var palette: Theme = factory.call("build")
		var body: Color = colors.get("TEXT_PRIMARY")
		var panel: Color = colors.get("BG_PANEL")
		if palette == null or absf(body.get_luminance() - panel.get_luminance()) < 0.3:
			push_error("Theme has insufficient foreground separation: " + mode)
			quit(1)
			return
		if str(state.to_dict().get("theme_mode", "")) != mode:
			push_error("Theme selection was not serialized: " + mode)
			quit(1)
			return
	state.set_theme_mode("dark")
	colors.call("apply_mode", "dark")
	state.reset_new_game("ist")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	state.set_theme_mode("light")
	reload_current_scene()
	await process_frame
	await process_frame
	var ui: Node = current_scene.get_node("UI")
	if (ui.get("_new_game_panel") as Control).visible or str(state.theme_mode) != "light" or colors.get("BG_DEEP") != Color("F3FFD4"):
		push_error("Theme switch did not restore the active game")
		quit(1)
		return
	if DisplayServer.get_name() != "headless":
		await create_timer(1.0).timeout
		root.get_texture().get_image().save_png("/tmp/flyyy-light-theme.png")
	state.set_theme_mode("dark")
	colors.call("apply_mode", "dark")
	print("SMOKE_THEMES_OK")
	quit(0)
