#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>

class P2000Fdc
{
public:
    static constexpr std::size_t Cylinders = 35;
    static constexpr std::size_t SectorsPerTrack = 16;
    static constexpr std::size_t SectorSize = 256;
    static constexpr std::size_t DiskCapacity =
        Cylinders * SectorsPerTrack * SectorSize;

    // Argument is false for command completion (CTC channel 0), true for the
    // P2000 board's independent not-ready signal (CTC channel 1).
    using InterruptCallback = std::function<void(bool)>;

    explicit P2000Fdc(InterruptCallback interruptCallback = {});

    bool insertDisk(int shugartDrive, const std::string &path,
                    std::string *error = nullptr);
    void ejectDisk(int shugartDrive);
    bool hasDisk(int shugartDrive) const;
    const std::string &diskPath(int shugartDrive) const;
    int currentTrack(int shugartDrive) const;

    void reset();
    void tick(unsigned long cycles);

    std::uint8_t readMainStatus() const;
    std::uint8_t readData();
    void writeData(std::uint8_t value);
    std::uint8_t readControl() const;
    void writeControl(std::uint8_t value);

private:
    enum class Phase { Idle, Command, ExecutionRead, ExecutionWrite, Result };
    enum class DelayedInterrupt { None, Complete, NotReady };

    struct Drive {
        std::vector<std::uint8_t> bytes;
        std::string path;
        std::uint8_t cylinder = 0;
    };

    static std::size_t commandLength(std::uint8_t command);
    int driveIndex(std::uint8_t unit) const;
    Drive *selectedDrive(std::uint8_t unit);
    const Drive *selectedDrive(std::uint8_t unit) const;
    bool controllerEnabled() const { return (m_control & 0x04) != 0; }
    bool motorOn() const { return (m_control & 0x08) != 0; }

    void resetController();
    void executeCommand();
    void beginRead(bool wholeTrack);
    void beginWrite();
    void beginFormat();
    void finishExecution();
    void setResult(std::initializer_list<std::uint8_t> bytes,
                   bool interrupt = false);
    void setIoResult(std::uint8_t st0, std::uint8_t st1, std::uint8_t st2,
                     std::uint8_t c, std::uint8_t h, std::uint8_t r,
                     std::uint8_t n, bool interrupt = true);
    void failNotReady(std::uint8_t unit, std::uint8_t c, std::uint8_t h,
                      std::uint8_t r, std::uint8_t n);
    void scheduleInterrupt(DelayedInterrupt interrupt,
                           unsigned long delayCycles = 256);
    std::size_t sectorOffset(std::uint8_t cylinder, std::uint8_t sector) const;

    std::array<Drive, 2> m_drives;
    InterruptCallback m_interruptCallback;
    Phase m_phase = Phase::Idle;
    std::uint8_t m_control = 0;
    std::vector<std::uint8_t> m_command;
    std::vector<std::uint8_t> m_transfer;
    std::vector<std::uint8_t> m_result;
    std::size_t m_transferPosition = 0;
    std::size_t m_resultPosition = 0;
    std::uint8_t m_lastSt0 = 0x20;
    std::uint8_t m_lastCylinder = 0;
    int m_activeDrive = -1;
    std::uint8_t m_activeUnitHead = 0;
    std::uint8_t m_activeC = 0;
    std::uint8_t m_activeH = 0;
    std::uint8_t m_activeR = 1;
    std::uint8_t m_activeN = 1;
    std::uint8_t m_activeEot = 1;
    std::uint8_t m_formatFill = 0;
    DelayedInterrupt m_delayedInterrupt = DelayedInterrupt::None;
    unsigned long m_interruptDelay = 0;
};
