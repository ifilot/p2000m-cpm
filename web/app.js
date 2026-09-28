(() => {
  "use strict";
  const ASSETS = [
    {name: "p2000.rom", size: 4096},
    {name: "cartridge.bin", size: 16 * 1024},
  ];
  const SD_ASSET = "p2000m-sd-template.img.gz";
  const SD_PATH = "/sd.img";
  const SD_SIZE = 160432128;
  const CHARACTER_ROMS = [
    {name: "charrom-upper.bin", scanlines: 8},
    {name: "charrom-lower.bin", scanlines: 4},
  ];
  const COLUMNS = 80;
  const ROWS = 24;
  const CELL_WIDTH = 8;
  const CELL_HEIGHT = 12;
  const NATIVE_WIDTH = COLUMNS * CELL_WIDTH;
  const NATIVE_HEIGHT = ROWS * CELL_HEIGHT;
  const DISPLAY_SCALE = 2;
  const VIDEO_BYTES = COLUMNS * ROWS;
  const FRAME_MS = 20;
  const FLASH_MS = 500;
  // Phosphor presets shared with the P2000M emulator's monitor settings.
  const THEMES = {
    green: {phosphor: [0x00, 0xff, 0x41], meta: "#020604"},
    amber: {phosphor: [0xff, 0xb0, 0x00], meta: "#070401"},
  };
  const THEME_STORAGE_KEY = "p2000m-theme";
  // Every published URL carries the build hash, so a rebuild is never mixed
  // with cached files from an older one (the cartridge and SD kernel must match).
  const BUILD = document.querySelector("#build").content;

  const terminal = document.querySelector("#terminal");
  const displayScreen = document.querySelector("#display-screen");
  const displayContext = displayScreen.getContext("2d", {alpha: false});
  const rasterScreen = document.createElement("canvas");
  rasterScreen.width = NATIVE_WIDTH;
  rasterScreen.height = NATIVE_HEIGHT;
  const rasterContext = rasterScreen.getContext("2d", {alpha: false});
  const raster = rasterContext.createImageData(NATIVE_WIDTH, NATIVE_HEIGHT);
  const rasterPixels = new Uint32Array(raster.data.buffer);

  const loading = document.querySelector("#loading");
  const loadingMessage = document.querySelector("#loading-message");
  const loadingProgress = document.querySelector("#loading-progress");
  const status = document.querySelector("#status");
  const powerLight = document.querySelector("#power-light");
  const diskLight = document.querySelector("#disk-light");
  const speed = document.querySelector("#speed");
  const themeToggle = document.querySelector("#theme-toggle");
  const themeColor = document.querySelector("#theme-color");
  const keyboard = window.P2000MKeyboard;

  let theme = document.documentElement.dataset.theme === "amber" ? "amber" : "green";
  let emulator = null;
  let characterRom = null;
  let running = false;
  let previousTime = 0;
  let frameBudget = 0;
  const previousVideo = new Uint8Array(VIDEO_BYTES * 2);
  let previousFlashPhase = null;
  let redraw = true;
  let diskFlashTimer = 0;

  function versioned(name) {
    return name + "?v=" + encodeURIComponent(BUILD);
  }

  function message(text, progress) {
    loadingMessage.textContent = text;
    loadingProgress.style.width = Math.max(2, Math.min(100, progress)) + "%";
    status.textContent = text;
  }

  function storeTheme() {
    try {
      localStorage.setItem(THEME_STORAGE_KEY, theme);
    } catch (_error) {
      // The toggle still works when browser storage is disabled.
    }
  }

  function applyTheme(nextTheme, persist = false) {
    theme = nextTheme === "amber" ? "amber" : "green";
    document.documentElement.dataset.theme = theme;
    themeToggle.setAttribute("aria-checked", theme === "amber" ? "true" : "false");
    themeColor.content = THEMES[theme].meta;
    redraw = true;
    if (persist) storeTheme();
    if (running) render(performance.now());
  }

  themeToggle.addEventListener("click", () => {
    applyTheme(theme === "green" ? "amber" : "green", true);
  });
  applyTheme(theme);

  async function fetchBytes(name, size) {
    const response = await fetch(versioned(name));
    if (!response.ok) throw new Error(name + ": HTTP " + response.status);
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.length !== size) {
      throw new Error(`${name}: expected ${size} bytes, received ${bytes.length}`);
    }
    return bytes;
  }

  async function loadCharacterRom() {
    characterRom = new Uint8Array(256 * CELL_HEIGHT);
    let offset = 0;
    for (const part of CHARACTER_ROMS) {
      const bytes = await fetchBytes(part.name, 256 * part.scanlines);
      characterRom.set(bytes, offset);
      offset += bytes.length;
    }
  }

  // Stream the compressed SD image straight into a preallocated file, so the
  // decompressed card exists only once in memory.
  async function loadSdImage() {
    if (typeof DecompressionStream !== "function") {
      throw new Error("This browser cannot decompress the SD-card image");
    }
    const response = await fetch(versioned(SD_ASSET));
    if (!response.ok || !response.body) {
      throw new Error(SD_ASSET + ": HTTP " + response.status);
    }
    const FS = emulator.FS;
    FS.writeFile(SD_PATH, new Uint8Array(0));
    FS.truncate(SD_PATH, SD_SIZE);
    const file = FS.open(SD_PATH, "r+");
    try {
      const reader = response.body
        .pipeThrough(new DecompressionStream("gzip"))
        .getReader();
      let position = 0;
      for (;;) {
        const {done, value} = await reader.read();
        if (done) break;
        if (position + value.length > SD_SIZE) throw new Error("SD-card image is too large");
        FS.write(file, value, 0, value.length, position);
        position += value.length;
        message("LOADING SD-CARD IMAGE…", 20 + 70 * position / SD_SIZE);
      }
      if (position !== SD_SIZE) {
        throw new Error(`SD-card image: expected ${SD_SIZE} bytes, received ${position}`);
      }
    } finally {
      FS.close(file);
    }
  }

  function videoChanged(bytes, offset) {
    for (let index = 0; index < bytes.length; index += 1) {
      if (bytes[index] !== previousVideo[offset + index]) return true;
    }
    return false;
  }

  function colour(red, green, blue) {
    return (0xff000000 | (blue << 16) | (green << 8) | red) >>> 0;
  }

  // Draws the P2000M's 80 by 24 text screen from its character ROM. Attribute
  // bit 0 selects the graphics bank, 1 underlines, 2 flashes and 3 inverts.
  function renderText(characters, attributes, flashBlank) {
    const [red, green, blue] = THEMES[theme].phosphor;
    const foreground = colour(red, green, blue);
    const background = colour(0, 0, 0);
    for (let cell = 0; cell < VIDEO_BYTES; cell += 1) {
      const attribute = attributes[cell] & 0x0f;
      const code = (characters[cell] & 0x7f) | ((attribute & 0x01) << 7);
      const hidden = flashBlank && (attribute & 0x04) !== 0;
      const left = (cell % COLUMNS) * CELL_WIDTH;
      const top = Math.floor(cell / COLUMNS) * CELL_HEIGHT;
      for (let scanline = 0; scanline < CELL_HEIGHT; scanline += 1) {
        let bits = hidden ? 0 : characterRom[scanline * 256 + code];
        if ((attribute & 0x02) !== 0 && scanline === 10) bits = 0xff;
        if ((attribute & 0x08) !== 0) bits ^= 0xff;
        let pixel = (top + scanline) * NATIVE_WIDTH + left;
        for (let mask = 0x80; mask !== 0; mask >>= 1) {
          rasterPixels[pixel] = (bits & mask) !== 0 ? foreground : background;
          pixel += 1;
        }
      }
    }
    rasterContext.putImageData(raster, 0, 0);
    displayContext.imageSmoothingEnabled = false;
    displayContext.drawImage(rasterScreen, 0, 0,
      NATIVE_WIDTH * DISPLAY_SCALE, NATIVE_HEIGHT * DISPLAY_SCALE);
  }

  function render(time) {
    const charactersPointer = emulator._p2000m_characters();
    const attributesPointer = emulator._p2000m_attributes();
    if (!charactersPointer || !attributesPointer) return;
    const characters = emulator.HEAPU8.subarray(charactersPointer, charactersPointer + VIDEO_BYTES);
    const attributes = emulator.HEAPU8.subarray(attributesPointer, attributesPointer + VIDEO_BYTES);
    const flashPhase = Math.floor(time / FLASH_MS) % 2 === 1;
    if (!redraw && flashPhase === previousFlashPhase &&
        !videoChanged(characters, 0) && !videoChanged(attributes, VIDEO_BYTES)) return;
    redraw = false;
    previousFlashPhase = flashPhase;
    previousVideo.set(characters);
    previousVideo.set(attributes, VIDEO_BYTES);
    renderText(characters, attributes, flashPhase);
  }

  function tick(time) {
    if (!running) return;
    const elapsed = previousTime ? Math.min(time - previousTime, 100) : FRAME_MS;
    previousTime = time;
    frameBudget += elapsed / FRAME_MS * Number(speed.value);
    const frames = Math.floor(frameBudget);
    frameBudget -= frames;
    if (frames > 0) emulator._p2000m_run_frames(frames);
    render(time);
    if (emulator._p2000m_sd_activity() !== 0) {
      diskLight.classList.add("on");
      clearTimeout(diskFlashTimer);
      diskFlashTimer = setTimeout(() => diskLight.classList.remove("on"), 90);
    }
    requestAnimationFrame(tick);
  }

  function queuePresses(presses) {
    if (!running || !presses) return;
    for (const [row, bit, shifted] of presses) {
      emulator._p2000m_queue_key(row, bit, shifted ? 1 : 0);
    }
  }

  terminal.addEventListener("keydown", event => {
    const lowerKey = event.key.toLowerCase();
    // Leave the browser's paste shortcut alone; the paste event types the text.
    if ((event.ctrlKey || event.metaKey) && lowerKey === "v") return;
    const presses = keyboard.event(event);
    if (!presses) return;
    event.preventDefault();
    // Held keys repeat, but never let the backlog outrun the machine.
    if (event.repeat && running && emulator._p2000m_pending_keys() > 1) return;
    queuePresses(presses);
  });
  document.addEventListener("paste", event => {
    if (document.activeElement !== terminal) return;
    event.preventDefault();
    queuePresses(keyboard.text(event.clipboardData.getData("text")));
  });
  document.querySelector("#reset").addEventListener("click", () => {
    if (!running) return;
    emulator._p2000m_reset();
    redraw = true;
    status.textContent = "Machine reset. Booting from the SD card…";
    terminal.focus();
  });

  async function start() {
    try {
      if (typeof createP2000M !== "function") throw new Error("WebAssembly loader unavailable");
      if (!keyboard) throw new Error("Keyboard map unavailable");
      message("LOADING P2000M CHARACTER GENERATOR…", 2);
      await loadCharacterRom();
      message("INITIALISING WEBASSEMBLY…", 5);
      emulator = await createP2000M({
        locateFile: versioned,
        printErr: text => console.error(text),
      });
      for (let index = 0; index < ASSETS.length; index += 1) {
        const asset = ASSETS[index];
        message(`LOADING ${asset.name.toUpperCase()}…`, 10 + index * 5);
        emulator.FS.writeFile("/" + asset.name, await fetchBytes(asset.name, asset.size));
      }
      message("LOADING SD-CARD IMAGE…", 20);
      await loadSdImage();
      message("INSERTING CARTRIDGES…", 95);
      if (!emulator._p2000m_init()) {
        throw new Error(emulator.UTF8ToString(emulator._p2000m_last_error()));
      }
      message("BOOTING PHILIPS P2000M…", 100);
      loading.hidden = true;
      powerLight.classList.add("on");
      status.textContent = "Running · click the display for keyboard input";
      running = true;
      terminal.focus();
      requestAnimationFrame(tick);
    } catch (error) {
      console.error(error);
      message("EMULATOR ERROR: " + error.message, 100);
      loadingProgress.classList.add("failed");
      status.textContent = "Could not start the browser emulator.";
    }
  }
  start();
})();
