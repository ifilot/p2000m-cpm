# README screenshots

`boot.png` shows the boot dashboard; `session.png` shows DIR, HELLO, and STAT.
Both render actual character/attribute RAM from the bundled emulator running
the built cartridge and SD image. These are emulator captures, not mockups or
photographs of physical hardware. The original character ROM is rendered at
2× integer scale with green text and the visible blink phase.

To regenerate, install Pillow, then run from the repository root:

```sh
python3 tools/build.py
python3 tools/capture_screenshots.py
```

The capture runs on a disposable copy of the SD template. Raw screen dumps
remain in `build/screenshot-*-characters.bin` and `*-attributes.bin`.
