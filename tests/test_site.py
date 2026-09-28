import ast
import re
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from build_site import ASSETS, WEB_FILES, build_site  # noqa: E402
from sd_image import IMAGE_SIZE  # noqa: E402


def assembly_table(label):
    """Return a keyboard table from src/console.asm as nine rows of bytes."""
    source = (ROOT / 'src/console.asm').read_text()
    body = source.split(label + ':\n', 1)[1].splitlines()[:9]
    rows = []
    for line in body:
        items = ast.literal_eval('(' + line.strip()[len('db '):] + ',)')
        rows.append([ord(item) if isinstance(item, str) else item for item in items])
    return rows


def javascript_table(name):
    """Return a NORMAL/SHIFTED table from web/keyboard.js as byte rows."""
    source = (ROOT / 'web/keyboard.js').read_text()
    body = re.search(r'const ' + name + r' = \[(.*?)\n  \];', source, re.S).group(1)
    rows = ast.literal_eval('[' + body + ']')
    return [[ord(item) if isinstance(item, str) else item for item in row] for row in rows]


class SiteTests(unittest.TestCase):
    def test_browser_keyboard_mirrors_cartridge_tables(self):
        self.assertEqual(javascript_table('NORMAL'), assembly_table('keys_normal'))
        self.assertEqual(javascript_table('SHIFTED'), assembly_table('keys_shift'))

    def test_page_offers_persistent_green_and_amber_themes(self):
        html = (ROOT / 'web/index.html').read_text()
        javascript = (ROOT / 'web/app.js').read_text()
        stylesheet = (ROOT / 'web/style.css').read_text()
        self.assertIn('<html lang="en" data-theme="green">', html)
        self.assertIn('id="theme-toggle"', html)
        self.assertIn('role="switch"', html)
        self.assertIn('localStorage.getItem("p2000m-theme")', html)
        self.assertIn('const THEME_STORAGE_KEY = "p2000m-theme"', javascript)
        self.assertIn('green: {phosphor: [0x00, 0xff, 0x41]', javascript)
        self.assertIn('amber: {phosphor: [0xff, 0xb0, 0x00]', javascript)
        self.assertIn(':root[data-theme="amber"]', stylesheet)
        self.assertIn('v__VERSION__', html)
        for name in WEB_FILES[1:]:
            url = f'{name}?v=__BUILD__'
            self.assertIn(f'src="{url}"' if name.endswith('.js') else f'href="{url}"', html)
        self.assertIn('<meta id="build" name="build" content="__BUILD__">', html)
        self.assertIn('locateFile: versioned,', javascript)

    def test_page_loads_every_published_machine_asset(self):
        javascript = (ROOT / 'web/app.js').read_text()
        for name, _path, _size in ASSETS:
            self.assertIn(f'"{name}"', javascript)
        self.assertIn(f'const SD_SIZE = {IMAGE_SIZE};', javascript)

    def fixture(self, root):
        (root / 'web').mkdir(parents=True)
        for name in WEB_FILES:
            (root / 'web' / name).write_text('<footer>v__VERSION__ __BUILD__</footer>'
                                             if name == 'index.html' else name)
        assets = []
        for name, _path, size in ASSETS:
            path = root / 'assets' / name
            path.parent.mkdir(exist_ok=True)
            path.write_bytes(bytes(size or 3))
            assets.append((name, path, size))
        emulator = root / 'p2000m-web'
        emulator.with_suffix('.js').write_text('createP2000M = () => {};')
        emulator.with_suffix('.wasm').write_bytes(b'wasm')
        return assets, emulator

    def test_build_site_publishes_page_assets_and_emulator(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            assets, emulator = self.fixture(root)
            output = build_site(root / 'site', emulator, '9.8.7', root, assets)
            index = (output / 'index.html').read_text()
            self.assertRegex(index, r'^<footer>v9\.8\.7 [0-9a-f]{12}</footer>$')
            (root / 'assets/cartridge.bin').write_bytes(b'\1' * 16384)
            rebuilt = build_site(root / 'site', emulator, '9.8.7', root, assets)
            self.assertNotEqual((rebuilt / 'index.html').read_text(), index)
            self.assertTrue((output / '.nojekyll').is_file())
            self.assertEqual((output / 'p2000m-web.wasm').read_bytes(), b'wasm')
            for name, _path, size in assets:
                self.assertEqual((output / name).stat().st_size, size or 3)
            self.assertEqual({path.name for path in output.iterdir()},
                             {*WEB_FILES, *(name for name, _p, _s in assets),
                              'p2000m-web.js', 'p2000m-web.wasm', '.nojekyll'})

    def test_build_site_keeps_previous_output_when_an_asset_is_wrong(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            assets, emulator = self.fixture(root)
            output = root / 'site'
            output.mkdir()
            (output / 'keep').write_text('old')
            assets[1][1].write_bytes(b'short')
            with self.assertRaisesRegex(ValueError, 'exactly'):
                build_site(output, emulator, '9.8.7', root, assets)
            self.assertEqual((output / 'keep').read_text(), 'old')


if __name__ == '__main__':
    unittest.main()
