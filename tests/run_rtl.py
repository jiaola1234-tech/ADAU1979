"""Execute the real RTL with Vivado 2022.2 XSim; no mocked I2C engines."""
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
tool_dir = os.environ.get("VIVADO_BIN")
if not tool_dir:
    found = shutil.which("xvlog.bat") or shutil.which("xvlog")
    tool_dir = str(Path(found).parent) if found else None
if not tool_dir:
    sys.exit("Set VIVADO_BIN to the Vivado 2022.2 bin directory, or add it to PATH.")
BIN = Path(tool_dir)
RUN = ROOT / "tests/.run"
RUN.mkdir(exist_ok=True)


def call(tool, args, label):
    suffix = ".bat" if os.name == "nt" else ""
    result = subprocess.run(
        [str(BIN / (tool + suffix)), *map(str, args)],
        cwd=RUN, capture_output=True, text=True, timeout=180,
    )
    output = result.stdout + result.stderr
    (RUN / (label + ".log")).write_text(output)
    if result.returncode:
        sys.exit(output[-6000:])
    return output


sources = sorted((ROOT / "ip_repo/adau1979_capture_1.0/hdl").glob("*.v"))
benches = [ROOT / "tests" / name for name in ("init_tb.sv", "stream_tb.sv", "axi_tb.sv")]
call("xvlog", ["--sv", *sources, *benches], "compile")
summary = []
for top, scenarios in (
    ("init_tb", range(7)), ("init_master1_tb", [0]), ("init_single_tb", [0]),
    ("stream_tb", [0]), ("stream_swap_tb", [0]), ("stream_single_tb", [0]),
    ("axi_tb", [0, 1]),
):
    call("xelab", [top, "-s", top], "elaborate_" + top)
    for scenario in scenarios:
        output = call("xsim", [top, "-runall", "-testplusarg", f"scenario{scenario}"],
                      f"{top}_{scenario}")
        passed = [line for line in output.splitlines() if line.startswith("PASS ")]
        if not passed or "Fatal:" in output or "Error:" in output:
            sys.exit(output[-6000:])
        summary.extend(passed)
        print("\n".join(passed), flush=True)
summary.append("ALL RTL TESTS PASS")
(RUN / "summary.txt").write_text("\n".join(summary) + "\n")
print(summary[-1])
