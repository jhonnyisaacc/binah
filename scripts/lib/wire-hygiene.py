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
    "scripts/check-guardrails-alone.sh",
)

GATES = "$RUNNER_TEMP/binah-base"
KIT_PATHS = (
    *REQUIRED,
    "scripts/lib/common.sh",
    "policy/branch-name.regex",
    "policy/secret-allowlist",
    "policy/integration-branches",
)

# This sentence is the Merging rule in rules.md. tests/test-policy-sync.sh
# fails when the two copies differ.
ONE_PULL_SENTENCE = (
    "One pull request is one job. A later pull request merged into a pull that is still open fails that pull. "
    "Redo per merge-playbook.md section 10, or ask Jhonny to list the pull in `policy/backlog-recovery`. "
    "The integration pull request is where those merges land, so it is not that failure. "
    "Its name is read from `policy/integration-branches` (one exact name or glob per line). "
    "A missing file means the numbered `refactor/run-<nn>` names. "
    "A fold passes only when `policy/backlog-recovery` on the default branch lists this pull's number. "
    "The check reads that file with `git show` of `origin/<default>:policy/backlog-recovery` and never the pull's head. "
    "A missing file or a failed read counts as not listed. "
    "Adding a number to `policy/backlog-recovery` is Tier A (editing guardrail files) and needs Jhonny's approval. "
    "The label approach was dropped because agents hold Jhonny's credentials. "
    "Enforcement: `scripts/check-one-pr.sh` in the `hygiene` job. "
    "It fails when stack depth is over 2 (`stack depth 3 is over the limit of 2`) or this pull is the 6th or later open pull (`pull #N is the 6th open pull; the limit is 5`). "
    "`binah-install` wires that call."
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
        ONE_PULL_SENTENCE,
    ),
)

PLANNED_LINE = re.compile(
    r"check-pr-body|check-one-pr|check-secrets|stack-limits|pull request body|secret scan|one pull request",
    re.IGNORECASE,
)


def steps_block(indent: str) -> str:
    key = indent + "  "
    nested = indent + "    "
    on_pull = f"{key}if: github.event_name == 'pull_request'"
    number = f"{nested}PR_NUMBER: " + "'${{ github.event.pull_request.number }}'"
    token = f"{nested}GH_TOKEN: " + "'${{ github.token }}'"
    lines = [
        f"{indent}# BEGIN binah hygiene",
        f"{indent}- name: check out gates",
        on_pull,
        f"{key}env:",
        f"{nested}DEFAULT_BRANCH: " + "'${{ github.event.repository.default_branch }}'",
        f"{key}run: |",
        nested + 'git fetch --depth 1 origin "$DEFAULT_BRANCH"',
        nested + f'git worktree add --detach "{GATES}" FETCH_HEAD',
        nested + "for rel in " + " ".join(KIT_PATHS) + "; do",
        nested + f'  if [ ! -e "{GATES}/$rel" ] && [ -e "$rel" ]; then',
        nested + f'    mkdir -p "$(dirname "{GATES}/$rel")"',
        nested + f'    cp "$rel" "{GATES}/$rel"',
        nested + "    printf '::warning::%s is not on %s yet, so this pull grades itself with its own copy\\n' \"$rel\" \"$DEFAULT_BRANCH\"",
        nested + "  fi",
        nested + "done",
        f"{indent}- name: branch name",
        on_pull,
        f"{key}env:",
        f"{nested}HEAD_REF: " + "'${{ github.head_ref }}'",
        f"{key}run: |",
        nested + f'bash "{GATES}/scripts/check-branch-name.sh" "$HEAD_REF"',
        f"{indent}- name: pull request body",
        on_pull,
        f"{key}env:",
        token,
        number,
        f"{key}run: |",
        nested + 'body="${RUNNER_TEMP}/pr-body.md"',
        nested + 'gh pr view "$PR_NUMBER" --json body --jq .body >"$body"',
        nested + "mapfile -t files < <(gh pr view \"$PR_NUMBER\" --json files --jq '.files[].path')",
        nested + f'bash "{GATES}/scripts/check-pr-body.sh" "$body" "${{files[@]}}"',
        f"{indent}- name: one pull request, one job",
        on_pull,
        f"{key}env:",
        token,
        number,
        f"{key}run: |",
        nested + f'bash "{GATES}/scripts/check-one-pr.sh" --repo "$GITHUB_REPOSITORY" --number "$PR_NUMBER"',
        f"{indent}- name: secret scan",
        f"{key}run: |",
        nested + 'if [ "$GITHUB_EVENT_NAME" = pull_request ]; then',
        nested + f'  bash "{GATES}/scripts/check-secrets.sh" "$GITHUB_WORKSPACE"',
        nested + "else",
        nested + "  bash scripts/check-secrets.sh",
        nested + "fi",
        f"{indent}- name: guardrail changes ride alone",
        on_pull,
        f"{key}env:",
        token,
        number,
        f"{key}run: |",
        nested + f'bash "{GATES}/scripts/check-guardrails-alone.sh" --repo "$GITHUB_REPOSITORY" --number "$PR_NUMBER"',
        f"{indent}# END binah hygiene",
    ]
    return "\n".join(lines) + "\n"


