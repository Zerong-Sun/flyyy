extends SceneTree
## Focused accounting regression for itinerary forecast, market drift,
## product quality loss, partial sales, and fare / baggage charges.

const _TripRecap = preload("res://scripts/systems/TripRecap.gd")
var _economy_script: GDScript
var _inventory_script: GDScript
var _flight_ops_script: GDScript


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_economy_script = load("res://scripts/systems/EconomySystem.gd") as GDScript
	_inventory_script = load("res://scripts/systems/InventorySystem.gd") as GDScript
	_flight_ops_script = load("res://scripts/systems/FlightOps.gd") as GDScript
	var recap := _TripRecap.create_forecast("ams", "ist", [{
		"product_id": "ceramics", "qty": 4, "unit_cost": 20.0, "forecast_unit": 40.0,
	}], 120.0, 30.0)
	recap = _TripRecap.land(recap, "ist")
	recap = _TripRecap.record_sale(recap, "ist", "ceramics", 3, 60.0, 105.0, 120.0)
	var totals: Dictionary = _TripRecap.totals(recap)
	assert(is_equal_approx(float(totals.forecast_net), -70.0), "forecast net must include fare and baggage once")
	assert(is_equal_approx(float(totals.realized_net), -105.0), "partial sale actual must exclude unsold stock")
	assert(is_equal_approx(float(recap.market_variance), 0.0), "stable full-quality quote should have no market variance")
	assert(is_equal_approx(float(recap.quality_loss), 15.0), "quality loss must be isolated from market variance")
	assert(int(totals.remaining_qty) == 1, "partial sale should leave one forecast unit pending")
	recap = _TripRecap.add_sale_bonus(recap, "ist", 5.0)
	assert(is_equal_approx(float(recap.actual_revenue), 110.0), "sale premium should update realized revenue")
	assert(is_equal_approx(float(recap.market_variance), 5.0), "sale premium belongs in price variance")
	assert(is_equal_approx(float(recap.quality_loss), 15.0), "premium must not erase the recorded quality loss")
	var unchanged := _TripRecap.record_sale(recap, "lon", "ceramics", 1, 20.0, 20.0, 20.0)
	assert(unchanged == recap, "sales in another city must not leak into the trip")
	assert(not _TripRecap.sanitize(recap).is_empty(), "valid trip ledger must survive save sanitization")
	var corrupt_recap := recap.duplicate(true)
	corrupt_recap["items"] = "corrupt"
	assert(_TripRecap.sanitize(corrupt_recap).is_empty(), "malformed persisted trip data must be discarded")
	var mixed_stock := _TripRecap.create_forecast("ams", "ist", [{
		"product_id": "tea", "qty": 1, "unit_cost": 5.0, "forecast_unit": 10.0,
	}], 0.0, 0.0)
	mixed_stock = _TripRecap.land(mixed_stock, "ist")
	mixed_stock = _TripRecap.record_sale(mixed_stock, "ist", "tea", 2, 10.0, 24.0, 24.0)
	assert(is_equal_approx(float(mixed_stock.market_variance), 2.0), "goods bought after landing must not be counted as market drift")
	mixed_stock = _TripRecap.record_sale(mixed_stock, "ist", "new_product", 1, 5.0, 12.0, 12.0)
	assert(not _TripRecap.sanitize(mixed_stock).is_empty(), "selling a new product after landing must survive save/reload")

	# Exercise the real market sell path to ensure it reports the same quote that
	# the trip ledger uses and does not invent a quality loss for fresh goods.
	var app_state := root.get_node("AppState")
	var clock := root.get_node("GameClock")
	var flight_ops: Node = _flight_ops_script.new() as Node
	root.add_child(flight_ops)
	app_state.call("reset_new_game", "lhr")
	app_state.set("save_id", "trip-recap-smoke")
	app_state.set("game_started", false)
	var city_id := str(app_state.call("current_city_id"))
	var product_id := "lhr_tea"
	var unit_cost: float = _economy_script.call("buy_price", city_id, product_id)
	app_state.set("inventory", [{
		"product_id": product_id, "qty": 1, "unit_cost": unit_cost,
		"quality": 1.0, "purchased_unix": float(clock.get("unix_time")), "in_cargo": false,
	}])
	var leg1 := {
		"flight_instance_id": "smoke-leg-1", "origin_iata": "LHR", "destination_iata": "IST",
		"origin_airport_id": "lhr", "destination_airport_id": "ist",
		"duration_minutes": 120, "layover_minutes": 60,
	}
	var leg2 := {
		"flight_instance_id": "smoke-leg-2", "origin_iata": "IST", "destination_iata": "DXB",
		"origin_airport_id": "ist", "destination_airport_id": "dxb",
		"duration_minutes": 90,
	}
	app_state.set("held_tickets", [leg1, leg2])
	app_state.set("last_flight_price", 350.0)
	app_state.set("last_baggage_cost", 40.0)
	flight_ops.call("_capture_trip_forecast", leg1)
	var in_flight_recap: Dictionary = app_state.get("trip_recap")
	assert(str(in_flight_recap.to_city) == "dubai", "connection forecast must target the final destination")
	assert(is_equal_approx(float(in_flight_recap.fare_cost), 350.0), "all itinerary fares must be counted once")
	assert(is_equal_approx(float(in_flight_recap.baggage_cost), 40.0), "itinerary baggage must be counted once")
	assert(is_equal_approx(float(in_flight_recap.estimated_arrival_unix) - float(clock.get("unix_time")), 270.0 * 60.0), "connection forecast arrival time must include the layover")
	app_state.set("current_airport_id", "dxb")
	app_state.set("held_tickets", [])
	app_state.set("trip_recap", _TripRecap.land(in_flight_recap, str(app_state.call("current_city_id"))))
	app_state.set("game_started", true)
	var live_sale: Dictionary = _inventory_script.call("sell", 0, 1)
	assert(bool(live_sale.get("success")), "InventorySystem sell integration failed")
	var live_recap: Dictionary = app_state.get("trip_recap")
	assert(is_equal_approx(float(live_recap.actual_revenue), float(live_sale.revenue)), "trip ledger must use realized sale revenue")
	assert(is_equal_approx(float(live_recap.quality_loss), 0.0), "fresh inventory must have no quality loss")
	assert(is_equal_approx(float(live_recap.market_variance), 0.0), "same-time market quote should match forecast")
	print("SMOKE_TRIP_RECAP_OK")
	quit(0)
