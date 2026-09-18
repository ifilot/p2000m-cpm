#include "p2000_machine.h"

extern "C" {
#include "z80.h"
}

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <sstream>
#include <vector>

P2000Machine::P2000Machine()
    : m_cpu(std::make_unique<z80>()),
      m_fdc([this](bool notReady) { triggerCtc(notReady ? 1 : 0); })
{
    m_rom.fill(0xff);
    m_keys.fill(0xff);
    configureMemory();
    reset();
}

P2000Machine::~P2000Machine() = default;

void P2000Machine::configureMemory()
{
    z80_init(m_cpu.get());
    m_cpu->read_byte = &P2000Machine::cpuRead;
    m_cpu->write_byte = &P2000Machine::cpuWrite;
    m_cpu->port_in = &P2000Machine::cpuPortIn;
    m_cpu->port_out = &P2000Machine::cpuPortOut;
    m_cpu->userdata = this;
}

bool P2000Machine::loadImage(const std::string &path, std::uint8_t *destination,
                             std::size_t expectedSize, const char *description,
                             std::string *error)
{
    std::ifstream stream(path, std::ios::binary);
    if (!stream) {
        if (error)
            *error = std::string("Could not open ") + description + ": " + path;
        return false;
    }

    const std::vector<char> bytes((std::istreambuf_iterator<char>(stream)),
                                  std::istreambuf_iterator<char>());
    if (bytes.size() != expectedSize) {
        if (error) {
            std::ostringstream text;
            text << description << " must be exactly " << expectedSize
                 << " bytes (got " << bytes.size() << ").";
            *error = text.str();
        }
        return false;
    }
    std::copy(bytes.begin(), bytes.end(), destination);
    return true;
}

bool P2000Machine::loadMonitor(const std::string &path, std::string *error)
{
    if (!loadImage(path, m_rom.data(), 0x1000, "monitor ROM", error))
        return false;

    m_monitorLoaded = true;
    reset();
    return true;
}

bool P2000Machine::loadCartridge(const std::string &path, std::string *error)
{
    std::ifstream stream(path, std::ios::binary);
    if (!stream) {
        if (error)
            *error = "Could not open cartridge image: " + path;
        return false;
    }
    const std::vector<char> bytes((std::istreambuf_iterator<char>(stream)),
                                  std::istreambuf_iterator<char>());
    if (bytes.size() != 0x4000) {
        if (error) {
            std::ostringstream text;
            text << "Cartridge image must be exactly 16384 bytes (got "
                 << bytes.size() << ").";
            *error = text.str();
        }
        return false;
    }
    std::fill(m_rom.begin() + 0x1000, m_rom.end(), 0xff);
    std::copy(bytes.begin(), bytes.end(), m_rom.begin() + 0x1000);
    m_cartridgeLoaded = true;
    m_cartridgePath = path;
    reset();
    return true;
}

std::string P2000Machine::bundledPath(const char *fileName)
{
    const auto local = std::filesystem::current_path() / "assets" / "roms" /
                       fileName;
    if (std::filesystem::exists(local))
        return local.string();
    return (std::filesystem::path(P2000M_SOURCE_ROM_DIR) / fileName).string();
}

std::string P2000Machine::bundledSoftwarePath(const char *relativePath)
{
    const auto local = std::filesystem::current_path() / "assets" / "software" /
                       relativePath;
    if (std::filesystem::exists(local))
        return local.string();
    return (std::filesystem::path(P2000M_SOURCE_SOFTWARE_DIR) /
            relativePath).string();
}

bool P2000Machine::loadBundledRoms(std::string *error,
                                   const std::string &baseDirectory)
{
    const auto pathFor = [&baseDirectory](const char *fileName) {
        if (!baseDirectory.empty())
            return (std::filesystem::path(baseDirectory) / "assets" / "roms" /
                    fileName).string();
        return bundledPath(fileName);
    };
    if (!loadMonitor(pathFor("p2000.rom"), error))
        return false;
    const auto cartridgePath = !baseDirectory.empty()
        ? (std::filesystem::path(baseDirectory) / "assets" / "software" /
           "cartridges" / "basic.bin").string()
        : bundledSoftwarePath("cartridges/basic.bin");
    return loadCartridge(cartridgePath, error);
}

