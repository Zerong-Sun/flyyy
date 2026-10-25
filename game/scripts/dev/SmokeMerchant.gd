extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app := root.get_node("AppState")
	var clock := root.get_node("GameClock")
	var merchant := root.get_node("MerchantSystem")
	var ds := root.get_node("DataService")
	var inv: GDScript = load("res://scripts/systems/InventorySystem.gd")
	var economy: GDScript = load("res://scripts/systems/EconomySystem.gd")
	app.reset_new_game("lhr")
	clock.set_paused(true)
	assert(merchant.catalog().size() == 30)
	var ids := {}
	for event in merchant.catalog():
		assert(not ids.has(event.id))
		ids[event.id] = true
	var d: Dictionary = merchant.data()
	assert(not d.offers.is_empty(), "real outgoing flights must generate reachable offers")
	var offer: Dictionary = d.offers[0].duplicate(true)
	assert(float(offer.deadline) - float(clock.unix_time) >= 24 * 3600)
	assert(float(offer.arrival) < float(offer.deadline))
	merchant.refresh_offers()
	assert(d.offers[0] == offer, "reopening must not reroll")
	assert(merchant.accept(str(offer.id)))
	assert(not merchant.accept(str(offer.id)))
	var pid := str(offer.product)
	var err: String = inv.buy(pid, int(offer.qty))
	assert(err == "", err)
	app.current_airport_id = str(offer.airport)
	var before: float = app.cash_usd
	var n := int(offer.qty)
	if n > 1:
		var partial: Dictionary = inv.sell(0, n - 1)
		assert(float(partial.order_bonus) == 0)
		assert(int(d.order.done) == n - 1)
	var result: Dictionary = inv.sell(0, 1)
	assert(float(result.order_bonus) == float(offer.bonus))
	assert(d.order.is_empty())
	assert(float(app.cash_usd) > before)
	if not d.offers.is_empty():
		assert(int(d.offers[0].stage) == 2)
	assert(not inv.sell(0, 1).success, "cannot claim an order twice")
	# Expiry is soft and checked even if the world clock jumps.
	d.order = offer.duplicate(true)
	d.order.deadline = float(clock.unix_time) + 10
	clock.add_minutes(1)
	merchant.expire()
	assert(d.order.is_empty())
	# Threshold candidates persist, cannot be rerolled, only one active ability.
	merchant.record_sale(pid, 1, 16000)
	assert(not d.candidates.is_empty())
	var candidate: Dictionary = d.candidates[0].duplicate(true)
	assert(merchant.equip(str(candidate.id)))
	assert(d.active.id == candidate.id)
	assert(not merchant.equip(str(candidate.id)))
	merchant._unlock("flights", 5, 5, "")
	assert(merchant.equip(str(d.candidates.back().id)))
	assert(d.active.scope == "flights")
	# Exercise every authored effect, once, with actual held inventory and an order.
	for event_v in merchant.catalog():
		var event: Dictionary = event_v.duplicate(true)
		app.cash_usd = 50000
		app.inventory = [{"product_id": pid, "qty": 2, "unit_cost": 100, "purchased_unix": clock.unix_time, "quality": 1.0, "in_cargo": false}]
		d.order = offer.duplicate(true)
		d.order.deadline = float(clock.unix_time) + 48 * 3600
		d.order.advance = 0.0
		event.key = "test|" + str(event.id)
		event.city = app.current_city_id()
		event.arrival = float(clock.unix_time) + 3600
		merchant.pending_event = event
		assert(merchant.event_available(event))
		assert(merchant.resolve_journey(true), str(event.id))
		assert(not merchant.resolve_journey(true), "double click must not double charge")
		assert(float(app.cash_usd) >= 0)
	# Locked quote is limited to the carried lot and expires.
	var lot: Dictionary = app.inventory[0]
	lot.merchant_deal = {"kind": "lock", "city": app.current_city_id(), "expires": float(clock.unix_time) + 60, "unit": 123, "mult": 1}
	assert(merchant.lot_quote(lot, 5) == 123)
	assert(merchant.lot_quote({"product_id": pid}, 5) == 5)
	clock.add_minutes(1)
	assert(merchant.lot_quote(lot, 5) == 5)
	# Preservation applies only while equipped and respects cold-chain changes.
	var cold_product: Dictionary = {}
	for product in ds.products_by_id.values():
		if bool(product.get("requires_cold_chain", false)) and float(product.get("shelf_life_hours", 0)) > 4 and float(product.get("shelf_life_hours", 0)) < 90000:
			cold_product = product
			break
	assert(not cold_product.is_empty())
	app.set_cold_chain(false)
	var cold_lot := {"product_id": str(cold_product.product_id), "qty": 1, "unit_cost": 100.0, "purchased_unix": float(clock.unix_time), "in_cargo": false}
	app.inventory = [cold_lot]
	d.active = {"id": "cold", "kind": "cold", "scope": "category:" + str(cold_product.category), "category": str(cold_product.category)}
	clock.add_minutes(60)
	app.set_cold_chain(true)
	clock.add_minutes(60)
	d.candidates = [{"id": "fare-test", "kind": "fare", "scope": "flights", "category": ""}]
	assert(merchant.equip("fare-test"))
	clock.add_minutes(60)
	var expected_age := 2.0 * 0.7 + 0.35 * 0.7 + 0.35
	assert(is_equal_approx(economy.current_quality(cold_lot), 1.0 - expected_age / float(cold_product.shelf_life_hours)))
	app.set_cold_chain(false)
	# Proper save round trip and malformed extension recovery.
	var saved: Dictionary = app.to_dict().duplicate(true)
	assert(not root.get_node("SaveSystem").validate(saved).is_empty())
	app.from_dict(saved)
	assert(app.merchant == merchant.sanitize(saved.merchant))
	assert(merchant.sanitize({"order": {"qty": "bad"}, "candidates": [null], "sales": {"x": -1}}).order.is_empty())
	# Load and lay out the real market panel, not just the engine.
	var hud_script: GDScript = load("res://scripts/ui/MainHUD.gd")
	assert(hud_script != null)
	var board: Control = load("res://scripts/ui/MerchantBoard.gd").new()
	root.add_child(board)
	board._expanded = true
	board.rebuild()
	await process_frame
	board.queue_free()
	print("SMOKE_MERCHANT_OK")
	quit(0)
