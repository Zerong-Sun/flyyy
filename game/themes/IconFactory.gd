extends RefCounted
class_name IconFactory
## HUD icons + product/achievement/city art under res://assets/.
## Falls back to procedural glyphs when a file is missing.

const _Colors = preload("res://themes/DemoColors.gd")
const ART_LEGACY := "res://assets/art/"
const ICONS_DIR := "res://assets/icons/"
const ACH_DIR := "res://assets/icons/achievements/"
const PRODUCTS_DIR := "res://assets/products/"
const CITIES_DIR := "res://assets/cities/"
const BRAND_DIR := "res://assets/brand/"
const ANIM_DIR := "res://assets/anim/flight_transition/"

## icon_id -> art filename stem (without extension)
const _ART_UI: Dictionary = {
	"ic_city": "icon_city_32",
	"ic_market": "icon_market_32",
	"ic_flight": "icon_flight_32",
	"ic_inventory": "icon_inventory_32",
	"ic_log": "icon_log_32",
	"ic_attr": "icon_attr_32",
	"ic_search": "icon_search_32",
	"ic_random": "icon_random_32",
	"ic_economy": "icon_economy_32",
	"ic_business": "icon_business_32",
	"ic_baggage": "icon_baggage_32",
	"ic_cargo": "icon_cargo_32",
	"ic_fast_forward": "icon_fast_forward_32",
	"ic_save": "icon_save_32",
	"ic_load": "icon_load_32",
	"ic_money": "icon_money_32",
	"ic_weight": "icon_weight_32",
	"ic_clock": "icon_clock_32",
	"ic_warning": "icon_warning_32",
	"ic_notes": "icon_notes_tab_32",
	"ic_intel": "icon_intel_upgrade_32",
	"ic_hot": "icon_hot_tag_32",
	"ic_cold": "icon_cold_tag_32",
	"ic_settings": "icon_settings_32",
	"ic_loading": "icon_loading_globe_32",
	"ic_plane": "icon_plane_tiny_32",
}

## Achievement id / icon stem aliases → available art stems
const _ACH_ALIASES: Dictionary = {
	"icon_ach_explore_cities_100_64": "icon_ach_explore_cities_50_64",
	"icon_ach_explore_cities_500_64": "icon_ach_explore_all_6_64",
	"icon_ach_explore_countries_10_64": "icon_ach_explore_countries_5_64",
	"icon_ach_explore_countries_30_64": "icon_ach_explore_countries_20_64",
	"icon_ach_explore_hubs_20_64": "icon_ach_explore_all_6_64",
	"icon_ach_explore_extreme_ns_64": "icon_ach_explore_continent_asia_64",
	"icon_ach_explore_extreme_ew_64": "icon_ach_explore_continent_europe_64",
	"icon_ach_trade_profit_10k_64": "icon_ach_wealth_50k_single_64",
	"icon_ach_trade_net_100k_64": "icon_ach_wealth_100k_64",
	"icon_ach_trade_big_loss_64": "icon_ach_wealth_bankrupt_64",
	"icon_ach_trade_hot_streak_64": "icon_ach_trade_hot_streak_5_64",
	"icon_ach_trade_intel_64": "icon_ach_specialist_intel_50_64",
	"icon_ach_trade_discovery_64": "icon_ach_trade_discovery_10_64",
	"icon_ach_trade_categories_8_64": "icon_ach_trade_categories_5_64",
	"icon_ach_flight_10_64": "icon_ach_flight_first_64",
	"icon_ach_flight_50_64": "icon_ach_flight_segments_100_64",
	"icon_ach_flight_distance_40k_64": "icon_ach_flight_distance_100k_64",
	"icon_ach_flight_business_64": "icon_ach_flight_business_10_64",
	"icon_ach_flight_cargo_64": "icon_ach_flight_cargo_20_64",
	"icon_ach_flight_connection_64": "icon_ach_flight_connection_5_64",
	"icon_ach_flight_ff_64": "icon_ach_flight_on_time_10_64",
	"icon_ach_flight_on_time_64": "icon_ach_flight_on_time_10_64",
	"icon_ach_collect_products_50_64": "icon_ach_completionist_34_64",
	"icon_ach_collect_products_200_64": "icon_ach_legendary_64",
	"icon_ach_collect_notes_20_64": "icon_ach_trade_discovery_10_64",
	"icon_ach_collect_heroes_50_64": "icon_ach_explore_cities_50_64",
}

