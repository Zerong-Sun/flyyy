extends Control
## Main HUD + panels. Builds UI in code for a self-contained Demo.

const _Economy = preload("res://scripts/systems/EconomySystem.gd")
const _Inventory = preload("res://scripts/systems/InventorySystem.gd")
const _Tickets = preload("res://scripts/systems/TicketService.gd")
const _FlightSearch = preload("res://scripts/systems/FlightSearch.gd")
const _Colors = preload("res://themes/DemoColors.gd")
const _ThemeFactory = preload("res://themes/ThemeFactory.gd")

@onready var globe: Node3D = $"../Globe"
@onready var flight_ops: Node = $"../FlightOps"

var _clock_label: Label
var _cash_label: Label
var _bag_label: Label
var _airport_label: Label
var _disclaimer: Label
var _search: LineEdit
var _airport_list: ItemList
var _airport_card: RichTextLabel
var _hint: Label
var _countdown: Label
var _btn_ff: Button
var _panel_host: Control
var _flight_list: ItemList
var _flight_query: LineEdit
var _flight_detail: RichTextLabel
const INTEL_UPGRADE_COST := 200.0
var _market_container: VBoxContainer
var _inv_list: ItemList
var _city_text: RichTextLabel
var _log_text: RichTextLabel
var _attr_text: RichTextLabel
var _overlay: ColorRect
var _overlay_label: Label
var _new_game_panel: PanelContainer
var _selected_flight: Dictionary = {}
var _cabin: String = "economy"
var _extra_tier: String = ""
var _cargo_blocks: int = 0
var _flights_cache: Array = []
var _market_cache: Array = []
var _product_market_tags: Dictionary = {}
var _selected_market_product_id: String = ""
var _market_row_panels: Dictionary = {}
var _last_hint_time := 0.0
var _ff_dialog: ConfirmationDialog
var _replace_ticket_dialog: ConfirmationDialog
var _pending_cabin: String = ""
var _filter_unvisited: bool = false
var _sort_by: String = "departure"
var _flight_page: int = 0
var _max_price: float = 0.0
var _max_duration: int = 0
var _biz_only: bool = false
const FLIGHTS_PER_PAGE := 80
var _transition_running: bool = false
var _trade_qty: SpinBox
var _flight_auto_focus: bool = false
var _active_arrival_discount: Dictionary = {}
var _free_cargo_on_flight: bool = false


func _ready() -> void:
	_build_ui()
	EventBus.airport_selected.connect(_on_airport_selected)
	EventBus.cash_changed.connect(_refresh_top)
	EventBus.inventory_changed.connect(_refresh_bags)
	EventBus.ticket_purchased.connect(_refresh_countdown)
	EventBus.arrived.connect(_on_arrived)
	EventBus.tutorial_hint.connect(_show_hint)
	EventBus.game_started.connect(_on_game_started)
	flight_ops.transition_started.connect(_on_transition_started)
	flight_ops.transition_finished.connect(_on_transition_finished)
	_load_market_tags()
	_show_new_game()
	_refresh_airport_list("")
	_disclaimer.text = I18nService.disclaimer()


