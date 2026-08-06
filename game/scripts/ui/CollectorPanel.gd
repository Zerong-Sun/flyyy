extends Control
## Collector-mode progress panel: product discovery, city visits, and
## collect-category achievement completion. Reuses achievement wall data.

const _Colors = preload("res://themes/DemoColors.gd")
const _ThemeFactory = preload("res://themes/ThemeFactory.gd")

var _products_total := 0
var _cities_total := 0
var _collect_ach_total := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _totals() -> void:
	_products_total = int(DataService.products_by_id.size())
	_cities_total = int(DataService.cities_by_id.size())
	_collect_ach_total = 0
	for ach_v in AchievementSystem.definitions:
		var ach: Dictionary = ach_v
		if str(ach.get("category", "")) == "collect":
			_collect_ach_total += 1


func refresh() -> void:
	_totals()
	for c in get_children():
		c.queue_free()
	_build()
	visible = true


func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(520, 320)
	panel.add_theme_stylebox_override("panel", _ThemeFactory.card_style(false))
	add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.add_theme_constant_override("margin_left", 28)
	v.add_theme_constant_override("margin_right", 28)
	v.add_theme_constant_override("margin_top", 20)
	v.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(v)

	var title := Label.new()
	title.text = I18nService.t("ui.collector.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", _Colors.ICE)
	v.add_child(title)

	_add_row(v, I18nService.t("ui.collector.products", {"cur": AppState.stats.get("products_discovered", {}).size(), "total": _products_total}),
			float(AppState.stats.get("products_discovered", {}).size()), _products_total)
	_add_row(v, I18nService.t("ui.collector.cities", {"cur": AppState.visited_cities.size(), "total": _cities_total}),
			float(AppState.visited_cities.size()), _cities_total)

	var collect_unlocked := 0
	for ach_v in AchievementSystem.definitions:
		var ach: Dictionary = ach_v
		if str(ach.get("category", "")) == "collect" \
				and AchievementSystem.is_unlocked(str(ach.get("id", ""))):
			collect_unlocked += 1
	_add_row(v, I18nService.t("ui.collector.achievements", {"cur": collect_unlocked, "total": _collect_ach_total}),
			float(collect_unlocked), _collect_ach_total)

	if _collect_ach_total > 0 and collect_unlocked >= _collect_ach_total:
		var done := Label.new()
		done.text = I18nService.t("ui.collector.complete")
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done.add_theme_color_override("font_color", _Colors.ACCENT_AMBER)
		v.add_child(done)

	var close := Button.new()
	close.text = I18nService.t("ui.common.close")
	close.pressed.connect(func (): visible = false)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(close)


func _add_row(v: VBoxContainer, text: String, cur: float, total: float) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", _Colors.TEXT_PRIMARY)
	v.add_child(label)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 1
	bar.value = clampf(cur / float(total) if total > 0 else 0.0, 0.0, 1.0)
	bar.custom_minimum_size = Vector2(460, 14)
	bar.show_percentage = false
	v.add_child(bar)
