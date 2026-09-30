# Sinclair QL for [MiSTer Board](https://github.com/MiSTer-devel/Main_MiSTer/wiki) 

## About this fork

This fork of the [MiSTer QL core](https://github.com/MiSTer-devel/QL_MiSTer) adds QSound and brings the timing of the 68008 in line with a real QL, measured with test programs on a real machine (JS ROM, 128K and with expansion RAM).

### What it adds
* **QSound**: the AY-3-8910 sound card for the QL, with its 8K ROM at $0C0000 (loaded from the OSD with *Load QSound*) and its registers at $0C2000 and $0C3000. The OSD lets you choose the AY clock (750 kHz, 1 MHz, 1.77 MHz or 2 MHz) and mono, stereo ABC or stereo ACB output. QSound uses the address space at $0C0000, so while it is enabled only 128k and 640k of RAM are offered, as on real hardware.
* **Timing measured on a real QL**: only the 128K on the motherboard wait for the ZX8301; ROM, I/O and expansion RAM have no wait states, as on a QL; writes get their wait states; and the ZX8301 uses 31 of the 40 chunks of each visible line and 13 of each border line, as measured in each region of the frame.
* **IPC link fix**: a write to $18003 is taken once per bus cycle, so a repeated write can no longer corrupt the bit being sent to the IPC.
* **Frame interrupt 41 lines before the first visible line** (6 lines of vertical sync and 35 of top border), as measured on a real QL.
* **Immediate screen switch**: a change of screen (bit 7 of $18063) shows at once, even in the middle of a frame, so double buffered programs display correctly.
* **Square pixel option** (*CRT 1:1 Square Pixel*): a 14 MHz pixel clock with the same line length, for square pixels on a CRT.

### Measurements
Blocks counted in 10 seconds by the timing test programs, on a real QL and on this core:

| Test | Real QL | This core |
|---|---|---|
| T0 NOP loop (expansion RAM) | 1076 | 1076 |
| T1 copy, internal RAM | 354 | 354 |
| T2 read, internal RAM | 530 | 532 |
| T3 write, internal RAM | 510 | 510 |
| T4 copy, expansion RAM | 555 | 555 |
| T5 copy with interrupts | 314 | 318 |
| T6 MULU, D5=0 | 539 | 539 |
| T7 MULU, D5=$FFFF | 367 | 367 |
| T8 DIVU | 248 | 248 |

With the code in the internal 128K as well, the eleven tests of a second battery (copies, reads and writes of bytes, words and long words, MOVEM, CLR, ADD) give the same result as the real QL, except the test with interrupts (2 % faster). The official core ran code in expansion RAM at about half the speed of a real QL.

### Notes
* The core uses the Hermes IPC firmware (you will hear the key click), which answers the IPC link faster than the original Sinclair firmware.
* The QSound ROM and more information about the card: [QL_Qsound2](https://github.com/alvaroalea/QL_Qsound2), the QSound clone by Álvaro Alea.

### Credits
* The original QL core for the MiST by Till Harbaum, and its MiSTer port with its many improvements (see below).
* `ql_timing` (the model of the ZX8301 memory contention) by Marcel Kilgus and Daniele Terdina.
* fx68k (the 68000 CPU) by Jorge Cwik.
* T48 (the 8049 of the IPC) by Arnim Läuger.
* [JT49](https://github.com/jotego/jt49) (the AY-3-8910) by Jose Tejada.
* [QL_Qsound2](https://github.com/alvaroalea/QL_Qsound2), the QSound clone by Álvaro Alea.

---

This is a much advanced port of the Sinclair QL implementation for the [MiST](https://github.com/mist-devel/mist-board/tree/master/cores/ql)

### Changes from MiST implementation:
* Switched CPU to cycle-perfect fx68 core
* QL/16Mhz/24Mhz/42Mhz CPU speeds
* 896kB/4096kB of RAM
* Support for SMSQ/E operating system using a GoldCard like implementation and boot ROM ("MiSTer Gold Card", also contains TK2). Automatically enabled when 4MB RAM is selected
* Full QL-SD support using real QL-SD card in secondary slot or QL-SD images (often called "QXL.WIN" files) on primary card. Needs QL-SD driver 1.08 or higher
* Allow dynamic mounting of QL-SD images from OSD
* Allow switching OS from the OSD
* RTC

### Installation:
* Copy the *.rbf file to the root of the SD card. 
* Download the MiSTer_QL_OS zip file from https://www.kilgus.net/ql/mister/ and copy one of the files (JS, Minerva English or Minerva German) as boot.rom into QL folder.
* Download qlsd_win_demo.zip from same page and extract it as boot.vhd to QL folder (or QL.vhd in root folder) if it should automatically be mounted. Otherwise mount later using OSD.
* Optionally copy some *.mdv files to QL folder.

## Operating systems
All QL operating systems are supported. More ROMs are available from http://www.dilwyn.me.uk/qlrom/. ROM size should be 49152 for pure OS images or 65536 for OS + 16kB extension ROM. QL-SD can be used if the QL-SD driver is in the extension ROM, but otherwise ROMs like TK2 are supported, too.

Additionally the much enhanced SMSQ/E operating system is now supported. The MiSTer SMSQ/E version is basically a GoldCard SMSQ/E minus the floppy driver as that is not implemented. Download it from https://www.kilgus.net/ql/mister/. It should be put into a QL-SD image and then be executed using LRESPR.

## QL-SD images
The new QL-SD driver uses QLWA type hard drive image files. These are the same files also supported by most major emulators (QPC, QemuLator, SMSQmulator) and native hardware solutions (QL with QL-SD, Q40/Q60, Q68), so data exchange is fairly easy. Images on a secondary SD card must be contiguous or data loss can happen! Best to copy it onto a clean SD card. Images on the primary SD are not affected from this limitation.
When an image is mounted from the primary SD the secondary SD slot remains available as "card 2" and any file called "QXL.WIN" on it is automatically mounted as the "WIN2" device (e.g. "DIR win2_"). Different files can be mounted using the WIN_DRIVE command, see QL-SD manual for details.

## MDV images
Files can be loaded from microdrive images stored in MDV files in QLAY format. These files must be exactly 174930 bytes in size. Examples can be found in http://web.inter.nl.net/hcc/A.Jaw.Venema/psion.zip as well as in the [releases](https://github.com/MiSTer-devel/QL_MiSTer/tree/master/releases) directory.
