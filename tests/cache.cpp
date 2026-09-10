#include "p2000_machine.h"
#include <cstdint>
#include <fstream>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static void require(bool ok,const std::string &why) {if(!ok)throw std::runtime_error(why);}
static unsigned word(P2000Machine &m,unsigned a) {return m.peekMemory(a)|(m.peekMemory(a+1)<<8);}
static std::string screen(P2000Machine &m) {return std::string((const char*)m.characters(),1920);}
static void frames(P2000Machine &m,int n) {while(n--)m.runFrame();}
struct Traffic {unsigned reads=0,writes=0; std::vector<std::uint32_t> commits;};

// Run real Z80 BIOS/BDOS code, observing the unchanged ROM I/O entry vectors.
// The NMI first enters a spin loop, so no I/O escapes the instruction observer.
static unsigned call(P2000Machine &m,unsigned address,unsigned bc=0,unsigned de=0,
                     Traffic *traffic=nullptr,std::uint32_t failLba=0xffffffff) {
    m.pokeMemory(0x66,0xc3);m.pokeMemory(0x67,0);m.pokeMemory(0x68,0x80);
    m.pokeMemory(0x8000,0xc3);m.pokeMemory(0x8001,0);m.pokeMemory(0x8002,0x80);
    m.requestNmi();frames(m,1);
    const unsigned char code[]={0x31,0,0x95,0x01,(unsigned char)bc,(unsigned char)(bc>>8),
        0x11,(unsigned char)de,(unsigned char)(de>>8),0xcd,(unsigned char)address,(unsigned char)(address>>8),
        0x32,0x70,0x9e,0x22,0x72,0x9e,0x3e,0x5a,0x32,0x71,0x9e,0x76};
    for(unsigned i=0;i<sizeof(code);++i)m.pokeMemory(0x8000+i,code[i]);
    m.pokeMemory(0x9e71,0);
    unsigned steps=0;
    while(m.peekMemory(0x9e71)!=0x5a && steps++<20000000) {
        if(m.programCounter()==0xe006 &&
           (word(m,0x9e00)|(std::uint32_t(word(m,0x9e02))<<16))==failLba) {
            m.sdCartridge().eject();failLba=0xffffffff;
        }
        if(traffic) {
            if(m.programCounter()==0xe003)++traffic->reads;
            if(m.programCounter()==0xe006) {
                ++traffic->writes;
                traffic->commits.push_back(word(m,0x9e00)|(std::uint32_t(word(m,0x9e02))<<16));
            }
        }
        m.stepInstruction();
    }
    require(steps<20000000,"Cache call failed to return");
    return m.peekMemory(0x9e70);
}
static unsigned bios(P2000Machine &m,unsigned index,unsigned bc=0,Traffic *t=nullptr) {
    return call(m,0xc000+3*index,bc,0,t);
}
static void select(P2000Machine &m,unsigned drive,unsigned rec) {
    bios(m,9,drive);require(word(m,0x9e72)!=0,"Drive selection failed");
    bios(m,10,rec/128);bios(m,11,rec%128);bios(m,12,0x8400);
}
static void pattern(P2000Machine &m,unsigned rec) {
    for(unsigned i=0;i<128;++i)m.pokeMemory(0x8400+i,(rec^i)&255);
}
static std::vector<unsigned char> sector(const std::string &path,unsigned lba) {
    std::ifstream in(path,std::ios::binary);in.seekg(std::uint64_t(lba)*512);
    std::vector<unsigned char> bytes(512);in.read((char*)bytes.data(),512);
    require(bool(in),"Cannot read backing sector");return bytes;
}
static void boot(P2000Machine &m,const std::string &emu,const std::string &build,const std::string &card) {
    std::string error;
    require(m.loadMonitor(emu+"/assets/roms/p2000.rom",&error),error);
    require(m.loadCartridge(build+"/cartridge.bin",&error),error);
    m.installCoBoard();m.sdCartridge().install();
    require(m.sdCartridge().insert(card,false,&error),error);frames(m,700);
    require(screen(m).find("A>")!=std::string::npos,"Cache fixture did not boot");
}
static Traffic workload(P2000Machine &m,bool cached) {
    Traffic t;
    for(unsigned rec=128;rec<160;++rec) {
        select(m,0,rec);pattern(m,rec);require(bios(m,14,0,&t)==0,"Sequential write failed");
    }
    for(unsigned rec=128;rec<160;++rec) {
        select(m,0,rec);require(bios(m,13,0,&t)==0,"Sequential read failed");
        for(unsigned i=0;i<128;++i)require(m.peekMemory(0x8400+i)==((rec^i)&255),"Cached data mismatch");
    }
    if(cached)require(bios(m,17,0,&t)==0,"Benchmark flush failed");
    return t;
}
int main(int argc,char **argv) {
    try {
        require(argc==4 || argc==5,"Usage: cache-test EMULATOR BUILD CARD [BASELINE_KERNEL]");
        const std::string emu=argv[1],build=argv[2],card=argv[3];
        // Exercise actual file CLOSE and warm boot on a separate clean volume.
        const std::string fileCard=card+".files";
        std::filesystem::copy_file(card,fileCard);
        {
            P2000Machine file;boot(file,emu,build,fileCard);
            for(unsigned i=0;i<36;++i)file.pokeMemory(0x8200+i,0);
            file.pokeMemory(0x8200,1);
            const std::string name="CACHE   DAT";
            for(unsigned i=0;i<11;++i)file.pokeMemory(0x8201+i,name[i]);
            require(call(file,5,22,0x8200)!=255,"Create cache fixture failed");
            call(file,5,26,0x8400);
            for(unsigned rec=0;rec<4;++rec) {
                pattern(file,rec+50);
                require(call(file,5,21,0x8200)==0,"Buffered file write failed");
            }
            require(sector(fileCard,133120)[15]==0,"Unclosed metadata was prematurely committed");
            Traffic close;
            require(call(file,5,16,0x8200,&close,133120)==255,"CLOSE hid directory flush failure");
            require(close.commits==std::vector<std::uint32_t>{133152,133120},"CLOSE commit order incorrect");
            require(file.peekMemory(0xdc91)==0 && file.peekMemory(0xdc99)==1,"Directory failure lost dirty metadata");
            auto data=sector(fileCard,133152);
            for(unsigned i=0;i<512;++i)require(data[i]==((50+i/128)^(i%128)),"CLOSE data not persisted");
            require(sector(fileCard,133120)[15]==0,"Failed directory write changed length");
            std::string error;
            require(file.sdCartridge().insert(fileCard,false,&error),error);
            require(call(file,5,16,0x8200)!=255,"CLOSE retry failed");
            require(sector(fileCard,133120)[15]==4,"CLOSE did not persist file size");
            pattern(file,99);require(call(file,5,21,0x8200)==0,"Warm-boot fixture write failed");
            require(file.sdCartridge().insert(fileCard,true,&error),error);
            file.pokeMemory(0x66,0xc3);file.pokeMemory(0x67,3);file.pokeMemory(0x68,0xc0);
            file.requestNmi();frames(file,100);
            require(screen(file).find("SD flush failed: dirty data retained")!=std::string::npos,
                    "Warm boot silently ignored failed commit");
            require(file.peekMemory(0xdc91)==1 && file.peekMemory(0xdc99)==1,"Warm boot discarded pending file");
            require(file.sdCartridge().insert(fileCard,false,&error),error);
            file.setKey(4,7,true);frames(file,300);file.setKey(4,7,false);frames(file,20);
            require(!file.peekMemory(0xdc91) && !file.peekMemory(0xdc99),"Warm boot R did not commit");
            require(sector(fileCard,133153)[0]==99 && sector(fileCard,133120)[15]==5,
                    "Warm boot lost file data or length");
            std::cout<<"PASS: CLOSE ordering, directory-write failure retention, retry and warm-boot recovery\n";
        }
        P2000Machine m;boot(m,emu,build,card);
        auto t=workload(m,true);
        require(t.reads==16 && t.writes==8,"Sequential sector coalescing regressed");
        std::cout<<"PASS: 32 writes + 32 reads: "<<t.reads<<" sector reads, "<<t.writes<<" sector writes\n";

        // Interleaved directory/data updates must stay in their separate slots.
        call(m,5,13);Traffic pair;
        for(unsigned i=0;i<4;++i) {
            select(m,0,256+i);pattern(m,256+i);require(bios(m,14,0,&pair)==0,"Data staging failed");
            select(m,0,i);pattern(m,40+i);require(bios(m,14,0,&pair)==0,"Directory staging failed");
        }
        require(pair.reads==2 && pair.writes==0,"Directory traffic evicted dirty data");
        require(bios(m,17,0,&pair)==0,"Ordered commit failed");
        require(pair.commits==std::vector<std::uint32_t>{133120+64,133120},"Metadata committed before data");

        // Failed writeback must retain both dirty buffers, stop metadata commit,
        // refuse cache replacement, and succeed on explicit retry with same card.
        select(m,0,300);pattern(m,0x66);require(bios(m,14)==0,"Staging data failed");
        select(m,0,4);pattern(m,0x77);require(bios(m,14)==0,"Staging metadata failed");
        auto oldData=sector(card,133120+75),oldDirectory=sector(card,133121);
        std::string error;
        require(m.sdCartridge().insert(card,true,&error),error);require(call(m,0xe009)==0,"Read-only init failed");
        Traffic failed;
        require(bios(m,17,0,&failed)==1,"Failed flush reported success");
        require(failed.commits==std::vector<std::uint32_t>{133120+75},"Metadata flushed after data failure");
        require(m.peekMemory(0xdc91)==1 && m.peekMemory(0xdc99)==1,"Dirty state lost on failure");
        require(sector(card,133120+75)==oldData && sector(card,133121)==oldDirectory,"Failed flush changed disk");
        bios(m,10,3);bios(m,11,0);
        require(bios(m,13)==1 && m.peekMemory(0xdc91)==1,"Fault allowed dirty cache eviction");
        require(m.sdCartridge().insert(card,false,&error),error);
        require(bios(m,17)==0,"Original-card retry failed");
        require(sector(card,133120+75)[0]==0x66 && sector(card,133121)[0]==0x77,"Recovered data not persisted");
        require(!m.peekMemory(0xdc91) && !m.peekMemory(0xdc99),"Dirty flags not cleared after commit");

        // A failed fill must invalidate the destination, never publish partial data.
        m.sdCartridge().eject();bios(m,10,4);bios(m,11,0);
        require(bios(m,13)==1 && m.peekMemory(0xdc90)==0,"Failed read left a valid cache tag");
        require(m.sdCartridge().insert(card,false,&error),error);require(call(m,0xe009)==0,"Reinsert init failed");
        require(bios(m,13)==0,"Read did not recover after failed fill");

        // Write-hint 1 is an immediate ordered barrier; neighbour bytes survive.
        select(m,0,600);auto before=sector(card,133120+150);pattern(m,0x39);
        require(bios(m,14,1)==0,"Immediate write barrier failed");
        auto after=sector(card,133120+150);
        for(unsigned i=0;i<512;++i)require(after[i]==(i<128?(0x39^i):before[i]),"Neighbour preservation failed");
        // Drive changes commit before selecting the new partition.
        select(m,0,604);pattern(m,0x58);require(bios(m,14)==0,"Pre-switch write failed");
        select(m,1,604);require(sector(card,133120+151)[0]==0x58,"Drive switch lost dirty data");
        pattern(m,0x69);require(bios(m,14)==0,"Partition B write failed");
        require(call(m,5,13)==0,"Disk reset flush failed");
        require(sector(card,149504+151)[0]==0x69,"Disk reset failed to persist partition B");
        std::cout<<"PASS: independent caches, data-before-directory commits, failure retention/retry, failed-fill invalidation, barriers, neighbours and drive isolation\n";

        if(argc==5) {
            // Optional measured comparison with a saved pre-cache kernel.
            P2000Machine baseline;boot(baseline,emu,build,card);
            std::ifstream in(argv[4],std::ios::binary);
            std::vector<unsigned char> kernel((std::istreambuf_iterator<char>(in)),{});
            require(kernel.size()==16384,"Bad baseline kernel");
            for(unsigned i=0;i<kernel.size();++i)baseline.pokeMemory(0xa000+i,kernel[i]);
            baseline.pokeMemory(0x66,0xc3);baseline.pokeMemory(0x67,0);baseline.pokeMemory(0x68,0xc0);
            baseline.requestNmi();frames(baseline,700);
            auto old=workload(baseline,false);
            require(old.reads==64 && old.writes==32,"Unexpected baseline sector counts");
            std::cout<<"MEASURED baseline: "<<old.reads<<" reads + "<<old.writes<<" writes; cache: "<<t.reads<<" + "<<t.writes<<" (75% fewer transfers)\n";
        }
        return 0;
    }catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}
}
