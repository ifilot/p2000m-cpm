#pragma once
#include "p2000_machine.h"
#include "memory_layout.h"
#include <stdexcept>

// Observe firmware I/O without replacing any service or changing the emulator.
struct Activity {
    bool selected=false;
    unsigned ledWrites=0, ramReads=0, ramWrites=0, sdReads=0, sdWrites=0;
    void expect(P2000Machine &m,unsigned value,const char *why) {
        if(m.sdCartridge().leds()!=value)throw std::runtime_error(why);
    }
    void idle(P2000Machine &m) { expect(m,0,"Activity LED left on after I/O returned"); }
    void step(P2000Machine &m) {
        const auto pc=m.programCounter();
        const auto opcode=m.peekMemory(pc),port=m.peekMemory(pc+1);
        if(opcode==0xd3) {
            if(port==0x42)selected=false;
            if(port==0x43)selected=true;
            if(port==0x44)++ledWrites;
            if(port==0x4d) {
                expect(m,2,"SRAM write without exclusive WRITE LED");++ramWrites;
            }
            if(port==0x41 && selected) {
                const bool writing=m.peekMemory(p2m_layout::rom_workspace+0x15)==24;
                expect(m,writing?2:1,"SD command/data/CRC/busy clocks have wrong LED");
                if(writing)++sdWrites;else ++sdReads;
            }
        } else if(opcode==0xdb && port==0x4d) {
            expect(m,1,"SRAM read without exclusive READ LED");++ramReads;
        }
        m.stepInstruction();
    }
};
