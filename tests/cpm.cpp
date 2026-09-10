#include "p2000_machine.h"
#include <iostream>
#include <stdexcept>
#include <string>
static void frames(P2000Machine &m,int n) { while(n--) m.runFrame(); }
static std::string screen(P2000Machine &m) {return std::string((const char*)m.characters(),1920);}
static void require(bool b,const std::string &s) {if(!b) throw std::runtime_error(s);}
static void type(P2000Machine &m,const std::string &s) {
    const std::string matrix =
        " 6 Q3574" " HZSDGJF" "  0 # , " " N<XCBMV" " YAWETUR" " 9*/ 01-" "9O87 P8@" "3.21]/K2" "6L54=;I:";
    for(char c:s) {
        unsigned pos=0;
        if(c=='\n') pos=6*8+4;
        else if(c==' ') pos=2*8+1;
        else if(c==27) pos=4*8;
        else {
            pos=matrix.find(c);
            require(pos<matrix.size(),"Unknown keyboard character");
        }
        m.setKey(pos/8,pos%8,true);frames(m,2);
        m.setKey(pos/8,pos%8,false);frames(m,2);
    }
}
static void prompt(P2000Machine &m) {
    for(int i=0;i<300;++i) {
        auto s=screen(m);
        auto end=s.find_last_not_of(" ");
        if(end!=std::string::npos && end>0 && s.substr(end-1,2)=="A>") return;
        frames(m,100);
    }
    throw std::runtime_error("Command did not return to CCP");
}
static void wait_text(P2000Machine &m,const std::string &text) {
    for(int i=0;i<300 && screen(m).find(text)==std::string::npos;++i) frames(m,100);
    require(screen(m).find(text)!=std::string::npos,"Missing text: "+text);
}
static unsigned bdos(P2000Machine &m,unsigned fn,unsigned arg=0) {
    const unsigned char code[]={
        0x31,0,0x95,0x0e,static_cast<unsigned char>(fn),0x11,
        static_cast<unsigned char>(arg),static_cast<unsigned char>(arg>>8),0xcd,5,0,
        0x32,0x40,0x9e,0x22,0x42,0x9e,0x3e,0x5a,0x32,0x41,0x9e,0x76
    };
    for(unsigned i=0;i<sizeof(code);++i)m.pokeMemory(0x8000+i,code[i]);
    m.pokeMemory(0x66,0xc3);m.pokeMemory(0x67,0);m.pokeMemory(0x68,0x80);
    m.pokeMemory(0x9e41,0);m.requestNmi();
    for(int i=0;i<2000 && m.peekMemory(0x9e41)!=0x5a;++i)frames(m,10);
    require(m.peekMemory(0x9e41)==0x5a,"BDOS call timed out");
    return m.peekMemory(0x9e40);
}
static void fcb(P2000Machine &m,const std::string &name,unsigned drive=3) {
    for(unsigned i=0;i<36;++i)m.pokeMemory(0x8200+i,0);
    m.pokeMemory(0x8200,drive);
    require(name.size()==11,"Test FCB name length");
    for(unsigned i=0;i<11;++i)m.pokeMemory(0x8201+i,name[i]);
}
static void edge_tests(P2000Machine &m) {
    bdos(m,26,0x8300);
    fcb(m,"SPARSE  DAT");
    require(bdos(m,22,0x8200)!=255,"Create sparse file");
    m.pokeMemory(0x8221,255);m.pokeMemory(0x8222,255); // random record 65535
    for(unsigned i=0;i<128;++i)m.pokeMemory(0x8300+i,i^0xa5);
    require(bdos(m,40,0x8200)==0,"Zero-fill random write");
    require(bdos(m,35,0x8200)==0,"Sparse file size call");
    require(m.peekMemory(0x8221)==0 && m.peekMemory(0x8222)==0 && m.peekMemory(0x8223)==1,
            "8 MiB logical file length lost high byte");
    require(bdos(m,33,0x8200)==6,"Random overflow was not rejected");
    m.pokeMemory(0x8221,248);m.pokeMemory(0x8222,255);m.pokeMemory(0x8223,0);
    require(bdos(m,33,0x8200)==0,"Read zero-filled sparse block");
    for(unsigned i=0;i<128;++i)require(m.peekMemory(0x8300+i)==0,"New block was not zero-filled");
    m.pokeMemory(0x8221,255);
    require(bdos(m,33,0x8200)==0,"Read final possible record");
    for(unsigned i=0;i<128;++i)require(m.peekMemory(0x8300+i)==(i^0xa5),"Final record mismatch");
    require(bdos(m,20,0x8200)==0,"Sequential read following random");
    require(bdos(m,20,0x8200)==6,"Sequential overflow wrapped around to record zero");
    m.pokeMemory(0x8209,'D'|128);
    require(bdos(m,30,0x8200)!=255,"Set read-only attribute");
    require(bdos(m,34,0x8200)==255,"Read-only file write accepted");
    require(bdos(m,19,0x8200)==255,"Read-only file delete accepted");
    m.pokeMemory(0x8209,'D');
    require(bdos(m,30,0x8200)!=255,"Clear read-only attribute");
    bdos(m,32,1);
    require(bdos(m,15,0x8200)==255,"File leaked between user areas");
    require(bdos(m,22,0x8200)!=255,"Same name in another user area");
    require(bdos(m,19,0x8200)!=255,"Delete user 1 file");
    bdos(m,32,0);
    require(bdos(m,15,0x8200)!=255,"User 0 file was lost");
    require(bdos(m,19,0x8200)!=255,"Delete sparse file");
    // Fill all 64 RAM directory slots with empty files, then reclaim them.
    for(unsigned i=0;i<64;++i) {
        std::string name="EMPTY000DAT";
        name[6]='0'+i/10;name[7]='0'+i%10;
        fcb(m,name);
        require(bdos(m,22,0x8200)!=255,"RAM directory filled too early");
    }
    fcb(m,"OVERFLOWDAT");
    require(bdos(m,22,0x8200)==255,"RAM directory overflow accepted");
    fcb(m,"???????????");
    require(bdos(m,19,0x8200)!=255,"Wildcard directory cleanup failed");
    fcb(m,"RECLAIM DAT");
    require(bdos(m,22,0x8200)!=255,"Directory space was not reclaimed");
    bdos(m,14,2);bdos(m,28);
    require(bdos(m,21,0x8200)==255,"Protected disk write accepted");
    bdos(m,37,4);
    require(bdos(m,21,0x8200)==0,"Drive reset did not clear protection");
    std::cout << "PASS: sparse 8 MiB logical file, zero fill, overflow, attributes, user isolation, full directory/reclaim, drive protection" << std::endl;
}
int main(int argc,char **argv) {
    P2000Machine m;
    try {
        require(argc==4,"Usage: cpm-test EMULATOR BUILD CARD");
        std::string error;
        require(m.loadMonitor(std::string(argv[1])+"/assets/roms/p2000.rom",&error),error);
        require(m.loadCartridge(std::string(argv[2])+"/cartridge.bin",&error),error);
        m.installCoBoard();m.sdCartridge().install();
        require(m.sdCartridge().insert(argv[3],false,&error),error);
        frames(m,700);
        require(screen(m).find("A>")!=std::string::npos,"Missing command prompt");
        type(m,"HELLO\n");frames(m,150);
        require(screen(m).find("Hello from an original Z80")!=std::string::npos,"HELLO did not execute");
        m.pokeMemory(0x9000,0);
        type(m,"CPMTEST\n");
        for(int i=0;i<1000 && m.peekMemory(0x9000)==0;++i) {
            frames(m,200);
            if(i%100==0) std::cout << "CPMTEST frames " << i*200 << std::endl;
        }
        require(m.peekMemory(0x9000)==0xa5,"CPMTEST failed or timed out");
        frames(m,20);
        require(screen(m).find("CPMTEST PASS")!=std::string::npos,"No success banner");
        type(m,"PIP B:HELLO.COM=A:HELLO.COM\n");prompt(m);
        std::cout << "PIP returned" << std::endl;
        type(m,"B:HELLO\n");prompt(m);
        require(screen(m).find("Hello from an original Z80")!=std::string::npos,"PIP copy did not execute");
        type(m,"COPY A:HELLO.COM C:HELLO.COM\n");prompt(m);
        require(screen(m).find("Copy complete.")!=std::string::npos,"Original COPY failed");
        type(m,"C:HELLO\n");prompt(m);
        type(m,"ERA C:HELLO.COM\n");prompt(m);
        type(m,"REN B:NEW.COM=B:HELLO.COM\n");prompt(m);
        type(m,"B:NEW\n");prompt(m);
        type(m,"SAVE 1 B:SAVED.COM\n");prompt(m);
        type(m,"B:SAVED\n");prompt(m);
        type(m,"STAT\n");prompt(m);
        require(screen(m).find("R/W, Space:")!=std::string::npos,"STAT failed");
        type(m,"ASM TEST\n");prompt(m);
        require(screen(m).find("END OF ASSEMBLY")!=std::string::npos,"ASM did not finish");
        type(m,"LOAD TEST\n");prompt(m);
        type(m,"TEST\n");prompt(m);
        require(screen(m).find("ASM/LOAD OK")!=std::string::npos,"ASM/LOAD output did not run");
        type(m,"DUMP HEXTEST.BIN\n");prompt(m);
        require(screen(m).find("0000 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F")!=std::string::npos,
                "DUMP first row differs from expected bytes");
        require(screen(m).find("0070 70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F")!=std::string::npos,
                "DUMP last row differs from expected bytes");
        type(m,"DDT\n");frames(m,300);
        require(screen(m).find("DDT VERS 2.2")!=std::string::npos,"DDT failed");
        type(m,"G0\n");frames(m,100);
        type(m,"ED NOTES.TXT\n");wait_text(m,"NEW FILE");wait_text(m,": *");frames(m,50);
        require(screen(m).find("NEW FILE")!=std::string::npos,"ED failed");
        type(m,"I\nEDITED ON SD\n");
        type(m,std::string(1,27)+"Z");frames(m,500);
        type(m,"E\n");prompt(m);
        type(m,"TYPE NOTES.TXT\n");prompt(m);
        require(screen(m).find("EDITED ON SD")!=std::string::npos,"ED output missing");
        type(m,"TPALIMIT\n");prompt(m);
        require(screen(m).find("TPA LIMIT PASS")!=std::string::npos,"Exact TPA-size COM failed");
        type(m,"TOOBIG\n");prompt(m);
        require(screen(m).find("Error: command, file or disk operation failed")!=std::string::npos,
                "Oversized COM was not rejected");
        edge_tests(m);
        std::cout << "PASS: PIP, STAT, ASM/LOAD toolchain, DUMP, DDT and ED run on the original BDOS" << std::endl;
        std::cout << "PASS: CCP loads COM, BDOS sequential/random files span extents and both RAM banks on A/B/C, close/reopen/size/delete" << std::endl;
    } catch(const std::exception &e) {
        std::cerr << e.what() << "; PC=" << std::hex << m.programCounter() << '\n';
        for(int row=0;row<24;++row) std::cerr << screen(m).substr(row*80,80) << '\n';
        return 1;
    }
}