func _process(_d: float) -> void:
	_refresh_clock()
	_refresh_countdown()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _ThemeFactory.build()

	var top := _bar(_Colors.BG_DEEP)
	top.position = Vector2(0, 0)
	top.size = Vector2(1280, 52)
	add_child(top)
	_clock_label = _label(top, Vector2(12, 8), "时间")
	_cash_label = _label(top, Vector2(520, 8), "资金")
	_bag_label = _label(top, Vector2(820, 8), "行李")
	_airport_label = _label(top, Vector2(1000, 8), "机场")

	_countdown = _label(self, Vector2(400, 60), "")
	_countdown.add_theme_font_size_override("font_size", 16)
	_countdown.add_theme_color_override("font_color", _Colors.WARN_RED)
	_btn_ff = Button.new()
	_btn_ff.text = I18nService.t("ui.ff.button")
	_btn_ff.position = Vector2(720, 56)
	_btn_ff.visible = false
	_btn_ff.pressed.connect(_on_fast_forward)
	_style_cta_button(_btn_ff)
	add_child(_btn_ff)

	_disclaimer = _label(self, Vector2(12, 690), I18nService.disclaimer())
	_disclaimer.add_theme_font_size_override("font_size", 12)
	_disclaimer.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	_disclaimer.modulate = Color(1, 1, 1, 0.7)

	_hint = _label(self, Vector2(200, 100), "")
	_hint.size = Vector2(880, 40)
	_hint.add_theme_color_override("font_color", _Colors.ACCENT_AMBER)

	# Left search
	var left := PanelContainer.new()
	left.position = Vector2(8, 120)
	left.size = Vector2(250, 420)
	add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索机场 / IATA / ICAO / 城市"
	_search.text_changed.connect(_refresh_airport_list)
	lv.add_child(_search)
	_airport_list = ItemList.new()
	_airport_list.custom_minimum_size = Vector2(230, 300)
	_airport_list.item_selected.connect(_on_list_airport)
	lv.add_child(_airport_list)
	var btn_rand := Button.new()
	btn_rand.text = I18nService.t("ui.new_game.random")
	btn_rand.pressed.connect(_on_random)
	lv.add_child(btn_rand)
	var btn_routes := Button.new()
	btn_routes.text = "显示/隐藏航线"
	btn_routes.pressed.connect(_on_toggle_routes)
	lv.add_child(btn_routes)

	# Right airport card
	var right := PanelContainer.new()
	right.position = Vector2(1000, 120)
	right.size = Vector2(270, 360)
	add_child(right)
	_airport_card = RichTextLabel.new()
	_airport_card.bbcode_enabled = true
	_airport_card.fit_content = false
	_airport_card.custom_minimum_size = Vector2(250, 340)
	_airport_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_airport_card)

	# Bottom nav
	var bottom := HBoxContainer.new()
	bottom.position = Vector2(200, 640)
	bottom.size = Vector2(880, 40)
	add_child(bottom)
	for pair in [
		[I18nService.t("ui.tab.city"), "_show_city"],
		[I18nService.t("ui.tab.market"), "_show_market"],
		[I18nService.t("ui.tab.flights"), "_show_flights"],
		[I18nService.t("ui.tab.inventory"), "_show_inventory"],
		["笔记", "_show_notes"],
		[I18nService.t("ui.tab.log"), "_show_log"],
		[I18nService.t("ui.tab.attribution"), "_show_attr"],
		[I18nService.t("ui.save.manual"), "_save"],
		[I18nService.t("ui.save.load"), "_load"],
		[I18nService.t("ui.settings.title"), "_toggle_pause"],
	]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(Callable(self, pair[1]))
		b.pressed.connect(func (): AudioService.play_sfx("sfx_ui_click"))
		bottom.add_child(b)

	_panel_host = PanelContainer.new()
	_panel_host.position = Vector2(260, 150)
	_panel_host.size = Vector2(720, 460)
	_panel_host.clip_contents = true
	_panel_host.visible = false
	add_child(_panel_host)

	_overlay = ColorRect.new()
	_overlay.color = Color(_Colors.BG_DEEP.r, _Colors.BG_DEEP.g, _Colors.BG_DEEP.b, 0.82)
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	_overlay_label = Label.new()
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_overlay_label.add_theme_font_size_override("font_size", 28)
	_overlay_label.add_theme_color_override("font_color", _Colors.ICE)
	_overlay.add_child(_overlay_label)

	_ff_dialog = ConfirmationDialog.new()
	_ff_dialog.title = "加速至起飞"
	_ff_dialog.ok_button_text = "确认加速"
	_ff_dialog.cancel_button_text = "取消"
	_ff_dialog.confirmed.connect(_do_fast_forward)
	add_child(_ff_dialog)

	_replace_ticket_dialog = ConfirmationDialog.new()
	_replace_ticket_dialog.title = "替换机票"
	_replace_ticket_dialog.ok_button_text = "退旧票并购买"
	_replace_ticket_dialog.cancel_button_text = "取消"
	_replace_ticket_dialog.confirmed.connect(_do_replace_purchase)
	add_child(_replace_ticket_dialog)

	_new_game_panel = PanelContainer.new()
	_new_game_panel.position = Vector2(360, 200)
	_new_game_panel.size = Vector2(560, 280)
	add_child(_new_game_panel)
	var ngv := VBoxContainer.new()
	_new_game_panel.add_child(ngv)
	var title := Label.new()
	title.text = "《环球航商》Demo — " + I18nService.t("ui.new_game.title")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", _Colors.ICE)
	ngv.add_child(title)
	var info := Label.new()
	info.text = "在左侧搜索或点选地球机场，然后开始。也可随机。\n" + I18nService.disclaimer()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	ngv.add_child(info)
	var row := HBoxContainer.new()
	ngv.add_child(row)
	var b1 := Button.new()
	b1.text = I18nService.t("ui.new_game.start")
	b1.pressed.connect(_start_selected)
	_style_cta_button(b1)
	row.add_child(b1)
	var b2 := Button.new()
	b2.text = I18nService.t("ui.new_game.random")
	b2.pressed.connect(func (): _on_random(); _start_selected())
	row.add_child(b2)
	if SaveSystem.has_save():
		var b3 := Button.new()
		b3.text = I18nService.t("ui.save.load")
		b3.pressed.connect(_load)
		row.add_child(b3)


