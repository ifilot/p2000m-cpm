#include "game.h"
#include "cpu.h"

#include <algorithm>
#include <array>
#include <cstdlib>
#include <iostream>
#include <random>
#include <stdexcept>
#include <vector>

using Board = std::array<uint8_t, OTHELLO_CELLS>;

static const int reference_directions[8][2] = {
    {-1, -1}, {0, -1}, {1, -1}, {-1, 0},
    {1, 0}, {-1, 1}, {0, 1}, {1, 1}
};

static void require(bool condition, const char *message)
{
    if (!condition)
        throw std::runtime_error(message);
}

static Board board_copy(const othello_game &game)
{
    Board board;
    std::copy(std::begin(game.board), std::end(game.board), board.begin());
    return board;
}

static uint8_t reference_flips(const Board &board, int x, int y,
                               uint8_t player)
{
    if (x < 0 || x >= 8 || y < 0 || y >= 8 || board[y * 8 + x])
        return 0;
    const uint8_t opponent = player == OTHELLO_HUMAN ?
        OTHELLO_CPU : OTHELLO_HUMAN;
    uint8_t total = 0;
    for (const auto &direction : reference_directions) {
        int scan_x = x + direction[0];
        int scan_y = y + direction[1];
        uint8_t line = 0;
        while (scan_x >= 0 && scan_x < 8 && scan_y >= 0 && scan_y < 8 &&
               board[scan_y * 8 + scan_x] == opponent) {
            ++line;
            scan_x += direction[0];
            scan_y += direction[1];
        }
        if (line && scan_x >= 0 && scan_x < 8 && scan_y >= 0 && scan_y < 8 &&
            board[scan_y * 8 + scan_x] == player)
            total += line;
    }
    return total;
}

static uint8_t reference_apply(Board &board, int x, int y, uint8_t player)
{
    const uint8_t total = reference_flips(board, x, y, player);
    if (!total)
        return 0;
    const uint8_t opponent = player == OTHELLO_HUMAN ?
        OTHELLO_CPU : OTHELLO_HUMAN;
    board[y * 8 + x] = player;
    for (const auto &direction : reference_directions) {
        int scan_x = x + direction[0];
        int scan_y = y + direction[1];
        std::vector<int> captured;
        while (scan_x >= 0 && scan_x < 8 && scan_y >= 0 && scan_y < 8 &&
               board[scan_y * 8 + scan_x] == opponent) {
            captured.push_back(scan_y * 8 + scan_x);
            scan_x += direction[0];
            scan_y += direction[1];
        }
        if (!captured.empty() && scan_x >= 0 && scan_x < 8 &&
            scan_y >= 0 && scan_y < 8 &&
            board[scan_y * 8 + scan_x] == player)
            for (const int index : captured)
                board[index] = player;
    }
    return total;
}

