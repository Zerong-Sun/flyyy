extends Control
## Main HUD + panels. Builds UI in code for a self-contained Demo.

const _Economy = preload("res://scripts/systems/EconomySystem.gd")
const _Inventory = preload("res://scripts/systems/InventorySystem.gd")
const _Tickets = preload("res://scripts/systems/TicketService.gd")
const _MarketEvents = preload("res://scripts/systems/MarketEvents.gd")
const _FlightSearch = preload("res://scripts/systems/FlightSearch.gd")
const _Colors = preload("res://themes/DemoColors.gd")
const _ThemeFactory = preload("res://themes/ThemeFactory.gd")
const _IconFactory = preload("res://themes/IconFactory.gd")

const PANEL_CENTER_POS := Vector2(260, 150)
const PANEL_CENTER_SIZE := Vector2(720, 460)
const PANEL_WORK_POS := Vector2(90, 90)
const PANEL_WORK_SIZE := Vector2(1100, 530)

@onready var globe: Node3D = $"../Globe"
@onready var flight_ops: Node = $"../FlightOps"

var _clock_label: Label
var _cash_label: Label
var _bag_label: Label
var _airport_label: Label
var _rep_label: Label
var _disclaimer: Label
var _search: LineEdit
var _airport_list: ItemList
var _airport_card: RichTextLabel
var _hint: Label
var _hint_panel: PanelContainer
var _countdown: Label
var _btn_ff: Button
var _panel_host: Control
var _flight_list: ItemList
var _flight_tree: Tree
var _flight_query: LineEdit
var _dest_code_query: LineEdit
var _flight_detail: RichTextLabel
var _airport_card_panel: PanelContainer
var _bottom_nav: HBoxContainer
const INTEL_UPGRADE_COST := 200.0
var _market_tabs: TabContainer
var _market_buy_tree: Tree
var _market_sell_tree: Tree
var _market_search: LineEdit
var _market_buy_detail: RichTextLabel
var _market_sell_detail: RichTextLabel
var _market_buy_page_label: Label
var _market_buy_qty: SpinBox
var _market_sell_qty: SpinBox
# Legacy row state remains until the next UI cleanup; the new market uses Trees.
var _market_container: VBoxContainer
var _city_text: RichTextLabel
var _log_text: RichTextLabel
var _attr_text: RichTextLabel
var _overlay: ColorRect
var _overlay_label: Label
var _overlay_fx: Control
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
var _last_clock_s := 0.0
var _last_countdown_s := 0.0
var _market_built_city := ""
var _market_arrival_sell_pending := false
var _market_sell_index := -1
var _market_buy_page := 0
const MARKET_ROWS_PER_PAGE := 30
var _ff_dialog: ConfirmationDialog
var _replace_ticket_dialog: ConfirmationDialog
var _pending_cabin: String = ""
var _filter_unvisited: bool = false
var _sort_by: String = "departure"
var _flight_page: int = 0
var _max_price: float = 0.0
var _max_duration: int = 0
var _biz_only: bool = false
const FLIGHTS_PER_PAGE := 24
var _cash_rolling: bool = false
var _search_sfx_at: float = 0.0
var _transition_running: bool = false
var _transition_ticket: Dictionary = {}
var _flight_auto_focus: bool = false
var _active_arrival_discount: Dictionary = {}
var _pinned_market_product_id: String = ""
var _free_cargo_on_flight: bool = false
var _discovery_triggered_in_city: Dictionary = {}  # "city_id|product_id" -> true
var _show_connections: bool = false
var _connection_cache: Array = []
var _selected_connection: Dictionary = {}
var _ach_filter_category: String = "all"
var _ach_filter_unlocked_only: bool = false
var _recommend_box: VBoxContainer
var _selected_mode: String = "sandbox"  # "sandbox" | "challenge" | "collector"
var _mode_desc: Label
var _mode_buttons: Array = []  # [Button, mode_string, ...]
var _challenge_label: Label
var _load_button: Button = null
var _collector_panel = null  # CollectorPanel instance (loaded lazily)
var _result_panel = null  # ChallengeResultPanel instance (loaded lazily)
var _codex_panel = null  # CodexPanel instance (loaded lazily)
var _rep_panel = null  # ReputationPanel instance (loaded lazily)

# Five-tier sell feedback copy now lives in zh_CN.csv (REQ §5.5):
# sell_console_*, celebration_w*_*, sell_result_title_*.


func _ready() -> void:
	_build_ui()
	EventBus.airport_selected.connect(_on_airport_selected)
	EventBus.cash_changed.connect(_refresh_top)
	EventBus.inventory_changed.connect(_refresh_bags)
	EventBus.ticket_purchased.connect(_refresh_countdown)
	EventBus.arrived.connect(_on_arrived)
	EventBus.tutorial_hint.connect(_show_hint)
	EventBus.game_started.connect(_on_game_started)
	EventBus.challenge_ended.connect(_on_challenge_ended)
	EventBus.reputation_changed.connect(_on_reputation_changed)
	flight_ops.transition_started.connect(_on_transition_started)
	flight_ops.transition_finished.connect(_on_transition_finished)
	_load_market_tags()
	_show_new_game()
	_refresh_airport_list("")
	_disclaimer.text = I18nService.disclaimer()


func _process(_d: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	if t - _last_clock_s >= 0.25:
		_refresh_clock()
		_last_clock_s = t
	if t - _last_countdown_s >= 0.5:
		_refresh_countdown()
		_refresh_challenge_label()
		_last_countdown_s = t
	if _hint_panel.visible and t - _last_hint_time >= (12.0 if AppState.subtitles_enabled else 8.0):
		_hint_panel.visible = false
		_countdown.visible = _countdown.text != ""


func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _ThemeFactory.build(AppState.font_scale)

	var top := _bar(_Colors.BG_DEEP)
	top.set_anchors_preset(PRESET_TOP_WIDE)
	top.offset_bottom = 52
	top.clip_contents = true
	add_child(top)
	_clock_label = _label(top, Vector2(36, 8), "时间")
	_configure_top_label(_clock_label, Vector2(430, 36))
	_cash_label = _label(top, Vector2(544, 8), "资金")
	_configure_top_label(_cash_label, Vector2(220, 36))
	_bag_label = _label(top, Vector2(828, 8), "行李")
	_configure_top_label(_bag_label, Vector2(280, 36))
	_airport_label = _label(top, Vector2(1090, 8), "机场")
	_configure_top_label(_airport_label, Vector2(140, 36))
	_airport_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rep_label = _label(top, Vector2(1234, 8), "Lv1")
	_configure_top_label(_rep_label, Vector2(42, 36))
	_rep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_IconFactory.make("ic_clock", 22.0))
	top.get_child(top.get_child_count() - 1).position = Vector2(10, 14)
	top.add_child(_IconFactory.make("ic_money", 22.0))
	top.get_child(top.get_child_count() - 1).position = Vector2(518, 14)
	top.add_child(_IconFactory.make("ic_weight", 22.0))
	top.get_child(top.get_child_count() - 1).position = Vector2(802, 14)

	_countdown = _label(self, Vector2(350, 60), "")
	_countdown.size = Vector2(580, 42)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown.add_theme_font_size_override("font_size", 16)
	_countdown.add_theme_color_override("font_color", _Colors.WARN_RED)
	_challenge_label = _label(self, Vector2(350, 106), "")
	_challenge_label.size = Vector2(580, 28)
	_challenge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_label.add_theme_font_size_override("font_size", 14)
	_challenge_label.add_theme_color_override("font_color", _Colors.ACCENT_AMBER)
	_btn_ff = Button.new()
	_btn_ff.text = I18nService.t("ui.ff.button")
	_btn_ff.position = Vector2(940, 60)
	_btn_ff.visible = false
	_btn_ff.pressed.connect(_on_fast_forward)
	_style_cta_button(_btn_ff)
	_IconFactory.decorate_button(_btn_ff, "ic_fast_forward", 18.0)
	add_child(_btn_ff)

	_disclaimer = _label(self, Vector2(12, 690), I18nService.disclaimer())
	_disclaimer.add_theme_font_size_override("font_size", 12)
	_disclaimer.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	_disclaimer.modulate = Color(1, 1, 1, 0.7)

	_hint_panel = PanelContainer.new()
	_hint_panel.position = Vector2(270, 60)
	_hint_panel.size = Vector2(740, 54)
	_hint_panel.clip_contents = true
	_hint_panel.visible = false
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color(_Colors.BG_DEEP.r, _Colors.BG_DEEP.g, _Colors.BG_DEEP.b, 0.94)
	hint_style.border_color = Color(_Colors.ACCENT_AMBER.r, _Colors.ACCENT_AMBER.g, _Colors.ACCENT_AMBER.b, 0.55)
	hint_style.set_border_width_all(1)
	hint_style.set_corner_radius_all(7)
	hint_style.content_margin_left = 14
	hint_style.content_margin_right = 14
	hint_style.content_margin_top = 6
	hint_style.content_margin_bottom = 6
	_hint_panel.add_theme_stylebox_override("panel", hint_style)
	add_child(_hint_panel)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", _Colors.ACCENT_AMBER)
	_hint_panel.add_child(_hint)

	# Left search
	var left := PanelContainer.new()
	left.position = Vector2(8, 120)
	left.size = Vector2(250, 420)
	add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索机场 / IATA / ICAO / 城市"
	_search.text_changed.connect(_on_search_changed)
	lv.add_child(_search)
	_airport_list = ItemList.new()
	_airport_list.custom_minimum_size = Vector2(230, 300)
	_airport_list.item_selected.connect(_on_list_airport)
	lv.add_child(_airport_list)
	var btn_rand := Button.new()
	btn_rand.text = I18nService.t("ui.new_game.random")
	btn_rand.pressed.connect(_on_random)
	_IconFactory.decorate_button(btn_rand, "ic_random", 18.0)
	lv.add_child(btn_rand)
	var btn_routes := Button.new()
	btn_routes.text = "显示/隐藏航线"
	btn_routes.pressed.connect(_on_toggle_routes)
	lv.add_child(btn_routes)

	# Right airport card
	var right := PanelContainer.new()
	right.position = Vector2(1000, 120)
	right.size = Vector2(270, 360)
	right.add_theme_stylebox_override("panel", _ThemeFactory.card_style(false))
	add_child(right)
	_airport_card_panel = right
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
	_bottom_nav = bottom
	for pair in [
		[I18nService.t("ui.tab.city"), "_show_city", "ic_city"],
		[I18nService.t("ui.tab.market"), "_show_market", "ic_market"],
		[I18nService.t("ui.tab.flights"), "_show_flights", "ic_flight"],
		[I18nService.t("ui.tab.inventory"), "_show_inventory", "ic_inventory"],
		["笔记", "_show_notes", "ic_notes"],
		[I18nService.t("ui.codex.title"), "_show_codex", "ic_notes"],
		[I18nService.t("ui.tab.achievements"), "_show_achievements", "ic_log"],
		[I18nService.t("ui.tab.log"), "_show_log", "ic_log"],
		[I18nService.t("ui.tab.attribution"), "_show_attr", "ic_attr"],
		[I18nService.t("ui.save.manual"), "_save", "ic_save"],
		[I18nService.t("ui.save.load"), "_load", "ic_load"],
		[I18nService.t("ui.settings.title"), "_toggle_pause", "ic_settings"],
		[I18nService.t("ui.reputation.title"), "_show_reputation", "ic_log"],
	]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(Callable(self, pair[1]))
		b.pressed.connect(func (): AudioService.play_sfx("sfx_ui_click"))
		if str(pair[2]) != "":
			_IconFactory.decorate_button(b, str(pair[2]), 18.0)
		_wire_ui_sound(b)
		bottom.add_child(b)

	_panel_host = PanelContainer.new()
	_panel_host.position = PANEL_CENTER_POS
	_panel_host.size = PANEL_CENTER_SIZE
	_panel_host.clip_contents = true
	_panel_host.visible = false
	_panel_host.add_theme_stylebox_override("panel", _ThemeFactory.card_style(false))
	add_child(_panel_host)

	_overlay = ColorRect.new()
	_overlay.color = Color(_Colors.BG_DEEP.r, _Colors.BG_DEEP.g, _Colors.BG_DEEP.b, 0.82)
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	_overlay_fx = Control.new()
	_overlay_fx.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_overlay_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_overlay_fx)
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
	_new_game_panel.position = Vector2(360, 160)
	_new_game_panel.size = Vector2(560, 360)
	_new_game_panel.add_theme_stylebox_override("panel", _ThemeFactory.card_style(false))
	add_child(_new_game_panel)
	var ngv := VBoxContainer.new()
	_new_game_panel.add_child(ngv)
	var splash_tex: Texture2D = _IconFactory.get_brand("splash")
	if splash_tex != null:
		var splash := TextureRect.new()
		splash.texture = splash_tex
		splash.custom_minimum_size = Vector2(520, 120)
		splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		splash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ngv.add_child(splash)
	var brand_row := HBoxContainer.new()
	brand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ngv.add_child(brand_row)
	var logo_tex: Texture2D = _IconFactory.get_brand("logo")
	if logo_tex != null:
		var logo := TextureRect.new()
		logo.texture = logo_tex
		logo.custom_minimum_size = Vector2(56, 56)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		brand_row.add_child(logo)
	var word_tex: Texture2D = _IconFactory.get_brand("wordmark")
	if word_tex != null:
		var word := TextureRect.new()
		word.texture = word_tex
		word.custom_minimum_size = Vector2(280, 56)
		word.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		word.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		brand_row.add_child(word)
	else:
		var title := Label.new()
		title.text = "《环球航商》"
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", _Colors.ICE)
		brand_row.add_child(title)
	var subtitle := Label.new()
	subtitle.text = I18nService.t("ui.new_game.title")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	ngv.add_child(subtitle)
	var info := Label.new()
	info.text = "在左侧搜索或点选地球机场，然后开始。也可随机。\n" + I18nService.disclaimer()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	ngv.add_child(info)
	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 8)
	ngv.add_child(mode_row)
	for pair in [["sandbox", I18nService.t("ui.mode.sandbox")],
			["challenge", I18nService.t("ui.mode.challenge")],
			["collector", I18nService.t("ui.mode.collector")]]:
		var mb := Button.new()
		mb.text = str(pair[1])
		mb.toggle_mode = true
		var m: String = str(pair[0])
		mb.button_pressed = m == _selected_mode
		mb.pressed.connect(func (): _select_mode(m))
		_wire_ui_sound(mb)
		mode_row.add_child(mb)
		_mode_buttons.append([mb, m])
	_mode_desc = Label.new()
	_mode_desc.text = I18nService.t("ui.mode.sandbox.desc")
	_mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_desc.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	ngv.add_child(_mode_desc)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	ngv.add_child(row)
	var b1 := Button.new()
	b1.text = I18nService.t("ui.new_game.start")
	b1.pressed.connect(_start_selected)
	_style_cta_button(b1)
	_wire_ui_sound(b1)
	row.add_child(b1)
	var b2 := Button.new()
	b2.text = I18nService.t("ui.new_game.random")
	b2.pressed.connect(func (): _on_random(); _start_selected())
	_IconFactory.decorate_button(b2, "ic_random", 18.0)
	_wire_ui_sound(b2)
	row.add_child(b2)
	_load_button = Button.new()
	_load_button.text = I18nService.t("ui.save.load")
	_load_button.pressed.connect(_load)
	_IconFactory.decorate_button(_load_button, "ic_load", 18.0)
	_wire_ui_sound(_load_button)
	row.add_child(_load_button)
	_update_load_button()


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


