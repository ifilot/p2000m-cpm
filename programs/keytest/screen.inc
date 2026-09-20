; Fixed 80x24 native glyphs: 23h=sterling, 5Fh=hash, 60h=underscore.
; 0Ah/0Bh=grave/acute, 0Fh/10h=brackets, 1Bh=degree. Not ASCII text.
    db "KEYTEST - P2000M keyboard wiring test                                           " ; row 0
    db "Each held key is INVERTED. Release it to return to normal.                      " ; row 1
    db "Electrical matrix order: X = input port, Y = data bit (not QWERTY order).       " ; row 2
    db "                                                                                " ; row 3
    db "X   RAW      Y0      Y1      Y2      Y3      Y4      Y5      Y6      Y7         " ; row 4
    db "00  FF      LEFT    6 &      UP     q Q     3 #     5 %     7 '     4 $         " ; row 5
    db "01  FF      TAB     h H     z Z     s S     d D     g G     j J     f F         " ; row 6
    db "02  FF    KP . ST  SPACE   KP 00   KP 0 =   _ ",27,"     DOWN     ,     RIGHT        " ; row 7
    db "03  FF      LOCK    n N     < >     x X     c C     b B     m M     v V         " ; row 8
    db "04  FF      CODE    y Y     a A     w W     e E     t T     u U     r R         " ; row 9
    db "05  FF    KPCLEAR   9 )    KP + *  KP - /    BS     0 =     1 !     - `         " ; row 10
    db "06  FF      KP 9    o O     KP 8    KP 7   RETURN   p P     8 (     @ '         " ; row 11
    db "07  FF      KP 3     .      KP 2    KP 1    ",16," ",15,"     / ?     k K     2 ",34,"         " ; row 12
    db "08  FF      KP 6    l L     KP 5    KP 4    ",11," ",10,"     ; +     i I     : *         " ; row 13
    db "09  FF    SHIFT L    --      --      --      --      --      --   SHIFT R       " ; row 14
    db "                                                                                " ; row 15
    db "Physical keycaps (NL/UK); KP = numeric pad; CODE acts as CP/M Escape.           " ; row 16
    db "Main 0/= is X5/Y5; keypad DEFINE/0 is X2/Y3. RAW: FF = all released.            " ; row 17
    db "All contacts highlight, including CLEAR/00/LOCK (no CP/M character).            " ; row 18
    db "                                                                                " ; row 19
    db "To exit: hold BOTH SHIFT keys + CODE (Escape), then release them.               " ; row 20
    db "                                                                                " ; row 21
    db "Raw wiring test: no debounce, character translation, or repeat filtering.       " ; row 22
    db "Map checked against Maintenance 2 NL/UK and the photographed keyboard.          " ; row 23
