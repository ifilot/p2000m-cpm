// Exercise the complete Z88DK Othello game on the real machine model.
#define main cpm_regression_main
#include "cpm.cpp"
#undef main

static unsigned board_discs(P2000Machine &machine)
{
    const auto contents = screen(machine);
    unsigned count = 0;
    for (unsigned y = 0; y < 8; ++y)
        for (unsigned x = 0; x < 8; ++x) {
            const char cell = contents[(3 + y * 2) * 80 + 7 + x * 4];
            if (cell == 'O' || cell == 'X')
                ++count;
        }
    return count;
}

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
        type(machine, "J:OTHELLO\n");
        frames(machine, 40);
        wait_text(machine, "PRESS ENTER TO START");
        type(machine, "h");
        frames(machine, 20);
        wait_text(machine, "P2000M OTHELLO - HELP");
        wait_text(machine, "VERSION 0.2.0");
        wait_text(machine, "COMPILED ");
        wait_text(machine, "AUTHOR IVO FILOT");
        wait_text(machine, "The game ends when neither player can move.");
        type(machine, "h");
        frames(machine, 20);
        wait_text(machine, "PRESS ENTER TO START");
        type(machine, "\n");
        frames(machine, 40);
        wait_text(machine, "HUMAN vs CPU");
        wait_text(machine, "LEGAL MOVES:  4");
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
        require(playing[7 * 80 + 23] == '.',
                "E3 is not marked as a legal opening move");
        require(playing[9 * 80 + 19] == 'O' &&
                playing[9 * 80 + 23] == 'X',
                "standard opening discs are missing");
        type(machine, "h");
        frames(machine, 20);
        wait_text(machine, "P2000M OTHELLO - HELP");
        type(machine, "\n");
        frames(machine, 20);
        wait_text(machine, "LEGAL MOVES:  4");
        const auto restored = screen(machine);
        require(restored[9 * 80 + 19] == 'O' &&
                restored[9 * 80 + 23] == 'X',
                "returning from help changed the active board");
        type(machine, " ");
        frames(machine, 30);
        wait_text(machine, "Choose a square to outflank CPU discs.");
        wait_text(machine, "TURN: YOU");
        wait_text(machine, "YOU (O):  3");
        wait_text(machine, "CPU (X):  3");
        const auto moved = screen(machine);
        require(moved[7 * 80 + 23] == 'O', "E3 disc was not placed");
        require(moved[9 * 80 + 23] == 'O', "E4 disc was not flipped");
        require(moved[7 * 80 + 19] == 'X', "CPU did not place at D3");
        require(moved[9 * 80 + 19] == 'X', "CPU did not flip D4");
        type(machine, "q");
        frames(machine, 20);
        wait_text(machine, "QUIT GAME? (Y/N)");
        type(machine, "n");
        frames(machine, 20);
        wait_text(machine, "Choose a square to outflank CPU discs.");
        bool finished = false;
        for (int move = 0; move < 60 && !finished; ++move) {
            const unsigned before = board_discs(machine);
            type(machine, " ");
            bool roundComplete = false;
            for (int wait = 0; wait < 300 && !roundComplete; ++wait) {
                frames(machine, 5);
                const auto current = screen(machine);
                finished = current.find("ENTER: PLAY AGAIN") !=
                           std::string::npos;
                roundComplete = finished ||
                    (board_discs(machine) > before &&
                     current.find("TURN: YOU") != std::string::npos);
            }
            require(roundComplete, "Human/CPU round did not complete");
        }
        require(finished, "Automated human/CPU game did not finish");
        const auto result = screen(machine);
        require(result.find("YOU WIN!") != std::string::npos ||
                result.find("CPU WINS.") != std::string::npos ||
                result.find("DRAW GAME.") != std::string::npos,
                "Finished game did not display a result");
        type(machine, "q");
        frames(machine, 40);
        wait_text(machine, "A>");
        require(screen(machine).find("P2000M OTHELLO") == std::string::npos,
                "Othello screen was not cleared on exit");
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n' << screen(machine) << '\n';
        return 1;
    }
}
