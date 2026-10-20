extends RefCounted
## Bounded, read-only route estimates. No future price guarantee.
const Economy = preload("res://scripts/systems/EconomySystem.gd")
const Search = preload("res://scripts/systems/FlightSearch.gd")

static func recommendations(limit: int = 5) -> Array:
	if not AppState.held_tickets.is_empty():
		return []
	var flights: Array = Search.search(AppState.current_airport_id, "", 500, false, "departure")
	var seen := {}
	var results: Array = []
	var source_city: String = AppState.current_city_id()
	var ticket_config: Dictionary = DataService.economy.get("ticket", {})
	var capacity: float = float(ticket_config.get("baggage_economy_kg", 20)) + float(ticket_config.get("carry_on_kg", 5))
	for flight in flights:
		var airport: Dictionary = DataService.get_airport(str(flight.get("destination_airport_id", "")))
		var city_id := str(airport.get("city_id", ""))
		if city_id == "" or city_id == source_city or seen.has(city_id):
			continue
		seen[city_id] = true
		if seen.size() > 40:
			break
		var fare: float = float(flight.get("ticket_base_price_economy", 0))
		var wait_hours: float = max(0.0, (GameClock.parse_iso_to_unix(str(flight.get("scheduled_departure_utc", ""))) - GameClock.unix_time) / 3600.0)
		if wait_hours > 24.0:
			continue
		var hours: float = wait_hours + float(flight.get("duration_minutes", 0)) / 60.0
		var lots: Array = AppState.inventory.duplicate(true)
		var starter := ""
		if lots.is_empty():
			var best_margin: float = -INF
			for pid in DataService.market_product_ids(source_city):
				var product: Dictionary = DataService.get_product(pid)
				if str(product.get("origin_city_id", "")) != source_city:
					continue
				# The tutorial avoids perishability and restricted goods.
				if float(product.get("shelf_life_hours", 99999)) < 90000 or str(product.get("hazmat_class", "none")) != "none":
					continue
				var price: float = Economy.buy_price(source_city, pid)
				var weight: float = float(product.get("weight_kg", 1))
				if price <= 0 or weight <= 0:
					continue
				var qty: int = mini(200, int(min(capacity / weight, max(0.0, AppState.cash_usd - fare) / price)))
				if qty <= 0:
					continue
				var best: Dictionary = best_purchase(pid, city_id, price, qty, hours)
				if float(best.margin) > best_margin:
					best_margin = float(best.margin)
					lots = [{"product_id": pid, "qty": int(best.qty), "unit_cost": price, "purchased_unix": GameClock.unix_time, "in_cargo": false}]
					starter = "%s × %d" % [DataService.place_name(product, "name"), int(best.qty)]

		if lots.is_empty():
			continue
		var weight := 0.0
		var purchase := 0.0
		var revenue := 0.0
		var unsupported := false
		for item in lots:
			var product: Dictionary = DataService.get_product(str(item.product_id))
			if bool(item.get("in_cargo", false)) or str(product.get("hazmat_class", "none")) != "none":
				unsupported = true
			weight += float(product.get("weight_kg", 1)) * int(item.qty)
			purchase += float(item.unit_cost) * int(item.qty)

		# Standard carry-on comparison only; do not advertise an unboardable plan.
		if unsupported or weight > capacity or fare > AppState.cash_usd:
			continue
		revenue = estimate_lots(lots, city_id, hours)
		var net: float = revenue - purchase - fare
		results.append({"city_id": city_id, "name_zh": DataService.place_name(DataService.get_city(city_id), "name"), "iata": airport.get("iata", ""), "direct": true, "net": net, "per_kg": net / max(weight, 0.01), "hours": hours, "fare": fare, "purchase": purchase, "revenue": revenue, "starter": starter})
	results.sort_custom(func(a, b): return float(a.net) > float(b.net))
	return results.slice(0, limit)

static func _quality_at_arrival(item: Dictionary, hours: float) -> float:
	var product: Dictionary = DataService.get_product(str(item.product_id))
	var life: float = float(product.get("shelf_life_hours", 99999))
	var quality: float = Economy.current_quality(item)
	if life < 90000:
		var age_multiplier: float = 2.0 if bool(product.get("requires_cold_chain", false)) else 1.0
		quality = max(0.0, quality - hours * age_multiplier / max(life, 0.01))
	return quality


static func best_purchase(pid: String, city_id: String, cost: float, max_qty: int, hours: float) -> Dictionary:
	# Buy only while the next unit improves total profit, not automatically a full bag.
	var item := {"product_id": pid, "purchased_unix": GameClock.unix_time}
	var quality: float = _quality_at_arrival(item, hours)
	var pressure: float = float(AppState.demand_pressure.get("%s|%s" % [city_id, pid], 0.0))
	var decay: float = maxf(0.0, float(DataService.economy.get("market", {}).get("demand_decay_per_sale", 0.08)))
	var margin := 0.0
	var best := {"qty": 1, "margin": -INF}
	for index in max_qty:
		margin += Economy.sell_price(city_id, pid, quality, minf(0.7, pressure + index * decay)) - cost
		if margin > float(best.margin):
			best = {"qty": index + 1, "margin": margin}
	return best


static func estimate_lots(lots: Array, city_id: String, hours: float) -> float:
	var sold: Dictionary = {}
	var total := 0.0
	var decay: float = maxf(0.0, float(DataService.economy.get("market", {}).get("demand_decay_per_sale", 0.08)))
	for item in lots:
		var pid := str(item.product_id)
		var pressure: float = minf(0.7, float(AppState.demand_pressure.get("%s|%s" % [city_id, pid], 0.0)) + float(sold.get(pid, 0)) * decay)
		total += _revenue(item, city_id, hours, pressure)
		sold[pid] = int(sold.get(pid, 0)) + int(item.qty)
	return total


static func _revenue(item: Dictionary, city_id: String, hours: float, pressure: float) -> float:
	var pid := str(item.product_id)
	var quality: float = _quality_at_arrival(item, hours)
	var decay: float = maxf(0.0, float(DataService.economy.get("market", {}).get("demand_decay_per_sale", 0.08)))
	var qty: int = int(item.qty)
	var ramp: int = mini(qty, int(ceil(maxf(0.0, 0.7 - pressure) / decay))) if decay > 0.0 else 0
	var total := 0.0
	for index in ramp:
		total += Economy.sell_price(city_id, pid, quality, minf(0.7, pressure + index * decay))
	if qty > ramp:
		total += (qty - ramp) * Economy.sell_price(city_id, pid, quality, minf(0.7, pressure + ramp * decay))
	return total
