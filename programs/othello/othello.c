/*
 * P2000M Othello user interface and application state machine.
 *
 * This module deliberately contains no board-rule implementation: game.c is
 * the platform-neutral authority for legal moves and captures, while cpu.c
 * selects a move for the computer player.  Keeping those parts independent
 * makes it possible to exhaustively test them as ordinary host C code.
 *
 * The application uses the P2000M's native 80x24 VT52-style terminal.  It
 * reads non-echoed key bytes with conio's getk(), renders with cursor-address
 * escape sequences, and does not require graphics, sound, files, or timers.
 * O is always the human player and moves first; X is controlled by the CPU.
 */
#include <conio.h>
#include <stdio.h>

#include "cpu.h"
#include "game.h"
#include "version.h"

#define ESC 27
#define ROWS OTHELLO_SIZE
#define COLS OTHELLO_SIZE
#define KEY_RETURN 13
#define KEY_ESCAPE 27
#define KEY_UP 11
#define KEY_DOWN 10
#define KEY_LEFT 8
#define KEY_RIGHT 12

/*
 * Every full-screen interaction mode handled by the main event loop.
 *
 * TITLE enters PLAYING or temporarily enters HELP.  PLAYING can temporarily
 * enter HELP or QUIT_CONFIRM and becomes RESULT when neither player can move.
 * RESULT starts a new PLAYING game or exits.  help_return_state records which
 * complete screen must be reconstructed after the modal help page closes.
 */
enum screen_state { TITLE, HELP, PLAYING, QUIT_CONFIRM, RESULT };

/* The UI owns turn/cursor state; struct othello_game contains only the board. */
static struct othello_game game;
static unsigned char current_player;
static unsigned char cursor_x;
static unsigned char cursor_y;
static enum screen_state help_return_state;

/* Emit a VT52 direct-cursor sequence followed by a zero-terminated string. */
static void put_at(unsigned char row, unsigned char column, const char *text)
{
    putchar(ESC);
    putchar('Y');
    putchar(row + 32);
    putchar(column + 32);
    fputs(text, stdout);
}

/* Select the P2000M terminal's inverse or normal character rendition. */
static void inverse(unsigned char enabled)
{
    putchar(ESC);
    putchar(enabled ? 'p' : 'q');
}

/* Home the cursor and erase the complete 80 by 24 terminal display. */
static void clear_screen(void)
{
    putchar(ESC);
    putchar('H');
    putchar(ESC);
    putchar('J');
}

/* Erase a partial row without disturbing text to its left. */
static void erase_from(unsigned char row, unsigned char column)
{
    put_at(row, column, "");
    putchar(ESC);
    putchar('K');
}

/* Print a right-aligned, two-character value in the game's 0 to 64 range. */
static void put_number(unsigned char row, unsigned char column,
                       unsigned char value)
{
    char number[3];
    number[0] = value >= 10 ? '0' + value / 10 : ' ';
    number[1] = '0' + value % 10;
    number[2] = 0;
    put_at(row, column, number);
}

/* Center a short string using the fixed 80-column terminal width. */
static void draw_centered(unsigned char row, const char *text)
{
    unsigned char length = 0;
    const char *scan = text;
    while (*scan++) ++length;
    put_at(row, (80 - length) / 2, text);
}

/* Render the initial menu and advertise every command available there. */
static void draw_title(void)
{
    clear_screen();
    draw_centered(2, "P2000M OTHELLO");
    draw_centered(5, "HUMAN (O)  versus  CPU (X)");
    draw_centered(9, "Capture discs by enclosing one or more X discs.");
    draw_centered(14, "Arrow keys move     Space places a disc");
    draw_centered(16, "Enter starts        Q returns to CP/M");
    draw_centered(18, "H shows help");
    draw_centered(21, "PRESS ENTER TO START");
}

/*
 * Draw the self-contained rules and controls page.  Text is kept within the
 * native 80 by 24 display so it is identical on hardware and in the emulator.
 */
