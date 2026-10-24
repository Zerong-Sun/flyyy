extends RefCounted
class_name TripRecap
## Pure bookkeeping for one destination-bound trip. Prices are captured at
## boarding; sale-time quality and market prices are recorded separately.


static func create_forecast(from_city: String, to_city: String, items: Array,
		fare_cost: float, baggage_cost: float) -> Dictionary:
	var forecast_items: Dictionary = {}
	var forecast_revenue := 0.0
	var forecast_cost := 0.0
	for item_v in items:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		var product_id := str(item.get("product_id", ""))
		var qty := maxi(0, int(item.get("qty", 0)))
		if product_id == "" or qty <= 0:
			continue
		var unit := maxf(0.0, float(item.get("forecast_unit", 0.0)))
		var cost := maxf(0.0, float(item.get("unit_cost", 0.0)))
		if not forecast_items.has(product_id):
			forecast_items[product_id] = {"qty": 0, "unit_cost": cost, "forecast_unit": unit, "sold_qty": 0}
		var row: Dictionary = forecast_items[product_id]
		var old_qty := int(row.get("qty", 0))
		var new_qty := old_qty + qty
		row["unit_cost"] = (float(row.get("unit_cost", 0.0)) * old_qty + cost * qty) / new_qty
		row["forecast_unit"] = (float(row.get("forecast_unit", 0.0)) * old_qty + unit * qty) / new_qty
		row["qty"] = new_qty
		forecast_revenue += unit * qty
		forecast_cost += cost * qty
	return {
		"status": "in_transit",
		"from_city": from_city,
		"to_city": to_city,
		"fare_cost": maxf(0.0, fare_cost),
		"baggage_cost": maxf(0.0, baggage_cost),
		"items": forecast_items,
		"forecast_revenue": forecast_revenue,
		"forecast_cost": forecast_cost,
		"actual_revenue": 0.0,
		"sold_cost": 0.0,
		"market_variance": 0.0,
		"quality_loss": 0.0,
		"sold_qty": 0,
		"forecast_sold_qty": 0,
	}


static func land(recap: Dictionary, city_id: String) -> Dictionary:
	if recap.is_empty():
		return {}
	var result := recap.duplicate(true)
	result["status"] = "landed"
	result["to_city"] = city_id
	return result


static func record_sale(recap: Dictionary, city_id: String, product_id: String, qty: int,
		cost: float, revenue: float, full_quality_revenue: float) -> Dictionary:
	if recap.is_empty() or str(recap.get("status", "")) != "landed" \
			or str(recap.get("to_city", "")) != city_id or qty <= 0:
		return recap
	var result := recap.duplicate(true)
	var items: Dictionary = result.get("items", {}).duplicate(true)
	var row: Dictionary = items.get(product_id, {"qty": 0, "unit_cost": 0.0, "forecast_unit": 0.0, "sold_qty": 0})
	var remaining := maxi(0, int(row.get("qty", 0)) - int(row.get("sold_qty", 0)))
	var matched_qty := mini(qty, remaining)
	var unforecast_qty := maxi(0, qty - matched_qty)
	var full_quality_unit := maxf(0.0, full_quality_revenue) / float(qty)
	var expected := float(row.get("forecast_unit", 0.0)) * float(matched_qty) \
			+ full_quality_unit * float(unforecast_qty)
	row["sold_qty"] = int(row.get("sold_qty", 0)) + matched_qty
	items[product_id] = row
	result["items"] = items
	result["actual_revenue"] = float(result.get("actual_revenue", 0.0)) + revenue
	result["sold_cost"] = float(result.get("sold_cost", 0.0)) + cost
	result["market_variance"] = float(result.get("market_variance", 0.0)) + full_quality_revenue - expected
	result["quality_loss"] = float(result.get("quality_loss", 0.0)) + maxf(0.0, full_quality_revenue - revenue)
	result["sold_qty"] = int(result.get("sold_qty", 0)) + qty
	result["forecast_sold_qty"] = int(result.get("forecast_sold_qty", 0)) + matched_qty
	return result


