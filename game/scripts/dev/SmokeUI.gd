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
	state.reset_new_game("ist")
	root.get_node("GameClock").set_paused(true)
	var ui: Node = main.get_node("UI")
	ui.call("_show_flights")
	await process_frame
	var recommendations: Node = ui.get("_recommend_box")
	var list: Node = recommendations.get_child(0)
	if list.get_child_count() < 2 or not list.get_child(1) is Button:
		push_error("Missing actionable starter recommendation")
		quit(1)
		return
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
	ui.call("_show_notes")
	await process_frame
	print("SMOKE_UI_PASS")
	main.queue_free()
	await process_frame
	quit(0)