static void draw_help(void)
{
    clear_screen();
    draw_centered(0, "P2000M OTHELLO - HELP");
    put_at(2, 4, "VERSION " OTHELLO_VERSION);
    put_at(3, 4, "COMPILED " OTHELLO_BUILD_DATE);
    put_at(4, 4, "AUTHOR IVO FILOT");
    put_at(6, 4, "OBJECTIVE");
    put_at(7, 4, "Finish with more O discs than the CPU has X discs.");
    put_at(9, 4, "HOW TO PLAY");
    put_at(10, 4, "You are O and move first. Select an empty square that traps");
    put_at(11, 4, "one or more X discs between the new O and another O.");
    put_at(12, 4, "Lines may be horizontal, vertical, or diagonal. Every trapped");
    put_at(13, 4, "disc is flipped. A player with no legal move passes automatically.");
    put_at(14, 4, "The game ends when neither player can move.");
    put_at(16, 4, "DISPLAY");
    put_at(17, 4, ". marks a legal move. Inverse video marks the cursor.");
    put_at(19, 4, "CONTROLS");
    put_at(20, 4, "ARROWS  Move cursor       SPACE/ENTER  Place disc");
    put_at(21, 4, "H       Show this help    Q            Quit game");
    draw_centered(23, "ENTER, H, OR ESC RETURNS");
}

static void draw_cell(unsigned char y, unsigned char x)
{
    /* Empty cells become dots only when legal for the active player. */
    char cell[2];
    const unsigned char disc = game.board[y * COLS + x];
    if (disc == OTHELLO_HUMAN) cell[0] = 'O';
    else if (disc == OTHELLO_CPU) cell[0] = 'X';
    else if (othello_is_legal(&game, x, y, current_player)) cell[0] = '.';
    else cell[0] = ' ';
    cell[1] = 0;
    put_at(3 + y * 2, 7 + x * 4, cell);
}

/* Redraw the selected cell between inverse-video on/off commands. */
static void draw_cursor(void)
{
    inverse(1);
    draw_cell(cursor_y, cursor_x);
    inverse(0);
}

/* Refresh all 64 cell characters while leaving the grid itself untouched. */
static void redraw_cells(void)
{
    unsigned char x;
    unsigned char y;
    for (y = 0; y < ROWS; ++y)
        for (x = 0; x < COLS; ++x)
            draw_cell(y, x);
}

/*
 * Draw the immutable board frame, coordinates, discs, and legal-move markers.
 * Board cells occupy odd display rows 3..17 and columns 7,11,..35.  The
 * surrounding grid occupies rows 2..18 and columns 5..37, leaving columns
 * 52 onward for status.  These fixed coordinates keep the full interface
 * within the machine's 80x24 display without scrolling.
 */
static void draw_board(void)
{
    unsigned char x;
    unsigned char y;
    char label[2];
    put_at(1, 7, "A   B   C   D   E   F   G   H");
    put_at(2, 5, "+---+---+---+---+---+---+---+---+");
    for (y = 0; y < ROWS; ++y) {
        label[0] = '1' + y;
        label[1] = 0;
        put_at(3 + y * 2, 3, label);
        put_at(3 + y * 2, 5, "|   |   |   |   |   |   |   |   |");
        for (x = 0; x < COLS; ++x)
            draw_cell(y, x);
        put_at(4 + y * 2, 5, "+---+---+---+---+---+---+---+---+");
    }
}

/* Recompute and display scores, active player, controls, and legal-move count. */
static void draw_status(void)
{
    unsigned char human;
    unsigned char cpu;
    unsigned char legal;
    othello_score(&game, &human, &cpu);
    legal = othello_legal_count(&game, current_player);
    put_at(2, 52, "STATUS");
    put_at(3, 52, "------");
    put_at(5, 52, "YOU (O):");
    put_number(5, 61, human);
    put_at(6, 52, "CPU (X):");
    put_number(6, 61, cpu);
    put_at(8, 52, current_player == OTHELLO_HUMAN ?
           "TURN: YOU" : "TURN: CPU");
    put_at(11, 52, "CONTROLS");
    put_at(12, 52, "--------");
    put_at(14, 52, "ARROWS  move cursor");
    put_at(15, 52, "SPACE   place disc");
    put_at(16, 52, "Q       quit game");
    put_at(17, 52, "H       show help");
    erase_from(22, 2);
    put_at(22, 2, "LEGAL MOVES:");
    put_number(22, 15, legal);
}

