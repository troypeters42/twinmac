# TwinMAC RTL notes

## Current status

- Updated Nov 5, 2026. OLED worktree: C:\Users\petet\twinmac-oled; branch: oled.
- Based on e8e710e. Original C:\Users\petet\twinmac and rtl remain unchanged.
- main remains at 162764d. Prior implementation commits below are on rtl; this step 9 commit is on oled.
- The final ASIC measurements come from 93ed933, GDS run 41988729116.
  Its six GitHub jobs passed. The FPGA-only OLED work preserves that ASIC design.

| Step | Commit | Current result |
| --- | --- | --- |
| 1: clamp | 156a403; review/rules follow-up fefa178 | Complete; exhaustive test passed |
| 2: MAC unit | fec9360 | Complete; reviewed reset-release test included |
| 3: weight register | 4489ce1 | Complete |
| 4: control FSM | 6027a6d | Complete |
| 5: TwinMAC core | 1f75cbb | Complete; both accumulator-high paths checked |
| 6: chip wrapper | e3ef3e8; exact-latency follow-up b4fcc70 | Complete; chip-pin and GitHub checks passed |
| 7: required mutations | c105b87 | Complete; every required mutation was caught |
| 8: Nexys Video demo | 93ed933 | Troy reports board test passed; detailed observations not supplied |
| 9: optional OLED | This commit on oled, from e8e710e | Approved for commit; simulation/build passed; **OLED board checks pending** |
| 10: final notes and measurements | e8e710e | Area/power/frequency and nine answers recorded; all seven xsim reruns passed |

The approved ASIC timing configuration is f71810b, between steps 7 and 8.
It adds the 2 ns setup-repair margin and all-corner setup gate. The clock
period remains 20 ns and placement density remains 60%. The remaining
open items are 303 max-slew checks, one max-fanout check, the two FPGA
LUT-packing warnings, and Troy's physical board observations.

## Confirmed working decisions

Review each completed build step as a group of RTL, tests, scripts, and notes.
Commit the step after Troy approves it. Keep the original frozen arithmetic,
weights, pins, timing contract, and build order.

The weight shift register has no reset. Load all 72 bits before starting.
Reset clears the core's other registers and aborts an active run.
The core ignores start while running; callers keep inputs and weights stable.
The chip wrapper retains its specified rule that every start pulse clears
the sticky done flag, even if the core ignores that pulse. Callers wait for
completion before requesting another run.

Python expected-value calculations inside cocotb tests are allowed; a separate
Python model remains out of scope. The plain step 8 image keeps the OLED off.
Troy authorized the FPGA-only OLED additions documented in step 9 below.

## Answers to the nine AGENTS.md questions

### Q1: Why can't one neuron do XOR, and how do three neurons do it?

One neuron draws a single straight line through the (x1, x2) plane:
its weighted sum changes from nonpositive to positive across that line.
XOR's 1s are at (0,1) and (1,0), while its 0s are at (0,0) and (1,1).
No straight line separates those two pairs of opposite corners. Clamping
a single weighted sum therefore cannot make XOR.

The real XOR preset is 72'h00_FE_01_FF_01_01_00_01_01. Its hidden
weights give h1=clamp(x1+x2) and h2=clamp(-1+x1+x2). The output weights
are a=1, c=-2, b=0, so y=clamp(h1-2*h2). For these Boolean inputs,
the last clamp does not change the result:

| x1 | x2 | h1 | h2 | y = h1 - 2*h2 |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 0 | 0 | 0 | 0 |
| 0 | 1 | 1 | 0 | 1 |
| 1 | 0 | 1 | 0 | 1 |
| 1 | 1 | 2 | 1 | 0 |