func _configure_top_label(label: Label, label_size: Vector2) -> void:
	label.size = label_size
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", _ThemeFactory.scaled(14))


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


func _wire_ui_sound(btn: Button) -> void:
	btn.mouse_entered.connect(func (): AudioService.play_sfx("sfx_ui_hover"))


func _show_new_game() -> void:
	if _result_panel != null:
		_result_panel.visible = false
	if _collector_panel != null:
		_collector_panel.visible = false
	if _codex_panel != null:
		_codex_panel.visible = false
	if _rep_panel != null:
		_rep_panel.visible = false
	_new_game_panel.visible = true
	GameClock.set_paused(true)
	AudioService.set_bgm("bgm_menu")


func _select_mode(mode: String) -> void:
	_selected_mode = mode
	_update_load_button()
	for pair_v in _mode_buttons:
		var pair: Array = pair_v
		var b: Button = pair[0]
		b.button_pressed = str(pair[1]) == mode
	if _mode_desc != null:
		_mode_desc.text = I18nService.t("ui.mode." + mode + ".desc")
	AudioService.play_sfx("sfx_ui_click")


func _update_load_button() -> void:
	if _load_button != null:
		_load_button.visible = SaveSystem.has_save(_selected_mode)


func _refresh_challenge_label() -> void:
	if _challenge_label == null:
		return
	if AppState.game_mode == "challenge":
		var days := ChallengeSystem.remaining_days()
		_challenge_label.text = I18nService.t("ui.challenge.days_left", {"days": "%.1f" % days})
		_challenge_label.visible = true
	else:
		_challenge_label.text = ""
		_challenge_label.visible = false


func _on_challenge_ended(result: Dictionary) -> void:
	if _result_panel == null:
		_result_panel = load("res://scripts/ui/ChallengeResultPanel.gd").new()
		add_child(_result_panel)
		_result_panel.restart_requested.connect(_on_challenge_restart)
		_result_panel.menu_requested.connect(_show_new_game)
	_result_panel.show_result(result)
	AudioService.play_sfx("sfx_grand_slam")


func _on_challenge_restart() -> void:
	if _result_panel != null:
		_result_panel.visible = false
	AppState.reset_new_game(AppState.current_airport_id, "challenge")
	globe.focus_airport(AppState.current_airport_id)
	_refresh_top()
	_refresh_bags()


func _show_collector_progress() -> void:
	if _collector_panel == null:
		_collector_panel = load("res://scripts/ui/CollectorPanel.gd").new()
		add_child(_collector_panel)
	_collector_panel.refresh()


func _show_codex() -> void:
	if not _require_started():
		return
	_set_panel_bgm("menu")
	if _codex_panel == null:
		_codex_panel = load("res://scripts/ui/CodexPanel.gd").new()
		add_child(_codex_panel)
	_codex_panel.refresh()
	AudioService.play_sfx("sfx_ui_click")


func _show_reputation() -> void:
	if not _require_started():
		return
	_set_panel_bgm("menu")
	if _rep_panel == null:
		_rep_panel = load("res://scripts/ui/ReputationPanel.gd").new()
		add_child(_rep_panel)
	_rep_panel.refresh()
	AudioService.play_sfx("sfx_ui_click")


func _on_reputation_changed(_level: int) -> void:
	_refresh_top()


func _on_search_changed(q: String) -> void:
	_refresh_airport_list(q)
	if q.length() > 0:
		var now := Time.get_ticks_msec() * 0.001
		if now - _search_sfx_at >= 0.12:
			_search_sfx_at = now
			AudioService.play_sfx("sfx_search_type")


func _close_panel() -> void:
	_panel_host.visible = false
	_flight_auto_focus = false
	_selected_flight = {}
	_selected_connection = {}
	_pinned_market_product_id = ""
	_restore_panel_center()
	AudioService.play_sfx("sfx_ui_close_panel")
	_set_panel_bgm("globe")


func _unhandled_input(event: InputEvent) -> void:
	if _panel_host == null or not _panel_host.visible:
		return
	if _overlay == null or _overlay.visible:
		return
	if _ff_dialog != null and _ff_dialog.visible:
		return
	if _replace_ticket_dialog != null and _replace_ticket_dialog.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		# If a text field has focus, ESC first releases focus (so the user can
		# cancel an edit without losing the whole panel); a second ESC closes it.
		var focused := get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:
			focused.release_focus()
			get_viewport().set_input_as_handled()
			return
		_close_panel()
		get_viewport().set_input_as_handled()


func _start_selected() -> void:
	var id := _selected_or_first()
	if id == "":
		return
	AppState.reset_new_game(id, _selected_mode)
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
	_dismiss_open_panel()
	_refresh_airport_list("")
	_refresh_top()
	_refresh_bags()
	_refresh_countdown()
	globe.focus_airport(AppState.current_airport_id)
	_set_panel_bgm("globe")
	AudioService.play_sfx("sfx_ui_click")
	if AppState.game_mode == "challenge" and bool(AppState.challenge.get("ended", false)):
		_on_challenge_ended(AppState.challenge.get("result", {}))


func _dismiss_open_panel() -> void:
	for c in _panel_host.get_children():
		c.queue_free()
	_panel_host.visible = false
	_restore_panel_center()
	_market_built_city = ""
	_selected_market_product_id = ""
	_flight_list = null
	_flight_tree = null
	_market_tabs = null
	_market_buy_tree = null
	_market_sell_tree = null
	_market_search = null
	_market_buy_detail = null
	_market_sell_detail = null
	_market_buy_qty = null
	_market_sell_qty = null
	_flight_query = null
	_dest_code_query = null
	_flight_detail = null
	_recommend_box = null


func _restore_panel_center() -> void:
	_panel_host.position = PANEL_CENTER_POS
	_panel_host.size = PANEL_CENTER_SIZE
	_panel_host.add_theme_stylebox_override("panel", _ThemeFactory.card_style(false))
	if _bottom_nav:
		_bottom_nav.visible = true


func _dock_panel_work() -> void:
	_panel_host.position = PANEL_WORK_POS
	_panel_host.size = PANEL_WORK_SIZE
	_panel_host.add_theme_stylebox_override("panel", _ThemeFactory.card_style(false))
	if _bottom_nav:
		_bottom_nav.visible = false


func _on_random() -> void:
	var id := DataService.random_hub_id()
	EventBus.airport_selected.emit(id)
	globe.focus_airport(id)
	AudioService.play_sfx("sfx_ui_click")


