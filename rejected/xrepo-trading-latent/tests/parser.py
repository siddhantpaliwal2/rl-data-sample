#!/usr/bin/env python3
"""Parse `bun test --reporter=junit` XML (on stdin) into per-test verdicts.

Reads the runner stdout on stdin (JUnit XML, possibly surrounded by console
noise) and prints JSON: {"tests": [{"name", "status"}]}.

A <testcase> is `failed` if it carries a <failure>/<error> child, `skipped`
if it carries a <skipped> child, and `passed` otherwise (bun emits passing
testcases as self-closing elements). Test identity is "<classname> > <name>"
to mirror a `describe > test` node id. Regex-only: no XML library required.
"""
import html
import json
import re
import sys

# Opening tag of a testcase; `selfclose` captures the trailing "/" when the
# element is self-closed (a passing test), e.g. <testcase name=".." ... />.
TESTCASE = re.compile(r"<testcase\b(?P<attrs>[^>]*?)(?P<selfclose>/?)>", re.S)
ATTR = re.compile(r'([\w:-]+)\s*=\s*"([^"]*)"')
STATUS_CHILD = re.compile(r"<(failure|error|skipped)\b")


def main() -> None:
    data = sys.stdin.read()
    verdicts = {}
    for m in TESTCASE.finditer(data):
        attrs = dict(ATTR.findall(m.group("attrs")))
        name = html.unescape(attrs.get("name", ""))
        classname = html.unescape(attrs.get("classname", ""))
        full = f"{classname} > {name}" if classname else name
        if m.group("selfclose"):
            status = "passed"
        else:
            end = data.find("</testcase>", m.end())
            body = data[m.end():end] if end != -1 else ""
            cm = STATUS_CHILD.search(body)
            if cm:
                status = "skipped" if cm.group(1) == "skipped" else "failed"
            else:
                status = "passed"
        verdicts[full] = status
    print(json.dumps({"tests": [{"name": n, "status": s} for n, s in verdicts.items()]}))


if __name__ == "__main__":
    main()
