// Exercise the Z88DK Othello terminal prototype on the real machine model.
#define main cpm_regression_main
#include "cpm.cpp"
#undef main

int main(int argc, char **argv)
{
    P2000Machine machine;
    try {
        require(argc == 4, "Usage: othello-ui-test EMULATOR BUILD CARD");
        std::string error;
        require(machine.loadMonitor(std::string(argv[1]) + "/assets/roms/p2000.rom", &error), error);
        require(machine.loadCartridge(std::string(argv[2]) + "/cartridge.bin", &error), error);
        machine.installCoBoard();
        machine.sdCartridge().install();
        require(machine.sdCartridge().insert(argv[3], false, &error), error);
        frames(machine, 700);
        prompt(machine);
        type(machine, "OTHELLO\n");
        frames(machine, 40);
        wait_text(machine, "PRESS ENTER TO START");
        type(machine, "\n");
        frames(machine, 40);
        wait_text(machine, "HUMAN vs CPU");
        wait_text(machine, "LEGAL MOVES: 5");
        const std::string grid = "+---+---+---+---+---+---+---+---+";
        const auto playing = screen(machine);
        for (unsigned row = 2; row <= 18; row += 2)
            require(playing.substr(row * 80 + 5, grid.size()) == grid,
                    "Othello horizontal grid line is missing or misaligned");
        for (unsigned column = 5; column <= 37; column += 4)
            require(playing[3 * 80 + column] == '|',
                    "Othello vertical grid line is misaligned");
        for (unsigned column = 7, letter = 'A'; column <= 35;
             column += 4, ++letter)
            require(playing[1 * 80 + column] == letter,
                    "Othello column heading is misaligned");
        type(machine, "q");
        frames(machine, 20);
        wait_text(machine, "QUIT GAME? (Y/N)");
        type(machine, "n");
        frames(machine, 20);
        wait_text(machine, "Choose a square to outflank CPU discs.");
        type(machine, "q");
        type(machine, "y");
        frames(machine, 40);
        wait_text(machine, "A>");
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n' << screen(machine) << '\n';
        return 1;
    }
}
