extends Node
## Loads zh_CN.csv, tutorial_zh.json, attribution_zh.txt for Demo UI strings.

const UI_CSV := "res://assets/i18n/zh_CN.csv"
const TUTORIAL_JSON := "res://assets/i18n/tutorial_zh.json"
const ATTRIBUTION_TXT := "res://assets/i18n/attribution_zh.txt"

var _ui: Dictionary = {}  # key -> zh_CN
var _tutorials: Dictionary = {}  # trigger -> {id, title, text, ...}
var attribution_body: String = ""
var loaded: bool = false


func _ready() -> void:
	_load_ui_csv()
	_load_tutorials()
	_load_attribution()
	loaded = true
	print("I18nService loaded: %d ui keys, %d tutorials" % [_ui.size(), _tutorials.size()])


func _load_ui_csv() -> void:
	if not FileAccess.file_exists(UI_CSV):
		push_warning("I18nService: missing %s" % UI_CSV)
		return
	var f := FileAccess.open(UI_CSV, FileAccess.READ)
	if f == null:
		return
	var header := f.get_csv_line()
	var key_i := 0
	var zh_i := 1
	for i in header.size():
		if str(header[i]) == "keys" or str(header[i]) == "key":
			key_i = i
		elif str(header[i]) == "zh_CN":
			zh_i = i
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.is_empty() or row.size() <= maxi(key_i, zh_i):
			continue
		var k := str(row[key_i]).strip_edges()
		if k.is_empty() or k == "keys" or k == "key":
			continue
		_ui[k] = str(row[zh_i])


func _load_tutorials() -> void:
	if not FileAccess.file_exists(TUTORIAL_JSON):
		push_warning("I18nService: missing %s" % TUTORIAL_JSON)
		return
	var f := FileAccess.open(TUTORIAL_JSON, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for item in data.get("tutorials", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var trigger := str(item.get("trigger", ""))
		if trigger.is_empty():
			continue
		_tutorials[trigger] = item


func _load_attribution() -> void:
	if not FileAccess.file_exists(ATTRIBUTION_TXT):
		attribution_body = ""
		return
	var f := FileAccess.open(ATTRIBUTION_TXT, FileAccess.READ)
	if f == null:
		return
	attribution_body = f.get_as_text()
	f.close()


## Translate UI key; optional {var} substitution from vars Dictionary.
func t(key: String, vars: Dictionary = {}) -> String:
	var s := str(_ui.get(key, key))
	for k in vars.keys():
		s = s.replace("{%s}" % str(k), str(vars[k]))
	return s


func has_key(key: String) -> bool:
	return _ui.has(key)


func tutorial(trigger: String) -> String:
	if _tutorials.has(trigger):
		return str(_tutorials[trigger].get("text", ""))
	return ""


func tutorial_title(trigger: String) -> String:
	if _tutorials.has(trigger):
		return str(_tutorials[trigger].get("title", ""))
	return ""


func disclaimer() -> String:
	if has_key("ui.disclaimer"):
		var d := t("ui.disclaimer")
		if d != "（见强制声明）" and not d.is_empty():
			return d
	# Prefer DataService world disclaimer when CSV placeholder
	if DataService != null and str(DataService.disclaimer) != "":
		return DataService.disclaimer
	return "航班网络基于公开航空数据重建，不代表真实购票信息。"
