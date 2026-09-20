#!/usr/bin/env python3
"""Fast host-side tests for the platform-neutral Othello rules engine."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class OthelloRules(unittest.TestCase):
    def test_rules_engine(self):
        output = ROOT / 'build' / 'othello-game-test'
        output.parent.mkdir(exist_ok=True)
        subprocess.run([
            'g++', '-std=c++17', '-O2',
            '-I' + str(ROOT / 'programs' / 'othello'),
            str(ROOT / 'tests' / 'othello_game.cpp'),
            str(ROOT / 'programs' / 'othello' / 'game.c'),
            str(ROOT / 'programs' / 'othello' / 'cpu.c'),
            '-o', str(output),
        ], check=True)
        subprocess.run([str(output)], check=True)


if __name__ == '__main__':
    unittest.main(verbosity=2)
