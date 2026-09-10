#include "p2000_machine.h"
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
static void frames(P2000Machine &m,int n) { while(n--) m.runFrame(); }
static std::string screen(P2000Machine &m) {return std::string((const char*)m.characters(),1920);}
static void require(bool b,const std::string &s) {if(!b) throw std::runtime_error(s);}
static void type(P2000Machine &m,const std::string &s) {
    const std::string matrix =
        " 6 Q3574" " HZSDGJF" "   0# , " " N<XCBMV" " YAWETUR" " 9*/ 01-" "9O87 P8@" "3.21]/K2" "6L54=;I:";
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
static void fcb(P2000Machine &m,const std::string &name,unsigned drive=12) {
    for(unsigned i=0;i<36;++i)m.pokeMemory(0x8200+i,0);
    m.pokeMemory(0x8200,drive);
    require(name.size()==11,"Test FCB name length");
    for(unsigned i=0;i<11;++i)m.pokeMemory(0x8201+i,name[i]);
}
static void edge_tests(P2000Machine &m) {
    // Exercise twelve independent namespaces and the full 16-bit BDOS masks.
    bdos(m,13);
    bdos(m,26,0x8300);
    for(unsigned drive=0;drive<12;++drive) {
        fcb(m,"DRIVETSTDAT",drive+1);
        require(bdos(m,22,0x8200)!=255,"Create file on drive "+std::to_string(drive));
        for(unsigned i=0;i<128;++i)m.pokeMemory(0x8300+i,drive*17+i);
        require(bdos(m,21,0x8200)==0,"Write drive fixture");
        require(bdos(m,16,0x8200)!=255,"Close drive fixture");
    }
    bdos(m,24);
    require((m.peekMemory(0x9e42)|(m.peekMemory(0x9e43)<<8))==0xfff,"Login mask lost high drives");
    for(unsigned drive=0;drive<12;++drive) {
        fcb(m,"DRIVETSTDAT",drive+1);
        require(bdos(m,15,0x8200)!=255 && bdos(m,20,0x8200)==0,"Read drive fixture");
        for(unsigned i=0;i<128;++i)
            require(m.peekMemory(0x8300+i)==((drive*17+i)&255),"BDOS drive alias");
        require(bdos(m,19,0x8200)!=255,"Delete drive fixture");
        bdos(m,14,drive);bdos(m,28);
        require(bdos(m,22,0x8200)==255,"Protected drive accepted create");
    }
    bdos(m,29);
    require((m.peekMemory(0x9e42)|(m.peekMemory(0x9e43)<<8))==0xfff,"Protection mask lost high drives");
    bdos(m,37,0x500);bdos(m,29);
    require((m.peekMemory(0x9e42)|(m.peekMemory(0x9e43)<<8))==0xaff,"Selective high-drive reset failed");
    require(bdos(m,14,12)==255,"BDOS accepted drive M:");
    bdos(m,13);
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
    bdos(m,14,11);bdos(m,28);
    require(bdos(m,21,0x8200)==255,"Protected disk write accepted");
    bdos(m,37,0x800);
    require(bdos(m,21,0x8200)==0,"Drive reset did not clear protection");
    std::cout << "PASS: sparse 8 MiB logical file, zero fill, overflow, attributes, user isolation, full directory/reclaim, drive protection" << std::endl;
}
// Execute a public entry with register sentinels, then snapshot actual CPU state.
// The NMI trampoline only arranges the call; no OS operation is mocked.
static unsigned word(P2000Machine &m,unsigned address) {
    return m.peekMemory(address) | (m.peekMemory(address+1)<<8);
}
static void contract_call(P2000Machine &m,unsigned target,unsigned bc) {
    std::vector<unsigned char> code={
        0x31,0,0x95,              // LD SP,9500h
        0x21,0x45,0xa5,0xe5,0xf1,// AF=A545h (known flags)
        0x01,(unsigned char)bc,(unsigned char)(bc>>8),
        0x11,0x56,0x34,0x21,0x9a,0x78,
        0xdd,0x21,0xbc,0x6a,0xfd,0x21,0xde,0x5b,
        0xcd,(unsigned char)target,(unsigned char)(target>>8),
        0x22,4,0x85,0xed,0x43,0,0x85,0xed,0x53,2,0x85,
        0xdd,0x22,6,0x85,0xfd,0x22,8,0x85,0xed,0x73,10,0x85,
        0xf5,0xe1,0x22,12,0x85,
        0x3e,0x5a,0x32,14,0x85,0x76
    };
    for(unsigned i=0;i<code.size();++i)m.pokeMemory(0x8000+i,code[i]);
    m.pokeMemory(0x66,0xc3);m.pokeMemory(0x67,0);m.pokeMemory(0x68,0x80);
    m.pokeMemory(0x850e,0);m.requestNmi();
    for(int i=0;i<200 && m.peekMemory(0x850e)!=0x5a;++i)frames(m,10);
    require(m.peekMemory(0x850e)==0x5a,"Register contract timed out");
    require(word(m,0x8502)==0x3456,"DE preservation");
    require(word(m,0x8506)==0x6abc,"IX preservation");
    require(word(m,0x8508)==0x5bde,"IY preservation");
    require(word(m,0x850a)==0x9500,"SP balance");
}
static void contract_tests(P2000Machine &m) {
    // SETTRK, SETSEC and SETDMA promise to preserve every register and flag.
    for(unsigned target:{0xc01eu,0xc021u,0xc024u}) {
        contract_call(m,target,0x1234);
        require(word(m,0x8500)==0x1234 && word(m,0x8504)==0x789a &&
                word(m,0x850c)==0xa545,"BIOS setter contract");
    }
    contract_call(m,0xc030,0x1234); // SECTRAN: HL=BC
    require(word(m,0x8504)==0x1234 && word(m,0x8500)==0x1234 &&
            word(m,0x850c)==0xa545,"SECTRAN contract");
    contract_call(m,0xc00c,'X'); // CONOUT preserves all registers including flags
    require(word(m,0x8500)=='X' && word(m,0x8504)==0x789a &&
            word(m,0x850c)==0xa545,"CONOUT contract");
    require(screen(m).find("A>X")!=std::string::npos,"CONOUT character");
    contract_call(m,0xc006,0x1234); // CONST without a pressed key
    require(word(m,0x8500)==0x1234 && word(m,0x8504)==0x789a &&
            (word(m,0x850c)>>8)==0,"CONST contract");
    contract_call(m,5,0x120c); // BDOS version, C=12
    require(word(m,0x8504)==0x22 && word(m,0x8500)==12 &&
            (word(m,0x850c)>>8)==0x22,"BDOS result aliases / C preservation");
    contract_call(m,5,0x12ff); // unsupported function returns zero
    require(word(m,0x8504)==0 && word(m,0x8500)==255 &&
            (word(m,0x850c)>>8)==0,"Unknown BDOS function contract");
}

// Each isolated case boots a fresh card; persistent output is checked by Python.
static void program_test(P2000Machine &m,const std::string &name) {
    if(name=="ABI") {
        contract_tests(m);
    } else if(name=="HELLO") {
        type(m,"HELLO\n");prompt(m);
        wait_text(m,"Hello from an original Z80");
    } else if(name=="PIP") {
        type(m,"PIP B:RESULT.BIN=A:PAYLOAD.BIN\n");prompt(m);
    } else if(name=="COPY") {
        type(m,"COPY A:PAYLOAD.BIN B:RESULT.BIN\n");prompt(m);
        wait_text(m,"Copy complete.");
    } else if(name=="COPYEXISTS") {
        type(m,"COPY A:PAYLOAD.BIN B:RESULT.BIN\n");prompt(m);
        wait_text(m,"Destination exists; use ERA first");
    } else if(name=="ASM") {
        type(m,"ASM TEST\n");prompt(m);wait_text(m,"END OF ASSEMBLY");
    } else if(name=="LOAD") {
        type(m,"LOAD TEST\n");prompt(m);
        type(m,"TEST\n");prompt(m);wait_text(m,"ASM/LOAD OK");
    } else if(name=="DUMP") {
        type(m,"DUMP HEXTEST.BIN\n");prompt(m);
        wait_text(m,"0000 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F");
        wait_text(m,"0070 70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F");
    } else if(name=="DDT") {
        type(m,"DDT\n");wait_text(m,"DDT VERS 2.2");frames(m,100);
        for(unsigned i=0x4000;i<0x4006;++i)m.pokeMemory(i,0xa3);
        type(m,"F4001,4004,5A\n");frames(m,100);
        require(m.peekMemory(0x4000)==0xa3 && m.peekMemory(0x4005)==0xa3,"DDT fill crossed boundaries");
        for(unsigned i=0x4001;i<=0x4004;++i)require(m.peekMemory(i)==0x5a,"DDT fill failed");
        type(m,"G0\n");prompt(m);
    } else if(name=="ED") {
        type(m,"ED NOTES.TXT\n");wait_text(m,"NEW FILE");wait_text(m,": *");frames(m,50);
        type(m,"I\nEDITED ON SD\n");type(m,std::string(1,27)+"Z");frames(m,500);
        type(m,"E\n");prompt(m);
    } else if(name=="STAT") {
        type(m,"STAT\n");prompt(m);wait_text(m,"R/W, Space:");
        type(m,"STAT A:DSK:\n");prompt(m);wait_text(m,"8192: Kilobyte Drive  Capacity");
        type(m,"STAT A:HELLO.COM\n");prompt(m);wait_text(m,"Recs");wait_text(m,"HELLO.COM");
    } else if(name=="SYNC") {
        type(m,"SYNC\n");prompt(m);wait_text(m,"SYNC: SD cache flushed");
    } else if(name=="DIR") {
        type(m,"DIR *.COM\n");prompt(m);
        const auto listing=screen(m);
        bool multi=false;
        for(unsigned row=0;row<24;++row) {
            auto line=listing.substr(row*80,80);
            auto first=line.find(".COM");
            if(first!=std::string::npos && line.find(".COM",first+4)!=std::string::npos)
                multi=true;
        }
        require(multi,"DIR did not print multiple files per row");
    } else if(name=="RAMTEST") {
        type(m,"COPY A:HELLO.COM L:KEEP.COM\n");prompt(m);
        m.pokeMemory(0x9000,0);type(m,"RAMTEST\n");
        for(int i=0;i<1000 && m.peekMemory(0x9000)==0;++i)frames(m,100);
        require(m.peekMemory(0x9000)==0xa5,"RAMTEST failed");
        prompt(m);wait_text(m,"RAMTEST PASS");
        type(m,"L:KEEP\n");prompt(m);wait_text(m,"Hello from an original Z80");
        type(m,"DIR L:RAMTEST.DAT\n");prompt(m);
        // Independently ask BDOS: successful test removes only its own file.
        fcb(m,"RAMTEST DAT");
        require(bdos(m,15,0x8200)==255,"RAMTEST left its test file behind");
    } else if(name=="RAMEXISTS") {
        type(m,"COPY A:HELLO.COM L:RAMTEST.DAT\n");prompt(m);
        m.pokeMemory(0x9000,0);type(m,"RAMTEST\n");prompt(m);
        require(m.peekMemory(0x9000)==0xee,"RAMTEST overwrote an existing test file");
        wait_text(m,"already exists; no files changed");
        fcb(m,"RAMTEST DAT");
        require(bdos(m,15,0x8200)!=255,"Existing RAMTEST.DAT vanished");
        bdos(m,26,0x8300);
        require(bdos(m,20,0x8200)==0 && m.peekMemory(0x8300)==0x11,
                "Existing test file contents changed");
    } else if(name=="CPMABORT") {
        m.pokeMemory(0x9000,0);type(m,"CPMTEST\n");
        wait_text(m,"Write patterns [");
        m.setKey(4,0,true);frames(m,300); // Escape prefix, held across I/O.
        m.setKey(4,0,false);frames(m,300);
        m.setKey(3,4,true); // C -> Ctrl-C through the console escape prefix.
        for(int i=0;i<100 && m.peekMemory(0x9000)==0;++i)frames(m,100);
        m.setKey(3,4,false);
        require(m.peekMemory(0x9000)==0xcc,"CPMTEST did not abort between records");
        prompt(m);wait_text(m,"CPMTEST ABORTED");
    } else if(name=="ZORK1" || name=="ZORK2" || name=="ZORK3") {
        type(m,"C:\n");frames(m,50);
        type(m,name+"\n");
        wait_text(m,name=="ZORK1"?"West of House":name=="ZORK2"?"Inside the Barrow":"Endless Stair");
        type(m,"LOOK\n");frames(m,300);
        require(screen(m).find("Error: command")==std::string::npos,"Zork failed after LOOK");
    } else if(name=="CPMTEST") {
        m.pokeMemory(0x9000,0);type(m,"CPMTEST\n");
        wait_text(m,"Write patterns [");
        wait_text(m,"030/600");
        for(int i=0;i<1000 && m.peekMemory(0x9000)==0;++i)frames(m,200);
        require(m.peekMemory(0x9000)==0xa5,"CPMTEST failed");prompt(m);wait_text(m,"CPMTEST PASS");
        // Native P2000 code 5Fh draws '#'; ASCII 23h would draw sterling.
        wait_text(m,"Read and verify [____________________] 600/600 OK");
        wait_text(m,"Random read: record 513 ...  OK");
    } else throw std::runtime_error("Unknown isolated program");
    std::cout << "PASS: isolated " << name << std::endl;
}

int main(int argc,char **argv) {
    P2000Machine m;
    try {
        require(argc==4 || argc==5,"Usage: cpm-test EMULATOR BUILD CARD [PROGRAM]");
        std::string error;
        require(m.loadMonitor(std::string(argv[1])+"/assets/roms/p2000.rom",&error),error);
        require(m.loadCartridge(std::string(argv[2])+"/cartridge.bin",&error),error);
        m.installCoBoard();m.sdCartridge().install();
        require(m.sdCartridge().insert(argv[3],false,&error),error);
        frames(m,700);
        require(screen(m).find("A>")!=std::string::npos,"Missing command prompt");
        if(argc==5) {program_test(m,argv[4]);return 0;}
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
        type(m,"COPY A:HELLO.COM L:HELLO.COM\n");prompt(m);
        require(screen(m).find("Copy complete.")!=std::string::npos,"Original COPY failed");
        type(m,"L:HELLO\n");prompt(m);
        type(m,"ERA L:HELLO.COM\n");prompt(m);
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
        std::cout << "PASS: CCP loads COM, BDOS sequential/random files span extents and both RAM banks on L:, close/reopen/size/delete" << std::endl;
    } catch(const std::exception &e) {
        std::cerr << e.what() << "; PC=" << std::hex << m.programCounter() << '\n';
        for(int row=0;row<24;++row) std::cerr << screen(m).substr(row*80,80) << '\n';
        return 1;
    }
}
