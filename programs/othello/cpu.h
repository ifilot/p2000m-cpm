#ifndef P2000M_OTHELLO_CPU_H
#define P2000M_OTHELLO_CPU_H

#include "game.h"

/*
 * Select the CPU's best legal move.  Returns zero when the CPU must pass;
 * otherwise writes the selected coordinates and returns nonzero.
 */
uint8_t othello_cpu_choose(const struct othello_game *game,
                           uint8_t *move_x, uint8_t *move_y);

#endif
