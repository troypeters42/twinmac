# TwinMAC RTL notes

## Current status

- Date: Nov 4, 2026.
- Repository: C:\Users\petet\twinmac.
- Working branch: rtl, created locally from origin/main at 162764d.
- Step 1 is complete; Troy reproduced the passing test and approved it on Nov 4, 2026.
- Step 1 is committed and pushed on rtl.
- Step 2 is committed as fec9360 and pushed on rtl.
- Step 3 is committed as 4489ce1 and pushed on rtl.
- Step 4 passed xsim and was approved by Troy on Nov 4, 2026.

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
Python model remains out of scope. Keep the OLED off until optional step 9.

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
