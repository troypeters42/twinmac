![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg)

# TwinMAC

Gabriel Hoda, Troy Peters, Nicholas Grieco

ECE 492, SUNY Poly, Fall 2026

TwinMAC is a three-neuron integer ReLU network built from two shared
multiply-accumulate units. Loading different weights lets the same hardware
compute AND, OR, XOR, NAND, NOR, and XNOR. The ASIC accepts signed 8-bit
inputs and weights, forms signed 16-bit products, accumulates in 17 bits,
and clamps each completed neuron to 0 through 127. One inference takes
six compute clock edges after the core accepts start.

The Nexys Video demo runs the chip wrapper at 100 MHz. Its OLED shows a
32-by-32 decision map and the selected gate's Boolean inputs and result.
The map uses nonnegative inputs from 0 through 31. The full signed input
range is verified in simulation, including extreme vectors on the
gate-level netlist; the FPGA demo does not exercise that full range.

## Results

These values are copied from [the RTL notes](docs/rtl_notes.md). ASIC
results come from commit `93ed933`, GDS run
[41988729116](https://github.com/troypeters42/twinmac/actions/runs/41988729116).
The accepted ASIC configuration is retained on `rtl` at `e8e710e`.
FPGA results are for the board-tested OLED Part 2 image recorded in
`68f0e0b`.

| Measurement | Result |
| --- | ---: |
| ASIC standard-cell area | 20,835.0 um^2 |
| ASIC standard-cell count | 2,223 |
| ASIC standard-cell utilization of core | 60.8226% |
| ASIC setup worst slack, max_ss_100C_1v60 | +0.932191 ns |
| ASIC hold worst slack, min_ff_n40C_1v95 | +0.115010 ns |
| ASIC STA-derived maximum frequency | 52.444411 MHz |
| ASIC total power, nom_tt_025C_1v80 | 4.647541326 mW |
| ASIC open max-slew / max-fanout counts | 303 / 1 |
| OLED FPGA setup / hold slack at 100 MHz | +0.867 / +0.043 ns |
| OLED FPGA worst recovery / removal slack | +5.213 / +0.647 ns |
| OLED FPGA LUTs / flip-flops / LUTRAM | 731 / 384 / 32 |
| OLED FPGA DSP / BRAM | 0 / 0 |
| OLED FPGA DRC violations / PDRC packing warnings | 0 / 0 |
| OLED FPGA methodology warnings | 23 TIMING-18 |

The ASIC meets setup and hold at all nine analyzed corners. Detailed-route
DRC, Magic DRC, LVS, and antenna checks report zero violations, and the
Tiny Tapeout precheck and gate-level test passed. The layout has 303 max-slew warnings, worst 1.199 ns against the flow's 0.75 ns guideline. That is inside the library's 1.5 ns limit, and static timing already includes these slow edges. There is also one max-fanout warning on the clock-tree root, documented as a waiver (worst transition 0.218 ns). Configuration-only fixes were tried and not adopted; see the [slew and fanout section of docs/rtl_notes.md](docs/rtl_notes.md#slew-and-fanout-investigation-nov-8-2026). KLayout DRC is disabled in the build;
precheck runs its own Magic and KLayout checks.

The ASIC clock remains 20 ns (50 MHz). The maximum frequency is derived
from routed static timing, not measured on silicon. Power is an OpenSTA
estimate at nominal RC, typical process, 25 C, 1.80 V, and 50 MHz, using
the default activity assumptions described in the notes. It is not a
workload or board-power measurement.

All eight xsim testbenches passed for OLED Part 2, and all fourteen OLED
mutations were detected. The plain and OLED board checklists passed on Nov 5, 2026, and the
OLED Part 2 checklist passed on Nov __, 2026 (observer: Troy). Its 23 methodology warnings
concern missing external I/O delays; internal timing closure does not
establish an external I/O timing budget.

## Repository map

| Directory | Contents |
| --- | --- |
| `src/` | ASIC SystemVerilog: clamp, MAC, weight register, controller, core, chip wrapper, and physical-flow configuration |
| `test/` | cocotb chip-pin tests shared by RTL and gate-level CI |
| `sim/` | Eight Vivado testbenches, OLED SPI monitor, and the xsim runner |
| `fpga/` | Nexys Video host, OLED logic, pin constraints, and Vivado build script |
| `docs/` | Chip description, implementation and verification notes, and the OLED board checklist |

See [docs/info.md](docs/info.md) for chip pins and the host test procedure,
[docs/rtl_notes.md](docs/rtl_notes.md) for the design and measured results,
and [the OLED board checklist](docs/oled_board_checklist.md) for programming
and safe shutdown.

## Rerun the simulations

Use Vivado 2024.2 on Windows. Run these commands from the repository root.
The runner defaults to `C:\Xilinx\Vivado\2024.2\bin`; pass `-VivadoBin`
to use another installation.

```powershell
$core = @('src\clamp.sv', 'src\mac_unit.sv', 'src\weight_sr.sv',
          'src\control_fsm.sv', 'src\twinmac_core.sv')
$chip = $core + @('src\tt_um_troypeters42_twinmac.sv')
$display = @('fpga\oled_ctrl.sv', 'fpga\oled_map.sv',
             'fpga\oled_text.sv', 'fpga\nexys_top.sv')
$cases = @(
  @{Name='tb_clamp'; Sources=@('src\clamp.sv','sim\tb_clamp.sv')},
  @{Name='tb_mac_unit'; Sources=@('src\mac_unit.sv','sim\tb_mac_unit.sv')},
  @{Name='tb_weight_sr'; Sources=@('src\weight_sr.sv','sim\tb_weight_sr.sv')},
  @{Name='tb_control_fsm'; Sources=@('src\control_fsm.sv','sim\tb_control_fsm.sv')},
  @{Name='tb_twinmac_core'; Sources=($core + @('sim\tb_twinmac_core.sv'))},
  @{Name='tb_twinmac'; Sources=($chip + @('sim\tb_twinmac.sv'))},
  @{Name='tb_oled_ctrl'; Sources=@('fpga\oled_ctrl.sv',
      'sim\oled_spi_monitor.sv','sim\tb_oled_ctrl.sv')},
  @{Name='tb_nexys_top'; Sources=($chip + $display +
      @('sim\oled_spi_monitor.sv','sim\tb_nexys_top.sv'))}
)
foreach ($case in $cases) {
  $sources = [string[]]$case.Sources
  & .\sim\run_xsim.ps1 -Testbench $case.Name -Sources $sources
  if ($LASTEXITCODE -ne 0) { throw "$($case.Name) failed" }
}
```

Each test must finish with `ALL TESTS PASSED` and exit 0. The runner keeps
raw tool logs and a combined verification log under `sim/logs/`.

The separate GitHub `test` job runs the cocotb test using Icarus and the
packages in `test/requirements.txt`. See [test/README.md](test/README.md)
and the [test workflow](.github/workflows/test.yaml).

## Rebuild the Nexys Video image

From the repository root, with Vivado 2024.2 and Artix-7 support installed:

```powershell
New-Item -ItemType Directory -Force .\fpga\build | Out-Null
& 'C:\Xilinx\Vivado\2024.2\bin\vivado.bat' -mode batch `
  -source fpga/build.tcl -log fpga/build/vivado.log `
  -journal fpga/build/vivado.jou
```

The build targets `xc7a200tsbg484-1`, checks setup and hold at 100 MHz, and
writes the routed checkpoint, reports, and `nexys_top.bit` to `fpga/build/`.
Rebuilding does not give a new image the earlier image's board-test result.
Check the image hash and follow the complete board checklist before use.
For safe OLED shutdown, press and release BTNC and wait at least four
seconds after release before reprogramming or removing power.

## Rerun the ASIC flow

Use the existing GitHub Actions workflows on the reviewed branch. A push
starts `test`, `docs`, and `gds`; the `gds` workflow also runs `precheck`,
`gl_test`, and `viewer`. Alternatively, manually dispatch the `gds`
workflow for the selected branch from GitHub Actions.

The flow is configured in [.github/workflows/gds.yaml](.github/workflows/gds.yaml)
and uses `TinyTapeout/tt-gds-action@ttsky26d` with `sky130A`. The design of
record used LibreLane 3.0.14. Keep the 20 ns period, 60% placement density,
2 ns setup-repair margin, and all-corner setup gate unchanged.

Download `GDS_logs` and read the post-route `summary.rpt` at all nine
corners. Compare timing, area, power and physical/electrical violations
with run 41988729116. Passing jobs alone do not establish that every
constraint is met. The six release checks are `test`, `docs`, `gds`,
`precheck`, `gl_test`, and `viewer`; they exclude the optional FPGA job.

## Branches and releases

`main` is the v1.0 release branch. Integration from `release-v1.0` uses a
merge commit so the original commit IDs, including `93ed933` and
`e8e710e`, remain in its history. The annotated `v1.0` tag identifies
the release merge commit; GitHub release `v1.0` carries the board-tested
plain and OLED Part 2 bitstreams with their full SHA-256 hashes.

- `rtl` (`e8e710e`) is the accepted ASIC design and plain demo.
- `oled` (`68f0e0b`) is the OLED demo including the Part 2 reset fix.
- `slew-fix` and `timing-test` are investigation records.

## How this was built

The RTL, tests and notes were written with AI coding assistance (Codex)
under the group's direction, and each step was independently reviewed
before it was accepted. [AGENTS.md](AGENTS.md) records the rules and
workflow; [docs/rtl_notes.md](docs/rtl_notes.md) records every step and review.
