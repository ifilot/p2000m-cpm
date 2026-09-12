#include "p2000_machine.h"
#include "memory_layout.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
#include <chrono>

static void require(bool ok, const std::string &why) {
    if (!ok) throw std::runtime_error(why);
}
static std::string screen(P2000Machine &m) {
    return std::string(reinterpret_cast<const char *>(m.characters()), 1920);
}
static void frames(P2000Machine &m, int n) {
    while (n--) m.runFrame();
}
static void launch(P2000Machine &m, const std::string &emu, const std::string &build) {
    std::string error;
    require(m.loadMonitor(emu + "/assets/roms/p2000.rom", &error), error);
    require(m.loadCartridge(build + "/cartridge.bin", &error), error);
    m.installCoBoard();
    m.sdCartridge().install();
}
static unsigned invoke(P2000Machine &m, int entry, unsigned bc = 0) {
    // A test-only NMI trampoline calls the real BIOS without CPU service hooks.
    const unsigned char code[] = {
        0xf3,0x31,0,0x9c, 0x01,static_cast<unsigned char>(bc),static_cast<unsigned char>(bc >> 8),
        0xcd,static_cast<unsigned char>(p2m_layout::bios + entry * 3),
        static_cast<unsigned char>((p2m_layout::bios + entry * 3) >> 8),
        0x32,0x20,0x9e, 0x22,0x22,0x9e, 0x3e,0x5a,0x32,0x21,0x9e,0x76
    };
    m.pokeMemory(0x66,0xc3); m.pokeMemory(0x67,0); m.pokeMemory(0x68,0x80);
    for (unsigned i=0; i<sizeof(code); ++i) m.pokeMemory(0x8000+i,code[i]);
    m.pokeMemory(0x9e21,0);
    m.requestNmi();
    frames(m,20);
    require(m.peekMemory(0x9e21)==0x5a,"BIOS call did not return");
    return m.peekMemory(0x9e20);
}
static void select_record(P2000Machine &m, unsigned drive, unsigned record) {
    invoke(m,9,drive);
    const auto spt = drive == 11 ? 32 : 128;
    invoke(m,10,record/spt);
    invoke(m,11,record%spt);
    invoke(m,12,0x8100);
}
int main(int argc, char **argv) {
    try {
        require(argc == 4, "Usage: boot-test EMULATOR_SOURCE BUILD_DIR WRITABLE_TEST_IMAGE");
        const std::string emu = argv[1], build = argv[2];
        P2000Machine m;
        launch(m, emu, build);
        std::string error;
        require(m.sdCartridge().insert(build + "/p2000m-sd-template.img", true, &error), error);
        unsigned steps = 0;
        bool floppyBootstrap=false, entered=false, earlyMessage=false;
        unsigned entrySteps=0;
        while (m.programCounter()!=0xa000 && steps++ < 10000000) {
            if(m.programCounter()==0x0e90) floppyBootstrap=true;
            if(m.programCounter()==0x1010) entered=true;
            if(entered && !earlyMessage) {
                ++entrySteps;
                earlyMessage=screen(m).find("P2000M SD SYSTEM")<80;
            }
            m.stepInstruction();
        }
        require(!floppyBootstrap,"Monitor attempted floppy DOS before cartridge boot");
        require(earlyMessage && entrySteps<2000,"Cartridge did not print promptly after entry");
        require(m.programCounter()==0xa000,"Loader did not enter kernel");
        require(m.coBoardMapped(), "Cartridge did not activate co-board");
        {
            std::ifstream rom(build+"/cartridge.bin",std::ios::binary);
            rom.seekg(0x2000);
            for(unsigned address=p2m_layout::boot_loader_base;address<p2m_layout::boot_loader_end;++address)
                require(m.peekMemory(address)==static_cast<unsigned char>(rom.get()),
                        "Copied RAM loader differs from cartridge source");
        }
        const auto bootScreen = screen(m);
        require(bootScreen.find("attempt ")==std::string::npos,"Boot displays retry count");
        require(bootScreen.find("RECOVERED")==std::string::npos,"Boot displays recovery history");
        require(bootScreen.substr(11*80+65,12)=="          OK","SPI not shown established before kernel entry");
        require(bootScreen.find("System  v")!=std::string::npos,"Missing shared system version");
        require(bootScreen.find("pending verification")!=std::string::npos,"Pair verified before kernel entry");
        for (const auto *stage : {"P2000M SD SYSTEM", "CP/M 2.2 compatible",
                                 "RAM enabled  /  RAM loader 7000",
                                 "SPI mode", "MID 01  /  OEM PM",
                                 "STARTING KERNEL  /  entry A000"})
            require(bootScreen.find(stage) != std::string::npos,
                    std::string("Missing boot stage: ") + stage + " " + bootScreen);
        std::ifstream in(build + "/kernel.bin", std::ios::binary);
        std::vector<unsigned char> kernel((std::istreambuf_iterator<char>(in)), {});
        for (std::size_t i = 0; i < kernel.size(); ++i)
            require(m.peekMemory(0xa000 + i) == kernel[i], "SD-loaded kernel differs from binary");
        frames(m,300);
        require(screen(m).find("BOOT COMPLETE") != std::string::npos,
                "Kernel did not boot: PC=" + std::to_string(m.programCounter()) + " " + screen(m));
        require(screen(m).find("Cartridge + kernel  /  matched system release")!=std::string::npos,
                "Missing shared release verification");
        require(screen(m).substr(80,80)==bootScreen.substr(80,80),"Kernel replaced shared version/build identity");
        require(screen(m).find("C: ZORK") != std::string::npos &&
                screen(m).find("L: SCRATCH (RAM) 128KiB") != std::string::npos,
                "Missing named volume grid: " + screen(m));
        require(screen(m).substr(20*80+1,2)=="A>","Prompt not on line 21");
        require(screen(m).substr(3*80,80).find(std::to_string(p2m_layout::tpa_limit-0x100)+" bytes")!=std::string::npos,
                "Missing TPA capacity");
        for(unsigned row : {5u,6u,7u,9u,11u})
            require(screen(m).substr(row*80+65,12)=="          OK","Stale status suffix");
        require(screen(m).substr(21*80)==std::string(240,' '),"Stale output below prompt");
        for(unsigned row : {0u,8u,12u})
            for(unsigned col=1;col<79;++col)
                require(m.attributes()[row*80+col]==8,"Missing inverse heading");
        for(const auto &dump : {std::string("characters"),std::string("attributes")}) {
            std::ofstream out(build+"/boot-"+dump+".bin",std::ios::binary);
            out.write((const char*)(dump=="characters"?m.characters():m.attributes()),1920);
        }
        for (int drive = 0; drive < 4; ++drive)
            require(!m.hasDisk(drive), "Unexpected floppy media");
        // Valid cartridge checksum, wrong cross-link fingerprint: must stop
        // before the kernel can use incompatible ROM filesystem callbacks.
        {
            std::ifstream source(build+"/cartridge.bin",std::ios::binary);
            std::vector<unsigned char> rom((std::istreambuf_iterator<char>(source)),{});
            rom[0x101a]^=0x80;
            unsigned sum=0;for(unsigned i=5;i<rom.size();++i)sum+=rom[i];
            unsigned checksum=(-sum)&0xffff;
            rom[3]=checksum&255;rom[4]=checksum>>8;
            auto path=std::string(argv[3])+".mismatched-rom.bin";
            std::ofstream out(path,std::ios::binary);out.write((const char*)rom.data(),rom.size());out.close();
            P2000Machine mismatch;launch(mismatch,emu,build);
            require(mismatch.loadCartridge(path,&error),error);
            require(mismatch.sdCartridge().insert(build+"/p2000m-sd-template.img",true,&error),error);
            frames(mismatch,700);
            require(screen(mismatch).find("update port-1 ROM")!=std::string::npos,"ROM/kernel mismatch was accepted");
            require(screen(mismatch).find("A>")==std::string::npos,"Mismatched pair reached command prompt");
            require(screen(mismatch).find("matched system release")==std::string::npos,"Mismatched pair displayed as matched");
        }
        // On a read-only card, reads succeed and writes propagate rejection.
        // Corrupt only the first in-memory header/payload: each full-load retry
        // must repair the data without losing the disposable loader itself.
        for(unsigned faultPC : {p2m_layout::header_check,p2m_layout::kernel_checksum}) {
            P2000Machine retry;launch(retry,emu,build);
            require(retry.sdCartridge().insert(build+"/p2000m-sd-template.img",true,&error),error);
            unsigned count=0;
            while(retry.programCounter()!=faultPC && ++count<10000000)retry.stepInstruction();
            require(count<10000000,"Boot fault injection point not reached");
            unsigned address=faultPC==p2m_layout::header_check?0x9600:0xa000;
            retry.pokeMemory(address,retry.peekMemory(address)^0x80);
            frames(retry,700);
            require(screen(retry).find("BOOT COMPLETE")!=std::string::npos,"Boot content retry failed");
            require(retry.peekMemory(p2m_layout::rom_workspace+0x14)==2,"Full-load retry budget mismatch");
        }
        {
            P2000Machine late;launch(late,emu,build);
            unsigned calls=0,count=0;
            while(calls<2 && ++count<20000000) {
                if(late.programCounter()==p2m_layout::boot_sd_retry && ++calls==2)break;
                late.stepInstruction();
            }
            require(calls==2,"Absent card did not reach second initialization attempt");
            require(late.sdCartridge().insert(build+"/p2000m-sd-template.img",true,&error),error);
            frames(late,700);
            require(screen(late).find("BOOT COMPLETE")!=std::string::npos,"Delayed card did not recover");
            require(late.peekMemory(p2m_layout::rom_workspace+0x12)==2,"Delayed-card attempt count wrong");
            require(screen(late).find("attempt ")==std::string::npos,"Recovery displays retry count");
            require(screen(late).find("RECOVERED")==std::string::npos,"Recovery history still displayed");
            require(screen(late).substr(11*80+65,12)=="          OK","Recovered SPI not shown established");
        }
        {
            P2000Machine protectedCard;
            launch(protectedCard,emu,build);
            require(protectedCard.sdCartridge().insert(build+"/p2000m-sd-template.img",true,&error),error);
            frames(protectedCard,700);
            select_record(protectedCard,0,0);
            require(invoke(protectedCard,13)==0,"Read-only card read failed");
            require(invoke(protectedCard,14,1)==1,"Read-only immediate write was not rejected");
        }
        // Verify both SRAM banks, their boundary, and the last record.
        for (unsigned rec : {0u,511u,512u,1023u}) {
            select_record(m,11,rec);
            for (unsigned i=0;i<128;++i) m.pokeMemory(0x8100+i,(rec/512)^rec^i);
            require(invoke(m,14)==0,"SRAM write failed");
        }
        for (unsigned rec : {0u,511u,512u,1023u}) {
            select_record(m,11,rec);
            require(invoke(m,13)==0,"SRAM read failed");
            for (unsigned i=0;i<128;++i)
                require(m.peekMemory(0x8100+i)==static_cast<unsigned char>((rec/512)^rec^i),
                        "SRAM data or bank independence failure");
        }
        m.pokeMemory(0x66,0xc3);m.pokeMemory(0x67,(p2m_layout::bios+3)&255);m.pokeMemory(0x68,(p2m_layout::bios+3)>>8);
        m.requestNmi();frames(m,100);
        for(unsigned rec : {0u,511u,512u,1023u}) {
            select_record(m,11,rec);
            require(invoke(m,13)==0,"Warm-boot SRAM read failed");
            for(unsigned i=0;i<128;++i)
                require(m.peekMemory(0x8100+i)==static_cast<unsigned char>((rec/512)^rec^i),
                        "Warm boot destroyed RAM drive");
        }
        invoke(m,10,32);
        require(invoke(m,13)==1,"Out-of-range SRAM track accepted");
        select_record(m,0,0);
        invoke(m,10,512);
        require(invoke(m,14)==1,"Out-of-range SD track accepted");
        invoke(m,9,12);
        require(m.peekMemory(0x9e22)==0 && m.peekMemory(0x9e23)==0,"Invalid drive accepted");
        // Destroy both disposable boot regions, then invoke public BIOS BOOT.
        // It must switch back to the monitor, reload the loader/kernel, and
        // perform a genuine cold initialization (unlike WBOOT tested above).
        for(unsigned address=0x100;address<p2m_layout::tpa_limit;++address)m.pokeMemory(address,0xa5);
        m.pokeMemory(0x66,0xc3);
        m.pokeMemory(0x67,0);m.pokeMemory(0x68,0x80);
        m.pokeMemory(0x8000,0xc3);m.pokeMemory(0x8001,0);m.pokeMemory(0x8002,0x80);
        // runFrame dispatches the emulator's requested NMI; stepInstruction
        // alone does not. Stop in a spin loop before observing the switch.
        m.requestNmi();frames(m,1);
        m.pokeMemory(0x8001,p2m_layout::bios&255);
        m.pokeMemory(0x8002,p2m_layout::bios>>8);
        bool stockMap=false;
        for(unsigned count=0;count<100000 && !stockMap;++count) {
            m.stepInstruction();stockMap=!m.coBoardMapped();
        }
        require(stockMap,"Cold restart did not restore monitor mapping; PC="+
                std::to_string(m.programCounter())+" cache fault="+std::to_string(m.peekMemory(0xdca4))+
                " screen="+screen(m));
        frames(m,700);
        require(m.coBoardMapped() && screen(m).find("BOOT COMPLETE")!=std::string::npos,
                "Cold restart failed after TPA overwrite; PC="+std::to_string(m.programCounter())+" "+screen(m));
        require(m.peekMemory(0xa000)==0xc3,"Cold restart did not reload kernel");
        select_record(m,11,512);
        require(invoke(m,13)==0,"Cold-restarted RAM disk unavailable");
        for(unsigned i=0;i<128;++i)require(m.peekMemory(0x8100+i)==0xe5,"Cold restart did not format SRAM");
        std::cout << "PASS: RAM-loader copy, delayed card, header/checksum retry, cold restart after TPA overwrite\n";
        P2000Machine writable;
        launch(writable,emu,build);
        require(writable.sdCartridge().insert(argv[3],false,&error),error);
        frames(writable,700);
        require(screen(writable).find("BOOT COMPLETE")!=std::string::npos,"Writable card boot failed");
        const std::vector<unsigned> records{0,1,2,3,4,127,128,511,512,65534,65535};
        for(unsigned drive=0;drive<11;++drive) {
            for(unsigned rec:records) {
                select_record(writable,drive,rec);
                for(unsigned i=0;i<128;++i) writable.pokeMemory(0x8100+i,drive*73+rec+i*7);
                require(invoke(writable,14)==0,"SD record write failed");
            }
        }
        for(unsigned drive=0;drive<11;++drive) {
            for(unsigned rec:records) {
                select_record(writable,drive,rec);
                require(invoke(writable,13)==0,"SD record read failed");
                for(unsigned i=0;i<128;++i)
                    require(writable.peekMemory(0x8100+i)==static_cast<unsigned char>(drive*73+rec+i*7),
                            "SD deblocking or partition isolation failure");
            }
        }
        // Reopen backing file independently: verify every logical record of A/B,
        // including all untouched neighbours, and thus persistence of every write.
        require(invoke(writable,17)==0,"Explicit cache flush failed");
        std::ifstream persisted(argv[3],std::ios::binary);
        for(unsigned drive=0;drive<11;++drive) {
            persisted.seekg((133120ull+drive*16384ull)*512);
            for(unsigned rec=0;rec<65536;++rec) {
                bool changed=false;
                for(unsigned target:records) if(rec==target) changed=true;
                unsigned char data[128];
                persisted.read(reinterpret_cast<char *>(data),128);
                require(static_cast<bool>(persisted),"Backing image truncated");
                for(unsigned i=0;i<128;++i)
                    require(data[i]==(changed?static_cast<unsigned char>(drive*73+rec+i*7):0xe5),
                            "Persistent SD sector contents mismatch");
            }
        }
        writable.sdCartridge().eject();
        {
            std::fstream corrupt(argv[3],std::ios::binary|std::ios::in|std::ios::out);
            corrupt.seekg(16*512+100);
            char value=0;corrupt.get(value);
            corrupt.seekp(16*512+100);corrupt.put(value^1);corrupt.flush();
        }
        P2000Machine damaged;
        launch(damaged,emu,build);
        require(damaged.sdCartridge().insert(argv[3],true,&error),error);
        frames(damaged,700);
        require(screen(damaged).find("SD BOOT ERROR")!=std::string::npos,
                "Damaged system checksum was accepted");
        require(screen(damaged).find("kernel checksum mismatch")!=std::string::npos,
                "Checksum failure was not identified");
        P2000Machine absent;
        launch(absent, emu, build);
        frames(absent, 700); // Includes eight bounded reset/initialization attempts.
        require(screen(absent).find("SD BOOT ERROR") != std::string::npos,
                "Absent SD did not give a bounded boot error");
        require(absent.peekMemory(p2m_layout::rom_workspace+0x12)==8,
                "SD retry limit was not reached");
        require(screen(absent).find("attempt ")==std::string::npos,"Failure displays retry count");
        P2000Machine delayed;
        launch(delayed, emu, build);
        for (int i=0; i<300 && delayed.peekMemory(p2m_layout::rom_workspace+0x12)!=2; ++i)
            frames(delayed,1);
        require(delayed.peekMemory(p2m_layout::rom_workspace+0x12)==2,
                "No retry after initial absent card");
        require(delayed.sdCartridge().insert(build+"/p2000m-sd-template.img",true,&error),error);
        frames(delayed,700);
        require(screen(delayed).find("A>")!=std::string::npos,
                "Late card did not recover without a machine reset");
        for(const auto *stage : {"CHECKING SYSTEM HEADER", "LOADING KERNEL", "CHECKING SD LAYOUT"}) {
        P2000Machine interruptedRead;
        launch(interruptedRead,emu,build);
        require(interruptedRead.sdCartridge().insert(build+"/p2000m-sd-template.img",true,&error),error);
        unsigned readSteps=0;
        while(screen(interruptedRead).find(stage)==std::string::npos
              && readSteps++<10000000) interruptedRead.stepInstruction();
        require(readSteps<10000000,std::string("Read stage not reached: ")+stage);
        interruptedRead.sdCartridge().eject();
        for(int i=0;i<300 && screen(interruptedRead).find("RETRYING")==std::string::npos;++i)
            frames(interruptedRead,1);
        require(screen(interruptedRead).find("RETRYING")!=std::string::npos,
                std::string("I/O failure did not enter recovery: ")+stage);
        require(interruptedRead.sdCartridge().insert(build+"/p2000m-sd-template.img",true,&error),error);
        frames(interruptedRead,700);
        require(screen(interruptedRead).find("A>")!=std::string::npos,
                std::string("Boot read did not recover after card interruption: ")+stage);
        }
        std::cout << "PASS: co-board switch, byte-exact SD kernel load, SD deblocking and persistence across all eleven SD volumes, read-only errors, SRAM bank boundaries, disk bounds, absent-card error; no floppy media\n";
    } catch (const std::exception &e) {
        std::cerr << e.what() << '\n';
        return 1;
    }
}
