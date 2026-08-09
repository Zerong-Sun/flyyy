extends Node
## Integration verification for the 10 regional news samples, deterministic
## activation, market pricing, flight quoting/removal, and boundary behavior.

const _News = preload("res://scripts/systems/NewsEvents.gd")
const _Economy = preload("res://scripts/systems/EconomySystem.gd")
const _LegacyEvents = preload("res://scripts/systems/MarketEvents.gd")
const _FlightSearch = preload("res://scripts/systems/FlightSearch.gd")

var _failures: PackedStringArray = []
var _news_signal_count := 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		print("FAIL: ", message)


func _ready() -> void:
	await get_tree().process_frame
	var catalog := _News.catalog()
	_check(catalog.size() == 10, "news catalog must contain exactly 10 samples")
	var ids := {}
	var cities := {}
	var kinds := {}
	for event_v in catalog:
		var event: Dictionary = event_v
		var event_id := str(event.get("id", ""))
		var city_id := str(event.get("city_id", ""))
		_check(not event_id.is_empty(), "event id is empty")
		_check(not ids.has(event_id), "duplicate event id: %s" % event_id)
		ids[event_id] = true
		cities[city_id] = true
		kinds[str(event.get("kind", ""))] = true
		_check(not DataService.get_city(city_id).is_empty(), "unknown event city: %s" % city_id)
		_check(not str(event.get("headline_zh", "")).is_empty(), "%s missing zh headline" % event_id)
		_check(not str(event.get("body_zh", "")).is_empty(), "%s missing zh body" % event_id)
		_check(float(event.get("probability", 0.0)) > 0.0 and float(event.get("probability", 0.0)) <= 1.0,
			"%s probability out of range" % event_id)
		_check(int(event.get("duration_days", 0)) >= 1, "%s duration must be positive" % event_id)
		var market: Dictionary = event.get("market", {})
		var flight: Dictionary = event.get("flight", {})
		_check(not (market.get("categories", []) as Array).is_empty(), "%s has no affected categories" % event_id)
		_check(float(market.get("buy_mult", 1.0)) > 0.0, "%s buy multiplier must be positive" % event_id)
		_check(float(market.get("sell_mult", 1.0)) > 0.0, "%s sell multiplier must be positive" % event_id)
		_check(float(flight.get("fare_mult", 1.0)) > 0.0, "%s fare multiplier must be positive" % event_id)
		_check(float(flight.get("cancel_prob", -1.0)) >= 0.0 and float(flight.get("cancel_prob", 2.0)) < 1.0,
			"%s cancellation probability out of range" % event_id)
		_verify_direct_effect(event)
		_check(_find_activation(event), "%s never activated in deterministic two-year window" % event_id)
		if int(event.get("duration_days", 1)) > 1:
			_verify_episode_continuity(event)
	_check(cities.size() == 10, "the 10 samples should cover 10 distinct cities")
	_check(kinds.has("natural") and kinds.has("economic") and kinds.has("political"),
		"catalog must cover natural, economic, and political events")

	# Find a deterministic save where Shanghai's sample is active on baseline.
	var chosen_save := ""
	for i in range(500):
		var sid := "NEWS_TEST_%d" % i
		if not _News.active_for_city("shanghai", "2025-03-01", sid).is_empty():
			chosen_save = sid
			break
	_check(not chosen_save.is_empty(), "could not find deterministic active sample in search window")
	if not chosen_save.is_empty():
		var a := _News.active_for_city("shanghai", "2025-03-01", chosen_save)
		var b := _News.active_for_city("shanghai", "2025-03-01", chosen_save)
		_check(a == b, "same save/date/city must produce identical news")
		AppState.save_id = chosen_save
		GameClock.unix_time = GameClock.BASELINE_UNIX
		_verify_economy_integration(a[0])
		_verify_flight_search_integration(a[0])

	_check(_News.active_for_city("not_a_city", "2025-03-01", "x").is_empty(),
		"unknown city must not produce news")
	_check(_News.active_for_city("shanghai", "not-a-date", "x").is_empty(),
		"invalid date must not produce news")
	_check(_News.active_for_city("shanghai", "2025-02-31", "x").is_empty(),
		"nonexistent calendar date must not produce news")
	_check(_News.market_factor("not_a_city", "not_a_product", true).mult == 1.0,
		"unknown product/city must have neutral market factor")
	_check(_News.quote_flight({}).is_empty(), "empty flight quote must stay empty")
	_verify_day_rollover()
	_finish()


