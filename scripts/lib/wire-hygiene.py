#!/usr/bin/env python3
"""Wire the binah hygiene job and drop planned marks for checks it runs."""

from __future__ import annotations

import re
import sys
from pathlib import Path

REQUIRED = (
    "scripts/check-branch-name.sh",
    "scripts/check-pr-body.sh",
    "scripts/check-one-pr.sh",
    "scripts/check-secrets.sh",
)

REPLACEMENTS = (
    (
        "Enforcement: `scripts/check-pr-body.sh`. Calling it from each repo's `hygiene` job is (planned) until Refa wires it.",
        "Enforcement: `scripts/check-pr-body.sh` in the `hygiene` job. `binah-install` wires that call. An empty template is not a filled body: the check exits non-zero when Why, What changed, or How to test has no text.",
    ),
    (
        "pull request body (planned)",
        "pull request body",
    ),
    (
        "A required `stack-limits` step in `hygiene` fails a PR that breaks either limit (planned until built).",
        "One pull request is one job. A later pull request merged into a pull that is still open fails that pull. Enforcement: `scripts/check-one-pr.sh` in the `hygiene` job. It fails when stack depth is over 2 or the run has more than 5 open pull requests. `binah-install` wires that call.",
    ),
)

PLANNED_LINE = re.compile(
    r"check-pr-body|check-one-pr|check-secrets|stack-limits|pull request body|secret scan|one pull request",
    re.IGNORECASE,
)


def steps_block(indent: str) -> str:
    key = indent + "  "
    nested = indent + "    "
    lines = [
        f"{indent}# BEGIN binah hygiene",
        f"{indent}- name: branch name",
        f"{key}if: github.event_name == 'pull_request'",
        f"{key}run: " + "'bash scripts/check-branch-name.sh \"${{ github.head_ref }}\"'",
        f"{indent}- name: pull request body",
        f"{key}if: github.event_name == 'pull_request'",
        f"{key}env:",
        f"{nested}GH_TOKEN: " + "'${{ github.token }}'",
        f"{key}run: |",
        nested + 'body="${RUNNER_TEMP}/pr-body.md"',
        nested + 'number="${{ github.event.pull_request.number }}"',
        nested + 'gh pr view "$number" --json body --jq .body >"$body"',
        nested + "mapfile -t files < <(gh pr view \"$number\" --json files --jq '.files[].path')",
        nested + 'bash scripts/check-pr-body.sh "$body" "${files[@]}"',
        f"{indent}- name: one pull request, one job",
        f"{key}if: github.event_name == 'pull_request'",
        f"{key}env:",
        f"{nested}GH_TOKEN: " + "'${{ github.token }}'",
        f"{key}run: "
        + "'bash scripts/check-one-pr.sh --repo \"${{ github.repository }}\" --number \"${{ github.event.pull_request.number }}\"'",
        f"{indent}- name: secret scan",
        f"{key}run: bash scripts/check-secrets.sh",
        f"{indent}# END binah hygiene",
    ]
    return "\n".join(lines) + "\n"


def new_workflow() -> str:
    return (
        "name: hygiene\n"
        "on:\n"
        "  pull_request:\n"
        "    types: [opened, synchronize, reopened, labeled, unlabeled]\n"
        "  push:\n"
        "    branches:\n"
        "      - main\n"
        "      - master\n"
        "concurrency:\n"
        "  group: '${{ github.workflow }}-${{ github.ref }}'\n"
        "  cancel-in-progress: true\n"
        "permissions:\n"
        "  contents: read\n"
        "  pull-requests: read\n"
        "  issues: read\n"
        "jobs:\n"
        "  hygiene:\n"
        "    runs-on: ubuntu-latest\n"
        "    steps:\n"
        "      - uses: actions/checkout@v4\n"
        "        with:\n"
        "          # Current tree only. History-scanning Gitleaks stays off until\n"
        "          # scripts/check-secrets.sh passes and fixtures are allowlisted.\n"
        "          fetch-depth: 1\n"
        + steps_block("      ")
    )


def checkout_and_steps() -> str:
    return (
        "      - uses: actions/checkout@v4\n"
        "        with:\n"
        "          fetch-depth: 1\n"
        + steps_block("      ")
    )


def workflow_files(root: Path) -> list[Path]:
    directory = root / ".github" / "workflows"
    if not directory.is_dir():
        return []
    return sorted(directory.glob("*.yml")) + sorted(directory.glob("*.yaml"))


