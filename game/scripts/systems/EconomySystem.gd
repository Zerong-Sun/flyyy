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


static func apply_sale_pressure(city_id: String, product_id: String, qty: int) -> void:
	var key: String = "%s|%s" % [city_id, product_id]
	var market: Dictionary = DataService.economy.get("market", {})
	var decay: float = float(market.get("demand_decay_per_sale", 0.08))
	var p: float = float(AppState.demand_pressure.get(key, 0.0))
	p = min(0.7, p + decay * float(qty))
	AppState.demand_pressure[key] = p


static func recover_demand_for_new_day(prev_date: String, new_date: String) -> void:
	if prev_date == new_date:
		return
	var market: Dictionary = DataService.economy.get("market", {})
	var rec: float = float(market.get("demand_recovery_per_day", 0.05))
	for k in AppState.demand_pressure.keys():
		AppState.demand_pressure[k] = max(0.0, float(AppState.demand_pressure[k]) - rec)


static func age_inventory(hours: float) -> void:
	for item_v in AppState.inventory:
		var item: Dictionary = item_v
		var p: Dictionary = DataService.get_product(str(item.get("product_id", "")))
		var life: float = float(p.get("shelf_life_hours", 99999))
		if life >= 90000.0:
			continue
		var q: float = float(item.get("quality", 1.0))
		q = max(0.0, q - hours / life)
		item["quality"] = q


static func format_money(usd: float) -> String:
	var cny: float = usd * float(DataService.economy.get("fx_usd_cny", 7.2))
	return "$%.2f（约¥%.0f）" % [usd, cny]
