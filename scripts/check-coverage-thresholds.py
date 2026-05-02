#!/usr/bin/env python3
"""Enforce per-assembly coverage thresholds from a merged Cobertura XML report."""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve()
REPO_ROOT = SCRIPT_PATH.parent.parent
DEFAULT_COBERTURA_PATH = REPO_ROOT / "CoverageReport" / "Cobertura.xml"
LOCAL_REPRO_COMMAND = r"pwsh .\scripts\run-coverage.ps1"
THRESHOLD_ONLY_COMMAND = r"python .\scripts\check-coverage-thresholds.py"
COVERAGE_GUIDE_PATH = r"docs\development\coverage.md"


@dataclass(frozen=True)
class Threshold:
    line: float
    branch: float


THRESHOLDS: dict[str, Threshold] = {
    "AHKFlowApp.Domain": Threshold(line=85.0, branch=70.0),
    "AHKFlowApp.Application": Threshold(line=85.0, branch=45.0),
    "AHKFlowApp.Infrastructure": Threshold(line=70.0, branch=50.0),
    "AHKFlowApp.API": Threshold(line=57.0, branch=50.0),
    "AHKFlowApp.UI.Blazor": Threshold(line=65.0, branch=28.0),
}


@dataclass(frozen=True)
class MetricResult:
    name: str
    actual: float
    required: float

    @property
    def passed(self) -> bool:
        return self.actual >= self.required

    @property
    def delta(self) -> float:
        return self.actual - self.required


@dataclass(frozen=True)
class AssemblyResult:
    name: str
    line: MetricResult | None = None
    branch: MetricResult | None = None
    missing: bool = False

    @property
    def passed(self) -> bool:
        return (
            not self.missing
            and self.line is not None
            and self.branch is not None
            and self.line.passed
            and self.branch.passed
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Enforce per-assembly coverage thresholds from a merged Cobertura XML report."
    )
    parser.add_argument(
        "--cobertura-path",
        type=Path,
        default=DEFAULT_COBERTURA_PATH,
        help="Path to the merged Cobertura.xml report.",
    )
    parser.add_argument(
        "--github-summary-footer",
        action="store_true",
        help="Print the markdown footer appended to CoverageReport\\SummaryGithub.md and exit.",
    )
    return parser.parse_args()


def simplify_assembly_name(assembly: str) -> str:
    return assembly.removeprefix("AHKFlowApp.")


def format_path(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT)).replace("/", "\\")
    except ValueError:
        return str(path).replace("/", "\\")


def format_threshold_summary() -> str:
    return " ; ".join(
        (
            f"{simplify_assembly_name(assembly)} line>={threshold.line:.0f}% "
            f"br>={threshold.branch:.0f}%"
        )
        for assembly, threshold in THRESHOLDS.items()
    )


def print_github_summary_footer() -> None:
    print()
    print("---")
    print(f"**Per-assembly thresholds:** {format_threshold_summary()}")
    print(f"**Local reproduction:** `{LOCAL_REPRO_COMMAND}`")
    print(f"**Threshold-only rerun:** `{THRESHOLD_ONLY_COMMAND}`")
    print(f"**Coverage policy:** `{COVERAGE_GUIDE_PATH}`")


def load_packages(cobertura_path: Path) -> dict[str, dict[str, str]]:
    tree = ET.parse(cobertura_path)
    root = tree.getroot()

    return {
        package.attrib["name"]: package.attrib
        for package in root.iter("package")
        if "name" in package.attrib
    }


def evaluate_results(packages: dict[str, dict[str, str]]) -> list[AssemblyResult]:
    results: list[AssemblyResult] = []

    for assembly, threshold in THRESHOLDS.items():
        package = packages.get(assembly)
        if package is None:
            results.append(AssemblyResult(name=assembly, missing=True))
            continue

        line_rate = float(package.get("line-rate", 0.0)) * 100
        branch_rate = float(package.get("branch-rate", 0.0)) * 100

        results.append(
            AssemblyResult(
                name=assembly,
                line=MetricResult("line", line_rate, threshold.line),
                branch=MetricResult("branch", branch_rate, threshold.branch),
            )
        )

    return results


def format_metric(metric: MetricResult) -> str:
    return (
        f"  - {metric.name:<6} {metric.actual:.1f}% "
        f"(required >= {metric.required:.1f}%, delta {metric.delta:+.1f}%)"
    )


def print_per_assembly_results(results: list[AssemblyResult]) -> None:
    print("Per-assembly results:")

    for result in results:
        status = "PASS" if result.passed else "FAIL"
        print(f"- {status} {result.name}")

        if result.missing:
            print("  - package missing from merged Cobertura report")
            continue

        print(format_metric(result.line))
        print(format_metric(result.branch))


def print_failure_summary(failures: list[AssemblyResult]) -> None:
    print()
    print(f"Coverage gate failed for {len(failures)} assembly(s):")

    for failure in failures:
        print(f"- {failure.name}")

        if failure.missing:
            print("  - package missing from CoverageReport\\Cobertura.xml")
            continue

        for metric in (failure.line, failure.branch):
            if metric is not None and not metric.passed:
                print(format_metric(metric))


def print_next_steps(results: list[AssemblyResult]) -> None:
    print()
    print("Reproduce locally from the repo root:")
    print(f"1. {LOCAL_REPRO_COMMAND}")
    print(f"2. {THRESHOLD_ONLY_COMMAND}    # rerun only the gate after CoverageReport exists")
    print()
    print("Next steps:")
    print("- Add or adjust tests when real business logic or request flow is uncovered.")
    print("- Review exclusions only when the uncovered code is narrow, explainable coverage noise.")

    if any(result.missing for result in results):
        print("- If an assembly is missing entirely, inspect TestResults\\**\\coverage.cobertura.xml and CoverageReport\\Cobertura.xml.")

    print(f"- See {COVERAGE_GUIDE_PATH} for the canonical workflow and exclusion guidance.")


def main() -> int:
    args = parse_args()

    if args.github_summary_footer:
        print_github_summary_footer()
        return 0

    cobertura_path = (
        args.cobertura_path
        if args.cobertura_path.is_absolute()
        else (Path.cwd() / args.cobertura_path).resolve()
    )

    try:
        packages = load_packages(cobertura_path)
    except FileNotFoundError:
        print(
            f"::error title=Coverage report missing::Coverage report not found at {format_path(cobertura_path)}."
        )
        print(f"Run `{LOCAL_REPRO_COMMAND}` from the repo root to generate CoverageReport\\Cobertura.xml.")
        return 1
    except ET.ParseError as exc:
        print(
            f"::error title=Coverage report invalid::Could not parse {format_path(cobertura_path)}: {exc}."
        )
        return 1

    results = evaluate_results(packages)
    failures = [result for result in results if not result.passed]

    print(f"Coverage report: {format_path(cobertura_path)}")
    print(f"Thresholds     : {format_threshold_summary()}")
    print()
    print_per_assembly_results(results)

    if failures:
        print_failure_summary(failures)
        print_next_steps(results)
        print()
        print(
            "::error title=Coverage gate failed::"
            f"{len(failures)} assembly(s) failed per-assembly coverage thresholds. "
            f"Run `{LOCAL_REPRO_COMMAND}` from the repo root to reproduce locally."
        )
        return 1

    print()
    print("All per-assembly coverage thresholds met.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