def job_spans(lines: list[str]) -> list[dict]:
    jobs_at = None
    for index, line in enumerate(lines):
        if re.match(r"^jobs:\s*(#.*)?$", line.rstrip("\n")):
            jobs_at = index
            break
    if jobs_at is None:
        return []
    job_indent = None
    spans = []
    current = None
    for index in range(jobs_at + 1, len(lines)):
        raw = lines[index].rstrip("\n")
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        if indent == 0:
            if current is not None:
                current["end"] = index
                spans.append(current)
                current = None
            break
        if job_indent is None:
            job_indent = indent
        if indent == job_indent and re.match(r"[A-Za-z0-9_-]+:\s*(#.*)?$", raw.strip()):
            if current is not None:
                current["end"] = index
                spans.append(current)
            current = {"id": raw.strip().split(":", 1)[0], "start": index, "indent": indent}
        elif job_indent is not None and indent < job_indent:
            if current is not None:
                current["end"] = index
                spans.append(current)
                current = None
            break
    if current is not None:
        current["end"] = len(lines)
        spans.append(current)
    return spans


def display_name(lines: list[str], span: dict) -> str:
    want = span["indent"] + 2
    for index in range(span["start"] + 1, span["end"]):
        raw = lines[index].rstrip("\n")
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        if indent != want:
            continue
        match = re.match(r"name:\s*[\"']?(.+?)[\"']?\s*(#.*)?$", raw.strip())
        if match:
            return match.group(1).strip()
    return ""


def hygiene_span(lines: list[str]) -> dict | None:
    spans = job_spans(lines)
    for span in spans:
        if span["id"] == "hygiene":
            return span
    for span in spans:
        if display_name(lines, span) == "hygiene":
            return span
    return None


def find_hygiene(root: Path):
    for path in workflow_files(root):
        text = path.read_text()
        lines = text.splitlines(keepends=True)
        span = hygiene_span(lines)
        if span is not None:
            return path, lines, span
    return None


def step_indent(lines: list[str], span: dict) -> str:
    for index in range(span["start"], span["end"]):
        match = re.match(r"^( +)- ", lines[index])
        if match and len(match.group(1)) > span["indent"]:
            return match.group(1)
    return " " * (span["indent"] + 4)


def marker_bounds(lines: list[str], span: dict):
    begin = end = None
    for index in range(span["start"], span["end"]):
        stripped = lines[index].lstrip()
        if stripped.startswith("# BEGIN binah hygiene"):
            begin = index
        elif stripped.startswith("# END binah hygiene"):
            end = index
    if begin is None or end is None or end < begin:
        return None
    return begin, end


def insert_at(lines: list[str], index: int, text: str) -> None:
    if index > 0 and not lines[index - 1].endswith("\n"):
        lines[index - 1] += "\n"
    chunk = text.splitlines(keepends=True)
    if chunk and not chunk[-1].endswith("\n"):
        chunk[-1] += "\n"
    lines[index:index] = chunk


def has_steps(lines: list[str], span: dict) -> bool:
    want = span["indent"] + 2
    for index in range(span["start"] + 1, span["end"]):
        raw = lines[index].rstrip("\n")
        if not raw.strip():
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        if indent == want and raw.strip().startswith("steps:"):
            return True
    return False


def update_job(lines: list[str], span: dict) -> list[str]:
    lines = list(lines)
    bounds = marker_bounds(lines, span)
    if bounds is not None:
        begin, end = bounds
        indent = re.match(r"^( *)# BEGIN binah hygiene", lines[begin]).group(1)
        block = steps_block(indent).splitlines(keepends=True)
        lines[begin : end + 1] = block
        return lines
    indent = step_indent(lines, span)
    block = steps_block(indent)
    if not has_steps(lines, span):
        key = " " * (span["indent"] + 2)
        block = f"{key}steps:\n{block}"
    insert_at(lines, span["end"], block)
    return lines


def append_hygiene_job(text: str) -> str:
    job = (
        "  hygiene:\n"
        "    runs-on: ubuntu-latest\n"
        "    steps:\n"
        + checkout_and_steps()
    )
    if not text.endswith("\n"):
        text += "\n"
    if re.search(r"(?m)^jobs:\s*(#.*)?$", text):
        return text + job
    return text + "jobs:\n" + job


PR_TYPES = ("opened", "synchronize", "reopened", "labeled", "unlabeled")


