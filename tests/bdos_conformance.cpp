#include "p2000_machine.h"
#include "memory_layout.h"
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static void require(bool ok,const std::string &why) {if(!ok)throw std::runtime_error(why);}
static unsigned word(P2000Machine &m,unsigned a) {return m.peekMemory(a)|(m.peekMemory(a+1)<<8);}
static std::string screen(P2000Machine &m) {return std::string((const char*)m.characters(),1920);}
static std::vector<unsigned char> read_bytes(const std::string &path,unsigned long long offset,unsigned size) {
    std::ifstream in(path,std::ios::binary);in.seekg(offset);std::vector<unsigned char> data(size);
    in.read((char*)data.data(),size);require(bool(in),"Read test media");return data;
}
struct Harness {
    P2000Machine m;
    bool fatal=false;
    Harness(const std::string &emu,const std::string &build,const std::string &card) {
        std::string error;
        require(m.loadMonitor(emu+"/assets/roms/p2000.rom",&error),error);
        require(m.loadCartridge(build+"/cartridge.bin",&error),error);
        m.installCoBoard();m.sdCartridge().install();
        require(m.sdCartridge().insert(card,false,&error),error);
        for(unsigned i=0;i<700;++i)m.runFrame();
        require(screen(m).find("A>")!=std::string::npos,"Boot conformance fixture");
    }
    void start(unsigned target,unsigned bc,unsigned de=0) {
        // Dispatch NMI into a parked loop, then observe every instruction of the call.
        m.pokeMemory(0x66,0xc3);m.pokeMemory(0x67,0);m.pokeMemory(0x68,0x80);
        m.pokeMemory(0x8000,0xc3);m.pokeMemory(0x8001,0);m.pokeMemory(0x8002,0x80);
        m.requestNmi();m.runFrame();
        const unsigned char code[]={0xf3,0x31,0,0x95,0x01,(unsigned char)bc,(unsigned char)(bc>>8),
            0x11,(unsigned char)de,(unsigned char)(de>>8),0xcd,(unsigned char)target,(unsigned char)(target>>8),
            0x22,0x42,0x9e,0x32,0x40,0x9e,0x3e,0x5a,0x32,0x41,0x9e,0x76};
        for(unsigned i=0;i<sizeof(code);++i)m.pokeMemory(0x8000+i,code[i]);
        m.pokeMemory(0x9e41,0);fatal=false;
    }
    unsigned finish() {
        for(unsigned i=0;i<30000000;++i) {
            if(m.programCounter()==p2m_layout::bdos_disk_error) {
                fatal=true;
                for(unsigned n=0;n<100;++n)m.runFrame();
                require(screen(m).find("BDOS disk error")!=std::string::npos,"Missing hard-error diagnostic");
                return 0xffff;
            }
            if(m.peekMemory(0x9e41)==0x5a)return m.peekMemory(0x9e40);
            m.stepInstruction();
        }
        throw std::runtime_error("Call timed out: "+screen(m));
    }
    unsigned bdos(unsigned fn,unsigned arg=0) {start(5,fn,arg);return finish();}
    unsigned bios(unsigned fn,unsigned bc=0) {start(p2m_layout::bios+3*fn,bc);return finish();}
    void fcb(const std::string &name,unsigned drive) {
        require(name.size()==11,"FCB name length");
        for(unsigned i=0;i<36;++i)m.pokeMemory(0x8200+i,0);
        m.pokeMemory(0x8200,drive+1);
        for(unsigned i=0;i<11;++i)m.pokeMemory(0x8201+i,name[i]);
    }
    void position(unsigned rec) {
        m.pokeMemory(0x8221,rec);m.pokeMemory(0x8222,rec>>8);m.pokeMemory(0x8223,0);
        m.pokeMemory(0x820c,(rec>>7)&31);m.pokeMemory(0x820e,rec>>12);m.pokeMemory(0x8220,rec&127);
    }
    void fill(unsigned byte) {for(unsigned i=0;i<128;++i)m.pokeMemory(0x8400+i,byte);bdos(26,0x8400);}
    void create(const std::string &name,unsigned drive,unsigned byte=0x5a) {
        fcb(name,drive);require(bdos(22,0x8200)!=255,"MAKE "+name);fill(byte);
        require(bdos(21,0x8200)==0,"WRITE "+name);require(bdos(16,0x8200)!=255,"CLOSE "+name);
    }
    void queue(const std::vector<unsigned char> &bytes) {
        require(bytes.size()<64,"Input queue capacity");
        m.pokeMemory(p2m_layout::key_tail,0);
        for(unsigned i=0;i<bytes.size();++i)m.pokeMemory(0xdcc0+i,bytes[i]);
        m.pokeMemory(p2m_layout::key_head,bytes.size());
    }
    void line(const std::vector<unsigned char> &keys,const std::vector<unsigned char> &expected,unsigned max=40) {
        m.pokeMemory(0x8500,max);m.pokeMemory(0x8501,0xa5);
        m.pokeMemory(0x8502+max,0xa5);queue(keys);
        require(bdos(10,0x8500)==0,"Read line");
        require(m.peekMemory(0x8501)==expected.size(),"Line length mismatch");
        for(unsigned i=0;i<expected.size();++i)require(m.peekMemory(0x8502+i)==expected[i],"Edited line mismatch");
        require(m.peekMemory(0x8502+max)==0xa5,"Line buffer overrun");
    }
};

