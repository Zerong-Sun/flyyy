extends Node
## Lightweight offers, flight choices and one replaceable merchant specialty.
## Every roll is keyed by the run and a persisted episode; reopening never rerolls.
signal changed
signal journey_requested(event: Dictionary)
signal journey_resolved
var pending_event: Dictionary = {}
var _rules: Dictionary = {}
var _events: Array = []
var _last_second := -1

func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/merchant_rules.json"))
	return _rules

func catalog() -> Array:
	if _events.is_empty():
		_events = JSON.parse_string(FileAccess.get_file_as_string("res://data/journey_events.json"))
	return _events

func fresh() -> Dictionary:
	return {"offers": [], "order": {}, "batch": "", "chain": 0, "sales": {}, "milestones": {}, "candidates": [], "active": {}, "flights": 0, "seen": [], "coupon": {}, "supply": {}, "lead": {}, "notice": ""}

func data() -> Dictionary:
	if AppState.merchant.is_empty():
		AppState.merchant = fresh()
	return AppState.merchant

func text(zh: String, en: String) -> String:
	return en if AppState.ui_locale == "en" else zh

func localized(row: Dictionary, key: String) -> String:
	return str(row.get(key + ("_en" if AppState.ui_locale == "en" else "_zh"), ""))

func _ready() -> void:
	EventBus.game_started.connect(_start)
	EventBus.arrived.connect(_arrival)

func _start() -> void:
	pending_event = {}
	journey_resolved.emit.call_deferred()
	refresh_offers()

func _process(_dt: float) -> void:
	if not AppState.game_started:
		return
	var second := int(GameClock.unix_time / 60.0)
	if second != _last_second:
		_last_second = second
		expire()

func _change() -> void:
	changed.emit()
	EventBus.settings_changed.emit()

func roll(key: String) -> int:
	return (AppState.save_id + "|merchant|" + key).sha256_text().substr(0, 8).hex_to_int()

func expire() -> void:
	var d := data()
	var order: Dictionary = d.order
	if not order.is_empty() and GameClock.unix_time >= float(order.deadline):
		d.order = {}
		d.chain = 0
		d.notice = text("委托已到期，货物仍可正常出售", "Order expired; goods can still be sold normally")
		_change()

func _arrival() -> void:
	var d := data()
	d.flights = int(d.flights) + 1
	_unlock("flights", float(d.flights), float(rules().flight_milestone), "")
	if AppState.held_tickets.is_empty():
		refresh_offers()
	_change()

func refresh_offers() -> void:
	if not AppState.game_started:
		return
	expire()
	var d := data()
	var batch := "%s|%s|%s" % [AppState.current_city_id(), GameClock.game_date_string(), d.flights]
	if str(d.batch) == batch:
		return
	d.batch = batch
	d.offers = []
	var search: GDScript = load("res://scripts/systems/FlightSearch.gd")
	var flights: Array = search.search(AppState.current_airport_id, "", 180, false, "departure")
	var local_ids: Array = []
	for pid in DataService.market_product_ids(AppState.current_city_id()):
		var product: Dictionary = DataService.get_product(str(pid))
		if str(product.get("origin_city_id", "")) == AppState.current_city_id() and str(product.get("hazmat_class", "none")) == "none":
			local_ids.append(pid)
	if local_ids.is_empty():
		return
	var seen := {}
	for flight_v in flights:
		var flight: Dictionary = flight_v
		var destination := str(DataService.get_airport(str(flight.destination_airport_id)).get("city_id", ""))
		if destination == "" or destination == AppState.current_city_id() or seen.has(destination):
			continue
		seen[destination] = true
		var arrival: float = GameClock.parse_iso_to_unix(str(flight.scheduled_arrival_utc))
		var hours := maxf(float(rules().min_hours), ceil((arrival - GameClock.unix_time) / 3600.0 + 12.0))
		if hours > float(rules().max_hours):
			continue
		var pid := str(local_ids[roll(batch + destination) % local_ids.size()])
		var product: Dictionary = DataService.get_product(pid)
		var unit := float(DataService.market_row(AppState.current_city_id(), pid).get("buy_base_usd", 0))
		if unit <= 0 or DataService.market_row(destination, pid).is_empty():
			continue
		var quantity := mini(12, int(AppState.personal_baggage_limit_kg() * 0.5 / maxf(0.01, float(product.get("weight_kg", 1)))))
		quantity = mini(quantity, int(maxf(0, AppState.cash_usd - float(flight.ticket_base_price_economy)) / unit))
		if quantity < 1:
			continue
		var boost := 1.0
		if not d.lead.is_empty() and str(d.lead.city) == AppState.current_city_id() and GameClock.unix_time < float(d.lead.expires):
			boost = 1.2
		d.offers.append({"id": batch + "|" + destination, "source": AppState.current_city_id(), "city": destination, "airport": str(flight.destination_airport_id), "product": pid, "qty": quantity, "done": 0, "deadline": GameClock.unix_time + hours * 3600.0, "bonus": round(maxf(80.0, unit * quantity * float(rules().order_bonus_rate)) * boost), "advance": 0.0, "stage": 1, "arrival": arrival})
		if d.offers.size() >= int(rules().offer_count):
			break
	_change()

