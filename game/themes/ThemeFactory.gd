extends RefCounted
class_name ThemeFactory
## Builds the Demo UI Theme (CAS §1.1.1 StyleBoxes + fonts).

const _Colors = preload("res://themes/DemoColors.gd")

const FONT_UI := "res://assets/fonts/NotoSansSC-Regular.otf"
const FONT_MONO := "res://assets/fonts/JetBrainsMono-Regular.ttf"


static func build() -> Theme:
	var theme := Theme.new()
	var ui_font := _load_font(FONT_UI)
	var mono_font := _load_font(FONT_MONO)
	if ui_font:
		theme.default_font = ui_font
	theme.default_font_size = 15

	_set_panel(theme)
	_set_button(theme)
	_set_line_edit(theme)
	_set_item_list(theme)
	_set_labels(theme, ui_font, mono_font)
	_set_rich_text(theme, ui_font)
	return theme


## Rounded card StyleBox with soft shadow (shared by airport / flight / market cards).
static func card_style(accent: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _Colors.BG_PANEL
	s.border_color = _Colors.ACCENT_AMBER if accent else _Colors.BORDER
	s.set_border_width_all(2 if accent else 1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.32)
	s.shadow_size = 5
	s.shadow_offset = Vector2(0, 2)
	return s


static func selected_row_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(_Colors.ACCENT_TEAL.r, _Colors.ACCENT_TEAL.g, _Colors.ACCENT_TEAL.b, 0.25)
	s.border_color = _Colors.ACCENT_TEAL
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	s.shadow_color = Color(0, 0, 0, 0.2)
	s.shadow_size = 3
	s.shadow_offset = Vector2(0, 1)
	return s


static func _load_font(path: String) -> FontFile:
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		push_warning("ThemeFactory: missing font %s" % path)
		return null
	var font := FontFile.new()
	var err := font.load_dynamic_font(path)
	if err != OK:
		push_warning("ThemeFactory: failed to load %s (%s)" % [path, err])
		return null
	return font


static func _flat(bg: Color, border: Color, radius: float = 6.0, border_w: float = 1.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(int(border_w))
	s.set_corner_radius_all(int(radius))
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func _set_panel(theme: Theme) -> void:
	var panel := card_style(false)
	panel.set_corner_radius_all(8)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)


static func _set_button(theme: Theme) -> void:
	var normal := _flat(Color(_Colors.BG_DEEP.r, _Colors.BG_DEEP.g, _Colors.BG_DEEP.b, 0.95), _Colors.BORDER, 6.0)
	var hover := _flat(Color(_Colors.ACCENT_TEAL.r, _Colors.ACCENT_TEAL.g, _Colors.ACCENT_TEAL.b, 0.35), _Colors.ACCENT_TEAL, 6.0)
	var pressed := _flat(Color(_Colors.ACCENT_AMBER.r, _Colors.ACCENT_AMBER.g, _Colors.ACCENT_AMBER.b, 0.45), _Colors.ACCENT_AMBER, 6.0)
	var disabled := _flat(Color(0.1, 0.12, 0.15, 0.7), _Colors.BORDER, 6.0)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", hover)
	theme.set_color("font_color", "Button", _Colors.TEXT_PRIMARY)
	theme.set_color("font_hover_color", "Button", _Colors.ICE)
	theme.set_color("font_pressed_color", "Button", _Colors.TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "Button", _Colors.TEXT_SECONDARY)
	theme.set_font_size("font_size", "Button", 15)


static func _set_line_edit(theme: Theme) -> void:
	var normal := _flat(Color(_Colors.BG_DEEP.r, _Colors.BG_DEEP.g, _Colors.BG_DEEP.b, 0.9), _Colors.BORDER, 4.0)
	var focus := _flat(Color(_Colors.BG_DEEP.r, _Colors.BG_DEEP.g, _Colors.BG_DEEP.b, 0.95), _Colors.ACCENT_TEAL, 4.0)
	theme.set_stylebox("normal", "LineEdit", normal)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_stylebox("read_only", "LineEdit", normal)
	theme.set_color("font_color", "LineEdit", _Colors.TEXT_PRIMARY)
	theme.set_color("font_placeholder_color", "LineEdit", _Colors.TEXT_SECONDARY)
	theme.set_color("caret_color", "LineEdit", _Colors.ACCENT_AMBER)
	theme.set_font_size("font_size", "LineEdit", 15)


static func _set_item_list(theme: Theme) -> void:
	var bg := _flat(Color(_Colors.BG_DEEP.r, _Colors.BG_DEEP.g, _Colors.BG_DEEP.b, 0.75), _Colors.BORDER, 4.0)
	var selected := _flat(Color(_Colors.ACCENT_TEAL.r, _Colors.ACCENT_TEAL.g, _Colors.ACCENT_TEAL.b, 0.4), _Colors.ACCENT_TEAL, 4.0)
	theme.set_stylebox("panel", "ItemList", bg)
	theme.set_stylebox("focus", "ItemList", bg)
	theme.set_stylebox("selected", "ItemList", selected)
	theme.set_stylebox("selected_focus", "ItemList", selected)
	theme.set_stylebox("cursor", "ItemList", selected)
	theme.set_stylebox("cursor_unfocused", "ItemList", selected)
	theme.set_color("font_color", "ItemList", _Colors.TEXT_PRIMARY)
	theme.set_color("font_selected_color", "ItemList", _Colors.ICE)
	theme.set_color("font_hovered_color", "ItemList", _Colors.ACCENT_TEAL)
	theme.set_font_size("font_size", "ItemList", 14)


static func _set_labels(theme: Theme, ui_font: FontFile, mono_font: FontFile) -> void:
	theme.set_color("font_color", "Label", _Colors.TEXT_PRIMARY)
	theme.set_font_size("font_size", "Label", 15)
	if ui_font:
		theme.set_font("font", "Label", ui_font)
	# Optional mono for code-like labels via type variation name.
	if mono_font:
		theme.set_font("font", "MonoLabel", mono_font)
		theme.set_font_size("font_size", "MonoLabel", 14)
		theme.set_color("font_color", "MonoLabel", _Colors.TEXT_PRIMARY)


static func _set_rich_text(theme: Theme, ui_font: FontFile) -> void:
	theme.set_color("default_color", "RichTextLabel", _Colors.TEXT_PRIMARY)
	theme.set_font_size("normal_font_size", "RichTextLabel", 15)
	if ui_font:
		theme.set_font("normal_font", "RichTextLabel", ui_font)
