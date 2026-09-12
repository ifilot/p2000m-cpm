#pragma once

#include <array>
#include <cstdint>
#include <deque>
#include <fstream>
#include <string>

// PCB v6+: byte-wide SPI bridge and two independently banked 64 KiB SRAM banks.
// SERIAL only loads/reads a latch; CLKSTART performs the actual SPI transfer.
class P2000SdCartridge
{
public:
    void install();
    void remove();
    bool installed() const { return m_installed; }
    void reset();
    bool insert(const std::string &path, bool readOnly, std::string *error = nullptr);
    void eject();
    static bool createImage(const std::string &path, std::uint64_t bytes,
                            std::string *error = nullptr);
    bool hasCard() const { return m_image.is_open(); }
    bool readOnly() const { return m_readOnly; }
    const std::string &path() const { return m_path; }
    std::uint64_t sectorCount() const { return m_sectors; }
    std::uint8_t leds() const { return m_leds; }
    std::uint8_t readPort(std::uint8_t port);
    void writePort(std::uint8_t port, std::uint8_t value);

private:
    void clearTransfer();
    std::uint8_t transfer(std::uint8_t value);
    void command();
    void queueData(const std::uint8_t *data, std::size_t size);
    bool readSector(std::uint32_t sector, std::uint8_t *data);
    bool writeSector(std::uint32_t sector, const std::uint8_t *data);

    bool m_installed = false;
    std::array<std::uint8_t, 131072> m_ram{};
    std::uint16_t m_address = 0;
    std::uint8_t m_ramBank = 0, m_romBank = 0, m_leds = 0;
    std::fstream m_image;
    std::string m_path;
    std::uint64_t m_sectors = 0;
    bool m_readOnly = false, m_selected = false, m_idle = true;
    bool m_appCommand = false, m_crcEnabled = false;
    std::uint8_t m_tx = 0xff, m_rx = 0xff;
    std::array<std::uint8_t, 6> m_command{};
    std::size_t m_commandSize = 0;
    std::deque<std::uint8_t> m_response;
    bool m_writePending = false;
    int m_writeIndex = -1;
    std::uint32_t m_writeSector = 0;
    std::array<std::uint8_t, 514> m_writeBuffer{};
};
