extends Node
## Lightweight meta-growth: reputation points → level → unlock tree.
## Points come from trading profit, new-city visits, flight arrivals, and
## product discovery (wired in AppState / FlightOps). Persisted via
## AppState.reputation_points / AppState.level.

const LEVEL_THRESHOLDS: Array[int] = [0, 30, 80, 160, 280, 460]

# Unlock keys (active when level reaches the index+1 threshold).
const UNLOCK_LV2 := "unlock_lv2_cargo"     # cargo capacity +1 block
const UNLOCK_LV3 := "unlock_lv3_cold_discount"  # cold-chain baggage 20% off
const UNLOCK_LV4 := "unlock_lv4_intel_discount"  # intel forecast 30% off
const UNLOCK_LV5 := "unlock_lv5_baggage_plus10"  # +10kg baggage allowance
const UNLOCK_LV6 := "unlock_lv6_globe_title"     # "环球航商" title


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func level_for(xp: int) -> int:
	var lv := 1
	for i in range(LEVEL_THRESHOLDS.size() - 1, 0, -1):
		if xp >= LEVEL_THRESHOLDS[i]:
			lv = i + 1
			break
	return lv


func xp_to_next_level() -> int:
	var lv := AppState.level
	if lv >= LEVEL_THRESHOLDS.size():
		return 0
	return maxi(0, LEVEL_THRESHOLDS[lv] - AppState.reputation_points)


func active_unlocks() -> Array[String]:
	var out: Array[String] = []
	if AppState.level >= 2:
		out.append(UNLOCK_LV2)
	if AppState.level >= 3:
		out.append(UNLOCK_LV3)
	if AppState.level >= 4:
		out.append(UNLOCK_LV4)
	if AppState.level >= 5:
		out.append(UNLOCK_LV5)
	if AppState.level >= 6:
		out.append(UNLOCK_LV6)
	return out


func has_unlock(key: String) -> bool:
	return AppState.level >= _level_for_key(key)


## Lv3 cold-chain privilege: 20% off the cold baggage tier. Single source of
## truth shared by the UI label (MainHUD._baggage_tier_price) and the actual
## charge (TicketService._extra_cost / add_baggage_or_cargo).
static func cold_baggage_discount() -> float:
	if AppState.level >= _level_for_key(UNLOCK_LV3):
		return 0.8
	return 1.0


func unlock_name(key: String) -> String:
	match key:
		UNLOCK_LV2:
			return "ui.reputation.unlock.lv2"
		UNLOCK_LV3:
			return "ui.reputation.unlock.lv3"
		UNLOCK_LV4:
			return "ui.reputation.unlock.lv4"
		UNLOCK_LV5:
			return "ui.reputation.unlock.lv5"
		UNLOCK_LV6:
			return "ui.reputation.unlock.lv6"
	return ""


static func _level_for_key(key: String) -> int:
	match key:
		UNLOCK_LV2:
			return 2
		UNLOCK_LV3:
			return 3
		UNLOCK_LV4:
			return 4
		UNLOCK_LV5:
			return 5
		UNLOCK_LV6:
			return 6
	return 99


func add_points(n: int) -> void:
	if n <= 0:
		return
	AppState.reputation_points += n
	var new_level := level_for(AppState.reputation_points)
	if new_level != AppState.level:
		AppState.level = new_level
		EventBus.reputation_changed.emit(new_level)
