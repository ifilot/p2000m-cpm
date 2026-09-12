#!/usr/bin/env python3
"""PC companion for the P2000M 300-baud RS232 diagnostics (requires pyserial)."""
import argparse
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('port', help='COM3 or /dev/ttyUSB0, for example')
    parser.add_argument('mode', choices=('receive', 'send', 'pins'))
    parser.add_argument('--text', default='Uu0123456789\r\n')
    args = parser.parse_args()
    try:
        import serial
    except ImportError:
        parser.error('Install pyserial with: python -m pip install pyserial')
    try:
        with serial.Serial(args.port, 300, bytesize=8, parity='N', stopbits=1,
                           timeout=0.2, write_timeout=2, xonxoff=False,
                           rtscts=False, dsrdtr=False) as port:
            port.rts = True
            if args.mode == 'receive':
                print('Listening at 300 8N1; start B:SERTX. Ctrl-C stops.', flush=True)
                while True:
                    data = port.read(256)
                    if data:
                        print(data.hex(' '), repr(data), flush=True)
            elif args.mode == 'send':
                input('Start B:SERRX and wait for Listening, then press Enter here: ')
                data = args.text.encode('ascii')
                for byte in data:
                    port.write(bytes([byte]))
                    port.flush()
                    time.sleep(0.1)
                print('Sent:', data.hex(' '))
            else:
                print('Start B:SERPINS. Observe bit 1 for RTS and bit 0 for BREAK.', flush=True)
                try:
                    for ready, send_break in ((False, False), (True, False), (True, True), (True, False)):
                        port.rts = ready
                        port.break_condition = send_break
                        print(f'RTS={ready}, BREAK={send_break}', flush=True)
                        time.sleep(3)
                finally:
                    port.break_condition = False
    except KeyboardInterrupt:
        pass
    except (serial.SerialException, OSError, UnicodeError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