static unsigned validate_field(const othello_game &game)
{
    const Board original = board_copy(game);
    bool any_moves[3]{};
    for (const uint8_t player : {uint8_t(OTHELLO_HUMAN),
                                 uint8_t(OTHELLO_CPU)}) {
        uint8_t legal_count = 0;
        for (int y = 0; y < 8; ++y) {
            for (int x = 0; x < 8; ++x) {
                const uint8_t expected = reference_flips(original, x, y, player);
                require(othello_flips(&game, x, y, player) == expected,
                        "random field flip count differs from reference");
                require(bool(othello_is_legal(&game, x, y, player)) ==
                            bool(expected),
                        "random field legality differs from reference");
                othello_game actual = game;
                Board reference = original;
                require(othello_apply(&actual, x, y, player) ==
                            reference_apply(reference, x, y, player),
                        "random field apply count differs from reference");
                require(std::equal(std::begin(actual.board),
                                   std::end(actual.board), reference.begin()),
                        "random field resulting board differs from reference");
                if (expected)
                    ++legal_count;
            }
        }
        any_moves[player] = legal_count != 0;
        require(othello_legal_count(&game, player) == legal_count,
                "random field legal move total differs from reference");
        require(bool(othello_has_moves(&game, player)) == any_moves[player],
                "random field has-moves result differs from reference");
    }
    require(bool(othello_is_over(&game)) ==
                (!any_moves[OTHELLO_HUMAN] && !any_moves[OTHELLO_CPU]),
            "random field end-state result differs from reference");

    uint8_t human = 0, cpu = 0;
    othello_score(&game, &human, &cpu);
    require(human == std::count(original.begin(), original.end(), OTHELLO_HUMAN),
            "random field human score differs from board");
    require(cpu == std::count(original.begin(), original.end(), OTHELLO_CPU),
            "random field CPU score differs from board");

    uint8_t expected_x = 0, expected_y = 0, best_score = 0;
    bool expected_move = false;
    for (uint8_t y = 0; y < 8; ++y) {
        for (uint8_t x = 0; x < 8; ++x) {
            const uint8_t flips = reference_flips(original, x, y, OTHELLO_CPU);
            const bool corner = (x == 0 || x == 7) && (y == 0 || y == 7);
            const uint8_t score = flips + (corner ? 10 : 0);
            if (flips && (!expected_move || score > best_score)) {
                expected_move = true;
                expected_x = x;
                expected_y = y;
                best_score = score;
            }
        }
    }
    uint8_t actual_x = 255, actual_y = 255;
    require(bool(othello_cpu_choose(&game, &actual_x, &actual_y)) == expected_move,
            "random field CPU move availability differs from reference");
    if (expected_move)
        require(actual_x == expected_x && actual_y == expected_y,
                "random field CPU choice differs from reference heuristic");
    return 1;
}

static void opening_test()
{
    othello_game game;
    uint8_t human, cpu;
    othello_init(&game);
    othello_score(&game, &human, &cpu);
    require(human == 2 && cpu == 2, "opening score is not 2-2");
    require(othello_legal_count(&game, OTHELLO_HUMAN) == 4,
            "human should have four opening moves");
    require(othello_legal_count(&game, OTHELLO_CPU) == 4,
            "CPU should have four opening moves");
    require(!othello_is_legal(&game, 3, 3, OTHELLO_HUMAN),
            "occupied opening square accepted");
    require(!othello_is_legal(&game, 0, 0, OTHELLO_HUMAN),
            "non-capturing opening square accepted");
    require(othello_apply(&game, 4, 2, OTHELLO_HUMAN) == 1,
            "E3 opening move did not flip one disc");
    require(game.board[2 * OTHELLO_SIZE + 4] == OTHELLO_HUMAN &&
            game.board[3 * OTHELLO_SIZE + 4] == OTHELLO_HUMAN,
            "E3 opening move did not place and flip correctly");
    othello_score(&game, &human, &cpu);
    require(human == 4 && cpu == 1, "score after E3 is not 4-1");
}

static void eight_direction_test()
{
    othello_game game{};
    const int directions[8][2] = {
        {-1, -1}, {0, -1}, {1, -1}, {-1, 0},
        {1, 0}, {-1, 1}, {0, 1}, {1, 1}
    };
    for (const auto &direction : directions) {
        game.board[(3 + direction[1]) * OTHELLO_SIZE + 3 + direction[0]] =
            OTHELLO_CPU;
        game.board[(3 + 2 * direction[1]) * OTHELLO_SIZE +
                   3 + 2 * direction[0]] = OTHELLO_HUMAN;
    }
    require(othello_flips(&game, 3, 3, OTHELLO_HUMAN) == 8,
            "center move did not see all eight directions");
    require(othello_apply(&game, 3, 3, OTHELLO_HUMAN) == 8,
            "center move did not flip all eight directions");
    for (const auto &direction : directions)
        require(game.board[(3 + direction[1]) * OTHELLO_SIZE +
                           3 + direction[0]] == OTHELLO_HUMAN,
                "multi-direction flip left a CPU disc behind");
}