func accept(id: String) -> bool:
	expire()
	var d := data()
	if not d.order.is_empty():
		return false
	for offer_v in d.offers:
		var offer: Dictionary = offer_v
		if str(offer.id) == id and GameClock.unix_time < float(offer.deadline):
			d.order = offer.duplicate(true)
			d.offers = []
			d.notice = ""
			_change()
			return true
	return false

func abandon() -> void:
	data().order = {}
	data().chain = 0
	data().notice = text("已结束委托，已赚收益保留", "Order ended; previous earnings kept")
	_change()

## Called before the base sale is credited. Bonus is part of the same sale ledger.
func record_sale(pid: String, qty: int, revenue: float) -> float:
	expire()
	var d := data()
	var category := str(DataService.get_product(pid).get("category", ""))
	for key in ["product:" + pid, "category:" + category]:
		d.sales[key] = float(d.sales.get(key, 0)) + revenue
		_unlock(key, float(d.sales[key]), float(rules().product_milestone if key.begins_with("product:") else rules().category_milestone), category)
	var order: Dictionary = d.order
	var bonus := 0.0
	if not order.is_empty() and str(order.product) == pid and str(order.city) == AppState.current_city_id():
		order.done = mini(int(order.qty), int(order.done) + qty)
		if int(order.done) >= int(order.qty):
			bonus = maxf(0, float(order.bonus) - float(order.advance))
			d.chain = int(order.stage)
			d.notice = text("委托完成 +$%.0f" % bonus, "Order complete +$%.0f" % bonus)
			d.order = {}
			# Follow-up uses reachable outgoing routes and local goods at this city.
			d.batch = ""
			refresh_offers()
			if int(d.chain) < int(rules().max_chain):
				for follow_v in d.offers:
					var follow: Dictionary = follow_v
					follow.stage = int(d.chain) + 1
					follow.bonus = round(float(follow.bonus) * (1.0 + float(rules().chain_bonus_step) * int(d.chain)))
			else:
				d.chain = 0
	_change()
	return bonus

func _unlock(key: String, amount: float, threshold: float, category: String) -> void:
	var d := data()
	var level := int(amount / threshold)
	if level <= int(d.milestones.get(key, 0)):
		return
	d.milestones[key] = level
	var kinds: Array = ["sell", "buy"]
	if key == "flights":
		kinds = ["fare", "cargo"]
	elif key.begins_with("category:"):
		kinds.append("cold")
	var kind := str(kinds[roll(key + str(level)) % kinds.size()])
	var candidate := {"id": key + ":" + str(level), "kind": kind, "scope": key, "category": category}
	for existing in d.candidates.duplicate():
		if str(existing.scope) == key:
			d.candidates.erase(existing)
	d.candidates.append(candidate)
	while d.candidates.size() > int(rules().candidate_limit):
		d.candidates.pop_front()

