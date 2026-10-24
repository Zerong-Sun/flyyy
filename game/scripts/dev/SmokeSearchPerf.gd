extends SceneTree
## Repeatable warm search benchmark. The digest guards result parity across changes.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state: Node = root.get_node("AppState")
	var clock: Node = root.get_node("GameClock")
	var data: Node = root.get_node("DataService")
	var search: GDScript = load("res://scripts/systems/FlightSearch.gd")
	var news: GDScript = load("res://scripts/systems/NewsEvents.gd")
	var failures: Array[String] = []
	state.reset_new_game("pvg")
	state.save_id = "gamedev-search-benchmark"
	clock.set_paused(true)
	clock.unix_time = clock.BASELINE_UNIX + 15 * 86400
	data.flights_from("pvg")
	for options in [["", "departure", 0.0], ["LHR", "price", 0.0], ["", "price", 500.0]]:
		var times: Array[float] = []
		var rows: Array = []
		for repeat in 3:
			var start := Time.get_ticks_usec()
			rows = search.search("pvg", options[0], 0, false, options[1], options[2])
			times.append((Time.get_ticks_usec() - start) / 1000.0)
		times.sort()
		print("SEARCH_BENCH query=%s sort=%s budget=%s count=%d median_ms=%.3f digest=%s" % [
			options[0], options[1], options[2], rows.size(), times[1], JSON.stringify(rows).sha256_text()])
		# Independent quote-first reference preserves the pre-optimization order.
		var reference: Array = []
		for flight in data.flights_from("pvg"):
			var quoted: Dictionary = news.quote_flight(flight)
			if quoted.get("news_unavailable", false) or str(quoted.scheduled_departure_utc) <= clock.now_iso():
				continue
			if options[2] > 0.0 and float(quoted.ticket_base_price_economy) > options[2]:
				continue
			if options[0] != "":
				var airport: Dictionary = data.get_airport(str(quoted.destination_airport_id))
				var blob := "%s %s %s %s %s %s" % [quoted.get("destination_iata", ""),
					quoted.get("marketing_flight_number", ""), quoted.get("airline_name", ""),
					quoted.get("destination_airport_id", ""), airport.get("city_zh", ""), airport.get("city_en", "")]
				if str(options[0]).to_lower() not in blob.to_lower():
					continue
			reference.append(quoted)
		reference.sort_custom(func(a, b): return search._cmp(a, b, options[1]))
		if rows != reference or rows.is_empty():
			failures.append("search differs from reference: %s" % [options])
	print("SMOKE_SEARCH_PERF_OK" if failures.is_empty() else "SMOKE_SEARCH_PERF_FAIL: %s" % [failures])
	quit(0 if failures.is_empty() else 1)
