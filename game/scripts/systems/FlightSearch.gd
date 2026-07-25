extends RefCounted
class_name FlightSearch


static func search(origin_id: String, query: String, max_results: int = 80) -> Array:
	var now_iso: String = GameClock.now_iso()
	var all: Array = DataService.flights_from(origin_id)
	var q: String = query.strip_edges().to_lower()
	var out: Array = []
	for fl_v in all:
		var fl: Dictionary = fl_v
		if str(fl.get("scheduled_departure_utc", "")) <= now_iso:
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
		if out.size() >= max_results:
			break
	return out
