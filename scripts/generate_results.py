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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sim_log", type=Path)
    parser.add_argument("--readme", type=Path, required=True)
    args = parser.parse_args()

    log_text = args.sim_log.read_text()
    rgb = INPUT_RAW.read_bytes()
    gray = OUTPUT_RAW.read_bytes()

    pixel_count = WIDTH * HEIGHT
    sample_positions = [0, pixel_count // 4, pixel_count // 2, pixel_count - 1]
    pixel_rows = verify_pixels(rgb, gray, sample_positions)
    final_time = parse_final_sim_time(log_text)

    readme_text = args.readme.read_text()
    readme_text = replace_marker(
        readme_text, "DATA-VOLUME", data_volume_table(len(rgb), len(gray))
    )
    readme_text = replace_marker(readme_text, "PIXELS", pixel_table(pixel_rows))
    readme_text = replace_marker(readme_text, "SIMTIME", f"**{final_time}**", inline=True)
    args.readme.write_text(readme_text)
    print(f"Updated {args.readme} with live simulation results")


if __name__ == "__main__":
    main()
