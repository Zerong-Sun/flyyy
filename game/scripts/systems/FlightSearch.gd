extends RefCounted
class_name FlightSearch


static func search(
	origin_id: String,
	query: String,
	max_results: int = 250,
	only_unvisited: bool = false,
	sort_by: String = "departure",
	max_price_economy: float = 0.0,
	max_duration_min: int = 0,
	business_available_only: bool = false
) -> Array:
	var now_iso: String = GameClock.now_iso()
	var all: Array = DataService.flights_from(origin_id)
	var q: String = query.strip_edges().to_lower()
	var out: Array = []
	for fl_v in all:
		var fl: Dictionary = fl_v
		if str(fl.get("scheduled_departure_utc", "")) <= now_iso:
			continue
		if only_unvisited:
			var dest_id: String = str(fl.get("destination_airport_id", ""))
			if AppState.visited_airports.has(dest_id):
				continue
		if max_price_economy > 0.0 and float(fl.get("ticket_base_price_economy", 0)) > max_price_economy:
			continue
		if max_duration_min > 0 and int(fl.get("duration_minutes", 0)) > max_duration_min:
			continue
		if business_available_only and not bool(fl.get("cabin_business_available", true)):
			continue
		if q != "":
			var dest_a: Dictionary = DataService.get_airport(str(fl.get("destination_airport_id", "")))
			var blob: String = "%s %s %s %s %s %s" % [
				fl.get("destination_iata", ""), fl.get("marketing_flight_number", ""),
				fl.get("airline_name", ""), fl.get("destination_airport_id", ""),
				dest_a.get("city_zh", ""), dest_a.get("city_en", "")
			]
			if blob.to_lower().find(q) < 0:
				continue
		out.append(fl)
	out.sort_custom(func(a, b): return _cmp(a, b, sort_by))
	if max_results > 0 and out.size() > max_results:
		return out.slice(0, max_results)
	return out


static func _cmp(a: Dictionary, b: Dictionary, sort_by: String) -> bool:
	match sort_by:
		"price":
			return float(a.get("ticket_base_price_economy", 0)) < float(b.get("ticket_base_price_economy", 0))
		"duration":
			return int(a.get("duration_minutes", 0)) < int(b.get("duration_minutes", 0))
		"distance":
			return float(a.get("distance_km", 0)) < float(b.get("distance_km", 0))
		_:
			return str(a.get("scheduled_departure_utc", "")) < str(b.get("scheduled_departure_utc", ""))
