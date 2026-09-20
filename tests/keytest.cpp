// Exercise the actual COM loaded by CCP, through physical matrix inputs.
#include "p2000_machine.h"
#include "memory_layout.h"
#include <iostream>
#include <stdexcept>
#include <string>
#include <array>
static void require(bool b,const std::string &s){if(!b)throw std::runtime_error(s);}
static void frames(P2000Machine &m,int n){while(n--)m.runFrame();}
static std::string screen(P2000Machine &m){return std::string((const char*)m.characters(),1920);}
static void type(P2000Machine &m,const std::string &s){
    const std::string matrix=" 6 Q3574" " HZSDGJF" "   0# , " " N<XCBMV" " YAWETUR"
        " 9+- 01-" "9O87 P8@" "3.21]/K2" "6L54 ;I:";
    for(char c:s){
        unsigned p=c=='\n'?6*8+4:matrix.find(c);
        require(p<72,"Unknown command key");
        m.setKey(p/8,p%8,true);frames(m,3);
        m.setKey(p/8,p%8,false);frames(m,3);
    }
}
static void wait_text(P2000Machine &m,const std::string &s){
    for(unsigned i=0;i<100 && screen(m).find(s)==std::string::npos;++i)frames(m,20);
    require(screen(m).find(s)!=std::string::npos,"Missing text: "+s);
}
using Rows=std::array<unsigned,10>;
static void verify(P2000Machine &m,const Rows &pressed,const std::string &baseline){
    // Compare every attribute, including separators, margins and instructions.
    // Also verify only raw hex digits changed in the entire character plane.
    auto expected=baseline;
    const char *hex="0123456789ABCDEF";
    for(unsigned r=0;r<10;++r){
        expected[(r+5)*80+4]=hex[(~pressed[r]>>4)&15];
        expected[(r+5)*80+5]=hex[~pressed[r]&15];
    }
    require(screen(m)==expected,"Character plane changed outside raw row values");
    for(unsigned pos=0;pos<1920;++pos){
        unsigned y=pos/80,x=pos%80,attr=0;
        if(y>=5 && y<15 && x>=10 && x<74 && (x-10)%8<7)
            attr=(pressed[y-5] & (1u<<((x-10)/8)))?8:0;
        require(m.attributes()[pos]==attr,"Wrong inverse tile at cell "+std::to_string(pos));
    }
}
int main(int argc,char **argv){
 try{
    require(argc==4,"Usage: keytest-test EMULATOR BUILD CARD");
    P2000Machine m;std::string error;
    require(m.loadMonitor(std::string(argv[1])+"/assets/roms/p2000.rom",&error),error);
    require(m.loadCartridge(std::string(argv[2])+"/cartridge.bin",&error),error);
    m.installCoBoard();m.sdCartridge().install();
    require(m.sdCartridge().insert(argv[3],false,&error),error);
    frames(m,700);wait_text(m,"A>");
    for(unsigned base:{p2m_layout::keyboard_stack_bottom,p2m_layout::bdos_stack_bottom,p2m_layout::system_stack_bottom})
        for(unsigned i=0;i<16;++i)m.pokeMemory(base+i,0xa5);
    type(m,"KEYTEST\n");wait_text(m,"KEYTEST - P2000M");frames(m,5);
    const auto baseline=screen(m); Rows pressed{};
    verify(m,pressed,baseline);
    auto tile=[&](unsigned r,unsigned b){return baseline.substr((5+r)*80+10+8*b,7);};
    require(tile(4,2)=="  a A  " && tile(5,5)=="  0 =  " && tile(2,3)==" KP 0 =","Letter/duplicate-zero labels wrong");
    require(tile(3,0)=="  LOCK " && tile(9,0)=="SHIFT L" && tile(9,7)=="SHIFT R","Modifiers missing");
    require(tile(0,4)=="  3 #  " && tile(0,7)=="  4 $  " && tile(7,7)=="  2 \"  ","Native hash/dollar/quote labels wrong");
    require(tile(5,7)=="  - `  " && tile(5,2)==" KP + *" && tile(5,3)==" KP - /",
            "Photo/maintenance minus/underscore and keypad operator labels wrong");
    require(tile(2,0)=="KP . ST" && tile(2,2)==" KP 00 " && tile(5,0)=="KPCLEAR",
            "Photo/maintenance keypad legends wrong");
    require(tile(7,4)==std::string("  ")+char(0x10)+" "+char(0x0f)+"  ","Native bracket legends wrong");
    // All 80 row/bit positions, including unmapped/unused inputs.
    for(unsigned r=0;r<10;++r)for(unsigned b=0;b<8;++b){
        m.setKey(r,b,true);pressed[r]=1u<<b;frames(m,2);verify(m,pressed,baseline);
        m.setKey(r,b,false);pressed[r]=0;frames(m,2);verify(m,pressed,baseline);
    }
    // Simultaneous keys on the same row, across rows, and both Shift keys.
    // Exclude ESC here so this large chord is not the exit command.
    for(unsigned r=0;r<10;++r)for(unsigned b=0;b<8;++b)if(r!=4 || b!=0){
        m.setKey(r,b,true);pressed[r]|=1u<<b;
    }
    frames(m,200);verify(m,pressed,baseline);
    require(m.peekMemory(p2m_layout::key_head)==m.peekMemory(p2m_layout::key_tail),"Test keys leaked into FIFO");
    for(unsigned r=0;r<10;++r)for(unsigned b=0;b<8;++b)m.setKey(r,b,false);
    pressed.fill(0);frames(m,3);verify(m,pressed,baseline);
    // A bouncing input must follow the raw wire, without software debounce.
    for(unsigned i=0;i<12;++i){bool down=i%2==0;m.setKey(4,2,down);pressed[4]=down?4:0;frames(m,1);verify(m,pressed,baseline);}
    // ESC with only one Shift must remain testable, for both Shift keys.
    for(unsigned b:{0u,7u}){
        m.setKey(9,b,true);m.setKey(4,0,true);pressed[9]=1u<<b;pressed[4]=1;
        frames(m,4);verify(m,pressed,baseline);
        m.setKey(9,b,false);m.setKey(4,0,false);pressed.fill(0);frames(m,3);verify(m,pressed,baseline);
    }
    for(unsigned pass=0;pass<2;++pass){
        if(pass){type(m,"KEYTEST\n");wait_text(m,"KEYTEST - P2000M");frames(m,5);verify(m,Rows{},baseline);}
        m.setKey(9,0,true);m.setKey(9,7,true);m.setKey(4,0,true);
        frames(m,5);wait_text(m,"Exit selected:");
        if(!pass){
            // A stuck ordinary key must not prevent exit. Seed a queued NUL
            // followed by Q: treating NUL as an empty queue would leak Q.
            m.setKey(4,2,true);
            m.pokeMemory(p2m_layout::keyboard_queue,0);
            m.pokeMemory(p2m_layout::keyboard_queue+1,'Q');
            m.pokeMemory(p2m_layout::key_tail,0);
            m.pokeMemory(p2m_layout::key_head,2);
        }
        m.setKey(4,0,false);frames(m,5);
        require(screen(m).find("Exit selected:")!=std::string::npos,"Exited before Shift release");
        m.setKey(9,0,false);m.setKey(9,7,false);frames(m,30);wait_text(m,"A>");
        m.setKey(4,2,false);frames(m,3);
        require(screen(m).find_first_not_of(" \r\nA>")==std::string::npos,"Input leaked to CCP after exit");
        type(m,"HELLO\n");wait_text(m,"Hello from an original Z80 CP/M");
    }
    for(unsigned base:{p2m_layout::keyboard_stack_bottom,p2m_layout::bdos_stack_bottom,p2m_layout::system_stack_bottom})
        for(unsigned i=0;i<16;++i)require(m.peekMemory(base+i)==0xa5,"Resident stack guard corrupted");
    std::cout<<"PASS: KEYTEST all 80 inputs, release, overlap, modifiers, bounce, hold, native labels, clean exit/relaunch and HELLO\n";
 }catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}
}