/* Place the cursor on the first row-major legal move for the active player. */
static void select_first_legal(void)
{
    unsigned char x;
    unsigned char y;
    for (y = 0; y < ROWS; ++y)
        for (x = 0; x < COLS; ++x)
            if (othello_is_legal(&game, x, y, current_player)) {
                cursor_x = x;
                cursor_y = y;
                return;
            }
}

/* Reconstruct the complete playing screen after a menu or help transition. */
static void draw_playing(void)
{
    clear_screen();
    put_at(0, 31, "P2000M OTHELLO");
    put_at(0, 61, "HUMAN vs CPU");
    draw_board();
    draw_status();
    put_at(20, 2, "Choose a square to outflank CPU discs.");
    draw_cursor();
}

/* Replace the status panel with final scores and replay/exit choices. */
static void draw_result(void)
{
    unsigned char row;
    unsigned char human;
    unsigned char cpu;
    othello_score(&game, &human, &cpu);
    for (row = 2; row <= 18; ++row)
        erase_from(row, 52);
    put_at(2, 52, "FINAL SCORE");
    put_at(3, 52, "-----------");
    put_at(5, 52, "YOU (O):");
    put_number(5, 61, human);
    put_at(6, 52, "CPU (X):");
    put_number(6, 61, cpu);
    put_at(8, 52, human > cpu ? "YOU WIN!" :
           cpu > human ? "CPU WINS." : "DRAW GAME.");
    erase_from(20, 2);
    put_at(20, 2, "ENTER: PLAY AGAIN    Q: RETURN TO CP/M");
    erase_from(22, 2);
}

/* Remove the old highlight, wrap coordinates at every edge, and highlight again. */
static void move_cursor(signed char dy, signed char dx)
{
    draw_cell(cursor_y, cursor_x);
    cursor_x = (cursor_x + dx + COLS) % COLS;
    cursor_y = (cursor_y + dy + ROWS) % ROWS;
    draw_cursor();
}

/* Reset all game state and start a human turn at the first legal square. */
static void start_game(void)
{
    othello_init(&game);
    current_player = OTHELLO_HUMAN;
    select_first_legal();
    draw_playing();
}

/*
 * Provide a visible thinking interval.  The volatile counter prevents the
 * compiler from deleting the loop; exact duration intentionally remains tied
 * to the original 2.5 MHz machine rather than host wall-clock facilities.
 */
static void cpu_pause(void)
{
    volatile unsigned int count;
    for (count = 0; count < 8000; ++count) {
        /* Keep the CPU status visible briefly on real hardware. */
    }
}

/*
 * Run one or more CPU turns synchronously.  A missing CPU move passes back to
 * the human.  If the human must pass after a CPU move, the loop continues with
 * another CPU move.  Either side having no move ends the game through the
 * shared rules engine's terminal-state check.
 */
static enum screen_state cpu_turn(void)
{
    unsigned char move_x;
    unsigned char move_y;
    for (;;) {
        if (!othello_cpu_choose(&game, &move_x, &move_y)) {
            if (othello_is_over(&game)) {
                draw_result();
                return RESULT;
            }
            current_player = OTHELLO_HUMAN;
            select_first_legal();
            redraw_cells();
            draw_status();
            erase_from(20, 2);
            put_at(20, 2, "CPU HAS NO LEGAL MOVE - YOUR TURN.");
            draw_cursor();
            return PLAYING;
        }
        erase_from(20, 2);
        put_at(20, 2, "CPU IS THINKING ...");
        cpu_pause();
        othello_apply(&game, move_x, move_y, OTHELLO_CPU);
        if (othello_is_over(&game)) {
            redraw_cells();
            draw_result();
            return RESULT;
        }
        if (othello_has_moves(&game, OTHELLO_HUMAN)) {
            current_player = OTHELLO_HUMAN;
            select_first_legal();
            redraw_cells();
            draw_status();
            erase_from(20, 2);
            put_at(20, 2, "Choose a square to outflank CPU discs.");
            draw_cursor();
            return PLAYING;
        }
        current_player = OTHELLO_CPU;
        redraw_cells();
        draw_status();
        erase_from(20, 2);
        put_at(20, 2, "YOU HAVE NO LEGAL MOVE - CPU CONTINUES.");
        cpu_pause();
    }
}

