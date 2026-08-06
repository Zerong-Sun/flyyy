extends Node
## Loads zh_CN.csv + en.csv (UI), tutorial_*.json and attribution_*.txt.
## Runtime language follows AppState.ui_locale ("zh" | "en"); t() falls back
## zh → key so the English table can never blank the UI.

const UI_CSV_ZH := "res://assets/i18n/zh_CN.csv"
const UI_CSV_EN := "res://assets/i18n/en.csv"
const TUTORIAL_JSON_ZH := "res://assets/i18n/tutorial_zh.json"
const TUTORIAL_JSON_EN := "res://assets/i18n/tutorial_en.json"
const ATTRIBUTION_TXT_ZH := "res://assets/i18n/attribution_zh.txt"
const ATTRIBUTION_TXT_EN := "res://assets/i18n/attribution_en.txt"

var _ui: Dictionary = {}  # locale -> {key -> text}
var _tutorials: Dictionary = {}  # locale -> {trigger -> {id, title, text, ...}}
var attribution_body: String = ""
var loaded: bool = false


func _ready() -> void:
	_ui["zh"] = _load_ui_csv(UI_CSV_ZH)
	_ui["en"] = _load_ui_csv(UI_CSV_EN)
	_tutorials["zh"] = _load_tutorials(TUTORIAL_JSON_ZH)
	_tutorials["en"] = _load_tutorials(TUTORIAL_JSON_EN)
	attribution_body = _load_attribution(ATTRIBUTION_TXT_ZH)
	loaded = true
	print("I18nService loaded: zh=%d en=%d ui keys, tutorials zh=%d en=%d" % [
		_ui["zh"].size(), _ui["en"].size(),
		_tutorials["zh"].size(), _tutorials["en"].size()])


func current_locale() -> String:
	if AppState != null:
		return "en" if str(AppState.ui_locale) == "en" else "zh"
	return "zh"


func _load_ui_csv(path: String) -> Dictionary:
	var table: Dictionary = {}
	if not FileAccess.file_exists(path):
		push_warning("I18nService: missing %s" % path)
		return table
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return table
	var header := f.get_csv_line()
	var key_i := 0
	var val_i := 1
	for i in header.size():
		if str(header[i]) == "keys" or str(header[i]) == "key":
			key_i = i
		elif str(header[i]) in ["zh_CN", "en"]:
			val_i = i
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.is_empty() or row.size() <= maxi(key_i, val_i):
			continue
		var k := str(row[key_i]).strip_edges()
		if k.is_empty() or k == "keys" or k == "key":
			continue
		table[k] = str(row[val_i])
	f.close()
	return table


func _load_tutorials(path: String) -> Dictionary:
	var table: Dictionary = {}
	if not FileAccess.file_exists(path):
		push_warning("I18nService: missing %s" % path)
		return table
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return table
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return table
	for item in data.get("tutorials", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var trigger := str(item.get("trigger", ""))
		if trigger.is_empty():
			continue
		table[trigger] = item
	return table


func _load_attribution(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var body := f.get_as_text()
	f.close()
	return body


## Translate UI key; optional {var} substitution from vars Dictionary.
## English falls back to zh, then to the raw key.
func t(key: String, vars: Dictionary = {}) -> String:
	var loc := current_locale()
	var s := str(_ui[loc].get(key, _ui["zh"].get(key, key)))
	for k in vars.keys():
		s = s.replace("{%s}" % str(k), str(vars[k]))
	return s


func has_key(key: String) -> bool:
	return _ui["zh"].has(key) or _ui["en"].has(key)


func tutorial(trigger: String) -> String:
	return _tutorial_text(trigger, "text")


func tutorial_title(trigger: String) -> String:
	return _tutorial_text(trigger, "title")


func _tutorial_text(trigger: String, field: String) -> String:
	var loc := current_locale()
	if _tutorials[loc].has(trigger):
		return str(_tutorials[loc][trigger].get(field, ""))
	if _tutorials["zh"].has(trigger):
		return str(_tutorials["zh"][trigger].get(field, ""))
	return ""


func disclaimer() -> String:
	var d := t("ui.disclaimer")
	if d != "（见强制声明）" and not d.is_empty():
		return d
	# Prefer DataService world disclaimer when CSV placeholder
	if DataService != null and str(DataService.disclaimer) != "":
		return DataService.disclaimer
	return "航班网络基于公开航空数据重建，不代表真实购票信息。"