func _bar(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _label(parent: Node, pos: Vector2, text: String) -> Label:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.add_theme_color_override("font_color", _Colors.TEXT_PRIMARY)
	parent.add_child(l)
	return l


func _style_cta_button(btn: Button) -> void:
	## Amber CTA for primary actions (加速 / 开始).
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(_Colors.ACCENT_AMBER.r, _Colors.ACCENT_AMBER.g, _Colors.ACCENT_AMBER.b, 0.92)
	normal.border_color = _Colors.ACCENT_AMBER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = _Colors.ACCENT_AMBER
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", _Colors.BG_DEEP)
	btn.add_theme_color_override("font_hover_color", _Colors.BG_DEEP)


func _show_new_game() -> void:
	_new_game_panel.visible = true
	GameClock.set_paused(true)


func _start_selected() -> void:
	var id := _selected_or_first()
	if id == "":
		return
	AppState.reset_new_game(id)
	_new_game_panel.visible = false
	globe.focus_airport(id)
	_refresh_top()
	_refresh_bags()


func _selected_or_first() -> String:
	if _airport_card.get_meta("aid", "") != "":
		return str(_airport_card.get_meta("aid"))
	if DataService.airports.size() > 0:
		return DataService.airports[0].airport_id
	return ""


func _on_game_started() -> void:
	_new_game_panel.visible = false
	_refresh_top()
	_refresh_bags()
	globe.focus_airport(AppState.current_airport_id)
	AudioService.set_bgm("bgm_globe_day")
	AudioService.play_sfx("sfx_ui_click")


func _on_random() -> void:
	var id := DataService.random_hub_id()
	EventBus.airport_selected.emit(id)
	globe.focus_airport(id)
	AudioService.play_sfx("sfx_ui_click")


func _refresh_airport_list(q: String) -> void:
	_airport_list.clear()
	for a in DataService.search_airports(q):
		_airport_list.add_item("%s  %s（%s）" % [a.iata, a.name_zh, a.city_zh])
		_airport_list.set_item_metadata(_airport_list.item_count - 1, a.airport_id)


func _on_list_airport(idx: int) -> void:
	var id: String = _airport_list.get_item_metadata(idx)
	EventBus.airport_selected.emit(id)
	globe.focus_airport(id)
	AudioService.play_sfx("sfx_airport_select")


func _on_airport_selected(airport_id: String) -> void:
	var a: Dictionary = DataService.get_airport(airport_id)
	if a.is_empty():
		return
	_airport_card.set_meta("aid", airport_id)
	var local := GameClock.format_local(str(a.timezone))
	var dests := DataService.destinations_from(str(a.iata)).size()
	_airport_card.text = "[b]%s[/b]\n%s / %s\n城市：%s（%s）\n国家：%s\n当地时间：%s\n海拔：%.0f ft\n直飞目的地：%d\n类型：%s\n可信：%s" % [
		a.name_zh, a.iata, a.icao, a.city_zh, a.city_en, a.country_zh, local,
		float(a.elevation_ft), dests, a.type, a.data_confidence
	]
	# Routes are drawn by GlobeController on selection; card only refreshes info.


func _on_toggle_routes() -> void:
	var shown: bool = globe.toggle_routes()
	_show_hint("航线已显示" if shown else "航线已隐藏")
	AudioService.play_sfx("sfx_ui_click")


func _refresh_clock() -> void:
	var a := AppState.current_airport()
	var local := ""
	if not a.is_empty():
		local = GameClock.format_local(str(a.timezone))
	_clock_label.text = "UTC %s | 当地 %s | %s" % [GameClock.now_iso(), local, "暂停" if GameClock.paused else "流逝中"]


func _refresh_top() -> void:
	_cash_label.text = "资金 " + _Economy.format_money(AppState.cash_usd)
	var a := AppState.current_airport()
	_airport_label.text = "当前位置 %s" % (a.get("iata", "-"))


func _refresh_bags() -> void:
	var used := AppState.inventory_weight_kg(false, true)
	var lim := AppState.personal_baggage_limit_kg()
	var cargo_u := AppState.inventory_weight_kg(true, false)
	_bag_label.text = "行李 %.1f/%.1fkg  货运 %.1f/%.0fkg" % [used, lim, cargo_u, AppState.cargo_kg_capacity]


func _refresh_countdown() -> void:
	var t: Dictionary = _Tickets.next_ticket()
	if t.is_empty():
		_countdown.text = ""
		_btn_ff.visible = false
		return
	var dep: float = GameClock.parse_iso_to_unix(str(t.get("scheduled_departure_utc", "")))
	var remain: float = max(0.0, dep - GameClock.unix_time)
	var hrs: int = int(remain / 3600.0)
	var mins: int = int(fmod(remain, 3600.0) / 60.0)
	if remain <= 0.0:
		_countdown.text = "下一班 %s %s→%s  登机中…" % [
			t.get("marketing_flight_number", ""), t.get("origin_iata", ""), t.get("destination_iata", "")
		]
		_countdown.add_theme_color_override("font_color", _Colors.WARN_RED)
		_btn_ff.visible = false
	else:
		_countdown.text = "下一班 %s %s→%s  倒计时 %dh%02dm  [%s]" % [
			t.get("marketing_flight_number", ""), t.get("origin_iata", ""), t.get("destination_iata", ""),
			hrs, mins, t.get("cabin", "")
		]
		_countdown.add_theme_color_override("font_color", _Colors.WARN_RED if hrs < 2 else _Colors.TEXT_PRIMARY)
		_btn_ff.visible = AppState.game_started


func _on_fast_forward() -> void:
	var t: Dictionary = _Tickets.next_ticket()
	if t.is_empty():
		_show_hint("没有已购航班")
		return
	var dep: float = GameClock.parse_iso_to_unix(str(t.get("scheduled_departure_utc", "")))
	var hours: float = max(0.0, (dep - GameClock.unix_time) / 3600.0)
	_ff_dialog.dialog_text = I18nService.t("ui.ff.confirm", {"hours": "%.1f" % hours})
	_ff_dialog.popup_centered()


func _do_fast_forward() -> void:
	var err: String = flight_ops.fast_forward_to_departure()
	if err != "":
		AudioService.play_sfx("sfx_error")
		_show_hint(err)
	else:
		AudioService.play_sfx("sfx_ff_confirm")
		_show_hint("已加速至起飞时刻。")


func _on_transition_started(ticket: Dictionary) -> void:
	_panel_host.visible = false
	_overlay.visible = true
	_transition_running = true
	_active_arrival_discount = {}
	AudioService.play_sfx("sfx_takeoff")
	_run_transition_sequence(ticket)
	globe.draw_trip_route(str(ticket.get("origin_airport_id", "")), str(ticket.get("destination_airport_id", "")))


func _run_transition_sequence(ticket: Dictionary) -> void:
	var base: String = "%s  %s → %s\n距离 %.0f km · %s舱\n" % [
		ticket.get("marketing_flight_number", ""), ticket.get("origin_iata", ""), ticket.get("destination_iata", ""),
		float(ticket.get("distance_km", 0)), ticket.get("cabin", "")
	]
	var phases: Array = [
		{"t": 0.0, "title": "强制登机 · 起飞", "bar": "■■■□□□□□□□", "sfx": ""},
		{"t": 1.6, "title": "巡航中", "bar": "□□■■■■■□□□", "sfx": "sfx_cruise"},
		{"t": 3.4, "title": "降落进近", "bar": "□□□□□□■■■■", "sfx": "sfx_landing"},
	]
	for ph in phases:
		if not _transition_running:
			return
		if str(ph.sfx) != "":
			AudioService.play_sfx(str(ph.sfx))
		_overlay_label.text = "%s\n%s\n%s\n（过场动画，飞行时间已计入世界时钟）" % [ph.title, base, ph.bar]
		var wait: float = 1.6 if ph.t < 3.0 else 1.6
		await get_tree().create_timer(wait).timeout


func _on_transition_finished() -> void:
	_transition_running = false
	_overlay.visible = false
	_overlay_label.text = ""
	AudioService.end_transition_duck()
	AudioService.play_sfx("sfx_arrive")


func _on_arrived() -> void:
	_refresh_top()
	_refresh_bags()
	globe.focus_airport(AppState.current_airport_id)
	var city_id := AppState.current_city_id()
	if city_id != "":
		_check_arrival_encounter(city_id)
		_check_free_cargo(city_id)


func _show_hint(text: String) -> void:
	_hint.text = text
	_last_hint_time = Time.get_ticks_msec() / 1000.0


func _get_market_products(_city_id: String) -> Array:
	var out: Array = []
	for p in DataService.world.get("products", []):
		out.append(str(p.get("product_id", "")))
	return out


func _check_arrival_encounter(city_id: String) -> void:
	var date_hour := int(GameClock.unix_time / 3600.0)
	var seed_val := PopupEvent.event_seed(city_id, date_hour, "", "arrival_discount")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	if rng.randf() > 0.20:
		return

	var market_products := _get_market_products(city_id)
	if market_products.size() == 0:
		return
	var product_idx := rng.randi() % market_products.size()
	var product_id := market_products[product_idx]
	var discount_pct := rng.randi_range(20, 40)

	var popup := load("res://scenes/PopupEvent.tscn").instantiate()
	popup.event_confirmed.connect(_on_arrival_discount_accepted.bind(product_id, discount_pct))
	popup.event_cancelled.connect(_on_arrival_discount_declined.bind())
	add_child(popup)
	popup.show_event("arrival_discount", {
		"product_name": product_id,
		"discount_pct": discount_pct,
		"product_id": product_id,
	})

	_active_arrival_discount = {
		"product_id": product_id,
		"discount_pct": discount_pct,
		"city_id": city_id,
	}


func _on_arrival_discount_accepted(result: Dictionary, product_id: String, discount_pct: int) -> void:
	AudioService.play_sfx("sfx_ui_click")
	_show_hint("已接受 %s 折扣！买入时自动应用 %d%% 优惠" % [product_id, discount_pct])


func _on_arrival_discount_declined(_result: Dictionary) -> void:
	AudioService.play_sfx("sfx_ui_click")
	_active_arrival_discount = {}


func _check_free_cargo(city_id: String) -> void:
	var date_hour := int(AppState.game_time_seconds / 3600.0)
	var seed_val := PopupEvent.event_seed(city_id, date_hour, "", "free_cargo")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	if rng.randf() > 0.10:
		return

	var popup := load("res://scenes/PopupEvent.tscn").instantiate()
	popup.event_confirmed.connect(_on_free_cargo_accepted.bind())
	popup.event_cancelled.connect(_on_free_cargo_declined.bind())
	add_child(popup)
	popup.show_event("free_cargo", {})


func _on_free_cargo_accepted(_result: Dictionary) -> void:
	AudioService.play_sfx("sfx_ui_click")
	_free_cargo_on_flight = true


func _on_free_cargo_declined(_result: Dictionary) -> void:
	AudioService.play_sfx("sfx_ui_click")
	_free_cargo_on_flight = false


func _clear_panel() -> void:
	for c in _panel_host.get_children():
		c.queue_free()
	_panel_host.visible = true


func _require_started() -> bool:
	if not AppState.game_started:
		_show_hint("请先选择机场开始游戏")
		return false
	return true


func _load_market_tags() -> void:
	_product_market_tags = DataService.world.get("product_market_tags", {})


func _get_ticket_dest_city_id() -> String:
	var ticket := _Tickets.next_ticket()
	if ticket.is_empty():
		return ""
	var dest_airport := DataService.get_airport(str(ticket.get("destination_airport_id", "")))
	return str(dest_airport.get("city_id", ""))


func _get_intelligence_tag(p: Dictionary, ticket_dest_city: String) -> String:
	var origin_city := str(p.get("origin_city_id", ""))
	var product_id := str(p.get("product_id", ""))
	var tag_key := "%s|%s" % [origin_city, product_id]
	var tags := _product_market_tags.get(tag_key, {})
	if ticket_dest_city != "":
		if ticket_dest_city in tags.get("hot", []):
			return "📍" + ticket_dest_city + "热卖"
		elif ticket_dest_city in tags.get("normal", []):
			return "📍" + ticket_dest_city + "可售"
		elif ticket_dest_city in tags.get("cold", []):
			return "⚠️不建议"
		return ""
	else:
		var hot_cities := tags.get("hot", [])
		if hot_cities.size() > 0:
			var city := DataService.get_city(hot_cities[0])
			var city_name := str(city.get("name_zh", hot_cities[0]))
			return "⭐最佳目的地：" + city_name
		return ""


func _show_city() -> void:
	if not _require_started():
		return
	_clear_panel()
	var c: Dictionary = DataService.get_city(AppState.current_city_id())
	_city_text = RichTextLabel.new()
	_city_text.bbcode_enabled = true
	_city_text.custom_minimum_size = Vector2(700, 440)
	_city_text.fit_content = false
	_city_text.scroll_active = true
	_panel_host.add_child(_city_text)
	if c.is_empty():
		_city_text.text = "无城市数据"
		return
	_city_text.text = "[b]%s[/b]\n\n%s\n\n[b]历史[/b]\n%s\n\n[b]地理[/b]\n%s\n\n[b]经济[/b]\n%s\n\n[b]饮食[/b]\n%s\n\n[b]旅行提示[/b]\n%s" % [
		c.name_zh, c.overview, c.history_summary, c.geography_summary, c.economy_summary, c.food_summary, c.travel_note
	]


func _show_market() -> void:
	if not _require_started():
		return
	_clear_panel()
	_selected_market_product_id = ""
	_market_row_panels.clear()
	_market_cache.clear()
	var v := VBoxContainer.new()
	_panel_host.add_child(v)
	var title := Label.new()
	title.text = "市场 — %s（超重可就地加购行李/货运）" % AppState.current_city_id()
	v.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_market_container = VBoxContainer.new()
	scroll.add_child(_market_container)
	var city := AppState.current_city_id()
	var ticket_dest_city := _get_ticket_dest_city_id()
	var locals := DataService.products_for_city(city)
	for p in locals:
		_add_market_row(city, p, true, ticket_dest_city)
	var count := 0
	for p in DataService.world.get("products", []):
		if p.origin_city_id == city:
			continue
		_add_market_row(city, p, false, ticket_dest_city)
		count += 1
		if count >= 25:
			break
	var qty_row := HBoxContainer.new()
	v.add_child(qty_row)
	var qty_label := Label.new()
	qty_label.text = "数量"
	qty_row.add_child(qty_label)
	_trade_qty = SpinBox.new()
	_trade_qty.min_value = 1
	_trade_qty.max_value = 9999
	_trade_qty.value = 1
	_trade_qty.rounded = true
	_trade_qty.custom_minimum_size = Vector2(100, 0)
	qty_row.add_child(_trade_qty)
	for n in [1, 10, 100]:
		var qb := Button.new()
		qb.text = str(n)
		var qn: int = n
		qb.pressed.connect(func (): _trade_qty.value = qn)
		qty_row.add_child(qb)
	var row := HBoxContainer.new()
	v.add_child(row)
	var b1 := Button.new()
	b1.text = "买入（行李）"
	b1.pressed.connect(func (): _buy_selected(false))
	row.add_child(b1)
	var b2 := Button.new()
	b2.text = "买入（货运）"
	b2.pressed.connect(func (): _buy_selected(true))
	row.add_child(b2)
	for pair in [["+10kg", "light"], ["+20kg", "standard"], ["+50kg", "heavy"]]:
		var bx := Button.new()
		var tier: String = pair[1]
		bx.text = "%s $%.0f" % [pair[0], _baggage_tier_price(tier)]
		bx.pressed.connect(func (): _show_hint(_Inventory.expand_baggage(tier)); _refresh_bags())
		row.add_child(bx)
	var bc := Button.new()
	bc.text = "+50kg货运 $%.0f" % _cargo_block_price()
	bc.pressed.connect(func (): _show_hint(_Inventory.expand_cargo(1)); _refresh_bags())
	row.add_child(bc)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func (): _panel_host.visible = false)
	row.add_child(close)


