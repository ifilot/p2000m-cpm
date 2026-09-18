// Revised CPLD rev 0.7: full output bus, optional 16 KiB SRAM window.
#include "p2000_machine.h"
#include <iostream>
#include <stdexcept>
#include <initializer_list>

static void check(bool ok, const char *message) {
    if (!ok) throw std::runtime_error(message);
}
static void select(P2000Machine &m, unsigned bank) {
    const unsigned control=0x81 | (bank << 3);
    m.writePort((control << 8) | 0x20, control);
}
static unsigned pattern(unsigned bank, unsigned offset) {
    return (offset ^ (offset >> 8) ^ (bank * 29)) & 255;
}
static void instructions(P2000Machine &m, std::initializer_list<unsigned> code) {
    m.reset();
    m.writePort(0x8020,0x80);
    unsigned address=0;
    for (auto byte:code) m.pokeMemory(address++,byte);
    for (unsigned step=0; step<32 && m.programCounter()!=address; ++step)
        m.stepInstruction();
    check(m.programCounter()==address,"CPU output fixture did not finish");
}
int main() {
    try {
        P2000Machine m;
        m.writePort(0xb920,0xb9);
        check(!m.coBoardMapped(),"Absent board accepted a control write");
        m.installCoBoard();
        m.writePort(0x8020,0x80);
        for (unsigned address=0;address<0xe000;++address)
            m.pokeMemory(address,pattern(0,address));
        for (unsigned address=0xf000;address<=0xffff;++address)
            m.pokeMemory(address,pattern(9,address));
        for (unsigned bank=1;bank<=7;++bank) {
            select(m,bank);
            for (unsigned offset=0;offset<0x4000;++offset)
                m.pokeMemory(0x4000+offset,pattern(bank,offset));
            // Hardware rev 0.6 accidentally selected video at banked 7000h.
            // This model represents the corrected isolated map (rev 0.7).
            for (unsigned address=0xf000;address<=0xffff;++address)
                check(m.peekMemory(address)==pattern(9,address),"Bank write corrupted video/attributes");
        }
        // All banks must survive writes to every other bank, byte for byte.
        for (unsigned bank=7;bank>0;--bank) {
            select(m,bank);
            for (unsigned offset=0;offset<0x4000;++offset)
                check(m.peekMemory(0x4000+offset)==pattern(bank,offset),"Bank alias/data failure");
            for (unsigned address: {0x3fffu,0x8000u,0x9fffu,0xa000u,0xdfffu})
                check(m.peekMemory(address)==pattern(0,address),"Overlay escaped 4000-7FFF");
        }
        m.writePort(0x8020,0x80);
        for (unsigned address=0;address<0xe000;++address)
            check(m.peekMemory(address)==pattern(0,address),"Normal RAM or fixed bank changed");
        // Every control value and mirrored port; register OUT can supply bank
        // independently of the data byte. Reserved data bits must be ignored.
        for (unsigned port=0x20;port<=0x2f;++port)
            for (unsigned data=0;data<256;++data)
                for (unsigned bank=0;bank<8;++bank) {
                    m.writePort((bank << 11)|port,data);
                    check(m.coBoardMapped()==bool(data&0x80),"Mode latch mismatch");
                    if (data&0x80) {
                        unsigned visible=(data&1) && bank ? bank : 0;
                        check(m.peekMemory(0x4000)==pattern(visible,visible ? 0:0x4000),
                              "Overlay enable/bank zero/alias/reserved bits mismatch");
                        check(m.peekMemory(0xa000)==pattern(0,0xa000),"Bank zero was remapped");
                    } else {
                        check(m.peekMemory(0xa000)==pattern(0,0x4000),"Overlay active in stock mode");
                    }
                }
        select(m,7);
        m.writePort(0x801f,0); m.writePort(0x8030,0);
        check(m.peekMemory(0x4000)==pattern(7,0),"Unrelated port changed banking");
        check(m.readPort(0x20)==0xf7,"Bank write changed cassette status input");
        m.reset();
        check(!m.coBoardMapped(),"Reset retained CP/M mode");
        m.writePort(0x0020,0x81);
        check(m.peekMemory(0x4000)==pattern(0,0x4000),"Reset/control retained stale bank");
        select(m,7);
        check(m.peekMemory(0x4000)==pattern(7,0),"Reset erased bank SRAM");
        // Execute real instructions through the machine's CPU callbacks.
        instructions(m,{0x3e,0x99,0xd3,0x2f}); // immediate: A -> data AND upper address
        check(m.peekMemory(0x4000)==pattern(3,0),"Immediate OUT lost upper address");
        instructions(m,{0x01,0x20,0x28,0x3e,0x89,0xed,0x79}); // B=28, A=89: bank 5
        check(m.peekMemory(0x4000)==pattern(5,0),"OUT (C),A took bank from A instead of B");
        instructions(m,{0x01,0x20,0x10,0x16,0x81,0xed,0x51}); // OUT (C),D: bank 2
        check(m.peekMemory(0x4000)==pattern(2,0),"OUT (C),D lost upper address");
        for (unsigned opcode: {0xa3u,0xabu,0xb3u,0xbbu}) {
            m.pokeMemory(0x9000,0x81);
            // B=18h decrements to 17h: bank 2, not bank 3. Execute only
            // the first iteration of repeating forms; they branch back to PC 6.
            m.reset(); m.writePort(0x8020,0x80);
            const unsigned code[]={0x01,0x20,0x18,0x21,0x00,0x90,0xed,opcode};
            for(unsigned i=0;i<8;++i)m.pokeMemory(i,code[i]);
            for(unsigned i=0;i<3;++i)m.stepInstruction();
            check(m.peekMemory(0x4000)==pattern(2,0),"Block OUT used pre-decrement B");
        }
        m.removeCoBoard();
        check(!m.coBoardMapped(),"Removal retained map");
        m.writePort(0xb920,0xb9);
        check(!m.coBoardMapped(),"Removed board accepted write");
        m.installCoBoard(); select(m,7);
        check(m.peekMemory(0x4000)==0,"Fresh install did not initialize SRAM");
        std::cout << "PASS: seven banks, full-window isolation, control combinations, aliases, reset, removal and real Z80 OUT bus semantics\n";
    } catch(const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
