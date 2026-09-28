import copy
from hashlib import sha256
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from games import fetch, install, load_lock, manifest  # noqa: E402

DATA = b'OTHELLO test payload'
DIGEST = sha256(DATA).hexdigest()
URL = 'https://github.com/example/game/releases/download/v1.2.3/GAME.COM'
LOCK = {
    'schema': 1,
    'games': [{
        'id': 'game', 'repository': 'https://github.com/example/game',
        'version': 'v1.2.3', 'commit': 'a' * 40, 'drive': 'J', 'user': 0,
        'artifacts': [{'path': 'GAME.COM', 'sha256': DIGEST, 'release_url': URL}],
    }],
}


def toml(document):
    """Serialize the small lock structure used by these tests."""
    lines = [f'schema = {document["schema"]}']
    for game in document['games']:
        lines.append('[[games]]')
        for key, value in game.items():
            if key != 'artifacts':
                lines.append(f'{key} = {value!r}' if isinstance(value, int) else f'{key} = "{value}"')
        for artifact in game['artifacts']:
            lines.append('[[games.artifacts]]')
            lines.extend(f'{key} = "{value}"' for key, value in artifact.items())
    return '\n'.join(lines) + '\n'


class GameLockTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def lock(self, document=LOCK):
        path = self.root / 'games.lock.toml'
        path.write_text(toml(document))
        return load_lock(path)

    def test_repository_lock_pins_othello_release(self):
        (othello,) = load_lock()
        self.assertEqual(othello.identifier, 'othello')
        self.assertEqual(othello.drive, 9)
        self.assertEqual(othello.repository, 'https://github.com/ifilot/p2000m-othello')
        self.assertEqual([artifact.name for artifact in othello.artifacts], ['OTHELLO.COM'])
        othello_ui = (ROOT / 'tests/othello_ui.cpp').read_text()
        self.assertIn(f'"VERSION {othello.version}"', othello_ui)

    def test_rejects_invalid_entries(self):
        cases = {
            'unknown key': ('games', 0, 'build_command', 'make'),
            'short commit': ('games', 0, 'commit', 'abc'),
            'bad version': ('games', 0, 'version', '1.2.3'),
            'RAM drive': ('games', 0, 'drive', 'L'),
            'two-letter drive': ('games', 0, 'drive', 'JK'),
            'other user': ('games', 0, 'user', 3),
            'foreign URL': ('artifacts', 0, 'release_url', URL.replace('v1.2.3', 'v9.9.9')),
            'bad filename': ('artifacts', 0, 'path', 'TOOLONGNAME.COM'),
            'bad digest': ('artifacts', 0, 'sha256', 'ab' * 16),
        }
        for label, (table, index, key, value) in cases.items():
            with self.subTest(label):
                document = copy.deepcopy(LOCK)
                target = document['games'][0]
                target = target if table == 'games' else target['artifacts'][index]
                target[key] = value
                if key == 'path':
                    target['release_url'] = URL.replace('GAME.COM', value)
                with self.assertRaises(ValueError):
                    self.lock(document)

    def test_rejects_duplicate_files_on_one_drive(self):
        document = copy.deepcopy(LOCK)
        second = copy.deepcopy(document['games'][0])
        second['id'] = 'other'
        document['games'].append(second)
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            self.lock(document)

    def test_install_verifies_caches_and_maps_drives(self):
        (game,) = self.lock()
        downloads = []

        def download(url):
            downloads.append(url)
            return DATA

        cache, output = self.root / 'cache', self.root / 'build'
        self.assertEqual(install(output, (game,), cache, download), {9: [output / 'GAME.COM']})
        self.assertEqual((output / 'GAME.COM').read_bytes(), DATA)
        self.assertEqual((cache / 'game/v1.2.3/GAME.COM').read_bytes(), DATA)
        install(output, (game,), cache, download)
        self.assertEqual(downloads, [URL], 'A verified cached copy must be reused')
        self.assertEqual(manifest((game,))['game']['files'], {'GAME.COM': DIGEST})

    def test_fetch_rejects_digest_mismatch_and_bad_cache(self):
        (game,) = self.lock()
        cache = self.root / 'cache'
        with self.assertRaisesRegex(ValueError, 'does not match'):
            fetch(game, game.artifacts[0], cache, lambda url: DATA + b'!')
        self.assertFalse((cache / 'game/v1.2.3/GAME.COM').exists())
        stale = cache / 'game/v1.2.3/GAME.COM'
        stale.parent.mkdir(parents=True)
        stale.write_bytes(b'tampered')
        self.assertEqual(fetch(game, game.artifacts[0], cache, lambda url: DATA), DATA)
        self.assertEqual(stale.read_bytes(), DATA)


if __name__ == '__main__':
    unittest.main()
