extends AcceptDialog
class_name PopupEvent

## PopupEvent — reusable dialog for all surprise events and sell results.
## Call show_event(type, data) to configure and display.
## Emits event_confirmed or event_cancelled after user choice.

signal event_confirmed(result: Dictionary)
signal event_cancelled(result: Dictionary)

var _event_type: String = ""
var _event_data: Dictionary = {}

func _ready() -> void:
	# AcceptDialog always shows a default OK button that also fires `confirmed`,
	# duplicating the explicit confirm buttons added by each event variant
	# (趁机买入 / 成交！ / 继续 / 全部溢价卖出). Hide it so every popup shows
	# exactly one set of choices.
	get_ok_button().visible = false

func show_event(event_type: String, data: Dictionary = {}) -> void:
	_event_type = event_type
	_event_data = data
	_configure()
	popup_centered()

func _configure() -> void:
	match _event_type:
		"arrival_discount":
			title = "偶遇商机！"
			_show_two_button(_event_data.get("product_name", ""), _event_data.get("discount_pct", 0))
		"free_cargo":
			title = "舱位福利"
			_show_two_button("额外 +50kg 免费货运", 0)
		"accidental_premium":
			title = "意外溢价！"
			_show_one_button(_event_data.get("bonus_pct", 0), _event_data.get("original", 0.0), _event_data.get("premium", 0.0))
		"sell_result":
			title = ""
			_show_sell_result(_event_data)
		_:
			push_error("PopupEvent: unknown event type '%s'" % _event_type)

func _show_two_button(item_desc: String, discount_pct: int = 0) -> void:
	var body := ""
	if _event_type == "arrival_discount":
		body = "本地经销商清仓，\n" + item_desc + " 限时折扣 " + str(discount_pct) + "%\n\n" + "剩余 2 小时（游戏时间）"
		add_button("趁机买入", true)
		add_cancel_button("不了谢谢")
	elif _event_type == "free_cargo":
		body = "该航班货舱有空位，额外 +50kg cargo 本次免费（原价 $380）"
		add_button("接受", true)
		add_cancel_button("不用")
	dialog_text = body

func _show_one_button(bonus_pct: int, original: float, premium: float) -> void:
	dialog_text = (
		"买家急需这批货！\n"
		+ "本次售价额外加成 +" + str(bonus_pct) + "%\n\n"
		+ "原售出价：$" + str(original) + "\n"
		+ "溢价后：$" + str(premium)
	)
	add_button("成交！", true)

func _show_sell_result(data: Dictionary) -> void:
	# Handled by MainHUD._show_sell_result_card — this variant just displays result card content
	dialog_text = ""  # populated by caller
	# One close button only
	add_button("继续", true)


func set_portrait(kind: String) -> void:
	## Show a merchant portrait (kind: "worried" | "celebrating") beside the
	## dialog text. No-op when the art is missing so feedback still works.
	var tex: Texture2D = IconFactory.get_portrait(kind)
	var frame := get_node_or_null("PortraitFrame") as TextureRect
	if frame == null:
		return
	frame.texture = tex
	frame.visible = tex != null

func _on_confirmed() -> void:
	event_confirmed.emit({"accepted": true, "type": _event_type, "data": _event_data})

func _on_cancelled() -> void:
	event_cancelled.emit({"accepted": false, "type": _event_type, "data": _event_data})

# Seed generation helper — deterministic hash for event triggers
static func event_seed(city_id: String, date_hour: int, product_id: String = "", event_type: String = "") -> int:
	var raw := str(city_id) + str(date_hour) + str(product_id) + event_type
	return hash(raw)