func _add_market_row(city: String, p: Dictionary, is_local: bool, ticket_dest_city: String = "") -> void:
	var buy: float = _Economy.buy_price(city, str(p.get("product_id", "")))
	var sell: float = _Economy.sell_price(city, str(p.get("product_id", "")), 1.0)
	var tag := "本地" if is_local else "外来"
	var intel := _get_intelligence_tag(p, ticket_dest_city)
	var product_id := str(p.get("product_id", ""))

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_market_container.add_child(panel)
	_market_row_panels[product_id] = panel

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(_on_market_row_input.bind(product_id))
	panel.add_child(row)

	var info_label := Label.new()
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := "[%s] %s  买%s  卖%s  %.2fkg" % [
		tag, p.get("name_zh", ""), _Economy.format_money(buy), _Economy.format_money(sell), float(p.get("weight_kg", 0))
	]
	info_label.text = line
	info_label.add_theme_font_size_override("font_size", 13)
	info_label.add_theme_color_override("font_color", _Colors.TEXT_PRIMARY)
	row.add_child(info_label)

	if intel != "":
		var intel_label := Label.new()
		intel_label.name = "IntelligenceLabel"
		intel_label.text = intel
		intel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		intel_label.add_theme_font_size_override("font_size", 13)
		intel_label.add_theme_color_override("font_color", _get_intel_color(intel))
		row.add_child(intel_label)

		var upgrade_btn := Button.new()
		upgrade_btn.text = "🔍"
		upgrade_btn.tooltip_text = "精准预测 ($200)"
		upgrade_btn.custom_minimum_size = Vector2(28, 28)
		upgrade_btn.pressed.connect(_on_upgrade_intel.bind(product_id, row))
		row.add_child(upgrade_btn)

	_market_cache.append(product_id)