func _verify_direct_effect(event: Dictionary) -> void:
	var market: Dictionary = event.get("market", {})
	var categories: Array = market.get("categories", [])
	var product_id := ""
	var city_id := str(event.get("city_id", ""))
	for product_id_v in DataService.market_product_ids(city_id):
		var product: Dictionary = DataService.get_product(str(product_id_v))
		if str(product.get("category", "")) in categories:
			product_id = str(product_id_v)
			break
	_check(not product_id.is_empty(), "%s categories affect no product in its city market" % event.get("id", ""))
	if product_id.is_empty():
		return
	var buy := _News.market_factor(city_id, product_id, true, [event])
	var sell := _News.market_factor(city_id, product_id, false, [event])
	_check(is_equal_approx(float(buy.mult), float(market.get("buy_mult", 1.0))),
		"%s buy effect mismatch" % event.get("id", ""))
	_check(is_equal_approx(float(sell.mult), float(market.get("sell_mult", 1.0))),
		"%s sell effect mismatch" % event.get("id", ""))

	var airport_id := _airport_for_city(city_id)
	var synthetic := {
		"flight_instance_id": "NEWS_SYNTH_%s" % event.get("id", ""),
		"origin_airport_id": airport_id,
		"destination_airport_id": DataService.airports[0].get("airport_id", ""),
		"ticket_base_price_economy": 100.0,
		"ticket_base_price_business": 400.0,
		"ticket_base_price_first": 900.0,
	}
	var quote1 := _News.quote_flight(synthetic, [event])
	var quote2 := _News.quote_flight(quote1, [event])
	var fare_mult := float((event.get("flight", {}) as Dictionary).get("fare_mult", 1.0))
	_check(is_equal_approx(float(quote1.get("ticket_base_price_economy", 0.0)), 100.0 * fare_mult),
		"%s fare effect mismatch" % event.get("id", ""))
	_check(is_equal_approx(float(quote2.get("ticket_base_price_economy", 0.0)), float(quote1.get("ticket_base_price_economy", 0.0))),
		"%s repeated quote compounded the multiplier" % event.get("id", ""))
	_check(bool(quote1.get("news_unavailable", false)) == bool(quote2.get("news_unavailable", false)),
		"%s flight removal is not deterministic" % event.get("id", ""))
	var removed := 0
	for i in range(120):
		var candidate := synthetic.duplicate(true)
		candidate["flight_instance_id"] = "NEWS_CANCEL_%s_%d" % [event.get("id", ""), i]
		if bool(_News.quote_flight(candidate, [event]).get("news_unavailable", false)):
			removed += 1
	_check(removed > 0 and removed < 120, "%s flight effect must remove some, but not all, sample flights" % event.get("id", ""))

	# Connection rows have no instance id or flight number. Their route identity
	# still needs to vary, otherwise one deterministic roll removes all of them.
	var fallback_removed := 0
	var route_event := event.duplicate(true)
	(route_event["flight"] as Dictionary)["cancel_prob"] = 0.5
	for i in range(120):
		var connection := {
			"origin_airport_id": "ORIGIN",
			"hub_airport_id": "HUB_%d" % (i % 7),
			"destination_airport_id": "DEST_%d" % i,
			"ticket_base_price_economy": 100.0,
		}
		if bool(_News.quote_flight(connection, [route_event]).get("news_unavailable", false)):
			fallback_removed += 1
	_check(fallback_removed > 0 and fallback_removed < 120,
		"%s connection fallback identity correlated every cancellation" % event.get("id", ""))


func _find_activation(event: Dictionary) -> bool:
	var base := GameClock.BASELINE_UNIX
	var city_id := str(event.get("city_id", ""))
	var event_id := str(event.get("id", ""))
	var sid := "ACTIVATION_%s" % event_id
	for day_offset in range(730):
		var date_dict := Time.get_datetime_dict_from_unix_time(int(base + day_offset * 86400.0))
		var date := "%04d-%02d-%02d" % [date_dict.year, date_dict.month, date_dict.day]
		var first := _News.active_for_city(city_id, date, sid)
		var second := _News.active_for_city(city_id, date, sid)
		if first != second:
			_check(false, "%s activation changed between identical calls" % event_id)
			return false
		for active_v in first:
			if str((active_v as Dictionary).get("id", "")) == event_id:
				return true
	return false


