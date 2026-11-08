# TwinMAC OLED Part 2 board checklist

Prerequisite: run this OLED checklist only after the plain board test passes.
Troy passed the plain checklist on Nov 5, 2026 using bitstream 28671ec5...
The complete plain and earlier OLED results are recorded in rtl_notes.md.

Board result: PASSED, as reported by Troy for this exact OLED Part 2 image.
Observer: Troy. Board-test date: not supplied. Notes: not supplied.
The date and notes were left blank in Troy's approval; they are not inferred
from the commit date. Individual readings were not supplied. Expected values
and blank fields below remain as a reusable checklist, not pending acceptance.

Tested bitstream SHA-256:
b73e56ff6bc0b685c04e21fca6818a0c2c9b9cb86fba790bb95aea43a65a7148

Preserved tested copy: C:\Users\petet\twinmac-oled-part2-tested\nexys_top.bit.
The earlier tested OLED image (92bc134d...) remains unchanged at
C:\Users\petet\twinmac-oled-tested\nexys_top.bit. The plain demo remains separate.
Codex did not program or observe the board; the hardware result is Troy's report.

1. With the board off, set JP4 to JTAG.
2. Connect 12 V power to J21 and micro-USB from PROG (J12) to the computer.
3. Power on with SW8 and confirm the OLED stays dark. If it lights up, stop. Do not
   reprogram it or power it off until the running image's shutdown step is identified.

OLED dark before programming: ______  Date / observer: ____________________

## Program the reviewed OLED image

- [ ] Leave CPU RESET and BTNC released. Set gate SW[4:2]=000 (AND), SW0=0, SW1=0.
- [ ] Set SW[6:5]=01: SW6 off, SW5 on, for the first bring-up stage.
- [ ] In Vivado Hardware Manager, select the Nexys Video device. Use this explicit
      path; check the printed PROGRAM.FILE before issuing program_hw_devices:

```tcl
set board_device [current_hw_device]
set_property PROGRAM.FILE {C:/Users/petet/twinmac-oled/fpga/build/nexys_top.bit} $board_device
get_property PROGRAM.FILE $board_device
program_hw_devices $board_device
```

- [ ] Confirm PROGRAM.FILE printed C:/Users/petet/twinmac-oled/fpga/build/nexys_top.bit,
      programming completed successfully, and the board's DONE LED is lit before
      checking the OLED. Confirm the file hash below matches the reviewed packet.
- [ ] Confirm the selected file is from twinmac-oled, not the retained plain build
      at C:\Users\petet\twinmac\fpga\build\nexys_top.bit.
- [ ] Allow one second for the power sequence and first map/frame to settle.

Part 2 rebuilt OLED bitstream SHA-256:

```text
b73e56ff6bc0b685c04e21fca6818a0c2c9b9cb86fba790bb95aea43a65a7148
```

Selected file / hash checked: ______________________________________________
Programming result and first visible image: _______________________________

## Three bring-up stages, in order

| Stage | SW6 | SW5 | Predicted display | What I observed |
| --- | --- | --- | --- | --- |
| 1 | 0 | 1 | Every pixel of the 128-by-32 display lit | __________________ |
| 2 | 1 | 0 | A one-pixel border; interior dark | __________________ |
| 3 | 0 | 0 | Left map and the three text rows below | __________________ |

For stage 3 with AND and inputs (0,0), the predicted text starts at column 40:

```text
GATE: AND
X1=0 X2=0
Y=0
```

- [ ] Verify the map is 32 columns wide at the left, followed by an eight-column gap.
- [ ] Verify the text uses three rows; the fourth text row is blank.
- [ ] Verify SW[6:5]=11 gives the same normal display as 00, then return to 00.

Text / spacing / normal-alias observations: _______________________________

## Six real-chip decision maps

x1 increases to the right; x2 increases upward. (0,0) is the map's bottom left.
A pixel is lit for y >= 16 using the map preset and a real completed chip run.
Set each gate below and allow one second to settle. Switch changes can briefly
show map values on the LEDs during the sweep; judge Boolean LED results afterward.

| SW[4:2] | Gate | Predicted lit region | Predicted lit pixels | Observed shape / orientation |
| --- | --- | --- | ---: | --- |
| 000 | AND | x1+x2 >= 47; upper-right triangle | 136 | __________________ |
| 001 | OR | x1+x2 >= 16; one boundary | 888 | __________________ |
| 010 | XOR | 16 <= x1+x2 <= 46; band with two boundaries | 752 | __________________ |
| 011 | NAND | x1+x2 <= 46 | 888 | __________________ |
| 100 | NOR | x1+x2 <= 15; lower-left triangle | 136 | __________________ |
| 101 | XNOR | x1+x2 <= 15 or x1+x2 >= 47; two corner regions | 272 | __________________ |
| 110 | AND alias | Same as 000 | 136 | __________________ |
| 111 | AND alias | Same as 000 | 136 | __________________ |

