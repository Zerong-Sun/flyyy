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
var _market_index: Dictionary = {}    # "city_id|product_id" → {b, s}
var _market_loaded: Dictionary = {}   # tracks which cities' markets are lazy-loaded
var routes: Array = []
var economy: Dictionary = {}
var tz_offsets: Dictionary = {}
var disclaimer: String = ""
var product_market_tags: Dictionary = {}
var transfer_edges: Dictionary = {}
var _transfer_keys: Array = []        # available transfer origin keys
var _transfer_loaded: bool = false
var loaded: bool = false


func _ready() -> void:
	_load_all()


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Missing file: %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Failed to open: %s" % path)
		return null
	var text := f.get_as_text()
	f.close()
	var result = JSON.parse_string(text)
	if result == null:
		push_error("Failed to parse JSON: %s" % path)
	return result


func _build_market_index() -> void:
	_market_index.clear()
	for city_id in markets_by_city.keys():
		var entries: Array = markets_by_city[city_id]
		for e in entries:
			var pid := str(e.get("p", ""))
			if pid == "":
				continue
			_market_index["%s|%s" % [str(city_id), pid]] = e


func _load_market_for_city(city_id: String) -> void:
	## Lazy-load market data for a city from per-city JSON file.
	if _market_loaded.has(city_id):
		return
	var path := "res://data/markets/%s.json" % city_id
	var data = _load_json(path)
	if data != null and data is Array:
		markets_by_city[city_id] = data
		# Feed entries into _market_index
		for e in data:
			var pid := str(e.get("p", ""))
			if pid != "":
				_market_index["%s|%s" % [city_id, pid]] = e
	_market_loaded[city_id] = true


func _load_all() -> void:
	# ── world.json (lightweight core) ──
	var w = _load_json("res://data/world.json")
	if w == null or not (w is Dictionary):
		push_error("Missing world.json — run etl/scripts/run_pipeline.py")
		return
	world = w as Dictionary
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

	# ── markets/ (per-city files, loaded on demand) ──
	# ── product_market_tags.json ──
	var t = _load_json("res://data/product_market_tags.json")
	if t != null and t is Dictionary:
		product_market_tags = t as Dictionary

	# ── transfers/ (per-origin files, loaded on demand by transfer_options) ──
	if DirAccess.dir_exists_absolute("res://data/transfers"):
		var tx_files := DirAccess.get_files_at("res://data/transfers")
		for fname in tx_files:
			if fname.ends_with(".json"):
				_transfer_keys.append(fname.replace(".json", ""))
	print("DataService: %d transfer origins available" % _transfer_keys.size())

	# ── flights/ (per-origin, lazy-loaded) ──
	var manifest = _load_json("res://data/flights/_manifest.json")
	if manifest != null and manifest is Dictionary:
		var mf: Dictionary = manifest as Dictionary
		print("Flights manifest: %d origins, %d total flights" % [
			mf.size() - 1,  # minus _total key
			int(mf.get("_total", 0))
		])

	loaded = true
	print("DataService loaded: %d airports, %d products, %d tags, %d transfer-origins" % [
		airports.size(), products_by_id.size(),
		product_market_tags.size(), _transfer_keys.size()
	])


func get_airport(airport_id: String) -> Dictionary:
	return airports_by_id.get(airport_id, {})


func get_airport_by_iata(iata: String) -> Dictionary:
	return airports_by_iata.get(iata.strip_edges().to_upper(), {})


func get_city(city_id: String) -> Dictionary:
	return cities_by_id.get(city_id, {})


func place_name(dict: Dictionary, field: String = "name") -> String:
	## Returns locale-aware display name for cities, airports, or countries.
	## AppState.place_locale: "zh" → field_zh, "en" → field_en.
	var locale := "zh"
	if AppState:
		var pl = AppState.get("place_locale")
		if pl != null:
			locale = str(pl)
	var suffix := "_zh" if locale == "zh" else "_en"
	var key := field + suffix
	var fallback_suffix := "_en" if locale == "zh" else "_zh"
	var fallback_key := field + fallback_suffix
	var raw = dict.get(key)
	if raw != null:
		var s := str(raw)
		if not s.is_empty():
			return s
	raw = dict.get(fallback_key)
	if raw != null:
		return str(raw)
	raw = dict.get(field)
	if raw != null:
		return str(raw)
	return ""


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
	var key := "%s|%s" % [city_id, product_id]
	if not _market_index.has(key):
		# Try lazy-loading first
		_load_market_for_city(city_id)
		if not _market_index.has(key):
			return {}
	var v: Dictionary = _market_index[key]
	return {
		"city_id": city_id,
		"product_id": product_id,
		"buy_base_usd": float(v.get("b", 0.0)),
		"sell_base_usd": float(v.get("s", 0.0)),
	}


func market_product_ids(city_id: String) -> Array:
	_load_market_for_city(city_id)
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
	var data = _load_json(path)
	if data != null and data is Array:
		flights_by_origin[origin_airport_id] = data
		_flights_loaded[origin_airport_id] = true
		return data as Array
	_flights_loaded[origin_airport_id] = true
	return []


func transfer_options(from_iata: String, to_iata: String = "") -> Array:
	## Return transfer edge dicts for origin→dest. If to_iata empty, return all from origin.
	var origin := from_iata.strip_edges().to_upper()
	if origin == "":
		return []
	var data = _load_json("res://data/transfers/%s.json" % origin)
	if data == null or not (data is Dictionary):
		return []
	var edges_map: Dictionary = data as Dictionary
	if to_iata != "":
		var edges = edges_map.get(to_iata.strip_edges().to_upper(), [])
		if edges is Array:
			return edges as Array
		return []
	var out: Array = []
	for dest in edges_map.keys():
		var edges = edges_map[dest]
		if edges is Array:
			for edge_v in edges:
				var edge: Dictionary = edge_v.duplicate(true)
				edge["origin_iata"] = origin
				edge["dest_iata"] = dest
				out.append(edge)
	return out