static void files(Harness &h) {
    for(unsigned drive : {10u,11u}) {
        const unsigned next=drive==11?128:256;
        h.create("PROTECT DAT",drive);
        h.m.pokeMemory(0x8209,'D'|128);require(h.bdos(30,0x8200)!=255,"Set R/O");
        for(unsigned fn : {21u,34u,40u}) {
            h.fcb("PROTECT DAT",drive);require(h.bdos(15,0x8200)!=255,"Open R/O");
            h.m.pokeMemory(0x8209,'D'); // protection must come from disk, not trusted FCB bits
            h.position(next);require(h.bdos(fn,0x8200)==255 && !h.fatal,"New extent bypassed R/O");
            require(h.bdos(35,0x8200)==0 && word(h.m,0x8221)==1,"R/O size changed");
        }
        h.fcb("PROTECT DAT",drive);h.m.pokeMemory(0x8209,'D');require(h.bdos(30,0x8200)!=255,"Clear R/O");
        h.position(next);require(h.bdos(40,0x8200)==0,"Writable extension rejected");
        h.create("WILDA   DAT",drive,0x41);h.create("WILDB   DAT",drive,0x42);
        h.position(next);require(h.bdos(34,0x8200)==0,"Second file extent");
        for(unsigned cr : {0u,127u,128u,255u}) {
            h.fcb("WILD?   DAT",drive);h.m.pokeMemory(0x8220,cr);
            require(h.bdos(15,0x8200)!=255,"OPEN incorrectly used CR");
            require(h.m.peekMemory(0x8220)==cr,"OPEN changed CR");
            require(h.m.peekMemory(0x8205)=='A',"Wildcard OPEN not bound to WILDA");
            h.position(next);require(h.bdos(33,0x8200)==4,"Wildcard read crossed files");
            h.position(0);require(h.bdos(33,0x8200)==0 && h.m.peekMemory(0x8400)==0x41,"Wildcard read wrong data");
        }
        h.bdos(32,1);h.create("OTHER   DAT",drive);h.bdos(32,0);h.bdos(14,drive);
        h.fcb("???????????",drive);h.m.pokeMemory(0x8200,'?');h.m.pokeMemory(0x820c,'?');
        unsigned count=0;bool free=false,user1=false;unsigned result=h.bdos(17,0x8200);
        while(result!=255) {
            require(result==(count&3),"Raw directory slot index");
            unsigned user=h.m.peekMemory(0x8400+32*result);
            free|=user==0xe5;user1|=user==1;++count;result=h.bdos(18);
            require(count<=512,"Unbounded search");
        }
        require(count==(drive==11?64u:512u) && free && user1,"Raw search omitted directory entries/users");
        require(h.bdos(18)==255,"Search Next did not stay exhausted");
    }
    h.bdos(13);
    for(unsigned drive=0;drive<12;++drive) {
        require(h.bdos(14,drive)==0,"Select drive");h.bdos(24);
        require(word(h.m,0x9e42)&(1u<<drive),"Select did not log in drive");
    }
    h.bdos(24);unsigned before=word(h.m,0x9e42);
    require(h.bdos(14,12)==255,"Invalid drive accepted");h.bdos(24);
    require(word(h.m,0x9e42)==before,"Invalid drive changed login vector");
}

