/*
 * Small deterministic CPU opponent.
 *
 * This is intentionally a one-ply heuristic rather than a search engine: the
 * 2.5 MHz target can respond quickly, and deterministic choices keep complete
 * emulator games reproducible.  Immediate captures determine the base score;
 * stable corner squares receive an additional strategic preference.
 */
#include "cpu.h"

/* Corners can never be recaptured and receive a deliberate strategic bonus. */
static uint8_t is_corner(uint8_t x, uint8_t y)
{
    return (x == 0 || x == OTHELLO_SIZE - 1) &&
           (y == 0 || y == OTHELLO_SIZE - 1);
}

/*
 * Score every legal move by immediate captures plus a ten-point corner bonus.
 * Iterating in row-major order and replacing only on a strictly better score
 * provides deterministic tie-breaking, which is useful on hardware and makes
 * complete emulator games reproducible.
 */
uint8_t othello_cpu_choose(const struct othello_game *game,
                           uint8_t *move_x, uint8_t *move_y)
{
    uint8_t x;
    uint8_t y;
    uint8_t found = 0;
    uint8_t best_score = 0;
    for (y = 0; y < OTHELLO_SIZE; ++y) {
        for (x = 0; x < OTHELLO_SIZE; ++x) {
            const uint8_t flips = othello_flips(game, x, y, OTHELLO_CPU);
            const uint8_t score = flips + (is_corner(x, y) ? 10 : 0);
            if (flips && (!found || score > best_score)) {
                found = 1;
                best_score = score;
                *move_x = x;
                *move_y = y;
            }
        }
    }
    return found;
}
