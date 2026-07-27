extends Node
## Loads world.json + split data files (exported from SQLite ETL).

var world: Dictionary = {}
var flights_by_origin: Dictionary = {}         # lazy-loaded cache: origin_airport_id → Array
var _flights_loaded: Dictionary = {}               # tracks which origins have been loaded
var airports: Array = []
var airports_by_id: Dictionary = {}
var airports_by_iata: Dictionary = {}
var cities_by_id: Dictionary = {}
var products_by_id: Dictionary = {}
var markets_by_city: Dictionary = {}  # city_id → [{p, b, s}, ...]
var routes: Array = []
var economy: Dictionary = {}
var tz_offsets: Dictionary = {}
var disclaimer: String = ""
var product_market_tags: Dictionary = {}
var transfer_edges: Dictionary = {}
var loaded: bool = false


func _ready() -> void:
	_load_all()


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Missing file: %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var result = JSON.parse_string(text)
	if result == null:
		push_error("Failed to parse JSON: %s" % path)
	return result


func _load_all() -> void:
	# ── world.json (lightweight core) ──
	var w := _load_json("res://data/world.json")
	if w == null:
		push_error("Missing world.json — run etl/scripts/run_pipeline.py")
		return
	world = w
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

	# ── markets.json (indexed by city_id, compact keys) ──
	var m := _load_json("res://data/markets.json")
	if m != null:
		markets_by_city = m

	# ── product_market_tags.json ──
	var t := _load_json("res://data/product_market_tags.json")
	if t != null:
		product_market_tags = t

	# ── transfer_edges.json ──
	var e := _load_json("res://data/transfer_edges.json")
	if e != null:
		transfer_edges = e

	# ── flights/ (per-origin, lazy-loaded) ──
	var manifest := _load_json("res://data/flights/_manifest.json")
	if manifest != null:
		print("Flights manifest: %d origins, %d total flights" % [
			manifest.size() - 1,  # minus _total key
			manifest.get("_total", 0)
		])
	else:
		# Fallback to old monolithic flights.json
		var fdata := _load_json("res://data/flights.json")
		if fdata != null:
			flights_by_origin = fdata.get("by_origin", {})

	loaded = true
	print("DataService loaded: %d airports, %d products, %d market-cities, %d tags, %d transfers" % [
		airports.size(), products_by_id.size(), markets_by_city.size(),
		product_market_tags.size(), transfer_edges.size()
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
	var entries: Array = markets_by_city.get(city_id, [])
	for e in entries:
		if e.get("p", "") == product_id:
			var v: Dictionary = e
			return {"city_id": city_id, "product_id": product_id,
					"buy_base_usd": v.get("b", 0.0), "sell_base_usd": v.get("s", 0.0)}
	return {}


func market_product_ids(city_id: String) -> Array:
	var entries: Array = markets_by_city.get(city_id, [])
	var out: Array = []
	for e in entries:
		out.append(e.get("p", ""))
	return out


func products_for_city(city_id: String) -> Array:
	var out: Array = []
	for p in world.get("products", []):
		if p.get("origin_city_id") == city_id:
			out.append(p)
	return out


func flights_from(origin_airport_id: String) -> Array:
	if _flights_loaded.has(origin_airport_id):
		return flights_by_origin.get(origin_airport_id, [])
	var path := "res://data/flights/%s.json" % origin_airport_id
	var data := _load_json(path)
	if data != null and data is Array:
		flights_by_origin[origin_airport_id] = data
		_flights_loaded[origin_airport_id] = true
		return data
	_flights_loaded[origin_airport_id] = true
	return []


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
