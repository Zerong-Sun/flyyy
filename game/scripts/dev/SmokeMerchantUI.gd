extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	var app := root.get_node("AppState")
	var clock := root.get_node("GameClock")
	var merchant := root.get_node("MerchantSystem")
	app.reset_new_game("lhr")
	clock.set_paused(true)
	app.reliability_events_enabled = false
	var ui: Control = main.get_node("UI")
	ui._show_market()
	await process_frame
	var board: Control = ui.find_child("MerchantBoard", true, false)
	assert(board != null)
	board._expanded = true
	board.rebuild()
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await create_timer(0.5).timeout
		root.get_texture().get_image().save_png("/tmp/flyyy-merchant-market.png")
	assert(board.size.y <= 260, "expanded merchant board must remain compact")
	var search: GDScript = load("res://scripts/systems/FlightSearch.gd")
	var tickets: GDScript = load("res://scripts/systems/TicketService.gd")
	var flights: Array = search.search("lhr", "", 10, false, "departure")
	assert(not flights.is_empty())
	var flight: Dictionary = flights[0]
	assert(tickets.purchase(flight, "economy", "", 0) == "")
	clock.jump_to_unix(clock.parse_iso_to_unix(str(flight.scheduled_departure_utc)))
	var ops: Node = main.get_node("FlightOps")
	ops.start_boarding(tickets.next_ticket())
	await process_frame
	assert(not merchant.pending_event.is_empty(), "journey must appear in the existing travel overlay")
	var card: Control = ui.find_child("JourneyChoice", true, false)
	assert(card != null and card.visible)
	if DisplayServer.get_name() != "headless":
		await create_timer(0.8).timeout
		root.get_texture().get_image().save_png("/tmp/flyyy-merchant-journey.png")
	# The second button leaves the plan unchanged, then the existing flight lands.
	var buttons: Node = card.get_child(0).get_child(2)
	buttons.get_child(1).pressed.emit()
	assert(merchant.pending_event.is_empty())
	await create_timer(5.5).timeout
	assert(app.current_airport_id == flight.destination_airport_id)
	assert(app.held_tickets.is_empty())
	assert(not root.get_node("SaveSystem").flight_in_progress)
	assert(not ui.get("_overlay").visible)
	# No news/arrival/result popup pile after one flight.
	assert(ui.get("_event_queue").is_empty())
	clock.set_paused(true)
	ui._show_market()
	board = ui.find_child("MerchantBoard", true, false)
	board._expanded = true
	board.rebuild()
	ui.size = Vector2(1024, 640)
	ui._layout_floating_panels()
	await process_frame
	await process_frame
	var host: Control = ui.get("_panel_host")
	assert(host.position.x + host.size.x <= 1025)
	assert(host.position.y + host.size.y <= 641)
	print("SMOKE_MERCHANT_UI_OK")
	quit(0)
