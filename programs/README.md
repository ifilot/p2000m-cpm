# Programs

Each program has its own source folder and a short usage guide:

- [HELLO](hello/) — console and COM-loader smoke test
- [COPY](copy/) — file copying without overwriting
- [CPMTEST](cpmtest/) — SD filesystem regression test
- [RAMTEST](ramtest/) — SRAM filesystem regression test
- [KEYTEST](keytest/) — raw keyboard matrix and inverse-video key test
- [BANKTEST](banktest/) — revised co-board bank-switching hardware diagnostic
- [SYNC](sync/) — explicit SD write flush
- [SERPINS](serpins/) — serial input and handshake inspection
- [SERTX](sertx/) — serial transmit test
- [SERRX](serrx/) — serial receive test
- [BASDEMO](basdemo/) — Microsoft BASIC example
- [CDEMO](cdemo/) — BDS C compile/link example

Shared assembly includes live in [common](common/). Run `python3 tools/build.py`
from the repository root to build the COM files in `build/` and populate the
SD image. BASIC and C example sources are installed on E: and B: respectively.
See the [build guide](../docs/source-guide.md#verification) for dependencies.
