#!/usr/bin/env python3
"""Enforce per-assembly coverage thresholds from a merged Cobertura XML report."""

import sys
import xml.etree.ElementTree as ET

THRESHOLDS = {
    "AHKFlowApp.Domain":         {"line": 85.0, "branch": 70.0},
    "AHKFlowApp.Application":    {"line": 85.0, "branch": 45.0},
    "AHKFlowApp.Infrastructure": {"line": 70.0, "branch": 50.0},
    "AHKFlowApp.API":            {"line": 57.0, "branch": 50.0},
    "AHKFlowApp.UI.Blazor":      {"line": 65.0, "branch": 28.0},
}

COBERTURA_PATH = "CoverageReport/Cobertura.xml"


def main() -> int:
    try:
        tree = ET.parse(COBERTURA_PATH)
    except FileNotFoundError:
        print(f"::error::Coverage report not found at {COBERTURA_PATH}", flush=True)
        return 1

    root = tree.getroot()
    packages = {
        pkg.attrib["name"]: pkg.attrib
        for pkg in root.iter("package")
    }

    failures: list[str] = []

    for assembly, thresholds in THRESHOLDS.items():
        pkg = packages.get(assembly)
        if pkg is None:
            failures.append(f"  {assembly}: NOT FOUND in coverage report")
            continue

        line_rate = float(pkg.get("line-rate", 0)) * 100
        branch_rate = float(pkg.get("branch-rate", 0)) * 100
        line_ok = line_rate >= thresholds["line"]
        branch_ok = branch_rate >= thresholds["branch"]

        status = "PASS" if (line_ok and branch_ok) else "FAIL"
        print(
            f"  {status}  {assembly}  "
            f"line={line_rate:.1f}% (>={thresholds['line']}%)  "
            f"branch={branch_rate:.1f}% (>={thresholds['branch']}%)"
        )

        if not line_ok:
            failures.append(
                f"  {assembly}: line {line_rate:.1f}% < {thresholds['line']}%"
            )
        if not branch_ok:
            failures.append(
                f"  {assembly}: branch {branch_rate:.1f}% < {thresholds['branch']}%"
            )

    if failures:
        print("\n::error::Coverage threshold failures:")
        for f in failures:
            print(f)
        return 1

    print("\nAll per-assembly coverage thresholds met.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
