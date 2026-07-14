#!/usr/bin/env python3
"""Parse pytest verbose output into per-test verdicts.

Reads runner stdout on stdin, prints JSON: {"tests": [{"name", "status"}]}.
ERROR is mapped to failed. Duplicate names keep the last verdict seen
(summary lines override progress lines).
"""
import json
import re
import sys

# progress lines: tests/test_x.py::Class::test_name PASSED [ 10%]
VERBOSE_LINE = re.compile(
    r"^(?P<name>\S+::\S+)\s+(?P<status>PASSED|FAILED|ERROR|SKIPPED|XFAIL|XPASS)\b"
)
# summary lines: FAILED tests/test_x.py::Class::test_name - AssertionError
RESULT_LINE = re.compile(
    r"^(?P<status>PASSED|FAILED|ERROR|SKIPPED)\s+(?P<name>\S+::\S+)"
)

STATUS_MAP = {
    "PASSED": "passed",
    "XPASS": "passed",
    "FAILED": "failed",
    "ERROR": "failed",
    "XFAIL": "failed",
    "SKIPPED": "skipped",
}


def main() -> None:
    verdicts = {}
    for raw in sys.stdin:
        line = raw.rstrip("\n")
        m = VERBOSE_LINE.match(line) or RESULT_LINE.match(line)
        if not m:
            continue
        name = m.group("name").split(" ")[0]
        verdicts[name] = STATUS_MAP[m.group("status")]
    print(json.dumps({"tests": [{"name": n, "status": s} for n, s in verdicts.items()]}))


if __name__ == "__main__":
    main()
