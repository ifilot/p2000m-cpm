// Run the COM diagnostic with a tiny CP/M console shim, allowing faulty/old
// bank hardware and initial DI/EI states to be exercised independently.
#include "p2000_machine.h"
extern "C" {
#include "z80.h"
}
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>
struct Rig {
    P2000Machine machine;
    std::string fault;
    unsigned bank=0;
    unsigned outputs=0;
};
static void check(bool ok,const char *message) { if(!ok)throw std::runtime_error(message); }
static uint8_t read(void *ctx,uint16_t address) {
    return static_cast<Rig*>(ctx)->machine.peekMemory(address);
}
static void write(void *ctx,uint16_t address,uint8_t value) {
    auto &r=*static_cast<Rig*>(ctx);
    if(r.fault=="stuck" && r.bank==4 && address==0x6123)value&=0xfe;
    r.machine.pokeMemory(address,value);
}
static uint8_t input(z80*,uint8_t) { return 0xff; }
static void output(z80 *cpu,uint16_t address,uint8_t value) {
    auto &r=*static_cast<Rig*>(cpu->userdata);
    ++r.outputs;
    if(r.fault=="legacy")address&=255; // old board only latches D7
    if(r.fault=="alias" && (value&1) && (address&0x3800))address=(address&255)|0x0800;
    r.bank=(value&0x81)==0x81 ? ((address>>11)&7):0;
    r.machine.writePort(address,value);
}
int main(int argc,char **argv) {
    try {
        check(argc==2,"Usage: banktest-test BANKTEST.COM");
        std::ifstream file(argv[1],std::ios::binary);
        std::vector<unsigned char> code((std::istreambuf_iterator<char>(file)),{});
        check(!code.empty() && code.size()<0x3d00,"Invalid COM size");
        for(const std::string fault: {"", "legacy", "alias", "stuck"})
            for(bool interrupts: {false,true})
              for(unsigned entrySp: {0xcafeu,0x6000u}) {
                Rig r; r.fault=fault;
                r.machine.installCoBoard(); r.machine.writePort(0x8020,0x80);
                for(unsigned a=0x4000;a<0x8000;++a)r.machine.pokeMemory(a,(a^(a>>8)^0x73)&255);
                for(unsigned i=0;i<code.size();++i)r.machine.pokeMemory(0x100+i,code[i]);
                r.machine.pokeMemory(5,0xc9); // BDOS console returns normally
                r.machine.pokeMemory(entrySp,0); r.machine.pokeMemory(entrySp+1,0);
                std::vector<uint8_t> original;
                for(unsigned a=0x4000;a<0x8000;++a)original.push_back(read(&r,a));
                z80 cpu; z80_init(&cpu);
                cpu.read_byte=read; cpu.write_byte=write; cpu.port_in=input; cpu.port_out=output;
                cpu.userdata=&r; cpu.pc=0x100; cpu.sp=entrySp; cpu.iff1=cpu.iff2=interrupts;
                std::string text;
                unsigned steps=0;
                while(cpu.pc && steps++<10000000) {
                    if(cpu.pc==5) {
                        check(r.bank==0,"Diagnostic called BDOS with bank mapped");
                        if(cpu.c==2 || cpu.c==6)text+=char(cpu.e);
                        else if(cpu.c==9) {
                            unsigned a=(cpu.d<<8)|cpu.e;
                            for(unsigned n=0;n<1024 && read(&r,a)!='$';++n,++a)text+=char(read(&r,a));
                        } else throw std::runtime_error("Unexpected BDOS function");
                    }
                    z80_step(&cpu);
                }
                check(cpu.pc==0,"Diagnostic did not return");
                check(cpu.sp==entrySp+2,"Diagnostic did not restore caller stack");
                check(cpu.iff1==interrupts,"Diagnostic changed caller interrupt state");
                check(r.bank==0 && r.machine.coBoardMapped(),"Diagnostic did not restore normal map");
                check(text.find(fault.empty()?"BANKTEST PASS":"BANKTEST FAIL")!=std::string::npos,
                      "Diagnostic reported the wrong result");
                if(fault=="stuck")check(text.find("bank 04 addr 6123")!=std::string::npos,"Wrong failure location");
                for(unsigned a=0x4000;a<0x8000;++a)
                    check(read(&r,a)==original[a-0x4000],"Diagnostic did not restore ordinary RAM");
            }
        std::cout<<"PASS: BANKTEST success, old board, aliased banks, stuck bit, RAM/stack/map/DI/EI restoration\n";
    }catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}
}
