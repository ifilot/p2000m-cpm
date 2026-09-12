#include "p2000_fdc.h"

#include <algorithm>
#include <fstream>
#include <iterator>
#include <sstream>

namespace {
constexpr std::uint8_t CommandMask = 0x1f;
constexpr std::uint8_t ReadTrack = 0x02;
constexpr std::uint8_t Specify = 0x03;
constexpr std::uint8_t SenseDriveStatus = 0x04;
constexpr std::uint8_t WriteData = 0x05;
constexpr std::uint8_t ReadData = 0x06;
constexpr std::uint8_t Recalibrate = 0x07;
constexpr std::uint8_t SenseInterrupt = 0x08;
constexpr std::uint8_t ReadId = 0x0a;
constexpr std::uint8_t FormatTrack = 0x0d;
constexpr std::uint8_t Seek = 0x0f;
}

P2000Fdc::P2000Fdc(InterruptCallback interruptCallback)
    : m_interruptCallback(std::move(interruptCallback))
{
}

bool P2000Fdc::insertDisk(int shugartDrive, const std::string &path,
                          std::string *error)
{
    if (shugartDrive < 1 || shugartDrive > 2) {
        if (error)
            *error = "Shugart drive must be 1 or 2.";
        return false;
    }

    std::ifstream stream(path, std::ios::binary);
    if (!stream) {
        if (error)
            *error = "Could not open floppy image: " + path;
        return false;
    }
    std::vector<std::uint8_t> bytes{
        std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
    if (bytes.empty() || bytes.size() > DiskCapacity ||
        bytes.size() % SectorSize != 0) {
        if (error) {
            std::ostringstream text;
            text << "P2000 floppy image must contain a non-empty, sector-aligned "
                    "flat image of at most "
                 << DiskCapacity << " bytes (got " << bytes.size() << ").";
            *error = text.str();
        }
        return false;
    }
    bytes.resize(DiskCapacity, 0x00);
    auto &drive = m_drives[static_cast<std::size_t>(shugartDrive - 1)];
    drive.bytes = std::move(bytes);
    drive.path = path;
    drive.cylinder = 0;
    return true;
}

void P2000Fdc::ejectDisk(int shugartDrive)
{
    if (shugartDrive < 1 || shugartDrive > 2)
        return;
    auto &drive = m_drives[static_cast<std::size_t>(shugartDrive - 1)];
    drive.bytes.clear();
    drive.path.clear();
    drive.cylinder = 0;
}

bool P2000Fdc::hasDisk(int shugartDrive) const
{
    return shugartDrive >= 1 && shugartDrive <= 2 &&
           !m_drives[static_cast<std::size_t>(shugartDrive - 1)].bytes.empty();
}

const std::string &P2000Fdc::diskPath(int shugartDrive) const
{
    static const std::string empty;
    if (shugartDrive < 1 || shugartDrive > 2)
        return empty;
    return m_drives[static_cast<std::size_t>(shugartDrive - 1)].path;
}

int P2000Fdc::currentTrack(int shugartDrive) const
{
    if (!hasDisk(shugartDrive))
        return -1;
    return m_drives[static_cast<std::size_t>(shugartDrive - 1)].cylinder;
}

void P2000Fdc::reset()
{
    m_control = 0;
    resetController();
    for (auto &drive : m_drives)
        drive.cylinder = 0;
}

void P2000Fdc::resetController()
{
    m_phase = Phase::Idle;
    m_command.clear();
    m_transfer.clear();
    m_result.clear();
    m_transferPosition = 0;
    m_resultPosition = 0;
    m_activeDrive = -1;
    m_activeUnitHead = 0;
    m_delayedInterrupt = DelayedInterrupt::None;
    m_interruptDelay = 0;
    m_lastSt0 = 0x20;
    m_lastCylinder = 0;
}

void P2000Fdc::tick(unsigned long cycles)
{
    if (m_delayedInterrupt == DelayedInterrupt::None)
        return;
    if (cycles < m_interruptDelay) {
        m_interruptDelay -= cycles;
        return;
    }
    const auto interrupt = m_delayedInterrupt;
    m_delayedInterrupt = DelayedInterrupt::None;
    m_interruptDelay = 0;
    if (m_interruptCallback)
        m_interruptCallback(interrupt == DelayedInterrupt::NotReady);
}

std::uint8_t P2000Fdc::readMainStatus() const
{
    if (!controllerEnabled())
        return 0x00;
    switch (m_phase) {
    case Phase::Idle:
        return 0x80; // RQM, CPU -> FDC, controller not busy
    case Phase::Command:
        return 0x90; // RQM | controller busy
    case Phase::ExecutionRead:
        return 0xf0; // RQM | DIO | non-DMA | controller busy
    case Phase::ExecutionWrite:
        return 0xb0; // RQM | non-DMA | controller busy
    case Phase::Result:
        return 0xd0; // RQM | DIO | controller busy
    }
    return 0x80;
}

std::uint8_t P2000Fdc::readData()
{
    if (!controllerEnabled())
        return 0xff;

    if (m_phase == Phase::ExecutionRead && (m_control & 0x01) != 0) {
        if (m_transferPosition >= m_transfer.size())
            return 0xff;
        const auto value = m_transfer[m_transferPosition++];
        if (m_transferPosition == m_transfer.size())
            finishExecution();
        return value;
    }

    if (m_phase != Phase::Result || m_resultPosition >= m_result.size())
        return 0xff;
    const auto value = m_result[m_resultPosition++];
    if (m_resultPosition == m_result.size()) {
        m_result.clear();
        m_resultPosition = 0;
        m_phase = Phase::Idle;
    }
    return value;
}

void P2000Fdc::writeData(std::uint8_t value)
{
    if (!controllerEnabled())
        return;

    if (m_phase == Phase::ExecutionWrite && (m_control & 0x01) != 0) {
        if (m_transferPosition < m_transfer.size())
            m_transfer[m_transferPosition++] = value;
        if (m_transferPosition == m_transfer.size())
            finishExecution();
        return;
    }

    if (m_phase == Phase::Result || m_phase == Phase::ExecutionRead)
        return;
    if (m_phase == Phase::Idle) {
        m_command.clear();
        m_phase = Phase::Command;
    }
    m_command.push_back(value);
    if (m_command.size() >= commandLength(m_command.front()))
        executeCommand();
}

std::uint8_t P2000Fdc::readControl() const
{
    if (!controllerEnabled() || !motorOn())
        return 0x00;
    const bool execution = m_phase == Phase::ExecutionRead ||
                           m_phase == Phase::ExecutionWrite;
    return execution && m_transferPosition < m_transfer.size() ? 0x01 : 0x00;
}

void P2000Fdc::writeControl(std::uint8_t value)
{
    const auto previous = m_control;
    m_control = value & 0x1f;
    if (!controllerEnabled()) {
        resetController();
        return;
    }
    if ((m_control & 0x02) != 0 && (previous & 0x02) == 0 &&
        (m_phase == Phase::ExecutionRead || m_phase == Phase::ExecutionWrite))
        finishExecution();
}

std::size_t P2000Fdc::commandLength(std::uint8_t command)
{
    switch (command & CommandMask) {
    case ReadTrack:
    case WriteData:
    case ReadData:
        return 9;
    case Specify:
    case Seek:
        return 3;
    case SenseDriveStatus:
    case Recalibrate:
    case ReadId:
        return 2;
    case SenseInterrupt:
        return 1;
    case FormatTrack:
        return 6;
    default:
        return 1;
    }
}

int P2000Fdc::driveIndex(std::uint8_t unit) const
{
    // Philips labels and ROM commands use 1 and 2 for the two Shugart drives.
    // Accept unit 0 as drive 1 as a compatibility concession for generic 765
    // software, but preserve the command's unit bits in returned status.
    unit &= 0x03;
    if (unit == 0 || unit == 1)
        return 0;
    if (unit == 2)
        return 1;
    return -1;
}

P2000Fdc::Drive *P2000Fdc::selectedDrive(std::uint8_t unit)
{
    const int index = driveIndex(unit);
    return index >= 0 ? &m_drives[static_cast<std::size_t>(index)] : nullptr;
}

const P2000Fdc::Drive *P2000Fdc::selectedDrive(std::uint8_t unit) const
{
    const int index = driveIndex(unit);
    return index >= 0 ? &m_drives[static_cast<std::size_t>(index)] : nullptr;
}

void P2000Fdc::executeCommand()
{
    const auto opcode = m_command.front() & CommandMask;
    switch (opcode) {
    case Specify:
        m_command.clear();
        m_phase = Phase::Idle;
        break;
    case SenseDriveStatus: {
        const auto unit = m_command[1] & 0x07;
        const auto *drive = selectedDrive(unit);
        std::uint8_t st3 = unit;
        if (drive && !drive->bytes.empty())
            st3 |= 0x20; // ready
        if (drive && drive->cylinder == 0)
            st3 |= 0x10; // track zero
        setResult({st3});
        break;
    }
    case Recalibrate: {
        const auto unit = m_command[1] & 0x03;
        auto *drive = selectedDrive(unit);
        if (!drive || drive->bytes.empty() || !motorOn()) {
            m_lastSt0 = static_cast<std::uint8_t>(0x48 | unit);
            m_lastCylinder = 0;
            m_command.clear();
            m_phase = Phase::Idle;
            scheduleInterrupt(DelayedInterrupt::Complete, 1024);
            break;
        }
        drive->cylinder = 0;
        m_lastCylinder = 0;
        m_lastSt0 = static_cast<std::uint8_t>(0x20 | unit);
        m_command.clear();
        m_phase = Phase::Idle;
        scheduleInterrupt(DelayedInterrupt::Complete, 1024);
        break;
    }
    case SenseInterrupt:
        setResult({m_lastSt0, m_lastCylinder});
        break;
    case Seek: {
        const auto unit = m_command[1] & 0x03;
        auto *drive = selectedDrive(unit);
        const auto cylinder = m_command[2];
        if (!drive || drive->bytes.empty() || !motorOn()) {
            m_lastSt0 = static_cast<std::uint8_t>(0x48 | unit);
            m_lastCylinder = cylinder;
            m_command.clear();
            m_phase = Phase::Idle;
            scheduleInterrupt(DelayedInterrupt::Complete, 1024);
            break;
        }
        drive->cylinder = std::min<std::uint8_t>(
            cylinder, static_cast<std::uint8_t>(Cylinders - 1));
        m_lastCylinder = drive->cylinder;
        m_lastSt0 = static_cast<std::uint8_t>(0x20 | unit);
        m_command.clear();
        m_phase = Phase::Idle;
        scheduleInterrupt(DelayedInterrupt::Complete, 1024);
        break;
    }
    case ReadTrack:
        beginRead(true);
        break;
    case ReadData:
        beginRead(false);
        break;
    case WriteData:
        beginWrite();
        break;
    case FormatTrack:
        beginFormat();
        break;
    case ReadId: {
        const auto unitHead = m_command[1];
        auto *drive = selectedDrive(unitHead);
        if (!drive || drive->bytes.empty() || !motorOn()) {
            failNotReady(unitHead, 0, (unitHead >> 2) & 1, 1, 1);
            break;
        }
        setIoResult(unitHead & 0x07, 0, 0,
                    static_cast<std::uint8_t>(drive->cylinder + 1),
                    0, 1, 1);
        break;
    }
    default:
        setResult({0x80}); // invalid command
        break;
    }
}

void P2000Fdc::beginRead(bool wholeTrack)
{
    const auto unitHead = m_command[1];
    auto *drive = selectedDrive(unitHead);
    m_activeDrive = driveIndex(unitHead);
    m_activeUnitHead = unitHead;
    m_activeC = m_command[2];
    m_activeH = m_command[3];
    m_activeR = wholeTrack ? 1 : m_command[4];
    m_activeN = m_command[5];
    m_activeEot = std::min<std::uint8_t>(m_command[6], SectorsPerTrack);
    if (!drive || drive->bytes.empty() || !motorOn()) {
        failNotReady(unitHead, m_activeC, m_activeH, m_activeR, m_activeN);
        return;
    }
    if (m_activeN != 1 || m_activeR == 0 || m_activeR > m_activeEot) {
        setIoResult(static_cast<std::uint8_t>(0x40 | (unitHead & 0x07)),
                    0x04, 0, m_activeC, m_activeH, m_activeR, m_activeN);
        return;
    }

    m_transfer.clear();
    for (std::uint8_t sector = m_activeR; sector <= m_activeEot; ++sector) {
        const auto offset = sectorOffset(drive->cylinder, sector);
        m_transfer.insert(m_transfer.end(), drive->bytes.begin() + offset,
                          drive->bytes.begin() + offset + SectorSize);
    }
    m_transferPosition = 0;
    m_result.clear();
    m_resultPosition = 0;
    m_command.clear();
    m_phase = Phase::ExecutionRead;
}

void P2000Fdc::beginWrite()
{
    const auto unitHead = m_command[1];
    auto *drive = selectedDrive(unitHead);
    m_activeDrive = driveIndex(unitHead);
    m_activeUnitHead = unitHead;
    m_activeC = m_command[2];
    m_activeH = m_command[3];
    m_activeR = m_command[4];
    m_activeN = m_command[5];
    m_activeEot = std::min<std::uint8_t>(m_command[6], SectorsPerTrack);
    if (!drive || drive->bytes.empty() || !motorOn()) {
        failNotReady(unitHead, m_activeC, m_activeH, m_activeR, m_activeN);
        return;
    }
    if (m_activeN != 1 || m_activeR == 0 || m_activeR > m_activeEot) {
        setIoResult(static_cast<std::uint8_t>(0x40 | (unitHead & 0x07)),
                    0x04, 0, m_activeC, m_activeH, m_activeR, m_activeN);
        return;
    }
    m_transfer.assign(static_cast<std::size_t>(m_activeEot - m_activeR + 1) *
                          SectorSize,
                      0);
    m_transferPosition = 0;
    m_command.clear();
    m_phase = Phase::ExecutionWrite;
}

void P2000Fdc::beginFormat()
{
    const auto unitHead = m_command[1];
    auto *drive = selectedDrive(unitHead);
    m_activeDrive = driveIndex(unitHead);
    m_activeUnitHead = unitHead;
    m_activeN = m_command[2];
    m_activeEot = std::min<std::uint8_t>(m_command[3], SectorsPerTrack);
    m_formatFill = m_command[5];
    if (!drive || drive->bytes.empty() || !motorOn()) {
        failNotReady(unitHead, 0, (unitHead >> 2) & 1, 1, m_activeN);
        return;
    }
    m_transfer.assign(static_cast<std::size_t>(m_activeEot) * 4, 0);
    m_transferPosition = 0;
    m_command.clear();
    m_phase = Phase::ExecutionWrite;
}

void P2000Fdc::finishExecution()
{
    if (m_activeDrive < 0 || m_activeDrive >= 2)
        return;
    auto &drive = m_drives[static_cast<std::size_t>(m_activeDrive)];
    const auto transferred = m_transferPosition;
    if (m_phase == Phase::ExecutionWrite) {
        if (m_transfer.size() == static_cast<std::size_t>(m_activeEot) * 4) {
            for (std::size_t i = 0; i + 3 < m_transfer.size(); i += 4) {
                const auto c = m_transfer[i];
                const auto r = m_transfer[i + 2];
                const auto n = m_transfer[i + 3];
                if (n == 1 && r >= 1 && r <= SectorsPerTrack) {
                    const auto physical = c > 0 ? c - 1 : drive.cylinder;
                    const auto offset = sectorOffset(physical, r);
                    std::fill_n(drive.bytes.begin() + offset, SectorSize,
                                m_formatFill);
                    m_activeC = c;
                    m_activeH = m_transfer[i + 1];
                    m_activeR = r;
                    m_activeN = n;
                }
            }
        } else {
            std::size_t position = 0;
            for (std::uint8_t sector = m_activeR;
                 sector <= m_activeEot && position + SectorSize <= transferred;
                 ++sector, position += SectorSize) {
                const auto offset = sectorOffset(drive.cylinder, sector);
                std::copy_n(m_transfer.begin() + position, SectorSize,
                            drive.bytes.begin() + offset);
            }
        }
    }
    m_transfer.clear();
    m_transferPosition = 0;
    const auto completedSectors = transferred == 0
        ? std::size_t{0}
        : (transferred - 1) / SectorSize;
    const auto resultSector = static_cast<std::uint8_t>(
        std::min<std::size_t>(m_activeEot, m_activeR + completedSectors));
    setIoResult(static_cast<std::uint8_t>(m_activeUnitHead & 0x07), 0, 0,
                m_activeC, m_activeH, resultSector, m_activeN);
}

void P2000Fdc::setResult(std::initializer_list<std::uint8_t> bytes,
                         bool interrupt)
{
    m_command.clear();
    m_transfer.clear();
    m_transferPosition = 0;
    m_result.assign(bytes);
    m_resultPosition = 0;
    m_phase = Phase::Result;
    if (interrupt)
        scheduleInterrupt(DelayedInterrupt::Complete);
}

void P2000Fdc::setIoResult(std::uint8_t st0, std::uint8_t st1,
                           std::uint8_t st2, std::uint8_t c, std::uint8_t h,
                           std::uint8_t r, std::uint8_t n, bool interrupt)
{
    setResult({st0, st1, st2, c, h, r, n}, interrupt);
}

void P2000Fdc::failNotReady(std::uint8_t unit, std::uint8_t c,
                            std::uint8_t h, std::uint8_t r, std::uint8_t n)
{
    m_lastSt0 = static_cast<std::uint8_t>(0x48 | (unit & 0x07));
    m_lastCylinder = c;
    setIoResult(m_lastSt0, 0x04, 0, c, h, r, n, false);
    scheduleInterrupt(DelayedInterrupt::NotReady, 1024);
}

void P2000Fdc::scheduleInterrupt(DelayedInterrupt interrupt,
                                 unsigned long delayCycles)
{
    m_delayedInterrupt = interrupt;
    m_interruptDelay = delayCycles;
}

std::size_t P2000Fdc::sectorOffset(std::uint8_t cylinder,
                                   std::uint8_t sector) const
{
    const auto safeCylinder = std::min<std::size_t>(cylinder, Cylinders - 1);
    const auto safeSector = std::clamp<std::size_t>(sector, 1, SectorsPerTrack);
    return (safeCylinder * SectorsPerTrack + safeSector - 1) * SectorSize;
}
