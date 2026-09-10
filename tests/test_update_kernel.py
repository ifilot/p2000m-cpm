"""Upgrade a copy without touching partition data or the original image."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import sd_image as sd
from update_kernel import upgrade


class UpgradeTests(unittest.TestCase):
    def test_upgrade_preserves_source_and_partition_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, dest, kernel = (root / name for name in ('old.img', 'new.img', 'kernel.bin'))
            sd.create_image(source)
            payload = bytearray(sd.LAYOUT['kernel_bytes'])
            payload[3:11] = b'P2MCPM03'
            kernel.write_bytes(payload)
            upgrade(source, dest, kernel)
            end = (16 + sd.LAYOUT['kernel_sectors']) * 512
            with source.open('rb') as old, dest.open('rb') as new:
                self.assertEqual(old.read(15 * 512), new.read(15 * 512))
                self.assertEqual(new.read(8), b'P2MSYS03')
                self.assertNotEqual(old.read(8), b'P2MSYS03')
                old.seek(end)
                new.seek(end)
                while chunk := old.read(1024 * 1024):
                    self.assertEqual(new.read(len(chunk)), chunk)
                self.assertEqual(new.read(1), b'')
            with self.assertRaises(FileExistsError):
                upgrade(source, dest, kernel)
            with self.assertRaises(FileExistsError):
                upgrade(source, source, kernel)
            kernel.write_bytes(bytes(16384))
            rejected = root / 'rejected.img'
            with self.assertRaises(ValueError):
                upgrade(source, rejected, kernel)
            self.assertFalse(rejected.exists())
            kernel.write_bytes(payload)
            with source.open('r+b') as file:
                file.seek(510)
                file.write(bytes(2))
            with self.assertRaises(ValueError):
                upgrade(source, rejected, kernel)
            self.assertFalse(rejected.exists())