def ensure_pr_types(text: str) -> str:
    """Re-run hygiene when a label is added or removed.

    GitHub's default pull_request types are opened, synchronize, and
    reopened. Naming types replaces that default, so those three stay.
    A close or merge of a different pull is not an event on this pull.
    """
    lines = text.splitlines(keepends=True)
    on_at = None
    for index, line in enumerate(lines):
        if re.match(r"^on:\s*(#.*)?$", line.rstrip("\n")):
            on_at = index
            break
    if on_at is None:
        return text
    pr_at = None
    block_end = len(lines)
    for index in range(on_at + 1, len(lines)):
        raw = lines[index].rstrip("\n")
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if not raw.startswith(" "):
            block_end = index
            break
        if re.match(r"^  pull_request:\s*(#.*)?$", raw):
            pr_at = index
            break
    if pr_at is None:
        return text
    types_at = None
    index = pr_at + 1
    while index < block_end:
        raw = lines[index].rstrip("\n")
        if not raw.strip() or raw.lstrip().startswith("#"):
            index += 1
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        if indent <= 2:
            break
        if indent == 4 and raw.strip().startswith("types:"):
            types_at = index
            break
        index += 1
    if types_at is None:
        lines.insert(pr_at + 1, "    types: [opened, synchronize, reopened, labeled, unlabeled]\n")
        return "".join(lines)
    raw = lines[types_at].rstrip("\n")
    flow = re.match(r"^(\s*types:\s*)\[(.*)\](\s*(#.*)?)?$", raw)
    if flow:
        items = [part.strip().strip("'\"") for part in flow.group(2).split(",") if part.strip()]
        for name in PR_TYPES:
            if name not in items:
                items.append(name)
        comment = flow.group(3) or ""
        if comment and not comment.startswith(" ") and not comment.startswith("\t"):
            comment = " " + comment
        lines[types_at] = f"{flow.group(1)}[{', '.join(items)}]{comment}\n"
        return "".join(lines)
    key_indent = len(raw) - len(raw.lstrip(" "))
    present = []
    item_indent = None
    last_item = types_at
    index = types_at + 1
    while index < len(lines):
        item = lines[index].rstrip("\n")
        if not item.strip() or item.lstrip().startswith("#"):
            index += 1
            continue
        indent = len(item) - len(item.lstrip(" "))
        if indent <= key_indent:
            break
        match = re.match(r"^\s*-\s+([^#]+?)\s*(#.*)?$", item)
        if match:
            present.append(match.group(1).strip().strip("'\""))
            item_indent = indent
            last_item = index
        index += 1
    if item_indent is None:
        return text
    for name in PR_TYPES:
        if name not in present:
            last_item += 1
            lines.insert(last_item, f"{' ' * item_indent}- {name}\n")
    return "".join(lines)


def write_if_changed(path: Path, text: str) -> None:
    if path.is_file() and path.read_text() == text:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def strip_planned(text: str) -> str:
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)
    out = []
    for line in text.splitlines(keepends=True):
        if PLANNED_LINE.search(line):
            line = line.replace(" (planned until built)", "")
            line = line.replace(" (planned until Refa wires it)", "")
            line = line.replace(" (planned)", "")
        out.append(line)
    return "".join(out)


def strip_rules(root: Path) -> None:
    path = root / "rules.md"
    if not path.is_file():
        return
    original = path.read_text()
    updated = strip_planned(original)
    if updated != original:
        path.write_text(updated)


def wire(root: Path) -> None:
    found = find_hygiene(root)
    if found is not None:
        path, lines, span = found
        updated = ensure_pr_types("".join(update_job(lines, span)))
        if not updated.endswith("\n"):
            updated += "\n"
        write_if_changed(path, updated)
        return
    path = root / ".github" / "workflows" / "hygiene.yml"
    if path.is_file():
        write_if_changed(path, ensure_pr_types(append_hygiene_job(path.read_text())))
        return
    write_if_changed(path, ensure_pr_types(new_workflow()))


def missing_scripts(root: Path) -> list[str]:
    found = find_hygiene(root)
    if found is None:
        return ["hygiene job", *REQUIRED]
    _path, lines, span = found
    body = "".join(lines[span["start"] : span["end"]])
    missing = [script for script in REQUIRED if script not in body]
    if "fetch-depth: 0" in steps_region(body):
        missing.append("fetch-depth: 0 history scan is enabled")
    return missing


def steps_region(body: str) -> str:
    begin = body.find("# BEGIN binah hygiene")
    end = body.find("# END binah hygiene")
    if begin == -1 or end == -1:
        return ""
    return body[begin:end]


def main() -> None:
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        missing = missing_scripts(Path(sys.argv[2]))
        if missing:
            for item in missing:
                print(f"hygiene job does not run {item}", file=sys.stderr)
            sys.exit(1)
        return
    if len(sys.argv) != 2:
        raise SystemExit("usage: wire-hygiene.py [--check] <target-repo>")
    root = Path(sys.argv[1])
    strip_rules(root)
    wire(root)


if __name__ == "__main__":
    main()
