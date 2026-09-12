// Reuse the regression harness's keyboard injection and prompt waiting.
#define main cpm_regression_main
#include "cpm.cpp"
#undef main
#include <fstream>

static void capture(P2000Machine &machine, const std::string &base) {
    for (const auto &part : {std::string("characters"), std::string("attributes")}) {
        std::ofstream out(base + "-" + part + ".bin", std::ios::binary);
        out.write(reinterpret_cast<const char *>(part == "characters"
            ? machine.characters() : machine.attributes()), 1920);
        require(bool(out), "Cannot write screen capture");
    }
}

int main(int argc, char **argv) {
    try {
        require(argc == 4, "Usage: screenshots-test EMULATOR BUILD SCRATCH_CARD");
        P2000Machine machine;
        std::string error;
        require(machine.loadMonitor(std::string(argv[1]) + "/assets/roms/p2000.rom", &error), error);
        require(machine.loadCartridge(std::string(argv[2]) + "/cartridge.bin", &error), error);
        machine.installCoBoard();
        machine.sdCartridge().install();
        require(machine.sdCartridge().insert(argv[3], false, &error), error);
        frames(machine, 700);
        prompt(machine);
        require(screen(machine).find("BOOT COMPLETE") != std::string::npos, "Boot failed");
        capture(machine, std::string(argv[2]) + "/screenshot-boot");
        type(machine, "DIR\n"); prompt(machine);
        type(machine, "HELLO\n"); prompt(machine);
        require(screen(machine).find("Hello from an original Z80") != std::string::npos,
                "HELLO did not execute");
        type(machine, "STAT\n"); prompt(machine);
        require(screen(machine).find("R/W, Space:") != std::string::npos, "STAT failed");
        capture(machine, std::string(argv[2]) + "/screenshot-session");
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
