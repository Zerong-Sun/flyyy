extends RefCounted
class_name ColorBlindPalette
## Okabe-Ito colour-blind-safe palette (CAS §1.7: 四态机场色可区分且不依赖
## 色盲单一通道 — 辅以形状/尺寸线索). Used when AppState.color_blind != "off".

## Pin state colours keyed by airport state for deuteranopia/protanopia modes.
## Order mirrors GlobeController._update_markers:
##   current / selected / visited / unvisited
const PIN_CURRENT := Color("0072B2")  # vivid blue
const PIN_SELECTED := Color("E69F00")  # orange
const PIN_VISITED := Color("009E73")  # bluish green
const PIN_UNVISITED := Color("999999")  # mid grey

const EMISSION_CURRENT := Color("004C7A")
const EMISSION_SELECTED := Color("8F5C00")
const EMISSION_VISITED := Color("005C45")

## Relative pin scale multipliers — a non-colour cue for each state.
const SCALE_CURRENT := 1.3
const SCALE_SELECTED := 1.15
const SCALE_VISITED := 1.0
const SCALE_UNVISITED := 0.9

const GRADE_A := Color("E69F00")
const GRADE_B := Color("0072B2")
const GRADE_C := Color("009E73")
const GRADE_D := Color("999999")


static func active() -> bool:
	return AppState != null and str(AppState.color_blind) != "off"


static func grade_color(grade: String) -> Color:
	if not active():
		return Color()
	match grade:
		"A":
			return GRADE_A
		"B":
			return GRADE_B
		"C":
			return GRADE_C
		_:
			return GRADE_D
	return Color()
