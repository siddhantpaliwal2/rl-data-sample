#!/usr/bin/env python3
"""Parse Maven Surefire XML reports into per-test verdicts.

Emits JSON on stdout: {"tests": [{"name", "status"}]}, with names formatted
``<SimpleClassName>::<methodName>`` to match config.json's fail_to_pass /
pass_to_pass node ids. A <failure> or <error> child marks a case failed; a
<skipped> child marks it skipped; otherwise it passed. Duplicate names keep
the last verdict seen.

Usage: parser.py [<surefire-reports-dir> ...]
Defaults to scanning common repo locations when no dir is given. This repo is
a multi-module Maven build; the graded module is ``webservice``, so its reports
land under ``webservice/target/surefire-reports``.
"""
import glob
import json
import os
import sys
import xml.etree.ElementTree as ET

DEFAULT_DIRS = [
    "/app/webservice/target/surefire-reports",
    "/testbed/webservice/target/surefire-reports",
    "webservice/target/surefire-reports",
    "/app/target/surefire-reports",
    "target/surefire-reports",
]


def report_dirs(argv):
    dirs = argv[1:] if len(argv) > 1 else DEFAULT_DIRS
    return [d for d in dirs if os.path.isdir(d)]


def simple_class(classname):
    return classname.rsplit(".", 1)[-1] if classname else classname


def verdict(testcase):
    for child in testcase:
        tag = child.tag.rsplit("}", 1)[-1]
        if tag in ("failure", "error"):
            return "failed"
        if tag == "skipped":
            return "skipped"
    return "passed"


def main():
    verdicts = {}
    for d in report_dirs(sys.argv):
        for path in sorted(glob.glob(os.path.join(d, "TEST-*.xml"))):
            try:
                root = ET.parse(path).getroot()
            except ET.ParseError:
                continue
            for tc in root.iter("testcase"):
                name = tc.get("name")
                cls = simple_class(tc.get("classname"))
                if not name or not cls:
                    continue
                verdicts["%s::%s" % (cls, name)] = verdict(tc)
    print(json.dumps({"tests": [{"name": n, "status": s} for n, s in verdicts.items()]}))


if __name__ == "__main__":
    main()
