#include "p2000_machine.h"
#include "memory_layout.h"
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>
#include <string>
static void require(bool ok,const std::string &s){if(!ok)throw std::runtime_error(s);}
static void frames(P2000Machine &m,int n){while(n--)m.runFrame();}
static unsigned word(P2000Machine &m,unsigned a){return m.peekMemory(a)|(m.peekMemory(a+1)<<8);}
static unsigned queued(P2000Machine &m){return (m.peekMemory(p2m_layout::key_head)-m.peekMemory(p2m_layout::key_tail))&63;}
static std::vector<unsigned char> load(P2000Machine &m,const char *path){
    std::ifstream in(path,std::ios::binary);require(bool(in),"Missing keyboard fixture");
    std::vector<unsigned char> data((std::istreambuf_iterator<char>(in)),{});
    for(unsigned i=0;i<data.size();++i)m.pokeMemory(0x100+i,data[i]);return data;
}
static void enter(P2000Machine &m,unsigned address){
    m.pokeMemory(0x66,0xc3);m.pokeMemory(0x67,address&255);m.pokeMemory(0x68,address>>8);
    m.requestNmi();frames(m,1);
}
static unsigned bios(P2000Machine &m,unsigned index,bool enabled=false){
    unsigned address=p2m_layout::bios+index*3;
    const unsigned char code[]={0xf3,0x31,0,0x95,static_cast<unsigned char>(enabled?0xfb:0x00),
        0xcd,(unsigned char)address,(unsigned char)(address>>8),0x32,0x20,0x91,
        0xed,0x57,0xf5,0xe1,0x22,0x22,0x91,0xf3,0x76};
    for(unsigned i=0;i<sizeof(code);++i)m.pokeMemory(0x8000+i,code[i]);
    enter(m,0x8000);require(bool(m.peekMemory(0x9122)&4)==enabled,"Console changed caller IFF");
    return m.peekMemory(0x9120);
}
static std::string drain(P2000Machine &m){
    std::string s;while(bios(m,2))s+=char(bios(m,3));return s;
}
static void tap(P2000Machine &m,unsigned row,unsigned bit){
    m.setKey(row,bit,true);frames(m,2);m.setKey(row,bit,false);frames(m,2);
}
int main(int argc,char **argv){
 try{
    require(argc==6,"Usage: keyboard-test EMULATOR BUILD CARD IRQ_FIXTURE IO_FIXTURE");
    P2000Machine m;std::string error;
    require(m.loadMonitor(std::string(argv[1])+"/assets/roms/p2000.rom",&error),error);
    require(m.loadCartridge(std::string(argv[2])+"/cartridge.bin",&error),error);
    m.installCoBoard();m.sdCartridge().install();require(m.sdCartridge().insert(argv[3],false,&error),error);
    frames(m,700);require(std::string((const char*)m.characters(),1920).find("A>")!=std::string::npos,"No boot prompt");
    require(word(m,p2m_layout::keyboard_vector)==p2m_layout::keyboard_interrupt,"Wrong IM2 vector");
    for(unsigned base:{p2m_layout::keyboard_stack_bottom,p2m_layout::bdos_stack_bottom,p2m_layout::system_stack_bottom})
        for(unsigned i=0;i<16;++i)m.pokeMemory(base+i,0xa5);
    auto busy=[&](){load(m,argv[4]);enter(m,0x100);};
    busy();
    m.setKey(4,2,true);frames(m,1);require(queued(m)==0,"Press was not debounced");
    frames(m,1);require(queued(m)==1,"Key not captured within two frames");
    tap(m,3,5); // B while A is still held
    m.setKey(4,2,false);frames(m,2);
    // Capture registers before any foreground console calls change them.
    unsigned spin=word(m,0x103),finish=word(m,0x105);
    m.pokeMemory(spin+1,finish&255);m.pokeMemory(spin+2,finish>>8);frames(m,1);
    require(m.peekMemory(0x9118)==0xa5,"IRQ register fixture did not finish");
    for(auto pair:std::vector<std::pair<unsigned,unsigned>>{{0x9100,0x2345},{0x9102,0x3456},{0x9104,0x4567},
        {0x9106,0x5678},{0x9108,0x6789},{0x910a,0x9500},{0x910c,0x1245},
        {0x9110,0x789a},{0x9112,0x89ab},{0x9114,0x9abc},{0x9116,0x2381}})
        require(word(m,pair.first)==pair.second,"ISR corrupted main/alternate registers or SP");
    require(drain(m)=="ab","Overlapping key lost or duplicated");
    busy();
    for(unsigned shift:{0u,7u}){
        m.setKey(9,shift,true);tap(m,4,2);m.setKey(9,shift,false);frames(m,2);
    }
    require(drain(m)=="AA","Shift was not captured with each event");
    busy();
    tap(m,5,5);
    for(unsigned shift:{0u,7u}) {
        m.setKey(9,shift,true);tap(m,5,5);m.setKey(9,shift,false);frames(m,2);
    }
    // These control values are application input, including SuperCalc arrows.
    tap(m,0,0);tap(m,2,7);
    require(drain(m)==std::string("0==\x08\x0c",5),
            "Numeric-pad DEFINE or cursor-key mapping failed");
    busy();
    for(int i=0;i<3;++i){m.setKey(4,2,true);frames(m,1);m.setKey(4,2,false);frames(m,1);}
    require(queued(m)==0,"Bouncing press generated input");
    m.setKey(4,2,true);frames(m,2);
    m.setKey(4,2,false);frames(m,1);m.setKey(4,2,true);frames(m,1);
    require(queued(m)==1,"Bouncing release duplicated input");
    m.setKey(4,2,false);frames(m,2);require(drain(m)=="a","Debounce lost valid input");
    busy();m.setKey(4,2,true);frames(m,2);
    require(m.peekMemory(p2m_layout::key_repeat_count)==50,"Initial repeat countdown wrong");
    frames(m,49);require(queued(m)==1,"Repeat started too early");
    frames(m,1);require(queued(m)==2,"One-second repeat missing");
    frames(m,2);require(queued(m)==3,"40 ms repeat missing");
    m.setKey(4,2,false);frames(m,2);require(drain(m)=="aaa","Repeat count wrong");
    busy();std::string expected;
    for(int i=0;i<70;++i){tap(m,i%2?3:4,i%2?5:2);if(i<63)expected+=i%2?'b':'a';}
    require(queued(m)==63 && m.peekMemory(p2m_layout::key_overflow)==1,"FIFO overflow not bounded/reported");
    require(drain(m)==expected,"Overflow changed older input or FIFO ordering");
    busy();tap(m,4,0);tap(m,4,2);tap(m,4,0);tap(m,4,0);
    require(drain(m)==std::string("\x01\x1b",2),"Escape control prefix failed");
    busy();tap(m,4,0);tap(m,6,7);
    require(bios(m,2,true)==255 && bios(m,3,true)==0,"Queued NUL/readiness or EI caller failed");
    m.setKey(4,2,true);require(bios(m,2)==255 && bios(m,3)=='a',"DI polling fallback failed");
    m.setKey(4,2,false);require(bios(m,2)==0,"DI release generated input");
    load(m,argv[5]);m.pokeMemory(0x9000,0);enter(m,0x100);
    require(m.peekMemory(0x9000)==0,"SD workload failed before typing");
    tap(m,4,2);tap(m,3,5);m.setKey(9,0,true);tap(m,3,4);m.setKey(9,0,false);tap(m,1,4);
    require(m.peekMemory(0x9000)==0,"SD workload finished before type-ahead test");
    // The 2,000 forced-I/O iterations now also calculate/check every SD CRC.
    for(int n=0;n<2000 && m.peekMemory(0x9000)==0;++n)frames(m,50);
    require(m.peekMemory(0x9000)==0xa5,"SD workload failed or timed out: status="+
            std::to_string(m.peekMemory(0x9000))+" PC="+std::to_string(m.programCounter()));
    require(drain(m)=="abCd","Type-ahead lost during SD reads");
    for(unsigned base:{p2m_layout::keyboard_stack_bottom,p2m_layout::bdos_stack_bottom,p2m_layout::system_stack_bottom})
        for(unsigned i=0;i<16;++i)require(m.peekMemory(base+i)==0xa5,"IRQ/BDOS/system stack overflow");
    busy();tap(m,4,2);tap(m,3,5);
    // An application may change IM/I. WBOOT must restore keyboard ownership
    // without throwing away already queued input.
    unsigned warm=p2m_layout::bios+3;
    const unsigned char changeMode[]={0xf3,0xed,0x56,0xaf,0xed,0x47,0xc3,
        (unsigned char)warm,(unsigned char)(warm>>8)};
    for(unsigned i=0;i<sizeof(changeMode);++i)m.pokeMemory(0x8000+i,changeMode[i]);
    enter(m,0x8000);frames(m,5);tap(m,3,4);
    require(std::string((const char*)m.characters(),1920).find("A>abc")!=std::string::npos,
            "Warm boot lost type-ahead or failed to restore IM2 keyboard");
    enter(m,p2m_layout::bios);frames(m,700);
    require(m.coBoardMapped() && queued(m)==0 && m.peekMemory(p2m_layout::key_overflow)==0,
            "Cold restart did not reset keyboard state");
    tap(m,1,4);
    require(std::string((const char*)m.characters(),1920).find("A>d")!=std::string::npos,
            "Cold-restarted keyboard is not responsive");
    std::cout<<"PASS: 50 Hz IRQ, debounce, overlap, modifier capture, repeat, FIFO overflow/wrap, controls, DI/EI, register preservation, SD type-ahead and stack guards\n";
    return 0;
 }catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}
}
