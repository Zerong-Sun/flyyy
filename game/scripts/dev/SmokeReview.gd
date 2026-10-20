extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
func write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
func _run() -> void:
	if not "flyyy-godot-" in OS.get_user_data_dir():
		quit(1)
		return
	var state: Node = root.get_node("AppState")
	var clock: Node = root.get_node("GameClock")
	var data: Node = root.get_node("DataService")
	var saves: Node = root.get_node("SaveSystem")
	var tickets: GDScript = load("res://scripts/systems/TicketService.gd")
	var economy: GDScript = load("res://scripts/systems/EconomySystem.gd")
	var inventory: GDScript = load("res://scripts/systems/InventorySystem.gd")
	var planner: GDScript = load("res://scripts/systems/TradePlanner.gd")
	var search: GDScript = load("res://scripts/systems/FlightSearch.gd")
	saves.set_process(false)
	state.reset_new_game("ist")
	clock.set_paused(true)
	state.save_id = "review-regression"
	var initial_cash: float = state.cash_usd
	var flights: Array = search.search("ist", "", 10)
	if flights.is_empty():
		check(false, "fixture needs a future flight")
		_finish()
		return
	var flight: Dictionary = flights[0]
	check(tickets.purchase(flight, "economy", "", 1) == "", "buy flight with cargo")
	var paid: float = state.held_tickets[0].total_paid
	var promotion: float = tickets.apply_cargo_promotion()
	check(promotion > 0, "free cargo applied")
	check(tickets.apply_cargo_promotion() == 0, "promotion is idempotent")
	check(absf(state.held_tickets[0].total_paid - (paid - promotion)) < 0.001, "receipt excludes free cargo")
	var fee: float = float(data.economy.baggage_extras.refund_fee_rate)
	tickets.refund_current()
	check(absf(state.cash_usd - (initial_cash - (paid - promotion) * fee)) < 0.001, "refund cannot create free-cargo money")
	check(absf(state.realized_net() + (paid - promotion) * fee) < 0.001, "net ledger equals actual fee")
	# A migrated ticket returns cash but cannot create profit in the new ledger epoch.
	state.travel_expenses = 0
	state.realized_margin = 0
	state.held_tickets = [{"total_paid": 100, "ledger_paid": 0}]
	var before: float = state.cash_usd
	check(absf(tickets.refund_held(0.5) - 50) < 0.001, "configured fee applied")
	check(state.cash_usd == before + 50 and state.realized_net() == 0, "legacy refund has no phantom profit")
	state.held_tickets = []

	# Same product in separate lots must share demand pressure, including slow decay.
	var pid := ""
	for product_id in data.market_product_ids("istanbul"):
		if float(data.get_product(product_id).get("shelf_life_hours", 0)) >= 90000:
			pid = product_id
			break
	var lots: Array = [
		{"product_id": pid, "qty": 15, "unit_cost": 1, "purchased_unix": clock.unix_time, "in_cargo": false},
		{"product_id": pid, "qty": 25, "unit_cost": 1, "purchased_unix": clock.unix_time, "in_cargo": false},
	]
	var previous_decay: float = float(data.economy.market.demand_decay_per_sale)
	for decay in [0.0, 0.001, 0.08]:
		data.economy.market.demand_decay_per_sale = decay
		state.demand_pressure = {}
		state.inventory = lots.duplicate(true)
		var expected: float = planner.estimate_lots(state.inventory, "istanbul", 0)
		var first: Dictionary = inventory.sell(0, 15)
		var second: Dictionary = inventory.sell(0, 25)
		check(absf(expected - float(first.revenue) - float(second.revenue)) < 0.001, "planner equals real separate sales at decay %s" % decay)
	data.economy.market.demand_decay_per_sale = previous_decay
	state.demand_pressure = {}
	var unit: float = economy.sell_price("istanbul", pid, 1.0)
	var best: Dictionary = planner.best_purchase(pid, "istanbul", unit * 0.8, 40, 0)
	var exhaustive := -INF
	var best_qty := 0
	for qty in range(1, 41):
		var candidate: Dictionary = lots[0].duplicate()
		candidate.qty = qty
		var margin: float = planner.estimate_lots([candidate], "istanbul", 0) - unit * 0.8 * qty
		if margin > exhaustive:
			exhaustive = margin
			best_qty = qty
	check(int(best.qty) == best_qty and absf(best.margin - exhaustive) < 0.001, "starter quantity maximizes profit")

	# Nested malformed JSON must not reach gameplay conversions or UI rendering.
	state.reset_new_game("ist")
	var original: Dictionary = state.to_dict()
	for patch in [
		{"challenge": {"deadline_unix": {}}},
		{"challenge": {"result": {"net_worth": []}}},
		{"sell_transactions": [{"margin": {}}]},
		{"stats": {"products_discovered": {"bad": {}}}},
		{"visited_airports": {"ist": []}},
	]:
		var malformed := original.duplicate(true)
		malformed.merge(patch, true)
		check(saves.validate(malformed).is_empty(), "reject nested malformed save: %s" % patch)
	var malformed_ticket := original.duplicate(true)
	malformed_ticket.held_tickets = [{"origin_airport_id": "ist", "destination_airport_id": "pvg", "scheduled_departure_utc": "2025-02-31T00:00:00Z", "scheduled_arrival_utc": "2025-03-03T00:00:00Z"}]
	check(saves.validate(malformed_ticket).is_empty(), "reject impossible calendar date")
	var future := original.duplicate(true)
	future.save_version = 999
	write_json("user://save_demo.json", future)
	check(not saves.save_game(), "future primary protected without prior load")
	check(JSON.parse_string(FileAccess.get_file_as_string("user://save_demo.json")).save_version == 999, "future primary unchanged")
	state.game_mode = "collector"
	check(saves.save_game(), "protected sandbox does not block another slot")
	state.game_mode = "challenge"
	write_json("user://save_challenge.json.bak", future)
	check(not saves.save_game(), "future backup protected")
	state.game_mode = "collector"

	# Old asynchronous flight completion must not mutate a newly started run.
	var ops: Node = (load("res://scripts/systems/FlightOps.gd") as GDScript).new()
	root.add_child(ops)
	ops.set_process(false)
	state.reset_new_game("ist", "collector")
	clock.set_paused(true)
	state.reliability_events_enabled = false
	check(tickets.purchase(flight, "economy", "", 0) == "", "flight fixture purchased")
	ops.start_boarding(state.held_tickets[0])
	check(saves.flight_in_progress, "flight checkpoint guarded")
	state.reset_new_game("pvg", "collector")
	clock.set_paused(true)
	await create_timer(5.2).timeout
	check(state.current_airport_id == "pvg", "old flight cannot teleport the new run")
	check(state.stats.total_flight_segments == 0, "old flight cannot credit new statistics")
	check(not saves.flight_in_progress, "new run clears save suspension")
	ops.queue_free()
	await process_frame
	_finish()
func _finish() -> void:
	print("SMOKE_REVIEW: ", failures)
	quit(0 if failures.is_empty() else 1)
