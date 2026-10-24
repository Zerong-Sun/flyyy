import json

from etl.content.runtime_data import export_runtime_data


def test_clean_export_includes_all_authored_runtime_catalogs(tmp_path):
    destination = tmp_path / 'fresh-data'
    export_runtime_data(destination)
    achievements = json.loads((destination / 'achievements.json').read_text())['achievements']
    news = json.loads((destination / 'news_events.json').read_text())
    mapping = json.loads((destination / 'steam_achievements.json').read_text())['achievements']
    assert len(achievements) >= 30
    assert len(news) == 10
    assert set(mapping) == {row['id'] for row in achievements}
    assert mapping['ach_flight_connection'] == 'FLIGHT_CONNECTION'
    assert {row['kind'] for row in news} == {'natural', 'economic', 'political'}
    first = {path.name: path.read_bytes() for path in destination.iterdir()}
    (destination / 'news_events.json').write_text('outdated')
    export_runtime_data(destination)
    assert {path.name: path.read_bytes() for path in destination.iterdir()} == first
