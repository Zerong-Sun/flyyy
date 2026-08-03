extends Node
## Headless verification for the stable flight-list workbench.

func _ready() -> void:
	await _frames(5)

	var airports: Array = DataService.airports
	if airports.is_empty():
		print("FAIL: no airports loaded")
		get_tree().quit(1)
		return
	AppState.reset_new_game(airports[0].airport_id)
	await _frames(5)

	var MainHUD: Control = get_node("../Main/UI")
	if not MainHUD.has_method("_show_flights"):
		print("FAIL: MainHUD has no _show_flights")
		get_tree().quit(1)
		return
	MainHUD._show_flights()
	await _frames(10)

	var tree: Tree = MainHUD.get("_flight_tree") as Tree
	var detail: Control = MainHUD.get("_flight_detail")
	if tree == null or not is_instance_valid(tree):
		print("FAIL: _flight_tree is null after _show_flights")
		get_tree().quit(1)
		return
	if detail == null or not is_instance_valid(detail):
		print("FAIL: _flight_detail is null")
		get_tree().quit(1)
		return
	var root: TreeItem = tree.get_root()
	var count: int = root.get_child_count() if root != null else 0
	var detail_text := ""
	if detail is RichTextLabel:
		detail_text = detail.text
	print("OK: flights panel built, stable rows=%d, detail text='%s'" % [count, detail_text])
	if count < 2:
		print("FAIL: flight list has fewer than 2 rows")
		get_tree().quit(1)
		return
	if detail_text == "":
		print("FAIL: flight detail text is empty")
		get_tree().quit(1)
		return

	var panel_host: Control = MainHUD.get("_panel_host")
	if panel_host == null or not is_instance_valid(panel_host):
		print("FAIL: _panel_host is null")
		get_tree().quit(1)
		return
	var viewport_h := get_viewport().get_visible_rect().size.y
	var top_y := panel_host.position.y
	var bottom_y := top_y + panel_host.size.y
	print("OK: panel bounds y=%.0f..%.0f viewport_h=%.0f" % [top_y, bottom_y, viewport_h])
	if top_y < 52.0:
		print("FAIL: flights panel overlaps the top HUD (y=%.0f < 52)" % top_y)
		get_tree().quit(1)
		return
	var tree_rect := tree.get_global_rect()
	var panel_rect := panel_host.get_global_rect()
	if not panel_rect.encloses(tree_rect):
		print("FAIL: flight tree falls outside workbench: tree=%s panel=%s" % [tree_rect, panel_rect])
		get_tree().quit(1)
		return
	var item := root.get_first_child()
	var seen := 0
	while item != null:
		if item.get_text(0) == "" or item.get_text(5) == "":
			print("FAIL: stable list row %d is missing visible content" % seen)
			get_tree().quit(1)
			return
		seen += 1
		item = item.get_next()
	if seen != count:
		print("FAIL: tree row traversal mismatch")
		get_tree().quit(1)
		return

	# Exercise direct/connection switch and ensure both use the same stable Tree.
	MainHUD.set("_show_connections", true)
	MainHUD.set("_flight_page", 0)
	MainHUD.call("_reload_flights")
	await _frames(5)
	var cnx_root := tree.get_root()
	if cnx_root == null or cnx_root.get_child_count() == 0:
		print("FAIL: connection mode did not populate the flight tree")
		get_tree().quit(1)
		return
	MainHUD.set("_show_connections", false)
	MainHUD.call("_reload_flights")
	await _frames(3)
	if bottom_y > viewport_h:
		print("FAIL: flights panel bottom out of bounds (%.0f > %.0f)" % [bottom_y, viewport_h])
		get_tree().quit(1)
		return

	if MainHUD.has_method("_close_panel"):
		MainHUD._close_panel()
	await _frames(3)
	MainHUD._show_flights()
	await _frames(5)
	print("OK: reopen succeeded")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
