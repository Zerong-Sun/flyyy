extends RefCounted
class_name InventorySystem

const _Economy = preload("res://scripts/systems/EconomySystem.gd")
const _Tickets = preload("res://scripts/systems/TicketService.gd")
const _TripRecap = preload("res://scripts/systems/TripRecap.gd")


static func buy(product_id: String, qty: int, as_cargo: bool = false, discount_factor: float = 1.0) -> String:
	if not AppState.game_started:
		return "请先开始游戏"
	if qty <= 0:
		return "数量无效"
	var city_id: String = AppState.current_city_id()
	if city_id == "":
		return "当前位置无效"
	var price: float = _Economy.buy_price(city_id, product_id)
	if price <= 0.0:
		return "该商品暂无报价"
	price *= discount_factor
	var total: float = price * float(qty)
	total -= MerchantSystem.purchase_discount(total)
	price = total / float(qty)
	if total > AppState.cash_usd:
		return "资金不足"
	var p: Dictionary = DataService.get_product(product_id)
	var hazmat := str(p.get("hazmat_class", "none"))
	var rule: Dictionary = DataService.hazmat_rule(hazmat)
	# Soft warnings only (v0.3): do not hard-block trade.
	if not bool(rule.get("cabin_ok", true)) and not as_cargo:
		var label := str(rule.get("label_zh", "受限"))
		if label != "":
			EventBus.tutorial_hint.emit("提示：%s — %s（建议货运/冷藏；本版不阻断购买）" % [p.get("name_zh", product_id), label])
	if bool(p.get("requires_cold_chain", false)) and not AppState.trip_cold_chain:
		EventBus.tutorial_hint.emit("提示：%s 建议加购冷藏行李，否则品质衰减更快" % p.get("name_zh", product_id))
	var add_w: float = float(p.get("weight_kg", 0.1)) * float(qty)
	if as_cargo:
		var used: float = AppState.inventory_weight_kg(true, false)
		if used + add_w > AppState.cargo_kg_capacity + 0.001:
			return "货运容量不足：可在航班页加购货运，或先购票"
	else:
		var used_p: float = AppState.inventory_weight_kg(false, true)
		if used_p + add_w > AppState.personal_baggage_limit_kg() + 0.001:
			return "行李超重：请加购行李扩展(+10/+20/+50)或改走货运"
	MerchantSystem.purchase_discount(price * float(qty), true)
	AppState.add_cash(-total)
	AppState.inventory.append({
		"product_id": product_id,
		"qty": qty,
		"unit_cost": price,
		"quality": 1.0,
		"purchased_unix": GameClock.unix_time,
		"in_cargo": as_cargo,
	})
	# Discovery credits at PURCHASE (GDLC Playtest #3): selling is already the
	# profit axis; requiring a sell to "discover" made the products metric
	# anti-correlated with net worth (collector runs wrecked their profit).
	AppState.mark_product_discovered(product_id)
	EventBus.inventory_changed.emit()
	if not bool(AppState.tutorial_flags.get("bought", false)):
		AppState.tutorial_flags["bought"] = true
		var tip := I18nService.tutorial("first_buy")
		if tip.is_empty():
			tip = "已采购商品。打开「航班」选择目的地，公务舱行李额度为经济舱 3 倍。"
		EventBus.tutorial_hint.emit(tip)
	return ""


static func sell(index: int, qty: int) -> Dictionary:
	if not AppState.game_started:
		return {"success": false, "msg": "请先开始游戏"}
	if index < 0 or index >= AppState.inventory.size():
		return {"success": false, "msg": "无效库存"}
	var item: Dictionary = AppState.inventory[index]
	qty = mini(qty, int(item.get("qty", 0)))
	if qty <= 0:
		return {"success": false, "msg": "数量无效"}
	var city_id: String = AppState.current_city_id()
	var product_id: String = str(item.get("product_id", ""))
	var q: float = _Economy.current_quality(item)
	item["quality"] = q
	# In-sale demand escalation (GDLC Playtest #3 ratchet): unit k is priced at
	# the pressure after k-1 units, so a single bulk dump cannot transact 100%
	# of units at the pre-sale price.
	var key: String = "%s|%s" % [city_id, product_id]
	var market: Dictionary = DataService.economy.get("market", {})
	var decay: float = float(market.get("demand_decay_per_sale", 0.08))
	var base_pressure: float = float(AppState.demand_pressure.get(key, 0.0))
	var revenue := 0.0
	var full_quality_revenue := 0.0
	var unit := _Economy.sell_price(city_id, product_id, q)
	for k in range(qty):
		var pressure := minf(0.7, base_pressure + decay * float(k))
		unit = MerchantSystem.lot_quote(item, _Economy.sell_price(city_id, product_id, q, pressure))
		revenue += unit
		full_quality_revenue += MerchantSystem.lot_quote(item, _Economy.sell_price(city_id, product_id, 1.0, pressure))
	var order_bonus := MerchantSystem.record_sale(product_id, qty, revenue)
	revenue += order_bonus
	full_quality_revenue += order_bonus
	var unit_cost: float = float(item.get("unit_cost", 0))
	var total_unit_cost: float = unit_cost * float(qty)
	var margin: float = revenue - total_unit_cost
	var margin_rate: float = margin / total_unit_cost if total_unit_cost > 0.0 else 0.0
	AppState.add_cash(revenue)
	_Economy.apply_sale_pressure(city_id, product_id, qty)
	item["qty"] = int(item.get("qty", 0)) - qty
	if int(item.get("qty", 0)) <= 0:
		AppState.inventory.remove_at(index)
	AppState.log_sell_transaction(city_id, product_id, qty, revenue, total_unit_cost, GameClock.unix_time)
	AppState.trip_recap = _TripRecap.record_sale(AppState.trip_recap, city_id, product_id,
		qty, total_unit_cost, revenue, full_quality_revenue)
	# Hot-streak: selling product at a destination tagged hot relative to its origin.
	var origin_city := str(DataService.get_product(product_id).get("origin_city_id", ""))
	var tag_key := "%s|%s" % [origin_city, product_id]
	var tags: Dictionary = DataService.product_market_tags.get(tag_key, {})
	if city_id in tags.get("hot", []):
		AppState.log_stat("hot_streak_sells", 1.0)
	var msg: String = "售出收入 %s，账面毛利 %s" % [_Economy.format_money(revenue), _Economy.format_money(margin)]
	var result := {
		"success": true,
		"msg": msg,
		"revenue": revenue,
		"order_bonus": order_bonus,
		"qty": qty,
		"product_id": product_id,
		"unit_price": unit,
		"unit_cost": unit_cost,
		"total_unit_cost": total_unit_cost,
		"full_quality_revenue": full_quality_revenue,
		"margin": margin,
		"margin_rate": margin_rate,
		"accidental_premium": false,
		"accidental_premium_bonus": 0.0,
	}
	EventBus.inventory_changed.emit()
	EventBus.market_changed.emit()
	EventBus.sell_completed.emit(result)
	if not bool(AppState.tutorial_flags.get("sold", false)):
		AppState.tutorial_flags["sold"] = true
		var tip := I18nService.tutorial("first_sell")
		if tip.is_empty():
			tip = "出售完成。利润 = 售价 − 成本 − 机票。继续探索价差航线吧。"
		EventBus.tutorial_hint.emit(tip)
	return result


static func expand_baggage(tier: String) -> String:
	return _Tickets.add_baggage_or_cargo(tier, 0)


static func expand_cargo(blocks: int = 1) -> String:
	return _Tickets.add_baggage_or_cargo("", blocks)