/* Validate and apply the cursor square, then hand control to the CPU or result. */
static enum screen_state human_move(void)
{
    if (!othello_apply(&game, cursor_x, cursor_y, OTHELLO_HUMAN)) {
        erase_from(20, 2);
        put_at(20, 2, "THAT SQUARE IS NOT A LEGAL MOVE.");
        draw_cursor();
        return PLAYING;
    }
    current_player = OTHELLO_CPU;
    redraw_cells();
    if (othello_is_over(&game)) {
        draw_result();
        return RESULT;
    }
    if (!othello_has_moves(&game, OTHELLO_CPU)) {
        current_player = OTHELLO_HUMAN;
        select_first_legal();
        redraw_cells();
        draw_status();
        erase_from(20, 2);
        put_at(20, 2, "CPU HAS NO LEGAL MOVE - YOUR TURN.");
        draw_cursor();
        return PLAYING;
    }
    draw_status();
    return cpu_turn();
}

/* Restore normal video and erase all game text before CP/M prints its prompt. */
static void leave_game(void)
{
    inverse(0);
    clear_screen();
}

/*
 * Dispatch raw, non-echoed CP/M keyboard bytes according to the screen state.
 * The arrow values are the P2000M native control bytes also used by CP/M
 * applications such as SuperCalc.  CPU turns run synchronously, so quit/help
 * input is accepted only while the human owns the turn.  Any key other than Y
 * cancels QUIT_CONFIRM, deliberately making accidental exits difficult.
 */
int main(void)
{
    enum screen_state state = TITLE;
    int key;

    draw_title();
    for (;;) {
        key = getk();
        if (!key)
            continue;
        if (state == TITLE) {
            if (key == KEY_RETURN) {
                state = PLAYING;
                start_game();
            } else if (key == 'h' || key == 'H') {
                help_return_state = TITLE;
                state = HELP;
                draw_help();
            } else if (key == 'q' || key == 'Q') {
                leave_game();
                return 0;
            }
        } else if (state == HELP) {
            if (key == KEY_RETURN || key == KEY_ESCAPE ||
                key == 'h' || key == 'H') {
                state = help_return_state;
                if (state == TITLE)
                    draw_title();
                else
                    draw_playing();
            }
        } else if (state == PLAYING) {
            if (current_player == OTHELLO_HUMAN && key == KEY_UP)
                move_cursor(-1, 0);
            else if (current_player == OTHELLO_HUMAN && key == KEY_DOWN)
                move_cursor(1, 0);
            else if (current_player == OTHELLO_HUMAN && key == KEY_LEFT)
                move_cursor(0, -1);
            else if (current_player == OTHELLO_HUMAN && key == KEY_RIGHT)
                move_cursor(0, 1);
            else if (current_player == OTHELLO_HUMAN &&
                     (key == ' ' || key == KEY_RETURN))
                state = human_move();
            else if (key == 'h' || key == 'H') {
                help_return_state = PLAYING;
                state = HELP;
                draw_help();
            }
            else if (key == 'q' || key == 'Q') {
                state = QUIT_CONFIRM;
                put_at(20, 2, "QUIT GAME? (Y/N)                                      ");
            }
        } else if (state == QUIT_CONFIRM) {
            if (key == 'y' || key == 'Y') {
                leave_game();
                return 0;
            }
            state = PLAYING;
            erase_from(20, 2);
            put_at(20, 2, "Choose a square to outflank CPU discs.");
        } else if (state == RESULT) {
            if (key == 'q' || key == 'Q') {
                leave_game();
                return 0;
            }
            if (key == KEY_RETURN) {
                state = PLAYING;
                start_game();
            }
        }
    }
}
