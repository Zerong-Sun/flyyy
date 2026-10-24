from etl.scripts.run_pipeline import build_cities_500_from_ourairports


def test_upstream_municipality_renames_preserve_authored_city_ids():
    renamed = {
        'EDI': ('Ingliston, Edinburgh', 'edinburgh'),
        'MVD': ('Montevideo', 'ciudad_de_la_costa'),
        'PBI': ('West Palm Beach (new name)', 'west_palm_beach'),
    }
    airports = {iata: {
        'municipality': name, 'name': name + ' Airport', 'type': 'large_airport',
        'iso_country': 'GB', 'continent': 'EU', 'lat': 0.0, 'lon': 0.0,
    } for iata, (name, _) in renamed.items()}
    rows = build_cities_500_from_ourairports(airports, [], set(airports))
    assert {row['iata']: row['city_id'] for row in rows} == {iata: value[1] for iata, value in renamed.items()}
    display = {row['iata']: row['city_en'] for row in rows}
    assert display['EDI'] == 'Edinburgh'  # approved city prose uses this name
    assert display['MVD'] == renamed['MVD'][0]  # no authored catalog: upstream display is retained


def test_new_airport_still_gets_a_city_id_and_demo_hubs_keep_priority():
    airports = {'ZZZ': {
        'municipality': 'Example City', 'name': 'Example Airport', 'type': 'large_airport',
        'iso_country': 'GB', 'continent': 'EU', 'lat': 0.0, 'lon': 0.0,
    }}
    assert build_cities_500_from_ourairports(airports, [], {'ZZZ'})[0]['city_id'] == 'example_city'
    assert build_cities_500_from_ourairports(airports, [{'iata': 'ZZZ', 'city_id': 'demo'}], {'ZZZ'}) == []


def test_supported_city_is_not_evicted_when_upstream_airport_type_changes(tmp_path, monkeypatch):
    import json
    import string
    from etl.scripts import run_pipeline
    monkeypatch.setattr(run_pipeline, 'CFG', tmp_path)
    (tmp_path / 'airport_city_ids.json').write_text(json.dumps({'PBI': 'west_palm_beach'}))
    airports = {}
    for index in range(480):
        code = 'Q' + string.ascii_uppercase[index // 26] + string.ascii_uppercase[index % 26]
        airports[code] = {
            'municipality': code, 'name': code, 'type': 'large_airport',
            'iso_country': 'US', 'continent': 'NA',
        }
    airports['PBI'] = {
        'municipality': 'Updated Palm Beach', 'name': 'Palm Beach', 'type': 'medium_airport',
        'iso_country': 'US', 'continent': 'NA',
    }
    rows = build_cities_500_from_ourairports(airports, [], set(airports))
    assert len(rows) == 480
    assert any(row['iata'] == 'PBI' and row['city_id'] == 'west_palm_beach' for row in rows)


def test_airport_code_change_joins_the_historical_schedule_by_source_id(tmp_path):
    from etl.scripts.run_pipeline import read_ourairports_by_iata
    snapshot = tmp_path / 'airports.csv'
    snapshot.write_text(
        'id,iata_code,latitude_deg,longitude_deg,municipality,name,type\n'
        '3766,DJT,26.68,-80.09,West Palm Beach,Renamed airport,large_airport\n'
        '999,DJT,1,2,Unrelated,Another airport,small_airport\n'
    )
    airports = read_ourairports_by_iata(snapshot)
    assert airports['PBI']['municipality'] == 'West Palm Beach'
    assert airports['DJT']['municipality'] == 'Unrelated'
