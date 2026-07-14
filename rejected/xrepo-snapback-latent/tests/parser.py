#!/usr/bin/env python3
"""Parse bun's JUnit XML (read from stdin) into per-test verdicts.

Reads the JUnit report bun writes with `--reporter=junit`, prints JSON:
{"tests": [{"name", "status"}]}. A test name is rendered as
"<file>::<classname>::<testname>" so it is unique across files and stable
across runs. A <failure>/<error> child maps to "failed", <skipped> to
"skipped", otherwise "passed". Regex-based on purpose: it must not depend on
pyexpat/libexpat being importable in the grading image.
"""
import html
import json
import re
import sys

TESTCASE = re.compile(r"<testcase\b([^>]*?)(/>|>(.*?)</testcase>)", re.S)
ATTR = re.compile(r'(\w+)="(.*?)"', re.S)
FAIL_CHILD = re.compile(r"<(failure|error)\b")
SKIP_CHILD = re.compile(r"<skipped\b")


def main() -> None:
    xml = sys.stdin.read()
    tests = []
    for m in TESTCASE.finditer(xml):
        attrs = dict(ATTR.findall(m.group(1)))
        inner = m.group(3) or ""
        if FAIL_CHILD.search(inner):
            status = "failed"
        elif SKIP_CHILD.search(inner):
            status = "skipped"
        else:
            status = "passed"
        name = "::".join(
            html.unescape(attrs.get(k, ""))
            for k in ("file", "classname", "name")
        )
        tests.append({"name": name, "status": status})
    print(json.dumps({"tests": tests}))


if __name__ == "__main__":
    main()
