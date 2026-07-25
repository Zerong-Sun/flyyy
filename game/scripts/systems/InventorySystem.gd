extends RefCounted
class_name InventorySystem

const _Economy = preload("res://scripts/systems/EconomySystem.gd")


static func buy(product_id: String, qty: int, as_cargo: bool = false) -> String:
	if qty <= 0:
		return "数量无效"
	var city_id: String = AppState.current_city_id()
	var price: float = _Economy.buy_price(city_id, product_id)
	var total: float = price * float(qty)
	if total > AppState.cash_usd:
		return "资金不足"
	var p: Dictionary = DataService.get_product(product_id)
	var add_w: float = float(p.get("weight_kg", 0.1)) * float(qty)
	if as_cargo:
		var used: float = AppState.inventory_weight_kg(true, false)
		if used + add_w > AppState.cargo_kg_capacity + 0.001:
			return "货运容量不足，请先加购货运服务"
	else:
		var used_p: float = AppState.inventory_weight_kg(false, true)
		if used_p + add_w > AppState.personal_baggage_limit_kg() + 0.001:
			return "行李超重：可加购行李扩展或改走货运"
	AppState.add_cash(-total)
	AppState.inventory.append({
		"product_id": product_id,
		"qty": qty,
		"unit_cost": price,
		"quality": 1.0,
		"purchased_unix": GameClock.unix_time,
		"in_cargo": as_cargo,
	})
	EventBus.inventory_changed.emit()
	if not bool(AppState.tutorial_flags.get("bought", false)):
		AppState.tutorial_flags["bought"] = true
		EventBus.tutorial_hint.emit("已采购商品。打开「航班」选择目的地，公务舱行李额度为经济舱 3 倍。")
	return ""


static func sell(index: int, qty: int) -> String:
	if index < 0 or index >= AppState.inventory.size():
		return "无效库存"
	var item: Dictionary = AppState.inventory[index]
	qty = mini(qty, int(item.get("qty", 0)))
	if qty <= 0:
		return "数量无效"
	var city_id: String = AppState.current_city_id()
	var q: float = float(item.get("quality", 1.0))
	var unit: float = _Economy.sell_price(city_id, str(item.get("product_id", "")), q)
	var revenue: float = unit * float(qty)
	var cost: float = float(item.get("unit_cost", 0)) * float(qty)
	AppState.add_cash(revenue)
	_Economy.apply_sale_pressure(city_id, str(item.get("product_id", "")), qty)
	item["qty"] = int(item.get("qty", 0)) - qty
	if int(item.get("qty", 0)) <= 0:
		AppState.inventory.remove_at(index)
	EventBus.inventory_changed.emit()
	EventBus.market_changed.emit()
	if not bool(AppState.tutorial_flags.get("sold", false)):
		AppState.tutorial_flags["sold"] = true
		EventBus.tutorial_hint.emit("出售完成。利润 = 售价 − 成本 − 机票。继续探索价差航线吧。")
	return "售出收入 %s，账面毛利 %s" % [_Economy.format_money(revenue), _Economy.format_money(revenue - cost)]