func _refresh_airport_list(q: String) -> void:
	_airport_list.clear()
	for a in DataService.search_airports(q):
		var airport_name := DataService.place_name(a, "name")
		var city_name := DataService.place_name(a, "city")
		_airport_list.add_item("%s  %s（%s）" % [a.iata, airport_name, city_name])
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
	var airport_name := DataService.place_name(a, "name")
	var airport_city := DataService.place_name(a, "city")
	var airport_country := DataService.place_name(a, "country")
	_airport_card.text = "[b]%s[/b]\n%s / %s\n城市：%s（%s）\n国家：%s\n当地时间：%s\n海拔：%.0f ft\n直飞目的地：%d\n类型：%s\n可信：%s" % [
		airport_name, a.iata, a.icao, airport_city, a.city_en, airport_country, local,
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
	if _cash_rolling:
		return
	_cash_label.text = "资金 " + _Economy.format_money(AppState.cash_usd)
	var a := AppState.current_airport()
	_airport_label.text = "当前位置 %s" % (a.get("iata", "-"))
	if _rep_label != null:
		_rep_label.text = I18nService.t("ui.reputation.level", {"level": AppState.level})


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
		AppState.log_stat("fast_forwards", 1.0)
		AudioService.play_sfx("sfx_ff_confirm")
		_show_hint("已加速至起飞时刻。")
		AchievementSystem.check_all()


func _on_transition_started(ticket: Dictionary) -> void:
	# Reset any docked workbench (flights/market) so the panel is cleared and the
	# bottom nav is restored before the travel overlay covers the screen.
	_dismiss_open_panel()
	_overlay.visible = true
	_transition_running = true
	_transition_ticket = ticket
	_active_arrival_discount = {}
	AudioService.play_sfx("sfx_takeoff")
	globe.draw_trip_route(str(ticket.get("origin_airport_id", "")), str(ticket.get("destination_airport_id", "")))
	_run_transition_sequence(ticket)


func _run_transition_sequence(ticket: Dictionary) -> void:
	var dest := DataService.get_airport(str(ticket.get("destination_airport_id", "")))
	var dest_city := str(ticket.get("destination_iata", ""))
	if not dest.is_empty():
		var cid := str(dest.get("city_id", ""))
		if cid != "" and DataService.cities_by_id.has(cid):
			dest_city = DataService.place_name(DataService.cities_by_id[cid], "name")
		elif str(dest.get("city_name_zh", "")) != "":
			dest_city = str(dest.get("city_name_zh"))
	var base: String = "%s  %s → %s\n%s\n" % [
		ticket.get("marketing_flight_number", ""), ticket.get("origin_iata", ""), ticket.get("destination_iata", ""),
		I18nService.t("ui.transition.distance", {"km": "%.0f" % float(ticket.get("distance_km", 0)), "cabin": str(ticket.get("cabin", ""))})
	]
	var phases: Array = [
		{"t": 0.0, "title": I18nService.t("ui.transition.takeoff"), "bar": "■■■□□□□□□□", "sfx": "", "fx": "takeoff"},
		{"t": 1.6, "title": I18nService.t("ui.transition.cruise"), "bar": "□□■■■■■□□□", "sfx": "sfx_cruise", "fx": "cruise"},
		{"t": 3.4, "title": I18nService.t("ui.transition.landing", {"city": dest_city}), "bar": "□□□□□□■■■■", "sfx": "sfx_landing", "fx": "land"},
	]
	var origin := DataService.get_airport(str(ticket.get("origin_airport_id", "")))
	for i in phases.size():
		var ph: Dictionary = phases[i]
		if not _transition_running:
			return
		if str(ph.sfx) != "":
			AudioService.play_sfx(str(ph.sfx))
		_overlay_label.text = "%s\n%s\n%s\n%s" % [ph.title, base, ph.bar, I18nService.t("ui.transition.note")]
		if AppState.subtitles_enabled:
			_show_hint(ph.title)
		_play_transition_fx(str(ph.fx), dest_city)
		# Advance plane along great-circle during phases
		if globe and globe.has_method("set_plane_on_route") and not origin.is_empty() and not dest.is_empty():
			globe.set_plane_on_route(origin, dest, 0.15 + 0.35 * float(i))
		await get_tree().create_timer(1.6).timeout
	_clear_transition_fx()


func _play_transition_fx(phase: String, dest_city: String = "") -> void:
	_clear_transition_fx()
	var art: Texture2D = _IconFactory.get_transition_art(phase)
	if art != null:
		var bg := TextureRect.new()
		bg.texture = art
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.modulate = Color(1, 1, 1, 0.85)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay_fx.add_child(bg)
	if AppState.reduced_animations:
		# Reduced-motion: keep static art, skip all tween animations.
		if phase == "land" and dest_city != "":
			var city_lab := Label.new()
			city_lab.text = dest_city
			city_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			city_lab.position = Vector2(340, 200)
			city_lab.size = Vector2(600, 60)
			city_lab.add_theme_font_size_override("font_size", 36)
			city_lab.add_theme_color_override("font_color", _Colors.ACCENT_AMBER)
			_overlay_fx.add_child(city_lab)
		return
	match phase:
		"takeoff":
			# Rising runway-light bars from bottom
			for i in 8:
				var bar := ColorRect.new()
				bar.color = Color(_Colors.ACCENT_AMBER.r, _Colors.ACCENT_AMBER.g, _Colors.ACCENT_AMBER.b, 0.55)
				bar.size = Vector2(14, 48)
				bar.position = Vector2(520 + i * 28, 720)
				_overlay_fx.add_child(bar)
				var tw := create_tween()
				tw.tween_property(bar, "position:y", 280.0 - i * 18.0, 1.4).set_ease(Tween.EASE_OUT)
				tw.parallel().tween_property(bar, "modulate:a", 0.15, 1.4)
		"cruise":
			# Arc / route progress line left → right
			var arc := ColorRect.new()
			arc.color = Color(_Colors.ACCENT_TEAL.r, _Colors.ACCENT_TEAL.g, _Colors.ACCENT_TEAL.b, 0.7)
			arc.size = Vector2(8, 6)
			arc.position = Vector2(200, 360)
			_overlay_fx.add_child(arc)
			var trail := ColorRect.new()
			trail.color = Color(_Colors.ICE.r, _Colors.ICE.g, _Colors.ICE.b, 0.35)
			trail.size = Vector2(8, 4)
			trail.position = Vector2(200, 362)
			_overlay_fx.add_child(trail)
			var tw2 := create_tween()
			tw2.tween_property(arc, "position:x", 1000.0, 1.5).set_ease(Tween.EASE_IN_OUT)
			tw2.parallel().tween_property(arc, "position:y", 280.0, 0.75).set_ease(Tween.EASE_OUT)
			tw2.chain().tween_property(arc, "position:y", 360.0, 0.75).set_ease(Tween.EASE_IN)
			tw2.parallel().tween_property(trail, "size:x", 800.0, 1.5)
		"land":
			# Descending bars + destination name fade-in
			for i in 6:
				var bar2 := ColorRect.new()
				bar2.color = Color(_Colors.ICE.r, _Colors.ICE.g, _Colors.ICE.b, 0.5)
				bar2.size = Vector2(18, 36)
				bar2.position = Vector2(540 + i * 32, 80)
				_overlay_fx.add_child(bar2)
				var tw3 := create_tween()
				tw3.tween_property(bar2, "position:y", 520.0 + i * 10.0, 1.4).set_ease(Tween.EASE_IN)
			var city_lab := Label.new()
			city_lab.text = dest_city
			city_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			city_lab.position = Vector2(340, 200)
			city_lab.size = Vector2(600, 60)
			city_lab.add_theme_font_size_override("font_size", 36)
			city_lab.add_theme_color_override("font_color", _Colors.ACCENT_AMBER)
			city_lab.modulate.a = 0.0
			_overlay_fx.add_child(city_lab)
			var tw4 := create_tween()
			tw4.tween_property(city_lab, "modulate:a", 1.0, 0.8)


func _clear_transition_fx() -> void:
	if _overlay_fx == null:
		return
	for c in _overlay_fx.get_children():
		c.queue_free()


func _on_transition_finished() -> void:
	_transition_running = false
	_clear_transition_fx()
	_overlay.visible = false
	_overlay_label.text = ""
	if globe and globe.has_method("clear_plane_marker"):
		globe.clear_plane_marker()
	AudioService.end_transition_duck()
	AudioService.play_sfx("sfx_arrive")


func _on_arrived() -> void:
	_refresh_top()
	_refresh_bags()
	globe.focus_airport(AppState.current_airport_id)
	var city_id := AppState.current_city_id()
	if not AppState.held_tickets.is_empty():
		var next_t: Dictionary = _Tickets.next_ticket()
		_show_hint("转机中 → %s（约 90 分钟转机后继续）" % str(next_t.get("destination_iata", "")))
		_set_panel_bgm("globe")
		return
	if city_id != "":
		_discovery_triggered_in_city.clear()
		_check_arrival_encounter(city_id)
		_check_free_cargo(city_id)
		_market_arrival_sell_pending = not AppState.inventory.is_empty()
	AchievementSystem.check_all()
	_set_panel_bgm("globe")


func _show_hint(text: String) -> void:
	_hint.text = text
	_hint_panel.visible = text != ""
	_countdown.visible = false
	_last_hint_time = Time.get_ticks_msec() / 1000.0


func _get_market_products(city_id: String) -> Array:
	return DataService.market_product_ids(city_id)


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
	var product_id: String = market_products[product_idx]
	var product_name := str(DataService.get_product(product_id).get("name_zh", product_id))
	var discount_pct := rng.randi_range(20, 40)

	var popup: PopupEvent = load("res://scenes/PopupEvent.tscn").instantiate() as PopupEvent
	popup.event_confirmed.connect(_on_arrival_discount_accepted.bind(product_id, discount_pct))
	popup.event_cancelled.connect(_on_arrival_discount_declined.bind())
	add_child(popup)
	popup.show_event("arrival_discount", {
		"product_name": product_name,
		"discount_pct": discount_pct,
		"product_id": product_id,
	})

	_active_arrival_discount = {
		"product_id": product_id,
		"discount_pct": discount_pct,
		"city_id": city_id,
	}


func _on_arrival_discount_accepted(_result: Dictionary, product_id: String, discount_pct: int) -> void:
	AudioService.play_sfx("sfx_ui_click")
	_active_arrival_discount = {
		"product_id": product_id,
		"discount_pct": discount_pct,
		"city_id": AppState.current_city_id(),
	}
	_pinned_market_product_id = product_id
	if _market_buy_tree == null:
		_show_market()
	else:
		_refresh_market_buy()
	var qty_before := _inventory_qty(product_id)
	_buy_market_item(product_id)
	if _inventory_qty(product_id) <= qty_before:
		# 行李超重/受限时改走货运重试；仍失败则保留折扣并给出可读提示。
		_select_market_row(product_id)
		_buy_selected(true)
	if _inventory_qty(product_id) > qty_before:
		_show_hint("已以 %d%% 折扣买入 %s！采购页已置顶该商品，可继续追加购买" % [discount_pct, product_id])


func _on_arrival_discount_declined(_result: Dictionary) -> void:
	AudioService.play_sfx("sfx_ui_click")
	_active_arrival_discount = {}


func _check_free_cargo(city_id: String) -> void:
	var date_hour := int(GameClock.unix_time / 3600.0)
	var seed_val := PopupEvent.event_seed(city_id, date_hour, "", "free_cargo")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	if rng.randf() > 0.10:
		return

	var popup: PopupEvent = load("res://scenes/PopupEvent.tscn").instantiate() as PopupEvent
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
	_restore_panel_center()
	_market_built_city = ""
	_selected_market_product_id = ""
	_flight_tree = null
	_market_tabs = null
	_market_buy_tree = null
	_market_sell_tree = null
	_market_search = null
	_market_buy_detail = null
	_market_sell_detail = null
	_market_buy_qty = null
	_market_sell_qty = null
	_flight_list = null
	AudioService.play_sfx("sfx_ui_open_panel")


func _require_started() -> bool:
	if not AppState.game_started:
		_show_hint("请先选择机场开始游戏")
		return false
	return true


func _load_market_tags() -> void:
	_product_market_tags = DataService.product_market_tags


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
	var tags: Dictionary = _product_market_tags.get(tag_key, {})
	if ticket_dest_city != "":
		var city := DataService.get_city(ticket_dest_city)
		var city_name := DataService.place_name(city, "name")
		if ticket_dest_city in tags.get("hot", []):
			return "📍" + city_name + "热卖"
		elif ticket_dest_city in tags.get("normal", []):
			return "📍" + city_name + "可售"
		elif ticket_dest_city in tags.get("cold", []):
			return "⚠️不建议"
		return ""
	else:
		var hot_cities: Array = tags.get("hot", [])
		if hot_cities.size() > 0:
			# Best-destination intel is shown for this product only ~20% of the
			# time per day, seeded by save_id + product + game date so the same
			# save on the same day always shows the same hints (replayable).
			var gate_seed := hash("%s|%s|%s|%s" % [
				AppState.save_id, origin_city, product_id, GameClock.game_date_string()
			])
			var rng := RandomNumberGenerator.new()
			rng.seed = gate_seed if gate_seed != 0 else 1
			if rng.randf() > 0.20:
				return ""
			var city := DataService.get_city(hot_cities[0])
			var city_name := DataService.place_name(city, "name")
			return "⭐最佳目的地：" + city_name
		return ""


func _show_city() -> void:
	if not _require_started():
		return
	_set_panel_bgm("market")
	_clear_panel()
	var city_id := AppState.current_city_id()
	var c: Dictionary = DataService.get_city(city_id)
	var col := VBoxContainer.new()
	_panel_host.add_child(col)
	var hero_tex: Texture2D = _IconFactory.get_city_hero(city_id)
	if hero_tex != null:
		var hero := TextureRect.new()
		hero.texture = hero_tex
		hero.custom_minimum_size = Vector2(700, 200)
		hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(hero)
	_city_text = RichTextLabel.new()
	_city_text.bbcode_enabled = true
	_city_text.custom_minimum_size = Vector2(700, 280)
	_city_text.fit_content = false
	_city_text.scroll_active = true
	_city_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_city_text)
	if c.is_empty():
		_city_text.text = I18nService.t("ui.city.no_data")
		return
	var sec := {
		"history_summary": I18nService.t("ui.city.history"),
		"geography_summary": I18nService.t("ui.city.geography"),
		"economy_summary": I18nService.t("ui.city.economy"),
		"food_summary": I18nService.t("ui.city.food"),
		"travel_note": I18nService.t("ui.city.travel"),
	}
	var body := "[b]%s[/b]\n\n%s" % [
		DataService.place_name(c, "name"),
		DataService.city_content(c, "overview"),
	]
	for key in sec:
		var txt := DataService.city_content(c, key)
		if txt.strip_edges().is_empty():
			continue
		body += "\n\n[b]%s[/b]\n%s" % [sec[key], txt]
	_city_text.text = body
	# Low-content-confidence cities get an explicit disclaimer (content_confidence C).
	if str(c.get("content_confidence", "")) == "C":
		_city_text.text = "[color=#d9a441]%s[/color]\n\n%s" % [
			I18nService.t("ui.city.low_content"), _city_text.text
		]


func _show_market() -> void:
	if not _require_started():
		return
	_set_panel_bgm("market")
	var city := AppState.current_city_id()
	_clear_panel()
	_dock_panel_work()
	_selected_market_product_id = ""
	_market_cache.clear()
	_market_built_city = city
	_market_sell_index = -1
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	_panel_host.add_child(v)
	var city_data: Dictionary = DataService.get_city(city)
	var airport: Dictionary = AppState.current_airport()
	var title := Label.new()
	title.text = "市场 — %s · %s · 资金 %s · 行李 %.1f/%.1fkg · 货运 %.1f/%.1fkg" % [
		DataService.place_name(city_data, "name"),
		GameClock.format_local(str(airport.get("timezone", ""))).substr(0, 16),
		_Economy.format_money(AppState.cash_usd),
		AppState.inventory_weight_kg(false, true), AppState.personal_baggage_limit_kg(),
		AppState.inventory_weight_kg(true, false), AppState.cargo_kg_capacity,
	]
	title.add_theme_color_override("font_color", _Colors.ACCENT_AMBER)
	v.add_child(title)
	var evs := _MarketEvents.city_events(city)
	if not evs.is_empty():
		var ev_label := Label.new()
		var texts := PackedStringArray()
		for ev in evs:
			texts.append(I18nService.t(str((ev as Dictionary).get("label", ""))))
		ev_label.text = "📌 " + "；".join(texts)
		ev_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ev_label.add_theme_color_override("font_color", _Colors.ACCENT_AMBER)
		v.add_child(ev_label)
	var ticket_dest_city := _get_ticket_dest_city_id()
	if ticket_dest_city != "":
		var dest := DataService.get_city(ticket_dest_city)
		var ticket_chip := Label.new()
		ticket_chip.text = "当前机票目的地：%s（采购页按此估算利润）" % DataService.place_name(dest, "name")
		ticket_chip.add_theme_color_override("font_color", _Colors.ACCENT_TEAL)
		v.add_child(ticket_chip)
	_market_tabs = TabContainer.new()
	_market_tabs.name = "MarketTabs"
	_market_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_market_tabs)
	_build_market_buy_tab()
	_build_market_sell_tab()
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(_close_panel)
	v.add_child(close)
	var open_sell := _market_arrival_sell_pending and not AppState.inventory.is_empty()
	_market_arrival_sell_pending = false
	_market_tabs.current_tab = 1 if open_sell else 0
	_refresh_market_buy()
	_refresh_market_sell()


