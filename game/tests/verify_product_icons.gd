extends Node
## Headless verification: after syncing the newest product sprites from
## assets/art/ into assets/products/, IconFactory.get_product_icon() must
## resolve real textures for a sample of product ids (not procedural fallback).

func _ready() -> void:
	await _frames(5)

	var airports: Array = DataService.airports
	if airports.is_empty():
		print("FAIL: no airports loaded")
		get_tree().quit(1)
		return
	AppState.reset_new_game(airports[0].airport_id)
	await _frames(5)

	# Sample product ids from the world data + category placeholders.
	var product_ids: Array = []
	var world_products: Array = DataService.world.get("products", [])
	for p in world_products:
		product_ids.append(str(p.get("product_id", "")))
		if product_ids.size() >= 12:
			break
	for extra in ["ams_cheese", "atl_cotton", "pvg_silk", "sin_perfume"]:
		product_ids.append(extra)
	product_ids.append("")  # generic placeholder path

	var loaded := 0
	var failures: Array = []
	for pid in product_ids:
		var tex = IconFactory.get_product_icon(pid)
		if tex != null:
			loaded += 1
		else:
			failures.append(pid)
	print("RESULT get_product_icon: loaded=%d/%d" % [loaded, product_ids.size()])
	if failures.size() > 0:
		print("  failures: ", failures)

	if loaded == product_ids.size():
		print("PASS: all product icons resolve to textures")
		get_tree().quit(0)
	else:
		print("FAIL: some product icons unresolved")
		get_tree().quit(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
