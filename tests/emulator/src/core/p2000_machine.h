#pragma once

#include "p2000_fdc.h"
#include "p2000_sd.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

struct z80;

class P2000Machine
{
public:
    static constexpr int ScreenColumns = 80;
    static constexpr int ScreenRows = 24;
    static constexpr int VideoBytes = 0x800;

    P2000Machine();
    ~P2000Machine();

    P2000Machine(const P2000Machine &) = delete;
    P2000Machine &operator=(const P2000Machine &) = delete;

    bool loadMonitor(const std::string &path, std::string *error = nullptr);
    bool loadCartridge(const std::string &path, std::string *error = nullptr);
    bool loadBundledRoms(std::string *error = nullptr,
                         const std::string &baseDirectory = {});
    bool loadBundledPascal(std::string *error = nullptr,
                           const std::string &baseDirectory = {});
    bool loadBundledCpm(std::string *error = nullptr,
                        const std::string &baseDirectory = {});
    bool loadBundledMcpm(std::string *error = nullptr,
                         const std::string &baseDirectory = {});
    void ejectCartridge();
    bool insertDisk(int shugartDrive, const std::string &path,
                    std::string *error = nullptr);
    void ejectDisk(int shugartDrive);
    bool hasDisk(int shugartDrive) const;
    const std::string &diskPath(int shugartDrive) const;
    int currentTrack(int shugartDrive) const;

    // CP/M co-board: an add-on that replaces the motherboard's address
    // decoder PROM with an EEPROM (U2) plus a local 16 KiB SRAM (U1). It is
    // physically either present or absent, so it must be installed before an
    // OUT to port 0x20 has any effect; installing it clears its own RAM, as
    // powering up real SRAM leaves it in an indeterminate state.
    void installCoBoard();
    void removeCoBoard();
    bool hasCoBoard() const { return m_coBoardInstalled; }
    // True once the board is both installed and latched into CP/M mode by a
    // write to the mirrored port range 0x20-0x2f with bit 7 set (U4, a
    // 74LS74 clocked by U5's decode of that range). See
    // p2000m-cpm-coboard/cupl/p2000m-cpm-coboard.pld for the hardware this reproduces.
    bool coBoardMapped() const { return m_coBoardInstalled && m_coBoardMapped; }

    P2000SdCartridge &sdCartridge() { return m_sd; }
    const P2000SdCartridge &sdCartridge() const { return m_sd; }

    void reset();
    void runFrame();
    void requestNmi();
    // For tests/tooling: executes exactly one CPU instruction (still
    // delivering any pending interrupt first, same as runFrame()'s inner
    // loop) and returns the resulting program counter.
    unsigned stepInstruction();

    void setKey(int row, int bit, bool pressed);
    void releaseAllKeys();

    const std::uint8_t *characters() const { return m_video.data(); }
    const std::uint8_t *attributes() const { return m_video.data() + 0x800; }
    std::uint64_t frameNumber() const { return m_frameNumber; }
    bool isReady() const { return m_monitorLoaded && m_cartridgeLoaded; }
    bool hasMonitor() const { return m_monitorLoaded; }
    bool hasCartridge() const { return m_cartridgeLoaded; }
    const std::string &cartridgePath() const { return m_cartridgePath; }
    unsigned programCounter() const;

    std::uint8_t readPort(std::uint8_t port);
    void writePort(std::uint8_t port, std::uint8_t value);

    // Direct memory access for tests and tooling. These exercise exactly the
    // same address decode the CPU uses (including the co-board remap when
    // mapped), so they can verify decoder behavior without depending on CPU
    // timing.
    std::uint8_t peekMemory(std::uint16_t address) const { return readMemory(address); }
    void pokeMemory(std::uint16_t address, std::uint8_t value) { writeMemory(address, value); }

private:
    bool loadImage(const std::string &path, std::uint8_t *destination,
                   std::size_t expectedSize, const char *description,
                   std::string *error);
    void configureMemory();
    std::uint8_t readMemory(std::uint16_t address) const;
    void writeMemory(std::uint16_t address, std::uint8_t value);
    std::uint8_t readCoBoardMemory(std::uint16_t address) const;
    void writeCoBoardMemory(std::uint16_t address, std::uint8_t value);
    static std::uint8_t cpuRead(void *context, std::uint16_t address);
    static void cpuWrite(void *context, std::uint16_t address,
                         std::uint8_t value);
    static std::uint8_t cpuPortIn(z80 *cpu, std::uint8_t port);
    static void cpuPortOut(z80 *cpu, std::uint8_t port, std::uint8_t value);
    static std::string bundledPath(const char *fileName);
    static std::string bundledSoftwarePath(const char *relativePath);
    void writeCtc(int channel, std::uint8_t value);
    void triggerCtc(int channel);
    void deliverPendingInterrupt();

    std::array<std::uint8_t, 0x5000> m_rom{};
    std::array<std::uint8_t, 0x1000> m_video{};
    std::array<std::uint8_t, 0x8000> m_ram{};
    std::array<std::array<std::uint8_t, 0x2000>, 2> m_extensionRam{};
    // CP/M co-board local RAM (U1, CY62256 wired as 16 KiB), mapped at CPU
    // 0xa000-0xdfff while the board is installed and mapped. It is neither
    // readable nor writable through the stock decode.
    std::array<std::uint8_t, 0x4000> m_coBoardRam{};
    // The Nater CP/M firmware uses the MultiWare multifunction-card RAM disk
    // through an indirect 18-bit address: ports 95, 96 and 97 select a 64 KiB
    // bank, select a 256-byte page, and transfer auto-incrementing bytes.
    std::array<std::uint8_t, 0x40000> m_cpmRamDisk{};
    std::uint8_t m_cpmRamDiskBank = 0;
    std::uint8_t m_cpmRamDiskPage = 0;
    std::uint8_t m_cpmRamDiskOffset = 0;
    std::array<std::uint8_t, 10> m_keys{};
    std::unique_ptr<z80> m_cpu;
    P2000Fdc m_fdc;
    P2000SdCartridge m_sd;
    struct CtcChannel {
        std::uint8_t control = 0;
        bool enabled = false;
        bool waitingForConstant = false;
    };
    std::array<CtcChannel, 4> m_ctc{};
    std::uint8_t m_ctcVector = 0x20;
    std::uint8_t m_pendingCtcInterrupts = 0;
    std::uint8_t m_ramBank = 0;
    bool m_coBoardInstalled = false;
    bool m_coBoardMapped = false;
    std::uint8_t m_outputLatch = 0;
    std::uint8_t m_soundLatch = 0;
    std::uint8_t m_disasLatch = 0;
    std::uint64_t m_frameNumber = 0;
    bool m_nmiRequested = false;
    bool m_monitorLoaded = false;
    bool m_cartridgeLoaded = false;
    std::string m_cartridgePath;
};
