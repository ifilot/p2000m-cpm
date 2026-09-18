#include "p2000_machine.h"
#include "memory_layout.h"
#include "activity.h"
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static void require(bool ok,const std::string &why) {if(!ok)throw std::runtime_error(why);}
static unsigned word(P2000Machine &m,unsigned a) {return m.peekMemory(a)|(m.peekMemory(a+1)<<8);}
static void word(P2000Machine &m,unsigned a,unsigned value) {
    m.pokeMemory(a,value);m.pokeMemory(a+1,value>>8);
}
static std::string screen(P2000Machine &m) {return std::string((const char*)m.characters(),1920);}
static std::vector<unsigned char> sector(const std::string &path,unsigned lba) {
    std::ifstream in(path,std::ios::binary);in.seekg(std::uint64_t(lba)*512);
    std::vector<unsigned char> data(512);in.read((char*)data.data(),data.size());
    require(bool(in),"Cannot read backing sector");return data;
}
static unsigned crc16(P2000Machine &m,unsigned address) {
    unsigned crc=0;
    for(unsigned i=0;i<512;++i) {
        crc ^= m.peekMemory(address+i)<<8;
        for(unsigned bit=0;bit<8;++bit)crc=((crc<<1)^((crc&0x8000)?0x1021:0))&0xffff;
    }
    return crc;
}

enum class Fault {none, command, read_data, read_high, read_low,
                  write_data, write_high, write_low, cid_data, cid_crc, enable, init_command};

// Faults are introduced at the SPI bridge, without modifying the emulator or
// replacing any firmware service. RX faults drop a wire byte; TX faults alter
// the transmit latch after OUT 40h and before OUT 41h starts the transfer.
struct Wire {
    Activity activity;
    Fault fault=Fault::none;
    unsigned remaining=0, injected=0, reads=0, writes=0, enables=0;
    unsigned commandByte=0, readByte=0, writeByte=0, cidByte=0, skip=0;
    int tx=-1;
    bool enableSent=false;

    Wire(Fault f=Fault::none,unsigned count=0):fault(f),remaining(count) {}
    void step(P2000Machine &m) {
        unsigned pc=m.programCounter(), cmd=m.peekMemory(p2m_layout::rom_workspace+0x15);
        if(pc==p2m_layout::sd_read_retry)readByte=0;
        if(pc==0xe006)writeByte=0;
        if(pc==p2m_layout::boot_cid_read)cidByte=0;
        if(pc==p2m_layout::cmd_send) {
            if(remaining && fault==Fault::enable && cmd==59 && commandByte==0)tx=0xff;
            ++commandByte;
        }
        if(pc==p2m_layout::cmd_crc) {
            commandByte=0;
            if(cmd==0)enableSent=false;
            if(cmd==59)enableSent=true;
            if(cmd==41)require(enableSent,"ACMD41 preceded CMD59 after reset");
            if(cmd==17)++reads;
            if(cmd==24)++writes;
            if(cmd==59)++enables;
            if(remaining && fault==Fault::command && cmd==17)tx=0;
            if(remaining && fault==Fault::init_command && cmd==41)tx=0;
        }
        if(pc==p2m_layout::read_byte && readByte++==123 && remaining && fault==Fault::read_data)skip=1;
        if(pc==p2m_layout::boot_cid_byte && cidByte++==3 && remaining && fault==Fault::cid_data)skip=1;
        if(pc==p2m_layout::sd_crc16_check && remaining) {
            if(cmd==17 && fault==Fault::read_high)skip=1;
            if(cmd==17 && fault==Fault::read_low)skip=2;
            if(cmd==10 && fault==Fault::cid_crc)skip=1;
        }
        if(pc==p2m_layout::write_byte && writeByte++==123 && remaining && fault==Fault::write_data)
            tx=m.peekMemory(word(m,p2m_layout::rom_workspace+4)+123)^1;
        if(pc==p2m_layout::write_crc && remaining) {
            unsigned crc=crc16(m,word(m,p2m_layout::rom_workspace+4));
            if(fault==Fault::write_high)tx=(crc>>8)^1;
            if(fault==Fault::write_low)tx=0x100|((crc&255)^1);
        }
        if(pc==p2m_layout::spi_tx+2 && tx>=0) {
            if(tx&0x100)tx &= 255;
            else {m.writePort(0x40,tx);tx=-1;--remaining;++injected;}
        }
        if(pc==p2m_layout::spi_tx+12 && skip && --skip==0) {
            m.writePort(0x41,0);--remaining;++injected;
        }
        activity.step(m);
    }
};

