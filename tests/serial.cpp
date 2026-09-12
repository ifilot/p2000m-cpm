extern "C" {
#include "z80.h"
}
#include <array>
#include <algorithm>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static void require(bool ok,const std::string &why) {if(!ok)throw std::runtime_error(why);}
struct Rig {
    z80 cpu{};
    std::array<unsigned char,65536> memory{};
    struct Output {unsigned long cycle;unsigned port,value;};
    std::vector<Output> output;
    unsigned byte=0,idle=1;
    bool ready=true,badStop=false,falseStart=false;
    unsigned long start=10000;
    Rig(const std::string &file) {
        std::ifstream in(file,std::ios::binary);
        std::vector<unsigned char> code((std::istreambuf_iterator<char>(in)),{});
        require(!code.empty() && code.size()<0x8000,"Load diagnostic COM");
        std::copy(code.begin(),code.end(),memory.begin()+0x100);
        z80_init(&cpu);cpu.userdata=this;
        cpu.read_byte=[](void *p,uint16_t a){return static_cast<Rig*>(p)->memory[a];};
        cpu.write_byte=[](void *p,uint16_t a,uint8_t v){static_cast<Rig*>(p)->memory[a]=v;};
        cpu.port_in=[](z80 *z,uint8_t port)->uint8_t {
            auto &r=*static_cast<Rig*>(z->userdata);require(port==0x20,"Unexpected input port");
            unsigned data=1;
            if(z->cyc>=r.start) {
                unsigned bit=(z->cyc-r.start)/8333;
                data=bit==0?0:bit<=8?(r.byte>>(bit-1))&1:bit==9 && r.badStop?0:1;
                if(r.falseStart && z->cyc-r.start>200)data=1;
            }
            return 0xfc|(r.ready?0:2)|(r.idle?data:1-data);
        };
        cpu.port_out=[](z80 *z,uint8_t port,uint8_t value) {
            auto &r=*static_cast<Rig*>(z->userdata);r.output.push_back({z->cyc,port,value});
        };
    }
    void call(unsigned address,bool interrupts=true,unsigned value=0) {
        cpu.pc=address;cpu.sp=0xf000;memory[0xf000]=0;memory[0xf001]=0x90;
        cpu.b=0x12;cpu.c=value;cpu.d=0x34;cpu.e=0x56;cpu.h=0x78;cpu.l=0x9a;
        cpu.iff1=cpu.iff2=interrupts;cpu.cyc=0;cpu.halted=false;output.clear();
        for(unsigned i=0;i<1000000 && cpu.pc!=0x9000;++i)z80_step(&cpu);
        require(cpu.pc==0x9000,"Serial routine did not return within bounded time");
        require(cpu.sp==0xf002 && cpu.iff1==interrupts,"Serial routine damaged SP/IFF");
        require(cpu.b==0x12 && cpu.c==value && cpu.d==0x34 && cpu.e==0x56 && cpu.h==0x78 && cpu.l==0x9a,
                "Serial routine damaged BC/DE/HL");
    }
    std::string program(const std::string &argument="",unsigned quitAfter=100000) {
        memory[0x80]=argument.size();
        std::copy(argument.begin(),argument.end(),memory.begin()+0x81);
        cpu.pc=0x100;cpu.sp=0xf000;memory[0xf000]=0;memory[0xf001]=0;
        unsigned polls=0;std::string console;
        for(unsigned steps=0;steps<20000000 && cpu.pc!=0;++steps) {
            if(cpu.pc==5) {
                unsigned result=0;
                if(cpu.c==9) {
                    unsigned p=(cpu.d<<8)|cpu.e;
                    for(unsigned n=0;memory[p]!='$' && n<65536;++n,++p)console+=char(memory[p&65535]);
                } else if(cpu.c==2)console+=char(cpu.e);
                else if(cpu.c==6)result=++polls>=quitAfter?'Q':0;
                else throw std::runtime_error("Unexpected diagnostic BDOS function");
                cpu.a=cpu.l=result;cpu.h=cpu.b=0;
                cpu.pc=memory[cpu.sp]|(memory[cpu.sp+1]<<8);cpu.sp+=2;
            } else z80_step(&cpu);
        }
        require(cpu.pc==0,"Diagnostic did not exit");
        return console;
    }
};
int main(int argc,char **argv) {
    try {
        require(argc==9,"Usage: serial-test COM TX RX READY IDLE FORCE SERPINS SERRX");
        unsigned tx=std::stoul(argv[2]),rx=std::stoul(argv[3]),ready=std::stoul(argv[4]);
        unsigned idleAddress=std::stoul(argv[5]),force=std::stoul(argv[6]);
        Rig r(argv[1]);
        for(bool interrupts : {false,true})for(unsigned byte=0;byte<256;++byte) {
            r.call(tx,interrupts,byte);
            require(r.output.size()==10,"Wrong UART frame length");
            for(unsigned bit=0;bit<10;++bit) {
                unsigned logical=bit==0?0:bit==9?1:(byte>>(bit-1))&1;
                require(r.output[bit].port==0x10 && r.output[bit].value==((1-logical)<<7),
                        "Bad serial bit or unsafe latch output");
                if(bit)require(r.output[bit].cycle-r.output[bit-1].cycle==8336,"300-baud TX timing changed");
            }
            for(unsigned idle : {0u,1u}) {
                r.byte=byte;r.idle=idle;r.memory[idleAddress]=idle;r.call(rx,interrupts);
                require(!r.cpu.cf && r.cpu.a==byte,"RX byte/polarity mismatch");
                require(r.output.empty(),"Receiver drove hardware outputs");
            }
        }
        r.ready=false;r.call(ready);require(r.cpu.cf,"Missing READY accepted");
        r.memory[force]=1;r.call(ready);require(!r.cpu.cf,"Forced three-wire TX rejected");
        r.memory[force]=0;r.ready=true;r.call(ready);require(!r.cpu.cf,"Active READY rejected");
        r.start=10000000;r.call(rx);require(r.cpu.cf && r.cpu.a==1,"Idle timeout missing");
        r.start=10000;r.badStop=true;r.call(rx);require(r.cpu.cf && r.cpu.a==2,"Bad stop bit accepted");
        r.badStop=false;r.falseStart=true;r.call(rx);require(r.cpu.cf && r.cpu.a==2,"False start accepted");
        Rig pins(argv[7]);pins.ready=false;pins.start=10000000;
        require(pins.program("",3).find("IN20 & 03 = 03")!=std::string::npos,"SERPINS reported wrong bits");
        require(pins.output.empty(),"SERPINS drove outputs");
        Rig txProgram(argv[1]);txProgram.ready=false;
        require(txProgram.program().find("READY inactive")!=std::string::npos && txProgram.output.empty(),"SERTX ignored handshake");
        Rig forced(argv[1]);forced.ready=false;forced.program(" F");
        std::string pattern="P2000M RS232 Uu0123456789\r\n";
        require(forced.output.size()==pattern.size()*100,"SERTX did not send ten complete lines");
        for(unsigned frame=0;frame<pattern.size()*10;++frame)for(unsigned bit=0;bit<10;++bit) {
            unsigned logical=bit==0?0:bit==9?1:(unsigned(pattern[frame%pattern.size()])>>(bit-1))&1;
            require(forced.output[frame*10+bit].value==((1-logical)<<7),"SERTX pattern corrupted");
        }
        Rig receiver(argv[8]);receiver.byte=0x55;
        require(receiver.program("",2).find("55\r\n")!=std::string::npos,"SERRX failed to display received byte");
        Rig invalid(argv[1]);require(invalid.program(" X").find("Usage: SERTX [F]")!=std::string::npos,"Bad SERTX argument accepted");
        std::cout<<"PASS: all 256 TX/RX bytes, both PRI polarities/IFF states, exact bit timing, READY, timeout/framing and safe port writes\n";
    } catch(const std::exception &e) {std::cerr<<e.what()<<'\n';return 1;}
}
