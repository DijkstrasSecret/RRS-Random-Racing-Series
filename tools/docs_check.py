"""Checks the documentation rules in CLAUDE.md and docs/README.md.

    python tools/docs_check.py            # both checks
    python tools/docs_check.py comments   # only the GDScript doc comments
    python tools/docs_check.py paths      # only the repo paths quoted in docs

comments: every `class_name` script, signal, @export and public function in
scripts/ needs a `##` doc comment, either on the lines directly above (other
annotations may sit in between) or trailing on the same line. A class_name
script needs a `##` line in its header, before the first declaration.

paths: every repo path quoted in backticks in a Markdown doc, such as
`scripts/race/upgrades.gd` or `res://tests/race_test.tscn`, must exist.
Paths with placeholders (`<id>`, `*`) are skipped, and so are docs in
docs/plans/, which name files that a plan has yet to create. Relative links between
docs are checked by lychee (`make docs-check`), not here.

Prints one `file:line: problem` per finding and exits 1 if there are any.
Needs only the standard library.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOP_DIRS = ("addons", "assets", "docs", "scenes", "scripts", "soundtrack", "tests", "tools")
# Plans in docs/plans/ name files that don't exist yet, so their paths aren't checked.
MD_FILES = ["CLAUDE.md", *sorted(str(p.relative_to(ROOT)) for p in (ROOT / "docs").rglob("*.md")
                                 if "plans" not in p.relative_to(ROOT / "docs").parts[:1])]

DECL = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(signal|var|const|enum|func|static\s+func|class)\b")
SIGNAL = re.compile(r"^\s*signal\s+(\w+)")
FUNC = re.compile(r"^\s*(?:static\s+)?func\s+([a-zA-Z]\w*)")
EXPORT = re.compile(r"^\s*@export(?:_(?!group|subgroup|category)\w+)?\b.*?\bvar\s+(\w+)")
ANNOTATION_ONLY = re.compile(r"^\s*@\w+(\([^)]*\))?\s*$")
QUOTED_PATH = re.compile(r"`(?:res://)?((?:%s)/[^`\s]*)`" % "|".join(TOP_DIRS))


def _has_doc_above(lines: list[str], i: int) -> bool:
    if "##" in lines[i]:
        return True
    j = i - 1
    while j >= 0 and ANNOTATION_ONLY.match(lines[j]):
        j -= 1
    return j >= 0 and lines[j].lstrip().startswith("##")


def check_comments() -> list[str]:
    problems: list[str] = []
    for path in sorted((ROOT / "scripts").rglob("*.gd")):
        rel = path.relative_to(ROOT)
        lines = path.read_text(encoding="utf-8").splitlines()
        if any(l.startswith("class_name ") for l in lines):
            header_doc = False
            for line in lines:
                if line.lstrip().startswith("##"):
                    header_doc = True
                    break
                if DECL.match(line):
                    break
            if not header_doc:
                problems.append(f"{rel}:1: class_name script has no ## header comment")
        for i, line in enumerate(lines):
            for kind, pattern in (("signal", SIGNAL), ("@export", EXPORT), ("public function", FUNC)):
                m = pattern.match(line)
                if m and not _has_doc_above(lines, i):
                    problems.append(f"{rel}:{i + 1}: {kind} '{m.group(1)}' has no ## doc comment")
                    break
    return problems


def check_paths() -> list[str]:
    problems: list[str] = []
    for md in MD_FILES:
        for n, line in enumerate((ROOT / md).read_text(encoding="utf-8").splitlines(), 1):
            for m in QUOTED_PATH.finditer(line):
                p = re.sub(r":[\d,\- ]+$", "", m.group(1))  # drop :LINE suffixes
                if "..." in p or any(c in p for c in "<>*{}"):
                    continue
                if not (ROOT / p.rstrip("/")).exists():
                    problems.append(f"{md}:{n}: quoted path '{p}' does not exist")
    return problems


def main() -> int:
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    checks = {"comments": check_comments, "paths": check_paths}
    if which != "all" and which not in checks:
        sys.exit(f"unknown check '{which}'; use comments, paths or nothing for both")
    failed = False
    for name, check in checks.items():
        if which not in ("all", name):
            continue
        problems = check()
        for p in problems:
            print(p)
        print(f"docs_check {name}: {len(problems)} problem(s)")
        failed = failed or bool(problems)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
