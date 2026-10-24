extends RefCounted
class_name NewsEvents
## Deterministic, data-driven regional news events.
##
## Activation is derived from save id + event id + start day. Events can span
## multiple days, so the same save is replayable and a save/load cannot reroll
## the market. Flight removals are additionally keyed by flight instance id.

const DATA_PATH := "res://data/news_events.json"
const CATEGORY_EN := {
	"电子": "electronics", "机械": "machinery", "能源": "energy",
	"矿产": "minerals", "工艺品": "crafts", "茶叶": "tea",
	"食品": "food", "纺织品": "textiles", "咖啡": "coffee",
	"日用品": "daily goods",
}

static var _catalog_cache: Array[Dictionary] = []
static var _active_context: Array = []
static var _active_city_cache: Dictionary = {}


static func catalog() -> Array[Dictionary]:
	if _catalog_cache.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f == null:
			push_error("NewsEvents: missing %s" % DATA_PATH)
			return []
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if not parsed is Array:
			push_error("NewsEvents: root must be an array")
			return []
		for row_v in parsed:
			if row_v is Dictionary:
				_catalog_cache.append(row_v)
	return _catalog_cache.duplicate(true)


static func _day_index(date: String) -> int:
	var parts := date.split("-")
	if parts.size() != 3:
		return -1
	var year := int(parts[0])
	var month := int(parts[1])
	var day := int(parts[2])
	if year < 1970 or month < 1 or month > 12 or day < 1 or day > 31:
		return -1
	var days_in_month := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var leap := year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)
	if leap:
		days_in_month[1] = 29
	if day > int(days_in_month[month - 1]):
		return -1
	var dt := {"year": year, "month": month, "day": day, "hour": 0, "minute": 0, "second": 0}
	var unix_day := Time.get_unix_time_from_datetime_dict(dt)
	var normalized := Time.get_datetime_dict_from_unix_time(unix_day)
	if int(normalized.year) != year or int(normalized.month) != month or int(normalized.day) != day:
		return -1
	return int(unix_day / 86400.0)


static func _roll_unit(seed_text: String) -> float:
	var h := hash(seed_text)
	var rng := RandomNumberGenerator.new()
	rng.seed = h if h != 0 else 1
	return rng.randf()


static func active_for_city(city_id: String, game_date: String = "", save_id: String = "") -> Array[Dictionary]:
	if city_id.is_empty():
		return []
	var date := game_date if not game_date.is_empty() else GameClock.game_date_string()
	var sid := save_id if not save_id.is_empty() else AppState.save_id
	# Bound the cache to one date/run. Never leak mutable dictionaries to callers.
	var context := [date, sid]
	if context != _active_context:
		_active_context = context
		_active_city_cache.clear()
	if _active_city_cache.has(city_id):
		var cached: Array[Dictionary] = []
		cached.assign(_active_city_cache[city_id].duplicate(true))
		return cached
	var today := _day_index(date)
	if today < 0:
		return []
	var out: Array[Dictionary] = []
	for event_v in catalog():
		var event: Dictionary = event_v
		if str(event.get("city_id", "")) != city_id:
			continue
		var duration := maxi(1, int(event.get("duration_days", 1)))
		var probability := clampf(float(event.get("probability", 0.0)), 0.0, 1.0)
		# Treat a successful roll as the start of a multi-day episode. Rolls inside
		# an already active episode cannot restart it, otherwise the same headline
		# can be shown again and extend forever on consecutive successful days.
		for age in range(duration - 1, -1, -1):
			var start_day := today - age
			if _is_episode_start(sid, str(event.get("id", "")), start_day, duration, probability):
				var active := event.duplicate(true)
				active["start_day"] = start_day
				active["days_remaining"] = duration - age
				out.append(active)
				break
	_active_city_cache[city_id] = out.duplicate(true)
	return out


static func _is_episode_start(save_id: String, event_id: String, start_day: int,
		duration: int, probability: float) -> bool:
	if _roll_unit("%s|news|%s|%d" % [save_id, event_id, start_day]) >= probability:
		return false
	for prior_day in range(start_day - duration + 1, start_day):
		if _roll_unit("%s|news|%s|%d" % [save_id, event_id, prior_day]) < probability:
			return false
	return true


static func localized(event: Dictionary, field: String) -> String:
	var suffix := "_en" if AppState.ui_locale == "en" else "_zh"
	var value := str(event.get(field + suffix, ""))
	if value.is_empty():
		value = str(event.get(field + ("_zh" if suffix == "_en" else "_en"), ""))
	return value