const _CATEGORY_ART: Dictionary = {
	"食品": "product_category_food_64",
	"香料": "product_category_spices_64",
	"茶叶": "product_category_tea_64",
	"咖啡": "product_category_coffee_64",
	"糖果": "product_category_confectionery_64",
	"工艺品": "product_category_crafts_64",
	"纺织品": "product_category_textiles_64",
	"陶瓷": "product_category_ceramics_64",
	"文具": "product_category_stationery_64",
	"玩具": "product_category_toys_64",
	"日用品": "product_category_daily_goods_64",
	"机械": "product_category_machinery_64",
	"能源": "product_category_energy_64",
	"电子": "product_category_electronics_64",
	"矿产": "product_category_minerals_64",
}

## icon_id -> {glyph, bg, fg} procedural fallback
const _DEFS: Dictionary = {
	"ic_city": {"glyph": "城", "bg": Color(0.18, 0.35, 0.48), "fg": Color(0.95, 0.97, 1.0)},
	"ic_market": {"glyph": "市", "bg": Color(0.22, 0.42, 0.36), "fg": Color(0.85, 1.0, 0.9)},
	"ic_flight": {"glyph": "航", "bg": Color(0.15, 0.28, 0.45), "fg": Color(0.7, 0.9, 1.0)},
	"ic_inventory": {"glyph": "库", "bg": Color(0.35, 0.28, 0.18), "fg": Color(1.0, 0.92, 0.75)},
	"ic_log": {"glyph": "志", "bg": Color(0.28, 0.22, 0.38), "fg": Color(0.92, 0.88, 1.0)},
	"ic_attr": {"glyph": "源", "bg": Color(0.22, 0.28, 0.32), "fg": Color(0.85, 0.9, 0.95)},
	"ic_search": {"glyph": "搜", "bg": Color(0.16, 0.3, 0.4), "fg": Color(0.8, 0.95, 1.0)},
	"ic_random": {"glyph": "随", "bg": Color(0.32, 0.3, 0.2), "fg": Color(1.0, 0.95, 0.7)},
	"ic_economy": {"glyph": "经", "bg": Color(0.2, 0.35, 0.48), "fg": Color(0.49, 0.71, 0.85)},
	"ic_business": {"glyph": "公", "bg": Color(0.38, 0.3, 0.15), "fg": Color(0.79, 0.64, 0.36)},
	"ic_baggage": {"glyph": "行", "bg": Color(0.3, 0.28, 0.22), "fg": Color(0.95, 0.9, 0.75)},
	"ic_cargo": {"glyph": "货", "bg": Color(0.28, 0.32, 0.25), "fg": Color(0.85, 0.95, 0.8)},
	"ic_fast_forward": {"glyph": "快", "bg": Color(0.45, 0.3, 0.1), "fg": Color(0.91, 0.6, 0.24)},
	"ic_save": {"glyph": "存", "bg": Color(0.18, 0.32, 0.28), "fg": Color(0.7, 0.95, 0.85)},
	"ic_load": {"glyph": "读", "bg": Color(0.18, 0.28, 0.38), "fg": Color(0.7, 0.85, 1.0)},
	"ic_money": {"glyph": "$", "bg": Color(0.25, 0.38, 0.22), "fg": Color(0.7, 1.0, 0.55)},
	"ic_weight": {"glyph": "kg", "bg": Color(0.3, 0.3, 0.32), "fg": Color(0.9, 0.9, 0.95)},
	"ic_clock": {"glyph": "时", "bg": Color(0.2, 0.28, 0.4), "fg": Color(0.85, 0.92, 1.0)},
	"ic_warning": {"glyph": "!", "bg": Color(0.45, 0.18, 0.18), "fg": Color(1.0, 0.7, 0.65)},
	"ic_notes": {"glyph": "记", "bg": Color(0.32, 0.26, 0.18), "fg": Color(1.0, 0.92, 0.75)},
	"ic_intel": {"glyph": "查", "bg": Color(0.18, 0.32, 0.42), "fg": Color(0.6, 0.95, 1.0)},
	"ic_hot": {"glyph": "热", "bg": Color(0.15, 0.4, 0.28), "fg": Color(0.4, 1.0, 0.7)},
	"ic_cold": {"glyph": "冷", "bg": Color(0.45, 0.18, 0.2), "fg": Color(1.0, 0.55, 0.55)},
	"ic_settings": {"glyph": "设", "bg": Color(0.28, 0.3, 0.35), "fg": Color(0.9, 0.92, 0.95)},
	"ic_loading": {"glyph": "球", "bg": Color(0.15, 0.28, 0.4), "fg": Color(0.7, 0.9, 1.0)},
	"ic_plane": {"glyph": "✈", "bg": Color(0.15, 0.28, 0.45), "fg": Color(0.7, 0.9, 1.0)},
}