h1 counts the 1s. h2 detects the case where both inputs are 1. Subtracting
two copies of h2 removes that case, leaving exactly one input high.
[Step 5](#step-5-twinmac-core) describes how the hardware computes these
three neurons using two MAC units.

### Q2: Why is the accumulator 17 bits?

Two signed products plus bias can reach +32895, above the signed 16-bit
maximum of +32767. Seventeen signed bits preserve that result and the
-32640 low corner without wrapping. The complete ranges and arithmetic
are in [Why the accumulator is 17 bits](#why-the-accumulator-is-17-bits).

### Q3: Why does the clamp have to act on the full sum?

The two products and bias must finish adding before deciding whether
the neuron is negative, in range, or too large. The clamp must see all
17 signed bits: taking only the low seven bits can turn -1 into 127 or
128 into 0. [Step 1](#step-1-clamp) explains these examples and the
exhaustive check; [Step 5](#step-5-twinmac-core) shows the final-sum wiring.

### Q4: What happens in each of the six steps, and why is MAC 0 used twice?

Steps 1 and 2 add the two products for both hidden neurons in parallel.
Step 3 stores their clamped results in h1 and h2. Steps 4 and 5 reuse
MAC 0 for the output neuron's two products, and step 6 stores y and
raises done. Step 4's first control replaces the old hidden sum with
the output bias plus its first product. This reuse needs two multipliers
rather than a separate multiplier pair for each neuron. The edge-by-edge
table is in [What happens on the six compute edges](#what-happens-on-the-six-compute-edges).

### Q5: How do the 72 weight bits get into the chip?

The caller sends all nine weight bytes serially, most significant bit
first. Each synchronized sck pulse enables one shift on the chip clock;
bit 71 enters first and bit 0 last. After 72 shifts the nine fields are
in their specified positions. sck is a strobe, not another internal clock.
[Why most significant bit goes first](#why-most-significant-bit-goes-first)
shows the field order, and [Step 6](#step-6-tiny-tapeout-chip-wrapper)
describes synchronization and the five-cycle pin setup/hold protocol.

### Q6: Why does the ASIC need a real reset and input synchronizers?

ASIC flip-flops have an unknown power-up state. They do not receive the
FPGA configuration step that sets FPGA flip-flops to known initial values.
Reset gives the chip a known control state, zero inputs/results, and a
cleared done flag before it starts work. Reset assertion is asynchronous;
the wrapper releases its internal reset through two clocked stages.

An external pin can change at any time relative to the chip clock. If it
changes too close to the sampling edge, the receiving flip-flop can go
metastable: it takes extra time to settle to a valid 0 or 1. The first
synchronizer stage gets almost a full clock cycle to settle before the
second stage samples it. That greatly reduces the risk of an unsettled
value reaching the control logic. The control pins and sdi use these
two stages; the data-byte bus instead follows the specified stable-data
protocol before its synchronized latch pulse. See the actual circuits
and timing rules in [Step 6](#step-6-tiny-tapeout-chip-wrapper).

The weight register needs no reset because the caller overwrites all
72 bits before the first start. That pushes every unknown old bit out.
Avoiding reset on those 72 flip-flops saves reset hardware. The caller
must complete the load before computing; later resets preserve the
already-loaded weights. [Step 3](#step-3-weight-shift-register) explains
the shift/hold behavior and checks it bit by bit.

### Q7: What do setup and hold slack mean, and why use different corners?

Slack is the margin before a timing requirement is broken. For setup,
slack is required time minus arrival time: data must arrive before the
receiving register's setup deadline. Positive slack passes; negative
slack means data arrives too late.

The real worst path begins at core.controller.state[1], mapped to cell
_2554_. Its printed path report gives:

```text
setup slack = required time - arrival time
20.643263 ns - 19.711073 ns ~= +0.932191 ns (reported STA result)
```

The displayed arrival/required times are rounded: subtracting those
printed values gives 0.932190 ns, while STA's full-precision subtraction
reports +0.932191 ns. The reported result is retained above.

For hold, new data must not arrive too soon after the receiving clock
edge. Hold slack is earliest arrival time minus the minimum required
time; a positive result means the old value was held long enough.
Slow logic is worst for setup, while fast logic is worst for hold.
The existing process/temperature/voltage and RC-corner explanation,
including the actual nine results, is in
[Setup, hold, and all nine corners](#setup-hold-and-all-nine-corners).

### Q8: What do DRC and LVS each prove?

DRC checks that the layout obeys the foundry's geometry rules, such as
minimum widths, spacing, and required overlaps. LVS extracts a circuit
from that layout and checks that it matches the reference gate-level
netlist: the expected devices and connections must be present.

Neither proves that the design is functionally correct or meets timing.
Simulation checks behavior against expected results, and static timing
analysis checks setup and hold. The actual check counts and remaining
limitations are in [Physical checks and remaining limitations](#physical-checks-and-remaining-limitations),
with the separate build/precheck DRC coverage in [DRC scope and status](#drc-scope-and-status).

### Q9: What assumptions sit behind the power number?

The 4.647541 mW number is a model-based estimate at 50 MHz, typical
process, 25 C, 1.80 V, and nominal extracted RC. It uses default input
activity and propagated internal activity, not a measured workload VCD.
Clock-tree power is already included. Different input activity, loading,
idle time, voltage, temperature, or process can change the estimate.
[Power assumptions and what the estimate covers](#power-assumptions-and-what-the-estimate-covers)
records the exact defaults, loads, limitations, and source reports.

## Step 1: clamp

### What hardware this describes

src/clamp.sv describes a combinational range limiter. Its input is the complete
signed 17-bit sum; its output is an unsigned 7-bit number.

- If the input is negative, output 0.
- If it is greater than 127, output 127.
- Otherwise, pass through the low seven bits.

Signed comparisons select between those three values. Every branch assigns
the output, so there is no latch. There are no registers, no clock input,
and no reset input. A clock edge does not move data inside this block:
its output responds to changes at its input after combinational propagation.
Later core registers will sample this output at their prescribed clock edges.

The comparisons must happen before taking the low seven bits. For example,
-1 has low bits 127 but must produce 0; 128 has low bits 0 but must produce 127.
Discarding upper bits first would give the wrong answer in both cases.
Values from 0 through 127 pass through exactly, without rounding.

### What the other files do

sim/tb_clamp.sv is simulation-only code. It visits every integer from -65536
through 65535 exactly once, drives its 17-bit representation, waits 1 ns for
the combinational output to settle, and compares with an integer reference.
The reference uses the candidate integer, never the RTL output. Case inequality
also treats any unknown output bit as a mismatch. Failures are counted;
only the first 16 mismatches are printed to limit diagnostic volume.

The exhaustive sweep includes every listed corner: -65536, -1, 0, 1, 127,
128, and 65535. It checks both saturation regions and every pass-through value.

sim/run_xsim.ps1 checks the source files and tool paths, then runs xvlog,
xelab, and xsim in order. A failed stage stops the run. Success requires
zero tool exit codes, exactly one testbench ALL TESTS PASSED verdict, and
no FAILED, ERROR, or FATAL diagnostics in tool output.

Vivado prints its own shutdown messages after the testbench's final verdict.
The runner preserves the raw tool logs, and also writes a combined verification
log that ends in ALL TESTS PASSED only after all checks succeed. It does not
treat simulator shutdown with exit code zero as sufficient evidence of a pass.

.gitignore excludes generated simulator files and the future fpga/build folder.
AGENTS.md contains the adopted handoff and the agreed workflow clarifications.

### Actual verification

Tool: Vivado Simulator 2024.2. Run from C:\Users\petet\twinmac:

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_clamp -Sources @('src\clamp.sv', 'sim\tb_clamp.sv')
```

The command exited with code 0. The final lines of the combined log were:

```text
Checked 131072 signed inputs (-65536 through 65535).
ALL TESTS PASSED
$finish called at time : 131072 ns : File "C:/Users/petet/TwinMac/sim/tb_clamp.sv" Line 56
exit
INFO: [Common 17-206] Exiting xsim at Wed Nov  4 18:29:47 2026...
ALL TESTS PASSED
```

Actual output is retained locally in these ignored generated files:

- sim/logs/tb_clamp.run.log
- sim/logs/tb_clamp.xvlog.log
- sim/logs/tb_clamp.xelab.log
- sim/logs/tb_clamp.xsim.log

The runner was also exercised with temporary, deliberately invalid fixtures:

- No pass verdict: exit 1, rejected.
- FAILED: 1 followed by ALL TESTS PASSED: exit 1, rejected.
- SystemVerilog syntax error: exit 1 at xvlog, rejected.
- Missing source file: exit 1 before compilation, rejected.

The fixtures were written under the system temporary directory, not committed
as project testbenches. The observed guard-check summary is retained in
sim/logs/runner_guards.log; raw logs for the compiled fixtures are in sim/logs.
These are runner checks, not the design mutations reserved for step 7.

### Implementation decisions and tool findings

xvlog first rejected an implicit input net under default_nettype none
(VRFC 10-1103). The declaration now uses input wire logic signed [16:0].
This explicitly states the net kind and preserves the signed 17-bit port.

xelab then required a timescale on the design module because the testbench
has one (XSIM 43-4099). Both files now specify 1ns/1ps. This is a simulation
directive; it adds no hardware or latency.

No expected values or checks were changed to resolve either tool error.
Only xsim has been run; Icarus, Yosys, chip builds, and the board are unverified.
There are no unresolved questions for step 1. Troy independently reran the test,
reported ALL TESTS PASSED, and approved this step. The next planned block is the MAC unit.

## Step 1 review rerun (Nov 4, 2026)

Troy requested a fresh run before pushing rtl for review. The clamp section
above was checked and is present. The existing RTL, testbench, runner, and
expected values were unchanged. The following command exited with code 0
when run from C:\Users\petet\twinmac:

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_clamp -Sources @('src\clamp.sv', 'sim\tb_clamp.sv')
```

The last 10 lines of its console output were:

```text
# xsim {tb_clamp_sim} -autoloadwcfg -runall
Time resolution is 1 ps
run -all
Checked 131072 signed inputs (-65536 through 65535).
ALL TESTS PASSED
$finish called at time : 131072 ns : File "C:/Users/petet/TwinMac/sim/tb_clamp.sv" Line 56
exit
INFO: [Common 17-206] Exiting xsim at Wed Nov  4 18:40:59 2026...
Verification log: C:\Users\petet\twinmac\sim\logs\tb_clamp.run.log
ALL TESTS PASSED
```

AGENTS.md now requires input wire logic and a 1ns/1ps timescale in every
SystemVerilog design file, and schedules deletion of src/project.v in step 6.
The existing clamp already satisfies both coding rules. Step 2 has not started.

## Step 2: MAC unit

### What hardware this describes

src/mac_unit.sv describes one signed multiplier, an adder, a selector for the
adder's starting value, and a 17-bit accumulator register named acc.

The multiplier takes two signed 8-bit operands and produces a signed 16-bit
product. The product is sign-extended to 17 bits by copying its sign bit.
The signed 8-bit bias is also sign-extended to 17 bits by repeating its sign bit.
This preserves negative values when they enter the wider adder.

The product, extended values, and next_acc are combinational signals. They
describe wires and arithmetic, not stored values or extra pipeline stages.
The always_comb block calculates next_acc continuously:

- With first high, next_acc is bias plus product.
- With first low, next_acc is the existing acc plus product. Bias is ignored.

Only acc stores state. At each rising clock edge, en decides whether acc
takes next_acc. With en low, acc holds its value even if first, bias, or
the operands change. A low rst_n clears acc to zero immediately, without
waiting for a clock edge, and takes priority over en and first. Releasing
reset alone does not perform an accumulation.

For example, first=1, bias=7, and operands 2 and 3 load 13 at a rising edge.
A subsequent enabled edge with first=0 and operands -4 and 5 changes acc to
13 + (-20) = -7. A disabled edge leaves -7 stored.

There is no clamp in this block: negative and large sums remain available
for the later clamp step. There is one multiplier and no pipeline register
between it and acc. All input ports use input wire logic, and the file has
the required 1ns/1ps simulation timescale.

### Why the accumulator is 17 bits

The largest required two-product sum is 127 + 16384 + 16384 = 32895.
A signed 16-bit number stops at 32767, so it would wrap on this valid case.
A signed 17-bit register covers -65536 through 65535 and accommodates both
the high corner 32895 and the low corner -128 - 16256 - 16256 = -32640.

### How the test works

sim/tb_mac_unit.sv drives inputs on falling clock edges, then checks that acc
is unchanged before the next rising edge. After the rising edge, it allows
the register assignment to settle and checks the new value. The expected
accumulator is calculated from integer stimulus values and the previous
expected value, never from DUT output or internal signals. Case inequality
treats unknown output bits as mismatches.

Directed checks cover:

- Asynchronous reset between rising edges, reset priority with en and first
  asserted, reset with en low, enabled reset release, and resuming from zero.
- Holding acc with both values of first while inputs and bias change.
- first replacing an existing sum and accumulation ignoring the bias.
- Positive, negative, and zero products, including all specified product corners.
- Bias sign extension, product sign extension, and both accumulator extremes.

The random seed is 0x54574D32. Each of 1000 cases uses random signed bytes
for bias and operands, performs one first update and one accumulation, and
inserts two disabled cycles with changed inputs. Each case starts a new sum,
so the reference stays within the specified two-product neuron range.
This gives 2000 random enabled updates and 2000 random hold cycles.
A simulation watchdog rejects a run that exceeds 100000 ns.

### Actual verification

Tool: Vivado Simulator 2024.2. Run from C:\Users\petet\twinmac:

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_mac_unit -Sources @('src\mac_unit.sv', 'sim\tb_mac_unit.sv')
```

The initial run passed. After external review, apply_reset was strengthened
to leave en unchanged while rst_n rises and until the reset-release check
finishes. Only then is en cleared, before the next rising clock edge.
This checks that reset release alone cannot update acc even with en high.
MAC RTL, expected values, and the number of comparisons were unchanged.

The fresh xsim run exited with code 0: 1000 random cases and 8062 accumulator
checks completed with zero failures. The last 10 console output lines were:

```text
Accumulator high: expected=32895 actual=32895
Accumulator low: expected=-32640 actual=-32640
Random cases completed: 1000 (two updates and two holds each).
Accumulator checks completed: 8062; failures: 0.
ALL TESTS PASSED
$finish called at time : 40246 ns : File "C:/Users/petet/TwinMac/sim/tb_mac_unit.sv" Line 210
exit
INFO: [Common 17-206] Exiting xsim at Wed Nov  4 19:49:07 2026...
Verification log: C:\Users\petet\twinmac\sim\logs\tb_mac_unit.run.log
ALL TESTS PASSED
```

The raw and combined logs are retained locally as ignored generated files:

- sim/logs/tb_mac_unit.run.log
- sim/logs/tb_mac_unit.xvlog.log
- sim/logs/tb_mac_unit.xelab.log
- sim/logs/tb_mac_unit.xsim.log
- sim/logs/tb_mac_unit.console.log

### Decisions and review status

The testbench was written before the RTL. Expected values remain unchanged.
External review identified a gap: reset release was checked only with en low.
The test now preserves en through the release check and clears it afterward.
No existing check was removed or weakened. The simulation runner required no
changes. Signed extensions are explicit, and only acc is a register.
Random tests deliberately use two products per sum, matching the frozen core
schedule and avoiding unspecified longer accumulation sequences.

Only xsim was run locally for this step. The Icarus, Yosys, Verilator, and
mutation results supplied in the external review are reviewer-reported and
were not reproduced in this session. Vivado synthesis, timing, chip-flow builds,
and physical board operation remain unverified.

There are no open questions for step 2. The three files changed are
src/mac_unit.sv, sim/tb_mac_unit.sv, and docs/rtl_notes.md. Troy approved
step 2 for commit on Nov 4, 2026, after the reset-release test fix and passing
xsim rerun. Step 3 has not started.

## Step 3: Weight shift register

### What hardware this describes

src/weight_sr.sv describes 72 stored bits named weights. Its only clock is clk.
At a rising clock edge with load high, each old bit moves one position toward
bit 71, old bit 71 falls out, and sdi enters bit 0. At a rising edge with load
low, all 72 bits hold their previous values.

load is a clock enable, not a second clock. Changing load or sdi between
rising edges does not change the stored word. There is no combinational
arithmetic, no multiplier, no FSM, no bit counter, and no extra pipeline.
The concatenation in the clocked assignment describes the connections
between the stored bits and the serial input.

There is deliberately no reset port or initial value on the register.
Callers must load all 72 bits before the first computation; startup contents
must not be assumed. The register does not know whether the core is busy,
so its caller must also avoid shifting during computation.

The word contains raw bits. The core will interpret the nine byte slices
as signed values later; the shift register itself performs no signed math.

### Why most significant bit goes first

The first incoming bit starts in position 0. After the remaining 71 shifts
it reaches position 71. Sending bit 71 first and bit 0 last therefore
places the complete word in the required order after 72 enabled edges.

The test-only patterns have these expected final fields:

| Bits | Field | First pattern | Second pattern |
| --- | --- | --- | --- |
| 71:64 | b | A5 | 5A |
| 63:56 | c | 3C | C3 |
| 55:48 | a | 81 | 7E |
| 47:40 | b2 | FF | 00 |
| 39:32 | w22 | 12 | ED |
| 31:24 | w21 | 69 | 96 |
| 23:16 | b1 | 00 | FF |
| 15:8 | w12 | 7E | 81 |
| 7:0 | w11 | C3 | 3C |

These are diagnostic test words; the frozen gate presets are unchanged.
Each word has nine distinct bytes. The second word complements the first,
so every stored position is checked at both binary values.

### How the test works

sim/tb_weight_sr.sv first shifts 72 zero bits through the public ports.
Only after that does it compare the full word with zero. This establishes
a known state without assuming a hardware reset or assigning DUT internals.

For a subsequent word, the expected contents after k enabled shifts are:

```text
((starting_word << k) | (target_word >> (72 - k))) limited to 72 bits
```

The reference uses fixed stimulus words and the number of bits sent, never
DUT output. Paused cycles do not advance k. The final nine byte fields are
also compared independently with the literal values in the table above.
Case inequality catches unknown bits as failures.

The first diagnostic word is sent most significant bit first, with two
disabled cycles before each byte. Those pauses change sdi between 0 and 1.
The second word is sent with load held high for 72 consecutive rising edges
and replaces the first word without a zero flush between them.

Each normal cycle checks the old value after falling-edge input changes
and the expected value after the following rising edge. A separate check
pulses load high and low and changes sdi entirely while clk stays high,
verifying that neither signal acts as a clock or opens a transparent latch.
Additional disabled cycles verify that a stored nonzero word holds.

After the second word, an extra 1 bit must produce B5_86_FC_01_DB_2D_FF_02_79.
This expected constant comes from doubling the second word, adding 1, and
keeping 72 bits. It checks continued shifting beyond a complete word.
The module does not automatically stop or restart after 72 bits.

The run tracks 217 enabled rising edges: 72 zero-fill shifts, two 72-bit
diagnostic words, and one extra bit. It also tracks 31 disabled rising edges.
The 376 comparisons include both whole-word and individual-byte checks.
A watchdog rejects a simulation that exceeds 10000 ns.

### Actual verification

Tool: Vivado Simulator 2024.2. Run from C:\Users\petet\twinmac:

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_weight_sr -Sources @('src\weight_sr.sv', 'sim\tb_weight_sr.sv')
```

The first run exited with code 0. All 376 comparisons passed with zero
failures. The last 10 lines of the command's console output were:

```text
All nine byte fields checked for both patterns.
Extra-bit word: expected=b586fc01db2dff0279 actual=b586fc01db2dff0279
Tracked rising edges: 217 shifts, 31 holds.
Weight comparisons completed: 376; failures: 0.
ALL TESTS PASSED
$finish called at time : 2486 ns : File "C:/Users/petet/TwinMac/sim/tb_weight_sr.sv" Line 190
exit
INFO: [Common 17-206] Exiting xsim at Wed Nov  4 22:10:04 2026...
Verification log: C:\Users\petet\twinmac\sim\logs\tb_weight_sr.run.log
ALL TESTS PASSED
```

The actual raw and combined logs are retained locally as ignored files:

- sim/logs/tb_weight_sr.run.log
- sim/logs/tb_weight_sr.xvlog.log
- sim/logs/tb_weight_sr.xelab.log
- sim/logs/tb_weight_sr.xsim.log
- sim/logs/tb_weight_sr.console.log

### Decisions and review status

The testbench was written before the RTL. Expected values and checks were
unchanged after the test run. The existing runner required no changes.
All design inputs use input wire logic, and the required timescale is present.
No reset, framing, counter, busy guard, or extra clock was added.

Only xsim was run for step 3. No synthesis, timing, Icarus, Yosys, mutation,
gate-level, or board result is claimed.

The three changed files are src/weight_sr.sv, sim/tb_weight_sr.sv, and
docs/rtl_notes.md. There are no open questions. Troy approved step 3 on
Nov 4, 2026, and authorized its commit and push on rtl together with step 2.
Step 4 has not started.

## Step 4: Control FSM

### What hardware this describes

src/control_fsm.sv schedules the six compute operations. It has seven states:
IDLE and STEP1 through STEP6. A typed three-bit enum names those states.
The stored state and done flag are the only registers in this module.

The always_comb block calculates both next_state and the datapath controls.
All controls receive zero defaults, then the selected state sets the required
ones. Every branch assigns next_state, including a default that returns an
invalid state to IDLE. These assignments describe combinational decode logic
and do not add pipeline registers or latches.

The control table is:

| State | mac0_en | mac1_en | mac_first | operand_sel | hidden_en | output_en |
| --- | --- | --- | --- | --- | --- | --- |
| IDLE | 0 | 0 | 0 | 0 | 0 | 0 |
| STEP1 | 1 | 1 | 1 | 0 | 0 | 0 |
| STEP2 | 1 | 1 | 0 | 1 | 0 | 0 |
| STEP3 | 0 | 0 | 0 | 0 | 1 | 0 |
| STEP4 | 1 | 0 | 1 | 2 | 0 | 0 |
| STEP5 | 1 | 0 | 0 | 3 | 0 | 0 |
| STEP6 | 0 | 0 | 0 | 0 | 0 | 1 |

start affects next_state only while IDLE. During the six active states,
the FSM advances once per rising edge regardless of start. A start held
high through a run can begin another run when it is sampled in IDLE.

At each rising edge, the state register takes next_state. done takes the
comparison of the old state with STEP6. Nonblocking assignments use the
pre-edge state, so exiting STEP6 sets done while the new state becomes IDLE.
A low rst_n asynchronously clears the state to IDLE and done to zero.

### How the edge timing works

E0 is the rising edge that accepts start while IDLE. The control signals
after each edge prepare the operation sampled by the datapath at the next
edge:

| Edge | State after edge | done after edge | Meaning |
| --- | --- | --- | --- |
| E0 | STEP1 | 0 | Prepare the first bias-plus-product updates |
| E1 | STEP2 | 0 | Step 1 executes; prepare second products |
| E2 | STEP3 | 0 | Step 2 executes; prepare hidden-register loads |
| E3 | STEP4 | 0 | Hidden values load; prepare output bias and first product |
| E4 | STEP5 | 0 | Step 4 executes; prepare the second output product |
| E5 | STEP6 | 0 | Step 5 executes; prepare the output-register load |
| E6 | IDLE | 1 | Output loads; done rises for one clock cycle |
| E7 | STEP1 or IDLE | 0 | Accept a new start or continue waiting |

This step tests the control signals and their timing. The datapath will
be connected and verified in step 5; no arithmetic result is claimed here.
done is a registered pulse, not a separate state and not the combinational
decode of STEP6. Controls are all idle during the done-high cycle.

### How the test works

sim/tb_control_fsm.sv uses literal seven-bit control rows transcribed from
the specification. A separate expected done bit makes an eight-bit vector.
The expected sequence is supplied by the stimulus, never by DUT state or
hierarchical references. Case inequality treats unknown output bits as
failures. All seven control bits and done are compared together.

Inputs are driven on falling clock edges. The previous expected vector
is checked before the next rising edge, then the new vector is checked
after the rising edge has settled. This checks both clocked advancement
and the absence of an immediate control or done change when start changes.

Each ordinary run begins at E0 and checks all following edges through E6.
All 64 possible start patterns across E1 through E6 are exercised. Mask
bit 0 drives start at E1 and bit 5 at E6. The patterns include isolated
busy starts, no busy starts, and continuously asserted start.

Consecutive ordinary runs accept start at E7, immediately following the
previous completion. The test also checks done clearing with no new start
and continued idle behavior. A short start pulse entirely between clock
edges must not launch a run.

Reset is asserted between rising edges in each compute state, including
STEP6 before it could generate done. start stays high through two clock
edges under reset and through reset release. The release check expects
IDLE controls and done low until the next rising clock edge accepts start.
Each aborted run is followed by a complete run, checking that no stale
completion appears. Reset is also checked while done is already high.

The summary counts 64 ordinary runs, six reset-abort phases, and eight
reset sequences: initial reset, six compute-state interruptions, and a
reset during done. The 1096 checks each compare the full eight-bit vector.
A watchdog rejects a simulation that exceeds 20000 ns.

### Actual verification

Tool: Vivado Simulator 2024.2. Run from C:\Users\petet\twinmac:

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_control_fsm -Sources @('src\control_fsm.sv', 'sim\tb_control_fsm.sv')
```

The first run exited with code 0. All 1096 control-vector checks passed
with zero failures. The last 10 lines of console output were:

```text
Reset aborts checked in all six compute states, plus reset during done.
Reset release with start high waited for the next rising edge.
Runs: 64; reset-abort phases: 6; reset sequences: 8.
Control-vector checks completed: 1096; failures: 0.
ALL TESTS PASSED
$finish called at time : 5476 ns : File "C:/Users/petet/TwinMac/sim/tb_control_fsm.sv" Line 219
exit
INFO: [Common 17-206] Exiting xsim at Wed Nov  4 22:24:55 2026...
Verification log: C:\Users\petet\twinmac\sim\logs\tb_control_fsm.run.log
ALL TESTS PASSED
```

The actual raw and combined logs are retained locally as ignored files:

- sim/logs/tb_control_fsm.run.log
- sim/logs/tb_control_fsm.xvlog.log
- sim/logs/tb_control_fsm.xelab.log
- sim/logs/tb_control_fsm.xsim.log
- sim/logs/tb_control_fsm.console.log

### Decisions and review status

The testbench was written before the RTL. Expected rows and checks were
unchanged after the first test run. The existing runner required no changes.
Combinational controls share the next-state block, with explicit defaults
and a unique case. State and done share one asynchronously reset clocked
block. No extra state, busy port, clock, or pipeline was introduced.

Only xsim was run for step 4. No synthesis, timing, Icarus, Yosys, mutation,
gate-level, or board result is claimed. Invalid-state recovery is present
in RTL but was not tested by forcing internal state.

Step 3 was committed as 4489ce1, then rtl was pushed and verified on GitHub
at that commit, including step 2 commit fec9360. Local and remote main
remained at 162764db71c8e561e3e8b9399a30a42f3c584fcd.

The three step 4 changes are src/control_fsm.sv, sim/tb_control_fsm.sv, and
docs/rtl_notes.md. There are no open questions. Troy approved step 4 on
Nov 4, 2026, and authorized its commit and push on rtl. Step 5 has not started.

## Step 5: TwinMAC core

### What hardware this describes

src/twinmac_core.sv connects the four previously verified module types:
one weight_sr, one control_fsm, two mac_unit instances, and two clamps.
It adds the hidden registers h1 and h2 and the output register y.
All instances use the same rising-edge clk.

The nine weight bytes are continuously decoded as signed 8-bit values.
These assignments are wires, not additional registers. A combinational
four-way operand selector routes x1, x2, h1, or h2 to MAC 0 and chooses
the corresponding weight and bias. MAC 1 computes only the hidden-neuron
pass. Its enable stays low during the output-neuron pass, so acc1 holds.

| operand_sel | MAC 0 operands | MAC 0 bias | MAC 1 operands | MAC 1 bias |
| --- | --- | --- | --- | --- |
| 0 | x1, w11 | b1 | x1, w21 | b2 |
| 1 | x2, w12 | b1 | x2, w22 | b2 |
| 2 | zero-extended h1, a | b | unused, driven zero | b2 |
| 3 | zero-extended h2, c | b | unused, driven zero | b2 |

h1 and h2 are unsigned seven-bit values. Adding a leading zero creates
an eight-bit signed multiplier operand in the range 0 through 127.
Sign-extending a value such as 64 would instead produce -64, which is wrong.

acc0 always feeds clamp0, and acc1 always feeds clamp1. At hidden_en,
the two clamped values load h1 and h2. At output_en, clamp0 loads y.
This reuses MAC 0 and its clamp for the output neuron and uses exactly
two multipliers and two clamp instances. There is no added pipeline.

The core's new registers are h1, h2, and y. The instantiated modules own
the accumulator, FSM, done, and weight registers. rst_n asynchronously
clears both accumulators, h1, h2, y, FSM state, and done. The weight shift
register deliberately has no reset, so reset preserves loaded weights.

x1 and x2 are not latched by this core: the caller holds them stable for
the run. The caller also loads all 72 weight bits before starting and
does not shift weights during computation. Input latches and external-pin
synchronizers belong to the chip wrapper in step 6.

### What happens on the six compute edges

E0 accepts start and prepares STEP1 controls. Existing y holds until E6.

| Edge | Registers updated | Integer operation |
| --- | --- | --- |
| E1 | acc0, acc1 | b1 + x1*w11; b2 + x1*w21 |
| E2 | acc0, acc1 | add x2*w12; add x2*w22 |
| E3 | h1, h2 | clamp the complete hidden sums to 0 through 127 |
| E4 | acc0 | b + h1*a |
| E5 | acc0 | add h2*c; acc1 continues holding |
| E6 | y, done | clamp acc0 into y; done rises and FSM becomes idle |

done clears on the next rising edge. A start at E7 begins the next run.
Nonblocking assignments let the output register and done flag update
together on E6 using the controls and sums established before that edge.

### How the test works

sim/tb_twinmac_core.sv uses independent 32-bit integer arithmetic for the
three-neuron formula. Raw weight bytes become signed integers by subtracting
256 when their unsigned value is at least 128. Each full sum is limited
to 0 through 127, with no rounding.

The testbench retains expected accumulators, hidden values, y, and done.
It updates those references according to the specification's edge table.
At each check it compares a 56-bit vector containing both 17-bit accumulators,
both seven-bit hidden registers, seven-bit y, and done. Case inequality
detects unknown bits. Hierarchical reads of dut.acc0, dut.acc1, dut.h1,
and dut.h2 observe actual values only; no expected value comes from the DUT.
These hierarchical references are confined to the testbench.

Every run checks the old vector before E0, the held values after E0,
and the pre-edge and post-edge vectors for E1 through E6. This verifies
intermediate arithmetic, register holding, exact done timing, and y holding
until completion. Weight loading also checks that arithmetic registers hold.

The six frozen gate presets are each loaded once and run on all four
binary input pairs. Their expected outputs are literal truth-table bits.
Consecutive cases reuse weights and accept the next start at E7.

Eight directed corners follow:

| Case | x1 | x2 | Expected y |
| --- | --- | --- | --- |
| Required accumulator high | -128 | -128 | 127 |
| MAC 1 accumulator high | -128 | -128 | 127 |
| Required accumulator low | -128 | -128 | 5 |
| Required second-pass saturation | 127 | 127 | 127 |
| Hidden h1=64 passed with weight 1 | 0 | 0 | 64 |
| Hidden h2=64 passed with weight 1 | 0 | 0 | 64 |
| Distinct w11=2 and w12=3 | 5 | 7 | 31 |
| Negative input and negative weight | -4 | 2 | 24 |

The high-corner vectors check acc0=32895 and acc1=32895 at E2 before clamping.
The two hidden-value vectors explicitly expose incorrect sign extension.
The asymmetric hidden weights expose swapping w11 and w12.

The seed is 0x54574D35. All 10000 random cases use nine random weight bytes
and two random signed input bytes. Their expected y comes from integer math.
Busy-start masks cycle through all 64 patterns; busy starts must not change
the six-step schedule or its intermediate results.

Reset tests interrupt runs after E0 through E5, covering every compute state.
A completed XNOR result of 1 is seeded before each interruption. Reset must
clear every observed register before the next rising edge. start stays high
through reset release, which must not update data registers by itself.
The next rising edge accepts start, then a full six-edge run completes.
Reset is also asserted with done high, followed by another computation
without reloading weights. Three idle cycles check result holding and done
clearing without a new start.

The 10045 completed results comprise 24 gate cases, eight corners, 10000
random cases, six reset-test seed runs, six runs restarted after reset,
and one final computation using weights retained across reset.
There are eight reset sequences including initial reset. The simulation
watchdog is 10000000 ns; the successful run finished at 7914296 ns.

### Actual verification

Tool: Vivado Simulator 2024.2. Run from C:\Users\petet\twinmac:

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_twinmac_core -Sources @('src\clamp.sv', 'src\mac_unit.sv', 'src\weight_sr.sv', 'src\control_fsm.sv', 'src\twinmac_core.sv', 'sim\tb_twinmac_core.sv')
```

The rerun after adding the MAC 1 high corner exited with code 0. All 1582858
core-state checks passed with zero failures. The last 10 console lines were:

```text
Random cases completed: 10000; all 64 busy-start masks exercised.
Reset aborts: six phases; all registers cleared; weights retained.
Completed results: 10045; reset sequences: 8.
Core-state checks completed: 1582858; failures: 0.
ALL TESTS PASSED
$finish called at time : 7914296 ns : File "C:/Users/petet/TwinMac/sim/tb_twinmac_core.sv" Line 312
exit
INFO: [Common 17-206] Exiting xsim at Wed Nov  4 23:06:26 2026...
Verification log: C:\Users\petet\twinmac\sim\logs\tb_twinmac_core.run.log
ALL TESTS PASSED
```

The actual raw and combined logs are retained locally as ignored files:

- sim/logs/tb_twinmac_core.run.log
- sim/logs/tb_twinmac_core.xvlog.log
- sim/logs/tb_twinmac_core.xelab.log
- sim/logs/tb_twinmac_core.xsim.log
- sim/logs/tb_twinmac_core.console.log

### Decisions and review status

The testbench was written before the RTL. Review added a mirrored MAC 1
high-accumulator case; all existing expected values and checks are unchanged.
The four earlier module files, core RTL, and runner are
unchanged. Operand selection is combinational; h1, h2, and y are the only
new core registers. The weights remain unreset, with no loading guard.

Only xsim was run locally for step 5. No synthesis, timing, Icarus, Yosys,
mutation, gate-level, chip-pin, or physical board result is claimed.
The reviewer's earlier throwaway integration is separate from this core.

Step 4 was committed and pushed as 6027a6d. Local and remote main remained
at 162764db71c8e561e3e8b9399a30a42f3c584fcd.

The step 5 changes are src/twinmac_core.sv, sim/tb_twinmac_core.sv, and
docs/rtl_notes.md. There are no open questions. Troy authorized commit and
push after the added MAC 1 corner passed with the exact requested totals.
Step 6 has not started.

## Step 6: Tiny Tapeout chip wrapper

### What hardware this describes

src/tt_um_troypeters42_twinmac.sv connects the verified core to the Tiny
Tapeout pins. The core still has two MACs, two clamps, and one clock.
sck is an input strobe, never a clock inside the design.

Two reset flip-flops assert asynchronously when rst_n goes low and release
the internal reset after two rising clock edges. All other resettable
registers use that internal reset. Reset clears the input registers, core
state, result, and done flag. The 72-bit weight register retains its value;
all weights must be loaded before the first computation.

Each of sck, start, lat_x1, and lat_x2 passes through two synchronizing
flip-flops. A third register remembers the previous synchronized value;
the combinational expression current AND NOT previous makes a one-cycle
rising-edge pulse. Serial data sdi has its own two synchronizing registers.
ASYNC_REG attributes identify the synchronizer stages for implementation
tools; simulation does not model analog metastability.

Two signed 8-bit input registers capture ui_in on the corresponding latch
pulse. The core receives those stored bytes, not the live data bus.
The sticky done register clears on reset and every synchronized start
pulse, including starts the busy core ignores. A start has priority over
setting the flag. Otherwise the core's completion pulse sets it.

Nonblocking assignments make the flag see the preceding core_done value:
y becomes valid on core edge E6 and the flag sets on E7. The result is
already valid when the flag rises. That flag stays high until another
start or reset. The core's E0 through E7 schedule is unchanged.

The edge detectors and output wiring are combinational. The reset stages,
synchronizers, previous-control values, latched input bytes, and done flag
are registers. uo_out is the flag followed by the seven-bit result.
uio_out and uio_oe are always zero. ena and uio_in[7:5] are unused.

### Pin timing and verification

Both testbenches drive the chip pins using the specified protocol. They
keep sdi and ui_in stable for at least five clock cycles before and after
their related control rising edge. Every control high and low lasts at
least five cycles. They never shift weights or latch new inputs during a
computation. test/test.py observes only chip pins. sim/tb_twinmac.sv also
reads internal wrapper stages for the exact-latency checks described below.

sim/tb_twinmac.sv uses a 20 ns clock. test/test.py uses the same protocol
with a slow 1000 ns functional clock so UNIT_DELAY gate models can settle.
That gate-level test is a functional check, not a 50 MHz timing measurement;
the physical flow must establish timing separately.

Both tests use the 24 literal golden truth-table outputs, eight directed
corners, and two computations after reset: test/test.py keeps 34 completed
results. sim/tb_twinmac.sv adds one result during the latency checks, for
35 completed results.
The corners include both +32895 accumulators, the negative accumulator
corner, second-pass saturation, both hidden values at 64, unequal input
weights, and signed inputs.

Checks explicitly require the old done flag to clear before completion,
the new flag to remain set, and both UIO output buses to stay zero. Changing
ui_in after latching proves that the input registers hold their bytes.
ena alternates during weight loading as well as gate cases without
changing the result. Reset is checked between
clock edges, with retained weights and cleared input bytes. An in-flight
reset must cancel the run without producing a stale completion flag.
Unknown output bits fail comparisons or integer conversion.

Review added exact-latency checks to sim/tb_twinmac.sv. Internal reads check
that reset remains asserted after one edge and releases after two; the
control first stage samples its pin on the third edge after reset release.
Serial data must reach the core after two edges. A rising start pin
produces a one-cycle core pulse after edge 2, is accepted on edge 3 (E0),
clears the flag on edge 3, and sets it on edge 10, one edge after the
result becomes valid. These reads observe actual signals only; expected
values remain literal checks from the specified timing.

### Actual local verification

Tool: Vivado Simulator 2024.2. Run from C:\Users\petet\twinmac:

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_twinmac -Sources @('src\clamp.sv','src\mac_unit.sv','src\weight_sr.sv','src\control_fsm.sv','src\twinmac_core.sv','src\tt_um_troypeters42_twinmac.sv','sim\tb_twinmac.sv')
```

The review rerun exited with code 0. There were 35 completed chip-pin results,
18056 checks, and zero failures. The last 10 command-output lines were:

```text
Reset, retained weights, zeroed inputs, and aborted run checked.
Exact wrapper latency checked.
Completed chip-pin results: 35.
Chip-pin checks completed: 18056; failures: 0.
ALL TESTS PASSED
$finish called at time : 337111 ns : File "C:/Users/petet/TwinMac/sim/tb_twinmac.sv" Line 281
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 00:07:42 2026...
Verification log: C:\Users\petet\twinmac\sim\logs\tb_twinmac.run.log
ALL TESTS PASSED
```

The complete vendor and combined logs remain local, ignored generated files:

- sim/logs/tb_twinmac.run.log
- sim/logs/tb_twinmac.xvlog.log
- sim/logs/tb_twinmac.xelab.log
- sim/logs/tb_twinmac.xsim.log
- sim/logs/tb_twinmac.console.log

Python AST parsing also accepted test/test.py. The GitHub test and gl_test
jobs run that same cocotb test against RTL and the generated gate netlist.
Actual GitHub job results and run links are supplied in the review packet
for this commit; local xsim alone does not establish their success.

### Integration files and review status

info.yaml keeps the original title, author, and description. It selects
SystemVerilog, the frozen six-source top, a 1x2 tile, and 50 MHz. Pin names
describe the implemented interface. test/Makefile lists those six sources,
test/tb.v instantiates the real top with optional gate-level power pins,
and test/test.py replaces the template adder test. docs/info.md explains
the hardware, pins, and host procedure. src/project.v is deleted.

The earlier design modules, sim/run_xsim.ps1, .github/workflows/, and
src/config.json are unchanged. No FPGA or physical board result is claimed.

Troy explicitly authorized committing and pushing step 6 to rtl after
chip-pin xsim passes, so the required GitHub jobs can run before review.
This is the step 6 exception to the usual pre-commit review checkpoint.
Step 7 has not started. No merge or push to main is authorized.

## Step 7: Required mutation tests

### What this checks

Mutation testing deliberately breaks one feature on a temporary copy and
checks whether an existing test notices. A caught mutation confirms that
the test can distinguish the intended behavior from that particular bug.
It does not prove every possible bug is covered.

This step adds no hardware. The clamp remains combinational; each MAC
retains a signed 17-bit accumulator register. Weight storage, the control
state register, hidden/output registers, and wrapper synchronizers keep
their existing behavior. The production RTL and tests are unchanged from
b4fcc704d34361fdf102bca7fa9e289b9938c253.

### Method and passing baselines

Tool: Vivado xsim 2024.2. Each mutation used a fresh copy of the six design
files, the required testbenches, and the unchanged sim/run_xsim.ps1.
The retained local workspace is:

```text
C:\Users\petet\AppData\Local\Temp\TwinMAC-Step7-1d647272
```

The baseline and seven mutation folders are independent. The core
testbench copies contain three additional diagnostic $display messages:
after the MAC 0 accumulator-high corner, before random cases, and after
random cases. They print the existing failure counter. They add no checks,
change no expected values, and consume no simulation time or random values.
The same diagnostic messages are present in the passing baseline copy.

All four baseline runs exited 0 and printed ALL TESTS PASSED:

| Testbench | Actual passing coverage |
| --- | --- |
| tb_clamp | 131072 signed inputs |
| tb_mac_unit | 8062 accumulator checks; zero failures |
| tb_twinmac_core | 10045 results; 1582858 checks; zero failures |
| tb_twinmac | 35 results; 18056 checks; zero failures |

Every mutated run compiled, elaborated, and reached a numeric testbench
FAILED verdict. The runner exited 1 for all ten mutation/test combinations.
Compiler errors, elaboration errors, and watchdog timeouts did not count
as detected mutations.

### Mutation results

| Temporary folder | Deliberate source change | Required test and actual verdict |
| --- | --- | --- |
| upper_clamp | Remove the value > 127 branch in clamp.sv | tb_clamp: FAILED: 64897; core: FAILED: 1185440 |
| lower_clamp | Remove the value < 0 branch in clamp.sv | tb_clamp: FAILED: 65024; core: FAILED: 1378482 |
| accumulator_16 | Change mac_unit.acc from signed [16:0] to signed [15:0]; leave the adder and core wires unchanged | core: FAILED: 324 |
| swap_w11_w12 | Read w11 from weights[15:8] and w12 from weights[7:0] | core: FAILED: 840668 |
| unsigned_multiply | Cast both operands with $unsigned before multiplication | tb_mac_unit: FAILED: 6788; core: FAILED: 1567310 |
| sign_extend_h1 | Replace {1'b0, h1} with {h1[6], h1} in the second-pass operand | core: FAILED: 769964 |
| sticky_start | Replace the start-branch flag clear with done_flag <= done_flag; retain reset | tb_twinmac: FAILED: 34 |

The 16-bit mutation first fails after the golden gate cases, during the
required MAC 0 high corner. There are 9 failures by that corner's checkpoint.
All 324 failures occur before random testing; random testing adds none.
The directed overflow checks remain essential.

Swapping w11/w12 adds 840499 failures during the random phase
(840668 minus 169). Sign-extending h1 adds 769325 random-phase failures
(769807 minus 482). The unsigned-multiplier mutation adds 1566004
random-phase core failures (1567043 minus 1039).

### Exact commands

Run these commands from the relevant baseline or mutation folder under
the retained workspace. The table above identifies which tests each
mutation requires. All four commands also ran on the baseline.

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_clamp -Sources @('src\clamp.sv','sim\tb_clamp.sv')
```

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_mac_unit -Sources @('src\mac_unit.sv','sim\tb_mac_unit.sv')
```

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_twinmac_core -Sources @('src\clamp.sv','src\mac_unit.sv','src\weight_sr.sv','src\control_fsm.sv','src\twinmac_core.sv','sim\tb_twinmac_core.sv')
```

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_twinmac -Sources @('src\clamp.sv','src\mac_unit.sv','src\weight_sr.sv','src\control_fsm.sv','src\twinmac_core.sv','src\tt_um_troypeters42_twinmac.sv','sim\tb_twinmac.sv')
```

### Actual failing-output excerpts

These excerpts retain the first two mismatch messages, phase checkpoints
where present, and final counters/verdict in their original order.
Every run below returned runner exit code 1.

upper_clamp / tb_clamp

```text
Mismatch: value=128 expected=127 actual=0
Mismatch: value=129 expected=127 actual=1
Checked 131072 signed inputs (-65536 through 65535).
FAILED: 64897
```

upper_clamp / tb_twinmac_core

```text
MUTATION CHECKPOINT: after MAC0 high corner; failures=0
Mismatch (after compute edge) at 9156000: expected=3f4080003f800a actual=3f40800000800a
Mismatch (before compute edge) at 9161000: expected=3f4080003f800a actual=3f40800000800a
MUTATION CHECKPOINT: before random cases; failures=164
MUTATION CHECKPOINT: after random cases; failures=1185289
Completed results: 10045; reset sequences: 8.
Core-state checks completed: 1582858; failures: 1185440.
FAILED: 1185440
```

lower_clamp / tb_clamp

```text
Mismatch: value=-65535 expected=0 actual=1
Mismatch: value=-65534 expected=0 actual=2
Checked 131072 signed inputs (-65536 through 65535).
FAILED: 65024
```

lower_clamp / tb_twinmac_core

```text
Mismatch (after compute edge) at 786000: expected=00007fffc00000 actual=00007fffc07f00
Mismatch (before compute edge) at 791000: expected=00007fffc00000 actual=00007fffc07f00
MUTATION CHECKPOINT: after MAC0 high corner; failures=120
MUTATION CHECKPOINT: before random cases; failures=120
MUTATION CHECKPOINT: after random cases; failures=1378247
Completed results: 10045; reset sequences: 8.
Core-state checks completed: 1582858; failures: 1378482.
FAILED: 1378482
```

accumulator_16 / tb_twinmac_core

```text
Mismatch (after compute edge) at 6776000: expected=403f8000010102 actual=c03f8000010102
Mismatch (before compute edge) at 6781000: expected=403f8000010102 actual=c03f8000010102
MUTATION CHECKPOINT: after MAC0 high corner; failures=9
MUTATION CHECKPOINT: before random cases; failures=324
MUTATION CHECKPOINT: after random cases; failures=324
Completed results: 10045; reset sequences: 8.
Core-state checks completed: 1582858; failures: 324.
FAILED: 324
```

swap_w11_w12 / tb_twinmac_core

```text
MUTATION CHECKPOINT: after MAC0 high corner; failures=0
Mismatch (after compute edge) at 11506000: expected=00050000004080 actual=00078000004080
Mismatch (before compute edge) at 11511000: expected=00050000004080 actual=00078000004080
MUTATION CHECKPOINT: before random cases; failures=169
MUTATION CHECKPOINT: after random cases; failures=840668
Completed results: 10045; reset sequences: 8.
Core-state checks completed: 1582858; failures: 840668.
FAILED: 840668
```

unsigned_multiply / tb_mac_unit

```text
Mismatch (after rising edge): expected=-16256 actual=16256 at 56000
Mismatch (127 times -128): expected=-16256 actual=16256 at 56000
Accumulator checks completed: 8062; failures: 6788.
FAILED: 6788
```

unsigned_multiply / tb_twinmac_core

```text
Mismatch (after compute edge) at 2016000: expected=00008000410102 actual=00808000410102
Mismatch (before compute edge) at 2021000: expected=00008000410102 actual=00808000410102
MUTATION CHECKPOINT: after MAC0 high corner; failures=860
MUTATION CHECKPOINT: before random cases; failures=1039
MUTATION CHECKPOINT: after random cases; failures=1567043
Completed results: 10045; reset sequences: 8.
Core-state checks completed: 1582858; failures: 1567310.
FAILED: 1567310
```

sign_extend_h1 / tb_twinmac_core

```text
Mismatch (after compute edge) at 6796000: expected=003f80003f8002 actual=ffff80003f8002
Mismatch (before compute edge) at 6801000: expected=003f80003f8002 actual=ffff80003f8002
MUTATION CHECKPOINT: after MAC0 high corner; failures=5
MUTATION CHECKPOINT: before random cases; failures=482
MUTATION CHECKPOINT: after random cases; failures=769807
Completed results: 10045; reset sequences: 8.
Core-state checks completed: 1582858; failures: 769964.
FAILED: 769964
```

sticky_start / tb_twinmac

```text
Mismatch (start clears flag before result completes): expected=00 actual=80 at 23611000
Mismatch (start clears flag before result completes): expected=00 actual=80 at 24611000
Completed chip-pin results: 35.
Chip-pin checks completed: 18056; failures: 34.
FAILED: 34
```

The complete vendor logs, combined run logs, and console output remain in
each folder's sim/logs directory. manifest.json records the exact changed
source text and source lists; summary.json contains the concise results.
SHA-256 checks confirm every production source, testbench, and runner still
matches the baseline. The mutation step changes only this notes section.

### Original step 6 chip-build evidence and timing finding

The requested screenshots are authentic captures of the original GDS run,
41968284611 at e3ef3e8. Its gds, precheck, gl_test, and viewer jobs are green.
The separate RTL test run is 41968284500. The GitHub Summary page does not
publish area or timing numbers; those come from its GDS_logs artifact,
ID 13388732507. Local evidence is retained under:

```text
C:\Users\petet\AppData\Local\Temp\TwinMAC-Step7-Review\original-GDS-logs\runs\wokwi
```

The original run's final/metrics.json and post-route summary report:

| Measurement | Actual value |
| --- | --- |
| Die dimensions | 161.000 by 225.760 um |
| Die area | 36347.4 um^2 |
| Reported standard-cell area (design__instance__area__stdcell) | 20868.8 um^2 |
| Standard-cell utilization | 60.9212% |
| Configured clock period | 20 ns (50 MHz) |
| Setup slack, nom_tt_025C_1v80 | +9.0447 ns |
| Worst setup slack, max_ss_100C_1v60 | -1.6856 ns |
| Setup violations at max_ss_100C_1v60 | 5 |
| Worst hold slack, min_ff_n40C_1v95 | +0.1138 ns |
| Hold violations across reported corners | 0 |
| Max-slew violations at max_ss_100C_1v60 | 364 |

The die dimensions are also explicit in final/def: units are 1000 database
units per micron, with DIEAREA (0,0) to (161000,225760).

This is a real register-to-register setup failure at the required slow
corner. The first worst-corner path starts at _2554_, the controller state
register, and ends at _2446_. The report's final lines are:

```text
                                             20.665323   data required time
                                            -22.350903   data arrival time
---------------------------------------------------------------------------------------------
                                             -1.685580   slack (VIOLATED)
```

The resolved 68-checker-setupviolations/config.json explains why a green
job did not prove slow-corner signoff:

```json
{
  "CLOCK_PERIOD": 20,
  "TIMING_VIOLATION_CORNERS": ["*tt*"],
  "SETUP_VIOLATION_CORNERS": null
}
```

The checker selects typical-process corners; the slow ss corner has
negative setup slack in the detailed reports. No clock period, density,
RTL, workflow, or timing exception was changed while gathering this evidence.

This is an initial chip-build measurement, not final project signoff.
AGENTS.md requires stopping and asking Troy when LibreLane timing fails.
Troy approved step 7 on Nov 5 and authorized up to four configuration
experiments on a separate timing-test branch. The experiments preserve RTL,
tests, CLOCK_PERIOD, and PL_TARGET_DENSITY_PCT. Step 8 has not started.

## ASIC timing adoption: setup margin and strict corner checks

### Approved configuration and hardware

Troy approved Experiment A on Nov 5. src/config.json now adds these two
settings above the template's protected section:

```json
"PL_RESIZER_SETUP_SLACK_MARGIN": 2,
"SETUP_VIOLATION_CORNERS": ["*"],
```

RTL, tests, the 20 ns clock period, 60% placement density, and tile size
are unchanged. These settings change physical optimization and verification,
not the specified hardware behavior or its registers and combinational
arithmetic. AGENTS.md records approval for these two configuration lines;
clock period and density changes still require Troy's approval.

### Baseline versus Experiment A

The original physical build is e3ef3e8, GDS run 41968284611.
Experiment A is 755cb27, GDS run 41975075383. A passed gds, precheck, and
gl_test. All nine reported setup and hold slacks were positive.

| Build | RC at ss_100C_1v60 | Setup slack (ns) | Setup WNS (ns) | Setup TNS (ns) |
| --- | --- | ---: | ---: | ---: |
| Original | min | -1.123484 | -1.123484 | -1.562258 |
| Original | nom | -1.387971 | -1.387971 | -2.384322 |
| Original | max | -1.685580 | -1.685580 | -3.594391 |
| A | min | 1.334934 | 0.000000 | 0.000000 |
| A | nom | 1.144626 | 0.000000 | 0.000000 |
| A | max | 0.932191 | 0.000000 | 0.000000 |

| Build | Worst hold slack (ns) | Cell area (um^2) | Utilization | Max-slew count |
| --- | ---: | ---: | ---: | ---: |
| Original | 0.113818 | 20868.8 | 60.9212% | 364 |
| A | 0.115010 | 20835.0 | 60.8226% | 303 |

Cell area is design__instance__area__stdcell in final/metrics.json.
The original setup-repair log improved WNS from -1.755 ns to +0.094 ns.
Hold repair, placement legalization, routing, and extraction followed;
the final worst slow-corner slack was -1.685580 ns. That is about 1.78 ns
less than the repair log's final setup value. The 2 ns target leaves
headroom for these later physical changes. Experiment A's final worst
setup slack is +0.932191 ns, with worst hold slack +0.115010 ns.

The repair log loaded all nine RC/process corners. The original green
job gated setup on typical-process corners; it did not establish the
required slow-corner result.

### Deliberately failing strict-gate test

On timing-test, commit 4d7791d removed the setup-margin override and added
only SETUP_VIOLATION_CORNERS = ["*"]. GDS run 41977246898 failed in the
setup checker. Its dependent precheck, gl_test, and viewer jobs were skipped.
The resolved checker configuration retained TIMING_VIOLATION_CORNERS =
["*tt*"] while SETUP_VIOLATION_CORNERS was ["*"], proving the explicit
setup override takes effect.

The actual terminal error names all three failing slow corners:

```text
Setup violations found in the following
corners:
* max_ss_100C_1v60
* min_ss_100C_1v60
* nom_ss_100C_1v60
ERROR LibreLane will now quit.
Process completed with exit code 1.
```

This is a deliberate timing-gate failure, not a source or compilation
failure. The complete timestamped log is retained locally under
TwinMAC-Adoption-Review/GateProof/gds-job.log in the Windows temp directory.
The subsequent rtl commit must pass all six GitHub jobs and have no
negative setup or hold corner; its actual results are supplied with the
next review packet.

### Open max-slew limitation

Experiment A reports 303 max-slew pin violations. Troy accepted this as
an open limitation rather than a reason to reject the approved timing
fix. The table below lists the ten worst distinct nets. Cell pins were
mapped to nets using the final netlist, then each net's worst transition
slack was selected across all nine corners. All ten worst cases occur
at max_ss_100C_1v60; their limit is 0.750000 ns.

| Net | Worst reported pin | Actual slew (ns) | Slew slack (ns) |
| --- | --- | ---: | ---: |
| net50 | _1738_/B | 1.198577 | -0.448577 |
| net55 | _1387_/C1 | 1.182288 | -0.432288 |
| net62 | _1795_/S | 1.142756 | -0.392756 |
| net121 | _2448_/RESET_B | 1.032720 | -0.282720 |
| net53 | _1432_/C1 | 1.008841 | -0.258841 |
| net98 | _2025_/S | 0.995794 | -0.245794 |
| net101 | _1274_/S | 0.991278 | -0.241278 |
| net107 | _2439_/RESET_B | 0.978448 | -0.228448 |
| net46 | _2032_/B | 0.960684 | -0.210684 |
| net79 | _2366_/S | 0.935729 | -0.185729 |

These are transition checks, separate from setup/hold WNS. No RTL,
timing exception, extra pipeline, clock change, or density change was
introduced to address them.

### DRC scope and status

KLayout DRC remains disabled in the LibreLane build by the template's
RUN_KLAYOUT_DRC = 0 setting. The build reports zero detailed-route DRC,
Magic DRC, LVS errors, and antenna-violating nets/pins. Tiny Tapeout
precheck runs its own Magic DRC and KLayout checks. Experiment A's actual
precheck log includes Magic DRC plus KLayout FEOL, BEOL, off-grid, pin-label,
zero-area, and nwell/urpm checks, and ends with Precheck passed.

The next step is the Nexys Video demonstration only after the adopted
rtl configuration's GitHub jobs and all timing corners pass. Step 9 is
not authorized. Physical board operation still requires Troy's report.

## Step 8: Nexys Video demonstration

### ASIC prerequisite and scope

The adopted rtl commit is f71810b. Its test, docs, gds, precheck, gl_test,
and viewer jobs all passed. All nine ASIC setup WNS and hold WNS values
are zero; actual worst slacks are positive. The all-corner setup gate was
proved by the deliberately failing timing-test commit 4d7791d before adoption.
The ASIC max-slew count remains 303, recorded as an open limitation above.

The new files are fpga/nexys_top.sv, fpga/twinmac.xdc, fpga/build.tcl,
and sim/tb_nexys_top.sv. Existing ASIC RTL, tests, and configuration are
unchanged by this step. The FPGA uses the same chip wrapper as the ASIC.
Status: **board test pending**. Troy approved the design and supplement.
This step records the local simulation/implementation result and the
approved review changes; physical board observations are still required.
Optional step 9 is skipped for now; step 10 records the existing ASIC run.

### Hardware and clock-edge behavior

nexys_top adds a host controller around the real chip pin interface.
clk is the only clock. sck is a strobe made from state decoding; it does
not clock any register. The board's CPU RESET connects directly to the
chip's active-low reset. The host has its own two-register asynchronous
assert/synchronized release circuit. Five switch inputs each have two
synchronizing registers.

The host state register, phase counter, selected gate, valid flag, serial
bit index, preset word, and input data byte store state. The next-state
logic, preset selection function, pin decoding, and LED wiring are
combinational. Synthesis can trim constant bits or recode the FSM.

The typed FSM waits after reset, then compares synchronized SW[4:2]
against the gate whose weights are loaded. It captures one complete
72-bit preset and sends bits 71 down to 0. LOAD_SETUP, LOAD_HIGH, and
LOAD_LOW each last five clock cycles. At 100 MHz, that is 50 ns per
phase and 150 ns per bit. All 72 bits are sent before a computation starts.

A gate change during loading finishes the current complete word, then
reloads the latest selection before starting. A gate change during a run
waits for completion before any loading. Thus weights never shift during
a run. At each idle boundary, a different synchronized select code triggers
a full reload. This includes transitions between 110 and 111, whose
presets both implement AND.

For each computation, the host captures SW0 as the integer byte x1,
waits five cycles, pulses lat_x1 high and low for five cycles each, then
does the same for SW1/x2. It pulses start high and low for five cycles
each and waits for the sticky done flag before repeating. The data byte
is registered, so changing the switches cannot break the pin setup/hold
rule or change the chip's latched inputs during a run.

led[6:0] is wired to y and led[7] to the done flag. OLED VDD/VBAT controls
stay high; OLED reset, DC, clock, and data stay low. BTNC is unused until
the optional OLED step. No older OLED source is included.

### Test independence and coverage

The testbench was written before the new RTL. It uses literal frozen
weight presets and truth tables, not values read from the design.
It reconstructs serial words and input bytes from the generated chip pins,
checks every completed computation, and separately checks that the desired
switch settings eventually produce a new matching computation.

All 32 combinations of eight select codes and four input pairs pass.
Input-byte matching also catches a swapped SW0/SW1 mapping, even though
the six Boolean gates are commutative. Each select-code change must load
a new complete preset, including the two AND aliases.

The monitor checks five-cycle data setup/hold and control high/low widths,
complete MSB-first presets, no shifting or input latching during a run,
explicit done-flag clearing, zero UIO drivers, known outputs, and OLED-off
levels. Direct stage reads check the host's two-edge reset release and
two-stage switch synchronization. Directed cases cover a gate change
during loading, a gate change during a run, and asynchronous reset after
the core has begun computing with a stored result of 1. The reset case
retains the AND select code and explicitly requires a new full weight
load, so a gate-change reload cannot hide a missing reset reload.

### Actual simulation

Tool: Vivado xsim 2024.2. Command from the repository root:

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_nexys_top -Sources @('src\clamp.sv','src\mac_unit.sv','src\weight_sr.sv','src\control_fsm.sv','src\twinmac_core.sv','src\tt_um_troypeters42_twinmac.sv','fpga\nexys_top.sv','sim\tb_nexys_top.sv')
```

After the approved review change, the unknown-pin check uses reduction
XOR and case inequality instead of $isunknown, with no expected values or
check counts changed. The runner exited 0. It verified 35 requested cases, 12 complete weight
words, and 53 completed computations from 54 starts. One live run was
deliberately aborted by reset. All 50440 checks passed. The simulation
finished at 152560 ns. The last 10 command-output lines were:

```text
Board reset during a run and complete preset reload checked.
Requested cases verified: 35; complete weight words: 12.
Observed computations: 53; starts: 54.
FPGA pin/protocol checks: 50440; failures: 0.
ALL TESTS PASSED
$finish called at time : 152560 ns : File "C:/Users/petet/TwinMac/sim/tb_nexys_top.sv" Line 303
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 02:28:54 2026...
Verification log: C:\Users\petet\twinmac\sim\logs\tb_nexys_top.run.log
ALL TESTS PASSED
```

The raw vendor logs and combined run log remain under sim/logs with
the tb_nexys_top prefix. The runner was not modified.

### Actual FPGA implementation

Tool: Vivado 2024.2. The build targets xc7a200tsbg484-1 and the frozen
Nexys Video pin map. The XDC defines one 10 ns clock, all used package
pins and I/O standards, CONFIG_VOLTAGE=3.3, and CFGBVS=VCCO.

Command from the repository root, after creating fpga/build:

```powershell
& 'C:\Xilinx\Vivado\2024.2\bin\vivado.bat' -mode batch -source fpga/build.tcl -log fpga/build/vivado.log -journal fpga/build/vivado.jou
```

The build exited 0 and printed BUILD PASSED after synthesis, optimization,
placement, routing, timing reports, DRC, checkpoint writing, and bitstream
generation. Both worst timing paths were nonnegative:

| Routed result | Actual value |
| --- | ---: |
| Clock period | 10.000 ns (100 MHz) |
| Worst setup slack | +0.606 ns |
| Worst hold slack | +0.122 ns |
| Setup TNS / failing endpoints | 0.000 ns / 0 |
| Hold THS / failing endpoints | 0.000 ns / 0 |
| Slice LUTs | 230 (0.17%) |
| Slice registers | 202 (0.08%) |
| Slices | 82 (0.25%) |
| Block RAM tiles | 0 |
| DSP blocks | 0 |
| Bonded IOBs | 21 (7.37%) |
| BUFGCTRL | 1 |

This Boolean-input bitstream uses LUT/CARRY arithmetic, zero DSP blocks,
and zero RAM. It does not contain two unrestricted signed-eight-bit
multipliers. These are FPGA resources, separate from ASIC area.

The bitstream is fpga/build/nexys_top.bit, 9730758 bytes.
Its SHA-256 is:

```text
28671ec5ddfc03038b709f643b2ff6664eec0a6069a8f4544085cc45916d760b
```

The complete build log is fpga/build/vivado.log. Routed reports are
timing_summary.rpt, setup_paths.rpt, hold_paths.rpt, utilization.rpt,
drc.rpt, and results.txt in fpga/build. The routed checkpoint is
nexys_top_routed.dcp. Vivado's auxiliary clockInfo.txt was retained there
after the run. All generated build files are already ignored by Git.

### Board arithmetic scope and build-input identity

The board host loads x1 and x2 only as the integer 0 or 1. The existing
routed checkpoint retains only x1_reg_reg[0] and x2_reg_reg[0]; bits [7:1]
of both chip input registers are removed. MAC 1 only multiplies a Boolean
input (or zero) by a weight, so it needs no general multiplier in this
bitstream. MAC 0 sees only nonnegative seven-bit operands: Boolean inputs
in the first pass and zero-extended h1/h2 in the second pass, multiplied
by signed eight-bit weights. Its declared product's redundant sign bit
can be trimmed. This arithmetic specialization follows from the source
and the constant input bits; module LUT counts alone do not prove it.

Negative and large x values are not exercised on hardware. The +0.606 ns
setup result and zero DSP count apply only to this Boolean demo bitstream;
they do not show that two full signed-eight-bit multipliers run at 100 MHz.
The full signed range is verified in simulation: at RTL, and with the
specified extreme test vectors on the gate-level netlist through gl_test.
The unchanged ASIC sources retain both full multipliers. The cocotb
chip-pin test includes both +32895 accumulator paths, the -32640 corner,
and negative inputs. Its gate-level run uses functional UNIT_DELAY models
at a 1 us clock, not a timing measurement at 50 or 100 MHz.
Vivado's logs do not state why it selected LUT logic rather than DSPs, so
its specific mapping heuristic remains unproven.

All eight build-input hashes below match the preserved post-build manifest.
Their modification times predate the original bitstream and they remain
unchanged after the build, including this review update. These are the
actual source and XDC inputs used by the preserved bitstream, not hashes
of an altered or rebuilt design. The one-line simulation-only testbench
change does not require a new bitstream. The build script, checkpoint,
and bitstream also remain unchanged.

| Build input | SHA-256 |
| --- | --- |
| fpga/nexys_top.sv | 4c586275e364c259f05a80e0ec98d3038af1b9ab8043598794caf50026283cc7 |
| fpga/twinmac.xdc | d0fbe121a3c67ff2094f83ce630440b0c6997baca5beda4298cc044c74336a23 |
| src/clamp.sv | 4b8fefb98bfa90016f9003cb531b4f10f340cde75ad6d77b32f5595241b11c97 |
| src/control_fsm.sv | 78a8f89a31f85df969678f2b6779e528ba900ffeded71e1df1457eb3575871c1 |
| src/mac_unit.sv | fbad2c0bbecaa0499cab8da6cc047f117febebbc83365ad06f9a2703d79ce42d |
| src/tt_um_troypeters42_twinmac.sv | 71b148a3d625c0b733c4d11070a11091e3cce31bf0d37df3d53ae1a48b703a41 |
| src/twinmac_core.sv | a5b6699983c84d12169c518d78b3de7199d35bd789c2887a31c6e8754554711f |
| src/weight_sr.sv | 49f144cece83d5c23167cd0346d26cade918d0f9e58da72c0d2093cadf1b0a37 |

### Routed utilization by hierarchy

This table was extracted from the existing routed checkpoint. Rows marked
"including children" include descendant cells; rows marked "own" exclude
them. There are 48 host flip-flops and 154 chip flip-flops, 202 in total.
All rows use zero DSP, RAMB36, and RAMB18 blocks.

| Instance | Module / ownership | LUTs | Flip-flops |
| --- | --- | ---: | ---: |
| nexys_top | including children | 230 | 202 |
| nexys_top | own host logic | 25 | 48 |
| chip | tt_um_troypeters42_twinmac, including children | 207 | 154 |
| chip | own wrapper logic | 16 | 19 |
| chip/core | twinmac_core, including children | 191 | 135 |
| chip/core | own core logic | 0 | 21 |
| chip/core/clamp0 | clamp | 0 | 0 |
| chip/core/clamp1 | clamp | 0 | 0 |
| chip/core/controller | control_fsm | 104 | 8 |
| chip/core/mac0 | mac_unit | 35 | 17 |
| chip/core/mac1 | mac_unit | 10 | 17 |
| chip/core/weight_store | weight_sr | 46 | 72 |

LUT counts by module are not functional sizes. Vivado moved logic across
module boundaries and combined LUTs across hierarchy. Child LUT counts
are therefore not necessarily additive, and a zero-LUT clamp row does
not mean clamping was removed. In particular, the controller's 104 LUTs
and MAC 1's 10 LUTs describe optimized ownership, not isolated source costs.

### Implementation limits and warnings

The timing report has zero unconstrained internal endpoints, zero
combinational loops, and no multiple-clock register pins. Six asynchronous
board inputs (CPU reset and switches) have no input-delay constraints,
and eight LED outputs have no output-delay constraints. These external
I/O paths are not covered by a synchronous board-interface timing
contract. The 100 MHz result applies to the clocked internal paths.
No timing exceptions were added.

Vivado reported zero errors and zero critical warnings. Its DRC report
contains two warnings, PDRC-144 and PDRC-146: LUT C6/C5 and D6/D5 pairs at
SLICE_X2Y69 have different equations without A6 connected to Global Logic
High. They are retained for review; no claim of a warning-free DRC run
is made. Other build warnings include the deliberately constant OLED
outputs and unused controls. The bitstream precondition DRC completed
with zero errors.

Only RTL simulation and FPGA synthesis/implementation were run for this
step. Post-route functional simulation and physical board operation are
unverified. The FPGA result does not establish ASIC timing.

### LUT-packing warnings: existing checkpoint evidence

The checkpoint has no named logical LUT cells in C6LUT, C5LUT, D6LUT,
or D5LUT at SLICE_X2Y69. The site instead has physical constant/route-through
LUT configurations. A control query of the occupied B6LUT correctly returns
chip/core/controller/next_acc1_carry_i_2, so the four empty cell queries
are not substituted with guessed source-cell names.

The physical BEL properties expose CONFIG.EQN, not a logical cell INIT
property, for these four positions. The following INIT equivalents are
calculated from each separate reported equation (A1 is the least significant
truth-table address bit). They are not a decoded shared LUT SRAM word from
the bitstream, and no nonexistent logical-cell INIT property is claimed.

| Physical BEL at SLICE_X2Y69 | Named logical LUT cell | Reported CONFIG.EQN | Function-equivalent INIT (derived) |
| --- | --- | --- | --- |
| C6LUT | none | O6=(A6+~A6)*(1) | 64'hFFFFFFFFFFFFFFFF |
| C5LUT | none; data route for weights_reg[30]/D | O5=(A1) | 32'hAAAAAAAA |
| D6LUT | none | O6=(A6+~A6)*(0) | 64'h0000000000000000 |
| D5LUT | none; data route for weights_reg[31]/D | O5=(A2) | 32'hCCCCCCCC |

What drives A6: the C6LUT/A6 and D6LUT/A6 BEL pins have no attached logical
pin or net. The SLICE_X2Y69/C6 and /D6 site inputs also have no net. Thus
no A6 signal driver or explicit global-high tie is recorded in this
checkpoint. This observation does not establish a physical default level.

The associated named cells are chip/core/mac1/next_acc1_carry (CARRY4),
chip/core/weight_store/weights_reg[30] (FDRE at CFF), and
chip/core/weight_store/weights_reg[31] (FDRE at DFF). The carry's S[2] and
S[3] pins use <const1> and <const0>, respectively. The register D pins map
through C5LUT/A1 and D5LUT/A2. These associations describe observed pins
and equations; they do not by themselves prove the packing warnings safe.

For completeness, the actual named logic LUTs elsewhere in this same site
are next_acc1_carry_i_2 at B6LUT with INIT=64'hF5FFF3F3F5FFFFFF, and
next_acc1_carry_i_3 at A6LUT with INIT=64'h0A000C0C0A000000, both under
chip/core/controller. Those are not the four positions named by the warnings.

The inspection only opened the existing routed checkpoint. It did not
synthesize, place, route, change constraints, or generate a bitstream.
The focused checkpoint output follows (trailing whitespace omitted):

```text
Read-only inspection of existing routed checkpoint nexys_top_routed.dcp
Named logical cells at SLICE_X2Y69:
  chip/core/controller/next_acc1_carry_i_2; REF_NAME=LUT6; BEL=SLICEM.B6LUT
  chip/core/controller/next_acc1_carry_i_3; REF_NAME=LUT6; BEL=SLICEM.A6LUT
  chip/core/mac1/next_acc1_carry; REF_NAME=CARRY4; BEL=SLICEM.CARRY4
  chip/core/weight_store/weights_reg[30]; REF_NAME=FDRE; BEL=SLICEM.CFF
  chip/core/weight_store/weights_reg[31]; REF_NAME=FDRE; BEL=SLICEM.DFF

BEL: SLICE_X2Y69/B6LUT
Named logical cell: chip/core/controller/next_acc1_carry_i_2
CONFIG.EQN: O6=(A5*A4*A1)+(A5*A4*(~A1)*A3*(~A6)*(~A2))+(A5*A4*(~A1)*(~A3)*A6)+(A5*A4*(~A1)*(~A3)*(~A6)*(~A2))+(A5*(~A4)*A1)+(A5*(~A4)*(~A1)*A3*(~A6))+(A5*(~A4)*(~A1)*(~A3))+((~A5)*A4*A1)+((~A5)*A4*(~A1)*A6)+((~A5)*A4*(~A1)*(~A6)*(~A2))+((~A5)*(~A4))

BEL: SLICE_X2Y69/C6LUT
Named logical cell:
CONFIG.EQN: O6=(A6+~A6)*(1)
A6 logical pins:
A6 logical nets:

BEL: SLICE_X2Y69/C5LUT
Named logical cell:
CONFIG.EQN: O5=(A1)

BEL: SLICE_X2Y69/D6LUT
Named logical cell:
CONFIG.EQN: O6=(A6+~A6)*(0)
A6 logical pins:
A6 logical nets:

BEL: SLICE_X2Y69/D5LUT
Named logical cell:
CONFIG.EQN: O5=(A2)
Site input SLICE_X2Y69/C6 net:
Site input SLICE_X2Y69/D6 net:

Carry pin: chip/core/mac1/next_acc1_carry/S[2]; net: chip/core/mac1/<const1>
Local physical BEL pin: SLICE_X2Y69/CARRY4/S2

Carry pin: chip/core/mac1/next_acc1_carry/S[3]; net: chip/core/mac1/<const0>
Local physical BEL pin: SLICE_X2Y69/CARRY4/CYINIT
Local physical BEL pin: SLICE_X2Y69/CARRY4/DI0
Local physical BEL pin: SLICE_X2Y69/CARRY4/DI2
Local physical BEL pin: SLICE_X2Y69/CARRY4/DI3
Local physical BEL pin: SLICE_X2Y69/CARRY4/S3

Register data pin: chip/core/weight_store/weights_reg[30]/D
Net: chip/core/weight_store/Q[17]
Physical BEL pins: SLICE_X2Y69/C5LUT/A1 SLICE_X2Y69/CFF/D

Register data pin: chip/core/weight_store/weights_reg[31]/D
Net: chip/core/weight_store/Q[18]
Physical BEL pins: SLICE_X2Y69/D5LUT/A2 SLICE_X2Y69/DFF/D
```

The full original warning text follows (trailing whitespace omitted):

```text
PDRC-144#1 Warning
SLICE_PairEqSame_C6C5_WARN
Luts C6LUT and C5LUT in use in site SLICE_X2Y69 with different equations without A6 pin connected to Global Logic High.
Related violations: <none>

PDRC-146#1 Warning
SLICE_PairEqSame_D6D5_WARN
Luts D6LUT and D5LUT in use in site SLICE_X2Y69 with different equations without A6 pin connected to Global Logic High.
Related violations: <none>


```

These warnings remain an implementation limitation. Bitstream generation
passed, but no claim that the warnings are harmless is made. Post-route
functional simulation has not been performed. Codex did not perform the
board test; Troy's later general pass report is recorded below.

### What the AND board row checks

Every board preset gives MAC 1 the same weights: b2=8'hFF (-1),
w22=8'h01 (1), and w21=8'h01 (1). Thus h2 is the clamped value of
-1 + x1 + x2 for all six gates. The AND preset has output bias b=0,
a=0, and c=1, so its output is y=h2 directly.

The AND row, with LD1 through LD6 off, is therefore the direct board
check of the MAC 1 / clamp1 / h2 logic associated with PDRC-144 and
PDRC-146. For inputs (0,0), (0,1), (1,0), and (1,1), the complete
seven-bit result must be 0, 0, 0, and 1; checking only LD0 would miss
unexpected upper result bits. Troy later reported that the board test
worked, without supplying observations for individual checks. These four
cases are the only MAC 1 computations this bitstream can perform,
because its presets and Boolean inputs are fixed. A pass therefore covers MAC 1
for this bitstream. It does not explain the warnings or carry over to a rebuild.

### Board verification and review checkpoint

## Nexys Video board-test checklist

1. With the board off, set JP4 to JTAG.
2. Connect 12 V power to J21 and micro-USB from PROG (J12) to the computer.
3. Power on with SW8 and confirm the OLED stays dark. If it lights up, stop. Don't reprogram it or power it off until we've identified its shutdown step.

Only after the OLED-dark check passes:

- [ ] Program fpga/build/nexys_top.bit onto the Nexys Video.
- [ ] Before pressing anything, confirm LD7 looks lit and LD0 matches the switches.
  No reset press should be needed after programming.

Predicted steady-state behavior, not a board measurement: LD7 is on about 83%
of the time at about 2.4 MHz (35 of 42 cycles at 100 MHz). It should look steady
and may be slightly dimmer than LD0 when LD0 is on.

- [ ] Confirm the OLED stays dark throughout these checks.
- [ ] Hold CPU RESET: LD0 through LD7 should clear. Release it to load the selected preset.
- [ ] Use SW[4:2] for the gate, SW0 for x1, and SW1 for x2.
- [ ] For every table cell below, set the two switches, let the output settle, and record LD0.
- [ ] Confirm LD1 through LD6 stay off for these Boolean results.
- [ ] Confirm LD7 illuminates after settling. Repeated runs are fast, so it may look steady.

Inputs are written as (x1, x2), meaning (SW0, SW1). Each cell is expected LD0 / observed LD0.

| SW[4:2] | Gate | (0,0) | (0,1) | (1,0) | (1,1) |
| --- | --- | --- | --- | --- | --- |
| 000 | AND | 0 / ___ | 0 / ___ | 0 / ___ | 1 / ___ |
| 001 | OR | 0 / ___ | 1 / ___ | 1 / ___ | 1 / ___ |
| 010 | XOR | 0 / ___ | 1 / ___ | 1 / ___ | 0 / ___ |
| 011 | NAND | 1 / ___ | 1 / ___ | 1 / ___ | 0 / ___ |
| 100 | NOR | 1 / ___ | 0 / ___ | 0 / ___ | 0 / ___ |
| 101 | XNOR | 1 / ___ | 0 / ___ | 0 / ___ | 1 / ___ |

- [ ] Check selects 110 and 111 repeat AND, including a 1 at input (1,1).
- [ ] Change gates without resetting; confirm the output settles to the new gate's truth table.
- [ ] Select NAND with (0,0), confirm LD0=1, hold CPU RESET to clear it, then release and confirm 1 returns.
- [ ] Press/release BTNC: OLED remains dark and computation continues. OLED control is not implemented yet.
- [ ] Report all 24 observed values and any mismatch, including gate select, inputs, LD0, and LD7.

Board observations and programming have not been performed by Codex.

Step 8 was committed with its board test pending. On Nov 5, 2026, Troy
reported that the board test worked and approved the OLED implementation
for commit. Individual switch/LED observations were not supplied, so the
checklist cells remain blank. OLED-specific checks are recorded separately
in step 9. Step 10 records the existing ASIC run.

## Step 10: Final ASIC area, power, and maximum frequency

### Scope and final-run provenance

Troy authorized this documentation step after the six jobs on 93ed933
passed and max_ss setup remained +0.932191 ns. At that review, optional
step 9 was skipped and step 8 still had a physical board test pending.
These ASIC measurements did not establish board acceptance. Troy's later
board-test report appears in step 8 and the approval record in step 9.

The measured hardware/configuration is commit
93ed9336332b825106a2125844bdb7f302f562f1 on rtl. Its ASIC source, tests,
info.yaml, and configuration are unchanged from f71810b. No source,
test, pin, clock-period, placement-density, or configuration change was
made for this step. All seven local xsim testbenches were rerun on the
unchanged design, as recorded below. No ASIC or FPGA implementation was
rerun locally.

The final measurement source is [GDS run 41988729116](https://github.com/troypeters42/twinmac/actions/runs/41988729116),
GDS_logs artifact 13397585857. The downloaded ZIP matches GitHub's
published SHA-256 digest:

```text
415851ce40f5b29e04a3a2c54a9959e11772baa1a2181db67c90d0354e9272b4
```

The artifact identifies LibreLane 3.0.14 and sky130_fd_sc_hd. Its source
and configuration content match the current tree. All report paths below
are relative to this GDS_logs artifact, not a previous timing experiment.

| GitHub job | Observed result |
| --- | --- |
| [test](https://github.com/troypeters42/twinmac/actions/runs/41988729222/job/127115597653) | passed |
| [docs](https://github.com/troypeters42/twinmac/actions/runs/41988729258/job/127115597926) | passed |
| [gds](https://github.com/troypeters42/twinmac/actions/runs/41988729116/job/127115597238) | passed |
| [precheck](https://github.com/troypeters42/twinmac/actions/runs/41988729116/job/127117723101) | passed |
| [gl_test](https://github.com/troypeters42/twinmac/actions/runs/41988729116/job/127117723097) | passed |
| [viewer](https://github.com/troypeters42/twinmac/actions/runs/41988729116/job/127117723028) | passed |

### Final physical area

Source: runs/wokwi/final/metrics.json. The chip uses the frozen 1x2 tile;
these are ASIC layout measurements, separate from FPGA utilization.

| Quantity | Final value |
| --- | ---: |
| Standard-cell area (design__instance__area__stdcell) | 20,835.0 um^2 |
| Standard-cell count | 2,223 |
| Core area | 34,255.4 um^2 |
| Die area | 36,347.4 um^2 |
| Die dimensions | 161.00 by 225.76 um |
| Standard-cell utilization of core | 60.8226% |
| Macro area / pad-cell area | 0 / 0 um^2 |

Cell area counts the instantiated standard cells. Core and die area are
layout envelopes, so they are different measurements. The unqualified
instance-area metric is 34,255.4 um^2 after filling; use the explicit
standard-cell metric for the 20,835.0 um^2 result. The requested placement
density remains 60%; final measured utilization is 60.8226%.

### What the standard-cell area contains

The class breakdown comes from the same final/metrics.json. The 315
timing-repair buffers and the tap cells are part of the 20,835 um^2.
Fill cells are excluded from that standard-cell total.

| Included class | Cells | Area (um^2), as reported |
| --- | ---: | ---: |
| Sequential cells | 168 | 4053.89 |
| Multi-input combinational cells | 1202 | 12004 |
| Inverters | 19 | 71.3184 |
| Ordinary buffers | 1 | 5.0048 |
| Timing-repair buffers | 315 | 2991.62 |
| Clock buffers | 61 | 1136.09 |
| Tap cells | 456 | 570.547 |
| Antenna cells | 1 | 2.5024 |
| Reported standard-cell total | 2223 | 20835.0 |

Individual class areas are printed at limited precision; the reported
total uses the tool's underlying values. The 4,060 fill cells occupy
13,420.4 um^2 separately. Adding that fill area to the reported
20,835.0 um^2 gives the filled instance area of 34,255.4 um^2.

### Setup, hold, and all nine corners

Source: runs/wokwi/55-openroad-stapostpnr/summary.rpt and the corresponding
per-corner ws.max.rpt, ws.min.rpt, wns/tns reports, and final/metrics.json.
The prefixes min, nom, and max select extracted interconnect RC corners.
The remaining name identifies the process, temperature, and supply:
ss_100C_1v60 is slow/100 C/1.60 V; ff_n40C_1v95 is fast/-40 C/1.95 V;
tt_025C_1v80 is typical/25 C/1.80 V.

| Corner | Setup worst slack (ns) | Hold worst slack (ns) | Max-slew count |
| --- | ---: | ---: | ---: |
| min_ss_100C_1v60 | +1.334934 | +0.867764 | 202 |
| min_tt_025C_1v80 | +10.512190 | +0.326064 | 0 |
| min_ff_n40C_1v95 | +14.027466 | +0.115010 | 0 |
| nom_ss_100C_1v60 | +1.144626 | +0.880109 | 251 |
| nom_tt_025C_1v80 | +10.396707 | +0.333243 | 0 |
| nom_ff_n40C_1v95 | +13.951905 | +0.119370 | 0 |
| max_ss_100C_1v60 | +0.932191 | +0.894136 | 303 |
| max_tt_025C_1v80 | +10.267687 | +0.339036 | 11 |
| max_ff_n40C_1v95 | +13.864521 | +0.120985 | 0 |

Setup and hold WNS and TNS are 0.000000 ns at every corner, with zero
setup/hold violating endpoints. Positive worst slack is different from
WNS: WNS records only a negative result, so a passing corner has WNS=0.

The setup signoff result at ss_100C_1v60 is limited by max RC:
+0.932191 ns. The hold signoff result at ff_n40C_1v95 is limited by min RC:
+0.115010 ns. Slow logic limits how late data may arrive; fast logic
limits how early it can change after the receiving clock edge.

### Maximum frequency from the measured slack

The configured period is 20.000000 ns, or 50 MHz. The worst setup path
in max_ss_100C_1v60 starts at core.controller.state[1] (mapped register
cell _2554_) and ends at register _2446_, both on the rising edge of clk.
The final gate-level netlist connects _2554_/Q to core.controller.state[1]. Its expanded-clock report includes the routed
clock tree, skew, 0.25 ns clock uncertainty, clock reconvergence correction,
and library setup time. The run also applies 5% timing derating.

Keeping that implementation and those timing assumptions fixed, its
positive slack is the amount by which the period can be reduced before
this path reaches zero setup slack:

```text
T_min = T_current - setup_slack
      = 20.000000000000000 - 0.932191239474114
      = 19.067808760525886 ns

f_max = 1 / T_min
      = 1000 / 19.067808760525886
      = 52.444411 MHz, approximately 52.44 MHz
```

The same corner's clock.rpt independently prints:

```text
clk period_min = 19.07 fmax = 52.44
```

This is a static-timing-derived limit for the routed ASIC under the stated
constraints, not a measured silicon frequency or a new build at 52.44 MHz.
CLOCK_PERIOD stays at 20 ns. It is also separate from the Boolean FPGA
demo's 100 MHz result. The open max-slew violations below still limit
how strongly this timing estimate can be treated as complete signoff.

### Power at tt_025C_1v80

The main power result uses nominal extracted RC at typical process,
25 C, 1.80 V, and the actual 20 ns clock (50 MHz). Source:
runs/wokwi/55-openroad-stapostpnr/nom_tt_025C_1v80/power.rpt and its
sta.log power metrics. The table uses milliwatts; the raw report uses watts.

| Component | Reported power (mW) |
| --- | ---: |
| Internal | 2.620613901 |
| Switching | 2.026908100 |
| Leakage | 0.000019274 |
| Total | 4.647541326 |

Total power is 0.0046475413255393505 W, or approximately 4.647541 mW.
Leakage is approximately 19.274 nW. Clock-tree power is already included
in the total; the report's Clock group is 0.5613171 mW and must not be
added again. Macro and Pad groups both report zero.

The same nominal-tt power report splits the total by cell group:

| Power group | Share of total |
| --- | ---: |
| Sequential | 8.8% |
| Combinational | 79.1% |
| Clock | 12.1% |

These shares describe the same total above; clock power is not an extra
amount to add to it. Macro and pad power groups are both zero.

The three RC variants at the requested typical PVT are:

| tt_025C_1v80 RC corner | Total power (mW) |
| --- | ---: |
| min_tt_025C_1v80 | 4.597597 |
| nom_tt_025C_1v80 | 4.647541 |
| max_tt_025C_1v80 | 4.702079 |

Do not label the unqualified final/metrics.json power__total as typical
power: its 5.422246 mW is the maximum aggregate result, which matches
max_ff_n40C_1v95. The requested nominal-tt number comes from its own report.

### Power assumptions and what the estimate covers

The final STA log reads the post-fill netlist, tt Liberty power models,
nominal extracted SPEF, and the generic base.sdc. The clock report uses a
20 ns period with rising/falling edges at 0/10 ns. The output load is
0.033442 pF (33.442 fF); input/output delay constraints are 4 ns.
STA_EXTRA_CORNER_TCL_FILE is null. The flow scripts contain no VCD/SAIF
read or application-specific activity override for this run.

The activity assumption is inferred from the flow scripts and documented
OpenSTA defaults, not a measured per-pin activity dump. The default
non-clock input activity is 0.1 transitions per minimum clock period,
with a 0.5 probability of being high. At 20 ns that is 5 million
transitions per second. OpenSTA propagates activity through the logic;
it does not assume every internal node toggles at that same rate.
See the [OpenSTA power commands](https://github.com/The-OpenROAD-Project/OpenSTA/blob/master/doc/Commands.md#report_power)
and [LibreLane 3.0.14 corner script](https://github.com/librelane/librelane/blob/3.0.14/librelane/scripts/openroad/sta/corner.tcl).

No gate-selection distribution, inference rate, weight-loading rate,
reset schedule, or idle fraction was supplied. The estimate therefore
is not a workload measurement of the Boolean board demo. It covers this
block's modeled cells, internal clock tree, and modeled output loads;
it is not FPGA board power or a complete Tiny Tapeout die/package power
measurement. The final STA log reports physical fill/tap cells as black
boxes without Liberty timing models, so their separate physical effects
are not characterized by this activity-based cell-power result. No VCD-based
power analysis or silicon power measurement is claimed.

### Physical checks and remaining limitations

The final metrics report zero detailed-route DRC errors, Magic DRC errors,
LVS errors, and antenna-violating nets/pins. KLayout DRC is disabled in
the LibreLane build by the template setting; the passing precheck runs
its separate Magic and KLayout checks. A green build does not replace
reading the actual per-corner timing table above.

The overall timing summary still reports **303 open max-slew pin
violations**, the maximum single-corner count at max_ss_100C_1v60. The
row counts are not summed across corners because checks can repeat the
same pins. max_tt has 11; min/nom_ss have 202/251. These are separate
transition constraints, not setup/hold failures, and remain the accepted
open limitation. The ten worst distinct nets are retained in the earlier
"Open max-slew limitation" table. No timing exception or hardware change
was made to remove or hide the violations.

The final metric design__max_fanout_violation__count = 1 is also an
**open item**, separate from the max-slew count above.

Step 8's two FPGA LUT-packing warnings remain recorded. Troy's later general
board-test pass report does not supply individual AND-row observations.
Negative/large signed inputs and the specified accumulator extremes have
simulation coverage at RTL and in the gl_test extreme vectors; the Boolean
board bitstream does not exercise that full input range. The subsequent
OLED implementation and its hardware-check status are recorded in step 9.

### Verification, regression, and review status

The area/power/timing numbers above come from the existing CI artifacts
for 93ed933. The report verification checked artifact digests, corner
values, power units, frequency arithmetic, and protected-file hashes.
The gate-level results.xml reports one test with zero errors/failures;
test/test.py includes the signed/extreme chip-pin vectors.

For this approved documentation update, all seven sim/ testbenches were
rerun in Vivado xsim 2024.2 on Nov 5, 2026, from 12:00:03 to 12:01:07
Eastern (UTC-05:00). Each runner exited 0 and printed ALL TESTS PASSED.
No expected values, tests, RTL, configuration, metadata, or FPGA files
were changed. The FPGA bitstream and routed checkpoint are unchanged.

| Testbench | Observed checks / inputs | Simulation finish (ns) | Failures | Runner exit |
| --- | ---: | ---: | ---: | ---: |
| tb_clamp | 131,072 | 131,072 | 0 | 0 |
| tb_mac_unit | 8,062 | 40,246 | 0 | 0 |
| tb_weight_sr | 376 | 2,486 | 0 | 0 |
| tb_control_fsm | 1,096 | 5,476 | 0 | 0 |
| tb_twinmac_core | 1,582,858 | 7,914,296 | 0 | 0 |
| tb_twinmac | 18,056 | 337,111 | 0 | 0 |
| tb_nexys_top | 50,440 | 152,560 | 0 | 0 |

The clamp row counts all possible signed 17-bit inputs. MAC tests include
1,000 random cases. The core completed 10,045 results, including 10,000
random cases. The chip wrapper completed 35 results. The Nexys monitor
checked 35 requested cases and 53 completions; one run was deliberately
aborted by reset. These are simulation results, not board observations.

Commands below were run from C:\Users\petet\twinmac. Each is followed
by the actual last ten command-output lines. The unchanged runner retains
raw tool logs and its combined verification logs under sim/logs/.

#### tb_clamp

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_clamp -Sources @('src\clamp.sv','sim\tb_clamp.sv')
```

```text
# xsim {tb_clamp_sim} -autoloadwcfg -runall
Time resolution is 1 ps
run -all
Checked 131072 signed inputs (-65536 through 65535).
ALL TESTS PASSED
$finish called at time : 131072 ns : File "C:/Users/petet/TwinMac/sim/tb_clamp.sv" Line 56
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 12:00:28 2026...
Verification log: C:\Users\petet\twinmac\sim\logs\tb_clamp.run.log
ALL TESTS PASSED
```

#### tb_mac_unit

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_mac_unit -Sources @('src\mac_unit.sv','sim\tb_mac_unit.sv')
```

```text
Accumulator high: expected=32895 actual=32895
Accumulator low: expected=-32640 actual=-32640
Random cases completed: 1000 (two updates and two holds each).
Accumulator checks completed: 8062; failures: 0.
ALL TESTS PASSED
$finish called at time : 40246 ns : File "C:/Users/petet/TwinMac/sim/tb_mac_unit.sv" Line 210
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 12:00:34 2026...
Verification log: C:\Users\petet\twinmac\sim\logs\tb_mac_unit.run.log
ALL TESTS PASSED
```

#### tb_weight_sr

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_weight_sr -Sources @('src\weight_sr.sv','sim\tb_weight_sr.sv')
```

```text
All nine byte fields checked for both patterns.
Extra-bit word: expected=b586fc01db2dff0279 actual=b586fc01db2dff0279
Tracked rising edges: 217 shifts, 31 holds.
Weight comparisons completed: 376; failures: 0.
ALL TESTS PASSED
$finish called at time : 2486 ns : File "C:/Users/petet/TwinMac/sim/tb_weight_sr.sv" Line 190
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 12:00:40 2026...
Verification log: C:\Users\petet\twinmac\sim\logs\tb_weight_sr.run.log
ALL TESTS PASSED
```

#### tb_control_fsm

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_control_fsm -Sources @('src\control_fsm.sv','sim\tb_control_fsm.sv')
```

```text
Reset aborts checked in all six compute states, plus reset during done.
Reset release with start high waited for the next rising edge.
Runs: 64; reset-abort phases: 6; reset sequences: 8.
Control-vector checks completed: 1096; failures: 0.
ALL TESTS PASSED
$finish called at time : 5476 ns : File "C:/Users/petet/TwinMac/sim/tb_control_fsm.sv" Line 219
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 12:00:46 2026...
Verification log: C:\Users\petet\twinmac\sim\logs\tb_control_fsm.run.log
ALL TESTS PASSED
```

#### tb_twinmac_core

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_twinmac_core -Sources @('src\clamp.sv','src\mac_unit.sv','src\weight_sr.sv','src\control_fsm.sv','src\twinmac_core.sv','sim\tb_twinmac_core.sv')
```

```text
Random cases completed: 10000; all 64 busy-start masks exercised.
Reset aborts: six phases; all registers cleared; weights retained.
Completed results: 10045; reset sequences: 8.
Core-state checks completed: 1582858; failures: 0.
ALL TESTS PASSED
$finish called at time : 7914296 ns : File "C:/Users/petet/TwinMac/sim/tb_twinmac_core.sv" Line 312
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 12:00:54 2026...
Verification log: C:\Users\petet\twinmac\sim\logs\tb_twinmac_core.run.log
ALL TESTS PASSED
```

#### tb_twinmac

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_twinmac -Sources @('src\clamp.sv','src\mac_unit.sv','src\weight_sr.sv','src\control_fsm.sv','src\twinmac_core.sv','src\tt_um_troypeters42_twinmac.sv','sim\tb_twinmac.sv')
```

```text
Reset, retained weights, zeroed inputs, and aborted run checked.
Exact wrapper latency checked.
Completed chip-pin results: 35.
Chip-pin checks completed: 18056; failures: 0.
ALL TESTS PASSED
$finish called at time : 337111 ns : File "C:/Users/petet/TwinMac/sim/tb_twinmac.sv" Line 281
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 12:01:00 2026...
Verification log: C:\Users\petet\twinmac\sim\logs\tb_twinmac.run.log
ALL TESTS PASSED
```

#### tb_nexys_top

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_nexys_top -Sources @('src\clamp.sv','src\mac_unit.sv','src\weight_sr.sv','src\control_fsm.sv','src\twinmac_core.sv','src\tt_um_troypeters42_twinmac.sv','fpga\nexys_top.sv','sim\tb_nexys_top.sv')
```

```text
Board reset during a run and complete preset reload checked.
Requested cases verified: 35; complete weight words: 12.
Observed computations: 53; starts: 54.
FPGA pin/protocol checks: 50440; failures: 0.
ALL TESTS PASSED
$finish called at time : 152560 ns : File "C:/Users/petet/TwinMac/sim/tb_nexys_top.sv" Line 303
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 12:01:07 2026...
Verification log: C:\Users\petet\twinmac\sim\logs\tb_nexys_top.run.log
ALL TESTS PASSED
```

All seven tests passed before this documentation-only commit. The
protected files were checked by SHA-256 and modification time against
the pre-run snapshot. Only docs/rtl_notes.md is committed for step 10.
The new commit's GitHub job results are reported after the push; the
six-job table above identifies the measured 93ed933 run.

At the e8e710e step 10 review, step 8 remained board test pending and
optional step 9 was skipped. That documentation-only commit changed no
source, test, configuration, or FPGA implementation. The later authorized
OLED work is recorded below; ASIC slew/fanout items remain open.

## Step 9: Optional OLED decision-map demo

### Scope and review status

Troy authorized this step after e8e710e, including FPGA-only bitmap memory,
OLED SPI, the six map presets, and two extra switch pins. These additions
apply only to the FPGA host. The ASIC sources, cocotb tests, info.yaml,
src/config.json, and original Boolean presets are unchanged.

Worktree: C:\Users\petet\twinmac-oled, branch oled, based on e8e710e.
Troy approved this implementation for commit on Nov 5, 2026, after
reporting that the existing board test worked. This commit records the
OLED implementation on oled only. No branch was pushed. Codex did not
program a board. The original rtl worktree and plain-demo bitstream remain
unchanged. OLED-specific hardware observations have not been supplied, so
the OLED checklist remains pending.

The new files are fpga/oled_ctrl.sv, fpga/oled_text.sv, fpga/oled_map.sv,
sim/oled_spi_monitor.sv, and sim/tb_oled_ctrl.sv. This step also changes
fpga/nexys_top.sv, fpga/twinmac.xdc, sim/tb_nexys_top.sv, and these notes.
The existing fpga/build.tcl and sim/run_xsim.ps1 required no changes.

### What the hardware does

The FPGA host still drives the real chip top through its byte/control pins.
All state uses the one 100 MHz clock. Five-clock setup, high, and low
phases preserve the existing pin protocol; OLED SPI is an output driven
by clock enables, never a clock for internal registers.

After reset or a gate change, the host loads the map preset and runs all
1024 input pairs, x1 and x2 each from 0 through 31. x1 changes fastest.
Each completed chip result writes one bitmap bit, lit when y >= 16.
The host does not calculate a substitute neuron result. A gate change
during an active sweep is queued: the host finishes the sweep, then
sweeps the latest selected gate. A change before the sweep's first run
reloads the latest preset before that run. CPU RESET aborts a run/sweep;
release starts a complete fresh sweep.

After the last pixel, the host reloads the unchanged Boolean preset and
resumes switch-driven runs. Only the first completed Boolean run publishes
the new map and its gate label. The renderer snapshots the mode, gate,
latched Boolean inputs, and latest completed Boolean result at frame start.
Y comes from chip_uo, never a truth-table lookup. A switch change appears
after the corresponding completed run and a subsequent frame snapshot.

led is still assigned directly from chip_uo. During a map sweep the LEDs
show intermediate map computations, so LD1-LD6 may light briefly. Once
Boolean operation resumes, LD0 again shows the gate result and LD1-LD6
are off. This temporary sweep behavior is part of this OLED demo.

The host registers hold its state, five-cycle counter, weight word and
bit index, map coordinates, loaded gate, run inputs, and completed Boolean
values. Combinational logic selects presets, drives the chip pins, and
compares chip_y against 16. A rising edge advances the host state; the
RESULT edge stores a real chip result or writes its map pixel.

oled_map stores 128 bytes (1024 bits). It has a clocked one-bit write and
combinational byte read. Screen row is 31-x2, page is row/8, and bit is
row%8; x1 selects column 0..31. Thus (0,0) is bottom left, x1 increases
rightward, and x2 upward. No bitmap reset is needed because every bit is
replaced before publication. New sweeps wait until a current user frame
finishes, and no fresh user frame starts while the map is invalid. The
initial forced blank frame reads no bitmap data. This prevents partial
maps from becoming visible within a transmitted frame.

oled_text is a combinational byte renderer with registered frame metadata.
Columns 0..31 show the map; 32..39 are blank; text begins at column 40.
Pages 0, 1, and 2 contain GATE, X1/X2, and Y; page 3 has no text. Glyphs
use 8-by-8 cells with five-column strokes. The digit 2 is included because
the requested X2 label needs it; the handoff's shorter font list omitted it.
SW[6:5]=01 renders all pixels, 10 renders a one-pixel border, and 00/11
render the map and text. Mode changes take effect at a frame boundary.

### Presets and independently calculated map counts

The 72-bit field order remains b,c,a,b2,w22,w21,b1,w12,w11. The map
hidden sums are h1=clamp(x1+x2) and h2=clamp(x1+x2-31).
For the 0..31 input range, h1 never exceeds 62. The table gives the
integer-math oracle; the actual FPGA obtains every pixel from the chip.

| Select | Gate | Map preset | Lit pixels | Region with y >= 16 |
| --- | --- | --- | ---: | --- |
| 000 | AND | 72'h00_01_00_E1_01_01_00_01_01 | 136 | x1+x2 >= 47 |
| 001 | OR | 72'h00_FF_01_E1_01_01_00_01_01 | 888 | x1+x2 >= 16 |
| 010 | XOR | 72'h00_FE_01_E1_01_01_00_01_01 | 752 | 16 <= x1+x2 <= 46 |
| 011 | NAND | 72'h1F_FF_00_E1_01_01_00_01_01 | 888 | x1+x2 <= 46 |
| 100 | NOR | 72'h1F_01_FF_E1_01_01_00_01_01 | 136 | x1+x2 <= 15 |
| 101 | XNOR | 72'h1F_02_FF_E1_01_01_00_01_01 | 272 | x1+x2 <= 15 or >= 47 |
| 110, 111 | AND aliases | Same as AND | 136 each | x1+x2 >= 47 |

The new switch pins are SW5/J16 and SW6/K13, LVCMOS12. All existing pin
assignments are retained. These match the [Digilent master XDC](https://github.com/Digilent/digilent-xdc/blob/master/Nexys-Video-Master.xdc).
All seven switches pass through two synchronizer stages.

### OLED power, SPI, reset, and button operation

The OLED controller has its own two-clock FPGA power-on reset, independent
of CPU RESET. Its state, timer, SPI serializer, and power pins are registers.
Its next-state, command-byte, and frame-byte selections are combinational.
The routed checkpoint confirms oled_vdd_reg and oled_vbat_reg are FDPE
registers with INIT=1, the inactive power levels. CPU RESET resets the
chip/host and invalidates the map without changing either OLED power pin.

BTNC passes through two synchronizing flip-flops and a 20 ms debounce
counter. A newly stable high level toggles the requested OLED state once.
A held button does not repeat. Press and release once to shut down; press
and release again to restart. A request during a frame waits for its end.

The production timing defaults at 100 MHz are 100000 clocks per 1 ms,
10000000 clocks for the 100 ms VBAT delay, 5000000 clocks for the 50 ms
display-on delay, and 350000000 clocks for shutdown's 3.5 seconds.
BUTTON_DEBOUNCE_CYCLES defaults to 2000000. These literal defaults are
checked separately from the accelerated simulation instances.

Power-up drives VDD low and waits 1 ms, raises RES for 1 ms, sends AE,
holds RES low for 1 ms, then high for 1 ms. It sends these command bytes
with D/C low, in this exact order:

    A8 1F 8D 14 D9 F1 81 0F A0 C0 DA 02 20 00

It then drives VBAT low, waits 100 ms, transmits a blank frame, sends AF,
and waits 50 ms before user frames. Every frame has command header
21 00 7F 22 00 03 followed by exactly 512 data bytes with D/C high.
SPI is MSB first, idles high, changes data on falling edges, and samples
on rising edges. A ten-clock half-period gives 5 MHz at 100 MHz.

Shutdown completes any current frame, sends AE, drives VBAT high, waits
3.5 seconds, drives RES low, then drives VDD high on the following clock.
Before reprogramming or removing power, press/release BTNC once and wait
at least four seconds after release, even if the display goes dark sooner.
The dark image after AE alone does not prove the power sequence finished.

### Verification independence and coverage

The controller test and separate SPI monitor were written before the RTL.
The integration test retains the existing Boolean and pin-protocol checks;
only the 0-or-1 byte restriction is limited to Boolean runs. Later checks
strengthened frame-boundary handling and unequal X1/X2 text snapshots.
No expected value or check was weakened to obtain a pass.

oled_spi_monitor decodes every byte at the external SPI pins. It checks
commands, D/C, headers, 512-byte frame length, blank data, edge timing,
power ordering, and shutdown timing without reading DUT state or ROMs.
The integration test independently calculates each map with signed integer
neuron arithmetic and checks all 1024 pixels for each gate and alias.
Its font oracle uses row bitmaps rather than the renderer's column table.
Frame payloads are compared after controls settle and two frame completions
allow an older snapshot to finish. Transport/power checks cover every byte,
including transitions. All maps happen to be symmetric in x1/x2; a separate
pin-level scan-order assertion is what detects a swapped-axis stimulus.

The accelerated instances use distinct delay values: 40 clocks for 1 ms,
80 for VBAT wait, 60 for display-on wait, and 100 for shutdown. The button
uses five debounce clocks. SPI stays at the real 5 MHz. Test-only default
instances check the unmodified production values as literal integers.

Coverage includes all eight gate codes, all Boolean cases, both unequal
input text values, both bring-up patterns, the normal alias, gate changes
during loading/running/sweeping, reset during a sweep, CPU RESET with the
OLED active, button bounce, shutdown during a frame, safe restart, and
continued chip/LED operation while the OLED is off. Every sweep run is
subject to the five-clock pin checks. The integrated run completes 14 maps,
67795 Boolean results, and 37 requested Boolean cases. No physical display
orientation or board behavior has been observed.

### Actual xsim regression on the final source

All eight tests ran in Vivado xsim 2024.2 from this worktree on Nov 5, 2026.
Every runner exited 0 with ALL TESTS PASSED and zero failures.
The seven existing tests were rerun as well as the new controller test.

| Testbench | Observed coverage | Finish time | Result |
| --- | --- | --- | --- |
| tb_clamp | 131072 signed inputs | 131072 ns | PASS, exit 0 |
| tb_mac_unit | 8062 accumulator checks; 1000 random cases | 40246 ns | PASS, exit 0 |
| tb_weight_sr | 376 comparisons | 2486 ns | PASS, exit 0 |
| tb_control_fsm | 1096 checks | 5476 ns | PASS, exit 0 |
| tb_twinmac_core | 1582858 checks; 10045 results; 10000 random cases | 7914296 ns | PASS, exit 0 |
| tb_twinmac | 18056 checks; 35 completed results | 337111 ns | PASS, exit 0 |
| tb_oled_ctrl | 1031 controller + 871083 SPI/power checks | 4256470 ns | PASS, exit 0 |
| tb_nexys_top | 10601368 pin/protocol + 8644114 SPI/power checks | 45560670 ns | PASS, exit 0 |

Exact commands and final ten command-output lines follow. Complete raw and
combined logs remain in sim/logs and are copied into the review packet.

#### tb_clamp

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_clamp -Sources @('src\clamp.sv','sim\tb_clamp.sv')
```

```text
# xsim {tb_clamp_sim} -autoloadwcfg -runall
Time resolution is 1 ps
run -all
Checked 131072 signed inputs (-65536 through 65535).
ALL TESTS PASSED
$finish called at time : 131072 ns : File "C:/Users/petet/twinmac-oled/sim/tb_clamp.sv" Line 56
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 14:16:45 2026...
Verification log: C:\Users\petet\twinmac-oled\sim\logs\tb_clamp.run.log
ALL TESTS PASSED
```

#### tb_mac_unit

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_mac_unit -Sources @('src\mac_unit.sv','sim\tb_mac_unit.sv')
```

```text
Accumulator high: expected=32895 actual=32895
Accumulator low: expected=-32640 actual=-32640
Random cases completed: 1000 (two updates and two holds each).
Accumulator checks completed: 8062; failures: 0.
ALL TESTS PASSED
$finish called at time : 40246 ns : File "C:/Users/petet/twinmac-oled/sim/tb_mac_unit.sv" Line 210
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 14:16:53 2026...
Verification log: C:\Users\petet\twinmac-oled\sim\logs\tb_mac_unit.run.log
ALL TESTS PASSED
```

#### tb_weight_sr

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_weight_sr -Sources @('src\weight_sr.sv','sim\tb_weight_sr.sv')
```

```text
All nine byte fields checked for both patterns.
Extra-bit word: expected=b586fc01db2dff0279 actual=b586fc01db2dff0279
Tracked rising edges: 217 shifts, 31 holds.
Weight comparisons completed: 376; failures: 0.
ALL TESTS PASSED
$finish called at time : 2486 ns : File "C:/Users/petet/twinmac-oled/sim/tb_weight_sr.sv" Line 190
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 14:17:00 2026...
Verification log: C:\Users\petet\twinmac-oled\sim\logs\tb_weight_sr.run.log
ALL TESTS PASSED
```

#### tb_control_fsm

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_control_fsm -Sources @('src\control_fsm.sv','sim\tb_control_fsm.sv')
```

```text
Reset aborts checked in all six compute states, plus reset during done.
Reset release with start high waited for the next rising edge.
Runs: 64; reset-abort phases: 6; reset sequences: 8.
Control-vector checks completed: 1096; failures: 0.
ALL TESTS PASSED
$finish called at time : 5476 ns : File "C:/Users/petet/twinmac-oled/sim/tb_control_fsm.sv" Line 219
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 14:17:07 2026...
Verification log: C:\Users\petet\twinmac-oled\sim\logs\tb_control_fsm.run.log
ALL TESTS PASSED
```

#### tb_twinmac_core

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_twinmac_core -Sources @('src\clamp.sv','src\mac_unit.sv','src\weight_sr.sv','src\control_fsm.sv','src\twinmac_core.sv','sim\tb_twinmac_core.sv')
```

```text
Random cases completed: 10000; all 64 busy-start masks exercised.
Reset aborts: six phases; all registers cleared; weights retained.
Completed results: 10045; reset sequences: 8.
Core-state checks completed: 1582858; failures: 0.
ALL TESTS PASSED
$finish called at time : 7914296 ns : File "C:/Users/petet/twinmac-oled/sim/tb_twinmac_core.sv" Line 312
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 14:17:16 2026...
Verification log: C:\Users\petet\twinmac-oled\sim\logs\tb_twinmac_core.run.log
ALL TESTS PASSED
```

#### tb_twinmac

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_twinmac -Sources @('src\clamp.sv','src\mac_unit.sv','src\weight_sr.sv','src\control_fsm.sv','src\twinmac_core.sv','src\tt_um_troypeters42_twinmac.sv','sim\tb_twinmac.sv')
```

```text
Reset, retained weights, zeroed inputs, and aborted run checked.
Exact wrapper latency checked.
Completed chip-pin results: 35.
Chip-pin checks completed: 18056; failures: 0.
ALL TESTS PASSED
$finish called at time : 337111 ns : File "C:/Users/petet/twinmac-oled/sim/tb_twinmac.sv" Line 281
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 14:17:22 2026...
Verification log: C:\Users\petet\twinmac-oled\sim\logs\tb_twinmac.run.log
ALL TESTS PASSED
```

#### tb_oled_ctrl

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_oled_ctrl -Sources @('fpga\oled_ctrl.sv','sim\oled_spi_monitor.sv','sim\tb_oled_ctrl.sv')
```

```text
Time resolution is 1 ps
run -all
Power-ups: 2; safe shutdowns: 1; user frames: 3.
OLED controller checks: 1031; SPI/power checks: 871083; failures: 0.
ALL TESTS PASSED
$finish called at time : 4256470 ns : File "C:/Users/petet/twinmac-oled/sim/tb_oled_ctrl.sv" Line 79
exit
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 14:17:30 2026...
Verification log: C:\Users\petet\twinmac-oled\sim\logs\tb_oled_ctrl.run.log
ALL TESTS PASSED
```

#### tb_nexys_top

```powershell
& .\sim\run_xsim.ps1 -Testbench tb_nexys_top -Sources @('src\clamp.sv','src\mac_unit.sv','src\weight_sr.sv','src\control_fsm.sv','src\twinmac_core.sv','src\tt_um_troypeters42_twinmac.sv','fpga\oled_ctrl.sv','fpga\oled_map.sv','fpga\oled_text.sv','fpga\nexys_top.sv','sim\oled_spi_monitor.sv','sim\tb_nexys_top.sv')
```

```text
Completed maps: 14; Boolean results: 67795; requested cases: 37.
FPGA pin/protocol checks: 10601368; SPI/power checks: 8644114; failures: 0.
ALL TESTS PASSED
$finish called at time : 45560670 ns : File "C:/Users/petet/twinmac-oled/sim/tb_nexys_top.sv" Line 522
run: Time (s): cpu = 00:00:00 ; elapsed = 00:00:51 . Memory (MB): peak = 195.672 ; gain = 0.000
exit
INFO: xsimkernel Simulation Memory Usage: 31104 KB (Peak: 31104 KB), Simulation CPU Usage: 42280 ms
INFO: [Common 17-206] Exiting xsim at Thu Nov  5 14:18:34 2026...
Verification log: C:\Users\petet\twinmac-oled\sim\logs\tb_nexys_top.run.log
ALL TESTS PASSED
```

### Required OLED mutation results

Each mutation changed one file in a disposable temporary copy, using the
unchanged final tests. All eight failed an intended assertion with runner
exit 1. None was accepted merely for a compile error or watchdog timeout.
The unmutated worktree passed before mutation testing. No mutated source
was copied into this worktree. Full diffs, commands, and logs are included
in the review packet.

| Mutation | Testbench | First actual assertion | Result |
| --- | --- | --- | --- |
| Swap map x1/x2 pin stimulus | tb_nexys_top | Mismatch (map stimulus x1 fast, x2 slow) at 11676000 | Detected, exit 1 |
| Use threshold 17 instead of 16 | tb_nexys_top | Mismatch (frame gate=0 mode=0 byte=16 expected=01 got=00) at 2546490000 | Detected, exit 1 |
| Store map with vertically flipped rows | tb_nexys_top | Mismatch (frame gate=0 mode=0 byte=16 expected=01 got=00) at 2546490000 | Detected, exit 1 |
| Flip one bit in AND map bias E1 to E0 | tb_nexys_top | Mismatch (all 72 bits form an approved preset) at 10836000 | Detected, exit 1 |
| Invert displayed Boolean Y digit | tb_nexys_top | Mismatch (frame gate=0 mode=0 byte=312 expected=00 got=3e) at 2546490000 | Detected, exit 1 |
| CPU RESET cuts VDD while VBAT is on | tb_nexys_top | OLED mismatch (VDD off after VBAT wait and reset low), cycle=3704947 phase=9 | Detected, exit 1 |
| Enable VBAT before initialization completes | tb_oled_ctrl | OLED mismatch (VBAT on only after all init commands), cycle=328 phase=5 | Detected, exit 1 |
| Skip the 3.5 second discharge wait | tb_oled_ctrl | OLED mismatch (3.5 s VBAT-off wait before reset low), cycle=254818 phase=11 | Detected, exit 1 |

Disposable copies and their complete logs are under:

```text
C:\Users\petet\AppData\Local\Temp\TwinMAC-Step9-Work\mutations
```

### Actual FPGA build and what it proves

The unchanged build script ran once on the final source and exited 0 with
BUILD PASSED. It synthesized, placed, routed, checked timing, wrote the
checkpoint, and wrote the OLED bitstream. No timing exceptions, extra
pipeline, ASIC source edit, or retry after a timing failure was needed.

```powershell
& 'C:\Xilinx\Vivado\2024.2\bin\vivado.bat' -mode batch -source fpga/build.tcl -log fpga/build/vivado.log -journal fpga/build/vivado.jou
```

| Measure | Routed OLED build |
| --- | ---: |
| Part | xc7a200tsbg484-1 |
| Clock | 100 MHz, 10 ns, one clock |
| Worst setup slack | +0.720 ns |
| Setup TNS / failing endpoints | 0 / 0 |
| Worst hold slack | +0.045 ns |
| Hold THS / failing endpoints | 0 / 0 |
| Total LUTs | 728 |
| Logic LUTs | 696 |
| LUTRAMs (included in total LUTs) | 32 |
| Flip-flops | 384 |
| Occupied slices | 248 |
| BRAM / DSP | 0 / 0 |
| IOB / BUFGCTRL | 24 / 1 |
| DRC errors / warnings | 0 / 2 |

Worst setup starts at chip/core/controller/FSM_onehot_state_reg[2]/C
and ends at chip/core/mac0/acc_reg[16]/D. Data-path delay is 9.330 ns,
with 4.095 ns logic and 5.235 ns routing; clock skew is -0.024 ns.
The complete expanded clock path and hold paths are in the packet.

The routed checkpoint retains bits [4:0] of both chip/x1_reg_reg and
chip/x2_reg_reg. Bits [7:5] are removed. Unlike the earlier Boolean-only
image, this image exercises positive 5-bit inputs and the new map presets.
It still does not exercise negative or full-range signed inputs in hardware.
The original full-range RTL and extreme gate-level gl_test results remain
separate evidence; these FPGA results do not establish full 8-bit arithmetic
at 100 MHz. Troy reports that the existing board test worked. No
OLED-specific hardware result is claimed without its checklist observations.

An FPGA-only use_dsp=yes instance attribute requests DSP mapping without
changing ASIC RTL. Vivado nevertheless reports zero DSP blocks in both
synthesis and routed utilization. The log does not state why, so no mapping
reason is claimed. Actual resource counts take precedence over that hint.
AMD documents the attribute and its propagation in [UG901](https://docs.amd.com/r/2024.2-English/ug901-vivado-synthesis/Synthesis-Attribute-Propagation-Rules).

The hierarchy table below comes from the routed checkpoint. Total rows
include their descendants, and LUT counts are placement/mapping results,
not functional module sizes: Vivado can move/combine logic across hierarchy.
The chip has 166 flip-flops; the FPGA host/display together have 218, total
384. The bitmap is distributed RAM rather than 1024 individual flip-flops.

```text
+--------------------+----------------------------+------------+------------+---------+------+-----+--------+--------+------------+
|      Instance      |           Module           | Total LUTs | Logic LUTs | LUTRAMs | SRLs | FFs | RAMB36 | RAMB18 | DSP Blocks |
+--------------------+----------------------------+------------+------------+---------+------+-----+--------+--------+------------+
| nexys_top          |                      (top) |        728 |        696 |      32 |    0 | 384 |      0 |      0 |          0 |
|   (nexys_top)      |                      (top) |         99 |         99 |       0 |    0 | 120 |      0 |      0 |          0 |
|   bitmap           |                   oled_map |         42 |         10 |      32 |    0 |   0 |      0 |      0 |          0 |
|   chip             | tt_um_troypeters42_twinmac |        226 |        226 |       0 |    0 | 166 |      0 |      0 |          0 |
|     (chip)         | tt_um_troypeters42_twinmac |         11 |         11 |       0 |    0 |  27 |      0 |      0 |          0 |
|     core           |               twinmac_core |        215 |        215 |       0 |    0 | 139 |      0 |      0 |          0 |
|       (core)       |               twinmac_core |          1 |          1 |       0 |    0 |  25 |      0 |      0 |          0 |
|       clamp0       |                      clamp |          0 |          0 |       0 |    0 |   0 |      0 |      0 |          0 |
|       clamp1       |                    clamp_0 |          0 |          0 |       0 |    0 |   0 |      0 |      0 |          0 |
|       controller   |                control_fsm |        104 |        104 |       0 |    0 |   8 |      0 |      0 |          0 |
|       mac0         |                   mac_unit |         37 |         37 |       0 |    0 |  17 |      0 |      0 |          0 |
|       mac1         |                 mac_unit_1 |         27 |         27 |       0 |    0 |  17 |      0 |      0 |          0 |
|       weight_store |                  weight_sr |         50 |         50 |       0 |    0 |  72 |      0 |      0 |          0 |
|   display_ctrl     |                  oled_ctrl |        357 |        357 |       0 |    0 |  90 |      0 |      0 |          0 |
|   render           |                  oled_text |          6 |          6 |       0 |    0 |   8 |      0 |      0 |          0 |
+--------------------+----------------------------+------------+------------+---------+------+-----+--------+--------+------------+
* Note: The sum of lower-level cells may be larger than their parent cells total, due to cross-hierarchy LUT combining
```

### Packing warnings and external I/O timing limits

The exact IDs PDRC-144 and PDRC-146 do not appear in this build. The same
C6/C5 and D6/D5 warning families remain under PDRC-136 and PDRC-138 at
different sites. Renumbering does not establish a fix or show they are
harmless. Their full text is:

```text
PDRC-136#1 Warning
SLICE_PairEqSame_C6C5_WARN
Luts C6LUT and C5LUT in use in site SLICE_X15Y86 with different equations without A6 pin connected to Global Logic High.
Related violations: <none>

PDRC-138#1 Warning
SLICE_PairEqSame_D6D5_WARN
Luts D6LUT and D5LUT in use in site SLICE_X9Y83 with different equations without A6 pin connected to Global Logic High.
Related violations: <none>
```

A read-only inspection of the existing routed checkpoint found no named
logical cells on these physical LUT BELs. At SLICE_X15Y86, the physical
C6 equation is O6=(A6+~A6)*(0), and C5 is O5=(A2). At SLICE_X9Y83,
D6 is O6=(A6+~A6)*(1), and D5 is O5=(A1). The A6 pin-net queries
returned no net at both sites. The packet includes this raw evidence;
it does not establish hardware behavior or waive either warning.

The timing report has nine inputs without input delays: btnc, cpu_resetn,
and sw[0] through sw[6]. Fourteen outputs have no output delays: led[0]
through led[7] and the six OLED pins. No false paths were added. Thus the
positive setup/hold results establish the constrained internal timing;
they do not prove an external I/O timing budget, eliminate asynchronous
metastability, or replace board checks. The synchronizers and SPI/power
simulation checks address behavior, with physical validation still pending.

### Build identity and protection of existing work

All 12 exact build inputs below retain their pre-build SHA-256 and file
modification time after the build. This includes the unchanged build script.
The reviewed source therefore matches the source used for this bitstream.

| Build input | SHA-256 of exact local bytes |
| --- | --- |
| src/clamp.sv | 264eb6a5729053d4835a1de05f98720b49f1537c5aa225a057368d5e99e24431 |
| src/control_fsm.sv | 253b161f8303bfe7df546fa5fe26740b246b0ad92caa7d4e53502de89b49eca8 |
| src/mac_unit.sv | d86df558365821814f8c0a0d94b1521b09ed70c71ded43741fd6bfb216ef7f9b |
| src/tt_um_troypeters42_twinmac.sv | bb94e0e5e915bb0916d40957d9fb97c02337d4d519d719d9bad7a92b6eb9c6bc |
| src/twinmac_core.sv | 3b04ccaaec0b890f7564b43b1330c88b54afcd3046bf73077b8d0c189ea7e2b9 |
| src/weight_sr.sv | f8daa892427aee201106b62b9a2d8a50a4cce3d835a5c268a3b764981832422e |
| fpga/nexys_top.sv | 00be46ebb9a57ace945762514d9fa5c2369000784e17bbdfeefb28d7f1ee7bab |
| fpga/oled_ctrl.sv | 6f675714675231d8fb27f90667fbf331f36aa6e92317aea416778a8cf0d261ab |
| fpga/oled_map.sv | 560efd76970bdf9a0f12fc90bfe2899519d186cf43806f35e0b59c0333f44e1d |
| fpga/oled_text.sv | 2b2af268526dd34e7f1be3ae71a3c3c8bafe4be6a0b8c40e6937463d0124e7d7 |
| fpga/twinmac.xdc | 7c75f43f2a08a4c5fe246cfb025ec8bd609046e56dda8e84f0abc300d3e5a53f |
| fpga/build.tcl | 2eb5601a83484e2181027605d143387673d1a2a533ac7f18b25adba4fa1f9062 |

OLED bitstream: C:\Users\petet\twinmac-oled\fpga\build\nexys_top.bit

```text
92bc134db12484854d3db658e53356d00f36530afd86b7d552c42ca0aaae3c35
```

Size: 9730758 bytes. Routed checkpoint SHA-256:

```text
b74cecc288b12a54b7b342e66d044c5c817dbe9bfadb962b55e8a50355cfbf07
```

The 14 protected files under src/, test/, and info.yaml match
e8e710e in canonical Git content, including src/config.json. Windows Git
checked them out with CRLF; the manifest records raw checkout hashes and
LF Git-content hashes separately. No protected file was edited to alter
its line endings. Their raw checkout hashes also remain unchanged.

All 52 snapshotted original tracked/build files retain their exact
bytes and modification times. The original worktree is clean; rtl remains
e8e710e and main remains 162764d. The original plain bitstream remains:

```text
C:\Users\petet\twinmac\fpga\build\nexys_top.bit
SHA-256: 28671ec5ddfc03038b709f643b2ff6664eec0a6069a8f4544085cc45916d760b
```

The original step 8 four-case MAC 1 coverage and +0.606 ns timing result
describe that earlier plain image. They must not be carried over to this
new image. This OLED image uses different map weights and a 0..31 sweep.
Its own board acceptance checklist follows. Every observation is pending.

### OLED board acceptance checklist

All results below are predicted. No board has been programmed or observed by Codex.
Record what you actually see in the blanks. Use this checklist only after reviewing
and accepting the OLED build. The original plain-demo bitstream remains separate.

1. With the board off, set JP4 to JTAG.
2. Connect 12 V power to J21 and micro-USB from PROG (J12) to the computer.
3. Power on with SW8 and confirm the OLED stays dark. If it lights up, stop. Do not
   reprogram it or power it off until the running image's shutdown step is identified.

OLED dark before programming: ______  Date / observer: ____________________

#### Program the reviewed OLED image

- [ ] Leave CPU RESET and BTNC released. Set gate SW[4:2]=000 (AND), SW0=0, SW1=0.
- [ ] Set SW[6:5]=01: SW6 off, SW5 on, for the first bring-up stage.
- [ ] Manually program C:\Users\petet\twinmac-oled\fpga\build\nexys_top.bit.
- [ ] Confirm the selected file is from twinmac-oled, not the retained plain build
      at C:\Users\petet\twinmac\fpga\build\nexys_top.bit.
- [ ] Allow one second for the power sequence and first map/frame to settle.

Reviewed OLED bitstream SHA-256:

```text
92bc134db12484854d3db658e53356d00f36530afd86b7d552c42ca0aaae3c35
```

Selected file / hash checked: ______________________________________________
Programming result and first visible image: _______________________________

#### Three bring-up stages, in order

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

#### Six real-chip decision maps

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
uses the specified A0/C0 orientation and has not been verified on this board.
Observed map orientation / any mismatch: __________________________________

#### Live Boolean text and LEDs

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
- [ ] Hold CPU RESET while the OLED is on. LEDs should clear, but the OLED should
      keep its power and last displayed frame. Release it and allow a new sweep;
      the normal live display should return without an OLED power cycle.

CPU RESET / gate-change / LED observations: ________________________________

#### BTNC shutdown and restart

- [ ] During normal display, press BTNC once for about 50 ms and release it.
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

#### Before any reprogramming or power-off

If shutdown has already completed and the OLED remains off, leave it off;
pressing BTNC again would restart it. Otherwise, with the OLED running:

Press BTNC once for about 50 ms, release, and wait at least FOUR SECONDS.
Confirm the OLED remains dark. Only then reprogram the FPGA or turn power off.
If the display does not stay dark, stop; do not reprogram or power off until
its shutdown state is understood.

Final shutdown performed / wait / observed result: _________________________
All three bring-up stages confirmed by: ____________________________________
All six maps and 24 Boolean cases confirmed by: ____________________________

### Step 9 approval and commit

On Nov 5, 2026, Troy wrote: "Board test worked and I'm ready for OLED
implementation and commit". This authorizes committing the reviewed OLED
implementation. The board report is recorded as a general pass, without
inventing individual observations or marking unreported OLED stages as
complete. The OLED bring-up, map/text, reset, and shutdown/restart checks
remain pending explicit hardware observations.

The 12 build inputs and both bitstreams were rechecked against the review
manifest before commit and remain unchanged. All 16 FPGA/test/runner text
files match the review packet. The existing eight passing xsim logs and
eight detected mutation results were checked again; no source or test was
changed after those runs, so no additional simulation or rebuild was needed.

The approved files are committed on oled only. rtl and main remain at
e8e710e and 162764d, respectively; no push or merge is included. No Icarus,
Yosys, new ASIC build, or new gate-level run is claimed for this FPGA-only
addition. The original ASIC signoff limitations remain unchanged.
