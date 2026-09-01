# xinghuo-npu

[中文说明](README.md)

This is your design directory. In normal use, you only edit the RTL and the
two test files. You do not need to change `FrameTop.sv` or the root RTL files.

## Files in this directory

| File | Purpose | Edit it? |
| --- | --- | --- |
| `rtl/XinghuoNpu.sv` | Your circuit | Yes; replace the example logic |
| `tests/XinghuoNpuTb.sv` | Tests only your circuit | Yes; check your real behavior |
| `tests/FrameXinghuoNpuTb.sv` | Tests your circuit through the full frame | Yes; check pins and design selection |
| `design.json` | Tells the build tools where sources and tests are | Usually no |

The design name is `xinghuo-npu`, and the top module is `XinghuoNpu`. Users do
not assign a design ID. Frame tests use an automatic temporary ID, and a
maintainer assigns the permanent ID during integration.

## Step 1: Implement the circuit

Open `rtl/XinghuoNpu.sv` and replace the example logic. Keep the five top-level
ports. They are the fixed connection between your circuit and the frame:

- `clock`: clock input. A combinational circuit may ignore it, but keep it.
- `reset`: reset input. A circuit without reset may ignore it, but keep it.
- `io_in[65:0]`: 66 input values read from the external pins.
- `io_out[65:0]`: 66 values your circuit wants to send to external pins.
- `io_oe[65:0]`: output switches. Bit `n` must be 1 to drive pin `n`.

`io_*[n]` maps to `user_io[n + 7]` at the chip top. For example, `io_in[0]`
maps to `user_io[7]`.

## Step 2: Update the tests

Both TB files mark the sections that are normally kept and the sections that
you should edit for your design.

First update `tests/XinghuoNpuTb.sv`, then run:

```sh
make user-lint
make user-test
```

The test passes only when its `$display` prints `PASS` and make exits normally.

## Step 3: Test the FrameTop connection

Do not edit `designs/registry.json`. The build tool automatically assigns a
temporary ID to an unregistered design:

```sh
make user-frame-test
```

Every Frame test automatically checks for overlap between external
`test_io_oe` and design `io_oe`. Keep the `reset`, `test_io_oe`, and `dut`
names in the Frame TB. The simulation fails if both sides enable any payload
bit, even when they drive the same value.

Before submitting, run:

```sh
make user-check
```

The current frame requires Verilator 5.050. The build scripts probe
nonessential warning flags before using them.

See `../../docs/en/user-guide.md` for the complete English workflow.
