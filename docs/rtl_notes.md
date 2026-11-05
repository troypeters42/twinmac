# TwinMAC RTL notes

## Current status

- Date: Nov 4, 2026.
- Repository: C:\Users\petet\twinmac.
- Working branch: rtl, created locally from origin/main at 162764d.
- Step 1 is complete; Troy reproduced the passing test and approved it on Nov 4, 2026.
- Step 1 is committed and pushed on rtl.
- Step 2 is committed as fec9360 and pushed on rtl.
- Step 3 is committed as 4489ce1 and pushed on rtl.
- Step 4 is committed as 6027a6d and pushed on rtl.
- Step 5 passed the requested MAC 1 corner rerun and was approved for commit and push.

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
