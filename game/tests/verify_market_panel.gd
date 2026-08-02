extends Node
## Headless verification for the redesigned market purchase-items table.
## Opens the market panel, asserts named column labels exist on rows,
## then reopens the same city to exercise _update_market_rows.

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
	if not MainHUD.has_method("_show_market"):
		print("FAIL: MainHUD has no _show_market")
		get_tree().quit(1)
		return
	MainHUD._show_market()
	await _frames(10)

	var container: Control = MainHUD.get("_market_container")
	if container == null or not is_instance_valid(container):
		print("FAIL: _market_container is null after _show_market")
		get_tree().quit(1)
		return
	var row_count := container.get_child_count()
	print("OK: market panel built, rows=%d" % row_count)
	if row_count < 1:
		print("FAIL: market has no product rows")
		get_tree().quit(1)
		return

	var first_panel: PanelContainer = container.get_child(0) as PanelContainer
	if first_panel == null:
		print("FAIL: first market child is not a PanelContainer")
		get_tree().quit(1)
		return
	var row: HBoxContainer = first_panel.get_child(0) as HBoxContainer
	if row == null:
		print("FAIL: market row HBox missing")
		get_tree().quit(1)
		return

	var required := ["NameLabel", "WeightLabel", "TagLabel", "BuyPriceLabel", "SellPriceLabel", "MarginLabel"]
	for label_name in required:
		var node := row.get_node_or_null(label_name)
		if node == null or not (node is Label):
			print("FAIL: missing named label '%s'" % label_name)
			get_tree().quit(1)
			return
		var lab := node as Label
		if lab.text == "":
			print("FAIL: label '%s' is empty" % label_name)
			get_tree().quit(1)
			return
	print("OK: named table columns present Name='%s' Buy='%s' Sell='%s' Margin='%s'" % [
		(row.get_node("NameLabel") as Label).text,
		(row.get_node("BuyPriceLabel") as Label).text,
		(row.get_node("SellPriceLabel") as Label).text,
		(row.get_node("MarginLabel") as Label).text,
	])

	# Selection highlight applies on click, and reopening the same city must
	# clear it (regression: previously the stylebox override stayed stale).
	var cache: Array = MainHUD.get("_market_cache")
	if cache.is_empty():
		print("FAIL: market cache empty")
		get_tree().quit(1)
		return
	var first_pid: String = str(cache[0])
	MainHUD._select_market_row(first_pid)
	await _frames(2)
	if not first_panel.has_theme_stylebox_override("panel"):
		print("FAIL: selected row has no highlight override")
		get_tree().quit(1)
		return

	# Reopen same city → highlight must be cleared
	MainHUD._show_market()
	await _frames(5)
	var container2: Control = MainHUD.get("_market_container")
	if container2 == null or not is_instance_valid(container2) or container2.get_child_count() < 1:
		print("FAIL: market reopen lost rows")
		get_tree().quit(1)
		return
	if first_panel.has_theme_stylebox_override("panel"):
		print("FAIL: stale selection highlight survived reopen")
		get_tree().quit(1)
		return
	print("OK: market reopen refreshed rows=%d, selection highlight cleared" % container2.get_child_count())
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
