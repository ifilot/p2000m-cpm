// Browser keys to P2000M keyboard-matrix positions.
//
// The tables mirror keys_normal/keys_shift in src/console.asm (rows 0-8,
// bits 0-7); tests/test_site.py keeps them identical. The emulated cartridge
// performs the real translation, so this file only chooses which physical
// key, with or without Shift, produces a wanted character.
(function (global) {
  "use strict";
  const NORMAL = [
    [8, "6", 11, "q", "3", "5", "7", "4"],
    [9, "h", "z", "s", "d", "g", "j", "f"],
    [".", " ", 0, "0", "#", 10, ",", 12],
    [0, "n", "<", "x", "c", "b", "m", "v"],
    [27, "y", "a", "w", "e", "t", "u", "r"],
    [0, "9", "+", "-", 8, "0", "1", "-"],
    ["9", "o", "8", "7", 13, "p", "8", "@"],
    ["3", ".", "2", "1", "]", "/", "k", "2"],
    ["6", "l", "5", "4", 39, ";", "i", ":"],
  ];
  const SHIFTED = [
    [8, "&", 11, "Q", "#", "%", 39, "$"],
    [9, "H", "Z", "S", "D", "G", "J", "F"],
    [".", " ", 0, "=", "#", 10, ",", 12],
    [0, "N", ">", "X", "C", "B", "M", "V"],
    [27, "Y", "A", "W", "E", "T", "U", "R"],
    [0, ")", "*", "/", 8, "=", "!", "_"],
    ["9", "O", "8", "7", 13, "P", "(", 39],
    ["3", ".", "2", "1", "[", "?", "K", 34],
    ["6", "L", "5", "4", 96, "+", "I", "*"],
  ];
  // Numeric-pad contacts; the main keyboard is preferred for shared symbols.
  const KEYPAD = new Set(["2,0", "2,3", "5,2", "5,3", "6,0", "6,2", "6,3",
    "7,0", "7,2", "7,3", "8,0", "8,2", "8,3"]);
  // Physical keys whose control codes are not ordinary typed characters.
  const SPECIAL = {
    ArrowLeft: [0, 0], ArrowUp: [0, 2], ArrowDown: [2, 5], ArrowRight: [2, 7],
    Tab: [1, 0], Escape: [4, 0], Backspace: [5, 4], Enter: [6, 4],
  };
  const ESCAPE = [4, 0, false];
  const CHARACTERS = new Map();

  function code(entry) {
    return typeof entry === "number" ? entry : entry.charCodeAt(0);
  }

  for (const keypad of [false, true]) {
    for (const [table, shifted] of [[NORMAL, false], [SHIFTED, true]]) {
      table.forEach((row, rowIndex) => row.forEach((entry, bit) => {
        const value = code(entry);
        if (value < 32 || KEYPAD.has(rowIndex + "," + bit) !== keypad) return;
        const character = String.fromCharCode(value);
        if (!CHARACTERS.has(character)) CHARACTERS.set(character, [rowIndex, bit, shifted]);
      }));
    }
  }

  // Returns [row, bit, shifted] matrix presses for one character, or null.
  // Control characters use the P2000M CP/M prefix: Escape, then the letter.
  function character(value) {
    if (value === "\n" || value === "\r") return [[6, 4, false]];
    if (value === "\t") return [[1, 0, false]];
    if (value === "\x1b") return [ESCAPE, ESCAPE];
    const direct = CHARACTERS.get(value);
    if (direct) return [direct];
    const byte = value.charCodeAt(0);
    if (value.length === 1 && byte >= 1 && byte <= 26) {
      return [ESCAPE, CHARACTERS.get(String.fromCharCode(byte + 96))];
    }
    return null;
  }

  // Translates a KeyboardEvent-like object; null means "not handled".
  function event(keyEvent) {
    if (keyEvent.altKey || keyEvent.metaKey) return null;
    if (keyEvent.ctrlKey) {
      const letter = keyEvent.key.length === 1 ? keyEvent.key.toLowerCase() : "";
      if (letter === "[") return [ESCAPE];
      if (letter < "a" || letter > "z") return null;
      return [ESCAPE, CHARACTERS.get(letter)];
    }
    const special = SPECIAL[keyEvent.key];
    if (special) return [[special[0], special[1], false]];
    return keyEvent.key.length === 1 ? character(keyEvent.key) : null;
  }

  // Translates pasted text; unknown characters are skipped.
  function text(value) {
    const presses = [];
    for (const item of value.replace(/\r\n?/g, "\n")) {
      const keys = character(item);
      if (keys) presses.push(...keys);
    }
    return presses;
  }

  const keyboard = {NORMAL, SHIFTED, character, event, text};
  if (typeof module === "object" && module.exports) module.exports = keyboard;
  else global.P2000MKeyboard = keyboard;
})(typeof window === "object" ? window : globalThis);