func _on_market_row_input(event: InputEvent, product_id: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				_buy_market_item(product_id)
			else:
				_select_market_row(product_id)


func _select_market_row(product_id: String) -> void:
	if _selected_market_product_id != "" and _market_row_panels.has(_selected_market_product_id):
		var prev_panel: PanelContainer = _market_row_panels[_selected_market_product_id]
		prev_panel.remove_theme_stylebox_override("panel")

	_selected_market_product_id = product_id

	if _market_row_panels.has(product_id):
		var panel: PanelContainer = _market_row_panels[product_id]
		var style := StyleBoxFlat.new()
		style.bg_color = Color(_Colors.ACCENT_TEAL.r, _Colors.ACCENT_TEAL.g, _Colors.ACCENT_TEAL.b, 0.25)
		style.set_border_width_all(1)
		style.border_color = _Colors.ACCENT_TEAL
		style.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", style)


func _get_intel_color(intel: String) -> Color:
	if intel.begins_with("📍"):
		return _Colors.ACCENT_TEAL
	elif intel.begins_with("⚠"):
		return _Colors.WARN_RED
	elif intel.begins_with("⭐"):
		return _Colors.ACCENT_AMBER
	return _Colors.TEXT_SECONDARY


func _on_upgrade_intel(product_id: String, product_row: Node) -> void:
	if AppState.cash_usd < INTEL_UPGRADE_COST:
		_show_hint("资金不足")
		AudioService.play_sfx("sfx_error")
		return

	var ticket_dest_city := _get_ticket_dest_city_id()
	if ticket_dest_city == "":
		_show_hint("请先购买机票")
		AudioService.play_sfx("sfx_error")
		return

	AppState.cash_usd -= INTEL_UPGRADE_COST
	_refresh_top()

	var buy_price_val: float = DataService.market_row(AppState.current_city_id(), product_id).get("buy_base_usd", 0.0)
	var sell_price_est: float = EconomySystem.sell_price_estimate(product_id, ticket_dest_city)

	var daily_amp := 0.06
	var low := (sell_price_est * buy_price_val * (1.0 - daily_amp)) - (buy_price_val * 1.0)
	var high := (sell_price_est * buy_price_val * (1.0 + daily_amp)) - (buy_price_val * 1.0)

	var free_label: Label = product_row.find_child("IntelligenceLabel", true, false)
	if free_label:
		free_label.text = "预计毛利 $" + str(int(low)) + "–$" + str(int(high))
		free_label.add_theme_color_override("font_color", Color.CYAN)

	for child in product_row.get_children():
		if child is Button and child.text == "🔍":
			child.queue_free()
			break

	AudioService.play_sfx("sfx_ui_click")


func _buy_selected(as_cargo: bool) -> void:
	if _selected_market_product_id == "":
		return
	var qty: int = int(_trade_qty.value) if _trade_qty else 1
	var discount_factor := 1.0
	if (_active_arrival_discount.get("product_id", "") == _selected_market_product_id
			and _active_arrival_discount.get("city_id", "") == AppState.current_city_id()):
		discount_factor = 1.0 - float(_active_arrival_discount["discount_pct"]) / 100.0
	var err: String = _Inventory.buy(_selected_market_product_id, qty, as_cargo, discount_factor)
	if err != "":
		AudioService.play_sfx("sfx_error")
		_show_hint(err)
	else:
		AudioService.play_sfx("sfx_buy")
		_show_hint("购买成功")
	_active_arrival_discount = {}
	_refresh_bags()


func _buy_market_item(product_id: String) -> void:
	_select_market_row(product_id)
	_buy_selected(false)


func _show_flights() -> void:
	if not _require_started():
		return
	_clear_panel()
	_flight_auto_focus = true
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_host.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var tip := Label.new()
	tip.text = "当前机场出港 · 灰字=距起飞不足2小时"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tip)
	_flight_query = LineEdit.new()
	_flight_query.placeholder_text = "目的地 / IATA / 航空公司"
	_flight_query.text_changed.connect(func (_t): _flight_page = 0; _reload_flights())
	v.add_child(_flight_query)
	var filters := HBoxContainer.new()
	v.add_child(filters)
	var bun := Button.new()
	bun.text = "仅未访问"
	bun.toggle_mode = true
	bun.button_pressed = _filter_unvisited
	bun.toggled.connect(func (on): _filter_unvisited = on; _flight_page = 0; _reload_flights())
	filters.add_child(bun)
	var bbiz := Button.new()
	bbiz.text = "含公务舱"
	bbiz.toggle_mode = true
	bbiz.button_pressed = _biz_only
	bbiz.toggled.connect(func (on): _biz_only = on; _flight_page = 0; _reload_flights())
	filters.add_child(bbiz)
	for pair in [["起飞", "departure"], ["票价", "price"], ["时长", "duration"], ["距离", "distance"]]:
		var bs := Button.new()
		bs.text = "排序:" + pair[0]
		var key: String = pair[1]
		bs.pressed.connect(func (): _sort_by = key; _flight_page = 0; _reload_flights())
		filters.add_child(bs)
	var filters2 := HBoxContainer.new()
	v.add_child(filters2)
	var bp := Button.new()
	bp.text = "票价≤$800"
	bp.toggle_mode = true
	bp.toggled.connect(func (on): _max_price = 800.0 if on else 0.0; _flight_page = 0; _reload_flights())
	filters2.add_child(bp)
	var bd := Button.new()
	bd.text = "时长≤8h"
	bd.toggle_mode = true
	bd.toggled.connect(func (on): _max_duration = 480 if on else 0; _flight_page = 0; _reload_flights())
	filters2.add_child(bd)
	var bclear := Button.new()
	bclear.text = "清除筛选"
	bclear.pressed.connect(func ():
		_max_price = 0.0
		_max_duration = 0
		_biz_only = false
		_filter_unvisited = false
		_flight_page = 0
		_reload_flights()
	)
	filters2.add_child(bclear)
	_flight_list = ItemList.new()
	_flight_list.custom_minimum_size = Vector2(680, 150)
	_flight_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_flight_list.item_selected.connect(_on_flight_selected)
	v.add_child(_flight_list)
	var pager := HBoxContainer.new()
	v.add_child(pager)
	var prev := Button.new()
	prev.text = "上一页"
	prev.pressed.connect(func (): _flight_page = maxi(0, _flight_page - 1); _reload_flights())
	pager.add_child(prev)
	var nxt := Button.new()
	nxt.text = "下一页"
	nxt.pressed.connect(func (): _flight_page += 1; _reload_flights())
	pager.add_child(nxt)
	_flight_detail = RichTextLabel.new()
	_flight_detail.bbcode_enabled = true
	_flight_detail.fit_content = false
	_flight_detail.scroll_active = true
	_flight_detail.custom_minimum_size = Vector2(680, 80)
	_flight_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_flight_detail)
	var row := HBoxContainer.new()
	v.add_child(row)
	var be := Button.new()
	be.text = I18nService.t("ui.ticket.economy")
	be.pressed.connect(func (): _purchase("economy"))
	row.add_child(be)
	var bb := Button.new()
	bb.text = I18nService.t("ui.ticket.business")
	bb.pressed.connect(func (): _purchase("business"))
	row.add_child(bb)
	for pair in [["+10kg", "light"], ["+20kg", "standard"], ["+50kg", "heavy"]]:
		var bx := Button.new()
		var tier: String = pair[1]
		bx.text = "%s $%.0f" % [pair[0], _baggage_tier_price(tier)]
		bx.pressed.connect(func ():
			_extra_tier = tier
			_show_hint("已选择行李扩展 %s（+$%.0f）" % [pair[0], _baggage_tier_price(tier)])
		)
		row.add_child(bx)
	var bc := Button.new()
	bc.text = "货运+50 FREE" if _free_cargo_on_flight else "货运+50 $%.0f" % _cargo_block_price()
	bc.pressed.connect(func ():
		_cargo_blocks += 1
		_show_hint("货运档位 ×%d（每档50kg +$%.0f）" % [_cargo_blocks, _cargo_block_price()])
	)
	row.add_child(bc)
	var bcr := Button.new()
	bcr.text = "清零货运"
	bcr.pressed.connect(func (): _cargo_blocks = 0; _show_hint("已清零货运加购"))
	row.add_child(bcr)
	var br := Button.new()
	br.text = I18nService.t("ui.ticket.refund")
	br.pressed.connect(func (): _show_hint(_Tickets.refund_current()); _refresh_bags())
	row.add_child(br)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func (): _panel_host.visible = false)
	row.add_child(close)
	_extra_tier = ""
	_cargo_blocks = 0
	_flight_page = 0
	_reload_flights()


