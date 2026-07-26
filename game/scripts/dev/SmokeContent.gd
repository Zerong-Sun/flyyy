extends SceneTree
## Headless smoke: load I18n + Audio autoloads, play one SFX, quit.
## Run: Godot --headless --path game -s res://scripts/dev/SmokeContent.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	var errors: PackedStringArray = []

	var i18n := root.get_node_or_null("I18nService")
	var audio := root.get_node_or_null("AudioService")
	var data := root.get_node_or_null("DataService")
	if i18n == null:
		ok = false
		errors.append("I18nService autoload missing")
	if audio == null:
		ok = false
		errors.append("AudioService autoload missing")
	if data == null:
		ok = false
		errors.append("DataService autoload missing")

	if i18n != null:
		if not bool(i18n.get("loaded")):
			ok = false
			errors.append("I18nService not loaded")
		var city_label: String = i18n.call("t", "ui.tab.city")
		if city_label != "城市":
			ok = false
			errors.append("ui.tab.city mismatch: %s" % city_label)
		var tip: String = i18n.call("tutorial", "new_game")
		if tip.is_empty():
			ok = false
			errors.append("tutorial new_game empty")
		if str(i18n.get("attribution_body")).is_empty():
			ok = false
			errors.append("attribution empty")
		var disc: String = i18n.call("disclaimer")
		if disc.find("公开航空数据重建") < 0:
			ok = false
			errors.append("disclaimer missing")

	if audio != null:
		audio.call("play_sfx", "sfx_ui_click")
		audio.call("set_bgm", "bgm_globe_day")
		var by_id: Dictionary = audio.get("_by_id")
		if by_id.is_empty():
			ok = false
			errors.append("AudioService manifest empty")
		elif not by_id.has("bgm_globe_day"):
			ok = false
			errors.append("bgm_globe_day missing from manifest")

	if data != null:
		var cities: Dictionary = data.get("cities_by_id")
		if cities.size() != 20:
			ok = false
			errors.append("expected 20 cities, got %d" % cities.size())

	if ok:
		print("SMOKE_CONTENT_OK")
		quit(0)
	else:
		print("SMOKE_CONTENT_FAIL")
		for e in errors:
			printerr("  - ", e)
		quit(1)
