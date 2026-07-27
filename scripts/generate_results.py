#!/usr/bin/env python3
"""Extract objective simulation results — final SystemC simulated time, byte
counts, and a BT.601 conversion check on sample pixels — and write them
directly into README.md between `<!-- RESULTS:* -->` markers, so the README
never carries hand-copied numbers.

Usage:
    python scripts/generate_results.py <sim_log_path> --readme README.md
"""

import argparse
import re
from pathlib import Path

WIDTH = 1920
HEIGHT = 1080
INPUT_RAW = Path("images/input/image.raw")
OUTPUT_RAW = Path("images/output/output.raw")

TIME_RE = re.compile(r"(\d+(?:\.\d+)?)\s*(ns|us|ms|s)\b")


def parse_final_sim_time(log_text: str) -> str:
    times = TIME_RE.findall(log_text)
    if not times:
        # Un log sin ningún timestamp significa que la simulación no corrió
        # (típicamente porque el build falló antes). Escribir "unknown" en el
        # README esconde el problema: mejor fallar acá.
        raise SystemExit(
            "error: no SystemC timestamp found in the simulation log.\n"
            "       The simulation almost certainly never ran — check the build\n"
            "       output above instead of trusting this step."
        )
    value, unit = times[-1]
    return f"{value} {unit}"


def verify_pixels(rgb: bytes, gray: bytes, positions: list) -> list:
    rows = []
    for p in positions:
        r, g, b = rgb[p * 3], rgb[p * 3 + 1], rgb[p * 3 + 2]
        expected = round(0.299 * r + 0.587 * g + 0.114 * b)
        actual = gray[p]
        rows.append((p, (r, g, b), expected, actual, expected == actual))
    return rows


def data_volume_table(input_bytes: int, output_bytes: int) -> str:
    total = input_bytes + output_bytes
    expected_input = WIDTH * HEIGHT * 3
    expected_output = WIDTH * HEIGHT
    expected_total = expected_input + expected_output
    rows = [
        ("Disk → RAM (input)", expected_input, input_bytes),
        ("RAM → Disk (output)", expected_output, output_bytes),
        ("Total moved", expected_total, total),
    ]
    lines = ["| Transfer | Expected | Actual | Match |", "|---|---|---|---|"]
    for label, expected, actual in rows:
        match = "✅" if expected == actual else "❌"
        lines.append(f"| {label} | {expected:,} B | {actual:,} B | {match} |")
    return "\n".join(lines)


def pixel_table(pixel_rows: list) -> str:
    lines = [
        "| Pixel # | RGB | Expected gray (BT.601) | Actual gray | Match |",
        "|---|---|---|---|---|",
    ]
    for p, rgb_val, expected, actual, match in pixel_rows:
        lines.append(f"| {p:,} | {rgb_val} | {expected} | {actual} | {'✅' if match else '❌'} |")
    return "\n".join(lines)


def replace_marker(text: str, name: str, content: str, inline: bool = False) -> str:
    pattern = re.compile(
        rf"(<!-- RESULTS:{name}:START -->)(.*?)(<!-- RESULTS:{name}:END -->)",
        re.DOTALL,
    )
    if not pattern.search(text):
        raise SystemExit(f"Marker RESULTS:{name} not found in README")
    sep = "" if inline else "\n"
    return pattern.sub(lambda m: f"{m.group(1)}{sep}{content}{sep}{m.group(3)}", text)


def backend_table(cpp_time: str, rtl_time: str | None) -> str:
    """Comparativa de los dos backends de RAM.

    El backend RTL puede no haber corrido todavía: mientras `src/rtl/axi4_ram.v`
    no tenga lógica, la corrida se cuelga y el guard de RamAxi la corta. En ese
    caso se publica el estado real en vez de inventar un número.
    """
    lines = [
        "| RAM backend | How | Simulated time at stop | Status |",
        "|---|---|---|---|",
        f"| C++ behavioural | `make run` | {cpp_time} | ✅ runs |",
    ]
    if rtl_time:
        lines.append(
            f"| Verilog AXI4-Full (DPI) | `make run-rtl` | {rtl_time} | ✅ runs |"
        )
    else:
        lines.append(
            "| Verilog AXI4-Full (DPI) | `make run-rtl` | — | ⏳ pending the RTL body |"
        )
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sim_log", type=Path, help="log of the C++ backend run")
    parser.add_argument(
        "--rtl-log",
        type=Path,
        default=None,
        help="optional log of the --rtl-ram run; omit while the RTL is a stub",
    )
    parser.add_argument("--readme", type=Path, required=True)
    args = parser.parse_args()

    log_text = args.sim_log.read_text()
    rgb = INPUT_RAW.read_bytes()
    gray = OUTPUT_RAW.read_bytes()

    pixel_count = WIDTH * HEIGHT
    sample_positions = [0, pixel_count // 4, pixel_count // 2, pixel_count - 1]
    pixel_rows = verify_pixels(rgb, gray, sample_positions)
    final_time = parse_final_sim_time(log_text)

    rtl_time = None
    if args.rtl_log is not None:
        if not args.rtl_log.exists():
            raise SystemExit(f"error: {args.rtl_log} does not exist")
        rtl_time = parse_final_sim_time(args.rtl_log.read_text())

    readme_text = args.readme.read_text()
    readme_text = replace_marker(
        readme_text, "DATA-VOLUME", data_volume_table(len(rgb), len(gray))
    )
    readme_text = replace_marker(readme_text, "PIXELS", pixel_table(pixel_rows))
    readme_text = replace_marker(readme_text, "SIMTIME", f"**{final_time}**", inline=True)
    readme_text = replace_marker(
        readme_text, "BACKENDS", backend_table(final_time, rtl_time)
    )
    args.readme.write_text(readme_text)

    which = "C++ only" if rtl_time is None else "C++ and RTL"
    print(f"Updated {args.readme} with live simulation results ({which})")


if __name__ == "__main__":
    main()
