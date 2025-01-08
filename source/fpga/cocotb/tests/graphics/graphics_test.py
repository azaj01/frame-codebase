#
# Authored by: Robert Metchev / Raumzeit Technologies (robert@raumzeit.co)
#
# CERN Open Hardware Licence Version 2 - Permissive
#
# Copyright (C) 2024 Robert Metchev
#
import sys, os, time, random, logging
import numpy as np

import cocotb
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, Timer

from tb_top import SpiTransactor, clock_n_reset


@cocotb.test()
async def spi_test(dut):
    log_level = os.environ.get('LOG_LEVEL', 'INFO') # NOTSET=0 DEBUG=10 INFO=20 WARN=30 ERROR=40 CRITICAL=50
    dut._log.setLevel(log_level)

    # SPI Transactor
    t = SpiTransactor(dut)

    # Start camera clock
    cr = cocotb.start_soon(clock_n_reset(dut.camera_pixel_clock, None, f=36.0*10e6))       # 36 MHz clock

    # Hack/Fix for missing "negedge reset" in verilator, works OK in icarus
    await Timer(10, 'ns')
    dut.spi_select_in.value = 0
    await Timer(10, 'ns')
    dut.spi_select_in.value = 1
    await Timer(10, 'ns')

    
    #   0. Wait for reset
    await Timer(10, units='us')

    #   1. Test single byte read from ID register 0xDB
    a = 0xdb
    id = [0x81]
    read_bytes = await t.spi_read(0xdb)
    assert read_bytes == id , f"ID register {hex(a)}: Expected: {[hex(i) for i in id]}. Received: {[hex(i) for i in read_bytes]}."
    
    #   2. Now lets power up the PLL 0x40/0x41
    await t.spi_write(0x40, 0x1)
    #   Wait for PLL to lock & global reset to kick in - 20ms
    await Timer(20, units='us')
    #   Check PLL lock flag
    a = 0x41
    read_bytes = await t.spi_read(a)
    assert read_bytes == [1] , f"ID register {hex(a)}: Expected: 0x1. Received: {[hex(i) for i in read_bytes]}."

    #   4. Test Graphics
    await Timer(10, units='us') # check buffer status
    read_bytes = await t.spi_read(0x18)
    await t.spi_write(0x12, [
        0x00, 0x32,     # X pos 
        0x00, 0x32,     # Y pos 
        0x00, 0x10,     # Width 
        0x02,           # Total colors
        0x00,           # palette offset
        0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00,
        0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00,
        0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff,
        0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff,
    ])
    await t.spi_command(0x14)
    read_bytes = await t.spi_read(0x18)

    await Timer(25, units='ms')
    await t.spi_write(0x12, [
        0x00, 0x32, 
        0x00, 0x64, 
        0x00, 0x10, 
        0x02, 
        0x00, 
        0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00,
        0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00,
        0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff,
        0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff,
    ])
    await t.spi_command(0x14)
    read_bytes = await t.spi_read(0x18)

    await Timer(25, units='ms')
    #           // Show command
    #           send_opcode('h14);
    #           done();
    #           #5000000
    await Timer(10, units='ms')
    await t.spi_command(0x14)
    await Timer(20, units='ms')
    await t.spi_command(0x14)
    await Timer(20, units='ms')
    await t.spi_command(0x14)
    await Timer(20, units='ms')
    await t.spi_command(0x14)

    # Finish
    await Timer(10, units='ms')
