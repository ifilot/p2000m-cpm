#!/usr/bin/env node
// Boot the assembled browser site's WebAssembly emulator headlessly in Node.
// Uses the site's own assets and web/keyboard.js, so it checks the published
// files, the SD boot, and browser-key translation through the cartridge.
"use strict";
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const site = path.resolve(process.argv[2] || path.join(__dirname, "../build/site"));
const keyboard = require(path.join(site, "keyboard.js"));
const createP2000M = require(path.join(site, "p2000m-web.js"));
// Native glyph codes that CONOUT substitutes for CP/M ASCII punctuation.
const NATIVE = {0x5f: "#", 0x60: "_", 0x0f: "[", 0x10: "]", 0x0a: "`"};

function fail(message, emulator) {
  if (emulator) console.error(screen(emulator));
  throw new Error(message);
}

function screen(emulator) {
  const pointer = emulator._p2000m_characters();
  const bytes = emulator.HEAPU8.subarray(pointer, pointer + 1920);
  const rows = [];
  for (let row = 0; row < 24; row += 1) {
    rows.push(Array.from(bytes.subarray(row * 80, row * 80 + 80), value =>
      NATIVE[value] ?? (value >= 32 && value < 127 ? String.fromCharCode(value) : " ")
    ).join("").trimEnd());
  }
  return rows.join("\n");
}

function waitFor(emulator, text, frames = 1500) {
  for (let frame = 0; frame < frames; frame += 10) {
    emulator._p2000m_run_frames(10);
    if (emulator._p2000m_pending_keys() === 0 && screen(emulator).includes(text)) return;
  }
  fail(`Timed out waiting for ${JSON.stringify(text)}`, emulator);
}

function type(emulator, text) {
  const presses = keyboard.text(text);
  if (presses.length === 0) fail(`No keys for ${JSON.stringify(text)}`);
  for (const [row, bit, shifted] of presses) emulator._p2000m_queue_key(row, bit, shifted ? 1 : 0);
}

async function main() {
  const emulator = await createP2000M({
    locateFile: name => path.join(site, name),
    printErr: text => console.error(text),
  });
  emulator.FS.writeFile("/p2000.rom", fs.readFileSync(path.join(site, "p2000.rom")));
  emulator.FS.writeFile("/cartridge.bin", fs.readFileSync(path.join(site, "cartridge.bin")));
  emulator.FS.writeFile("/sd.img",
    zlib.gunzipSync(fs.readFileSync(path.join(site, "p2000m-sd-template.img.gz"))));
  if (!emulator._p2000m_init()) {
    fail(emulator.UTF8ToString(emulator._p2000m_last_error()));
  }
  waitFor(emulator, "BOOT COMPLETE");
  waitFor(emulator, "A>");
  console.log("PASS: browser emulator boots CP/M from the SD image");

  type(emulator, "hello\n");
  waitFor(emulator, "Hello from an original Z80");
  type(emulator, "stat\n");
  waitFor(emulator, "R/W, Space:");
  console.log("PASS: typed commands run HELLO and STAT");

  // Every mapped printable character must survive the cartridge translation.
  const printable = [];
  for (let value = 33; value < 127; value += 1) {
    const character = String.fromCharCode(value);
    if (keyboard.character(character)) printable.push(character);
  }
  // Two halves keep each probe on one 80-column screen row.
  const half = Math.ceil(printable.length / 2);
  for (const probe of [printable.slice(0, half), printable.slice(half)].map(part => part.join(""))) {
    type(emulator, probe);
    waitFor(emulator, "A>" + probe);
    type(emulator, "\x18");  // Ctrl-X (Escape, X) cancels the probe line.
  }
  type(emulator, "b:\n");
  waitFor(emulator, "B>");
  console.log(`PASS: ${printable.length} printable characters and control prefix typed exactly`);

  emulator._p2000m_reset();
  waitFor(emulator, "BOOT COMPLETE");
  console.log("PASS: reset reboots from the SD image");
}

main().catch(error => {
  console.error(error.message);
  process.exit(1);
});
