extends Node
## Headless regression for the v0.3.1 real-schedule layers:
##   - BTS 2025-03 US domestic flights (real flight numbers + March departures)
##   - data_source tagging is present but ignored by gameplay
##
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/verify_bts_flights.tscn

var _failures: PackedStringArray = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)
		print("FAIL: ", msg)


func _ready() -> void:
	await _frames(5)

	if DataService.airports.is_empty():
		_check(false, "no airports loaded")
		_finish()
		return

	# ATL is a US hub; with the BTS layer it must expose real US carriers.
	var atl_airport: Dictionary = DataService.get_airport_by_iata("ATL")
	_check(not atl_airport.is_empty(), "ATL missing from airport catalog")
	if atl_airport.is_empty():
		_finish()
		return
	var atl_id := str(atl_airport.get("airport_id", ""))
	var flights: Array = DataService.flights_from(atl_id)
	_check(flights.size() > 100, "ATL should expose >100 outbound flights, got %d" % flights.size())

	var bts: Array = []
	var dep_ok := true
	var shape_ok := true
	var us_carriers := {
		"AA": true, "DL": true, "UA": true, "WN": true,
		"B6": true, "AS": true, "NK": true, "F9": true, "G4": true,
	}
	for f_v in flights:
		var f: Dictionary = f_v
		if str(f.get("data_source", "")) != "bts_2025_03":
			continue
		bts.append(f)
		var dep := str(f.get("scheduled_departure_utc", ""))
		if dep.is_empty():
			dep_ok = false
		var fn := str(f.get("marketing_flight_number", ""))
		var al := fn.substr(0, 2)
		if fn.length() < 3 or not us_carriers.has(al):
			shape_ok = false
	_check(bts.size() > 0, "no BTS-tagged flights out of ATL")

	# Departures must land within the 2025-03 schedule window (UTC spillover to
	# 2025-04-01 is allowed for late-night West Coast departures).
	var bts_dep := true
	for f in bts:
		var dep := str(f.get("scheduled_departure_utc", ""))
		var day := dep.substr(0, 10)
		if day < "2025-03-01" or day > "2025-04-01":
			bts_dep = false
	_check(bts_dep, "BTS departures outside the 2025-03/04-01 window")

	# Every BTS flight must be US-domestic.
	var us_domestic := true
	for f in bts:
		var o: Dictionary = DataService.get_airport_by_iata(str(f.get("origin_iata", "")))
		var d: Dictionary = DataService.get_airport_by_iata(str(f.get("destination_iata", "")))
		if o.get("country_id", "") != "US" or d.get("country_id", "") != "US":
			us_domestic = false
	_check(us_domestic, "non-US domestic flight tagged bts_2025_03")

	# Ticket/baggage fields must exist (shape parity with synthetic flights).
	for f in bts:
		if not (f.has("ticket_base_price_economy") and f.has("baggage_allowance_economy")
				and f.has("scheduled_arrival_utc") and f.has("duration_minutes")):
			shape_ok = false
	_check(shape_ok, "BTS flight dict missing standard fields")

	_check(dep_ok, "ATL BTS departures missing or outside 2025-03")
	print("OK: BTS out of ATL count=%d, example=%s" % [
		bts.size(),
		str(bts[0].get("marketing_flight_number", "") + " " + str(bts[0].get("origin_iata", "")) + "→" + str(bts[0].get("destination_iata", ""))),
	] if not bts.is_empty() else 0)
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("VERIFY_BTS_FLIGHTS_OK")
		get_tree().quit(0)
	else:
		print("VERIFY_BTS_FLIGHTS_FAIL (%d)" % _failures.size())
		for f in _failures:
			printerr("  - ", f)
		get_tree().quit(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