If a map is mirrored or upside down, record it and stop for review; the source
uses the specified A0/C0 orientation, covered by Troy's reported checklist pass.
Observed map orientation / any mismatch: __________________________________

## Live Boolean text and LEDs

SW0 is x1 and SW1 is x2. The Y text must match the chip's latest completed Boolean
result and LD0. LD1 through LD6 should be off after a sweep settles. LD7 should
look steady during repeated computations. Changing only SW0/SW1 changes the text
and Boolean result; the decision map remains the selected gate's map.

Each cell below is predicted Y / my observed Y (check both text and LD0):

| Gate | (0,0) | (0,1) | (1,0) | (1,1) |
| --- | --- | --- | --- | --- |
| AND | 0 / ___ | 0 / ___ | 0 / ___ | 1 / ___ |
| OR | 0 / ___ | 1 / ___ | 1 / ___ | 1 / ___ |
| XOR | 0 / ___ | 1 / ___ | 1 / ___ | 0 / ___ |
| NAND | 1 / ___ | 1 / ___ | 1 / ___ | 0 / ___ |
| NOR | 1 / ___ | 0 / ___ | 0 / ___ | 0 / ___ |
| XNOR | 1 / ___ | 0 / ___ | 0 / ___ | 1 / ___ |

- [ ] Explicitly check X1=1 X2=0 and X1=0 X2=1 in the text.
- [ ] Change gates without CPU RESET; the final map, gate label, and result must agree.
- [ ] Press CPU RESET mid-display while a nonzero Boolean result is visible.
      LEDs clear after the second rising clock edge. This is a nominal two-cycle
      20 ns reset path at 100 MHz; with an arbitrary button phase the second edge
      arrives 10 to 20 ns after the fall (16.7 ns in the off-edge simulation).
      The OLED stays powered, finishes its in-flight frame, and keeps that image.
- [ ] Release CPU RESET. A fresh complete sweep and Boolean result must appear
      before new user frames resume. Confirm the displayed gate, X1, X2, Y and
      map agree, and there is no OLED power cycle.
- [ ] Repeat CPU RESET during a gate-change map sweep and confirm recovery.

CPU RESET / gate-change / LED observations: ________________________________

## BTNC shutdown and restart

- [ ] During normal display, press and hold BTNC for about TWO SECONDS.
      Confirm the display goes dark while the button is still held. Release it;
      release must do nothing more and must not restart or toggle the display.
- [ ] Wait at least FOUR SECONDS AFTER RELEASE, even if the OLED goes dark sooner.
      The controller finishes the current frame, sends AE, turns VBAT off, waits
      3.5 seconds, holds reset low, and then turns VDD off. Darkness alone does
      not mean that discharge wait has finished. Do not double-press the button.
- [ ] Confirm the OLED remains dark after that wait. Boolean LED computations
      should continue while the OLED is off.
- [ ] To test restart, press/release BTNC once again and allow one second. The
      complete power-up sequence should restore the latest map and Boolean text.

Shutdown wait / dark-state / continuing LEDs: ______________________________
Restart observations: ____________________________________________________

## Before any reprogramming or power-off

If shutdown has already completed and the OLED remains off, leave it off;
pressing BTNC again would restart it. Otherwise, with the OLED running:

Press BTNC once for about 50 ms, release, and wait at least FOUR SECONDS.
Confirm the OLED remains dark. Only then reprogram the FPGA or turn power off.
If the display does not stay dark, stop; do not reprogram or power off until
its shutdown state is understood.

Final shutdown performed / wait / observed result: _________________________
All three bring-up stages confirmed by: ____________________________________
All six maps and 24 Boolean cases confirmed by: ____________________________

## Short retest for the Part 2 rebuild

Troy reported this checklist passed for the exact Part 2 hash above.
Date and notes were not supplied. The form remains available for future retests;
the Nov 5 results for the older images remain separate historical records.

- [ ] After the plain prerequisite passes, run the three bring-up modes,
      all six oriented maps, and the 24 Boolean cases using the new hash above.
- [ ] Change SW5/SW6, SW0/SW1, and the selected gate while frames are updating.
      Each displayed frame should keep a consistent mode, map, label and result.
- [ ] Assert/release CPU RESET during a map sweep and during normal display.
      OLED power should stay on; a new complete map/result should appear afterward.
- [ ] Hold BTNC for about two seconds and confirm darkness before release. Wait at least
      four seconds after release before reprogramming or power-off. Release must
      not restart the OLED. Press again to restart; confirm the map/text return.

New-image hash checked: ___________________________________________________
Observer / date: __________________________________________________________
Retest observations / mismatch: ___________________________________________
