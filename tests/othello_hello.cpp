// Smoke-test a Z88DK-generated CP/M COM program on the real P2000M model.
#include "p2000_machine.h"

#include <stdexcept>
#include <string>

static void frames(P2000Machine &machine, int count)
{
    while (count--)
        machine.runFrame();
}

static std::string screen(const P2000Machine &machine)
{
    return std::string(reinterpret_cast<const char *>(machine.characters()), 1920);
}

static void type(P2000Machine &machine, const std::string &text)
{
    static const std::string matrix =
        " 6 Q3574" " HZSDGJF" "   0# , " " N<XCBMV" " YAWETUR"
        " 9+- 01-" "9O87 P8@" "3.21]/K2" "6L54 ;I:";
    for (char key : text) {
        bool shift = key >= 'A' && key <= 'Z';
        if (key >= 'a' && key <= 'z') key -= 'a' - 'A';
        unsigned position = key == '\n' ? 6 * 8 + 4 : matrix.find(key);
        if (position >= matrix.size()) throw std::runtime_error("Unsupported test key");
        machine.setKey(9, 0, shift); frames(machine, 2);
        machine.setKey(position / 8, position % 8, true); frames(machine, 2);
        machine.setKey(position / 8, position % 8, false); frames(machine, 2);
        machine.setKey(9, 0, false); frames(machine, 2);
    }
}

int main(int argc, char **argv)
{
    if (argc != 4)
        throw std::runtime_error("Usage: othello-hello-test EMULATOR BUILD CARD");
    P2000Machine machine;
    std::string error;
    if (!machine.loadMonitor(std::string(argv[1]) + "/assets/roms/p2000.rom", &error) ||
        !machine.loadCartridge(std::string(argv[2]) + "/cartridge.bin", &error))
        throw std::runtime_error(error);
    machine.installCoBoard();
    machine.sdCartridge().install();
    if (!machine.sdCartridge().insert(argv[3], false, &error))
        throw std::runtime_error(error);
    frames(machine, 700);
    type(machine, "HELLO\n");
    frames(machine, 150);
    if (screen(machine).find("Hello from Z88DK on P2000M CP/M!") == std::string::npos)
        throw std::runtime_error("Z88DK Hello World did not execute");
}
