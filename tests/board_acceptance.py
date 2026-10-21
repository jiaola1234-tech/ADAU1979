"""UART acceptance helper; requires pyserial and a programmed/running dual_capture.elf.

Run: python tests/board_acceptance.py --port COM5 --seconds 60
This checks continuous digital acquisition counters. Physical channel injection
and address/SDATA wiring checks remain a separate manual acceptance step.
"""
import argparse
import re
import time
from pathlib import Path

import serial

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--port", required=True)
parser.add_argument("--baud", type=int, default=115200)
parser.add_argument("--seconds", type=float, default=60)
parser.add_argument("--output", type=Path, default=Path("build/board-acceptance.txt"))
args = parser.parse_args()
if args.seconds < 60:
    parser.error("Acceptance requires at least 60 seconds of progress samples")
args.output.parent.mkdir(parents=True, exist_ok=True)
progress = []
log = []
started = None
passed = False
with serial.Serial(args.port, args.baud, timeout=0.2) as uart:
    # The application retains the existing s/r start prompt. No per-packet reset.
    uart.write(b"s")
    deadline = time.monotonic() + args.seconds + 30
    try:
        while time.monotonic() < deadline:
            line = uart.readline().decode("ascii", errors="replace").strip()
            if not line:
                continue
            log.append(line)
            if "INIT FAIL" in line or "init failed" in line or "DMA stalled" in line or "DMA interrupt error" in line:
                raise RuntimeError(line)
            if not line.startswith("ring-progress "):
                continue
            values = dict(re.findall(r"(\w+)=(0x[0-9a-fA-F]+|[0-9a-fA-F]+)", line))
            item = {key: int(values[key], 16 if key == "DMASR" else 0)
                    for key in ("dma_blocks", "fifo_overflows", "i2s_sync_err", "i2c_ack_err", "DMASR")}
            now = time.monotonic()
            if started is None:
                started = now
            if progress:
                if item["dma_blocks"] <= progress[-1]["dma_blocks"]:
                    raise RuntimeError("DMA block count stopped increasing")
                for key in ("fifo_overflows", "i2s_sync_err", "i2c_ack_err"):
                    if item[key] != progress[0][key]:
                        raise RuntimeError(f"{key} increased")
            if item["i2c_ack_err"] or item["DMASR"] & 0x70:
                raise RuntimeError("I2C/DMA error")
            progress.append(item)
            print(line, flush=True)
            if now - started >= args.seconds:
                passed = True
                break
        if not passed:
            raise RuntimeError("Insufficient continuous progress samples")
        print(f"PASS UART counters for {args.seconds:g}+ seconds; physical channel mapping still needs signal injection")
    finally:
        uart.write(b"q")
        args.output.write_text("\n".join(log) + "\n", encoding="utf-8")