func _baggage_tier_price(tier: String) -> float:
	var extras: Dictionary = DataService.economy.get("baggage_extras", {})
	if extras.has(tier):
		return float(extras[tier].get("price_usd", 0))
	return 0.0


func _cargo_block_price() -> float:
	var extras: Dictionary = DataService.economy.get("baggage_extras", {})
	return float(extras.get("cargo_per_50kg_usd", 0))


func _reload_flights(_q: String = "") -> void:
	if _flight_list == null:
		return
	_flight_list.clear()
	var q: String = _flight_query.text if _flight_query else ""
	var all: Array = _FlightSearch.search(
		AppState.current_airport_id, q, 0, _filter_unvisited, _sort_by,
		_max_price, _max_duration, _biz_only
	)
	if _flight_auto_focus and all.size() > 0:
		var focus_idx: int = _FlightSearch.first_focus_index(all)
		_flight_page = focus_idx / FLIGHTS_PER_PAGE
		_flight_auto_focus = false
		var start_f: int = _flight_page * FLIGHTS_PER_PAGE
		_flights_cache = all.slice(start_f, mini(all.size(), start_f + FLIGHTS_PER_PAGE))
		_fill_flight_rows()
		var local_idx: int = focus_idx - start_f
		if local_idx >= 0 and local_idx < _flights_cache.size():
			_flight_list.select(local_idx)
			_flight_list.ensure_current_is_visible()
			_on_flight_selected(local_idx)
		_show_hint("航班 %d–%d / 共 %d（页 %d）· 已定位≥2小时后班次" % [
			start_f + 1, start_f + _flights_cache.size(), all.size(), _flight_page + 1
		])
		return
	var start: int = _flight_page * FLIGHTS_PER_PAGE
	if start >= all.size() and _flight_page > 0:
		_flight_page = maxi(0, (all.size() - 1) / FLIGHTS_PER_PAGE)
		start = _flight_page * FLIGHTS_PER_PAGE
	_flights_cache = all.slice(start, mini(all.size(), start + FLIGHTS_PER_PAGE))
	_fill_flight_rows()
	_show_hint("航班 %d–%d / 共 %d（页 %d）" % [
		start + (1 if all.size() > 0 else 0), start + _flights_cache.size(), all.size(), _flight_page + 1
	])