static void corruption(Harness &h,const std::string &card) {
    for(unsigned drive : {9u,11u}) {
        h.create("POINTER DAT",drive);
        // Find its directory record and slot via the public search result.
        h.fcb("POINTER DAT",drive);h.bdos(26,0x8600);
        unsigned slot=h.bdos(17,0x8200);require(slot<4,"Find corruption fixture");
        std::vector<unsigned char> original(128);
        for(unsigned i=0;i<128;++i)original[i]=h.m.peekMemory(0x8600+i);
        const std::vector<unsigned> blocks=drive==11?std::vector<unsigned>{1,128,255}:std::vector<unsigned>{1,2,3,2048,2049,65535};
        // J: is fresh; the earlier L: fixtures occupy the first six slots.
        unsigned record=drive==11?1:0;
        for(unsigned block:blocks) {
            for(unsigned i=0;i<128;++i)h.m.pokeMemory(0x8600+i,original[i]);
            h.m.pokeMemory(0x8610+slot*32,block);
            if(drive!=11)h.m.pokeMemory(0x8611+slot*32,block>>8);
            h.bios(9,drive);h.bios(10,0);h.bios(11,record);h.bios(12,0x8600);
            require(h.bios(14,1)==0,"Inject invalid allocation pointer");
            auto snapshot=drive==11?std::vector<unsigned char>{}:read_bytes(card,(133120ull+drive*16384ull)*512,16384);
            for(unsigned fn : {20u,21u,33u,34u,40u}) {
                h.bdos(13);h.fill(0xa5);h.fcb("POINTER DAT",drive);
                require(h.bdos(15,0x8200)!=255,"Open corruption fixture");
                require(h.bdos(fn,0x8200)==0xffff && h.fatal,"Corrupt pointer not a hard error");
                if(drive!=11)require(read_bytes(card,(133120ull+drive*16384ull)*512,16384)==snapshot,"Corrupt pointer overwrote directory");
            }
        }
        for(unsigned i=0;i<128;++i)h.m.pokeMemory(0x8600+i,original[i]);
        unsigned last=drive==11?127:2047;
        h.m.pokeMemory(0x8610+slot*32,last);
        if(drive!=11)h.m.pokeMemory(0x8611+slot*32,last>>8);
        h.bios(9,drive);h.bios(10,0);h.bios(11,record);h.bios(12,0x8600);
        require(h.bios(14,1)==0,"Install last valid block fixture");
        h.bdos(13);h.fill(0x67);h.fcb("POINTER DAT",drive);
        require(h.bdos(15,0x8200)!=255 && h.bdos(34,0x8200)==0,"Last valid block rejected");
        require(h.bdos(16,0x8200)!=255,"Commit last valid block");h.fill(0);
        require(h.bdos(33,0x8200)==0 && h.m.peekMemory(0x8400)==0x67,"Last valid block read failed");
        for(unsigned i=0;i<128;++i)h.m.pokeMemory(0x8600+i,original[i]);
        h.bios(9,drive);h.bios(10,0);h.bios(11,record);h.bios(12,0x8600);require(h.bios(14,1)==0,"Restore fixture");
    }
    h.bdos(13);h.fill(0);h.fcb("POINTER DAT",9);require(h.bdos(15,0x8200)!=255,"Open I/O fixture");
    h.bdos(13);h.m.sdCartridge().eject();
    require(h.bdos(20,0x8200)==0xffff && h.fatal,"Absent card returned ordinary EOF");
    std::string error;require(h.m.sdCartridge().insert(card,false,&error),error);
    h.bdos(13);h.fill(0);h.fcb("POINTER DAT",9);require(h.bdos(15,0x8200)!=255,"Restore card");
    require(h.bdos(20,0x8200)==0,"Read restored card");require(h.bdos(20,0x8200)==1,"Normal EOF no longer works");
}