bool P2000Machine::loadBundledPascal(std::string *error,
                                     const std::string &baseDirectory)
{
    const auto pathFor = [&baseDirectory](const char *fileName) {
        if (!baseDirectory.empty())
            return (std::filesystem::path(baseDirectory) / "assets" / "software" /
                    fileName).string();
        return bundledSoftwarePath(fileName);
    };
    if (!loadCartridge(pathFor("cartridges/ucsd_pascal.bin"), error))
        return false;
    if (!insertDisk(1, pathFor("disks/ucsd_pascal_system.bin"), error))
        return false;
    reset();
    return true;
}

bool P2000Machine::loadBundledCpm(std::string *error,
                                  const std::string &baseDirectory)
{
    const auto pathFor = [&baseDirectory](const char *fileName) {
        if (!baseDirectory.empty())
            return (std::filesystem::path(baseDirectory) / "assets" / "software" /
                    fileName).string();
        return bundledSoftwarePath(fileName);
    };
    installCoBoard();
    if (!loadCartridge(pathFor("cartridges/cpm_nater.bin"), error))
        return false;
    // The bundled image combines the recovered Seeters system tracks with a
    // complete CP/M filesystem containing the standard command-line tools.
    if (!insertDisk(1, pathFor("disks/cpm_seeters_system.bin"), error))
        return false;
    reset();
    return true;
}

bool P2000Machine::loadBundledMcpm(std::string *error,
                                   const std::string &baseDirectory)
{
    const auto pathFor = [&baseDirectory](const char *fileName) {
        if (!baseDirectory.empty())
            return (std::filesystem::path(baseDirectory) / "assets" / "software" /
                    fileName).string();
        return bundledSoftwarePath(fileName);
    };
    installCoBoard();
    if (!loadCartridge(pathFor("cartridges/mcpm.bin"), error))
        return false;
    if (!insertDisk(1, pathFor("disks/mcpm_system.bin"), error))
        return false;
    reset();
    return true;
}

void P2000Machine::ejectCartridge()
{
    std::fill(m_rom.begin() + 0x1000, m_rom.end(), 0xff);
    m_cartridgeLoaded = false;
    m_cartridgePath.clear();
    reset();
}

bool P2000Machine::insertDisk(int shugartDrive, const std::string &path,
                              std::string *error)
{
    return m_fdc.insertDisk(shugartDrive, path, error);
}

void P2000Machine::ejectDisk(int shugartDrive)
{
    m_fdc.ejectDisk(shugartDrive);
}

bool P2000Machine::hasDisk(int shugartDrive) const
{
    return m_fdc.hasDisk(shugartDrive);
}

const std::string &P2000Machine::diskPath(int shugartDrive) const
{
    return m_fdc.diskPath(shugartDrive);
}

int P2000Machine::currentTrack(int shugartDrive) const
{
    return m_fdc.currentTrack(shugartDrive);
}

void P2000Machine::installCoBoard()
{
    m_coBoardInstalled = true;
    m_coBoardMapped = false;
    m_coBoardBankEnabled = false;
    m_coBoardBank = 0;
    // Real SRAM powers up with indeterminate contents; zero it so a fresh
    // install is at least deterministic.
    m_coBoardRam.fill(0);
    m_cpmRamDisk.fill(0);
}

void P2000Machine::removeCoBoard()
{
    // Pulling the board drops /RAMS3 back to R3's pull-up and tri-states U2,
    // so the CPU immediately sees the stock decode again.
    m_coBoardInstalled = false;
    m_coBoardMapped = false;
    m_coBoardBankEnabled = false;
    m_coBoardBank = 0;
}