func equip(id: String) -> bool:
	var d := data()
	for row_v in d.candidates:
		var row: Dictionary = row_v
		if str(row.id) == id:
			for item in AppState.inventory:
				settle_preservation(item)
			d.active = row.duplicate(true)
			d.candidates.erase(row)
			_change()
			EventBus.market_changed.emit()
			return true
	return false

func dismiss_candidate(id: String) -> void:
	for row in data().candidates.duplicate():
		if str(row.id) == id:
			data().candidates.erase(row)
	_change()

func matches(pid: String, kind: String) -> bool:
	var a: Dictionary = data().active
	if a.is_empty() or str(a.kind) != kind:
		return false
	return str(a.scope) == "product:" + pid or str(a.scope) == "category:" + str(DataService.get_product(pid).get("category", ""))

func ability_label(a: Dictionary) -> String:
	if a.is_empty():
		return text("尚无专长 · 销售或飞行解锁", "Specialties unlock through sales or flights")
	var names := {"sell": text("议价行家 · 售价 +8%", "Negotiator · sell +8%"), "buy": text("采购能手 · 进价 −8%", "Buyer · buy −8%"), "cold": text("保鲜行家 · 损耗减缓 30%", "Preserver · aging −30%"), "fare": text("航空常客 · 票价 −10%", "Frequent flyer · fare −10%"), "cargo": text("货运熟客 · 货运费 −15%", "Cargo regular · cargo −15%")}
	var prefix := ""
	if str(a.scope).begins_with("product:"):
		prefix = DataService.place_name(DataService.get_product(str(a.scope).trim_prefix("product:")), "name") + " · "
	elif str(a.scope).begins_with("category:"):
		prefix = str(a.category) + " · "
	return prefix + str(names.get(str(a.kind), ""))

func buy_factor(pid: String) -> float:
	return 1.0 - float(rules().ability_buy) if matches(pid, "buy") else 1.0

func sell_factor(pid: String) -> float:
	return 1.0 + float(rules().ability_sell) if matches(pid, "sell") else 1.0

func fare_factor() -> float:
	return 1.0 - float(rules().ability_fare) if str(data().active.get("kind", "")) == "fare" else 1.0

func cargo_factor() -> float:
	return 1.0 - float(rules().ability_cargo) if str(data().active.get("kind", "")) == "cargo" else 1.0

func purchase_discount(total: float, consume := false) -> float:
	var c: Dictionary = data().supply
	if c.is_empty() or str(c.city) != AppState.current_city_id() or GameClock.unix_time >= float(c.expires):
		return 0.0
	var discount := minf(100, total * 0.12)
	if consume:
		data().supply = {}
	return discount

func fare_discount(total: float, consume := false) -> float:
	var c: Dictionary = data().coupon
	if c.is_empty() or GameClock.unix_time >= float(c.expires):
		return 0.0
	var discount := minf(150, total * 0.15)
	if consume:
		data().coupon = {}
	return discount

func preservation_hours(item: Dictionary) -> float:
	var credit := float(item.get("merchant_preserved_hours", 0))
	if matches(str(item.product_id), "cold"):
		var speed := 1.0
		if bool(DataService.get_product(str(item.product_id)).get("requires_cold_chain", false)):
			var config: Dictionary = DataService.economy.get("cold_chain", {})
			speed = float(config.get("protected_decay_mult", 0.35) if AppState.trip_cold_chain else config.get("unprotected_decay_mult", 2.0))
		credit += maxf(0, GameClock.unix_time - float(item.get("merchant_age_stamp", item.purchased_unix))) / 3600.0 * 0.3 * speed
	return credit

func settle_preservation(item: Dictionary) -> void:
	item.merchant_preserved_hours = preservation_hours(item)
	item.merchant_age_stamp = GameClock.unix_time