static void pass_and_end_test()
{
    othello_game game;
    for (auto &cell : game.board)
        cell = OTHELLO_HUMAN;
    game.board[0] = OTHELLO_EMPTY;
    game.board[1] = OTHELLO_CPU;
    require(othello_has_moves(&game, OTHELLO_HUMAN),
            "human pass fixture has no human move");
    require(!othello_has_moves(&game, OTHELLO_CPU),
            "CPU should have to pass");
    require(!othello_is_over(&game), "game ended while human could move");
    require(othello_apply(&game, 0, 0, OTHELLO_HUMAN) == 1,
            "final human move failed");
    require(othello_is_over(&game), "full board did not end the game");
}

static void cpu_choice_test()
{
    othello_game game;
    uint8_t x = 255, y = 255;
    othello_init(&game);
    require(othello_cpu_choose(&game, &x, &y),
            "CPU found no opening move");
    require(x == 3 && y == 2,
            "CPU tie-breaking is not deterministic row-major order");

    for (auto &cell : game.board)
        cell = OTHELLO_EMPTY;
    game.board[1] = OTHELLO_HUMAN;
    game.board[2] = OTHELLO_CPU;
    game.board[3 * OTHELLO_SIZE + 4] = OTHELLO_HUMAN;
    game.board[3 * OTHELLO_SIZE + 5] = OTHELLO_HUMAN;
    game.board[3 * OTHELLO_SIZE + 6] = OTHELLO_CPU;
    require(othello_cpu_choose(&game, &x, &y),
            "CPU found no move in corner fixture");
    require(x == 0 && y == 0, "CPU did not prefer an available corner");

    for (auto &cell : game.board)
        cell = OTHELLO_EMPTY;
    require(!othello_cpu_choose(&game, &x, &y),
            "CPU reported a move on an empty board");
}

static void randomized_field_tests()
{
    constexpr unsigned Seed = 0x2000c0de;
    constexpr int ArbitraryFields = 512;
    constexpr int CompleteGames = 200;
    std::mt19937 random(Seed);
    std::uniform_int_distribution<int> cell(OTHELLO_EMPTY, OTHELLO_CPU);
    unsigned reachable_fields = 0;

    for (int field = 0; field < ArbitraryFields; ++field) {
        othello_game game;
        for (auto &value : game.board)
            value = static_cast<uint8_t>(cell(random));
        validate_field(game);
    }

    for (int game_number = 0; game_number < CompleteGames; ++game_number) {
        othello_game game;
        othello_init(&game);
        uint8_t player = OTHELLO_HUMAN;
        unsigned passes = 0;
        for (unsigned ply = 0; ply < 128; ++ply) {
            reachable_fields += validate_field(game);
            std::vector<std::array<uint8_t, 2>> moves;
            for (uint8_t y = 0; y < 8; ++y)
                for (uint8_t x = 0; x < 8; ++x)
                    if (reference_flips(board_copy(game), x, y, player))
                        moves.push_back({x, y});
            if (moves.empty()) {
                if (++passes == 2)
                    break;
                player = othello_opponent(player);
                continue;
            }
            passes = 0;
            const auto &move = moves[random() % moves.size()];
            const Board before = board_copy(game);
            const uint8_t flips = reference_flips(before, move[0], move[1], player);
            require(othello_apply(&game, move[0], move[1], player) == flips,
                    "random playout move returned wrong flip count");
            const Board after = board_copy(game);
            require(std::count(after.begin(), after.end(), OTHELLO_EMPTY) + 1 ==
                        std::count(before.begin(), before.end(), OTHELLO_EMPTY),
                    "random playout move did not consume exactly one empty square");
            player = othello_opponent(player);
        }
        validate_field(game);
        require(othello_is_over(&game),
                "random playout did not reach a valid terminal position");
    }
    std::cout << "PASS: " << ArbitraryFields << " arbitrary fields and "
              << reachable_fields << " reachable fields from "
              << CompleteGames << " complete random games (seed 0x"
              << std::hex << Seed << std::dec << ")\n";
}

int main()
{
    try {
        opening_test();
        eight_direction_test();
        pass_and_end_test();
        cpu_choice_test();
        randomized_field_tests();
        std::cout << "PASS: Othello rules engine\n";
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return EXIT_FAILURE;
    }
}