void P2000Machine::reset()
{
    m_outputLatch = 0;
    m_soundLatch = 0;
    m_disasLatch = 0;
    m_nmiRequested = false;
    m_frameNumber = 0;
    m_ramBank = 0;
    m_cpmRamDiskBank = 0;
    m_cpmRamDiskPage = 0;
    m_cpmRamDiskOffset = 0;
    // Reset clears all CPLD control latches, returning to the stock map
    // even when the board stays installed. SRAM contents survive reset.
    m_coBoardMapped = false;
    m_coBoardBankEnabled = false;
    m_coBoardBank = 0;
    m_ctcVector = 0x20;
    m_pendingCtcInterrupts = 0;
    m_ctc.fill({});
    m_fdc.reset();
    m_sd.reset();
    releaseAllKeys();
    configureMemory();
}

void P2000Machine::runFrame()
{
    if (!m_monitorLoaded)
        return;

    if (m_nmiRequested) {
        z80_gen_nmi(m_cpu.get());
        m_nmiRequested = false;
    }
    triggerCtc(3);

    const unsigned long targetCycles = m_cpu->cyc + 2'500'000 / 50;
    while (m_cpu->cyc < targetCycles) {
        deliverPendingInterrupt();
        const unsigned long before = m_cpu->cyc;
        z80_step(m_cpu.get());
        m_fdc.tick(m_cpu->cyc - before);
    }
    ++m_frameNumber;
}

unsigned P2000Machine::stepInstruction()
{
    deliverPendingInterrupt();
    const unsigned long before = m_cpu->cyc;
    z80_step(m_cpu.get());
    m_fdc.tick(m_cpu->cyc - before);
    return programCounter();
}

void P2000Machine::requestNmi()
{
    m_nmiRequested = true;
}

void P2000Machine::setKey(int row, int bit, bool pressed)
{
    if (row < 0 || row >= static_cast<int>(m_keys.size()) || bit < 0 || bit > 7)
        return;
    if (pressed)
        m_keys[row] &= static_cast<std::uint8_t>(~(1u << bit));
    else
        m_keys[row] |= static_cast<std::uint8_t>(1u << bit);
}

void P2000Machine::releaseAllKeys()
{
    m_keys.fill(0xff);
}

std::uint8_t P2000Machine::readPort(std::uint8_t port)
{
    if ((port >> 4) == 4) return m_sd.readPort(port);
    if (port == 0x97 && m_coBoardInstalled) {
        const auto address =
            (static_cast<std::size_t>(m_cpmRamDiskBank & 0xc0) << 10) |
            (static_cast<std::size_t>(m_cpmRamDiskPage) << 8) |
            m_cpmRamDiskOffset;
        const auto value = m_cpmRamDisk[address];
        ++m_cpmRamDiskOffset;
        return value;
    }
    if (port == 0x8c)
        return m_fdc.readMainStatus();
    if (port == 0x8d)
        return m_fdc.readData();
    if (port == 0x90)
        return m_fdc.readControl();

    switch (port >> 4) {
    case 0x0:
        if (m_outputLatch & 0x40) {
            std::uint8_t result = 0xff;
            for (const auto row : m_keys)
                result &= row;
            return result;
        }
        return (port & 0x0f) < m_keys.size() ? m_keys[port & 0x0f] : 0xff;
    case 0x1:
        return m_outputLatch;
    case 0x2:
        return 0xf7; // No cassette present; write-enable input is active low.
    case 0x5:
        return m_soundLatch;
    case 0x7:
        return m_disasLatch;
    default:
        return 0xff;
    }
}

