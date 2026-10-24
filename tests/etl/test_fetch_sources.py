import importlib.util
import io
from pathlib import Path
import zipfile

import pytest


@pytest.fixture
def fetcher(tmp_path, monkeypatch):
    path = Path(__file__).resolve().parents[2] / 'etl/scripts/01_fetch_sources.py'
    spec = importlib.util.spec_from_file_location('fetch_sources', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    monkeypatch.setattr(module, 'RAW', tmp_path)
    return module


def archive(name='nested/schedule.csv', payload=b'FlightDate,Flight_Number\n2025-03-01,1\n'):
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w') as bundle:
        bundle.writestr(name, payload)
    return output.getvalue()


def test_bts_archive_uses_the_pipeline_csv_filename(fetcher, monkeypatch):
    monkeypatch.setattr(fetcher.urllib.request, 'urlopen', lambda *a, **k: io.BytesIO(archive()))
    assert fetcher._fetch('bts_on_time_2025_3.zip', 'https://example.test/bts')
    expected = fetcher.RAW / 'bts_on_time_2025_3.csv'
    assert expected.read_bytes().startswith(b'FlightDate,')
    assert list(fetcher.RAW.iterdir()) == [expected]


def test_bad_archive_preserves_last_good_csv(fetcher, monkeypatch):
    expected = fetcher.RAW / 'bts_on_time_2025_3.csv'
    expected.write_bytes(b'last-good')
    monkeypatch.setattr(fetcher.urllib.request, 'urlopen', lambda *a, **k: io.BytesIO(archive('readme.txt')))
    assert not fetcher._fetch('bts_on_time_2025_3.zip', 'https://example.test/bts')
    assert expected.read_bytes() == b'last-good'
    assert list(fetcher.RAW.iterdir()) == [expected]


def test_interrupted_download_preserves_last_good_source(fetcher, monkeypatch):
    class Interrupted(io.BytesIO):
        def read(self, size=-1):
            if self.tell():
                raise OSError('connection lost')
            return super().read(size)
    expected = fetcher.RAW / 'airports.csv'
    expected.write_bytes(b'last-good')
    monkeypatch.setattr(fetcher.urllib.request, 'urlopen', lambda *a, **k: Interrupted(b'incomplete'))
    assert not fetcher._fetch('airports.csv', 'https://example.test/airports')
    assert expected.read_bytes() == b'last-good'
    assert list(fetcher.RAW.iterdir()) == [expected]


def test_plain_download_replaces_source_only_after_completion(fetcher, monkeypatch):
    monkeypatch.setattr(fetcher.urllib.request, 'urlopen', lambda *a, **k: io.BytesIO(b'id,name\n1,airport\n'))
    assert fetcher._fetch('airports.csv', 'https://example.test/airports')
    assert (fetcher.RAW / 'airports.csv').read_bytes() == b'id,name\n1,airport\n'


def test_strict_mode_reports_a_failed_source(fetcher, monkeypatch):
    monkeypatch.setattr(fetcher, 'SOURCES', {'airports.csv': 'https://example.test/airports'})
    monkeypatch.setattr(fetcher, '_fetch', lambda *a: False)
    assert fetcher.main(['--strict']) == 1
    assert fetcher.main([]) == 0
