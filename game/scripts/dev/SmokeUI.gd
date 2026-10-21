extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		quit(1)
		return
	var main: Node = scene.instantiate()
	root.add_child(main)
	await process_frame
	var state: Node = root.get_node("AppState")
	state.reset_new_game("ist", "sandbox", true)
	root.get_node("GameClock").set_paused(true)
	var ui: Node = main.get_node("UI")
	if not ui.get("_new_game_route_hints") is CheckButton:
		push_error("New-game route hint choice is missing")
		quit(1)
		return
	ui.call("_show_flights")
	await process_frame
	var recommendations: Node = ui.get("_recommend_box")
	var list: Node = recommendations.get_child(0)
	if list.get_child_count() != 2 or not list.get_child(1) is Button:
		push_error("Starter recommendation must contain exactly one actionable city")
		quit(1)
		return
	state.route_hints_enabled = false
	ui.call("_rebuild_recommendations")
	if recommendations.visible:
		push_error("Route recommendation remained visible after hints were disabled")
		quit(1)
		return
	state.route_hints_enabled = true
	if not bool(state.to_dict().get("route_hints_enabled", false)):
		push_error("Route hint choice was not serialized")
		quit(1)
		return
	ui.call("_rebuild_recommendations")
	list = recommendations.get_child(0)
	list.get_child(1).pressed.emit()
	await process_frame
	if str(ui.get("_flight_query").text).is_empty() or not "采购建议" in str(ui.get("_hint").text):
		push_error("Recommendation did not filter flights and explain the purchase")
		quit(1)
		return
	if DisplayServer.get_name() != "headless":
		await create_timer(3.0).timeout
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png("/tmp/flyyy-desktop-flights.png")
	ui.call("_show_market")
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await create_timer(1.0).timeout
		root.get_texture().get_image().save_png("/tmp/flyyy-desktop-market.png")
	var host: Control = ui.get("_panel_host")
	var viewport_size := (ui as Control).size
	if host.position.x < 0.0 or host.position.y < 0.0 or host.position.x + host.size.x > viewport_size.x or host.position.y + host.size.y > viewport_size.y:
		push_error("Market panel escaped the viewport: %s in %s" % [host.get_rect(), viewport_size])
		quit(1)
		return
	var buy_tree: Tree = ui.get("_market_buy_tree")
	if buy_tree != null and buy_tree.get_root() != null and buy_tree.get_root().get_first_child() != null:
		var hints := 0
		var item := buy_tree.get_root().get_first_child()
		while item != null:
			if str(item.get_text(4)) != "":
				hints += 1
			if str(item.get_text(4)).length() > 26:
				push_error("Market outlook summary is too long for its column")
				quit(1)
				return
			item = item.get_next()
		if hints > 1:
			push_error("Market showed more than one unsolicited destination hint")
			quit(1)
			return
	# Resize the HUD itself to exercise the panel layout independently of the
	# headless display server's fixed virtual window.
	(ui as Control).size = Vector2(1024, 640)
	ui.call("_layout_floating_panels")
	await process_frame
	if host.position.x < 0.0 or host.position.y < 0.0 or host.position.x + host.size.x > 1024.0 or host.position.y + host.size.y > 640.0:
		push_error("Market panel escaped the narrow viewport: %s" % host.get_rect())
		quit(1)
		return
	(ui as Control).theme = load("res://themes/ThemeFactory.gd").build(1.5)
	await process_frame
	ui.call("_layout_floating_panels")
	await process_frame
	if host.position.x < 0.0 or host.position.y < 0.0 or host.position.x + host.size.x > 1024.0 or host.position.y + host.size.y > 640.0:
		push_error("Market panel escaped at 150%% font scale: %s" % host.get_rect())
		quit(1)
		return
	ui.call("_show_notes")
	await process_frame
	print("SMOKE_UI_PASS")
	main.queue_free()
	await process_frame
	quit(0)
