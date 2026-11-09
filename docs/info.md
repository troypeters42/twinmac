## How it works

TwinMAC is a three-neuron integer ReLU network implemented with two shared
multiply-accumulate units. It computes AND, OR, XOR, NAND, NOR, or XNOR
by loading a different 72-bit weight preset. Each neuron sums an 8-bit
signed bias and two signed products, then clamps the full 17-bit sum to
the unsigned range 0 through 127. Logic true is integer 1.

The core uses six compute edges after accepting start. The chip wrapper
synchronizes external controls, latches the two input bytes, and retains
a done flag until the next start. All logic uses the clk input.

## Pin use

| Pins | Use |
| --- | --- |
| ui_in[7:0] | Signed data byte to latch as x1 or x2 |
| uio[0] | Serial weight data, sdi |
| uio[1] | sck; each rising edge requests one weight-bit shift |
| uio[2] | start; rising edge requests one computation |
| uio[3] | lat_x1; rising edge stores ui_in as x1 |
| uio[4] | lat_x2; rising edge stores ui_in as x2 |
| uio[7:5] | Unused inputs |
| uo_out[6:0] | y, unsigned result from 0 through 127 |
| uo_out[7] | Sticky done flag; clears on start or reset |
| clk | System clock, specified at 50 MHz |
| rst_n | Active-low reset; assertion is asynchronous, release synchronized |
| ena | Ignored |

All uio pins are inputs: uio_out and uio_oe are tied to zero.

## How to test

1. Hold control pins low, assert rst_n low, then release it and wait at least
   five clock cycles.
2. Load all 72 weight bits, most significant first. Set sdi at least five
   cycles before raising sck, keep it stable at least five cycles afterward,
   and hold sck high and low for at least five cycles each.
3. Place x1 on ui_in, wait five cycles, pulse lat_x1 high for five cycles,
   then hold it low for at least five cycles. Repeat for x2 and lat_x2.
   Keep ui_in stable for at least five cycles on both sides of each latch edge.
4. Pulse start high for at least five cycles and low for at least five.
   Verify the old done flag clears, then wait for it to rise with a valid y.
   Keep input latches and weight-shift controls inactive during computation.
5. Check the result against the chosen gate's truth table. Reset clears
   inputs, core registers, result, and done, while preserving loaded weights.

The wrapper synchronizes controls to clk; sck is a data-control strobe,
not an internal clock. The sticky flag registers the core's completion
pulse, so it may rise one clock after the core result becomes valid.

From the repository root, run the chip-pin xsim test with:

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_twinmac -Sources @('src\clamp.sv','src\mac_unit.sv','src\weight_sr.sv','src\control_fsm.sv','src\twinmac_core.sv','src\tt_um_troypeters42_twinmac.sv','sim\tb_twinmac.sv')
```

The GitHub test and gl_test jobs use test/test.py to run all 24 gate cases,
eight directed corners, and reset/retained-weight checks through the chip pins.

## External hardware

A host that drives clk, reset, data, and the five control/data pins is sufficient.
The planned Nexys Video demonstration uses the same chip wrapper.
Board operation is verified separately during the FPGA demonstration step.