## Quotes are bound to carried lots, so buying new goods cannot reuse them.
func lot_quote(item: Dictionary, normal: float) -> float:
	var deal: Dictionary = item.get("merchant_deal", {})
	if deal.is_empty() or str(deal.city) != AppState.current_city_id() or GameClock.unix_time >= float(deal.expires):
		return normal
	match str(deal.kind):
		"lock": return float(deal.unit)
		"insurance": return maxf(normal, float(deal.unit))
		"buyer", "speculate": return normal * float(deal.mult)
	return normal

func make_event(ticket: Dictionary) -> Dictionary:
	var d := data()
	var key := str(ticket.get("flight_instance_id", "")) + "|" + str(ticket.get("scheduled_departure_utc", ""))
	if key in d.seen or bool(ticket.get("is_connection_leg", false)) and int(ticket.get("connection_leg", 0)) != 1:
		return {}
	var eligible: Array = []
	for ev_v in catalog():
		var ev: Dictionary = ev_v
		if str(ev.kind) in ["lock", "speculate", "insurance", "buyer"] and AppState.inventory.is_empty():
			continue
		if str(ev.kind) in ["extend", "rush", "advance"] and d.order.is_empty():
			continue
		if str(ev.kind) == "advance" and float(d.order.get("advance", 0)) > 0:
			continue
		eligible.append(ev)
	if eligible.is_empty():
		return {}
	var event: Dictionary = eligible[roll(key) % eligible.size()].duplicate(true)
	var final_ticket: Dictionary = AppState.held_tickets.back() if not AppState.held_tickets.is_empty() else ticket
	event.city = str(DataService.get_airport(str(final_ticket.destination_airport_id)).get("city_id", ""))
	event.key = key
	event.arrival = maxf(GameClock.unix_time + float(ticket.duration_minutes) * 60.0, GameClock.parse_iso_to_unix(str(final_ticket.scheduled_arrival_utc)))
	return event

func request_journey(ticket: Dictionary) -> void:
	pending_event = make_event(ticket)
	if pending_event.is_empty():
		return
	if journey_requested.get_connections().is_empty():
		resolve_journey(false)
		return
	journey_requested.emit(pending_event)
	await journey_resolved

func event_available(event: Dictionary) -> bool:
	if event.is_empty():
		return false
	if AppState.cash_usd < float(rules().event_fees.get(str(event.kind), 0)):
		return false
	if str(event.kind) in ["extend", "rush", "advance"]:
		var order: Dictionary = data().order
		if order.is_empty() or float(order.deadline) <= GameClock.unix_time:
			return false
		if str(event.kind) == "rush" and float(order.deadline) - GameClock.unix_time < 12 * 3600:
			return false
	return true