func _build_market_buy_tab() -> void:
	var page := HBoxContainer.new()
	page.name = "采购"
	page.add_theme_constant_override("separation", 10)
	_market_tabs.add_child(page)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(700, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(left)
	_market_search = LineEdit.new()
	_market_search.name = "MarketSearch"
	_market_search.placeholder_text = "搜索全部商品（空白时仅显示本地特产）"
	_market_search.text_changed.connect(func (_text): _market_buy_page = 0; _refresh_market_buy())
	left.add_child(_market_search)
	_market_buy_tree = _make_table(["商品", "来源", "重量", "采购价", "目的地估价 / 情报"], [210, 85, 70, 100, 190])
	_market_buy_tree.name = "MarketBuyTree"
	_market_buy_tree.item_selected.connect(_on_market_buy_tree_selected)
	left.add_child(_market_buy_tree)
	var pager := HBoxContainer.new()
	left.add_child(pager)
	var prev := Button.new()
	prev.text = "‹"
	prev.pressed.connect(func (): _market_buy_page = maxi(0, _market_buy_page - 1); _refresh_market_buy())
	pager.add_child(prev)
	_market_buy_page_label = Label.new()
	_market_buy_page_label.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	pager.add_child(_market_buy_page_label)
	var next := Button.new()
	next.text = "›"
	next.pressed.connect(func (): _market_buy_page += 1; _refresh_market_buy())
	pager.add_child(next)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(330, 0)
	page.add_child(right)
	_market_buy_detail = RichTextLabel.new()
	_market_buy_detail.bbcode_enabled = true
	_market_buy_detail.custom_minimum_size = Vector2(320, 220)
	_market_buy_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_market_buy_detail.text = "选择商品查看采购与目的地利润。"
	right.add_child(_market_buy_detail)
	_add_market_buy_actions(right)


func _build_market_sell_tab() -> void:
	var page := HBoxContainer.new()
	page.name = "出售"
	page.add_theme_constant_override("separation", 10)
	_market_tabs.add_child(page)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(700, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(left)
	var help := Label.new()
	help.text = "出售库存 · 品质和当地需求会影响最终售价"
	help.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	left.add_child(help)
	_market_sell_tree = _make_table(["商品", "数量", "品质", "存放", "成本", "当地售价", "预计毛利"], [170, 55, 60, 60, 85, 95, 100])
	_market_sell_tree.name = "MarketSellTree"
	_market_sell_tree.item_selected.connect(_on_market_sell_tree_selected)
	left.add_child(_market_sell_tree)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(330, 0)
	page.add_child(right)
	_market_sell_detail = RichTextLabel.new()
	_market_sell_detail.bbcode_enabled = true
	_market_sell_detail.custom_minimum_size = Vector2(320, 220)
	_market_sell_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_market_sell_detail.text = "选择库存商品查看出售结果。"
	right.add_child(_market_sell_detail)
	_add_market_sell_actions(right)


func _make_table(headers: Array, widths: Array) -> Tree:
	var tree := Tree.new()
	tree.columns = headers.size()
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.custom_minimum_size = Vector2(0, 340)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for i in headers.size():
		tree.set_column_title(i, str(headers[i]))
		tree.set_column_custom_minimum_width(i, int(widths[i]))
		tree.set_column_expand(i, i == 0 or i == headers.size() - 1)
	return tree


func _add_market_buy_actions(parent: VBoxContainer) -> void:
	var qty_row := HBoxContainer.new()
	parent.add_child(qty_row)
	var qty_label := Label.new()
	qty_label.text = "数量"
	qty_row.add_child(qty_label)
	_market_buy_qty = SpinBox.new()
	_market_buy_qty.min_value = 1
	_market_buy_qty.max_value = 9999
	_market_buy_qty.value = 1
	_market_buy_qty.rounded = true
	_market_buy_qty.custom_minimum_size = Vector2(88, 0)
	qty_row.add_child(_market_buy_qty)
	for n in [1, 10, 100]:
		var quick := Button.new()
		quick.text = str(n)
		var quick_n: int = n
		quick.pressed.connect(func (): _market_buy_qty.value = quick_n)
		qty_row.add_child(quick)
	var actions := HBoxContainer.new()
	parent.add_child(actions)
	var buy_bag := Button.new()
	buy_bag.text = "买入（行李）"
	buy_bag.pressed.connect(func (): _buy_selected(false))
	actions.add_child(buy_bag)
	var buy_cargo := Button.new()
	buy_cargo.text = "买入（货运）"
	buy_cargo.pressed.connect(func (): _buy_selected(true))
	actions.add_child(buy_cargo)
	var capacity := HBoxContainer.new()
	parent.add_child(capacity)
	for pair in [["+10kg", "light"], ["+20kg", "standard"], ["+50kg", "heavy"]]:
		var extend := Button.new()
		var tier: String = pair[1]
		extend.text = "%s $%.0f" % [pair[0], _baggage_tier_price(tier)]
		extend.pressed.connect(func (): _show_hint(_Inventory.expand_baggage(tier)); _refresh_bags())
		capacity.add_child(extend)
	var cargo := Button.new()
	cargo.text = "+50kg货运 $%.0f" % _cargo_block_price()
	cargo.pressed.connect(func (): _show_hint(_Inventory.expand_cargo(1)); _refresh_bags())
	capacity.add_child(cargo)


func _add_market_sell_actions(parent: VBoxContainer) -> void:
	var qty_row := HBoxContainer.new()
	parent.add_child(qty_row)
	var qty_label := Label.new()
	qty_label.text = "出售数量"
	qty_row.add_child(qty_label)
	_market_sell_qty = SpinBox.new()
	_market_sell_qty.min_value = 1
	_market_sell_qty.max_value = 9999
	_market_sell_qty.value = 1
	_market_sell_qty.rounded = true
	_market_sell_qty.custom_minimum_size = Vector2(88, 0)
	qty_row.add_child(_market_sell_qty)
	for n in [1, 10, 100]:
		var quick := Button.new()
		quick.text = str(n)
		var quick_n: int = n
		quick.pressed.connect(func (): _market_sell_qty.value = quick_n)
		qty_row.add_child(quick)
	var sell := Button.new()
	sell.text = "出售选中商品"
	sell.pressed.connect(_sell_selected_market)
	_style_cta_button(sell)
	parent.add_child(sell)


func _refresh_market_buy() -> void:
	if _market_buy_tree == null:
		return
	_market_buy_tree.clear()
	_market_cache.clear()
	_selected_market_product_id = ""
	var city := AppState.current_city_id()
	var query := _market_search.text.strip_edges().to_lower() if _market_search else ""
	var pinned := _pinned_market_product_id
	var product_ids: Array = []
	if query == "":
		for p_v in DataService.products_for_city(city):
			product_ids.append(str((p_v as Dictionary).get("product_id", "")))
		# 热卖折扣商品即使非本地也出现在空白搜索列表（置顶）。
		if pinned != "" and not product_ids.has(pinned):
			var p := DataService.get_product(pinned)
			if not p.is_empty() and DataService.market_product_ids(city).has(pinned):
				product_ids.insert(0, pinned)
	else:
		for product_id_v in DataService.market_product_ids(city):
			var product_id := str(product_id_v)
			var p := DataService.get_product(product_id)
			var origin := DataService.get_city(str(p.get("origin_city_id", "")))
			var haystack := "%s %s %s %s" % [p.get("name_zh", ""), p.get("name_en", ""), p.get("category", ""), DataService.place_name(origin, "name")]
			if haystack.to_lower().find(query) >= 0:
				product_ids.append(product_id)
	if pinned != "":
		var pin_idx := product_ids.find(pinned)
		if pin_idx > 0:
			product_ids.remove_at(pin_idx)
			product_ids.insert(0, pinned)
	var total := product_ids.size()
	var start := _market_buy_page * MARKET_ROWS_PER_PAGE
	if start >= total and _market_buy_page > 0:
		_market_buy_page = maxi(0, int((total - 1) / float(MARKET_ROWS_PER_PAGE)))
		start = _market_buy_page * MARKET_ROWS_PER_PAGE
	var end := mini(total, start + MARKET_ROWS_PER_PAGE)
	var root := _market_buy_tree.create_item()
	var ticket_dest_city := _get_ticket_dest_city_id()
	for i in range(start, end):
		var product_id := str(product_ids[i])
		var p := DataService.get_product(product_id)
		var item := _market_buy_tree.create_item(root)
		var is_local := str(p.get("origin_city_id", "")) == city
		var origin := DataService.get_city(str(p.get("origin_city_id", "")))
		item.set_text(0, str(p.get("name_zh", product_id)))
		item.set_text(1, "本地" if is_local else DataService.place_name(origin, "name"))
		item.set_text(2, "%.2fkg" % float(p.get("weight_kg", 0)))
		item.set_text(3, _Economy.format_money(_Economy.buy_price(city, product_id)))
		item.set_text(4, _market_buy_outlook(p, city, ticket_dest_city))
		item.set_metadata(0, product_id)
		if is_local:
			item.set_custom_color(1, _Colors.ACCENT_AMBER)
		_market_cache.append(product_id)
	if _market_buy_page_label:
		_market_buy_page_label.text = " %d–%d / %d（第 %d 页）" % [start + (1 if total > 0 else 0), end, total, _market_buy_page + 1]


func _market_buy_outlook(p: Dictionary, city: String, ticket_dest_city: String) -> String:
	var product_id := str(p.get("product_id", ""))
	var buy := _Economy.buy_price(city, product_id)
	if ticket_dest_city != "":
		var estimate := _Economy.sell_price_estimate(product_id, ticket_dest_city)
		var margin := estimate - buy
		return "%s · %s$%.0f" % [_Economy.format_money(estimate), "+" if margin >= 0 else "-", absf(margin)]
	return _get_intelligence_tag(p, "")


func _on_market_buy_tree_selected() -> void:
	var item := _market_buy_tree.get_selected()
	if item == null:
		return
	_selected_market_product_id = str(item.get_metadata(0))
	var product := DataService.get_product(_selected_market_product_id)
	var city := AppState.current_city_id()
	var outlook := _market_buy_outlook(product, city, _get_ticket_dest_city_id())
	_market_buy_detail.text = "[b]%s[/b]\n%s\n\n重量：%.2fkg\n当前采购价：%s\n%s" % [
		product.get("name_zh", _selected_market_product_id),
		str(product.get("description", product.get("short_description", ""))),
		float(product.get("weight_kg", 0)),
		_Economy.format_money(_Economy.buy_price(city, _selected_market_product_id)),
		outlook if outlook != "" else "请选择航班查看目的地估价",
	]


func _refresh_market_sell() -> void:
	if _market_sell_tree == null:
		return
	_market_sell_tree.clear()
	_market_sell_index = -1
	var root := _market_sell_tree.create_item()
	var city := AppState.current_city_id()
	for i in AppState.inventory.size():
		var stack: Dictionary = AppState.inventory[i]
		var product_id := str(stack.get("product_id", ""))
		var product := DataService.get_product(product_id)
		var quality := _Economy.current_quality(stack)
		var cost := float(stack.get("unit_cost", 0))
		var sell := _Economy.sell_price(city, product_id, quality)
		var item := _market_sell_tree.create_item(root)
		item.set_text(0, str(product.get("name_zh", product_id)))
		item.set_text(1, "×%d" % int(stack.get("qty", 0)))
		item.set_text(2, "%.0f%%" % (quality * 100.0))
		item.set_text(3, "货运" if bool(stack.get("in_cargo", false)) else "行李")
		item.set_text(4, _Economy.format_money(cost))
		item.set_text(5, _Economy.format_money(sell))
		item.set_text(6, "%s$%.0f" % ["+" if sell >= cost else "-", absf(sell - cost)])
		item.set_metadata(0, i)
		item.set_custom_color(6, Color(0.45, 0.85, 0.55) if sell >= cost else _Colors.WARN_RED)
	if AppState.inventory.is_empty() and _market_sell_detail:
		_market_sell_detail.text = "库存为空。前往采购页购买当地特产。"


func _on_market_sell_tree_selected() -> void:
	var item := _market_sell_tree.get_selected()
	if item == null:
		return
	_market_sell_index = int(item.get_metadata(0))
	if _market_sell_index < 0 or _market_sell_index >= AppState.inventory.size():
		return
	var stack: Dictionary = AppState.inventory[_market_sell_index]
	var product_id := str(stack.get("product_id", ""))
	var product := DataService.get_product(product_id)
	var quality := _Economy.current_quality(stack)
	var cost := float(stack.get("unit_cost", 0))
	var sell := _Economy.sell_price(AppState.current_city_id(), product_id, quality)
	_market_sell_detail.text = "[b]%s[/b]\n\n数量：%d\n品质：%.0f%%\n存放：%s\n成本：%s / 件\n当地售价：%s / 件\n预计毛利：%s$%.0f / 件" % [
		product.get("name_zh", product_id), int(stack.get("qty", 0)), quality * 100.0,
		"货运" if bool(stack.get("in_cargo", false)) else "行李",
		_Economy.format_money(cost), _Economy.format_money(sell),
		"+" if sell >= cost else "-", absf(sell - cost),
	]
	_market_sell_qty.max_value = int(stack.get("qty", 0))
	_market_sell_qty.value = mini(_market_sell_qty.value, _market_sell_qty.max_value)


func _sell_selected_market() -> void:
	if _market_sell_index < 0 or _market_sell_index >= AppState.inventory.size():
		_show_hint("请先选择要出售的库存商品")
		return
	var stack: Dictionary = AppState.inventory[_market_sell_index]
	var qty := int(_market_sell_qty.value) if _market_sell_qty else 1
	_check_accidental_premium(str(stack.get("product_id", "")), _market_sell_index, qty)


## Legacy market-row helpers remain for compatibility with old saves and tooling.
func _update_market_rows(city: String) -> void:
	var ticket_dest_city := _get_ticket_dest_city_id()
	for product_id in _market_cache:
		var panel: PanelContainer = _market_row_panels.get(product_id)
		if panel == null:
			continue
		var p: Dictionary = DataService.get_product(product_id)
		if p.is_empty():
			continue
		var is_local: bool = str(p.get("origin_city_id", "")) == city
		var buy: float = _Economy.buy_price(city, product_id)
		var sell: float = _Economy.sell_price(city, product_id, 1.0)
		var row: HBoxContainer = panel.get_child(0)
		_apply_market_row_values(row, p, is_local, buy, sell)
		var intel := _get_intelligence_tag(p, ticket_dest_city)
		var intel_label: Label = row.get_node_or_null("IntelligenceLabel") as Label
		if intel_label != null:
			intel_label.text = intel
			if intel != "":
				intel_label.add_theme_color_override("font_color", _get_intel_color(intel))


func _apply_market_row_values(row: HBoxContainer, p: Dictionary, is_local: bool, buy: float, sell: float) -> void:
	var name_label: Label = row.get_node_or_null("NameLabel") as Label
	if name_label != null:
		name_label.text = str(p.get("name_zh", ""))
	var weight_label: Label = row.get_node_or_null("WeightLabel") as Label
	if weight_label != null:
		weight_label.text = "%.2fkg" % float(p.get("weight_kg", 0))
	var tag_label: Label = row.get_node_or_null("TagLabel") as Label
	if tag_label != null:
		tag_label.text = "本地" if is_local else "外来"
		tag_label.add_theme_color_override(
			"font_color", _Colors.ACCENT_AMBER if is_local else _Colors.TEXT_SECONDARY
		)
	var buy_label: Label = row.get_node_or_null("BuyPriceLabel") as Label
	if buy_label != null:
		buy_label.text = "买 %s" % _Economy.format_money(buy)
	var sell_label: Label = row.get_node_or_null("SellPriceLabel") as Label
	if sell_label != null:
		sell_label.text = "卖 %s" % _Economy.format_money(sell)
		sell_label.add_theme_color_override(
			"font_color", _Colors.WARN_RED if sell < buy else _Colors.ACCENT_TEAL
		)
	var margin_label: Label = row.get_node_or_null("MarginLabel") as Label
	if margin_label != null:
		var margin := sell - buy
		var sign := "+" if margin >= 0 else "-"
		margin_label.text = "%s$%.0f" % [sign, absf(margin)]
		margin_label.add_theme_color_override(
			"font_color",
			Color(0.45, 0.85, 0.55) if margin >= 0 else _Colors.WARN_RED
		)


func _add_market_row(city: String, p: Dictionary, is_local: bool, ticket_dest_city: String = "") -> void:
	var buy: float = _Economy.buy_price(city, str(p.get("product_id", "")))
	var sell: float = _Economy.sell_price(city, str(p.get("product_id", "")), 1.0)
	var intel := _get_intelligence_tag(p, ticket_dest_city)
	var product_id := str(p.get("product_id", ""))

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(_Colors.BG_DEEP.r, _Colors.BG_DEEP.g, _Colors.BG_DEEP.b, 0.35)
	row_style.set_corner_radius_all(6)
	row_style.content_margin_left = 6
	row_style.content_margin_right = 6
	row_style.content_margin_top = 3
	row_style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", row_style)
	_market_container.add_child(panel)
	_market_row_panels[product_id] = panel

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(_on_market_row_input.bind(product_id))
	panel.add_child(row)

	var icon_tex: Texture2D = _IconFactory.get_product_icon(product_id)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", _Colors.TEXT_PRIMARY)
	row.add_child(name_label)

	var weight_label := Label.new()
	weight_label.name = "WeightLabel"
	weight_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weight_label.custom_minimum_size = Vector2(64, 0)
	weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weight_label.add_theme_font_size_override("font_size", 12)
	weight_label.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	row.add_child(weight_label)

	var tag_label := Label.new()
	tag_label.name = "TagLabel"
	tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_label.custom_minimum_size = Vector2(52, 0)
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_label.add_theme_font_size_override("font_size", 12)
	row.add_child(tag_label)

	var buy_label := Label.new()
	buy_label.name = "BuyPriceLabel"
	buy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buy_label.custom_minimum_size = Vector2(92, 0)
	buy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	buy_label.add_theme_font_size_override("font_size", 12)
	buy_label.add_theme_color_override("font_color", _Colors.ECONOMY)
	row.add_child(buy_label)

	var sell_label := Label.new()
	sell_label.name = "SellPriceLabel"
	sell_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sell_label.custom_minimum_size = Vector2(92, 0)
	sell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sell_label.add_theme_font_size_override("font_size", 12)
	row.add_child(sell_label)

	var margin_label := Label.new()
	margin_label.name = "MarginLabel"
	margin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin_label.custom_minimum_size = Vector2(84, 0)
	margin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	margin_label.add_theme_font_size_override("font_size", 12)
	row.add_child(margin_label)

	_apply_market_row_values(row, p, is_local, buy, sell)

	var inherited := str(p.get("inherited_from", ""))
	if inherited != "":
		var inh := Label.new()
		inh.name = "InheritedLabel"
		if inherited.find("region") >= 0:
			inh.text = I18nService.t("ui.product.inherited_region")
			if inh.text == "" or inh.text.begins_with("ui."):
				inh.text = "区域特产"
		else:
			inh.text = I18nService.t("ui.product.inherited_country")
			if inh.text == "" or inh.text.begins_with("ui."):
				inh.text = "国家标准品"
		inh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inh.add_theme_font_size_override("font_size", 11)
		inh.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
		row.add_child(inh)

	if intel != "":
		var tag_icon_id := _intel_icon_id(intel)
		if tag_icon_id != "":
			var tag_tex: Texture2D = _IconFactory.get_ui_icon(tag_icon_id)
			if tag_tex != null:
				var tag_icon := TextureRect.new()
				tag_icon.name = "IntelTagIcon"
				tag_icon.texture = tag_tex
				tag_icon.custom_minimum_size = Vector2(18, 18)
				tag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(tag_icon)
		var intel_label := Label.new()
		intel_label.name = "IntelligenceLabel"
		intel_label.text = intel
		intel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		intel_label.add_theme_font_size_override("font_size", 13)
		intel_label.add_theme_color_override("font_color", _get_intel_color(intel))
		row.add_child(intel_label)

		var upgrade_btn := Button.new()
		upgrade_btn.name = "IntelUpgradeBtn"
		upgrade_btn.text = ""
		upgrade_btn.tooltip_text = "精准预测 ($%.0f)" % _intel_upgrade_cost()
		upgrade_btn.custom_minimum_size = Vector2(28, 28)
		_IconFactory.decorate_button(upgrade_btn, "ic_intel", 18.0)
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
		panel.add_theme_stylebox_override("panel", _ThemeFactory.selected_row_style())


func _clear_market_selection() -> void:
	if _selected_market_product_id != "" and _market_row_panels.has(_selected_market_product_id):
		var prev_panel: PanelContainer = _market_row_panels[_selected_market_product_id]
		prev_panel.remove_theme_stylebox_override("panel")
	_selected_market_product_id = ""


func _get_intel_color(intel: String) -> Color:
	if intel.begins_with("📍"):
		return _Colors.ACCENT_TEAL
	elif intel.begins_with("⚠"):
		return _Colors.WARN_RED
	elif intel.begins_with("⭐"):
		return _Colors.ACCENT_AMBER
	return _Colors.TEXT_SECONDARY


func _intel_icon_id(intel: String) -> String:
	if intel.begins_with("⚠") or intel.find("不建议") >= 0:
		return "ic_cold"
	if intel.begins_with("📍") or intel.begins_with("⭐") or intel.find("热卖") >= 0:
		return "ic_hot"
	return ""


func _intel_upgrade_cost() -> float:
	var cost := INTEL_UPGRADE_COST
	if ReputationSystem.has_unlock(ReputationSystem.UNLOCK_LV4):
		cost *= 0.7
	return cost


func _on_upgrade_intel(product_id: String, product_row: Node) -> void:
	var cost := _intel_upgrade_cost()
	if AppState.cash_usd < cost:
		_show_hint("资金不足")
		AudioService.play_sfx("sfx_error")
		return

	var ticket_dest_city := _get_ticket_dest_city_id()
	if ticket_dest_city == "":
		_show_hint("请先购买机票")
		AudioService.play_sfx("sfx_error")
		return

	AppState.cash_usd -= cost
	AppState.log_stat("intel_purchases", 1.0)
	_refresh_top()

	var buy_price_val: float = float(DataService.market_row(AppState.current_city_id(), product_id).get("buy_base_usd", 0.0))
	var sell_price_est: float = EconomySystem.sell_price_estimate(product_id, ticket_dest_city)

	var daily_amp := 0.06
	var mid := sell_price_est - buy_price_val
	var low := mid * (1.0 - daily_amp)
	var high := mid * (1.0 + daily_amp)

	var free_label: Label = product_row.find_child("IntelligenceLabel", true, false)
	if free_label:
		free_label.text = "预计毛利 $" + str(int(low)) + "–$" + str(int(high))
		free_label.add_theme_color_override("font_color", Color.CYAN)

	for child in product_row.get_children():
		if child is Button and child.name == "IntelUpgradeBtn":
			child.queue_free()
			break

	AudioService.play_sfx("sfx_ui_click")
	AchievementSystem.check_all()


func _buy_selected(as_cargo: bool) -> void:
	if _selected_market_product_id == "":
		_show_hint("请先选择要采购的商品")
		return
	var qty: int = int(_market_buy_qty.value) if _market_buy_qty else 1
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
	if err == "":
		_refresh_market_buy()
		_refresh_market_sell()


func _buy_market_item(product_id: String) -> void:
	_select_market_row(product_id)
	_buy_selected(false)


func _show_flights() -> void:
	if not _require_started():
		return
	_set_panel_bgm("globe")
	_clear_panel()
	_dock_panel_work()
	_flight_auto_focus = true
	_selected_connection = {}
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	_panel_host.add_child(v)

	# Row 1: search + mode + compact filters
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	_flight_query = LineEdit.new()
	_flight_query.placeholder_text = "航班号 / 航空公司 / 城市"
	_flight_query.custom_minimum_size = Vector2(180, 0)
	_flight_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flight_query.text_changed.connect(func (_t): _flight_page = 0; _reload_flights())
	top.add_child(_flight_query)
	_dest_code_query = LineEdit.new()
	_dest_code_query.placeholder_text = "IATA"
	_dest_code_query.custom_minimum_size = Vector2(72, 0)
	_dest_code_query.text_changed.connect(func (_t): _flight_page = 0; _reload_flights())
	top.add_child(_dest_code_query)
	var b_direct := Button.new()
	b_direct.text = "直飞"
	b_direct.toggle_mode = true
	b_direct.button_pressed = not _show_connections
	b_direct.pressed.connect(func ():
		_show_connections = false
		b_direct.button_pressed = true
		_flight_page = 0
		_reload_flights()
	)
	top.add_child(b_direct)
	var b_cnx := Button.new()
	b_cnx.text = I18nService.t("ui.transfer.tab")
	if b_cnx.text == "" or b_cnx.text.begins_with("ui."):
		b_cnx.text = "联程"
	b_cnx.toggle_mode = true
	b_cnx.button_pressed = _show_connections
	b_cnx.pressed.connect(func ():
		_show_connections = true
		b_cnx.button_pressed = true
		_flight_page = 0
		_reload_flights()
	)
	top.add_child(b_cnx)
	var bun := Button.new()
	bun.text = "未访"
	bun.toggle_mode = true
	bun.button_pressed = _filter_unvisited
	bun.toggled.connect(func (on): _filter_unvisited = on; _flight_page = 0; _reload_flights())
	top.add_child(bun)
	for pair in [["起飞", "departure"], ["票价", "price"], ["时长", "duration"]]:
		var bs := Button.new()
		bs.text = pair[0]
		var key: String = pair[1]
		bs.pressed.connect(func (): _sort_by = key; _flight_page = 0; _reload_flights())
		top.add_child(bs)
	var prev := Button.new()
	prev.text = "‹"
	prev.pressed.connect(func (): _flight_page = maxi(0, _flight_page - 1); _reload_flights())
	top.add_child(prev)
	var nxt := Button.new()
	nxt.text = "›"
	nxt.pressed.connect(func (): _flight_page += 1; _reload_flights())
	top.add_child(nxt)

	# Recommended chips (single compact row)
	_recommend_box = VBoxContainer.new()
	_recommend_box.add_theme_constant_override("separation", 2)
	v.add_child(_recommend_box)
	_rebuild_recommendations()

	# Fixed-height Tree rows replace the transformed coverflow cards.
	_flight_tree = _make_table(["起飞", "航班 / 航司", "目的地", "到达", "时长 / 经停", "经济舱"], [100, 220, 145, 100, 145, 110])
	_flight_tree.name = "FlightTree"
	_flight_tree.custom_minimum_size = Vector2(0, 240)
	_flight_tree.item_selected.connect(_on_flight_tree_selected)
	v.add_child(_flight_tree)

	# Detail is deliberately outside the scrolling list so choosing another row never reflows it.
	_flight_detail = RichTextLabel.new()
	_flight_detail.bbcode_enabled = true
	_flight_detail.fit_content = false
	_flight_detail.scroll_active = false
	_flight_detail.custom_minimum_size = Vector2(0, 52)
	_flight_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_flight_detail)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var be := Button.new()
	be.text = I18nService.t("ui.ticket.economy")
	be.pressed.connect(func (): _purchase("economy"))
	_IconFactory.decorate_button(be, "ic_economy", 18.0)
	row.add_child(be)
	var bb := Button.new()
	bb.text = I18nService.t("ui.ticket.business")
	bb.pressed.connect(func (): _purchase("business"))
	_IconFactory.decorate_button(bb, "ic_business", 18.0)
	row.add_child(bb)
	var bf := Button.new()
	bf.text = "头等舱"
	bf.pressed.connect(func (): _purchase("first"))
	row.add_child(bf)
	for pair in [["+10kg", "light"], ["+20kg", "standard"], ["+50kg", "heavy"]]:
		var bx := Button.new()
		var tier: String = pair[1]
		bx.text = "%s $%.0f" % [pair[0], _baggage_tier_price(tier)]
		bx.pressed.connect(func ():
			_extra_tier = tier
			_show_hint("已选择行李扩展 %s（+$%.0f）" % [pair[0], _baggage_tier_price(tier)])
		)
		_IconFactory.decorate_button(bx, "ic_baggage", 16.0)
		row.add_child(bx)
	var bc := Button.new()
	bc.text = "货运+50 FREE" if _free_cargo_on_flight else "货运+50 $%.0f" % _cargo_block_price()
	bc.pressed.connect(func ():
		_cargo_blocks += 1
		_show_hint("货运档位 ×%d（每档50kg +$%.0f）" % [_cargo_blocks, _cargo_block_price()])
	)
	_IconFactory.decorate_button(bc, "ic_cargo", 16.0)
	row.add_child(bc)
	var br := Button.new()
	br.text = I18nService.t("ui.ticket.refund")
	br.pressed.connect(func (): _show_hint(_Tickets.refund_current()); _refresh_bags())
	row.add_child(br)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(_close_panel)
	row.add_child(close)
	_extra_tier = ""
	_cargo_blocks = 0
	_flight_page = 0
	_reload_flights()


func _get_recommended_destinations(limit: int = 5) -> Array:
	var scores: Dictionary = {}
	for item_v in AppState.inventory:
		var item: Dictionary = item_v
		var product_id := str(item.get("product_id", ""))
		var origin := str(DataService.get_product(product_id).get("origin_city_id", AppState.current_city_id()))
		var tag_key := "%s|%s" % [origin, product_id]
		var tags: Dictionary = DataService.product_market_tags.get(tag_key, {})
		for dest in tags.get("hot", []):
			scores[dest] = int(scores.get(dest, 0)) + 1
	var sorted_keys: Array = scores.keys()
	sorted_keys.sort_custom(func(a, b): return int(scores[a]) > int(scores[b]))
	var out: Array = []
	var origin_iata := str(AppState.current_airport().get("iata", "")).to_upper()
	var direct_dests := {}
	for d in DataService.destinations_from(origin_iata):
		direct_dests[str(d).to_upper()] = true
	for city_id in sorted_keys:
		var city: Dictionary = DataService.get_city(str(city_id))
		var city_iata := ""
		# Find a passenger airport for this city
		for a in DataService.airports:
			if str(a.get("city_id", "")) == str(city_id):
				city_iata = str(a.get("iata", "")).to_upper()
				break
		var is_direct := city_iata != "" and direct_dests.has(city_iata)
		out.append({
			"city_id": city_id,
			"name_zh": DataService.place_name(city, "name"),
			"iata": city_iata,
			"hot_count": scores[city_id],
			"direct": is_direct,
		})
		if out.size() >= limit:
			break
	return out


func _rebuild_recommendations() -> void:
	if _recommend_box == null:
		return
	for c in _recommend_box.get_children():
		c.queue_free()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_recommend_box.add_child(row)
	var header := Label.new()
	header.text = I18nService.t("ui.recommend.title")
	if header.text == "" or header.text.begins_with("ui."):
		header.text = "推荐航线"
	header.add_theme_color_override("font_color", _Colors.ACCENT_AMBER)
	header.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(header)
	var recs := _get_recommended_destinations(5)
	if recs.is_empty():
		var empty := Label.new()
		empty.text = "（库存为空时无推荐；买入商品后根据热卖目的地生成）"
		empty.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
		row.add_child(empty)
		return
	for rec_v in recs:
		var rec: Dictionary = rec_v
		var btn := Button.new()
		var mode := "直飞" if rec.get("direct", false) else "联程"
		btn.text = "%s · %s件 · %s" % [rec.get("name_zh", rec.get("city_id", "")), rec.get("hot_count", 0), mode]
		var dest_iata := str(rec.get("iata", ""))
		var want_cnx := not bool(rec.get("direct", false))
		btn.pressed.connect(func ():
			_show_connections = want_cnx
			if _flight_query:
				_flight_query.text = dest_iata
			_flight_page = 0
			_reload_flights()
		)
		row.add_child(btn)


func _baggage_tier_price(tier: String) -> float:
	var extras: Dictionary = DataService.economy.get("baggage_extras", {})
	if extras.has(tier):
		var price := float(extras[tier].get("price_usd", 0))
		if bool(extras[tier].get("enables_cold_chain", false)):
			price *= ReputationSystem.cold_baggage_discount()
		return price
	return 0.0


func _cargo_block_price() -> float:
	var extras: Dictionary = DataService.economy.get("baggage_extras", {})
	return float(extras.get("cargo_per_50kg_usd", 0))


## Lv2 privilege: one cargo block is free per purchase. When the free-cargo
## promo already refunded the block on this purchase (free_cargo_used), the
## privilege must not refund the same block a second time.
func _refund_unlock_cargo(free_cargo_used: bool = false) -> void:
	if free_cargo_used:
		return
	if _cargo_blocks > 0 and ReputationSystem.has_unlock(ReputationSystem.UNLOCK_LV2):
		AppState.add_cash(_cargo_block_price())
		_refresh_top()
		_show_hint("声望特权：免费货运 1 块")


func _reload_flights(_q: String = "") -> void:
	if _flight_tree == null:
		return
	_selected_flight = {}
	_selected_connection = {}
	var q: String = _flight_query.text if _flight_query else ""
	var dest_code: String = _dest_code_query.text.strip_edges() if _dest_code_query else ""
	if _show_connections:
		var origin_iata := str(AppState.current_airport().get("iata", ""))
		var all_cnx: Array = _FlightSearch.search_connections(origin_iata, q, 200, dest_code)
		if _filter_unvisited:
			var filtered: Array = []
			for c_v in all_cnx:
				var c: Dictionary = c_v
				if not AppState.visited_airports.has(str(c.get("destination_airport_id", ""))):
					filtered.append(c)
			all_cnx = filtered
		if _max_price > 0.0:
			all_cnx = all_cnx.filter(func(c): return float(c.get("ticket_base_price_economy", 0)) <= _max_price)
		if _max_duration > 0:
			all_cnx = all_cnx.filter(func(c): return int(c.get("duration_minutes", 0)) <= _max_duration)
		var start_c: int = _flight_page * FLIGHTS_PER_PAGE
		if start_c >= all_cnx.size() and _flight_page > 0:
			_flight_page = maxi(0, int((all_cnx.size() - 1) / float(FLIGHTS_PER_PAGE)))
			start_c = _flight_page * FLIGHTS_PER_PAGE
		_connection_cache = all_cnx.slice(start_c, mini(all_cnx.size(), start_c + FLIGHTS_PER_PAGE))
		_flights_cache = []
		_fill_connection_rows()
		_show_hint("联程 %d–%d / 共 %d（页 %d）· 滚轮/拖拽选班" % [
			start_c + (1 if all_cnx.size() > 0 else 0), start_c + _connection_cache.size(), all_cnx.size(), _flight_page + 1
		])
		return
	var all: Array = _FlightSearch.search(
		AppState.current_airport_id, q, 500, _filter_unvisited, _sort_by,
		_max_price, _max_duration, _biz_only, dest_code
	)
	if _flight_auto_focus and all.size() > 0:
		var focus_idx: int = _FlightSearch.first_focus_index(all)
		_flight_page = int(focus_idx / float(FLIGHTS_PER_PAGE))
		_flight_auto_focus = false
		var start_f: int = _flight_page * FLIGHTS_PER_PAGE
		_flights_cache = all.slice(start_f, mini(all.size(), start_f + FLIGHTS_PER_PAGE))
		_fill_flight_rows()
		var local_idx: int = focus_idx - start_f
		if local_idx >= 0 and local_idx < _flights_cache.size():
			_select_flight_tree_index(local_idx)
		_show_hint("航班 %d–%d / 共 %d（页 %d）· 已定位≥2小时后班次" % [
			start_f + 1, start_f + _flights_cache.size(), all.size(), _flight_page + 1
		])
		return
	var start: int = _flight_page * FLIGHTS_PER_PAGE
	if start >= all.size() and _flight_page > 0:
		_flight_page = maxi(0, int((all.size() - 1) / float(FLIGHTS_PER_PAGE)))
		start = _flight_page * FLIGHTS_PER_PAGE
	_flights_cache = all.slice(start, mini(all.size(), start + FLIGHTS_PER_PAGE))
	_fill_flight_rows()
	_show_hint("航班 %d–%d / 共 %d（页 %d）· 滚轮/拖拽选班" % [
		start + (1 if all.size() > 0 else 0), start + _flights_cache.size(), all.size(), _flight_page + 1
	])


func _fill_flight_rows() -> void:
	if _flight_tree == null:
		return
	_flight_tree.clear()
	var root := _flight_tree.create_item()
	for i in _flights_cache.size():
		var fl: Dictionary = _flights_cache[i]
		var stop_n := int(fl.get("stops", 0))
		var item := _flight_tree.create_item(root)
		item.set_text(0, _flight_local_time(str(fl.get("scheduled_departure_utc", "")), str(fl.get("origin_airport_id", ""))))
		item.set_text(1, "%s · %s" % [fl.get("marketing_flight_number", ""), fl.get("airline_name", "")])
		item.set_text(2, "%s %s" % [fl.get("destination_iata", ""), _flight_destination_name(fl)])
		item.set_text(3, _flight_local_time(str(fl.get("scheduled_arrival_utc", "")), str(fl.get("destination_airport_id", ""))))
		item.set_text(4, "%d分钟%s" % [int(fl.get("duration_minutes", 0)), " · 经停×%d" % stop_n if stop_n > 0 else ""])
		item.set_text(5, _Economy.format_money(float(fl.get("ticket_base_price_economy", 0))))
		item.set_metadata(0, i)
		var muted := _FlightSearch.is_short_lead(fl)
		if muted:
			for column in _flight_tree.columns:
				item.set_custom_color(column, _Colors.TEXT_SECONDARY)
	if not _flights_cache.is_empty():
		_select_flight_tree_index(0)
	elif _flight_detail:
		_flight_detail.text = "无匹配航班"
		_selected_flight = {}
		_selected_connection = {}


func _fill_connection_rows() -> void:
	if _flight_tree == null:
		return
	_flight_tree.clear()
	var root := _flight_tree.create_item()
	for i in _connection_cache.size():
		var c: Dictionary = _connection_cache[i]
		var item := _flight_tree.create_item(root)
		item.set_text(0, "约 3小时后")
		item.set_text(1, "联程 · %s→%s" % [c.get("origin_iata", ""), c.get("hub_iata", "")])
		item.set_text(2, "%s 经 %s" % [c.get("destination_iata", ""), c.get("hub_iata", "")])
		item.set_text(3, "两段行程")
		item.set_text(4, "%d分钟 · MCT%d" % [int(c.get("duration_minutes", 0)), int(c.get("mct_minutes", 90))])
		item.set_text(5, _Economy.format_money(float(c.get("ticket_base_price_economy", 0))))
		item.set_metadata(0, i)
	if not _connection_cache.is_empty():
		_select_flight_tree_index(0)
	elif _flight_detail:
		_flight_detail.text = "无匹配联程"
		_selected_flight = {}
		_selected_connection = {}


func _on_flight_tree_selected() -> void:
	if _flight_tree == null:
		return
	var item := _flight_tree.get_selected()
	if item != null:
		_on_flight_selected(int(item.get_metadata(0)))


func _select_flight_tree_index(index: int) -> void:
	if _flight_tree == null:
		return
	var item := _flight_tree.get_root().get_first_child()
	var cursor := 0
	while item != null:
		if cursor == index:
			item.select(0)
			_on_flight_selected(index)
			return
		cursor += 1
		item = item.get_next()


func _flight_destination_name(flight: Dictionary) -> String:
	var airport := DataService.get_airport(str(flight.get("destination_airport_id", "")))
	var city := DataService.get_city(str(airport.get("city_id", "")))
	return DataService.place_name(city, "name")


func _flight_local_time(iso: String, airport_id: String) -> String:
	var airport := DataService.get_airport(airport_id)
	var local_unix := GameClock.parse_iso_to_unix(iso) + GameClock.offset_hours_for(str(airport.get("timezone", ""))) * 3600.0
	var d := Time.get_datetime_dict_from_unix_time(int(local_unix))
	return "%02d:%02d" % [int(d.get("hour", 0)), int(d.get("minute", 0))]


func _on_flight_selected(idx: int) -> void:
	if _flight_detail == null:
		return
	if _show_connections:
		if idx < 0 or idx >= _connection_cache.size():
			return
		_selected_connection = _connection_cache[idx]
		_selected_flight = {}
		var c: Dictionary = _selected_connection
		var mct := int(c.get("mct_minutes", 90))
		_flight_detail.text = "[b]联程[/b] %s→%s→%s · %.0fkm · %dmin(MCT%d) · 经$%.0f/公$%.0f/头$%.0f · 行李=%s 货运×%d" % [
			c.get("origin_iata", ""), c.get("hub_iata", ""), c.get("destination_iata", ""),
			float(c.get("total_distance_km", 0)), int(c.get("duration_minutes", 0)), mct,
			float(c.get("ticket_base_price_economy", 0)), float(c.get("ticket_base_price_business", 0)),
			float(c.get("ticket_base_price_first", 0)),
			_extra_tier if _extra_tier != "" else "无", _cargo_blocks
		]
		return
	if idx < 0 or idx >= _flights_cache.size():
		return
	_selected_flight = _flights_cache[idx]
	_selected_connection = {}
	var fl: Dictionary = _selected_flight
	var stop_n := int(fl.get("stops", 0))
	var stop_tag := "" if stop_n <= 0 else " · 经停%s" % ", ".join(fl.get("stop_airports", []))
	var al_id := str(fl.get("alliance_id", ""))
	var al_tag := ""
	if al_id != "" and al_id != "none":
		al_tag = " · %s" % DataService.alliance_name(al_id)
	_flight_detail.text = "[b]%s[/b] %s→%s · 起飞 %s · %.0fkm/%dmin · 经$%.0f/公$%.0f/头$%.0f%s%s · 行李=%s 货运×%d" % [
		fl.get("marketing_flight_number", ""),
		fl.get("origin_iata", ""), fl.get("destination_iata", ""),
		str(fl.get("scheduled_departure_utc", "")).substr(0, 16),
		float(fl.get("distance_km", 0)), int(fl.get("duration_minutes", 0)),
		float(fl.get("ticket_base_price_economy", 0)), float(fl.get("ticket_base_price_business", 0)),
		float(fl.get("ticket_base_price_first", 0)),
		stop_tag, al_tag,
		_extra_tier if _extra_tier != "" else "无", _cargo_blocks
	]


func _purchase(cabin: String) -> void:
	if _show_connections or not _selected_connection.is_empty():
		if _selected_connection.is_empty():
			_show_hint("请先选择联程航线")
			return
		var err_c: String = _Tickets.purchase_connection(_selected_connection, cabin, _extra_tier, _cargo_blocks, false)
		if err_c.find("已有机票") >= 0:
			_pending_cabin = cabin
			_replace_ticket_dialog.dialog_text = err_c + "\n将按 30% 手续费退旧票后购买联程，确认？"
			_replace_ticket_dialog.popup_centered()
			return
		_show_hint(err_c if err_c != "" else "联程购票成功（两段）")
		if err_c == "":
			AudioService.play_sfx("sfx_ticket_ok")
			if _selected_connection.has("hub_airport_id"):
				globe.draw_trip_route(AppState.current_airport_id, str(_selected_connection.hub_airport_id))
		else:
			AudioService.play_sfx("sfx_error")
		_refresh_bags()
		_refresh_countdown()
		var free_cargo_used := false
		if err_c == "" and _free_cargo_on_flight and _cargo_blocks > 0:
			AppState.add_cash(_cargo_block_price())
			_free_cargo_on_flight = false
			free_cargo_used = true
			_refresh_top()
			_show_hint("免费货运额度已使用！")
		if err_c == "":
			_refund_unlock_cargo(free_cargo_used)
			_check_free_cargo(AppState.current_city_id())
			AchievementSystem.check_all()
		return
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
	var free_cargo_used := false
	if err == "" and _free_cargo_on_flight and _cargo_blocks > 0:
		AppState.add_cash(_cargo_block_price())
		_free_cargo_on_flight = false
		free_cargo_used = true
		_refresh_top()
		_show_hint("免费货运额度已使用！")
	if err == "":
		_refund_unlock_cargo(free_cargo_used)
		_check_free_cargo(AppState.current_city_id())
		AchievementSystem.check_all()


func _do_replace_purchase() -> void:
	var err: String = ""
	if _show_connections or not _selected_connection.is_empty():
		err = _Tickets.purchase_connection(_selected_connection, _pending_cabin, _extra_tier, _cargo_blocks, true)
		_show_hint(err if err != "" else "已替换联程购票")
	else:
		err = _Tickets.purchase(_selected_flight, _pending_cabin, _extra_tier, _cargo_blocks, true)
		_show_hint(err if err != "" else "已替换购票")
	_refresh_bags()
	_refresh_countdown()
	if err == "" and not _selected_flight.is_empty() and _selected_flight.has("destination_airport_id"):
		globe.draw_trip_route(AppState.current_airport_id, str(_selected_flight.destination_airport_id))
	elif err == "" and not _selected_connection.is_empty() and _selected_connection.has("hub_airport_id"):
		globe.draw_trip_route(AppState.current_airport_id, str(_selected_connection.hub_airport_id))
	var free_cargo_used := false
	if err == "" and _free_cargo_on_flight and _cargo_blocks > 0:
		AppState.add_cash(_cargo_block_price())
		_free_cargo_on_flight = false
		free_cargo_used = true
		_refresh_top()
		_show_hint("免费货运额度已使用！")
	if err == "":
		_refund_unlock_cargo(free_cargo_used)
		_check_free_cargo(AppState.current_city_id())
		AchievementSystem.check_all()


func _show_inventory() -> void:
	if not _require_started():
		return
	_clear_panel()
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel_host.add_child(v)
	var summary := Label.new()
	summary.text = "库存整理 · 行李 %.1f/%.1fkg · 货运 %.1f/%.1fkg" % [
		AppState.inventory_weight_kg(false, true), AppState.personal_baggage_limit_kg(),
		AppState.inventory_weight_kg(true, false), AppState.cargo_kg_capacity,
	]
	summary.add_theme_color_override("font_color", _Colors.ACCENT_AMBER)
	v.add_child(summary)
	_add_inventory_group(v, "随身 / 托运行李", false)
	_add_inventory_group(v, "货运", true)
	var row := HBoxContainer.new()
	v.add_child(row)
	var market := Button.new()
	market.text = "前往市场出售"
	market.pressed.connect(func (): _market_arrival_sell_pending = true; _show_market())
	row.add_child(market)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(_close_panel)
	row.add_child(close)


func _add_inventory_group(parent: VBoxContainer, title_text: String, cargo: bool) -> void:
	var title := Label.new()
	title.text = title_text
	title.add_theme_color_override("font_color", _Colors.ACCENT_TEAL)
	parent.add_child(title)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(700, 130)
	list.fixed_icon_size = Vector2i(28, 28)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(list)
	for item_v in AppState.inventory:
		var item: Dictionary = item_v
		if bool(item.get("in_cargo", false)) != cargo:
			continue
		var pid := str(item.get("product_id", ""))
		var product := DataService.get_product(pid)
		var quality := _Economy.current_quality(item)
		var cost := float(item.get("unit_cost", 0))
		var current := _Economy.sell_price(AppState.current_city_id(), pid, quality)
		var spread := current - cost
		var idx := list.add_item("%s ×%d · 品质 %.0f%% · 成本 %s · 当前价值 %s · %s$%.0f/件" % [
			product.get("name_zh", pid), int(item.get("qty", 0)), quality * 100.0,
			_Economy.format_money(cost), _Economy.format_money(current),
			"+" if spread >= 0 else "-", absf(spread),
		])
		var texture := _IconFactory.get_product_icon(pid)
		if texture != null:
			list.set_item_icon(idx, texture)
	if list.item_count == 0:
		list.add_item("暂无%s库存" % ("货运" if cargo else "行李"))


func _check_accidental_premium(product_id: String, index: int, qty: int) -> void:
	var city_id := AppState.current_city_id()
	var date_hour := int(GameClock.unix_time / 3600.0)
	var seed_val := PopupEvent.event_seed(city_id, date_hour, product_id, "accidental_premium")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var base_chance := 0.075  # 7.5%, midpoint of 5-10%
	if rng.randf() > base_chance:
		_do_sell(index, qty)
		return

	var bonus_pct := rng.randi_range(20, 35)

	var item: Dictionary = AppState.inventory[index]
	var actual_qty: int = mini(qty, int(item.get("qty", 0)))
	if actual_qty <= 0:
		return
	var quality: float = _Economy.current_quality(item)
	var unit: float = _Economy.sell_price(city_id, product_id, quality)
	var original_revenue: float = unit * float(actual_qty)
	var premium_revenue: float = original_revenue * (1.0 + float(bonus_pct) / 100.0)

	var popup: PopupEvent = load("res://scenes/PopupEvent.tscn").instantiate() as PopupEvent
	popup.event_confirmed.connect(_on_premium_accepted.bind(index, actual_qty, bonus_pct, original_revenue, premium_revenue))
	add_child(popup)
	popup.show_event("accidental_premium", {
		"bonus_pct": bonus_pct,
		"original": int(original_revenue),
		"premium": int(premium_revenue),
	})


func _on_premium_accepted(index: int, qty: int, bonus_pct: int, original_revenue: float, premium_revenue: float) -> void:
	var result: Dictionary = _Inventory.sell(index, qty)

	if not result.get("success", false):
		_show_hint(str(result.get("msg", "")))
		return

	var bonus_cash: float = premium_revenue - original_revenue
	AppState.add_cash(bonus_cash)

	result["accidental_premium"] = true
	result["accidental_premium_bonus"] = bonus_pct
	result["revenue"] = premium_revenue
	result["margin"] = premium_revenue - result["total_unit_cost"]
	result["margin_rate"] = result["margin"] / result["total_unit_cost"] if result["total_unit_cost"] > 0 else 0.0

	# Correct the logged sell transaction to reflect premium revenue
	var last_tx: Dictionary = AppState.sell_transactions.back()
	if not last_tx.is_empty():
		last_tx["total_revenue"] = premium_revenue
		last_tx["margin"] = result["margin"]
	AppState.log_stat("single_profit_max", 0.0)  # trigger re-eval
	if result["margin"] > float(AppState.stats.get("single_profit_max", 0.0)):
		AppState.stats["single_profit_max"] = result["margin"]
	if result["margin"] < 0.0 and result["total_unit_cost"] > 0.0 and result["margin"] / result["total_unit_cost"] < -0.20:
		AppState.log_stat("big_loss_count", 1.0)

	_show_sell_result_card(result)
	_refresh_market_after_sale()
	_refresh_bags()
	_after_sell_check_discovery(result["product_id"])


func _do_sell(index: int, qty: int) -> void:
	var result: Dictionary = _Inventory.sell(index, qty)
	if not result.get("success", false):
		_show_hint(str(result.get("msg", "")))
		return
	_show_sell_result_card(result)
	_refresh_market_after_sale()
	_refresh_bags()
	_after_sell_check_discovery(result["product_id"])


func _player_has_more_of(product_id: String) -> bool:
	for stack in AppState.inventory:
		if str(stack.get("product_id", "")) == product_id and int(stack.get("qty", 0)) > 0:
			return true
	return false


func _inventory_qty(product_id: String) -> int:
	var total := 0
	for stack in AppState.inventory:
		if str(stack.get("product_id", "")) == product_id:
			total += int(stack.get("qty", 0))
	return total


func _refresh_market_after_sale() -> void:
	if _market_tabs != null and is_instance_valid(_market_tabs):
		_refresh_market_sell()
		_market_tabs.current_tab = 1
		return
	_market_arrival_sell_pending = true
	_show_market()


func _after_sell_check_discovery(sold_product_id: String) -> void:
	var city_id := AppState.current_city_id()

	# Get origin city from product data (where the product was sourced)
	var product_data := DataService.get_product(sold_product_id)
	var origin_city := str(product_data.get("origin_city_id", ""))

	# Check if this destination is COLD for the product
	var tag_key := "%s|%s" % [origin_city, sold_product_id]
	var tags: Dictionary = _product_market_tags.get(tag_key, {})
	if city_id not in tags.get("cold", []):
		return

	# Check if player still has more of this product in inventory
	if not _player_has_more_of(sold_product_id):
		return

	# Roll for discovery (5% chance, deterministic seed)
	var date_hour := int(GameClock.unix_time / 3600.0)
	var seed_val := PopupEvent.event_seed(city_id, date_hour, sold_product_id, "city_discovery")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	if rng.randf() > 0.05:
		return

	# Check already triggered this stay
	var trigger_key := city_id + "|" + sold_product_id
	if _discovery_triggered_in_city.has(trigger_key):
		return
	_discovery_triggered_in_city[trigger_key] = true

	var popup: PopupEvent = load("res://scenes/PopupEvent.tscn").instantiate() as PopupEvent
	popup.event_confirmed.connect(_on_discovery_sell_all.bind(sold_product_id, city_id))
	add_child(popup)
	popup.dialog_text = (
		'"这里的人从没见过%s！"\n\n库存中所有%s 卖出价额外 ×2.0'
		% [sold_product_id, sold_product_id]
	)
	popup.title = "✨ 意外发现！"
	popup.add_button("全部溢价卖出", true)
	popup.add_cancel_button("暂不处理")
	popup.popup_centered()


func _on_discovery_sell_all(_result: Dictionary, product_id: String, city_id: String) -> void:
	var total_revenue: float = 0.0
	var total_cost: float = 0.0
	var total_qty: int = 0

	# Sell all stacks of this product across baggage and cargo at 2x
	for stack in AppState.inventory:
		if str(stack.get("product_id", "")) == product_id:
			var quality: float = _Economy.current_quality(stack)
			var base_price: float = _Economy.sell_price(city_id, product_id, quality)
			var sell_price: float = base_price * 2.0
			var qty: int = int(stack.get("qty", 0))
			var revenue: float = sell_price * qty
			total_revenue += revenue
			total_cost += float(stack.get("unit_cost", 0)) * qty
			total_qty += qty
			AppState.add_cash(revenue)
			_Economy.apply_sale_pressure(city_id, product_id, qty)
			AppState.log_sell_transaction(city_id, product_id, qty, revenue, float(stack.get("unit_cost", 0)) * qty, GameClock.unix_time)

	# Remove all stacks of this product
	AppState.inventory = AppState.inventory.filter(func(s): return str(s.get("product_id", "")) != product_id)
	EventBus.inventory_changed.emit()
	EventBus.market_changed.emit()

	var margin: float = total_revenue - total_cost
	var margin_rate: float = margin / total_cost if total_cost > 0 else 0.0
	AppState.log_stat("discovery_triggered", 1.0)

	AudioService.play_sfx("sfx_sell")
	_show_hint("🎉 意外发现！售出 %s ×%d，收入 %s，毛利 %s（溢价%d%%）" % [
		product_id,
		total_qty,
		_Economy.format_money(total_revenue),
		_Economy.format_money(margin),
		int(margin_rate * 100),
	])
	_refresh_market_after_sale()
	_refresh_bags()
	AchievementSystem.check_all()


func _show_notes() -> void:
	if not _require_started():
		return
	_set_panel_bgm("menu")
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
		var city_name := DataService.place_name(city, "name")

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


func _show_achievements() -> void:
	if not _require_started():
		return
	_set_panel_bgm("menu")
	_clear_panel()
	var v := VBoxContainer.new()
	_panel_host.add_child(v)
	var title := Label.new()
	title.text = I18nService.t("ui.tab.achievements")
	if title.text == "" or title.text.begins_with("ui."):
		title.text = "成就"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", _Colors.ICE)
	v.add_child(title)
	var filters := HBoxContainer.new()
	v.add_child(filters)
	for pair in [["全部", "all"], ["探索", "explore"], ["贸易", "trade"], ["飞行", "flight"], ["收集", "collect"]]:
		var b := Button.new()
		b.text = pair[0]
		b.toggle_mode = true
		b.button_pressed = _ach_filter_category == pair[1]
		var cat: String = pair[1]
		b.pressed.connect(func (): _ach_filter_category = cat; _show_achievements())
		filters.add_child(b)
	var bun := Button.new()
	bun.text = "仅已解锁" if not _ach_filter_unlocked_only else "显示全部"
	bun.pressed.connect(func (): _ach_filter_unlocked_only = not _ach_filter_unlocked_only; _show_achievements())
	filters.add_child(bun)
	if AppState.game_mode == "collector":
		var collector_btn := Button.new()
		collector_btn.text = I18nService.t("ui.collector.title")
		collector_btn.pressed.connect(_show_collector_progress)
		filters.add_child(collector_btn)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var list := VBoxContainer.new()
	scroll.add_child(list)
	for ach_v in AchievementSystem.definitions:
		var ach: Dictionary = ach_v
		if _ach_filter_category != "all" and str(ach.get("category", "")) != _ach_filter_category:
			continue
		var unlocked := AchievementSystem.is_unlocked(str(ach.get("id", "")))
		if _ach_filter_unlocked_only and not unlocked:
			continue
		var row := HBoxContainer.new()
		list.add_child(row)
		var icon_key := str(ach.get("icon", ach.get("id", "")))
		var ach_tex: Texture2D = _IconFactory.get_achievement_icon(icon_key, unlocked)
		var icon := TextureRect.new()
		icon.texture = ach_tex
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			icon.modulate = Color(0.45, 0.45, 0.5, 0.8)
		row.add_child(icon)
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(body)
		var name_l := Label.new()
		name_l.text = str(ach.get("name", ach.get("id", "")))
		name_l.add_theme_color_override("font_color", _Colors.ACCENT_AMBER if unlocked else _Colors.TEXT_SECONDARY)
		body.add_child(name_l)
		var desc_l := Label.new()
		desc_l.text = str(ach.get("desc", ""))
		desc_l.add_theme_font_size_override("font_size", 12)
		desc_l.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
		body.add_child(desc_l)
		var prog := ProgressBar.new()
		prog.min_value = 0
		prog.max_value = 1
		prog.value = AchievementSystem.progress_of(ach)
		prog.custom_minimum_size = Vector2(200, 12)
		prog.show_percentage = false
		body.add_child(prog)
		var prog_l := Label.new()
		prog_l.text = AchievementSystem.current_display(ach)
		prog_l.add_theme_font_size_override("font_size", 11)
		row.add_child(prog_l)
	var footer := Label.new()
	footer.text = "已解锁 %d / %d" % [AppState.unlocked_achievements.size(), AchievementSystem.definitions.size()]
	footer.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	v.add_child(footer)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(_close_panel)
	v.add_child(close)


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
	var body := I18nService.attribution()
	if body.is_empty():
		body = I18nService.disclaimer()
		for a in DataService.world.get("attributions", []):
			body += "\n• %s — %s\n  %s" % [a.get("name", ""), a.get("license", ""), a.get("note", "")]
	var meta: Dictionary = DataService.world.get("meta", {})
	_attr_text.text = "[b]%s[/b]\n\n%s\n\n%s\n%s\n%s\n" % [
		I18nService.t("ui.tab.attribution"),
		body,
		I18nService.t("ui.attr.baseline", {"v": str(meta.get("baseline_date", ""))}),
		I18nService.t("ui.attr.etl", {"v": str(meta.get("etl_version", ""))}),
		I18nService.t("ui.attr.generated", {"v": str(meta.get("generated_at", ""))}),
	]


func _determine_sell_tier(margin: float, margin_rate: float, accidental_premium: bool) -> String:
	if accidental_premium or margin >= 10000:
		return "W2"  # Grand Slam
	elif margin >= 3000:
		return "W1"  # Big Win
	elif margin >= 0:
		return "W0"  # Normal Win
	elif margin_rate >= -0.20:
		return "L1"  # Small Loss
	else:
		return "L2"  # Big Loss


func _show_sell_result_card(sell_result: Dictionary) -> void:
	var tier := _determine_sell_tier(
		sell_result["margin"], sell_result["margin_rate"],
		sell_result.get("accidental_premium", false)
	)

	var popup: PopupEvent = load("res://scenes/PopupEvent.tscn").instantiate() as PopupEvent

	match tier:
		"L2":
			popup.title = I18nService.t("sell_result_title_l2")
			popup.set_portrait("worried")
			if not AppState.reduced_animations:
				FeedbackParticles.play(self, {"palette": "grey", "count": 25, "duration": 2.0, "direction": "down"})
			AudioService.play_sfx("sfx_loss")

		"L1":
			popup.title = I18nService.t("sell_result_title_l1")
			AudioService.play_sfx("sfx_loss_light")

		"W0":
			popup.title = I18nService.t("sell_result_title_w0")
			AudioService.play_sfx("sfx_sell")

		"W1":
			popup.title = I18nService.t("sell_result_title_w1")
			if not AppState.reduced_animations:
				FeedbackParticles.play(self, {"palette": "gold", "count": 30, "duration": 2.0, "direction": "right_arc"})
			AudioService.play_sfx("sfx_big_win")

		"W2":
			popup.title = I18nService.t("sell_result_title_w2")
			popup.set_portrait("celebrating")
			if sell_result.get("discovery_bonus", false):
				popup.title = I18nService.t("sell_result_title_w2_discovery")
			if not AppState.reduced_animations:
				FeedbackParticles.play(self, {"palette": "gold_rain", "count": 60, "duration": 3.0, "direction": "down"})
			AudioService.play_sfx("sfx_grand_slam")

	# Build card body text
	var body := ""
	body += "售出数量：" + str(sell_result["qty"]) + "\n"
	body += "售出收入：$" + str(int(sell_result["revenue"])) + "\n"
	var unit_buy: float = float(sell_result.get("unit_cost", 0))
	var unit_sell: float = float(sell_result.get("unit_price", 0))
	if unit_buy > 0 or unit_sell > 0:
		body += "买入单价：$" + str(int(unit_buy)) + "  →  卖出单价：$" + str(int(unit_sell))
		if unit_sell > 0:
			var unit_spread := unit_sell - unit_buy
			var unit_sign := "+" if unit_spread >= 0 else ""
			body += "  (%s$%d)" % [unit_sign, int(unit_spread)]
		body += "\n"

	var margin: float = sell_result["margin"]
	var sign := "+" if margin >= 0 else ""
	body += "账面毛利：" + sign + "$" + str(int(margin)) + "\n"

	# Net trip profit hint
	var flight_cost: float = AppState.last_flight_price
	var baggage_cost: float = AppState.last_baggage_cost
	if flight_cost > 0 or baggage_cost > 0:
		body += "本趟机票：−$" + str(int(flight_cost))
		if baggage_cost > 0:
			body += "  行李/货运：−$" + str(int(baggage_cost))
		body += "\n"
		var net: float = margin - flight_cost - baggage_cost
		var net_sign := "+" if net >= 0 else ""
		body += "──────────────────\n"
		body += "行程净利：" + net_sign + "$" + str(int(net)) + "\n"

	# Consolation or celebration copy (pool from zh_CN.csv)
	match tier:
		"L2":
			body += "\n" + I18nService.t("sell_console_big_loss")
		"L1":
			body += "\n" + _draw_i18n_pool("sell_console", 5)
		"W1":
			body += "\n" + _draw_i18n_pool("celebration_w1", 3)
		"W2":
			body += "\n" + _draw_i18n_pool("celebration_w2", 3)

	# Wealth milestone toast
	var start_cash: float = float(DataService.economy.get("starting_cash_usd", 50000.0))
	if AppState.cash_usd >= 100000 or AppState.cash_usd >= start_cash * 2.0:
		_show_toast(I18nService.t("sell_result_milestone"))

	popup.dialog_text = body
	popup.add_button(I18nService.t("sell_result_continue"), true)

	add_child(popup)
	popup.popup_centered()

	# Cash roll animation (Task 14 will wire this)
	popup.event_confirmed.connect(func(_r):
		_cash_roll_animation(int(sell_result["revenue"] - sell_result["total_unit_cost"]))
	)


## Draw one random line from an i18n pool named {prefix}_{1..n} (zh_CN.csv).
func _draw_i18n_pool(prefix: String, count: int) -> String:
	var keys: Array[String] = []
	for i in range(1, count + 1):
		var k := "%s_%d" % [prefix, i]
		if I18nService.has_key(k):
			keys.append(k)
	if keys.is_empty():
		push_warning("MainHUD: i18n pool %s empty" % prefix)
		return ""
	return I18nService.t(keys[randi() % keys.size()])


func _show_toast(text: String) -> void:
	_show_hint(text)


func _cash_roll_animation(delta_margin: float) -> void:
	var cash_label := _find_cash_label()
	if not cash_label:
		return
	if AppState.reduced_animations:
		cash_label.text = "$" + str(int(AppState.cash_usd))
		_refresh_top()
		return

	var old_value: float = AppState.cash_usd - delta_margin
	var new_value: float = AppState.cash_usd
	var duration := 1.0
	var is_grand_slam := delta_margin >= 10000

	_cash_rolling = true
	AudioService.play_loop_sfx("sfx_coin_roll")

	if is_grand_slam:
		duration = 0.5  # double speed
		# Flash gold once
		cash_label.add_theme_color_override("font_color", Color.GOLD)
		await get_tree().create_timer(0.3).timeout
		cash_label.remove_theme_color_override("font_color")

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.tween_method(_update_cash_display.bind(cash_label), old_value, new_value, duration)
	await tween.finished
	AudioService.stop_loop_sfx()

	_cash_rolling = false
	_refresh_top()


func _update_cash_display(value: float, label: Label) -> void:
	label.text = "$" + str(int(value))


func _find_cash_label() -> Label:
	return _cash_label


func _save() -> void:
	GameClock.set_paused(true)
	if SaveSystem.save_game():
		_show_hint("已保存")
	else:
		_show_hint("保存失败")
	GameClock.set_paused(false)


func _load() -> void:
	GameClock.set_paused(true)
	if not AppState.game_started:
		AppState.game_mode = _selected_mode
	if SaveSystem.load_game():
		_show_hint("已读档")
	else:
		_show_hint("无存档或存档损坏")
	GameClock.set_paused(not AppState.game_started)


func _toggle_pause() -> void:
	_clear_panel()
	_set_panel_bgm("menu")
	var v := VBoxContainer.new()
	_panel_host.add_child(v)
	var title := Label.new()
	title.text = I18nService.t("ui.settings.title")
	title.add_theme_font_size_override("font_size", 18)
	v.add_child(title)
	var pause_btn := Button.new()
	pause_btn.text = I18nService.t("ui.settings.resume") if GameClock.paused else I18nService.t("ui.settings.pause")
	pause_btn.pressed.connect(func ():
		GameClock.set_paused(not GameClock.paused)
		_show_hint(I18nService.t("ui.settings.pause") if GameClock.paused else I18nService.t("ui.settings.resume"))
		_toggle_pause()
	)
	v.add_child(pause_btn)
	var reduced := CheckButton.new()
	reduced.text = I18nService.t("ui.settings.reduced_anims")
	if reduced.text == "" or reduced.text.begins_with("ui."):
		reduced.text = "减少动态效果"
	reduced.button_pressed = AppState.reduced_animations
	reduced.toggled.connect(func (on): AppState.reduced_animations = on)
	v.add_child(reduced)
	var night := CheckButton.new()
	night.text = I18nService.t("ui.settings.night_bgm")
	if night.text == "" or night.text.begins_with("ui."):
		night.text = "夜时 BGM 变奏"
	night.button_pressed = AppState.night_bgm_enabled
	night.toggled.connect(func (on):
		AppState.night_bgm_enabled = on
		_set_panel_bgm("menu")
	)
	v.add_child(night)
	var font_btn := Button.new()
	var font_levels := [1.0, 1.25, 1.5]
	font_btn.text = I18nService.t("ui.settings.font_scale", {"scale": "%d%%" % int(AppState.font_scale * 100.0)})
	if font_btn.text == "" or font_btn.text.begins_with("ui."):
		font_btn.text = "字号：%d%%" % int(AppState.font_scale * 100.0)
	font_btn.pressed.connect(func ():
		var cur: int = font_levels.find(AppState.font_scale)
		var next: float = font_levels[(cur + 1) % font_levels.size()] if cur >= 0 else 1.0
		AppState.font_scale = next
		_show_hint(I18nService.t("ui.settings.font_scale_changed", {"scale": "%d%%" % int(next * 100.0)}))
		get_tree().reload_current_scene()
	)
	v.add_child(font_btn)
	var cb_btn := Button.new()
	var cb_mode := AppState.color_blind
	cb_btn.text = I18nService.t("ui.settings.color_blind", {"mode": I18nService.t("ui.settings.cb." + cb_mode)})
	if cb_btn.text == "" or cb_btn.text.begins_with("ui."):
		cb_btn.text = "色盲模式：%s" % cb_mode
	cb_btn.pressed.connect(func ():
		var order := ["off", "deuteranopia", "protanopia"]
		var idx := order.find(AppState.color_blind)
		var nxt: String = order[(idx + 1) % order.size()]
		AppState.color_blind = nxt
		_toggle_pause()
	)
	v.add_child(cb_btn)
	var subtitles := CheckButton.new()
	subtitles.text = I18nService.t("ui.settings.subtitles")
	if subtitles.text == "" or subtitles.text.begins_with("ui."):
		subtitles.text = "字幕/提示"
	subtitles.button_pressed = AppState.subtitles_enabled
	subtitles.toggled.connect(func (on): AppState.subtitles_enabled = on)
	v.add_child(subtitles)
	var ui_locale_btn := Button.new()
	ui_locale_btn.text = I18nService.t("ui.settings.language", {"lang": I18nService.t("ui.settings.lang." + AppState.ui_locale)})
	ui_locale_btn.pressed.connect(func ():
		AppState.ui_locale = "zh" if AppState.ui_locale == "en" else "en"
		_show_hint(I18nService.t("ui.settings.language_changed"))
		get_tree().reload_current_scene()
	)
	v.add_child(ui_locale_btn)
	var locale_btn := Button.new()
	locale_btn.text = I18nService.t("ui.settings.place_locale", {"lang": I18nService.t("ui.settings.lang." + AppState.place_locale)})
	locale_btn.pressed.connect(func ():
		AppState.place_locale = "en" if AppState.place_locale == "zh" else "zh"
		locale_btn.text = I18nService.t("ui.settings.place_locale", {"lang": I18nService.t("ui.settings.lang." + AppState.place_locale)})
		_show_hint(I18nService.t("ui.settings.place_locale_changed"))
	)
	v.add_child(locale_btn)
	var mute := CheckButton.new()
	mute.text = I18nService.t("ui.settings.mute")
	if mute.text == "" or mute.text.begins_with("ui."):
		mute.text = "静音"
	mute.button_pressed = AudioService.is_muted()
	mute.toggled.connect(func (on): AudioService.set_muted(on))
	v.add_child(mute)
	var bgm_row := HBoxContainer.new()
	v.add_child(bgm_row)
	var bgm_l := Label.new()
	bgm_l.text = I18nService.t("ui.settings.volume_bgm")
	if bgm_l.text == "" or bgm_l.text.begins_with("ui."):
		bgm_l.text = "音乐"
	bgm_l.custom_minimum_size = Vector2(72, 0)
	bgm_row.add_child(bgm_l)
	var bgm_slider := HSlider.new()
	bgm_slider.min_value = 0.0
	bgm_slider.max_value = 1.0
	bgm_slider.step = 0.05
	bgm_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bgm_slider.value = AudioService.get_bgm_volume()
	bgm_slider.value_changed.connect(func (v: float): AudioService.set_bus_volume("BGM", v))
	bgm_row.add_child(bgm_slider)
	var sfx_row := HBoxContainer.new()
	v.add_child(sfx_row)
	var sfx_l := Label.new()
	sfx_l.text = I18nService.t("ui.settings.volume_sfx")
	if sfx_l.text == "" or sfx_l.text.begins_with("ui."):
		sfx_l.text = "音效"
	sfx_l.custom_minimum_size = Vector2(72, 0)
	sfx_row.add_child(sfx_l)
	var sfx_slider := HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.value = AudioService.get_sfx_volume()
	sfx_slider.value_changed.connect(func (v: float):
		AudioService.set_bus_volume("SFX", v)
		AudioService.set_bus_volume("UI", v)
		AudioService.set_bus_volume("Transition", v)
	)
	sfx_row.add_child(sfx_slider)
	var close := Button.new()
	close.text = I18nService.t("ui.settings.back")
	if close.text == "" or close.text.begins_with("ui."):
		close.text = "关闭"
	close.pressed.connect(_close_panel)
	v.add_child(close)


func _set_panel_bgm(mode: String) -> void:
	## mode: globe | market | menu
	var a := AppState.current_airport()
	var local_hour := -1
	if not a.is_empty() and AppState.night_bgm_enabled:
		var tz := str(a.get("timezone", ""))
		if tz != "":
			local_hour = GameClock.local_hour_for(tz)
	var use_night := AppState.night_bgm_enabled and local_hour >= 0 and (local_hour >= 22 or local_hour < 5)
	match mode:
		"market":
			AudioService.set_bgm("bgm_market")
		"menu":
			AudioService.set_bgm("bgm_menu")
		_:
			AudioService.set_bgm("bgm_night" if use_night else "bgm_globe_day")
