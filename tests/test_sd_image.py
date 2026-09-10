import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))

spec = importlib.util.spec_from_file_location('sd_image', Path(__file__).parents[1] / 'tools/sd_image.py')
sd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sd)


class ImageTests(unittest.TestCase):
    def test_kernel_install_preserves_everything_outside_boot_region(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'card.img'
            # Patterned reserved space reveals accidental writes outside the
            # exact new header/payload range, including the old 16 KiB tail.
            original = bytes(range(256)) * (1024 * 1024 // 256)
            path.write_bytes(original)
            kernel = bytearray(sd.LAYOUT['kernel_bytes'])
            kernel[3:11] = b'P2MCPM02'
            sd.install_kernel(path, kernel)
            actual = path.read_bytes()
            end = (16 + sd.LAYOUT['kernel_sectors']) * 512
            self.assertEqual(actual[:15*512], original[:15*512])
            self.assertEqual(actual[end:], original[end:])
            self.assertEqual(actual[15*512:15*512+8], b'P2MSYS02')
            self.assertEqual(actual[16*512:end], kernel)
            self.assertEqual(struct.unpack_from('<HH', actual, 15*512+8),
                             (len(kernel), sum(kernel) & 0xffff))
            before = path.read_bytes()
            with self.assertRaises(ValueError):
                sd.install_kernel(path, bytes(16384))
            self.assertEqual(path.read_bytes(), before)

    def test_partition_and_fat_structure(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'card.img'
            sd.create_image(path)
            self.assertEqual(path.stat().st_size, 153 * 1024 * 1024)
            with path.open('rb') as card:
                mbr = card.read(512)
                self.assertEqual(mbr[510:], b'\x55\xaa')
                parts = [struct.unpack_from('<B3sB3sII', mbr, 446 + i * 16) for i in range(2)]
                self.assertEqual([(p[2], p[4], p[5]) for p in parts],
                                 [(12, 2048, 131072), (82, 133120, 180224)])
                self.assertEqual(mbr[478:510], bytes(32))
                def sector(lba):
                    card.seek(lba * 512)
                    return card.read(512)
                boot = sector(parts[0][4])
                self.assertEqual(boot, sector(2054))
                self.assertEqual(boot[510:], b'\x55\xaa')
                bps = struct.unpack_from('<H', boot, 11)[0]
                spc = boot[13]
                reserved = struct.unpack_from('<H', boot, 14)[0]
                fats = boot[16]
                count = struct.unpack_from('<I', boot, 32)[0]
                fat_size = struct.unpack_from('<I', boot, 36)[0]
                self.assertEqual((bps, spc, reserved, fats, count), (512, 1, 32, 2, 131072))
                clusters = (count - reserved - fats * fat_size) // spc
                self.assertGreaterEqual(clusters, 65525)
                self.assertGreaterEqual(fat_size * bps // 4, clusters + 2)
                info = sector(2049)
                self.assertEqual(info, sector(2055))
                self.assertEqual(struct.unpack_from('<III', info, 484), (0x61417272, clusters - 1, 3))
                first_fat = sector(2048 + reserved)
                self.assertEqual(first_fat, sector(2048 + reserved + fat_size))
                self.assertEqual(struct.unpack_from('<III', first_fat), (0x0ffffff8, 0xffffffff, 0x0fffffff))
                root = sector(2048 + reserved + fats * fat_size)
                self.assertEqual(root[:12], b'P2000M DATA\x08')
                self.assertEqual(root[32], 0)
                for part in parts[1:]:
                    self.assertEqual(sector(part[4]), b'\xe5' * 512)
                    self.assertEqual(sector(part[4] + part[5] - 1), b'\xe5' * 512)
            with self.assertRaises(FileExistsError):
                sd.create_image(path)

    def test_file_extent_roundtrip(self):
        # Decode using CP/M extent semantics, independently of the writer.
        for length in (0, 1, 128, 16384, 16385, 32768, 32769, 524417):
            with self.subTest(length=length), tempfile.TemporaryDirectory() as tmp:
                file = Path(tmp) / 'TEST.BIN'
                data = bytes((i * 17 + i // 16384) & 255 for i in range(length))
                file.write_bytes(data)
                volume = sd.make_volume([file])
                recovered = bytearray()
                for offset in range(0, 16384, 32):
                    entry = volume[offset:offset + 32]
                    if entry[0] == 0xe5:
                        break
                    self.assertEqual(entry[1:12], b'TEST    BIN')
                    extent = entry[12] + 32 * entry[14]
                    self.assertEqual((extent & ~1) * 16384, len(recovered))
                    size = ((extent & 1) * 128 + entry[15]) * 128
                    chunk = bytearray()
                    for block in struct.unpack_from('<8H', entry, 16):
                        if block:
                            chunk.extend(volume[block * 4096:(block + 1) * 4096])
                    recovered.extend(chunk[:size])
                self.assertEqual(recovered[:length], data)
                self.assertEqual(recovered[length:], b'\x1a' * ((-length) % 128))

    def test_reject_invalid_files(self):
        for name in ('TOOLONGNAME.COM', 'A.B.C', 'A*.COM', '.COM'):
            with self.assertRaises(ValueError):
                sd.disk_name(name)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'DUP.COM'
            path.write_bytes(b'')
            with self.assertRaises(ValueError):
                sd.make_volume([path, path])


if __name__ == '__main__':
    unittest.main()