func _verify_episode_continuity(event: Dictionary) -> void:
	var base := GameClock.BASELINE_UNIX
	var city_id := str(event.get("city_id", ""))
	var event_id := str(event.get("id", ""))
	var sid := "CONTINUITY_%s" % event_id
	var previous: Dictionary = {}
	var continuations := 0
	for day_offset in range(730):
		var date_dict := Time.get_datetime_dict_from_unix_time(int(base + day_offset * 86400.0))
		var date := "%04d-%02d-%02d" % [date_dict.year, date_dict.month, date_dict.day]
		var current: Dictionary = {}
		for active_v in _News.active_for_city(city_id, date, sid):
			var active: Dictionary = active_v
			if str(active.get("id", "")) == event_id:
				current = active
				break
		if not previous.is_empty() and int(previous.get("days_remaining", 0)) > 1:
			continuations += 1
			_check(not current.is_empty(), "%s episode disappeared before its duration elapsed" % event_id)
			if not current.is_empty():
				_check(int(current.get("start_day", -1)) == int(previous.get("start_day", -2)),
					"%s episode restarted while it was already active" % event_id)
		previous = current
	_check(continuations > 0, "%s continuity test found no multi-day episode" % event_id)


func _verify_economy_integration(event: Dictionary) -> void:
	var city_id := str(event.get("city_id", ""))
	var categories: Array = (event.get("market", {}) as Dictionary).get("categories", [])
	var product_id := ""
	for pid_v in DataService.market_product_ids(city_id):
		var p := DataService.get_product(str(pid_v))
		if str(p.get("category", "")) in categories:
			product_id = str(pid_v)
			break
	_check(not product_id.is_empty(), "active event has no affected product in its city market")
	if product_id.is_empty():
		return
	var row := DataService.market_row(city_id, product_id)
	var daily := _Economy.daily_factor(AppState.save_id, city_id, GameClock.game_date_string(), product_id)
	var legacy := _LegacyEvents.factor_for(city_id, product_id, true)
	var news := _News.market_factor(city_id, product_id, true)
	var expected: float = round(float(row.get("buy_base_usd", 0.0)) * daily * float(legacy.mult) * float(news.mult) * 100.0) / 100.0
	_check(is_equal_approx(_Economy.buy_price(city_id, product_id), expected),
		"EconomySystem did not include news multiplier")


func _verify_flight_search_integration(event: Dictionary) -> void:
	var city_id := str(event.get("city_id", ""))
	var origin_id := _airport_for_city(city_id)
	_check(not origin_id.is_empty(), "active event city has no airport")
	if origin_id.is_empty():
		return
	var results := _FlightSearch.search(origin_id, "", 500)
	_check(not results.is_empty(), "news filtering removed every flight from affected hub")
	var found_affected := false
	for flight_v in results:
		var flight: Dictionary = flight_v
		if str(event.get("id", "")) in flight.get("news_event_ids", []):
			found_affected = true
			_check(float(flight.get("news_fare_mult", 1.0)) != 1.0,
				"affected flight did not receive a fare multiplier")
			break
	_check(found_affected, "FlightSearch results were not annotated with active news")


func _airport_for_city(city_id: String) -> String:
	for airport_v in DataService.airports:
		var airport: Dictionary = airport_v
		if str(airport.get("city_id", "")) == city_id:
			return str(airport.get("airport_id", ""))
	return ""


func _verify_day_rollover() -> void:
	var ops: Node = load("res://scripts/systems/FlightOps.gd").new()
	add_child(ops)
	ops.set_process(false)
	AppState.game_started = true
	AppState.held_tickets = []
	AppState.last_market_date = "2025-03-01"
	AppState.demand_pressure = {"test|product": 0.40}
	GameClock.unix_time = GameClock.BASELINE_UNIX + 86400.0
	_news_signal_count = 0
	EventBus.news_changed.connect(_on_news_changed_for_test)
	ops.call("_process", 0.0)
	EventBus.news_changed.disconnect(_on_news_changed_for_test)
	_check(AppState.last_market_date == "2025-03-02", "day rollover did not update market date")
	_check(float(AppState.demand_pressure.get("test|product", 1.0)) < 0.40,
		"day rollover did not recover demand pressure")
	_check(_news_signal_count == 1, "day rollover must emit exactly one news refresh")
	ops.queue_free()


func _on_news_changed_for_test() -> void:
	_news_signal_count += 1


func _finish() -> void:
	if _failures.is_empty():
		print("VERIFY_NEWS_EVENTS_OK")
		get_tree().quit(0)
	else:
		print("VERIFY_NEWS_EVENTS_FAIL (%d)" % _failures.size())
		for failure in _failures:
			printerr("  - ", failure)
		get_tree().quit(1)
