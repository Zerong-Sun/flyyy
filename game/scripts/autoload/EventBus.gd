extends Node
## Global signal bus
## Signals are emitted/connected from other autoloads & systems (not within this file).

signal airport_selected(airport_id: String)
signal game_started
signal ticket_purchased
signal boarded
signal arrived
signal market_changed
signal sell_completed(result: Dictionary)
signal inventory_changed
signal cash_changed
signal clock_paused_changed(paused: bool)
signal tutorial_hint(text: String)