void P2000Machine::writePort(std::uint16_t address, std::uint8_t value)
{
    const auto port = static_cast<std::uint8_t>(address);
    if ((port >> 4) == 4) { m_sd.writePort(port, value); return; }
    if (m_coBoardInstalled && port == 0x95) {
        m_cpmRamDiskBank = value;
        return;
    }
    if (m_coBoardInstalled && port == 0x96) {
        m_cpmRamDiskPage = value;
        m_cpmRamDiskOffset = 0;
        return;
    }
    if (m_coBoardInstalled && port == 0x97) {
        const auto address =
            (static_cast<std::size_t>(m_cpmRamDiskBank & 0xc0) << 10) |
            (static_cast<std::size_t>(m_cpmRamDiskPage) << 8) |
            m_cpmRamDiskOffset;
        m_cpmRamDisk[address] = value;
        ++m_cpmRamDiskOffset;
        return;
    }
    if (port >= 0x88 && port <= 0x8b) {
        writeCtc(port - 0x88, value);
        return;
    }
    if (port == 0x8d) {
        m_fdc.writeData(value);
        return;
    }
    if (port == 0x90) {
        m_fdc.writeControl(value);
        return;
    }
    if (port == 0x94) {
        m_ramBank = value & 0x01;
        return;
    }

    switch (port >> 4) {
    case 0x1:
        m_outputLatch = value;
        break;
    case 0x2:
        // The CPLD atomically captures D7 (mode), D0 (overlay enable),
        // and A11-A13 (bank). Immediate OUT drives A onto A8-A15; OUT (C)
        // drives B there. Other devices continue decoding only A0-A7.
        if (m_coBoardInstalled) {
            m_coBoardMapped = (value & 0x80) != 0;
            m_coBoardBankEnabled = (value & 1) != 0;
            m_coBoardBank = (address >> 11) & 7;
        }
        break;
    case 0x5:
        m_soundLatch = value;
        break;
    case 0x7:
        m_disasLatch = value;
        break;
    default:
        break;
    }
}

void P2000Machine::writeCtc(int channel, std::uint8_t value)
{
    if (channel < 0 || channel >= static_cast<int>(m_ctc.size()))
        return;
    auto &ctc = m_ctc[static_cast<std::size_t>(channel)];
    if (ctc.waitingForConstant) {
        ctc.waitingForConstant = false;
        ctc.enabled = (ctc.control & 0x80) != 0;
        // Timer mode starts from the internal clock. It is used by the monitor
        // to detect that the extension-board CTC is present.
        if (ctc.enabled && (ctc.control & 0x40) == 0)
            triggerCtc(channel);
        return;
    }
    if ((value & 0x01) == 0) {
        if (channel == 0)
            m_ctcVector = value & 0xf8;
        return;
    }
    ctc.control = value;
    if ((value & 0x02) != 0 || (value & 0x80) == 0)
        ctc.enabled = false;
    ctc.waitingForConstant = (value & 0x04) != 0;
    if (!ctc.waitingForConstant)
        ctc.enabled = (value & 0x80) != 0;
}

void P2000Machine::triggerCtc(int channel)
{
    if (channel < 0 || channel >= static_cast<int>(m_ctc.size()) ||
        !m_ctc[static_cast<std::size_t>(channel)].enabled)
        return;
    m_pendingCtcInterrupts |= static_cast<std::uint8_t>(1u << channel);
}

void P2000Machine::deliverPendingInterrupt()
{
    // Keep the request at the CTC while maskable interrupts are disabled.
    // In a real daisy chain the CTC puts its *current* vector on the bus when
    // the CPU acknowledges INT.  Latching it into the CPU earlier leaves a
    // stale vector behind if firmware reprograms the CTC before executing EI
    // (the Philips MCPM bootstrap does exactly that).
    if (!m_cpu->iff1 || m_cpu->int_pending || m_pendingCtcInterrupts == 0)
        return;
    for (int channel = 0; channel < 4; ++channel) {
        const auto mask = static_cast<std::uint8_t>(1u << channel);
        if ((m_pendingCtcInterrupts & mask) == 0)
            continue;
        m_pendingCtcInterrupts &= static_cast<std::uint8_t>(~mask);
        z80_gen_int(m_cpu.get(),
                    static_cast<std::uint8_t>(m_ctcVector + channel * 2));
        return;
    }
}

