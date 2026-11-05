# TwinMAC RTL notes

## Current status

- Date: Nov 4, 2026.
- Repository: C:\Users\petet\twinmac.
- Working branch: rtl, created locally from origin/main at 162764d.
- Step 1 is complete; Troy reproduced the passing test and approved it on Nov 4, 2026.
- Step 1 is committed and pushed on rtl.
- Step 2 passed xsim and was approved by Troy on Nov 4, 2026.
- Step 3 has not started.

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
