"""Check the split load image/runtime RAM contract and reproducible ROM link."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from build_metadata import generate
from link_core import link_core
from memory_layout import LAYOUT, TPA_BYTES, TPA_TEXT


class MemoryLayoutTests(unittest.TestCase):
    def test_shared_release_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'src').symlink_to(ROOT / 'src', target_is_directory=True)
            identities = []
            for version in ('0.4.0', '0.4.1'):
                (root / 'VERSION').write_text(version + '\n')
                with patch.dict('os.environ', {'SOURCE_DATE_EPOCH': '0'}):
                    metadata = generate(root)
                exported = link_core(root, root / 'build')
                self.assertEqual(metadata['version'], version)
                rom = (root / 'build/cartridge.bin').read_bytes()
                kernel = (root / 'build/kernel.bin').read_bytes()
                self.assertIn(f'System  v{version}'.encode('ascii'), rom)
                self.assertIn(b'Cartridge + kernel  /  pending verification', rom)
                self.assertIn(b'Cartridge + kernel  /  matched system release', kernel)
                self.assertNotIn(b'Kernel  v', kernel)
                self.assertNotIn(b'ROM     v', rom)
                identities.append(((root / 'build/generated/link-id.txt').read_text(), exported))
            self.assertNotEqual(identities[0][0], identities[1][0])
            self.assertEqual(identities[0][1], identities[1][1],
                             'Version-only change must not alter link addresses')

    def test_memory_regions(self):
        self.assertEqual(TPA_BYTES, 51200)
        self.assertEqual(LAYOUT['tpa_limit'] & 255, 0)
        self.assertEqual(LAYOUT['kernel_end'], LAYOUT['sector_buffer'])
        self.assertGreaterEqual(LAYOUT['rom_workspace'], LAYOUT['kernel_end'])
        self.assertGreaterEqual(LAYOUT['bdos_workspace'], LAYOUT['kernel_end'])
        self.assertLessEqual(LAYOUT['bdos_workspace'] + 0x38, LAYOUT['rom_workspace'])
        self.assertEqual(LAYOUT['rom_workspace'] + 64, 0xdc00)
        self.assertEqual(LAYOUT['resident_code_limit'], LAYOUT['bdos_stack_bottom'])
        self.assertEqual(LAYOUT['bdos_stack_top'], LAYOUT['system_stack_bottom'])
        self.assertEqual(LAYOUT['system_stack_top'], LAYOUT['kernel_end'])
        self.assertEqual(LAYOUT['keyboard_stack_top'] - LAYOUT['keyboard_stack_bottom'], 128)
        self.assertEqual(LAYOUT['keyboard_stack_top'], LAYOUT['allocation_c'])
        self.assertEqual(LAYOUT['keyboard_queue'], 0xdcc0)
        self.assertEqual(LAYOUT['keyboard_queue'] + 64, 0xdd00)
        self.assertIn('50.00 KiB (51200 bytes)', TPA_TEXT)

    def test_link_from_clean_directory_is_reproducible(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'VERSION').write_text((ROOT / 'VERSION').read_text())
            results = []
            for _ in range(2):
                with patch.dict('os.environ', {'SOURCE_DATE_EPOCH': '0'}):
                    generate(root)
                exported = link_core(ROOT, root / 'build')
                self.assertEqual(exported['bdos_entry'], LAYOUT['tpa_limit'])
                self.assertLessEqual(exported['rom_filesystem_end'], 0xf000)
                self.assertLessEqual(exported['rom_keyboard_tail_end'], 0xf000)
                self.assertLessEqual(exported['rom_crc_end'], 0xf000)
                self.assertEqual(exported['keyboard_vector'], 0xe7fe)
                self.assertLessEqual(exported['rom_runtime_end'], exported['keyboard_vector'])
                self.assertLessEqual(exported['resident_code_end'], LAYOUT['resident_code_limit'])
                results.append(tuple((root / 'build' / name).read_bytes()
                                     for name in ('cartridge.bin', 'kernel.bin')))
            self.assertEqual(results[0], results[1])
            self.assertEqual(len(results[0][0]), 8192 + exported['boot_loader_end'] - LAYOUT['boot_loader_base'])
            self.assertEqual(len(results[0][1]), LAYOUT['kernel_bytes'])
