# TwinMAC RTL Handoff for Codex

Nov 4, 2026 · @Troy

Build and verify the TwinMAC RTL from this specification, one build step at a time, and stop for Troy's review after each completed step (RTL, tests, scripts, and notes together).


## Confirmed workflow clarifications (Nov 4, 2026)

- Review once per completed build step, including its RTL, tests, scripts, and notes.
- Make one commit after Troy approves that completed step; do not push without approval.
- The unreset weight register, reset behavior, ignored busy starts, and no shifting
  during a run are confirmed. The caller loads all weights before the first start.
- The wrapper retains the specified done-flag behavior: every synchronized start
  pulse clears the sticky flag, including a pulse that the busy core ignores.
  The caller waits for completion before starting another run and holds inputs
  stable during a run. No busy port or additional core control is introduced.
- Python expected-value calculations inside the required cocotb tests are allowed.
  A separate Python model remains out of scope.
- Keep the OLED off using the specified pin levels until optional step 9.
- Raw simulator logs include vendor messages after the testbench's last line.
  Keep those logs unchanged. The runner also writes a combined verification log
  whose final line is ALL TESTS PASSED only after all tools exit successfully,
  the testbench prints that verdict, and no tool output contains FAILED or an error.

## Working rules

Troy must be able to explain every file, because AI use on this class project depends on that. Work in the order under Build order, and treat this document as the requirement.

**For each step:**

1. Write or extend the test from this document. Take expected values from this document or from integer math, never from the RTL.
2. Write the RTL for that step only.
3. Run the test and keep the real output.
4. Add a short plain-language section to `docs/rtl_notes.md`: what hardware the file describes, which parts are registers, which parts are combinational, and how a clock edge moves data through it.
5. Report the files changed, the exact test command, the last lines of its output, any decision you made, and any open question.
6. Stop and wait for Troy's approval. Make one commit per approved step.

**Never do these:**

- Change a frozen item: widths, clamp range, step order, weight order, presets, pins, top module name, or tile size.
- Change an expected value, weaken a check, or delete a test to get a pass. If a value looks wrong, stop and show why.
- Add pipelining, extra clocks, RAM, IP cores, SPI, on-chip training, HDMI, or a Python model.
- Reuse Troy's older OLED files.
- Edit `.github/workflows/` or `src/config.json`, unless Troy asks.
- Push to `main`, force-push, or rewrite history.
- Claim a test, build, or board result that you did not actually run or see.

**Stop and ask Troy when:**

- This document conflicts with itself or leaves out something you need.
- A required tool is missing.
- A test keeps failing and you can't explain why.
- Vivado can't meet timing at 100 MHz, or LibreLane fails placement, routing, or timing.
- A step needs someone at the Nexys Video board.

## Repository and tools

Work natively on Windows in `C:\Users\petet\twinmac`, because Vivado runs there. GitHub Actions builds the chip layout, so you don't need Ubuntu for normal work.

