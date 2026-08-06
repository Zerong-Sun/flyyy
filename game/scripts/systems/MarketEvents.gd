extends RefCounted
class_name MarketEvents
## Deterministic market events derived from save_id + game date + city.
## Reuses the seeded-random idea from FlightOps._reliability_roll so that a
## given save on a given day always yields the same events (idempotent,
## replayable, and testable) without breaking the "time stays credible" rule.

const FESTIVAL_MULT := 1.15
const WEATHER_COLD_BUY := 1.10
const WEATHER_COLD_SELL := 0.92
const SCARCITY_MULT := 1.10

const EVENT_FESTIVAL := "festival"
const EVENT_WEATHER := "weather_cold"
const EVENT_SCARCITY := "scarcity"

const FESTIVAL_PROB := 0.04
const WEATHER_PROB := 0.03
const SCARCITY_PROB := 0.05


static func _roll(seed_s: String, prob: float) -> bool:
	var h := hash(seed_s)
	var rng := RandomNumberGenerator.new()
	rng.seed = h if h != 0 else 1
	return rng.randf() < prob


static func _day() -> String:
	return GameClock.game_date_string()


## Market multiplier for one product in one city. is_buy selects the
## buy/sell side of the weather-cold event. Returns an event even when the
## multiplier is neutral so callers can render hints uniformly.
static func factor_for(city_id: String, product_id: String, is_buy: bool) -> Dictionary:
	var p: Dictionary = DataService.get_product(product_id)
	if p.is_empty():
		return {"mult": 1.0, "event_id": "", "label": ""}
	var date := _day()
	var is_local := str(p.get("origin_city_id", "")) == city_id
	var is_cold := bool(p.get("requires_cold_chain", false))

	if is_local and _roll("%s|festival|%s" % [city_id, date], FESTIVAL_PROB):
		if not is_buy:
			return {"mult": FESTIVAL_MULT, "event_id": EVENT_FESTIVAL, "label": "ui.event.festival"}
	if is_cold and _roll("%s|weather|%s" % [city_id, date], WEATHER_PROB):
		var mult := WEATHER_COLD_BUY if is_buy else WEATHER_COLD_SELL
		return {"mult": mult, "event_id": EVENT_WEATHER, "label": "ui.event.weather_cold"}
	if is_local and _roll("%s|scarcity|%s" % [city_id, date], SCARCITY_PROB):
		if not is_buy:
			return {"mult": SCARCITY_MULT, "event_id": EVENT_SCARCITY, "label": "ui.event.scarcity"}
	return {"mult": 1.0, "event_id": "", "label": ""}


## All city-level events active today, for the market panel hint line.
## Roll seeds must match factor_for so hints always mirror actual pricing.
static func city_events(city_id: String) -> Array[Dictionary]:
	var date := _day()
	var out: Array[Dictionary] = []
	if _roll("%s|festival|%s" % [city_id, date], FESTIVAL_PROB):
		out.append({"event_id": EVENT_FESTIVAL, "label": "ui.event.festival"})
	if _roll("%s|weather|%s" % [city_id, date], WEATHER_PROB):
		out.append({"event_id": EVENT_WEATHER, "label": "ui.event.weather_cold"})
	if _roll("%s|scarcity|%s" % [city_id, date], SCARCITY_PROB):
		out.append({"event_id": EVENT_SCARCITY, "label": "ui.event.scarcity"})
	return out
