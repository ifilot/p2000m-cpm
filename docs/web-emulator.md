# Browser emulator

The [browser emulator](https://ifilot.github.io/p2000m-cpm/) runs the bundled
headless P2000M core (`tests/emulator`) as WebAssembly. It installs the CP/M
co-board and SD/SRAM cartridge, and boots the freshly built `cartridge.bin` and
`p2000m-sd-template.img` exactly as the hardware would. The page is in English;
a GREEN/AMBER switch selects the phosphor colour of both the page and the
emulated monitor, and the choice is remembered in the browser.

## Building locally

Build the firmware first (see the [README](../README.md)), then activate an
[Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html)
and assemble the site:

```sh
python3 tools/build.py
source /path/to/emsdk/emsdk_env.sh
python3 tools/build_site.py            # writes build/site
node tools/test_web_emulator.js        # headless boot and keyboard check
python3 -m http.server -d build/site   # open http://localhost:8000/
```

`tools/build_site.py --emulator PATH` reuses a prebuilt `PATH.js`/`PATH.wasm`
instead of running Emscripten. CI pins the SDK version in
`.github/workflows/build.yml`.

## Files

| Path | Purpose |
| --- | --- |
| `web/wasm/p2000m_web.cpp` | Emscripten entry point: machine setup, frames, key replay |
| `web/keyboard.js` | Browser key and text to keyboard-matrix translation |
| `web/app.js` | Asset loading, display rendering, timing, and controls |
| `web/index.html`, `web/style.css` | Page and both colour themes |
| `tools/build_site.py` | Compiles the emulator and assembles `build/site` |
| `tools/test_web_emulator.js` | Boots the assembled site headlessly in Node |

The site publishes the monitor ROM, cartridge, both character-ROM halves, and
the gzip-compressed SD image (under 1 MiB). The page streams the image through
`DecompressionStream` into a preallocated in-memory file, so the 153 MiB card
exists once in browser memory. Changes to the SD card last until the page is
reloaded.

## Display

The renderer follows the P2000M emulator: 80 by 24 cells of 8 by 12 pixels
from the recovered character ROM, drawn at 640 by 288 and scaled by exactly
two. Attribute bit 0 selects the graphics glyph bank, bit 1 underlines on
scanline 10, bit 2 flashes at 1 Hz, and bit 3 inverts the cell. Green is
`#00ff41` and amber `#ffb000`, the same presets as the emulator's monitor menu.

## Keyboard

Keys are not injected as bytes. `web/keyboard.js` chooses the physical matrix
key, with or without left Shift, that produces each character. The WebAssembly
side then holds it for two 50 Hz frames and releases it for two, which the
cartridge's interrupt-driven scanner debounces and translates using its own
tables. `tests/test_site.py` checks that the JavaScript tables match
`keys_normal` and `keys_shift` in `src/console.asm`.

The P2000M has no Ctrl key. CP/M control characters are typed with the
cartridge's Escape prefix, so browser `Ctrl+letter` is sent as Escape followed
by that letter; a single Escape key press arms the prefix, and a second sends
Escape itself. Characters the P2000M keyboard cannot produce (such as `{`, `\`,
`^` or `~`) are ignored. Pasted text is typed through the same mapping.