static var _tex_cache: Dictionary = {}  # path -> Texture2D


static func all_ids() -> PackedStringArray:
	return PackedStringArray(_DEFS.keys())


static func has(icon_id: String) -> bool:
	return _DEFS.has(icon_id) or _ART_UI.has(icon_id)


static func _dirs_for_stem(stem: String) -> PackedStringArray:
	if stem.begins_with("icon_ach_"):
		return PackedStringArray([ACH_DIR, ICONS_DIR, ART_LEGACY])
	if stem.begins_with("icon_"):
		return PackedStringArray([ICONS_DIR, ART_LEGACY])
	if stem.begins_with("product_"):
		return PackedStringArray([PRODUCTS_DIR, ART_LEGACY])
	if stem.begins_with("city_"):
		return PackedStringArray([CITIES_DIR, ART_LEGACY])
	if stem.begins_with("anim_flight_"):
		return PackedStringArray([ANIM_DIR, ART_LEGACY])
	if stem.begins_with("logo_") or stem in ["app_icon", "splash"]:
		return PackedStringArray([BRAND_DIR, ART_LEGACY])
	return PackedStringArray([ART_LEGACY, ICONS_DIR, PRODUCTS_DIR, CITIES_DIR, BRAND_DIR, ANIM_DIR, ACH_DIR])


static func load_art(stem: String) -> Texture2D:
	## Load webp/png by stem from typed asset dirs. Cached. Returns null if missing.
	if stem == "":
		return null
	if _tex_cache.has(stem):
		return _tex_cache[stem]
	for dir_path in _dirs_for_stem(stem):
		for ext in [".webp", ".png"]:
			var path: String = str(dir_path) + stem + str(ext)
			if ResourceLoader.exists(path):
				var tex: Texture2D = load(path) as Texture2D
				if tex != null:
					_tex_cache[stem] = tex
					return tex
			if FileAccess.file_exists(path):
				var img := Image.new()
				var err := img.load(path)
				if err == OK:
					var it := ImageTexture.create_from_image(img)
					_tex_cache[stem] = it
					return it
	_tex_cache[stem] = null
	return null


static func make(icon_id: String, size_px: float = 24.0) -> Control:
	## Prefer art TextureRect; else procedural PanelContainer glyph.
	var tex := get_ui_icon(icon_id)
	if tex != null:
		var tex_rect := TextureRect.new()
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(size_px, size_px)
		tex_rect.size = Vector2(size_px, size_px)
		tex_rect.texture = tex
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex_rect.name = icon_id
		return tex_rect
	var def: Dictionary = _DEFS.get(icon_id, {"glyph": "?", "bg": _Colors.BG_PANEL, "fg": _Colors.TEXT_SECONDARY})
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(size_px, size_px)
	root.size = Vector2(size_px, size_px)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.name = icon_id
	var style := StyleBoxFlat.new()
	style.bg_color = def["bg"]
	style.set_corner_radius_all(int(size_px * 0.2))
	style.set_border_width_all(1)
	style.border_color = _Colors.BORDER
	root.add_theme_stylebox_override("panel", style)
	var lab := Label.new()
	lab.text = str(def["glyph"])
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lab.add_theme_color_override("font_color", def["fg"])
	var font_size := int(size_px * 0.55) if str(def["glyph"]).length() <= 1 else int(size_px * 0.4)
	lab.add_theme_font_size_override("font_size", font_size)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lab)
	return root


