extends Node
## Headless verification for the flights-panel crash (d020020 regression).
## Starts a new game and opens the flights panel; prints OK/FAIL markers.

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

	var carousel: Control = MainHUD.get("_flight_carousel")
	var detail: Control = MainHUD.get("_flight_detail")
	if carousel == null or not is_instance_valid(carousel):
		print("FAIL: _flight_carousel is null after _show_flights (panel build aborted)")
		get_tree().quit(1)
		return
	if detail == null or not is_instance_valid(detail):
		print("FAIL: _flight_detail is null")
		get_tree().quit(1)
		return
	var count: int = carousel.get_child_count()
	var detail_text := ""
	if detail is RichTextLabel:
		detail_text = detail.text
	print("OK: flights panel built, carousel children=%d, detail text='%s'" % [count, detail_text])
	if count < 2:
		print("FAIL: carousel has fewer than 2 cards — _reload_flights() did not populate it")
		get_tree().quit(1)
		return
	if detail_text == "":
		print("FAIL: flight detail text is empty")
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