func resolve_journey(accept_choice: bool) -> bool:
	if pending_event.is_empty() or accept_choice and not event_available(pending_event):
		return false
	var ev := pending_event.duplicate(true)
	pending_event = {}
	var d := data()
	d.seen.append(str(ev.key))
	if d.seen.size() > 128:
		d.seen.pop_front()
	if accept_choice:
		var kind := str(ev.kind)
		var fee := float(rules().event_fees.get(kind, 0))
		AppState.add_cash(-fee)
		AppState.record_travel_expense(fee)
		if not AppState.trip_recap.is_empty():
			AppState.trip_recap.journey_cost = float(AppState.trip_recap.get("journey_cost", 0)) + fee
		var order: Dictionary = d.order
		match kind:
			"extend": order.deadline = float(order.deadline) + 6 * 3600
			"rush":
				order.deadline = float(order.deadline) - 4 * 3600
				order.bonus = float(order.bonus) * 1.25
			"advance":
				var advance := float(order.bonus) * 0.25
				order.advance = advance
				order.bonus = float(order.bonus) * 0.75
				AppState.add_cash(advance)
				AppState.realized_margin += advance
				if not AppState.trip_recap.is_empty():
					AppState.trip_recap.journey_income = float(AppState.trip_recap.get("journey_income", 0)) + advance
			"fare": d.coupon = {"expires": float(ev.arrival) + 72 * 3600}
			"supply": d.supply = {"city": ev.city, "expires": float(ev.arrival) + 24 * 3600}
			"tip": d.lead = {"city": ev.city, "expires": float(ev.arrival) + 72 * 3600}
			"lock", "insurance", "buyer", "speculate":
				var economy: GDScript = load("res://scripts/systems/EconomySystem.gd")
				var multiplier := 1.08
				if kind == "speculate":
					multiplier = 1.25 if roll(str(ev.key) + "premium") % 100 < 60 else 0.9
				for item in AppState.inventory:
					var unit: float = economy.sell_price(str(ev.city), str(item.product_id), economy.current_quality(item)) * 0.95
					if kind == "insurance":
						unit = float(item.unit_cost) * 0.9
					item.merchant_deal = {"kind": kind, "city": ev.city, "unit": unit, "mult": multiplier, "expires": float(ev.arrival) + float(rules().event_quote_hours) * 3600}
				if kind == "buyer":
					GameClock.add_minutes(60)
		d.notice = localized(ev, "action")
		if kind == "speculate":
			d.notice = text("买家已回价：+25%" if roll(str(ev.key) + "premium") % 100 < 60 else "买家已回价：−10%", "Buyer quote: +25%" if roll(str(ev.key) + "premium") % 100 < 60 else "Buyer quote: −10%")
	_change()
	journey_resolved.emit()
	return true

func sanitize(raw: Variant) -> Dictionary:
	var clean := fresh()
	if not raw is Dictionary:
		return clean
	for key in clean:
		if raw.has(key) and typeof(raw[key]) == typeof(clean[key]):
			clean[key] = raw[key].duplicate(true) if raw[key] is Dictionary or raw[key] is Array else raw[key]
	# JSON numbers load as floats, including integer counters.
	for key in ["chain", "flights"]:
		if _number(raw.get(key, 0)):
			clean[key] = maxi(0, int(raw.get(key, 0)))
	for key in ["sales", "milestones"]:
		for scope in clean[key].keys():
			if not scope is String or not _number(clean[key][scope]):
				clean[key].erase(scope)
	if not _valid_ability(clean.active):
		clean.active = {}
	clean.candidates = clean.candidates.filter(func(a): return _valid_ability(a) and not a.is_empty()).slice(-3)
	clean.offers = clean.offers.filter(func(o): return _valid_order(o) and not o.is_empty()).slice(0, 3)
	if not _valid_order(clean.order):
		clean.order = {}
	clean.seen = clean.seen.filter(func(k): return k is String).slice(-128)
	for key in ["coupon", "supply", "lead"]:
		var c: Dictionary = clean[key]
		if not c.is_empty() and (not _number(c.get("expires")) or key != "coupon" and not c.get("city") is String):
			clean[key] = {}
	return clean

func _number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) >= 0

func _valid_ability(a: Variant) -> bool:
	if not a is Dictionary:
		return false
	if a.is_empty():
		return true
	return a.get("kind", "") in ["sell", "buy", "cold", "fare", "cargo"] and a.get("id") is String and a.get("scope") is String and a.get("category") is String

func _valid_order(o: Variant) -> bool:
	if not o is Dictionary:
		return false
	if o.is_empty():
		return true
	for key in ["id", "source", "city", "airport", "product"]:
		if not o.get(key) is String:
			return false
	for key in ["qty", "done", "deadline", "bonus", "advance", "stage", "arrival"]:
		if not _number(o.get(key)):
			return false
	return float(o.qty) >= 1 and float(o.qty) == floor(float(o.qty)) and float(o.done) <= float(o.qty) and float(o.stage) >= 1 and float(o.stage) <= float(rules().max_chain) and not DataService.get_product(str(o.product)).is_empty() and not DataService.get_city(str(o.city)).is_empty()