func _fill_flight_rows() -> void:
	var gray := Color(0.55, 0.55, 0.55)
	for i in _flights_cache.size():
		var fl: Dictionary = _flights_cache[i]
		_flight_list.add_item("%s  %s→%s  %s  $%.0f  %dmin" % [
			fl.marketing_flight_number, fl.origin_iata, fl.destination_iata,
			str(fl.scheduled_departure_utc).substr(0, 16),
			float(fl.ticket_base_price_economy),
			int(fl.duration_minutes)
		])
		if _FlightSearch.is_short_lead(fl):
			_flight_list.set_item_custom_fg_color(i, gray)


func _on_flight_selected(idx: int) -> void:
	if idx < 0 or idx >= _flights_cache.size():
		return
	_selected_flight = _flights_cache[idx]
	var fl: Dictionary = _selected_flight
	_flight_detail.text = "航班 %s（%s）\n%s → %s\n起飞 %s\n到达 %s\n距离 %.0f km · %d 分钟\n经济舱 $%.2f / 公务舱 $%.2f（10×）\n行李额：经济 %.0fkg / 公务 %.0fkg\n加购：行李档=%s  货运×%d" % [
		fl.get("marketing_flight_number", ""), fl.get("airline_name", ""), fl.get("origin_iata", ""), fl.get("destination_iata", ""),
		fl.get("scheduled_departure_utc", ""), fl.get("scheduled_arrival_utc", ""), float(fl.get("distance_km", 0)), int(fl.get("duration_minutes", 0)),
		float(fl.get("ticket_base_price_economy", 0)), float(fl.get("ticket_base_price_business", 0)),
		float(fl.get("baggage_allowance_economy", 20)), float(fl.get("baggage_allowance_business", 60)),
		_extra_tier if _extra_tier != "" else "无", _cargo_blocks
	]


func _purchase(cabin: String) -> void:
	if _selected_flight.is_empty():
		_show_hint("请先选择航班")
		return
	var err: String = _Tickets.purchase(_selected_flight, cabin, _extra_tier, _cargo_blocks, false)
	if err.find("已有机票") >= 0:
		_pending_cabin = cabin
		_replace_ticket_dialog.dialog_text = err + "\n将按 30% 手续费退旧票后购买新票，确认？"
		_replace_ticket_dialog.popup_centered()
		return
	_show_hint(err if err != "" else "购票成功")
	if err == "":
		AudioService.play_sfx("sfx_ticket_ok")
	else:
		AudioService.play_sfx("sfx_error")
	_refresh_bags()
	_refresh_countdown()
	if err == "" and _selected_flight.has("destination_airport_id"):
		globe.draw_trip_route(AppState.current_airport_id, str(_selected_flight.destination_airport_id))
	if err == "" and _free_cargo_on_flight and _cargo_blocks > 0:
		AppState.add_cash(_cargo_block_price())
		_free_cargo_on_flight = false
		_refresh_top()
		_show_hint("免费货运额度已使用！")
	if err == "":
		_check_free_cargo(AppState.current_city_id())


func _do_replace_purchase() -> void:
	var err: String = _Tickets.purchase(_selected_flight, _pending_cabin, _extra_tier, _cargo_blocks, true)
	_show_hint(err if err != "" else "已替换购票")
	_refresh_bags()
	_refresh_countdown()
	if err == "" and _selected_flight.has("destination_airport_id"):
		globe.draw_trip_route(AppState.current_airport_id, str(_selected_flight.destination_airport_id))
	if err == "" and _free_cargo_on_flight and _cargo_blocks > 0:
		AppState.add_cash(_cargo_block_price())
		_free_cargo_on_flight = false
		_refresh_top()
		_show_hint("免费货运额度已使用！")
	if err == "":
		_check_free_cargo(AppState.current_city_id())