def new_workflow() -> str:
    return (
        "name: hygiene\n"
        "on:\n"
        "  pull_request:\n"
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


def checkout_and_steps(indent: str) -> str:
    return (
        f"{indent}- uses: actions/checkout@v4\n"
        f"{indent}  with:\n"
        f"{indent}    fetch-depth: 1\n"
        + steps_block(indent)
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


def job_key(lines: list[str], span: dict, name: str) -> tuple[int, str] | None:
    want = span["indent"] + 2
    for index in range(span["start"] + 1, span["end"]):
        raw = lines[index].rstrip("\n")
        if not raw.strip():
            continue
        if len(raw) - len(raw.lstrip(" ")) != want:
            continue
        match = re.match(rf"{name}\s*:\s*(.*)$", raw.strip())
        if match:
            return index, YAML_COMMENT.sub("", match.group(1)).strip()
    return None


def steps_end(lines: list[str], span: dict, steps_at: int) -> int:
    key_indent = len(lines[steps_at]) - len(lines[steps_at].lstrip(" "))
    end = steps_at + 1
    for index in range(steps_at + 1, span["end"]):
        raw = lines[index].rstrip("\n")
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        if indent < key_indent or (indent == key_indent and not raw.lstrip().startswith("- ")):
            break
        end = index + 1
    return end


def has_checkout(lines: list[str], start: int, end: int) -> bool:
    text = "\n".join(YAML_COMMENT.sub("", line.rstrip("\n")) for line in lines[start:end])
    return CHECKOUT_USES.search(text) is not None


def refuse_shape(lines: list[str], span: dict) -> None:
    def refuse(reason: str) -> None:
        raise SystemExit(f"cannot wire the hygiene job: {reason}. Change the job, then run binah-install again.")

    if job_key(lines, span, "uses") is not None:
        refuse("it calls a reusable workflow, and such a job cannot have steps")
    steps = job_key(lines, span, "steps")
    if steps is None:
        return
    if steps[1]:
        refuse(f"its steps are written inline (steps: {steps[1]})")


def update_job(lines: list[str], span: dict) -> list[str]:
    lines = list(lines)
    bounds = marker_bounds(lines, span)
    if bounds is not None:
        begin, end = bounds
        indent = re.match(r"^( *)# BEGIN binah hygiene", lines[begin]).group(1)
        block = steps_block(indent).splitlines(keepends=True)
        lines[begin : end + 1] = block
        return lines
    refuse_shape(lines, span)
    steps = job_key(lines, span, "steps")
    if steps is None:
        key = " " * (span["indent"] + 2)
        insert_at(lines, span["end"], f"{key}steps:\n{checkout_and_steps(key + '  ')}")
        return lines
    end = steps_end(lines, span, steps[0])
    indent = step_indent(lines, span)
    block = steps_block(indent) if has_checkout(lines, steps[0], end) else checkout_and_steps(indent)
    insert_at(lines, end, block)
    return lines


def append_hygiene_job(text: str) -> str:
    job = (
        "  hygiene:\n"
        "    runs-on: ubuntu-latest\n"
        "    steps:\n"
        + checkout_and_steps("      ")
    )
    if not text.endswith("\n"):
        text += "\n"
    if re.search(r"(?m)^jobs:\s*(#.*)?$", text):
        return text + job
    return text + "jobs:\n" + job


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
        updated = "".join(update_job(lines, span))
        if not updated.endswith("\n"):
            updated += "\n"
        write_if_changed(path, updated)
        return
    path = root / ".github" / "workflows" / "hygiene.yml"
    if path.is_file():
        write_if_changed(path, append_hygiene_job(path.read_text()))
        return
    write_if_changed(path, new_workflow())


def wiring_problems(root: Path) -> list[str]:
    found = find_hygiene(root)
    if found is None:
        return ["there is no hygiene job. Run binah-install."]
    _path, lines, span = found
    bounds = marker_bounds(lines, span)
    if bounds is None:
        return ["the hygiene job has no binah block. Run binah-install."]
    begin, end = bounds
    indent = re.match(r"^( *)# BEGIN binah hygiene", lines[begin]).group(1)
    problems = []
    if "".join(lines[begin : end + 1]) != steps_block(indent):
        problems.append("the binah block differs from what this binah writes. Run binah-install.")
    if job_key(lines, span, "if") is not None:
        problems.append("the hygiene job has a job-level if, so the gates may not run.")
    if job_key(lines, span, "continue-on-error") is not None:
        problems.append("the hygiene job sets continue-on-error, so a failed gate would not fail it.")
    trigger = "\n".join(YAML_COMMENT.sub("", line.rstrip("\n")) for line in lines[: span["start"]])
    if not re.search(r"\bpull_request\b", trigger):
        problems.append("the workflow does not run on pull_request.")
    if not has_checkout(lines, span["start"], begin):
        problems.append("the hygiene job has no actions/checkout step before the binah block.")
    if checkout_requests_history(lines, span):
        problems.append("fetch-depth: 0 history scan is enabled.")
    return problems


CHECKOUT_USES = re.compile(r"""\buses["']?\s*:\s*["']?actions/checkout@""")
FULL_HISTORY = re.compile(r"""fetch-depth["']?\s*:\s*["']?0["']?\s*([,}]|$)""", re.MULTILINE)
YAML_COMMENT = re.compile(r"(^|\s)#.*$")


def checkout_requests_history(lines: list[str], span: dict) -> bool:
    step_indent = None
    starts = []
    for index in range(span["start"], span["end"]):
        match = re.match(r"^( +)- ", lines[index])
        if not match or len(match.group(1)) <= span["indent"]:
            continue
        indent = len(match.group(1))
        if step_indent is None:
            step_indent = indent
        if indent == step_indent:
            starts.append(index)
    starts.append(span["end"])
    for start, end in zip(starts, starts[1:]):
        text = "\n".join(YAML_COMMENT.sub("", line.rstrip("\n")) for line in lines[start:end])
        if CHECKOUT_USES.search(text) and FULL_HISTORY.search(text):
            return True
    return False


def main() -> None:
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        problems = wiring_problems(Path(sys.argv[2]))
        for problem in problems:
            print(problem, file=sys.stderr)
        if problems:
            sys.exit(1)
        return
    if len(sys.argv) != 2:
        raise SystemExit("usage: wire-hygiene.py [--check] <target-repo>")
    root = Path(sys.argv[1])
    strip_rules(root)
    wire(root)


if __name__ == "__main__":
    main()
