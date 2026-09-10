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
    def test_memory_regions(self):
        self.assertEqual(TPA_BYTES, 52224)
        self.assertEqual(LAYOUT['tpa_limit'] & 255, 0)
        self.assertEqual(LAYOUT['kernel_end'], LAYOUT['sector_buffer'])
        self.assertGreaterEqual(LAYOUT['rom_workspace'], LAYOUT['kernel_end'])
        self.assertGreaterEqual(LAYOUT['bdos_workspace'], LAYOUT['kernel_end'])
        self.assertLessEqual(LAYOUT['bdos_workspace'] + 0x38, LAYOUT['rom_workspace'])
        self.assertEqual(LAYOUT['rom_workspace'] + 64, 0xdc00)
        self.assertEqual(LAYOUT['resident_code_limit'], LAYOUT['bdos_stack_bottom'])
        self.assertEqual(LAYOUT['bdos_stack_top'], LAYOUT['system_stack_bottom'])
        self.assertEqual(LAYOUT['system_stack_top'], LAYOUT['kernel_end'])
        self.assertIn('51.00 KiB (52224 bytes)', TPA_TEXT)

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
                self.assertLessEqual(exported['resident_code_end'], LAYOUT['resident_code_limit'])
                results.append(tuple((root / 'build' / name).read_bytes()
                                     for name in ('cartridge.bin', 'kernel.bin')))
            self.assertEqual(results[0], results[1])
            self.assertEqual(len(results[0][0]), 8192 + exported['boot_loader_end'] - LAYOUT['boot_loader_base'])
            self.assertEqual(len(results[0][1]), LAYOUT['kernel_bytes'])