static func decorate_button(btn: Button, icon_id: String, size_px: float = 20.0) -> void:
	var art := get_ui_icon(icon_id)
	btn.icon = art if art != null else make_texture(icon_id, int(size_px))
	btn.expand_icon = true
	btn.add_theme_constant_override("icon_max_width", int(size_px))


static func get_ui_icon(icon_id: String) -> Texture2D:
	var stem := str(_ART_UI.get(icon_id, ""))
	if stem != "":
		return load_art(stem)
	return null


static func make_texture(icon_id: String, size_px: int = 24) -> ImageTexture:
	var art := get_ui_icon(icon_id)
	if art != null:
		var img: Image = art.get_image()
		if img != null:
			if img.get_width() != size_px or img.get_height() != size_px:
				img = img.duplicate()
				img.resize(size_px, size_px, Image.INTERPOLATE_LANCZOS)
			return ImageTexture.create_from_image(img)
	# Procedural fallback
	var def: Dictionary = _DEFS.get(icon_id, {"glyph": "?", "bg": Color(0.2, 0.25, 0.3), "fg": Color(0.9, 0.9, 0.9)})
	var img2 := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var bg: Color = def["bg"]
	var margin := maxi(1, int(size_px / 8.0))
	for y in size_px:
		for x in size_px:
			var on_edge := x < margin or y < margin or x >= size_px - margin or y >= size_px - margin
			var cx := mini(x, size_px - 1 - x)
			var cy := mini(y, size_px - 1 - y)
			var corner := cx < margin and cy < margin and (margin - cx) * (margin - cx) + (margin - cy) * (margin - cy) > margin * margin
			if corner:
				img2.set_pixel(x, y, Color(0, 0, 0, 0))
			elif on_edge:
				img2.set_pixel(x, y, Color(_Colors.BORDER.r, _Colors.BORDER.g, _Colors.BORDER.b, 0.9))
			else:
				img2.set_pixel(x, y, Color(bg.r, bg.g, bg.b, 1.0))
	_stamp_glyph(img2, str(def["glyph"]), def["fg"], size_px)
	return ImageTexture.create_from_image(img2)


static func get_product_icon(product_id: String) -> Texture2D:
	## Resolve product art: exact → fuzzy stem → category → generic placeholder.
	if product_id == "":
		return load_art("product_generic_placeholder_64")
	var stems: Array = [
		"product_%s_64" % product_id,
	]
	var base := product_id
	for suf in ["_contract", "_sample", "_proxy", "_core"]:
		if base.ends_with(suf):
			base = base.substr(0, base.length() - suf.length())
			break
	stems.append("product_%s_64" % base)
	# Drop trailing segment noise: atl_chem → try atl_peach style known art via category later
	var parts := base.split("_")
	if parts.size() >= 2:
		stems.append("product_%s_%s_64" % [parts[0], parts[1]])
	for stem_v in stems:
		var tex := load_art(str(stem_v))
		if tex != null:
			return tex
	var p: Dictionary = DataService.get_product(product_id) if DataService != null else {}
	var cat := str(p.get("category", ""))
	if _CATEGORY_ART.has(cat):
		var ctex := load_art(str(_CATEGORY_ART[cat]))
		if ctex != null:
			return ctex
	return load_art("product_generic_placeholder_64")


