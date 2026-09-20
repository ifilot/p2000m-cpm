#ifndef P2000M_OTHELLO_GAME_H
#define P2000M_OTHELLO_GAME_H

#include <stdint.h>

#define OTHELLO_SIZE 8
#define OTHELLO_CELLS 64

/*
 * Public model and rules API.  Cell values are deliberately compact so the
 * complete board occupies 64 bytes on the memory-constrained Z80 target.
 * Coordinates are zero-based: (0,0) is display square A1.  Public rule
 * functions expect OTHELLO_HUMAN or OTHELLO_CPU wherever a player is required.
 */
enum othello_disc {
    OTHELLO_EMPTY = 0,
    OTHELLO_HUMAN = 1,
    OTHELLO_CPU = 2
};

struct othello_game {
    /* Row-major cells; index = y * OTHELLO_SIZE + x. */
    uint8_t board[OTHELLO_CELLS];
};

/* Restore the standard four-disc opening position. */
void othello_init(struct othello_game *game);

/* Return the opposing disc value for a valid player value. */
uint8_t othello_opponent(uint8_t player);

/* Count discs captured by a proposed move without changing the board. */
uint8_t othello_flips(const struct othello_game *game, uint8_t x, uint8_t y,
                      uint8_t player);

/* Return nonzero precisely when the proposed move captures at least one disc. */
uint8_t othello_is_legal(const struct othello_game *game, uint8_t x, uint8_t y,
                         uint8_t player);

/* Apply a legal move and return its flip count; return zero without mutation. */
uint8_t othello_apply(struct othello_game *game, uint8_t x, uint8_t y,
                      uint8_t player);

/* Count or test the legal moves currently available to one player. */
uint8_t othello_legal_count(const struct othello_game *game, uint8_t player);
uint8_t othello_has_moves(const struct othello_game *game, uint8_t player);

/* A game is over only when neither player has a legal move. */
uint8_t othello_is_over(const struct othello_game *game);

/* Count both kinds of discs and write the two totals through the output pointers. */
void othello_score(const struct othello_game *game, uint8_t *human,
                   uint8_t *cpu);

#endif
