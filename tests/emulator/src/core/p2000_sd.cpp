#include "p2000_sd.h"

#include <filesystem>
#include <utility>

namespace {
bool fail(std::string *error, const std::string &message)
{
    if (error) *error = message;
    return false;
}
std::uint16_t crc16(const std::uint8_t *data, std::size_t size)
{
    std::uint16_t crc = 0;
    for (std::size_t i = 0; i < size; ++i) {
        crc ^= static_cast<std::uint16_t>(data[i]) << 8;
        for (int bit = 0; bit < 8; ++bit)
            crc = (crc & 0x8000) ? (crc << 1) ^ 0x1021 : crc << 1;
    }
    return crc;
}
std::uint8_t crc7(const std::uint8_t *data, std::size_t size)
{
    std::uint8_t crc = 0;
    for (std::size_t i = 0; i < size; ++i) {
        auto value = data[i];
        for (int bit = 0; bit < 8; ++bit) {
            crc <<= 1;
            if ((value ^ crc) & 0x80) crc ^= 9;
            value <<= 1;
        }
    }
    return (crc << 1) | 1;
}
}

void P2000SdCartridge::install()
{
    if (m_installed) return;
    m_installed = true;
    m_ram.fill(0);
    reset();
}

void P2000SdCartridge::remove()
{
    eject();
    m_installed = false;
    reset();
}

void P2000SdCartridge::clearTransfer()
{
    m_commandSize = 0;
    m_response.clear();
    m_writePending = false;
    m_writeIndex = -1;
    m_rx = 0xff;
}

void P2000SdCartridge::reset()
{
    clearTransfer();
    m_address = 0;
    m_ramBank = m_romBank = m_leds = 0;
    m_selected = m_appCommand = m_crcEnabled = false;
    m_idle = true;
    m_tx = 0xff;
}

bool P2000SdCartridge::insert(const std::string &path, bool readOnly,
                              std::string *error)
{
    if (!m_installed) return fail(error, "Install the SD cartridge in slot 2 first.");
    std::error_code ec;
    if (!std::filesystem::is_regular_file(path, ec))
        return fail(error, "SD image must be a regular file: " + path);
    const auto bytes = std::filesystem::file_size(path, ec);
    // CSD v2 expresses capacity in 512 KiB units; cap at SDHC's 32 GiB.
    if (ec || bytes < 524288 || bytes % 524288 || bytes > (32ull << 30))
        return fail(error, "SD image must be 512 KiB to 32 GiB, in multiples of 512 KiB.");
    std::fstream image(path, std::ios::binary | std::ios::in |
                            (readOnly ? std::ios::openmode{} : std::ios::out));
    if (!image) return fail(error, "Could not open SD image in the requested mode: " + path);
    m_image = std::move(image);
    m_path = path;
    m_sectors = bytes / 512;
    m_readOnly = readOnly;
    reset();
    return true;
}

void P2000SdCartridge::eject()
{
    if (m_image.is_open()) m_image.close();
    m_image.clear();
    m_path.clear();
    m_sectors = 0;
    m_readOnly = false;
    reset();
}

bool P2000SdCartridge::createImage(const std::string &path, std::uint64_t bytes,
                                  std::string *error)
{
    if (bytes < 524288 || bytes % 524288 || bytes > (32ull << 30))
        return fail(error, "Invalid SD image size.");
    std::error_code ec;
    if (std::filesystem::exists(path, ec) || ec)
        return fail(error, "Choose a new filename; an existing image will not be overwritten.");
    std::ofstream stream(path, std::ios::binary);
    if (!stream) return fail(error, "Could not create SD image: " + path);
    stream.seekp(static_cast<std::streamoff>(bytes - 1));
    stream.put(0);
    stream.flush();
    if (!stream) return fail(error, "Could not size SD image: " + path);
    return true;
}

bool P2000SdCartridge::readSector(std::uint32_t sector, std::uint8_t *data)
{
    if (sector >= m_sectors) return false;
    m_image.clear();
    m_image.seekg(static_cast<std::streamoff>(sector) * 512);
    m_image.read(reinterpret_cast<char *>(data), 512);
    return static_cast<bool>(m_image);
}

bool P2000SdCartridge::writeSector(std::uint32_t sector, const std::uint8_t *data)
{
    if (m_readOnly || sector >= m_sectors) return false;
    m_image.clear();
    m_image.seekp(static_cast<std::streamoff>(sector) * 512);
    m_image.write(reinterpret_cast<const char *>(data), 512);
    m_image.flush(); // Complete persistence before returning the accepted token.
    return static_cast<bool>(m_image);
}

void P2000SdCartridge::queueData(const std::uint8_t *data, std::size_t size)
{
    m_response.push_back(0xff);
    m_response.push_back(0xfe);
    m_response.insert(m_response.end(), data, data + size);
    const auto crc = crc16(data, size);
    m_response.push_back(static_cast<std::uint8_t>(crc >> 8));
    m_response.push_back(static_cast<std::uint8_t>(crc & 0xff));
}