static func impact_text(event: Dictionary) -> String:
	var market: Dictionary = event.get("market", {})
	var flight: Dictionary = event.get("flight", {})
	var categories := PackedStringArray()
	for category in market.get("categories", []):
		var category_name := str(category)
		if AppState.ui_locale == "en":
			category_name = str(CATEGORY_EN.get(category_name, category_name))
		categories.append(category_name)
	var buy_pct := int(round((float(market.get("buy_mult", 1.0)) - 1.0) * 100.0))
	var sell_pct := int(round((float(market.get("sell_mult", 1.0)) - 1.0) * 100.0))
	var fare_pct := int(round((float(flight.get("fare_mult", 1.0)) - 1.0) * 100.0))
	var cancel_pct := int(round(float(flight.get("cancel_prob", 0.0)) * 100.0))
	if AppState.ui_locale == "en":
		return "Affected: %s · buy %+d%% · sell %+d%% · airfare %+d%% · schedule reduction %d%%" % [
			", ".join(categories), buy_pct, sell_pct, fare_pct, cancel_pct
		]
	return "影响：%s · 采购价 %+d%% · 售价 %+d%% · 票价 %+d%% · 航班削减约 %d%%" % [
		"、".join(categories), buy_pct, sell_pct, fare_pct, cancel_pct
	]


static func market_factor(city_id: String, product_id: String, is_buy: bool, events_override: Array = []) -> Dictionary:
	var events: Array = events_override if not events_override.is_empty() else active_for_city(city_id)
	var product: Dictionary = DataService.get_product(product_id)
	if product.is_empty():
		return {"mult": 1.0, "events": []}
	var category := str(product.get("category", ""))
	var multiplier := 1.0
	var matched: Array[String] = []
	for event_v in events:
		var event: Dictionary = event_v
		if str(event.get("city_id", "")) != city_id:
			continue
		var market: Dictionary = event.get("market", {})
		var categories: Array = market.get("categories", [])
		if not categories.is_empty() and category not in categories:
			continue
		multiplier *= float(market.get("buy_mult" if is_buy else "sell_mult", 1.0))
		matched.append(str(event.get("id", "")))
	return {"mult": clampf(multiplier, 0.5, 2.0), "events": matched}


static func _airport_city(airport_id: String) -> String:
	var airport := DataService.get_airport(airport_id)
	return str(airport.get("city_id", ""))


static func _events_for_route(flight: Dictionary) -> Array[Dictionary]:
	var city_ids: Array[String] = []
	for airport_key in ["origin_airport_id", "hub_airport_id", "destination_airport_id"]:
		var city_id := _airport_city(str(flight.get(airport_key, "")))
		if not city_id.is_empty() and city_id not in city_ids:
			city_ids.append(city_id)
	var out: Array[Dictionary] = []
	for city_id in city_ids:
		out.append_array(active_for_city(city_id))
	return out


static func quote_flight(flight: Dictionary, events_override: Array = []) -> Dictionary:
	if flight.is_empty():
		return {}
	var quoted := flight.duplicate(true)
	var date := GameClock.game_date_string()
	var marker := str(quoted.get("news_quote_date", ""))
	if marker == date and events_override.is_empty():
		return quoted
	# Preserve source prices so a quote can be refreshed on a later day without
	# compounding yesterday's news multiplier.
	for cabin in ["economy", "business", "first"]:
		var key := "ticket_base_price_%s" % cabin
		var base_key := "news_base_price_%s" % cabin
		if not quoted.has(base_key):
			quoted[base_key] = float(quoted.get(key, 0.0))
		quoted[key] = float(quoted.get(base_key, 0.0))
	quoted.erase("news_unavailable")
	var events: Array = events_override if not events_override.is_empty() else _events_for_route(quoted)
	var fare_mult := 1.0
	var ids: Array[String] = []
	var headlines: Array[String] = []
	var flight_key := str(quoted.get("flight_instance_id", ""))
	if flight_key.is_empty():
		flight_key = str(quoted.get("marketing_flight_number", ""))
	if flight_key.is_empty():
		# Synthetic connection itineraries do not have a flight number. Derive a
		# stable route identity so one event roll cannot remove every connection.
		flight_key = "%s|%s|%s|%s" % [
			quoted.get("origin_airport_id", quoted.get("origin_iata", "")),
			quoted.get("hub_airport_id", quoted.get("hub_iata", "")),
			quoted.get("destination_airport_id", quoted.get("destination_iata", "")),
			quoted.get("scheduled_departure_utc", ""),
		]
	for event_v in events:
		var event: Dictionary = event_v
		var effect: Dictionary = event.get("flight", {})
		fare_mult *= float(effect.get("fare_mult", 1.0))
		var cancel_prob := clampf(float(effect.get("cancel_prob", 0.0)), 0.0, 0.95)
		var start_day := int(event.get("start_day", _day_index(date)))
		if _roll_unit("%s|news-flight|%s|%d|%s" % [AppState.save_id, event.get("id", ""), start_day, flight_key]) < cancel_prob:
			quoted["news_unavailable"] = true
		ids.append(str(event.get("id", "")))
		headlines.append(localized(event, "headline"))
	fare_mult = clampf(fare_mult, 0.6, 2.0)
	for cabin in ["economy", "business", "first"]:
		var key := "ticket_base_price_%s" % cabin
		var value := float(quoted.get(key, 0.0))
		if value > 0.0:
			quoted[key] = round(value * fare_mult * 100.0) / 100.0
	quoted["news_quote_date"] = date
	quoted["news_event_ids"] = ids
	quoted["news_headlines"] = headlines
	quoted["news_fare_mult"] = fare_mult
	return quoted
