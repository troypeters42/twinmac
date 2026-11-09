# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.triggers import Timer


class Pins:
    def __init__(self, dut):
        self.dut = dut
        self.control = 0
        self.y = 0
        self.flag = False
        self.results = 0
        dut.clk.value = 0
        dut.rst_n.value = 0
        dut.ena.value = 1
        dut.ui_in.value = 0
        dut.uio_in.value = 0

    def pin(self, bit, value):
        self.control = (self.control & ~(1 << bit)) | (value << bit)
        self.dut.uio_in.value = self.control

    async def tick(self, cycles=1):
        # A slow functional clock allows UNIT_DELAY gate models to settle.
        for _ in range(cycles):
            self.dut.clk.value = 0
            await Timer(500, unit="ns")
            self.dut.clk.value = 1
            await Timer(500, unit="ns")
            assert int(self.dut.uio_oe.value) == 0, "UIO output enables must stay zero"
            assert int(self.dut.uio_out.value) == 0, "UIO outputs must stay zero"

    def check(self, y, flag, context):
        expected = (int(flag) << 7) | y
        actual = int(self.dut.uo_out.value)
        assert actual == expected, f"{context}: expected 0x{expected:02x}, got 0x{actual:02x}"

    async def reset(self):
        self.control = 0
        self.dut.uio_in.value = 0
        self.dut.rst_n.value = 0
        self.y = 0
        self.flag = False
        await Timer(50, unit="ns")
        self.check(0, False, "asynchronous reset without a clock edge")
        await self.tick(5)
        self.dut.rst_n.value = 1
        await self.tick(5)
        self.check(0, False, "reset release")

    async def pulse(self, bit):
        self.pin(bit, 1)
        await self.tick(5)
        self.pin(bit, 0)
        await self.tick(5)

    async def weights(self, word):
        for bit in range(71, -1, -1):
            self.pin(0, (word >> bit) & 1)
            await self.tick(5)
            await self.pulse(1)
            self.check(self.y, self.flag, "weight loading must hold output and flag")

    async def latch(self, pin, value):
        self.dut.ui_in.value = value & 0xFF
        await self.tick(5)
        await self.pulse(pin)
        self.check(self.y, self.flag, "input latching must hold output and flag")

    async def start_result(self, wanted):
        self.pin(2, 1)
        await self.tick(5)
        self.check(self.y, False, "start must clear the old done flag")
        self.flag = False
        self.pin(2, 0)
        await self.tick(5)
        for _ in range(20):
            if int(self.dut.uo_out.value) & 0x80:
                break
            await self.tick()
        self.check(wanted, True, "completed result")
        self.y = wanted
        self.flag = True
        await self.tick(5)
        self.check(wanted, True, "done flag must remain set")
        self.results += 1

    async def case(self, x1, x2, wanted):
        await self.latch(3, x1)
        await self.latch(4, x2)
        self.dut.ui_in.value = 0xA6
        await self.tick(5)
        await self.start_result(wanted)


@cocotb.test(timeout_time=100, timeout_unit="ms")
async def test_twinmac_pins(dut):
    pins = Pins(dut)
    await pins.reset()
    # Expected outputs are literal truth-table entries in (00, 01, 10, 11) order.
    gates = (
        (0x000100FF0101000101, (0, 0, 0, 1)),
        (0x00FF01FF0101000101, (0, 1, 1, 1)),
        (0x00FE01FF0101000101, (0, 1, 1, 0)),
        (0x01FF00FF0101000101, (1, 1, 1, 0)),
        (0x0101FFFF0101000101, (1, 0, 0, 0)),
        (0x0102FFFF0101000101, (1, 0, 0, 1)),
    )
    for word, truth in gates:
        await pins.weights(word)
        for index, wanted in enumerate(truth):
            dut.ena.value = index & 1
            await pins.case(index // 2, index % 2, wanted)
    dut._log.info("All 24 gate truth-table cases passed through chip pins")

    corners = (
        (0x0000010000007F8080, -128, -128, 127),
        (0x0001007F8080000000, -128, -128, 127),
        (0x050001000000807F7F, -128, -128, 5),
        (0x7F7F7F0000007F7F7F, 127, 127, 127),
        (0x000001000000400000, 0, 0, 64),
        (0x000100400000000000, 0, 0, 64),
        (0x000001000000000302, 5, 7, 31),
        (0x0000010000000A03FE, -4, 2, 24),
    )
    for word, x1, x2, wanted in corners:
        await pins.weights(word)
        await pins.case(x1, x2, wanted)

    # Last weights implement max(0, 10 - 2*x1 + 3*x2), capped at 127.
    await pins.reset()
    await pins.start_result(10)
    pins.pin(2, 1)
    await pins.tick(5)
    pins.check(10, False, "in-flight run before reset abort")
    await pins.reset()
    await pins.tick(15)
    pins.check(0, False, "aborted run must not produce a stale done flag")
    await pins.start_result(10)
    assert pins.results == 34
    dut._log.info("All 34 chip-pin results passed, including reset and retained weights")
