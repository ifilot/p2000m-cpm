/*
 * Platform-neutral Othello rules engine.
 *
 * Board inspection and mutation live here rather than in the terminal UI.
 * Legality follows the standard rule: an empty square must bracket at least
 * one uninterrupted opponent run against one of the moving player's discs.
 * Passing is represented by the absence of legal moves; a game ends only
 * when both players lack a move, which also covers a completely full board.
 */
#include "game.h"

#include <string.h>

/* Direction vectors cover every horizontal, vertical, and diagonal ray. */
static const int8_t directions[8][2] = {
    {-1, -1}, {0, -1}, {1, -1},
    {-1,  0},           {1,  0},
    {-1,  1}, {0,  1}, {1,  1}
};

/* Test signed scan coordinates before converting them into a board index. */
static uint8_t inside(int8_t x, int8_t y)
{
    return x >= 0 && x < OTHELLO_SIZE && y >= 0 && y < OTHELLO_SIZE;
}

/* Read a cell after the caller has established that its coordinates are valid. */
static uint8_t at(const struct othello_game *game, int8_t x, int8_t y)
{
    return game->board[(uint8_t)y * OTHELLO_SIZE + (uint8_t)x];
}

/*
 * Clear all cells and place the conventional diagonal pair of discs for each
 * player.  The human owns D4/E5 and therefore has the first move.
 */
void othello_init(struct othello_game *game)
{
    memset(game->board, OTHELLO_EMPTY, sizeof(game->board));
    game->board[3 * OTHELLO_SIZE + 3] = OTHELLO_HUMAN;
    game->board[3 * OTHELLO_SIZE + 4] = OTHELLO_CPU;
    game->board[4 * OTHELLO_SIZE + 3] = OTHELLO_CPU;
    game->board[4 * OTHELLO_SIZE + 4] = OTHELLO_HUMAN;
}

/* Map either valid player constant to the other player constant. */
uint8_t othello_opponent(uint8_t player)
{
    return player == OTHELLO_HUMAN ? OTHELLO_CPU : OTHELLO_HUMAN;
}

/*
 * Probe all eight rays from an empty candidate square.  A ray contributes its
 * consecutive opponent discs only when they terminate at one of the current
 * player's discs.  Reaching an edge or empty square invalidates that ray.
 * No board bytes are modified, making this routine safe for move generation.
 */
uint8_t othello_flips(const struct othello_game *game, uint8_t x, uint8_t y,
                      uint8_t player)
{
    uint8_t direction;
    uint8_t total = 0;
    const uint8_t opponent = othello_opponent(player);
    if (x >= OTHELLO_SIZE || y >= OTHELLO_SIZE ||
        at(game, (int8_t)x, (int8_t)y) != OTHELLO_EMPTY)
        return 0;
    for (direction = 0; direction < 8; ++direction) {
        const int8_t dx = directions[direction][0];
        const int8_t dy = directions[direction][1];
        int8_t scan_x = (int8_t)x + dx;
        int8_t scan_y = (int8_t)y + dy;
        uint8_t line = 0;
        while (inside(scan_x, scan_y) &&
               at(game, scan_x, scan_y) == opponent) {
            ++line;
            scan_x += dx;
            scan_y += dy;
        }
        if (line && inside(scan_x, scan_y) &&
            at(game, scan_x, scan_y) == player)
            total += line;
    }
    return total;
}

/* A move is legal exactly when the non-mutating probe finds a capture. */
uint8_t othello_is_legal(const struct othello_game *game, uint8_t x, uint8_t y,
                         uint8_t player)
{
    return othello_flips(game, x, y, player) != 0;
}

/*
 * Validate the move first, then repeat the ray scans and recolor only bounded
 * opponent runs.  Invalid moves return zero before placing a disc, which is an
 * important API guarantee used by both the UI and the randomized tests.
 */
uint8_t othello_apply(struct othello_game *game, uint8_t x, uint8_t y,
                      uint8_t player)
{
    uint8_t direction;
    uint8_t total = othello_flips(game, x, y, player);
    const uint8_t opponent = othello_opponent(player);
    if (!total)
        return 0;
    game->board[y * OTHELLO_SIZE + x] = player;
    for (direction = 0; direction < 8; ++direction) {
        const int8_t dx = directions[direction][0];
        const int8_t dy = directions[direction][1];
        int8_t scan_x = (int8_t)x + dx;
        int8_t scan_y = (int8_t)y + dy;
        uint8_t line = 0;
        while (inside(scan_x, scan_y) &&
               at(game, scan_x, scan_y) == opponent) {
            ++line;
            scan_x += dx;
            scan_y += dy;
        }
        if (line && inside(scan_x, scan_y) &&
            at(game, scan_x, scan_y) == player) {
            scan_x = (int8_t)x + dx;
            scan_y = (int8_t)y + dy;
            while (line--) {
                game->board[(uint8_t)scan_y * OTHELLO_SIZE +
                            (uint8_t)scan_x] = player;
                scan_x += dx;
                scan_y += dy;
            }
        }
    }
    return total;
}

/* Enumerate the small fixed board instead of maintaining derived move state. */
uint8_t othello_legal_count(const struct othello_game *game, uint8_t player)
{
    uint8_t x;
    uint8_t y;
    uint8_t count = 0;
    for (y = 0; y < OTHELLO_SIZE; ++y)
        for (x = 0; x < OTHELLO_SIZE; ++x)
            if (othello_is_legal(game, x, y, player))
                ++count;
    return count;
}

/* Express the common pass check in terms of the authoritative move generator. */
uint8_t othello_has_moves(const struct othello_game *game, uint8_t player)
{
    return othello_legal_count(game, player) != 0;
}

/* Othello ends after two implicit passes: neither side can make a legal move. */
uint8_t othello_is_over(const struct othello_game *game)
{
    return !othello_has_moves(game, OTHELLO_HUMAN) &&
           !othello_has_moves(game, OTHELLO_CPU);
}

/* Recompute scores from board contents so counters can never become stale. */
void othello_score(const struct othello_game *game, uint8_t *human,
                   uint8_t *cpu)
{
    uint8_t index;
    *human = 0;
    *cpu = 0;
    for (index = 0; index < OTHELLO_CELLS; ++index) {
        if (game->board[index] == OTHELLO_HUMAN) ++*human;
        else if (game->board[index] == OTHELLO_CPU) ++*cpu;
    }
}
