extends Node
## Headless verification: the flight-detail RichTextLabel inside a ScrollContainer
## must grow with content (fit_content=true) so a long detail is scrollable,
## not clipped at the 44px viewport with no scrollbar.

func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1160, 44)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = Vector2(1160, 0)
	rtl.text = "[b]TG681[/b] ATL→BJX · 起飞 2025-03-01T11:10 · 2188km/202min · 经$334/公$3336/头$8339 · 星空联盟 · 行李=无 货运×0 · 这是一条很长的附加说明需要换行显示以验证滚动是否正常工作"
	scroll.add_child(rtl)

	await get_tree().process_frame
	await get_tree().process_frame

	var vbar: VScrollBar = scroll.get_v_scroll_bar()
	var scrolled := vbar != null and vbar.max_value > vbar.page
	print("RESULT fit_content=true: rtl.min_size=", rtl.get_combined_minimum_size(),
		" scrollbar_max=", (vbar.max_value if vbar else -1.0),
		" page=", (vbar.page if vbar else -1.0),
		" scrollable=", scrolled)

	# Now test the old broken config (fit_content=false)
	var scroll2 := ScrollContainer.new()
	scroll2.custom_minimum_size = Vector2(1160, 44)
	scroll2.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll2)
	var rtl2 := RichTextLabel.new()
	rtl2.bbcode_enabled = true
	rtl2.fit_content = false
	rtl2.scroll_active = false
	rtl2.custom_minimum_size = Vector2(1160, 0)
	rtl2.text = rtl.text
	scroll2.add_child(rtl2)
	await get_tree().process_frame
	await get_tree().process_frame
	var vbar2: VScrollBar = scroll2.get_v_scroll_bar()
	var scrolled2 := vbar2 != null and vbar2.max_value > vbar2.page
	print("RESULT fit_content=false: rtl.min_size=", rtl2.get_combined_minimum_size(),
		" scrollbar_max=", (vbar2.max_value if vbar2 else -1.0),
		" page=", (vbar2.page if vbar2 else -1.0),
		" scrollable=", scrolled2)

	if scrolled and not scrolled2:
		print("PASS: fit_content=true enables scrolling, false clips")
		get_tree().quit(0)
	else:
		print("FAIL: unexpected scroll behavior")
		get_tree().quit(1)
