extends Node
## Global signal bus

signal airport_selected(airport_id: String)
signal game_started
signal ticket_purchased
signal boarded
signal arrived
signal market_changed
signal inventory_changed
signal cash_changed
signal clock_paused_changed(paused: bool)
signal tutorial_hint(text: String)
