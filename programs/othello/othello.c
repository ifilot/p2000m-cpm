/*
 * P2000M Othello terminal prototype.
 *
 * This establishes the interaction and rendering contract before the rules
 * engine is connected.  It deliberately displays a fixed board position.
 */
#include <conio.h>
#include <stdio.h>

#define ESC 27
#define ROWS 8
#define COLS 8

enum screen_state { TITLE, PLAYING, QUIT_CONFIRM, RESULT };

static const char board[ROWS][COLS] = {
    { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
    { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
    { ' ', ' ', ' ', 'O', 'X', ' ', ' ', ' ' },
    { ' ', ' ', 'O', 'X', 'O', ' ', ' ', ' ' },
    { ' ', ' ', 'X', 'O', 'X', ' ', ' ', ' ' },
    { ' ', 'O', ' ', 'X', 'O', ' ', ' ', ' ' },
    { ' ', ' ', ' ', ' ', ' ', 'O', ' ', ' ' },
    { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' }
};

static unsigned char cursor_x;
static unsigned char cursor_y;

static void put_at(unsigned char row, unsigned char column, const char *text)
{
    putchar(ESC);
    putchar('Y');
    putchar(row + 32);
    putchar(column + 32);
    fputs(text, stdout);
}

static void inverse(unsigned char enabled)
{
    putchar(ESC);
    putchar(enabled ? 'p' : 'q');
}

static void clear_screen(void)
{
    putchar(ESC);
    putchar('H');
    putchar(ESC);
    putchar('J');
}

static void draw_centered(unsigned char row, const char *text)
{
    unsigned char length = 0;
    const char *scan = text;
    while (*scan++) ++length;
    put_at(row, (80 - length) / 2, text);
}

static void draw_title(void)
{
    clear_screen();
    draw_centered(2, "P2000M OTHELLO");
    draw_centered(5, "HUMAN (O)  versus  CPU (X)");
    draw_centered(9, "Capture discs by enclosing one or more X discs.");
    draw_centered(14, "Arrow keys move     Space places a disc");
    draw_centered(16, "Enter starts        Q returns to CP/M");
    draw_centered(21, "PRESS ENTER TO START");
}

static void draw_cell(unsigned char y, unsigned char x)
{
    char cell[2];
    cell[0] = board[y][x];
    cell[1] = 0;
    put_at(3 + y * 2, 7 + x * 4, cell);
}

static void draw_cursor(void)
{
    inverse(1);
    draw_cell(cursor_y, cursor_x);
    inverse(0);
}

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

static void draw_status(void)
{
    put_at(2, 52, "STATUS");
    put_at(3, 52, "------");
    put_at(5, 52, "YOU (O): 12");
    put_at(6, 52, "CPU (X): 10");
    put_at(8, 52, "TURN: YOU");
    put_at(11, 52, "CONTROLS");
    put_at(12, 52, "--------");
    put_at(14, 52, "ARROWS  move cursor");
    put_at(15, 52, "SPACE   place disc");
    put_at(16, 52, "Q       quit game");
}

static void draw_playing(void)
{
    clear_screen();
    put_at(0, 31, "P2000M OTHELLO");
    put_at(0, 61, "HUMAN vs CPU");
    draw_board();
    draw_status();
    put_at(20, 2, "Choose a square to outflank CPU discs.");
    put_at(22, 2, "LEGAL MOVES: 5");
    draw_cursor();
}

static void draw_result(void)
{
    put_at(2, 52, "FINAL SCORE");
    put_at(3, 52, "-----------");
    put_at(5, 52, "YOU (O): 34");
    put_at(6, 52, "CPU (X): 30");
    put_at(8, 52, "YOU WIN!");
    put_at(20, 2, "ENTER: PLAY AGAIN    Q: RETURN TO CP/M");
}

static void move_cursor(signed char dy, signed char dx)
{
    draw_cell(cursor_y, cursor_x);
    cursor_x = (cursor_x + dx + COLS) % COLS;
    cursor_y = (cursor_y + dy + ROWS) % ROWS;
    draw_cursor();
}

int main(void)
{
    enum screen_state state = TITLE;
    int key;

    cursor_x = 3;
    cursor_y = 2;
    draw_title();
    for (;;) {
        key = getk();
        if (!key)
            continue;
        if (state == TITLE) {
            if (key == 13) {
                state = PLAYING;
                draw_playing();
            } else if (key == 'q' || key == 'Q') {
                return 0;
            }
        } else if (state == PLAYING) {
            if (key == 11) move_cursor(-1, 0);
            else if (key == 10) move_cursor(1, 0);
            else if (key == 8) move_cursor(0, -1);
            else if (key == 12) move_cursor(0, 1);
            else if (key == ' ' || key == 13)
                put_at(20, 2, "MOVE PREVIEW ONLY — RULES ENGINE COMES NEXT.       ");
            else if (key == 'q' || key == 'Q') {
                state = QUIT_CONFIRM;
                put_at(20, 2, "QUIT GAME? (Y/N)                                      ");
            }
        } else if (state == QUIT_CONFIRM) {
            if (key == 'y' || key == 'Y') return 0;
            state = PLAYING;
            put_at(20, 2, "Choose a square to outflank CPU discs.               ");
        } else if (state == RESULT) {
            if (key == 'q' || key == 'Q') return 0;
            if (key == 13) {
                state = PLAYING;
                cursor_x = 3;
                cursor_y = 2;
                draw_playing();
            }
        }
    }
}