// Revised CP/M decode from p2000m-cpm-coboard/cupl/p2000m-cpm-coboard.pld.
// Motherboard RAM keeps CPU A0-A13: stock 6000-7fff becomes CP/M 2000-3fff,
// and stock 8000-9fff becomes CP/M 0000-1fff. This is a property of the
// hardware, independent of the cartridge. Expansion addresses translate by
// six 4 KiB pages, exposing stock a000-ffff at CP/M 4000-9fff.
std::uint8_t P2000Machine::readCoBoardMemory(std::uint16_t address) const
{
    if (address < 0x4000)
        return m_ram[address ^ 0x2000];
    if (address < 0x8000 && m_coBoardBankEnabled && m_coBoardBank != 0)
        return m_coBoardRam[m_coBoardBank * 0x4000 + address - 0x4000];
    if (address < 0x8000)
        return m_ram[address]; // expansion RAM; same as stock a000-dfff
    if (address < 0xa000)
        return m_extensionRam[m_ramBank][address - 0x8000]; // stock e000-ffff
    if (address < 0xe000)
        return m_coBoardRam[address - 0xa000]; // U1, local 16 KiB SRAM
    if (address < 0xf000)
        return m_rom[address - 0xc000]; // cartridge slice, same bytes as stock 2000-2fff
    return m_video[address - 0xf000]; // same video RAM as stock 5000-5fff
}

void P2000Machine::writeCoBoardMemory(std::uint16_t address, std::uint8_t value)
{
    if (address < 0x4000)
        m_ram[address ^ 0x2000] = value;
    else if (address < 0x8000 && m_coBoardBankEnabled && m_coBoardBank != 0)
        m_coBoardRam[m_coBoardBank * 0x4000 + address - 0x4000] = value;
    else if (address < 0x8000)
        m_ram[address] = value;
    else if (address < 0xa000)
        m_extensionRam[m_ramBank][address - 0x8000] = value;
    else if (address < 0xe000)
        m_coBoardRam[address - 0xa000] = value;
    else if (address >= 0xf000)
        m_video[address - 0xf000] = value;
    // 0xe000-0xefff is the CP/M cartridge boot-ROM slice (CARS1); it is
    // read-only, matching how the stock decode ignores writes below 0x5000.
}

std::uint8_t P2000Machine::readMemory(std::uint16_t address) const
{
    if (m_coBoardInstalled && m_coBoardMapped)
        return readCoBoardMemory(address);
    if (address < 0x5000)
        return m_rom[address];
    if (address < 0x6000)
        return m_video[address - 0x5000];
    if (address < 0xe000)
        return m_ram[address - 0x6000];
    return m_extensionRam[m_ramBank][address - 0xe000];
}

void P2000Machine::writeMemory(std::uint16_t address, std::uint8_t value)
{
    if (m_coBoardInstalled && m_coBoardMapped) {
        writeCoBoardMemory(address, value);
        return;
    }
    if (address >= 0x5000 && address < 0x6000)
        m_video[address - 0x5000] = value;
    else if (address >= 0x6000 && address < 0xe000)
        m_ram[address - 0x6000] = value;
    else if (address >= 0xe000)
        m_extensionRam[m_ramBank][address - 0xe000] = value;
}

std::uint8_t P2000Machine::cpuRead(void *context, std::uint16_t address)
{
    return static_cast<P2000Machine *>(context)->readMemory(address);
}

void P2000Machine::cpuWrite(void *context, std::uint16_t address,
                            std::uint8_t value)
{
    static_cast<P2000Machine *>(context)->writeMemory(address, value);
}

std::uint8_t P2000Machine::cpuPortIn(z80 *cpu, std::uint8_t port)
{
    return static_cast<P2000Machine *>(cpu->userdata)->readPort(port);
}

void P2000Machine::cpuPortOut(z80 *cpu, std::uint16_t port,
                              std::uint8_t value)
{
    static_cast<P2000Machine *>(cpu->userdata)->writePort(port, value);
}

unsigned P2000Machine::programCounter() const
{
    return m_cpu->pc;
}