static func add_sale_bonus(recap: Dictionary, city_id: String, bonus: float) -> Dictionary:
	if recap.is_empty() or str(recap.get("status", "")) != "landed" \
			or str(recap.get("to_city", "")) != city_id or bonus <= 0.0:
		return recap
	var result := recap.duplicate(true)
	result["actual_revenue"] = float(result.get("actual_revenue", 0.0)) + bonus
	result["market_variance"] = float(result.get("market_variance", 0.0)) + bonus
	return result


static func totals(recap: Dictionary) -> Dictionary:
	if recap.is_empty():
		return {}
	var fare := float(recap.get("fare_cost", 0.0))
	var baggage := float(recap.get("baggage_cost", 0.0))
	var remaining := 0
	for row_v in recap.get("items", {}).values():
		if typeof(row_v) == TYPE_DICTIONARY:
			var row: Dictionary = row_v
			remaining += maxi(0, int(row.get("qty", 0)) - int(row.get("sold_qty", 0)))
	return {
		"forecast_net": float(recap.get("forecast_revenue", 0.0)) - float(recap.get("forecast_cost", 0.0)) - fare - baggage,
		"realized_net": float(recap.get("actual_revenue", 0.0)) - float(recap.get("sold_cost", 0.0)) - fare - baggage,
		"remaining_qty": remaining,
	}


static func sanitize(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var recap: Dictionary = raw
	var status := str(recap.get("status", ""))
	if status not in ["in_transit", "landed"]:
		return {}
	for field in ["from_city", "to_city"]:
		if typeof(recap.get(field, "")) != TYPE_STRING:
			return {}
	for field in ["fare_cost", "baggage_cost", "forecast_revenue", "forecast_cost", "actual_revenue", "sold_cost", "market_variance", "quality_loss", "sold_qty", "forecast_sold_qty"]:
		if not recap.has(field):
			return {}
		var value_v: Variant = recap[field]
		if typeof(value_v) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value_v)):
			return {}
		if field != "market_variance" and float(value_v) < 0.0:
			return {}
		if field in ["sold_qty", "forecast_sold_qty"] and int(value_v) != float(value_v):
			return {}
	var raw_items: Variant = recap.get("items", {})
	if typeof(raw_items) != TYPE_DICTIONARY:
		return {}
	var clean_items: Dictionary = {}
	for product_v in raw_items.keys():
		var product_id := str(product_v)
		var row_v: Variant = raw_items[product_v]
		if typeof(row_v) != TYPE_DICTIONARY:
			return {}
		var row: Dictionary = row_v
		for field in ["qty", "sold_qty", "unit_cost", "forecast_unit"]:
			if not row.has(field) or typeof(row[field]) not in [TYPE_INT, TYPE_FLOAT] \
					or not is_finite(float(row[field])):
				return {}
		var qty := int(row["qty"])
		var sold_qty := int(row["sold_qty"])
		var unit_cost := float(row["unit_cost"])
		var forecast_unit := float(row["forecast_unit"])
		if qty < 0 or sold_qty < 0 or sold_qty > qty or not is_finite(unit_cost) \
				or not is_finite(forecast_unit) or unit_cost < 0.0 or forecast_unit < 0.0:
			return {}
		if int(row["qty"]) != float(row["qty"]) or int(row["sold_qty"]) != float(row["sold_qty"]):
			return {}
		clean_items[product_id] = {"qty": qty, "sold_qty": sold_qty,
			"unit_cost": unit_cost, "forecast_unit": forecast_unit}
	var clean := recap.duplicate(true)
	clean["items"] = clean_items
	for field in ["from_iata", "to_iata"]:
		if typeof(clean.get(field, "")) != TYPE_STRING:
			clean.erase(field)
	return clean
