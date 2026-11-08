"""Every ordering of agent activity around keep-current's branch sweep, up to fixed bounds.

The sweep's decision is not written here. It comes from probe.py, which runs the
real script. Each script step below is one real step of scripts/keep-current.sh main():
  read open   open=$(gh pr list ... --state open ...)
  read merged merged=$(gh pr list ... --state merged ...)
  fetch       git fetch --quiet origin
  sweep       one pass of the `while read branch` loop: should_delete_branch, then
              git push origin --delete
"""
import collections

MAIN, MASTER, RUN, A, B = "main", "master", "refactor/run-01", "feat/a", "feat/b"
BRANCHES = (MAIN, MASTER, RUN, A, B)
PROTECTED = (MAIN, MASTER, RUN)
AGENT_BRANCHES = (RUN, A, B)

BETWEEN_RUNS = "between-runs"
DURING_RUN = "during-run"
MODES = (BETWEEN_RUNS, DURING_RUN)

MAX_RUNS = 2
BOUNDS = {BETWEEN_RUNS: (4, 3), DURING_RUN: (4, 2)}

PROPERTIES = collections.OrderedDict([
    ("protected-branch-kept",
     "main, master, and refactor/run-* are never deleted."),
    ("open-head-kept",
     "The head branch of an open PR is never deleted, or GitHub closes that PR."),
    ("open-base-kept",
     "The base branch of an open PR is never deleted, or GitHub can close that PR."),
    ("unlanded-work-kept",
     "A branch holding commits that never landed is never deleted, or that work is lost."),
])

State = collections.namedtuple(
    "State", "tips landed commits prs pc open_snap merged_snap tip_snap queue runs"
)


def _set(tup, branch, value):
    i = BRANCHES.index(branch)
    return tup[:i] + (value,) + tup[i + 1:]


def _get(tup, branch):
    return tup[BRANCHES.index(branch)]


def initial():
    seeded = ((-2, MAIN, RUN, "merged", 1), (-1, MASTER, RUN, "merged", 1))
    return State(
        tips=(1, 1, 1, 0, 0), landed=(1, 1, 1, 0, 0), commits=1, prs=seeded,
        pc="idle", open_snap=(), merged_snap=(), tip_snap=(), queue=(), runs=0,
    )


def _open_prs(s):
    return [p for p in s.prs if p[3] == "open"]


def _agent_steps(s, max_commits, max_prs):
    if s.commits < max_commits:
        for b in AGENT_BRANCHES:
            c = s.commits + 1
            yield (f"agent pushes commit c{c} to {b}",
                   s._replace(tips=_set(s.tips, b, c), commits=c), ())

    opened = len([p for p in s.prs if p[0] > 0])
    if opened < max_prs:
        for head in AGENT_BRANCHES:
            if _get(s.tips, head) <= _get(s.landed, head):
                continue
            for base in BRANCHES:
                if base == head or _get(s.tips, base) == 0:
                    continue
                if any(p[1] == head and p[2] == base for p in _open_prs(s)):
                    continue
                n = opened + 1
                pr = (n, head, base, "open", 0)
                yield (f"agent opens PR #{n}: {head} into {base}",
                       s._replace(prs=s.prs + (pr,)), ())

    open_heads = {p[1] for p in _open_prs(s)}
    for i, p in enumerate(s.prs):
        if p[3] != "open":
            continue
        n, head, base = p[0], p[1], p[2]
        if _get(s.tips, base) != 0 and not (base in open_heads and base != RUN):
            tip = _get(s.tips, head)
            prs = s.prs[:i] + ((n, head, base, "merged", tip),) + s.prs[i + 1:]
            yield (f"PR #{n} squash-merges with {head} at c{tip}",
                   s._replace(prs=prs, landed=_set(s.landed, head, tip)), ())
        merged_heads = {q[1] for q in s.prs if q[3] == "merged"}
        if base in (A, B) and base in merged_heads and base not in open_heads and head != MAIN:
            if not any(q[1] == head and q[2] == MAIN for q in _open_prs(s)):
                prs = s.prs[:i] + ((n, head, MAIN, "open", 0),) + s.prs[i + 1:]
                yield (f"restack.yml retargets PR #{n} from {base} to main",
                       s._replace(prs=prs), ())


def _harm(s, branch):
    harm = []
    if branch in PROTECTED:
        harm.append("protected-branch-kept")
    if any(p[1] == branch for p in _open_prs(s)):
        harm.append("open-head-kept")
    if any(p[2] == branch for p in _open_prs(s)):
        harm.append("open-base-kept")
    if _get(s.tips, branch) > _get(s.landed, branch):
        harm.append("unlanded-work-kept")
    return tuple(harm)


def _script_steps(s, decision):
    if s.pc == "idle":
        if s.runs < MAX_RUNS:
            snap = tuple((p[1], p[2]) for p in _open_prs(s))
            yield (f"keep-current run {s.runs + 1} reads the open PR list",
                   s._replace(pc="read-open", open_snap=snap), ())
    elif s.pc == "read-open":
        snap = tuple((p[1], p[4]) for p in s.prs if p[3] == "merged")
        yield ("keep-current reads the merged PR list",
               s._replace(pc="read-merged", merged_snap=snap), ())
    elif s.pc == "read-merged":
        queue = tuple(dict.fromkeys(h for h, _ in s.merged_snap))
        yield ("keep-current fetches, then merges bases into open heads",
               s._replace(pc="sweep", tip_snap=s.tips, queue=queue), ())
    elif s.pc == "sweep":
        if not s.queue:
            yield (f"keep-current run {s.runs + 1} ends",
                   s._replace(pc="idle", open_snap=(), merged_snap=(), tip_snap=(),
                              runs=s.runs + 1), ())
            return
        b = s.queue[0]
        if _get(s.tips, b) == 0:
            yield (f"keep-current keeps {b}", s._replace(queue=s.queue[1:]), ())
            return
        snap = tuple((p[1], p[2]) for p in _open_prs(s))
        yield (f"keep-current rereads the open PR list before {b}",
               s._replace(pc="confirm", open_snap=snap), ())
    elif s.pc == "confirm":
        b = s.queue[0]
        rest = s._replace(pc="sweep", queue=s.queue[1:])
        oids = {o for h, o in s.merged_snap if h == b}
        key = (b, any(h == b for h, _ in s.open_snap),
               any(base == b for _, base in s.open_snap),
               _get(s.tip_snap, b) not in oids,
               _get(s.tips, b) != _get(s.tip_snap, b))
        if _get(s.tips, b) == 0 or not decision[key]:
            yield (f"keep-current keeps {b}", rest, ())
        else:
            yield (f"keep-current deletes {b}",
                   rest._replace(tips=_set(rest.tips, b, 0)), _harm(s, b))


def explore(decision, mode):
    """Breadth-first, so each reported path is a shortest one. A harmful delete ends its path."""
    max_commits, max_prs = BOUNDS[mode]
    start = initial()
    parent = {start: None}
    frontier = collections.deque([start])
    broken = {}
    while frontier:
        s = frontier.popleft()
        steps = list(_script_steps(s, decision))
        if mode == DURING_RUN or s.pc == "idle":
            steps += list(_agent_steps(s, max_commits, max_prs))
        for event, nxt, harm in steps:
            if harm:
                for name in harm:
                    if name not in broken:
                        broken[name] = _path(parent, s) + [event]
                continue
            if nxt not in parent:
                parent[nxt] = (s, event)
                frontier.append(nxt)
    return broken, len(parent)


def _path(parent, s):
    events = []
    while parent[s] is not None:
        s, event = parent[s]
        events.append(event)
    return events[::-1]
