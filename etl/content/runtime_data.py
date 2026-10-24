"""Export small authored runtime catalogs alongside the generated world."""
import json
from pathlib import Path
import re

SOURCE = Path(__file__).resolve().parents[1] / 'config' / 'runtime'


def export_runtime_data(destination: Path) -> None:
    catalogs = {name: json.loads((SOURCE / name).read_text(encoding='utf-8'))
                for name in ('achievements.json', 'news_events.json')}
    definitions = catalogs['achievements.json']['achievements']
    catalogs['steam_achievements.json'] = {
        'achievements': {
            row['id']: re.sub(r'[^A-Z0-9_]', '_', row['id'].removeprefix('ach_').upper())
            for row in sorted(definitions, key=lambda row: row['id'])
        },
        '_generated_from': 'game/data/achievements.json',
        '_note': "Steam API name = achievements.json id with 'ach_' prefix stripped, uppercased, non-alphanumeric mapped to '_'. Keep in sync with the achievement wall.",
    }
    destination.mkdir(parents=True, exist_ok=True)
    for name, data in catalogs.items():
        (destination / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
