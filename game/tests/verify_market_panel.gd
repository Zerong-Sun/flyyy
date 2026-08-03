extends Node
## Headless verification for the market purchase/sell workbench.

func _ready() -> void:
	await _frames(5)
	var airports: Array = DataService.airports
	if airports.is_empty():
		_fail("no airports loaded")
		return
	AppState.reset_new_game(airports[0].airport_id)
	await _frames(5)
	var MainHUD: Control = get_node("../Main/UI")
	MainHUD._show_market()
	await _frames(5)
	var tabs: TabContainer = MainHUD.get("_market_tabs") as TabContainer
	var buy_tree: Tree = MainHUD.get("_market_buy_tree") as Tree
	if tabs == null or buy_tree == null:
		_fail("market tabs or buy tree missing")
		return
	if tabs.get_tab_count() != 2 or tabs.get_tab_title(0) != "采购" or tabs.get_tab_title(1) != "出售":
		_fail("market does not expose purchase/sell tabs")
		return
	if tabs.current_tab != 0:
		_fail("empty new game must open purchase tab")
		return
	var root := buy_tree.get_root()
	var local_count := root.get_child_count() if root else 0
	var expected_local := DataService.products_for_city(AppState.current_city_id()).size()
	print("OK: local purchase rows=%d expected=%d" % [local_count, expected_local])
	if local_count != expected_local:
		_fail("blank purchase search must show only local products")
		return
	var destination_id := ""
	for airport_v in airports:
		var airport: Dictionary = airport_v
		if str(airport.get("city_id", "")) != AppState.current_city_id():
			destination_id = str(airport.get("airport_id", ""))
			break
	AppState.held_tickets = [{"destination_airport_id": destination_id}]
	MainHUD._show_market()
	await _frames(3)
	buy_tree = MainHUD.get("_market_buy_tree") as Tree
	var outlook_item := buy_tree.get_root().get_first_child()
	if outlook_item == null or outlook_item.get_text(4).find("$") < 0:
		_fail("ticket destination must produce a purchase estimate")
		return
	AppState.held_tickets.clear()

	var external: Dictionary = {}
	for product_v in DataService.world.get("products", []):
		var product: Dictionary = product_v
		if str(product.get("origin_city_id", "")) != AppState.current_city_id():
			external = product
			break
	if external.is_empty():
		_fail("could not find external product for search check")
		return
	var search: LineEdit = MainHUD.get("_market_search") as LineEdit
	search.text = str(external.get("name_zh", ""))
	MainHUD._refresh_market_buy()
	await _frames(5)
	root = buy_tree.get_root()
	if root == null or root.get_child_count() == 0:
		_fail("global product search returned no rows")
		return
	var found := false
	var item := root.get_first_child()
	while item != null:
		if item.get_text(0) == str(external.get("name_zh", "")):
			found = true
			break
		item = item.get_next()
	if not found:
		_fail("global product search did not include external product")
		return

	# Landing with inventory opens Sell once, then defaults back to Purchase.
	AppState.inventory.append({
		"product_id": str(external.get("product_id", "")), "qty": 2,
		"unit_cost": 100.0, "quality": 1.0,
		"purchased_unix": GameClock.unix_time, "in_cargo": false,
	})
	MainHUD.set("_market_arrival_sell_pending", true)
	MainHUD._show_market()
	await _frames(5)
	tabs = MainHUD.get("_market_tabs") as TabContainer
	var sell_tree: Tree = MainHUD.get("_market_sell_tree") as Tree
	if tabs.current_tab != 1 or sell_tree.get_root().get_child_count() != 1:
		_fail("arrival inventory did not open populated sell tab")
		return
	var sell_item := sell_tree.get_root().get_first_child()
	sell_item.select(0)
	MainHUD._on_market_sell_tree_selected()
	var sale := InventorySystem.sell(0, 1)
	if not bool(sale.get("success", false)):
		_fail("test inventory stack could not be sold")
		return
	MainHUD._refresh_market_after_sale()
	await _frames(3)
	if tabs.current_tab != 1:
		_fail("sale must keep the market on sell tab")
		return
	MainHUD._show_market()
	await _frames(3)
	tabs = MainHUD.get("_market_tabs") as TabContainer
	if tabs.current_tab != 0:
		_fail("arrival sell default must be consumed after one market open")
		return
	MainHUD._show_inventory()
	await _frames(3)
	if _has_exact_button_text(MainHUD, "出售"):
		_fail("inventory must not retain a duplicate sell action")
		return
	print("OK: market tabs, global search, arrival sell and post-sale refresh work")
	get_tree().quit(0)


func _fail(message: String) -> void:
	print("FAIL: " + message)
	get_tree().quit(1)


func _has_exact_button_text(node: Node, wanted: String) -> bool:
	if node is Button and (node as Button).text == wanted:
		return true
	for child in node.get_children():
		if _has_exact_button_text(child, wanted):
			return true
	return false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
