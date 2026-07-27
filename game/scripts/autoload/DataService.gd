extends Node
## Loads world.json + flights.json (exported from SQLite ETL).

var world: Dictionary = {}
var flights_by_origin: Dictionary = {}
var airports: Array = []
var airports_by_id: Dictionary = {}
var airports_by_iata: Dictionary = {}
var cities_by_id: Dictionary = {}
var products_by_id: Dictionary = {}
var markets: Array = []
var routes: Array = []
var economy: Dictionary = {}
var tz_offsets: Dictionary = {}
var disclaimer: String = ""
var product_market_tags: Dictionary = {}
var transfer_edges: Dictionary = {}
var loaded: bool = false


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	var world_path := "res://data/world.json"
	var flights_path := "res://data/flights.json"
	if not FileAccess.file_exists(world_path):
		push_error("Missing world.json — run etl/scripts/run_pipeline.py")
		return
	var wf := FileAccess.open(world_path, FileAccess.READ)
	world = JSON.parse_string(wf.get_as_text())
	wf.close()
	airports = world.get("airports", [])
	routes = world.get("routes", [])
	economy = world.get("economy", {})
	tz_offsets = world.get("tz_offsets", {})
	disclaimer = str(world.get("disclaimer", ""))
	airports_by_id.clear()
	airports_by_iata.clear()
	for a in airports:
		airports_by_id[a["airport_id"]] = a
		var iata := str(a.get("iata", "")).to_upper()
		if iata != "":
			airports_by_iata[iata] = a
	for c in world.get("cities", []):
		cities_by_id[c["city_id"]] = c
	for p in world.get("products", []):
		products_by_id[p["product_id"]] = p
	markets = world.get("markets", [])
	product_market_tags = world.get("product_market_tags", {})
	transfer_edges = world.get("transfer_edges", {})
	if FileAccess.file_exists(flights_path):
		var ff := FileAccess.open(flights_path, FileAccess.READ)
		var fdata = JSON.parse_string(ff.get_as_text())
		ff.close()
		flights_by_origin = fdata.get("by_origin", {})
	loaded = true
	print("DataService loaded: %d airports, %d products, %d tags, %d transfers" % [
		airports.size(), products_by_id.size(), product_market_tags.size(), transfer_edges.size()
	])


func get_airport(airport_id: String) -> Dictionary:
	return airports_by_id.get(airport_id, {})


func get_airport_by_iata(iata: String) -> Dictionary:
	return airports_by_iata.get(iata.strip_edges().to_upper(), {})


func get_city(city_id: String) -> Dictionary:
	return cities_by_id.get(city_id, {})


func get_product(product_id: String) -> Dictionary:
	return products_by_id.get(product_id, {})


func search_airports(query: String) -> Array:
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		return airports.duplicate()
	var out: Array = []
	for a in airports:
		var iata := str(a.get("iata", "")).to_lower()
		var icao := str(a.get("icao", "")).to_lower()
		# Exact code match first (IATA / ICAO), then name / city substring.
		if iata == q or icao == q:
			out.append(a)
			continue
		var blob := "%s %s %s %s %s %s" % [
			iata, icao, a.get("name_zh", ""),
			a.get("name_en", ""), a.get("city_zh", ""), a.get("city_en", "")
		]
		if blob.find(q) >= 0:
			out.append(a)
	return out


func random_hub_id() -> String:
	if airports.is_empty():
		return ""
	return airports[randi() % airports.size()]["airport_id"]


func destinations_from(origin_iata: String) -> Array:
	var out: Array = []
	for r in routes:
		if r.get("origin") == origin_iata:
			out.append(r.get("destination"))
	return out


func market_row(city_id: String, product_id: String) -> Dictionary:
	for m in markets:
		if m.get("city_id") == city_id and m.get("product_id") == product_id:
			return m
	return {}


func products_for_city(city_id: String) -> Array:
	var out: Array = []
	for p in world.get("products", []):
		if p.get("origin_city_id") == city_id:
			out.append(p)
	return out


func flights_from(origin_airport_id: String) -> Array:
	return flights_by_origin.get(origin_airport_id, [])


func transfer_options(from_iata: String, to_iata: String = "") -> Array:
	## Return transfer edge dicts for origin→dest. If to_iata empty, return all from origin.
	var origin := from_iata.strip_edges().to_upper()
	if origin == "":
		return []
	if to_iata != "":
		var key := "%s|%s" % [origin, to_iata.strip_edges().to_upper()]
		return transfer_edges.get(key, [])
	var out: Array = []
	var prefix := origin + "|"
	for key in transfer_edges.keys():
		var k := str(key)
		if k.begins_with(prefix):
			var dest := k.substr(prefix.length())
			for edge_v in transfer_edges[key]:
				var edge: Dictionary = edge_v.duplicate(true)
				edge["origin_iata"] = origin
				edge["dest_iata"] = dest
				out.append(edge)
	return out