static func get_achievement_icon(ach_id: String, _unlocked: bool = true) -> Texture2D:
	## Load achievement icon; apply alias map. Callers tint locked icons via modulate.
	var stem := ach_id
	if not stem.begins_with("icon_ach_"):
		stem = "icon_ach_%s_64" % ach_id.trim_prefix("ach_")
	if not stem.ends_with("_64"):
		stem = stem + "_64"
	var tex := load_art(stem)
	if tex == null and _ACH_ALIASES.has(stem):
		tex = load_art(str(_ACH_ALIASES[stem]))
	if tex == null:
		# Prefer category-ish fallbacks
		if stem.find("explore") >= 0:
			tex = load_art("icon_ach_explore_first_city_64")
		elif stem.find("trade") >= 0 or stem.find("wealth") >= 0:
			tex = load_art("icon_ach_trade_first_profit_64")
		elif stem.find("flight") >= 0:
			tex = load_art("icon_ach_flight_first_64")
		else:
			tex = load_art("icon_ach_completionist_34_64")
	if tex == null:
		return make_texture("ic_log", 64)
	return tex


static func get_city_hero(city_id: String) -> Texture2D:
	## Load city hero by city.image_asset_id or city_{id}_hero_720.
	var stem := ""
	if DataService != null:
		var city: Dictionary = DataService.get_city(city_id)
		stem = str(city.get("image_asset_id", ""))
	if stem == "":
		stem = "city_%s_hero_720" % city_id
	var tex := load_art(stem)
	if tex != null:
		return tex
	# Fallback: logo_mark as atmosphere placeholder
	return load_art("logo_mark")


static func get_transition_art(phase: String) -> Texture2D:
	match phase:
		"takeoff":
			return load_art("anim_flight_takeoff")
		"cruise":
			return load_art("anim_flight_cruise")
		"land":
			return load_art("anim_flight_land")
		_:
			return null


static func get_brand(kind: String) -> Texture2D:
	match kind:
		"logo":
			return load_art("logo_mark")
		"wordmark":
			return load_art("logo_wordmark_zh")
		"splash":
			return load_art("splash")
		"app_icon":
			return load_art("app_icon")
		_:
			return null


static func _stamp_glyph(img: Image, glyph: String, fg: Color, size_px: int) -> void:
	var c := int(size_px / 2.0)
	var r := maxi(2, int(size_px / 5.0))
	match glyph:
		"$", "资", "钱":
			_hline(img, c - r, c + r, c - 1, fg)
			_hline(img, c - r, c + r, c + 1, fg)
			_vline(img, c, c - r, c + r, fg)
		"!", "警":
			_vline(img, c, c - r, c + 1, fg)
			_set_pixel(img, c, c + r - 1, fg)
		"kg", "重":
			_hline(img, c - r, c + r, c, fg)
			_vline(img, c - r, c - r + 1, c + r - 1, fg)
			_vline(img, c + r, c - r + 1, c + r - 1, fg)
		"快":
			_set_pixel(img, c - 2, c - 2, fg)
			_set_pixel(img, c - 1, c - 1, fg)
			_set_pixel(img, c, c, fg)
			_set_pixel(img, c - 1, c + 1, fg)
			_set_pixel(img, c - 2, c + 2, fg)
			_set_pixel(img, c + 1, c - 2, fg)
			_set_pixel(img, c + 2, c - 1, fg)
			_set_pixel(img, c + 3, c, fg)
			_set_pixel(img, c + 2, c + 1, fg)
			_set_pixel(img, c + 1, c + 2, fg)
		"航":
			for i in range(-r, r + 1):
				_set_pixel(img, c + i, c, fg)
			_set_pixel(img, c - 1, c - 1, fg)
			_set_pixel(img, c - 1, c + 1, fg)
			_set_pixel(img, c - 2, c - 2, fg)
			_set_pixel(img, c - 2, c + 2, fg)
		_:
			for dy in range(-r + 1, r):
				for dx in range(-r + 1, r):
					if abs(dx) + abs(dy) <= r - 1:
						_set_pixel(img, c + dx, c + dy, fg)


static func _set_pixel(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, c)


static func _hline(img: Image, x0: int, x1: int, y: int, c: Color) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		_set_pixel(img, x, y, c)


static func _vline(img: Image, x: int, y0: int, y1: int, c: Color) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		_set_pixel(img, x, y, c)