func _show_inventory() -> void:
	if not _require_started():
		return
	_clear_panel()
	var v := VBoxContainer.new()
	_panel_host.add_child(v)
	_inv_list = ItemList.new()
	_inv_list.custom_minimum_size = Vector2(700, 360)
	v.add_child(_inv_list)
	for i in AppState.inventory.size():
		var item: Dictionary = AppState.inventory[i]
		var p: Dictionary = DataService.get_product(str(item.get("product_id", "")))
		var q: float = _Economy.current_quality(item)
		_inv_list.add_item("%s ×%d  品质%.0f%%  成本%s  %s" % [
			p.get("name_zh", item.get("product_id", "")), int(item.get("qty", 0)), q * 100.0,
			_Economy.format_money(float(item.get("unit_cost", 0))),
			"货运" if item.get("in_cargo", false) else "行李"
		])
	var qty_row := HBoxContainer.new()
	v.add_child(qty_row)
	var qty_label := Label.new()
	qty_label.text = "数量"
	qty_row.add_child(qty_label)
	_trade_qty = SpinBox.new()
	_trade_qty.min_value = 1
	_trade_qty.max_value = 9999
	_trade_qty.value = 1
	_trade_qty.rounded = true
	_trade_qty.custom_minimum_size = Vector2(100, 0)
	qty_row.add_child(_trade_qty)
	for n in [1, 10, 100]:
		var qb := Button.new()
		qb.text = str(n)
		var qn: int = n
		qb.pressed.connect(func (): _trade_qty.value = qn)
		qty_row.add_child(qb)
	var row := HBoxContainer.new()
	v.add_child(row)
	var sell := Button.new()
	sell.text = "出售"
	sell.pressed.connect(_sell_one)
	row.add_child(sell)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func (): _panel_host.visible = false)
	row.add_child(close)


func _sell_one() -> void:
	var idxs := _inv_list.get_selected_items()
	if idxs.is_empty():
		return
	var qty: int = int(_trade_qty.value) if _trade_qty else 1
	var result: Dictionary = _Inventory.sell(idxs[0], qty)
	AudioService.play_sfx("sfx_sell")
	_show_hint(str(result.get("msg", "")))
	_show_inventory()
	_refresh_bags()


func _show_notes() -> void:
	if not _require_started():
		return
	_clear_panel()
	AudioService.play_sfx("sfx_ui_click")
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_host.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	if AppState.sell_transactions.is_empty():
		var empty := Label.new()
		empty.text = "暂无交易记录"
		empty.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
		vbox.add_child(empty)
		return

	var by_city: Dictionary = {}
	for tx in AppState.sell_transactions:
		var city_id := str(tx.get("sell_city", ""))
		if city_id not in by_city:
			by_city[city_id] = []
		by_city[city_id].append(tx)

	for city_id in by_city:
		var city := DataService.get_city(city_id)
		var city_name := str(city.get("name_zh", city_id))

		var header := Label.new()
		header.text = "📒 %s" % city_name
		header.add_theme_font_size_override("font_size", 16)
		header.add_theme_color_override("font_color", _Colors.ICE)
		vbox.add_child(header)

		var total_margin: float = 0.0
		var wins: int = 0
		var losses: int = 0
		for tx in by_city[city_id]:
			var product_id := str(tx.get("product_id", ""))
			var p := DataService.get_product(product_id)
			var product_name := str(p.get("name_zh", product_id))
			var margin: float = float(tx.get("margin", 0.0))
			total_margin += margin
			var emoji := "✅" if margin >= 0 else "❌"
			if margin >= 0:
				wins += 1
			else:
				losses += 1
			var row := Label.new()
			row.text = "  %s %s：毛利 $%d" % [emoji, product_name, int(margin)]
			row.add_theme_color_override("font_color", _Colors.TEXT_PRIMARY)
			vbox.add_child(row)

		var sep := HSeparator.new()
		vbox.add_child(sep)

		var summary := Label.new()
		summary.text = "  %d赚 %d亏  净利 $%d" % [wins, losses, int(total_margin)]
		summary.add_theme_color_override("font_color", _Colors.ACCENT_TEAL if total_margin >= 0 else _Colors.WARN_RED)
		vbox.add_child(summary)


func _show_log() -> void:
	_clear_panel()
	_log_text = RichTextLabel.new()
	_log_text.custom_minimum_size = Vector2(700, 440)
	_log_text.bbcode_enabled = true
	_panel_host.add_child(_log_text)
	var s := "[b]旅行记录[/b]\n已访问机场 %d · 城市 %d · 国家 %d\n\n" % [
		AppState.visited_airports.size(), AppState.visited_cities.size(), AppState.visited_countries.size()
	]
	for e in AppState.travel_log:
		s += "%s %s→%s  %s  $%.0f\n" % [
			e.get("flight_number", ""), e.get("departure_airport", ""), e.get("arrival_airport", ""),
			e.get("airline", ""), float(e.get("ticket_price", 0))
		]
	_log_text.text = s


func _show_attr() -> void:
	_clear_panel()
	_attr_text = RichTextLabel.new()
	_attr_text.bbcode_enabled = true
	_attr_text.custom_minimum_size = Vector2(700, 440)
	_attr_text.scroll_active = true
	_panel_host.add_child(_attr_text)
	AudioService.play_sfx("sfx_ui_open_panel")
	var body := I18nService.attribution_body
	if body.is_empty():
		body = I18nService.disclaimer()
		for a in DataService.world.get("attributions", []):
			body += "\n• %s — %s\n  %s" % [a.get("name", ""), a.get("license", ""), a.get("note", "")]
	var meta: Dictionary = DataService.world.get("meta", {})
	_attr_text.text = "[b]%s[/b]\n\n%s\n\n基准日：%s\nETL：%s\n生成：%s\n" % [
		I18nService.t("ui.tab.attribution"),
		body,
		meta.get("baseline_date", ""),
		meta.get("etl_version", ""),
		meta.get("generated_at", ""),
	]


func _save() -> void:
	GameClock.set_paused(true)
	if SaveSystem.save_game():
		_show_hint("已保存")
	else:
		_show_hint("保存失败")
	GameClock.set_paused(false)


func _load() -> void:
	GameClock.set_paused(true)
	if SaveSystem.load_game():
		_show_hint("已读档")
		_new_game_panel.visible = false
		globe.focus_airport(AppState.current_airport_id)
		_refresh_top()
		_refresh_bags()
	else:
		_show_hint("无存档")
	GameClock.set_paused(not AppState.game_started)


func _toggle_pause() -> void:
	GameClock.set_paused(not GameClock.paused)
	_show_hint("时间暂停" if GameClock.paused else "时间继续")
