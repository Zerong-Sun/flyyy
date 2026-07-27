extends RefCounted
class_name FlightSearch

const FOCUS_LEAD_SEC := 7200.0


static func seconds_until_departure(fl: Dictionary) -> float:
	var dep: float = GameClock.parse_iso_to_unix(str(fl.get("scheduled_departure_utc", "")))
	return dep - GameClock.unix_time


static func is_short_lead(fl: Dictionary) -> bool:
	return seconds_until_departure(fl) < FOCUS_LEAD_SEC


static func first_focus_index(flights: Array) -> int:
	for i in flights.size():
		if not is_short_lead(flights[i]):
			return i
	return 0


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


static func search_connections(origin_iata: String, query: String = "", max_results: int = 80) -> Array:
	## Build synthetic connection itineraries from DataService.transfer_edges.
	var origin := origin_iata.strip_edges().to_upper()
	if origin == "":
		return []
	var q := query.strip_edges().to_upper()
	var edges: Array = DataService.transfer_options(origin, "")
	var results: Array = []
	var econ: Dictionary = DataService.economy.get("ticket", {})
	var price_per_km: float = float(econ.get("price_per_km_usd", 0.12))
	var connection_factor: float = float(econ.get("connection_price_factor", 0.9))
	for edge_v in edges:
		var edge: Dictionary = edge_v
		var dest: String = str(edge.get("dest_iata", "")).to_upper()
		var hub: String = str(edge.get("hub", "")).to_upper()
		if dest == "" or hub == "":
			continue
		if q != "" and q not in dest and q not in hub:
			var dest_a: Dictionary = DataService.get_airport_by_iata(dest)
			var blob := "%s %s %s %s" % [
				dest, hub, dest_a.get("city_zh", ""), dest_a.get("city_en", "")
			]
			if blob.to_upper().find(q) < 0:
				continue
		var dist: float = float(edge.get("total_distance_km", 0.0))
		var seg1: int = int(edge.get("seg1_duration_avg", 0))
		var seg2: int = int(edge.get("seg2_duration_avg", 0))
		var duration: int = seg1 + 90 + seg2
		var price_econ: float = round(dist * price_per_km * connection_factor * 100.0) / 100.0
		var hub_a: Dictionary = DataService.get_airport_by_iata(hub)
		var dest_ap: Dictionary = DataService.get_airport_by_iata(dest)
		var origin_ap: Dictionary = DataService.get_airport_by_iata(origin)
		results.append({
			"type": "connection",
			"origin_iata": origin,
			"hub_iata": hub,
			"destination_iata": dest,
			"origin_airport_id": str(origin_ap.get("airport_id", "")),
			"hub_airport_id": str(hub_a.get("airport_id", "")),
			"destination_airport_id": str(dest_ap.get("airport_id", "")),
			"total_distance_km": dist,
			"distance_km": dist,
			"seg1_duration_avg": seg1,
			"seg2_duration_avg": seg2,
			"duration_minutes": duration,
			"est_total_duration_min": duration,
			"ticket_base_price_economy": price_econ,
			"ticket_base_price_business": price_econ * 10.0,
			"marketing_flight_number": "CNX %s-%s-%s" % [origin, hub, dest],
			"airline_name": "联程拼装（重建网络）",
			"cabin_business_available": true,
			"scheduled_departure_utc": "",  # filled at purchase time
			"scheduled_arrival_utc": "",
		})
	results.sort_custom(func(a, b): return float(a.get("total_distance_km", 0)) < float(b.get("total_distance_km", 0)))
	if max_results > 0 and results.size() > max_results:
		return results.slice(0, max_results)
	return results