static void console(Harness &h) {
    h.bdos(6,12);
    h.line({'a',9,8,'b',13},{'a','b'});
    require(screen(h.m).substr(0,9)=="ab       ","TAB deletion left display cells");
    h.line({'a',9,'b',13},{'a',9,'b'});
    h.line({'a',9,8,'b',13},{'a','b'});
    h.line({'a','b',18,'c',13},{'a','b','c'});
    h.line({'a',5,'b',8,8,'c',13},{'c'});
    h.line({'a',9,24,'b',13},{'b'});
    h.line({'a',9,21,'b',13},{'b'});
    h.line({'a',3,'b',13},{'a',3,'b'});
    h.line({'a','b','c'},{'a','b','c'},3);
    h.bdos(6,12);for(unsigned i=0;i<31;++i)h.bdos(6,' ');
    std::vector<unsigned char> wrap(50,'a');wrap.push_back(8);wrap.push_back(8);wrap.push_back('b');wrap.push_back('c');wrap.push_back(13);
    std::vector<unsigned char> expected(48,'a');expected.push_back('b');expected.push_back('c');h.line(wrap,expected,60);
    require(screen(h.m).substr(31,50)==std::string(expected.begin(),expected.end()),"Backspace across column zero corrupted display");
    for(unsigned fn : {2u,9u}) {
        h.queue({19});
        const std::string message="FLOW$";for(unsigned i=0;i<message.size();++i)h.m.pokeMemory(0x8700+i,message[i]);
        auto before=screen(h.m);h.start(5,fn,fn==2?'X':0x8700);
        for(unsigned n=0;n<30000;++n)h.m.stepInstruction();
        require(h.m.peekMemory(0x9e41)!=0x5a && screen(h.m)==before,"Ctrl-S failed to pause cooked output");
        h.queue({17,'k'});require(h.finish()==0,"Ctrl-Q failed to resume");
        require(h.bdos(6,255)=='k',"Cooked output stole ordinary type-ahead");
    }
    h.queue({19});require(h.bdos(6,255)==19,"Direct input filtered Ctrl-S");
    h.queue({19});require(h.bdos(6,'X')==0,"Direct output blocked");
    require(h.bdos(6,255)==19,"Direct output consumed input");
    h.queue({19,17,'z'});require(h.bdos(1)=='z',"Cooked input flow control");
    for(unsigned fn : {10u,2u}) {
        h.m.pokeMemory(0x8500,40);h.queue(fn==10?std::vector<unsigned char>{3}:std::vector<unsigned char>{19,3});
        h.start(5,fn,fn==10?0x8500:'X');bool warm=false;
        for(unsigned n=0;n<100000;++n) {
            if(h.m.programCounter()==p2m_layout::warm_boot){warm=true;break;}
            h.m.stepInstruction();
        }
        require(warm && h.m.peekMemory(0x9e41)!=0x5a,"Ctrl-C returned instead of warm boot");
        for(unsigned n=0;n<100;++n)h.m.runFrame();
    }
}
int main(int argc,char **argv) {
    try {
        require(argc==4,"Usage: bdos_conformance-test EMULATOR BUILD SCRATCH_CARD");
        Harness h(argv[1],argv[2],argv[3]);files(h);corruption(h,argv[3]);console(h);
        std::cout<<"PASS: protected extents, wildcard identity, OPEN CR, raw searches, login vectors, invalid blocks, hard I/O errors, line editing and cooked/raw flow control\n";
    } catch(const std::exception &e) {std::cerr<<e.what()<<'\n';return 1;}
}
