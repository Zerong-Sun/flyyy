extends RefCounted
class_name IconFactory
## Procedural icon placeholders for CAS §1.2.E (Demo — replace with SVG/PNG in art pack D1).
## Each icon is a ColorRect + Label glyph; sized for 24×24 / 32×32 HUD use.

const _Colors = preload("res://themes/DemoColors.gd")

## icon_id -> {glyph, bg, fg}
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
	# Trade-feedback extras (CAS feedback art §5.1 placeholders)
	"ic_notes": {"glyph": "记", "bg": Color(0.32, 0.26, 0.18), "fg": Color(1.0, 0.92, 0.75)},
	"ic_intel": {"glyph": "查", "bg": Color(0.18, 0.32, 0.42), "fg": Color(0.6, 0.95, 1.0)},
	"ic_hot": {"glyph": "热", "bg": Color(0.15, 0.4, 0.28), "fg": Color(0.4, 1.0, 0.7)},
	"ic_cold": {"glyph": "冷", "bg": Color(0.45, 0.18, 0.2), "fg": Color(1.0, 0.55, 0.55)},
}


static func all_ids() -> PackedStringArray:
	return PackedStringArray(_DEFS.keys())


static func has(icon_id: String) -> bool:
	return _DEFS.has(icon_id)


static func make(icon_id: String, size_px: float = 24.0) -> Control:
	## Returns a Control sized size_px×size_px. Falls back to "?" if unknown.
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
	## Prepends an icon Control as a child overlay at the left of a Button via icon texture substitute.
	## Since Button.icon expects Texture2D, we bake a tiny ImageTexture instead.
	btn.icon = make_texture(icon_id, int(size_px))
	btn.expand_icon = true
	btn.add_theme_constant_override("icon_max_width", int(size_px))


static func make_texture(icon_id: String, size_px: int = 24) -> ImageTexture:
	## Rasterize a solid rounded square + glyph into an ImageTexture (placeholder art).
	var def: Dictionary = _DEFS.get(icon_id, {"glyph": "?", "bg": Color(0.2, 0.25, 0.3), "fg": Color(0.9, 0.9, 0.9)})
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var bg: Color = def["bg"]
	var margin := maxi(1, size_px / 8)
	for y in size_px:
		for x in size_px:
			var on_edge := x < margin or y < margin or x >= size_px - margin or y >= size_px - margin
			# Soft rounded corners via distance from corner
			var cx := mini(x, size_px - 1 - x)
			var cy := mini(y, size_px - 1 - y)
			var corner := cx < margin and cy < margin and (margin - cx) * (margin - cx) + (margin - cy) * (margin - cy) > margin * margin
			if corner:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif on_edge:
				img.set_pixel(x, y, Color(_Colors.BORDER.r, _Colors.BORDER.g, _Colors.BORDER.b, 0.9))
			else:
				img.set_pixel(x, y, Color(bg.r, bg.g, bg.b, 1.0))
	# Draw a simple glyph mark as a cross/dot pattern so icons are distinguishable without fonts
	_stamp_glyph(img, str(def["glyph"]), def["fg"], size_px)
	return ImageTexture.create_from_image(img)


static func _stamp_glyph(img: Image, glyph: String, fg: Color, size_px: int) -> void:
	## Draw a few distinctive pixel patterns per glyph family (no font rasterizer needed).
	var c := int(size_px / 2)
	var r := maxi(2, size_px / 5)
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
			# Chevrons >>
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
			# Plane-ish triangle pointing right
			for i in range(-r, r + 1):
				_set_pixel(img, c + i, c, fg)
			_set_pixel(img, c - 1, c - 1, fg)
			_set_pixel(img, c - 1, c + 1, fg)
			_set_pixel(img, c - 2, c - 2, fg)
			_set_pixel(img, c - 2, c + 2, fg)
		_:
			# Filled diamond / square mark
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
