extends RefCounted
class_name EconomySystem
## Deterministic daily market prices + quality / demand modifiers.


static func _hash_unit(seed_s: String) -> float:
	var h: int = 0
	for i in seed_s.length():
		h = ((h * 31) + seed_s.unicode_at(i)) & 0x7fffffff
	return float(h % 10000) / 10000.0


static func daily_factor(save_id: String, city_id: String, game_date: String, product_id: String) -> float:
	var market: Dictionary = DataService.economy.get("market", {})
	var amp: float = float(market.get("daily_variation_amp", 0.06))
	var u: float = _hash_unit("%s|%s|%s|%s" % [save_id, city_id, game_date, product_id])
	return 1.0 + (u - 0.5) * 2.0 * amp


static func buy_price(city_id: String, product_id: String) -> float:
	var row: Dictionary = DataService.market_row(city_id, product_id)
	if row.is_empty():
		return 0.0
	var f: float = daily_factor(AppState.save_id, city_id, GameClock.game_date_string(), product_id)
	return round(float(row.get("buy_base_usd", 0)) * f * 100.0) / 100.0


static func sell_price(city_id: String, product_id: String, quality: float) -> float:
	var row: Dictionary = DataService.market_row(city_id, product_id)
	if row.is_empty():
		return 0.0
	var f: float = daily_factor(AppState.save_id, city_id, GameClock.game_date_string(), product_id)
	var base: float = float(row.get("sell_base_usd", 0)) * f
	var qmul: float = quality_multiplier(quality)
	var key: String = "%s|%s" % [city_id, product_id]
	var pressure: float = float(AppState.demand_pressure.get(key, 0.0))
	var demand_mul: float = max(0.55, 1.0 - pressure)
	return round(base * qmul * demand_mul * 100.0) / 100.0


static func quality_multiplier(quality: float) -> float:
	if quality >= 0.8:
		return 1.0
	if quality >= 0.5:
		return 0.75
	if quality >= 0.2:
		return 0.45
	return 0.1


static func current_quality(item: Dictionary) -> float:
	## Quality from purchased_unix so waiting time ages perishables.
	var p: Dictionary = DataService.get_product(str(item.get("product_id", "")))
	var life: float = float(p.get("shelf_life_hours", 99999))
	if life >= 90000.0:
		return 1.0
	var bought: float = float(item.get("purchased_unix", GameClock.unix_time))
	var hours: float = max(0.0, (GameClock.unix_time - bought) / 3600.0)
	return max(0.0, 1.0 - hours / life)


static func apply_sale_pressure(city_id: String, product_id: String, qty: int) -> void:
	var key: String = "%s|%s" % [city_id, product_id]
	var market: Dictionary = DataService.economy.get("market", {})
	var decay: float = float(market.get("demand_decay_per_sale", 0.08))
	var p: float = float(AppState.demand_pressure.get(key, 0.0))
	p = min(0.7, p + decay * float(qty))
	AppState.demand_pressure[key] = p


static func _parse_ymd(s: String) -> Dictionary:
	var parts: PackedStringArray = s.split("-")
	if parts.size() < 3:
		return {}
	return {"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]), "hour": 0, "minute": 0, "second": 0}


static func day_delta(prev_date: String, new_date: String) -> int:
	if prev_date == "" or new_date == "" or prev_date == new_date:
		return 0
	var a: Dictionary = _parse_ymd(prev_date)
	var b: Dictionary = _parse_ymd(new_date)
	if a.is_empty() or b.is_empty():
		return 1
	var ua: int = Time.get_unix_time_from_datetime_dict(a)
	var ub: int = Time.get_unix_time_from_datetime_dict(b)
	return max(0, int((ub - ua) / 86400.0))


static func recover_demand_for_new_day(prev_date: String, new_date: String) -> void:
	var days: int = day_delta(prev_date, new_date)
	if days <= 0:
		return
	var market: Dictionary = DataService.economy.get("market", {})
	var rec: float = float(market.get("demand_recovery_per_day", 0.05))
	for k in AppState.demand_pressure.keys():
		AppState.demand_pressure[k] = max(0.0, float(AppState.demand_pressure[k]) - rec * float(days))


static func age_inventory(_hours: float) -> void:
	## Kept for flight/FF paths; also bumps purchased_unix baseline via quality sync.
	for item_v in AppState.inventory:
		var item: Dictionary = item_v
		item["quality"] = current_quality(item)


static func apply_flight_fragility(duration_hours: float) -> void:
	for item_v in AppState.inventory:
		var item: Dictionary = item_v
		var p: Dictionary = DataService.get_product(str(item.get("product_id", "")))
		var frag: float = float(p.get("fragility", 0.0))
		if frag <= 0.0:
			continue
		var bought: float = float(item.get("purchased_unix", GameClock.unix_time))
		# Simulate extra aging equivalent for fragile goods during flight.
		item["purchased_unix"] = bought - duration_hours * 3600.0 * frag * 0.25
		item["quality"] = current_quality(item)


static func inventory_cargo_value_usd() -> float:
	var total: float = 0.0
	for item_v in AppState.inventory:
		var item: Dictionary = item_v
		total += float(item.get("unit_cost", 0)) * float(item.get("qty", 0))
	return total


static func format_money(usd: float) -> String:
	return "$%.2f" % usd


static func sell_price_estimate(product_id: String, dest_city: String) -> float:
	## Static approximate sell price — for UI preview, not actual transaction.
	## Returns the sell_base_usd from world data (no runtime modifiers applied).
	var row: Dictionary = DataService.market_row(dest_city, product_id)
	return float(row.get("sell_base_usd", 0.0))


static func sell_price_with_quality(city_id: String, product_id: String, quality: float, qty: int) -> Dictionary:
	## Returns estimated sell price and margin data without executing a transaction.
	## Used by UI preview before confirming a sell.
	var row: Dictionary = DataService.market_row(city_id, product_id)
	if row.is_empty() or qty <= 0:
		return {
			"unit_price": 0.0,
			"revenue": 0.0,
			"margin": 0.0,
			"margin_rate": 0.0,
			"valid": false,
		}
	var unit: float = sell_price(city_id, product_id, quality)
	var total_revenue: float = unit * float(qty)
	var total_unit_cost: float = float(row.get("unit_cost", 0)) * float(qty) if row.has("unit_cost") else 0.0
	var margin: float = total_revenue - total_unit_cost
	var margin_rate: float = margin / total_unit_cost if total_unit_cost > 0.0 else 0.0
	return {
		"unit_price": unit,
		"revenue": total_revenue,
		"total_unit_cost": total_unit_cost,
		"margin": margin,
		"margin_rate": margin_rate,
		"valid": true,
	}
