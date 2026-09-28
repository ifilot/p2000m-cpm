// WebAssembly entry point for the browser emulator.
//
// Wraps the bundled headless P2000M core (tests/emulator) with the CP/M
// co-board and SD/SRAM cartridge installed. The page writes the monitor ROM,
// cartridge and SD image into the Emscripten filesystem before p2000m_init().
// Typed keys are replayed through the real keyboard matrix, one key at a
// time, so the cartridge's own interrupt scanner and tables translate them.
#include <cstdint>
#include <deque>
#include <memory>
#include <string>

#include <emscripten/emscripten.h>

#include "p2000_machine.h"

namespace {

constexpr int ShiftRow = 9;
constexpr int LeftShiftBit = 0;
// The cartridge debounces each matrix bit over two equal 50 Hz samples.
constexpr int PressFrames = 2;
constexpr int ReleaseFrames = 2;

struct MatrixKey {
    int row;
    int bit;
    bool shifted;
};

std::unique_ptr<P2000Machine> machine;
std::string lastError;
std::deque<MatrixKey> pendingKeys;
int keyFrame = 0;
std::uint8_t sdActivity = 0;

int fail(const std::string &message)
{
    lastError = message;
    machine.reset();
    return 0;
}

void releaseKey(const MatrixKey &key)
{
    machine->setKey(key.row, key.bit, false);
    machine->setKey(ShiftRow, LeftShiftBit, false);
}

// Hold the front key (with Shift when required), then release it long enough
// for the debouncer to see the release before the next key is pressed.
void advanceKeyboard()
{
    if (pendingKeys.empty())
        return;
    const MatrixKey &key = pendingKeys.front();
    if (keyFrame == 0) {
        machine->setKey(ShiftRow, LeftShiftBit, key.shifted);
        machine->setKey(key.row, key.bit, true);
    } else if (keyFrame == PressFrames) {
        releaseKey(key);
    }
    if (++keyFrame == PressFrames + ReleaseFrames) {
        pendingKeys.pop_front();
        keyFrame = 0;
    }
}

} // namespace

extern "C" {

EMSCRIPTEN_KEEPALIVE int p2000m_init()
{
    machine = std::make_unique<P2000Machine>();
    pendingKeys.clear();
    keyFrame = 0;
    if (!machine->loadMonitor("/p2000.rom", &lastError) ||
        !machine->loadCartridge("/cartridge.bin", &lastError))
        return fail(lastError);
    machine->installCoBoard();
    machine->sdCartridge().install();
    if (!machine->sdCartridge().insert("/sd.img", false, &lastError))
        return fail(lastError);
    machine->reset();
    lastError.clear();
    return 1;
}

EMSCRIPTEN_KEEPALIVE const char *p2000m_last_error()
{
    return lastError.c_str();
}

EMSCRIPTEN_KEEPALIVE void p2000m_reset()
{
    if (!machine)
        return;
    pendingKeys.clear();
    keyFrame = 0;
    machine->reset();
}

EMSCRIPTEN_KEEPALIVE void p2000m_run_frames(std::uint32_t frames)
{
    if (!machine)
        return;
    while (frames--) {
        advanceKeyboard();
        machine->runFrame();
        sdActivity |= machine->sdCartridge().leds();
    }
}

EMSCRIPTEN_KEEPALIVE void p2000m_queue_key(int row, int bit, int shifted)
{
    if (machine && row >= 0 && row < ShiftRow && bit >= 0 && bit < 8)
        pendingKeys.push_back({row, bit, shifted != 0});
}

EMSCRIPTEN_KEEPALIVE std::uint32_t p2000m_pending_keys()
{
    return static_cast<std::uint32_t>(pendingKeys.size());
}

EMSCRIPTEN_KEEPALIVE void p2000m_clear_keys()
{
    if (!machine)
        return;
    if (keyFrame != 0 && !pendingKeys.empty())
        releaseKey(pendingKeys.front());
    pendingKeys.clear();
    keyFrame = 0;
}

EMSCRIPTEN_KEEPALIVE std::uintptr_t p2000m_characters()
{
    return machine ? reinterpret_cast<std::uintptr_t>(machine->characters()) : 0;
}

EMSCRIPTEN_KEEPALIVE std::uintptr_t p2000m_attributes()
{
    return machine ? reinterpret_cast<std::uintptr_t>(machine->attributes()) : 0;
}

// Returns the SD/SRAM cartridge LEDs lit since the previous call.
EMSCRIPTEN_KEEPALIVE int p2000m_sd_activity()
{
    const int activity = sdActivity;
    sdActivity = 0;
    return activity;
}

} // extern "C"