static void launch(P2000Machine &m,const std::string &emu,const std::string &build,const std::string &card) {
    std::string error;
    require(m.loadMonitor(emu+"/assets/roms/p2000.rom",&error),error);
    require(m.loadCartridge(build+"/cartridge.bin",&error),error);
    m.installCoBoard();m.sdCartridge().install();
    require(m.sdCartridge().insert(card,false,&error),error);
}
static void boot(P2000Machine &m,Wire &wire,bool success=true) {
    const std::string marker=success?"A>":"SD BOOT ERROR";
    unsigned steps=0;
    while(++steps<30000000) {
        wire.step(m);
        if(steps%1000==0 && screen(m).find(marker)!=std::string::npos) {wire.activity.idle(m);return;}
    }
    throw std::runtime_error("Boot failed: "+screen(m));
}
static void run(P2000Machine &m,const std::vector<unsigned char> &code,Wire &wire) {
    // Park in a loop before replacing the trampoline, so every I/O instruction
    // of the tested call is observed (including with interrupts enabled).
    m.pokeMemory(0x66,0xc3);word(m,0x67,0x8000);
    m.pokeMemory(0x8000,0xc3);word(m,0x8001,0x8000);
    m.requestNmi();m.runFrame();
    for(unsigned i=0;i<code.size();++i)m.pokeMemory(0x8000+i,code[i]);
    m.pokeMemory(0x9e71,0);
    unsigned steps=0;
    while(!m.peekMemory(0x9e71) && ++steps<30000000)wire.step(m);
    require(steps<30000000,"CRC call did not return");
    wire.activity.idle(m);
}
static unsigned call(P2000Machine &m,unsigned address,Wire &wire,unsigned bc=0,unsigned de=0) {
    run(m,{0xf3,0x31,0,0x95,0x01,(unsigned char)bc,(unsigned char)(bc>>8),
        0x11,(unsigned char)de,(unsigned char)(de>>8),0xcd,(unsigned char)address,(unsigned char)(address>>8),
        0x32,0x70,0x9e,0x3e,1,0x32,0x71,0x9e,0x76},wire);
    return m.peekMemory(0x9e70);
}
static unsigned bios(P2000Machine &m,unsigned entry,Wire &wire,unsigned bc=0) {
    return call(m,p2m_layout::bios+3*entry,wire,bc);
}
static void vectors(P2000Machine &m) {
    for(bool seven : {false,true}) {
        const std::vector<std::vector<unsigned char>> inputs = seven ?
            std::vector<std::vector<unsigned char>>{{0x40,0,0,0,0},{0x48,0,0,1,0xaa}} :
            std::vector<std::vector<unsigned char>>{{'1','2','3','4','5','6','7','8','9'},
                                                   std::vector<unsigned char>(512,0xff),std::vector<unsigned char>(512,0)};
        const std::vector<unsigned> expected=seven?std::vector<unsigned>{0x94,0x86}:std::vector<unsigned>{0x31c3,0x7fa1,0};
        for(unsigned n=0;n<inputs.size();++n) {
            auto &input=inputs[n];
            for(unsigned i=0;i<input.size();++i)m.pokeMemory(0x8400+i,input[i]);
            unsigned address=seven?p2m_layout::sd_crc7_byte:p2m_layout::sd_crc16_byte;
            Wire wire;
            // Preserve outer BC because CRC7 deliberately clobbers B.
            run(m,{0xf3,0x31,0,0x95,0x21,0,0x84,0x11,0,0,
                0x01,(unsigned char)input.size(),(unsigned char)(input.size()>>8),
                0xc5,0x7e,0xcd,(unsigned char)address,(unsigned char)(address>>8),0xc1,
                0x23,0x0b,0x78,0xb1,0x20,0xf4,
                0xed,0x53,0x72,0x9e,0x3e,1,0x32,0x71,0x9e,0x76},wire);
            require(word(m,0x9e72)==expected[n],"CRC known vector mismatch");
        }
    }
}
int main(int argc,char **argv) {
    try {
        require(argc==4,"Usage: sd_crc-test EMULATOR BUILD CARD");
        std::string emu=argv[1],build=argv[2],card=argv[3];
        for(auto fault : {Fault::cid_data,Fault::cid_crc,Fault::enable,Fault::init_command,Fault::read_data,Fault::command}) {
            P2000Machine m;launch(m,emu,build,card);
            bool initFailure=fault==Fault::enable || fault==Fault::init_command;
            Wire wire(fault,initFailure?8:1);boot(m,wire,!initFailure);
            require(wire.remaining==0,"Boot fault not injected");
            if(initFailure) {
                require(m.peekMemory(p2m_layout::rom_workspace+0x12)==8,"CRC enable failure did not exhaust initialization");
                require(wire.reads==0,"Read data after CRC initialization failure");
            } else if(fault==Fault::cid_data || fault==Fault::cid_crc)
                require(screen(m).find("CID unavailable")!=std::string::npos,"Corrupt CID was displayed");
            else require(wire.enables==2,"Boot read recovery did not re-enable CRC");
        }
        P2000Machine m;launch(m,emu,build,card);Wire startup;boot(m,startup);
        require(startup.enables==1,"CRC not enabled at startup");
        vectors(m);
        // All subsequent CRC/recovery work must survive reuse of disposable RAM.
        for(unsigned i=0x7000;i<0x8000;++i)m.pokeMemory(i,0x76);
        for(unsigned i=0xa000;i<p2m_layout::tpa_limit;++i)m.pokeMemory(i,0x76);
        const unsigned lba=133120+2000;
        word(m,p2m_layout::rom_workspace,lba);word(m,p2m_layout::rom_workspace+2,lba>>16);
        word(m,p2m_layout::rom_workspace+4,0x8400);
        for(unsigned i=0;i<512;++i)m.pokeMemory(0x8400+i,i^0x5a);
        Wire good;require(call(m,0xe006,good)==0,"CRC-protected write failed");
        auto original=sector(card,lba);
        for(unsigned i=0;i<512;++i)require(original[i]==(unsigned char)(i^0x5a),"Written data mismatch");
        for(auto fault : {Fault::command,Fault::read_data,Fault::read_high,Fault::read_low}) {
            for(unsigned attempts : {1u,3u}) {
                Wire wire(fault,attempts);
                require(call(m,0xe003,wire)==(attempts==3?1u:0u),"Read CRC failure not propagated/recovered");
                require(wire.injected==attempts && wire.reads==(attempts==3?3u:2u),"Read retry count changed");
                require(wire.enables==(attempts==3?2u:1u),"CRC not re-enabled on read recovery");
                if(attempts==1)for(unsigned i=0;i<512;++i)require(m.peekMemory(0x8400+i)==original[i],"Recovered read mismatch");
                else require(m.peekMemory(p2m_layout::rom_workspace+0x16)==8,"CRC error diagnostic lost");
            }
        }
        for(auto fault : {Fault::write_data,Fault::write_high,Fault::write_low}) {
            for(unsigned i=0;i<512;++i)m.pokeMemory(0x8400+i,i^0xa5);
            Wire wire(fault,1);
            require(call(m,0xe006,wire)==1 && wire.injected==1 && wire.writes==1,"Rejected write was retried or accepted");
            require((m.peekMemory(p2m_layout::rom_workspace+0x16)&31)==11,"Write CRC rejection token lost");
            require(sector(card,lba)==original,"CRC-rejected write altered the card");
        }
        bios(m,9,good,0);bios(m,10,good,8000/128);bios(m,11,good,8000%128);bios(m,12,good,0x8400);
        Wire badRead(Fault::read_high,3);
        require(bios(m,13,badRead)==1 && m.peekMemory(0xdc90)==0,"Bad CRC published a cache entry");
        require(bios(m,13,good)==0,"Cache did not recover after CRC failure");
        for(unsigned i=0;i<128;++i)m.pokeMemory(0x8400+i,i^0xa5);
        require(bios(m,14,good)==0,"Cannot stage cache write");
        Wire badWrite(Fault::write_low,1);
        require(bios(m,17,badWrite)==1 && badWrite.writes==1,"Cache flush hid CRC rejection");
        require(m.peekMemory(0xdc91)==1 && m.peekMemory(0xdca4)==1,"CRC rejection lost dirty cache data");
        require(sector(card,lba)==original,"Rejected cache flush changed disk");
        Wire retry;
        require(bios(m,17,retry)==0 && retry.enables==1,"Explicit flush retry failed to re-enable CRC");
        require(m.peekMemory(0xdc91)==0 && m.peekMemory(0xdca4)==0,"Successful flush retained error state");
        auto saved=sector(card,lba);
        for(unsigned i=0;i<512;++i)require(saved[i]==(i<128?(unsigned char)(i^0xa5):original[i]),"Cache recovery damaged data/neighbours");
        std::cout<<"PASS: CRC vectors, CMD59, command/data/CRC wire faults, bounded read recovery, CID rejection, write rejection and dirty-cache retention; full TPA overwrite\n";
        return 0;
    } catch(const std::exception &e) {std::cerr<<e.what()<<'\n';return 1;}
}