void P2000SdCartridge::command()
{
    const auto cmd = m_command[0] & 0x3f;
    const std::uint32_t arg = (std::uint32_t(m_command[1]) << 24) |
        (std::uint32_t(m_command[2]) << 16) |
        (std::uint32_t(m_command[3]) << 8) | m_command[4];
    const std::uint8_t r1 = m_idle ? 1 : 0;
    const bool app = m_appCommand;
    m_appCommand = false;
    m_response.push_back(0xff); // Ncr: one dummy byte before R1.
    if ((m_crcEnabled || cmd == 0 || cmd == 8) &&
        crc7(m_command.data(), 5) != m_command[5]) {
        m_response.push_back(r1 | 8);
        return;
    }
    switch (cmd) {
    case 0:
        m_idle = true;
        m_crcEnabled = false;
        m_response.push_back(1);
        break;
    case 8:
        m_response.insert(m_response.end(), {r1, 0, 0, m_command[3], m_command[4]});
        break;
    case 55:
        m_appCommand = true;
        m_response.push_back(r1);
        break;
    case 41:
        if (!app) { m_response.push_back(r1 | 4); break; }
        if (arg & 0x40000000) m_idle = false;
        m_response.push_back(m_idle ? 1 : 0);
        break;
    case 58:
        m_response.insert(m_response.end(),
            {r1, static_cast<std::uint8_t>(m_idle ? 0 : 0xc0), 0xff, 0x80, 0});
        break;
    case 59:
        m_crcEnabled = (arg & 1) != 0;
        m_response.push_back(r1);
        break;
    default:
        if (m_idle) { m_response.push_back(1); break; }
        switch (cmd) {
        case 16: m_response.push_back(arg == 512 ? 0 : 0x40); break;
        case 13: m_response.insert(m_response.end(), {0, 0}); break;
        case 9: {
            std::array<std::uint8_t, 16> csd{0x40, 0x0e, 0, 0x32, 0x5b, 0x59};
            const auto size = m_sectors / 1024 - 1;
            csd[7] = (size >> 16) & 0x3f;
            csd[8] = (size >> 8) & 0xff;
            csd[9] = size & 0xff;
            csd[10] = 0x7f; csd[11] = 0x80; csd[12] = 0x0a; csd[13] = 0x40;
            csd[14] = m_readOnly ? 0x10 : 0;
            csd[15] = crc7(csd.data(), 15);
            m_response.push_back(0);
            queueData(csd.data(), csd.size());
            break;
        }
        case 10: {
            std::array<std::uint8_t, 16> cid{0x01, 'P', 'M', 'S', 'D', 'H', 'C', ' ',
                                           0x10, 0, 0, 0, 1, 0x01, 0x91};
            cid[15] = crc7(cid.data(), 15);
            m_response.push_back(0);
            queueData(cid.data(), cid.size());
            break;
        }
        case 17: {
            std::array<std::uint8_t, 512> block{};
            if (arg >= m_sectors) m_response.push_back(0x20);
            else {
                m_response.push_back(0);
                if (readSector(arg, block.data())) queueData(block.data(), block.size());
                else m_response.push_back(0x01); // Data error token.
            }
            break;
        }
        case 24:
            if (arg >= m_sectors) m_response.push_back(0x20);
            else {
                m_response.push_back(0);
                m_writePending = true;
                m_writeIndex = -1;
                m_writeSector = arg;
            }
            break;
        default: m_response.push_back(4); break; // Illegal command.
        }
    }
}

std::uint8_t P2000SdCartridge::transfer(std::uint8_t value)
{
    if (!m_selected || !hasCard()) return 0xff;
    if (!m_response.empty()) {
        const auto result = m_response.front();
        m_response.pop_front();
        return result;
    }
    if (m_writePending) {
        if (m_writeIndex < 0) {
            if (value == 0xfe) m_writeIndex = 0;
        } else {
            m_writeBuffer[m_writeIndex++] = value;
            if (m_writeIndex == 514) {
                const auto crc = crc16(m_writeBuffer.data(), 512);
                const bool valid = !m_crcEnabled ||
                    (m_writeBuffer[512] == (crc >> 8) && m_writeBuffer[513] == (crc & 0xff));
                const std::uint8_t token = !valid ? 0x0b :
                    writeSector(m_writeSector, m_writeBuffer.data()) ? 0x05 : 0x0d;
                m_response.push_back(token);
                m_response.push_back(0); // One byte busy, followed by idle 0xff.
                m_writePending = false;
            }
        }
        return 0xff;
    }
    if (m_commandSize == 0 && (value & 0xc0) != 0x40) return 0xff;
    m_command[m_commandSize++] = value;
    if (m_commandSize == m_command.size()) {
        m_commandSize = 0;
        command();
    }
    return 0xff;
}

std::uint8_t P2000SdCartridge::readPort(std::uint8_t port)
{
    if (!m_installed) return 0xff;
    switch (port) {
    case 0x40: return m_rx;
    case 0x48: return static_cast<std::uint8_t>(m_address & 0xff);
    case 0x49: return static_cast<std::uint8_t>(m_address >> 8);
    case 0x4a: return m_romBank;
    case 0x4b: return m_ramBank;
    case 0x4c: return 0xff; // Unpopulated/erased flash; programming not emulated.
    case 0x4d: return m_ram[std::size_t(m_ramBank) * 65536 + m_address];
    default: return 0xff;
    }
}

void P2000SdCartridge::writePort(std::uint8_t port, std::uint8_t value)
{
    if (!m_installed) return;
    switch (port) {
    case 0x40: m_tx = value; break;
    case 0x41: m_rx = transfer(m_tx); break;
    case 0x42: m_selected = false; clearTransfer(); break;
    case 0x43:
        if (!m_selected) clearTransfer();
        m_selected = true;
        break;
    case 0x44: m_leds = value & 3; break;
    case 0x48: m_address = (m_address & 0xff00) | value; break;
    case 0x49: m_address = (m_address & 0xff) | (std::uint16_t(value) << 8); break;
    case 0x4a: m_romBank = value & 1; break;
    case 0x4b: m_ramBank = value & 1; break;
    case 0x4d: m_ram[std::size_t(m_ramBank) * 65536 + m_address] = value; break;
    default: break;
    }
}