| Item | Value |
| --- | --- |
| Repository | [troypeters42/twinmac](https://github.com/troypeters42/twinmac), public, created from the Tiny Tapeout SKY130 Verilog template |
| Working branch | `rtl`; merge to `main` only when Troy asks |
| Simulator | Vivado 2024.2 `xsim`, default folder `C:\Xilinx\Vivado\2024.2\bin`; confirm the path on first use |
| FPGA | Digilent Nexys Video, part `xc7a200tsbg484-1`, 100 MHz clock |
| Chip flow | `tt-gds-action@ttsky26d`, LibreLane 3.0.14, SkyWater `sky130A` |
| Local LibreLane | Ubuntu on WSL has a working 3.0.14 install, for debugging only |

```text
twinmac/
  AGENTS.md    this document
  info.yaml    project details, tile size, clock, top module, source list
  src/         chip RTL and config.json
  sim/         Vivado testbenches and run_xsim.ps1
  test/        cocotb test used by the GitHub test and gl_test jobs
  fpga/        nexys_top.sv, OLED files, and twinmac.xdc
  docs/        info.md and rtl_notes.md
```

Run Vivado simulations from the repository root:

```powershell
xvlog -sv src\clamp.sv sim\tb_clamp.sv
xelab tb_clamp -s tb_clamp_sim
xsim tb_clamp_sim -runall
```

In step 1, wrap this in `sim/run_xsim.ps1`. It takes a testbench name and source list, then exits with an error unless the log ends with `ALL TESTS PASSED` and contains no `FAILED`. Every testbench counts its failures and prints either `ALL TESTS PASSED` or `FAILED: <count>` as its last line.

Add `xsim.dir/`, `.Xil/`, `*.jou`, `*.log`, `*.pb`, and `*.wdb` to `.gitignore`. Pushes may need Troy's approval.

**Coding rules, based on the [lowRISC Verilog style guide](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md):**

- Use plain SystemVerilog that `xsim`, Icarus Verilog, and Yosys all accept. Put one module in each file, named after the file.
- Start design files with ``  `default_nettype none ``. Declare every signal.
- Use `input wire logic` for input ports in every SystemVerilog design file.
- Keep `` `timescale 1ns/1ps `` in every SystemVerilog design file.
- Use `logic`, `always_ff`, and `always_comb`. Use `<=` in clocked blocks and `=` in combinational blocks.
- Use `always_ff @(posedge clk or negedge rst_n)` for reset registers.
- Use a typed enum, a next-state block, and a state register for each FSM. Use `unique case` with a `default`.
- Give every literal an explicit width. Handle signed values explicitly.
- Use named ports, with no `.*`. Avoid latches, `X` assignments, `#` delays, and hierarchical references in design files.
- Use ASCII, two-space indents, no tabs, and at most 100 characters per line.
- Keep the port names in this document, without `_i` or `_o` suffixes. Keep the template's `input wire` and `output wire` ports on the chip top.

Keep testbenches Icarus-compatible where possible: no classes, and use `$urandom` for random values. Icarus may print `sorry` notes about constant selects and `unique case`. Those notes appeared in a test build and didn't affect its results.

## Frozen design

TwinMAC is a three-neuron ReLU network that computes six logic gates, using one clock, two multipliers, and six compute steps per result. Only the weights change between gates.

```text
neuron(b, w1, w2, p, q) = min(127, max(0, b + w1*p + w2*q))

h1 = neuron(b1, w11, w12, x1, x2)
h2 = neuron(b2, w21, w22, x1, x2)
y  = neuron(b,  a,   c,   h1, h2)
```

- **Numbers:** `x1`, `x2`, and all weights are 8-bit signed integers, and logic 1 is the integer 1.
- **Products:** Each multiply gives a 16-bit signed product. Use `*`, with no pipeline stage.
- **Accumulators:** `acc0` and `acc1` are 17-bit signed. The largest possible range is -32,640 to +32,895.
- **Clamped values:** `h1`, `h2`, and `y` are 7-bit unsigned, from 0 to 127. There is no rounding.
- **Second pass:** Extend `h1` and `h2` with a leading 0 bit before they enter the 8-bit signed multiplier.
- **Clock:** The core uses one rising-edge clock.

| Step | MAC 0 | MAC 1 | Registers updated |
| --- | --- | --- | --- |
| 1 | `b1 + x1 * w11` | `b2 + x1 * w21` | `acc0`, `acc1` |
| 2 | `acc0 + x2 * w12` | `acc1 + x2 * w22` | `acc0`, `acc1` |
| 3 | Holds | Holds | `h1`, `h2`, from the clamps |
| 4 | `b + h1 * a` | Idle | `acc0` |
| 5 | `acc0 + h2 * c` | Idle | `acc0` |
| 6 | Holds | Idle | `y`, from the clamp |

**Timing:** Call the clock edge that samples `start` E0. Steps 1 through 6 happen on edges E1 through E6. After E6, `y` is valid and `done` is high for exactly one clock cycle. The FSM is idle again by then, so a `start` sampled on E7 begins the next run.

Weights shift in most significant bit first, so bit 71 enters first and bit 0 enters last.

| Bits | Name | Meaning | Value |
| --- | --- | --- | --- |
| 71:64 | `b` | Output bias | Depends on gate |
| 63:56 | `c` | Output weight on `h2` | Depends on gate |
| 55:48 | `a` | Output weight on `h1` | Depends on gate |
| 47:40 | `b2` | `h2` bias | -1 (`0xFF`) |
| 39:32 | `w22` | `h2` weight on `x2` | 1 |
| 31:24 | `w21` | `h2` weight on `x1` | 1 |
| 23:16 | `b1` | `h1` bias | 0 |
| 15:8 | `w12` | `h1` weight on `x2` | 1 |
| 7:0 | `w11` | `h1` weight on `x1` | 1 |

**Rules confirmed by Troy on Nov 4, 2026:**

- `weight_sr` has no reset, because flip-flops without reset are smaller. Load the weights before the first `start`. Its value is unknown in simulation until then.
- Reset clears the FSM, `acc0`, `acc1`, `h1`, `h2`, `y`, and `done`. A reset during a run returns to idle.
- `start` is ignored during a run.
- Never shift weights during a run. `weight_sr` doesn't guard against this, so the caller must follow the rule.

**Out of scope:** SPI, on-chip training, more than two inputs, more than one clock domain, custom cells, HDMI, and a Python model.

## Build order

Build from the smallest block upward, and finish each row before starting the next.

| Step | Files | Done when |
| --- | --- | --- |
| 1 | `src/clamp.sv`, `sim/tb_clamp.sv`, `sim/run_xsim.ps1` | All 131,072 inputs match integer math |
| 2 | `src/mac_unit.sv`, `sim/tb_mac_unit.sv` | Corner cases and at least 1,000 random cases pass |
| 3 | `src/weight_sr.sv`, `sim/tb_weight_sr.sv` | A 72-bit pattern lands in all nine byte fields correctly |
| 4 | `src/control_fsm.sv`, `sim/tb_control_fsm.sv` | Every control output matches the table below, cycle by cycle |
| 5 | `src/twinmac_core.sv`, `sim/tb_twinmac_core.sv` | All golden vectors and at least 10,000 random cases pass |
| 6 | `src/tt_um_troypeters42_twinmac.sv`, `sim/tb_twinmac.sv`, `info.yaml`, `test/Makefile`, `test/tb.v`, `test/test.py`, `docs/info.md`; delete `src/project.v` | Chip-pin tests pass, and **test**, **gds**, **precheck**, and **gl_test** pass on `rtl` |
| 7 | Mutation results in `docs/rtl_notes.md` | Every required mutation makes a test fail |
| 8 | `fpga/nexys_top.sv`, `fpga/twinmac.xdc`, `fpga/build.tcl`, `sim/tb_nexys_top.sv` | Simulation passes, timing closes at 100 MHz, and Troy confirms the board |
| 9 | `fpga/oled_ctrl.sv`, `fpga/oled_text.sv` (optional) | Troy confirms all three OLED bring-up stages |
| 10 | Final results in `docs/rtl_notes.md` | Area, power, and maximum frequency come from the final run |

### `clamp`

This block is combinational. It has `input wire logic signed [16:0] value` and `output logic [6:0] clamped`. Negative values give 0, values above 127 give 127, and all others pass through.

### `mac_unit`

| Port | Direction | Width | Meaning |
| --- | --- | --- | --- |
| `clk`, `rst_n` | In | 1 | Clock and asynchronous active-low reset |
| `en` | In | 1 | Update `acc` on this clock edge |
| `first` | In | 1 | 1: `acc` gets `bias` + product. 0: `acc` gets `acc` + product |
| `bias` | In | 8, signed | Sign-extended to 17 bits |
| `operand_a`, `operand_b` | In | 8, signed | Multiplier inputs |
| `acc` | Out | 17, signed | Accumulator, reset to 0 |

### `weight_sr`

Its ports are `clk`, `load`, `sdi`, and `output logic [71:0] weights`. When `load` is high, `weights <= {weights[70:0], sdi}`. It has no reset port.

### `control_fsm`

Its inputs are `clk`, `rst_n`, and `start`. Use seven states: idle and steps 1 through 6. Every output below is 1 bit, except `operand_sel`, which is 2 bits.

| State | `mac0_en` | `mac1_en` | `mac_first` | `operand_sel` | `hidden_en` | `output_en` |
| --- | --- | --- | --- | --- | --- | --- |
| Idle | 0 | 0 | 0 | 0 | 0 | 0 |
| Step 1 | 1 | 1 | 1 | 0 | 0 | 0 |
| Step 2 | 1 | 1 | 0 | 1 | 0 | 0 |
| Step 3 | 0 | 0 | 0 | 0 | 1 | 0 |
| Step 4 | 1 | 0 | 1 | 2 | 0 | 0 |
| Step 5 | 1 | 0 | 0 | 3 | 0 | 0 |
| Step 6 | 0 | 0 | 0 | 0 | 0 | 1 |

`done` is a registered output. It is high only in the cycle after step 6.

### `twinmac_core`

| Port | Direction | Width | Meaning |
| --- | --- | --- | --- |
| `clk` | In | 1 | Rising-edge clock |
| `rst_n` | In | 1 | Asynchronous active-low reset |
| `load` | In | 1 | One-cycle enable that shifts `sdi` into the weights |
| `sdi` | In | 1 | Serial weight data, most significant bit first |
| `start` | In | 1 | One-cycle pulse that begins a run |
| `x1`, `x2` | In | 8, signed | Inputs, held stable during a run |
| `y` | Out | 7 | Result, 0 to 127, reset to 0 |
| `done` | Out | 1 | High for one cycle when `y` is valid |

| `operand_sel` | MAC 0 operands | MAC 0 bias | MAC 1 operands | MAC 1 bias |
| --- | --- | --- | --- | --- |
| 0 | `x1`, `w11` | `b1` | `x1`, `w21` | `b2` |
| 1 | `x2`, `w12` | `b1` | `x2`, `w22` | `b2` |
| 2 | `{0, h1}`, `a` | `b` | Not used | `b2` |
| 3 | `{0, h2}`, `c` | `b` | Not used | `b2` |

Instantiate two `mac_unit` blocks and two `clamp` blocks. `acc0` feeds one clamp, which loads `h1` when `hidden_en` is high and `y` when `output_en` is high. `acc1` feeds the other clamp, which loads `h2` when `hidden_en` is high. MAC 1's `first` input can share `mac_first`, because `mac1_en` is low in step 4.

## Chip wrapper

`tt_um_troypeters42_twinmac` connects `twinmac_core` to Tiny Tapeout's 26 pins and is the design that goes to LibreLane. Keep the template's port list and directions exactly.

| Pin | Direction | Use |
| --- | --- | --- |
| `ui_in[7:0]` | In | Data byte for `x1` or `x2` |
| `uio_in[0]` | In | `sdi`: serial weight data |
| `uio_in[1]` | In | `sck`: each rising edge shifts in one weight bit |
| `uio_in[2]` | In | `start`: a rising edge begins a run |
| `uio_in[3]` | In | `lat_x1`: a rising edge stores `ui_in` in `x1` |
| `uio_in[4]` | In | `lat_x2`: a rising edge stores `ui_in` in `x2` |
| `uo_out[6:0]` | Out | `y` |
| `uo_out[7]` | Out | Done flag, high from the end of a run until the next start |
| `uio_out`, `uio_oe` | Out | Tied to 0, so every `uio` pin is an input |
| `clk`, `rst_n`, `ena` | In | Clock, active-low reset, and an enable you ignore |

The wrapper adds these circuits:

- **Reset:** Two flip-flops give an asynchronous assert and a synchronized release. Use that synchronized reset everywhere else in the chip.
- **Control pins:** `sck`, `start`, `lat_x1`, and `lat_x2` each pass through two synchronizing flip-flops, then a rising-edge detector that makes a one-cycle pulse. The `sck` pulse drives `load`.
- **Serial data:** `sdi` passes through two synchronizing flip-flops.
- **Input registers:** `x1` and `x2` reset to 0 and load from `ui_in` on their latch pulses.
- **Done flag:** It clears on reset and on a `start` pulse, and sets on the core's `done` pulse.

**Pin timing:** Keep `sdi` and `ui_in` stable for at least 5 clock cycles on each side of the related rising edge. Hold every control pin high and low for at least 5 cycles each. Use this timing in every chip-pin test and in `nexys_top`.

Step 6 also has to update the template files:

- **`src/project.v`:** Delete this template source in step 6 when replacing the example top.

- **`info.yaml`:** Keep the current `title`, `author`, and `description`. Set the values below, and fill in the pin names for the used pins.

```yaml
language: "SystemVerilog"
clock_hz: 50000000
tiles: "1x2"
top_module: "tt_um_troypeters42_twinmac"
source_files:
  - "tt_um_troypeters42_twinmac.sv"
  - "twinmac_core.sv"
  - "control_fsm.sv"
  - "weight_sr.sv"
  - "mac_unit.sv"
  - "clamp.sv"
```

- **`test/Makefile`:** List the same six files in `PROJECT_SOURCES`.
- **`test/tb.v`:** Replace `tt_um_example` with the new top module.
- **`test/test.py`:** Replace the template's adder check, which asserts `uo_out == 50`. The **test** and **gl_test** jobs both depend on this file, so it must run all 24 gate cases at the chip pins.
- **`docs/info.md`:** Replace the placeholder text with a real description, pin use, and test procedure.

## Nexys Video demo

`nexys_top` drives the same chip top that goes to LibreLane, so the board tests the real pin behavior. These pins match [Digilent's master XDC](https://github.com/Digilent/digilent-xdc/blob/master/Nexys-Video-Master.xdc), checked on Nov 4, 2026.

| Board part | XDC port | FPGA pins | I/O standard | Use |
| --- | --- | --- | --- | --- |
| 100 MHz clock | `clk` | R4 | LVCMOS33 | System clock |
| CPU RESET button | `cpu_resetn` | G4 | LVCMOS15 | Active-low TwinMAC reset |
| BTNC | `btnc` | B22 | LVCMOS12 | OLED shutdown and restart |
| SW0 | `sw[0]` | E22 | LVCMOS12 | `x1`, as 0 or 1 |
| SW1 | `sw[1]` | F21 | LVCMOS12 | `x2`, as 0 or 1 |
| SW2 to SW4 | `sw[4:2]` | G21, G22, H17 | LVCMOS12 | Gate select |
| LD0 to LD6 | `led[6:0]` | T14, T15, T16, U16, V15, W16, W15 | LVCMOS25 | `y` |
| LD7 | `led[7]` | Y13 | LVCMOS25 | Done flag |
| OLED control | `oled_dc`, `oled_res`, `oled_sclk` | W22, U21, W21 | LVCMOS33 | Control and clock |
| OLED data and power | `oled_sdin`, `oled_vbat`, `oled_vdd` | Y22, P20, V22 | LVCMOS33 | Data and power control |

`fpga/twinmac.xdc` needs only the used ports, plus these lines from Digilent's file:

```tcl
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
```

`fpga/build.tcl` is a batch script for `vivado -mode batch -source fpga/build.tcl`. It reads `src/*.sv` and the `fpga/` sources, targets `xc7a200tsbg484-1`, runs synthesis and implementation, writes a timing summary and bitstream to `fpga/build/`, and reports worst setup and hold slack. Add `fpga/build/` to `.gitignore`. Don't add timing exceptions unless Troy approves them.

**`nexys_top` behavior:**

1. Connect `cpu_resetn` to the chip top's `rst_n`, and tie `ena` high.
2. Synchronize the switches with two flip-flops each.
3. On reset or a change of `SW[4:2]`, shift in that gate's preset through `sdi` and `sck`, using the pin timing above. Selects 110 and 111 repeat AND.
4. Repeatedly latch `x1` and `x2` as 0 or 1, pulse `start`, and wait for the done flag.
5. Drive `led[6:0]` with `y`, so LD0 is the gate's output, and drive `led[7]` with the done flag.
6. Until step 9, hold the OLED off: `oled_vdd` and `oled_vbat` high, and `oled_res`, `oled_dc`, `oled_sclk`, and `oled_sdin` low. Troy confirmed this rule on Nov 4, 2026.

FPGA timing says nothing about the SkyWater result. Troy runs the board test, so ask him to report what he sees for every gate and input.

### OLED driver

Step 9 is optional. Build it from this list, and don't copy the command table in Digilent's reference manual, because it lists `DA 00`, shows `20` without its second byte, and leaves out the multiplex ratio.

Power up in this order:

1. Drive `oled_vdd` low and wait 1 ms.
2. Wait 1 ms with `oled_res` high, send `AE`, hold `oled_res` low for 1 ms, then high for 1 ms.
3. Send `A8 1F`, `8D 14`, `D9 F1`, `81 0F`, `A0`, `C0`, `DA 02`, and `20 00`.
4. Drive `oled_vbat` low and wait 100 ms.
5. Send a blank frame, send `AF`, and wait 50 ms.
6. For every frame, send `21 00 7F` and `22 00 03`, then 512 bytes with `oled_dc` high.

- **SPI:** Run at 5 MHz, most significant bit first, with SCLK idling high. `oled_sdin` changes on the falling edge. The display latches on the rising edge and samples `oled_dc` on the eighth clock.
- **Screen:** It holds 4 rows of 16 characters, each 8 pixels square. Each data byte is one vertical column, with bit 0 at the top.
- **Font:** Only A, D, E, G, N, O, R, T, X, Y, 0, 1, colon, equals, and space are needed.
- **Bring-up:** First light every pixel, then draw a one-pixel border, then add text. If the picture is flipped, change `A0` and `C0` to `A1` and `C8`.
- **Reset:** Keep the OLED controller out of the TwinMAC reset, so CPU RESET never cuts its power suddenly.
- **Shutdown:** BTNC sends `AE`, turns VBAT off, waits 3.5 seconds, drives `oled_res` low, and turns VDD off. Digilent warns that power-off or reprogramming with the OLED on can damage it.

```text
GATE: XOR
X1=1 X2=0
Y=1
```

## Golden test vectors

These values are the reference for every test. A separate integer-math script confirmed all 24 gate cases against the truth tables, so treat a mismatch as an RTL or test bug first.

| Select `SW[4:2]` | Gate | `a` | `c` | `b` | 72-bit preset | `y` at (0,0) | (0,1) | (1,0) | (1,1) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 000 | AND | 0 | 1 | 0 | `72'h00_01_00_FF_01_01_00_01_01` | 0 | 0 | 0 | 1 |
| 001 | OR | 1 | -1 | 0 | `72'h00_FF_01_FF_01_01_00_01_01` | 0 | 1 | 1 | 1 |
| 010 | XOR | 1 | -2 | 0 | `72'h00_FE_01_FF_01_01_00_01_01` | 0 | 1 | 1 | 0 |
| 011 | NAND | 0 | -1 | 1 | `72'h01_FF_00_FF_01_01_00_01_01` | 1 | 1 | 1 | 0 |
| 100 | NOR | -1 | 1 | 1 | `72'h01_01_FF_FF_01_01_00_01_01` | 1 | 0 | 0 | 0 |
| 101 | XNOR | -1 | 2 | 1 | `72'h01_02_FF_FF_01_01_00_01_01` | 1 | 0 | 0 | 1 |

Inputs are written as (`x1`, `x2`). The hidden values are the same for every gate:

| `x1` | `x2` | `h1` | `h2` |
| --- | --- | --- | --- |
| 0 | 0 | 0 | 0 |
| 0 | 1 | 1 | 0 |
| 1 | 0 | 1 | 0 |
| 1 | 1 | 2 | 1 |

**Clamp corners:** -65,536 gives 0, -1 gives 0, 0 gives 0, 1 gives 1, 127 gives 127, 128 gives 127, and 65,535 gives 127.

**MAC corners:** -128 x -128 = 16,384, 127 x -128 = -16,256, and 127 x 127 = 16,129. Starting from bias 127, two products of -128 x -128 give 32,895. Starting from bias -128, two products of 127 x -128 give -32,640.

**Core corner vectors:**

| Case | Weights | `x1` | `x2` | Expected `y` |
| --- | --- | --- | --- | --- |
| Accumulator high | `72'h00_00_01_00_00_00_7F_80_80` | `0x80` | `0x80` | 127 |
| Accumulator low | `72'h05_00_01_00_00_00_80_7F_7F` | `0x80` | `0x80` | 5 |
| Second-pass saturation | `72'h7F_7F_7F_00_00_00_7F_7F_7F` | `0x7F` | `0x7F` | 127 |

The accumulator-high case is required. A 16-bit accumulator wraps at +32,895 and gives `y = 0`. In a throwaway test build, 300 random cases missed that bug and this one vector caught it, so random testing can't replace it.

**Random cases:** Use nine random weight bytes and random 8-bit `x1` and `x2`. Compute the expected `y` in the testbench with the `neuron` formula and integer math.

## Verification and acceptance

Work down this table in order, and don't move on until the current row passes. Vivado results come from `xsim`, and gate-level results come from the GitHub **gl_test** job.

| Level | Tool | What it covers | Pass rule |
| --- | --- | --- | --- |
| Clamp | `xsim` | All 131,072 possible 17-bit inputs | Every output matches integer math |
| MAC unit | `xsim` | Corners, `en` low, `first` high and low, reset, and random values | Every product and sum is correct |
| Weight register | `xsim` | A 72-bit pattern shifted in, with `load` also held low | All nine fields are correct, and weights hold when `load` is low |
| Control FSM | `xsim` | Idle, all six steps, `start` during a run, and reset during a run | Outputs match the table on every clock cycle |
| Core | `xsim` | All golden vectors, 10,000 random cases, reset during a run, and repeated starts | `y` and `done` timing match this document |
| Chip pins | `xsim` | All 24 gate cases through the Tiny Tapeout pins | Results match, `uio_oe` stays 0, and the done flag falls after `start` and rises when `y` is valid |
| Template test | GitHub **test** | All 24 gate cases in `test/test.py` | The job passes |
| Gate level | GitHub **gl_test** | The same test on the final netlist | No mismatches and no unknown outputs once weights are loaded |
| Board | Nexys Video | Every gate and input, set by hand | Troy reports that LD0 matches the truth table |
| Signoff | GitHub **gds** and **precheck** | Setup, hold, DRC, LVS, antenna checks, and Tiny Tapeout precheck | Zero violations |

A green gds job doesn't prove slow-corner setup. Read the per-corner table in the post-route summary.rpt.

If the **viewer** job fails only on the `rtl` branch, report it and carry on, because it publishes the results page. It must pass after the merge to `main`.

**Required mutations:** Make each change on a temporary copy, run the listed test, confirm it fails, and record the failure in `docs/rtl_notes.md`. Don't commit the mutated code.

| Mutation | Test that must fail |
| --- | --- |
| Remove the upper clamp | `tb_clamp`, core tests |
| Remove the lower clamp | `tb_clamp`, core tests |
| Narrow the accumulator to 16 bits | Core corner vector for accumulator high |
| Swap `w11` and `w12` | Core random cases |
| Treat the multiplier inputs as unsigned | MAC and core tests |
| Sign-extend `h1` instead of adding a leading 0 | Core random cases |
| Don't clear the done flag on `start` | Chip-pin done-flag check |

The throwaway test build showed why the last check must be explicit: a test that only waits for the done flag still passed with that bug.

**The RTL is finished when:**

- [ ] All `sim/` tests pass in `xsim` on the final commit.
- [ ] **docs**, **test**, **gds**, **precheck**, and **gl_test** pass with the `1x2` tile.
- [ ] Setup timing passes at 50 MHz, or the real maximum frequency is recorded and Troy accepts it.
- [ ] Hold timing passes, and DRC, LVS, and antenna checks report zero violations.
- [ ] Troy confirms all six gates on the Nexys Video.
- [ ] Area, power, and maximum frequency come from the final run. Record setup at `ss_100C_1v60`, hold at `ff_n40C_1v95`, and power at `tt_025C_1v80`, and state the power assumptions.
- [ ] `docs/rtl_notes.md` lets every group member answer the questions below.

The approved settings in `src/config.json` are `"PL_RESIZER_SETUP_SLACK_MARGIN": 2` and `"SETUP_VIOLATION_CORNERS": ["*"]`. Changes to `CLOCK_PERIOD` or `PL_TARGET_DENSITY_PCT` still require Troy's approval. Report timing failures and ask before making other configuration changes.

**Questions the notes must answer:**

1. Why can't one neuron do XOR, and how do three neurons do it?
2. Why is the accumulator 17 bits?
3. Why does the clamp have to act on the full sum?
4. What happens in each of the six steps, and why is MAC 0 used twice?
5. How do the 72 weight bits get into the chip?
6. Why does the ASIC need a real reset and input synchronizers?
7. What do setup and hold slack mean, and why are they checked at different corners?
8. What do DRC and LVS each prove?
9. What assumptions sit behind the power number?

## Sources

- [Tiny Tapeout SKY130 Verilog template](https://github.com/TinyTapeout/ttsky-verilog-template)
- [Tiny Tapeout local hardening guide](https://tinytapeout.com/guides/local-hardening/)
- [Tiny Tapeout FAQ](https://tinytapeout.com/faq/)
- [Digilent Nexys Video master XDC](https://github.com/Digilent/digilent-xdc/blob/master/Nexys-Video-Master.xdc)
- [lowRISC Verilog coding style guide](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md)
- [Codex guide to AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Codex approvals and security](https://learn.chatgpt.com/docs/agent-approvals-security)
- [Codex on Windows](https://learn.chatgpt.com/docs/windows/windows-sandbox)
