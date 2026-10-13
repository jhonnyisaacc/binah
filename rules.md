# Agent-friendly refactoring rules (v4.2, 2026-10-13)

Versioning: MAJOR.MINOR. Bump the minor number for polish (wording, a new check, a resolved open question) and the major number for structural changes (new tiers, a new process stage, a changed role split). Every change gets a line in the changelog at the bottom.


Roles: Refa reviews the repo and writes the Cursor briefs. Jhonny decides only Tier A items (see Autonomy). No plan review. Cursor (a Project for full refactors, plain cloud agents for small jobs) writes the code and makes Tier B decisions, recording each one.

Order of work: 1) codebase (data structures, algorithms, agent-friendly framework) 2) static analysis 3) rules / Bugbot 4) skills 5) style guide.

## General rules
1. Fix at the highest level. When an agent makes a mistake, first change the code so it can't happen, then catch it with static analysis, then add rules, Bugbot, or skills, and use a style guide last.
2. One approved way to do each thing. Delete tech debt rather than working around it, because agents copy whatever patterns they see.
3. Lint before cleanup. A bad pattern first gets a lint rule so it stops spreading, then gets cleaned up. Lint errors say how to fix the problem.
4. Explicit contracts at every boundary. Typed, validated data shapes, defined once and shared.
5. Enforced boundaries. Tooling checks the folder and import rules.
6. Verification is infrastructure. One fast check command, a way for agents to run and drive the app (pstack /create-verification-skill plus a feature map), and proof (tests, screenshots, video) before a PR counts as done.
7. A short AGENTS.md as a map. It covers only what an agent can't infer from the code. Rules get added only for mistakes that keep happening.
8. Small PRs that keep behavior the same unless we've decided otherwise, merged as they go. Work that isn't merged isn't done (see Merging).
9. Decisions are recorded in the repo.
10. No code comments.
11. Native stack. When one stack replaces another, parity means the same observable outcomes, never the same mechanism. Build it the new stack's way (see Stack migrations).
12. Every rule names its enforcer (a CI check, a ruleset, an account setting, a hook or a bot). A rule whose enforcer isn't built yet is marked (planned), and the preflight reports it. Instructions alone never count as enforcement.
13. Budgets up front. The brief fixes the PR list (one PR per outcome), the stack limits and a wake budget before launch. No "open now, fold later".

## Git and GitHub
- Agents use the gh CLI for GitHub reads (CI runs and logs, issues, PR state). For Cursor cloud agents gh is read-only even with a write-scoped token. The write path is Cursor's PR tool, given the full PR URL, and the merge steps agents can't run (enabling auto-merge, retargeting a child PR, triggering Bugbot) are run by repo workflows.
- Branches are named `<prefix>/<name>`, where `<name>` is a short kebab-case description and the prefix matches what the PR does. One spelling per prefix:
  - `feat/` new behavior
  - `fix/` bug fix
  - `hotfix/` urgent production patch
  - `chore/` deps, config, tooling
  - `docs/` docs only
  - `refactor/` structure change, same behavior
  - `test/` tests only
  - `release/` release cut
  Never `cursor/` or any other tool prefix. The table applies to all work, refactor runs included (a visible change is `feat/`, not `refactor/`). Every prefix in the table is used for its own kind of change; none is a default. Integration branches are `refactor/run-<nn>` allowed by exact name. Hosted Cloud Agents create the branch from the dashboard's single static prefix before they read AGENTS.md, and the dashboard can't pick a type per change. So every brief names the branch with the right prefix, the agent's first step is `git branch -m <prefix>/<name>` before the first push (whatever the platform created, `cursor/` included), and the required branch-name check blocks anything else.
- The first refactor PR writes this list into the repo's AGENTS.md (git section) and adds the branch-name step to the `hygiene` job (see CI baseline): `^(feat|fix|hotfix|chore|docs|refactor|test|release)/[a-z0-9][a-z0-9-]*$` plus exact integration-branch names. Exemptions for old branches are removed once those PRs close.
- PRs are opened under Jhonny's account as drafts while the work is in progress. The agent marks a PR ready when the work is done, the local check command passes and the proof is in the PR body. Marking ready hands the PR to the merge path: Bugbot, the approver, preview deploys and CI run, and auto-merge is turned on. A draft is a work in progress, never a parking spot: a PR that other work depends on is marked ready before that work starts.
- Agent PRs merge without human review, squash only, after they are open and reviewed. The merge conditions: the PR is ready, CI is green, `bugbot-gate` passed (a finished Bugbot review), every Bugbot finding has a fix commit or a triage reply, and `guard-paths` passes. Until a repo has the auto-merge setup, the agent that owns the PR merges it itself once those hold (`gh pr merge <n> --squash`, or the Cursor GitHub integration if gh can't). Once the setup exists, automerge.yml turns on GitHub auto-merge (`gh pr merge <n> --auto --squash`) when a PR is marked ready. Tier A PRs never merge until Jhonny applies the approval label. Agents never bypass a required check and never merge another agent's PR that isn't green.
- The auto-merge setup is Tier A and done once per repo: Allow auto-merge on, squash as the only merge method, automatic head-branch deletion off (the merge playbook deletes branches), the ruleset from Autonomy 4 on the base branch and on `refactor/run-*`, the automerge.yml and restack.yml workflows, the stack-limits check, and the token they use. It is the target state; a run may start without it, and then the agent merges as described above.
- Commits are authored and committed as the repo owner, with no Cursor co-author trailer, and signed with the owner's agent signing key so GitHub shows Verified. The key comes from cloud agent secrets and is loaded by the repo's Cursor environment setup script. An agent that can't sign stops committing and reports; it never pushes unverified commits. The key is a dedicated SSH signing key for agents only (never the owner's personal key), registered on the owner's GitHub account as a Signing Key and stored as one cloud agent secret, so it can be revoked on its own. Commits rewritten by a rebase are signed again before the push. Squash merges are made and signed by GitHub, so they show Verified, and GitHub allows them only when every commit on the head branch is Verified. Rebase-merge is never used, because GitHub can't sign it. Hosted Cloud Agents author as `Cursor Agent` and inject a `Co-authored-by: Cursor` trailer, and no Cursor setting turns this off for cloud agents (IDE and CLI attribution toggles are off on Jhonny's machines). So the environment setup script also sets `core.hooksPath .githooks`, whose `commit-msg` hook strips agent trailers and whose author is the owner. The required `hygiene` check fails any PR commit that isn't Verified, isn't authored by the owner, or carries a Cursor or other AI co-author trailer. The repo's squash message default is "PR title and description". The ruleset requires signed commits.

## Merging (procedure in merge-playbook.md)
- One integration branch per run, `refactor/run-<nn>`, cut from the project base. The brief may instead name an existing branch as the integration branch (davar run 1 uses `feat/davar-v2`, and nothing goes to `main` until Jhonny says so) (the branch the brief names, such as `main` or a long-lived feature branch). Every PR in the run targets it. The run ends with one PR from the integration branch into the project base, squash merged; it's Tier A when the base deploys to production. The integration branch is kept after that merge so each PR's squash commit stays findable and revertible.
- PR flow: feature PRs open as drafts directly against `main` (draft, then ready for review, then squash-merge into `main`). There is no `staging` branch; staging is only a Railway environment. Drafts deploy nothing. Marking a PR ready starts the Cloudflare preview workflow, whose build points at the Railway staging API (`STAGING_API_URL`). If the PR changes the API paths (`api/**` and the API's watch paths), the same ready event also deploys that PR's head to the Railway staging environment, in a concurrency group so only one PR holds staging at a time and the PR body says which PR staging is running. Railway's automatic PR environments are off. CI runs on every PR (`pull_request:` with no branch filter), and `gate` is the required check on `main`.
- Merge as you go. A PR merges before any work that depends on it starts. New work branches from the latest integration branch tip, never from an open PR's branch. While a PR waits on checks, the agent works on something independent of it.
- Limits per run (proposed numbers, tunable; changing them is a rule change): stack depth at most 2 (a PR may sit on one unmerged PR, never two), and at most 5 open PRs counting drafts but not the integration PR. At either limit, agents open no new PR and work to merge first: fix CI, triage Bugbot findings, restack children. A required `stack-limits` step in `hygiene` fails a PR that breaks either limit (planned until built).
- After a parent squash-merges, restack.yml retargets its children to the integration branch, and each child's agent replays only its own commits (`git rebase --onto`), re-runs the check command and pushes with `--force-with-lease` to its own branch. Head branches are deleted in one sweep at the end of the run, only after no open PR uses them as a base.
- Merge order is bottom-up: a chain's root first, then the next PR up once restacked and green.
- Mechanical conflicts are Tier C, fixed by the agent. A conflict whose resolution would change a pin assertion, a contract, a Tier A path, or pick between two behaviors stops that PR and gets reported.
- If the integration branch goes red, the first action is a revert PR, and nothing else merges until it's green.
- A run that ends with open stacked PRs gets the backlog recovery procedure in merge-playbook.md before any new run starts on the repo.
- The run report ends with the merge metrics in merge-playbook.md (wall-clock time, PRs opened, merged and closed, max stack depth, blocked Tier A items, rule violations).

## Repo review (before any refactor)
Inventory of the structure, data structures and contracts, algorithm hot spots (churn x size), competing patterns, import graph and cycles, current static analysis setup, tests and verification, AGENTS.md and docs, whether the dev environment comes up cleanly, past GitHub CI failures (gh run list and the failure logs), and the history of agent mistakes (pstack /correct, /why), and the CI inventory (each check's job, median time, required or not, overlap). It also asks, without scoring it: could agents rewrite this repo hands-off and prove what users see is identical, and what blocks that? The output is one report with an agent-readiness score.

## Preflight (before any agent run)
A `preflight` workflow (or a throwaway `chore/preflight-<date>` draft PR from a cloud agent) proves, before any code is written: a cloud-agent commit lands Verified, owner-authored and trailer-free; the branch name passes; every secret in `.github/required-secrets.txt` exists; the preview deploys; Bugbot answers a `bugbot run` within 15 minutes; `gate` is the required check on `main`; a ready PR that changes the API reaches Railway staging and the preview calls it. Any failure stops the run and is reported. Account settings checked by hand at the same time: Cloud Agents branch prefix, proof artifacts set to link only, Cloudflare Pages Git-integration *preview* branches set to none (the integration stays: it is the production deploy from `main`; the GitHub `web-preview` workflow is the only PR preview), Railway PR environments off, Copilot review off.

## CI baseline (every repo)
- One aggregate required check, `gate` (`needs:` every job, `if: always()`, fails on any failure or cancel). Nothing else is required, so path-skipped jobs never block.
- Fast tier (under ~2 min): `hygiene` (branch name, signed/owner/no-trailer commits, secret scan, actionlint, stack limits), then per-surface lint, types and unit tests. Path filtering happens inside the workflow (`dorny/paths-filter`), never with `on.paths` on a required workflow.
- Slow or optional tier: preview deploy, e2e against the preview, data-parity suites, scheduled upstream checks, Bugbot.
- Every workflow has `concurrency` with cancel-in-progress, caches bun and pip, and one install per job. Suites in the same language share one workflow with a matrix. Empty or deprecated workflows are deleted, and a check that guarded a finished migration is scoped to its paths or folded.
- `railway-staging.yml`: on `ready_for_review` and `synchronize` of a ready PR that touches the API paths, `railway up --service <svc> --environment staging` with `RAILWAY_TOKEN` (a project token scoped to staging), then waits for the health route. It never touches production.
- `bugbot-trigger.yml`: on `ready_for_review` for a non-docs PR it comments `bugbot run` with Jhonny's fine-grained PAT (`BUGBOT_TRIGGER_PAT`, this repo, pull requests: write). It never checks out PR code.
- A gate change ships with a test of the gate and allows additive data by design.

## Verification setup (before any refactor)
Every repo gets this in its first setup PR, before refactoring starts.
- Verification skill: generated with pstack `/create-verification-skill` (launch, doctor, drive, evidence, cleanup), committed in the repo.
- Feature Map: `feature-map.md` lists the main features and how to check each one. Start with 3 to 5 features and add each feature as it gets refactored.
- Control CLI: one CLI per app with small, focused subcommands, such as `doctor` (check the setup), `start`/`stop`, `drive` (click, call or type), `state` (read what the app shows), `evidence` (screenshots, logs, responses) and `reset` (back to a clean state). Output is short and readable by agents. Drivers by stack: Chrome DevTools protocol for React web, HTTP for Hono, a terminal session for the Python worker, Maestro for React Native (test on the first repo). pstack doesn't ship a control CLI, so Cursor builds it.
- Proof: a PR isn't done until it includes evidence from the control CLI for the features it touches.

## pstack
Use these skills directly by name, not through /poteto-mode: /create-verification-skill and /maintain-verification-skill (setup, then after feature changes); /correct, /how and /why (repo review, and whenever Jhonny repeats a correction twice); /architect (before Tier A designs); /blast-radius and /interrogate (before marking a risky PR ready); /tdd (every bug or CI fix); /no-comments; /setup-pstack once (models per role); /ketchup (Jhonny's catch-up after a run, typed only); /reflect then /automate-me after each run to grow a `jhonny-mode`. Skip the autopilot, orchestrate, and shipping playbooks.

## Default stack for new projects
React Native (mobile), React (web), Hono on Bun (server), shared Zod schemas package, and Python as a separate data worker behind a typed contract.

## Reference blueprint (Lauren Tan's host-backed feature model)
This is not a fixed folder layout. We adapt it to each repo after reviewing it, but the principles hold everywhere.

Concepts:
- Feature: one owned folder per feature.
- Entrypoint: one view a user can open.
- Transcript card: a body owned by the feature, for one entry type.
- Host: always-on behavior behind a type contract.
- Client: one writer, with durable renderer state behind hooks and commands.

Host-backed feature blueprint:
1. Feature UI: features/<name>, workspace/entrypoints.ts, workspace/view.ts. Thin React components that only read hooks.
2. Client: client/<name>-store.ts, a source adapter, a named hook plus command. It owns the local replica.
3. Shared edge: shared/<name>-rpc.ts via declareRpcEdge, with typed arguments and failures. Both processes import it.
4. Host extension: extensions/<name>/ with extension.ts, api.d.ts, service, and test. It owns durable behavior.

Principles we carry to every stack: one folder per feature, one writer for each piece of state, a typed shared contract at every process or service boundary, UI that only reads, durable behavior that lives in a tested service, and import rules enforced by tooling. For Hono + React/React Native + Python, the shared edge is the Zod schemas package plus the Hono typed client, and the host is the Hono service or the Python worker.

## Stack migrations (old stack to new stack)
Applies when one framework or runtime replaces another, for example Rails to Hono on Bun. The switch itself is Tier A; everything below is how the agents carry it out.
- Parity is defined by observable outcomes, never by mechanism: routes, request and response contracts (method, path, status, JSON shape, headers clients rely on), stored data, features, user-visible behavior, and the ability to reset the test environment. How the old stack produced them doesn't matter.
- Build with the new stack's own idioms, data structures and algorithms. Before porting any old mechanism, name the outcome it produces for a user, a client or an operator. Port that outcome the new stack's way, and drop the mechanism if the new stack or the platform already provides the outcome or nobody needs it. Examples for Rails to Hono on Bun: Bun's native `.env` loading instead of a recreated dotenv load order; Hono middleware (secure headers, CORS, a small host check) or the edge (forced HTTPS at Cloudflare) instead of Rails' SSL and host-authorization config; the platform's scheduled triggers instead of a recreated job runner; settings named for what they do instead of `RAILS_*` names.
- No old-stack names, file layouts or dev-mode behaviors in the new stack (env var names, setup scripts, environment folders, boot sequences) unless an external contract requires them, such as a deploy platform or a client that reads that exact name. Then it's one explicit compatibility shim, in one file, with a removal issue, listed in the PR body. This is the only exception to the no-shims rule in Autonomy 2.
- Dropping a mechanism is a Tier B decision, recorded. Dropping an outcome a user can see is Tier A.
- Retirement checklist. The old stack is deleted only when each item is proven with a test or control CLI evidence against the new stack:
  1. Contracts: every route a client calls answers with the same method, path, status codes and JSON shape (a parity test that fails on any missing route).
  2. Features: every Feature Map entry passes through the control CLI.
  3. Data: everything the old stack stored (rows, encrypted fields, files) is readable by the new stack, proven on a copy of the data.
  4. Environments: development, test and production each start from documented settings in the new stack's own form, and a missing required setting stops boot with a clear message.
  5. Test environment: one command resets it to a known state with seed data.
  6. Scheduled work: each recurring job's outcome happens on schedule on the new platform, shown by a run log.
  7. Flags: every feature flag a user can notice has the same default and effect.
  8. Security outcomes: HTTPS only, the same allowed hosts and origins, the same sign-in and session behavior, wherever it's enforced (middleware or edge).
  9. Old-stack names: the `legacy-names` count is zero, or each remaining match is a listed shim with a removal issue.
  An old mechanism with no outcome on this list is dropped, not ported.
- Enforcement: a required `legacy-names` ratchet check scans the new stack's folders for old-stack names and mechanisms, with a pattern list per migration set in the brief (for Rails: `RAILS_`, `RACK_ENV`, `bin/rails`, `bin/setup`, `config/environments`, `database.yml`, `ActiveRecord`, `Rails.`). Its baseline starts at zero, so a new match fails the PR, and raising the baseline for a shim is Tier A. A PR that introduces an old-stack name or mechanism says in its body which outcome and which external contract need it, and stops for Jhonny. The approver rejects a migration PR that ports a mechanism without naming the outcome it serves.

## Cursor native features (see cursor-native.md and cursor-commands.md)
Jhonny is on Pro+ (individual). Team-only features (Security Review, CI auto-fix, Rollouts, Team Rules) are skipped until that changes.
- Repo review: adopt Explore subagents and Instant Grep. Test Cursor Cloud MCP transcripts for the agent-mistake history. Cursor has no AGENTS.md generator or readiness score, so our repo-review skill and score stay ours.
- Setup: adopt environment.json (proposed by the agent, snapshotted, Fix Build), an allowlist-only network, environment-scoped secrets, signed commits, hooks.json (command hooks only, fail closed, deny writes to .cursor/**), deny rules in .cursor/cli.json, and the `action_required` conclusion for our checks that wait on Jhonny. Use /migrate-to-skills only when a repo has legacy .cursor/commands or intelligent rules.
- Rules and skills: adopt root and nested AGENTS.md, .cursor/BUGBOT.md, /create-rule, /create-skill, /create-hook, /create-subagent (their output lands on Tier A paths), and a read-only verifier subagent in .cursor/agents/. Project skills are committed, because cloud agents only get synced ~/.cursor/skills. Skip Bugbot learned rules and @cursor remember.
- Execution: adopt cloud agents, draft PRs while work is in progress, and Plan mode only as a self-plan (briefs say "plan, then execute without waiting"). Agents subscribe to their own PR (/subscribe) and keep it green until it merges. Test Projects (one per full refactor; every thread follows the Merging limits), /goal, the stop-hook follow-up loop with a finite loop_limit, /autopilot, and posting artifacts to GitHub set to "Link only" in the Cloud Agents dashboard, so proof links need a sign-in. Models by task: a fast, cheap model for mechanical threads (deletions, renames, docs, CI fixes), a strong one for design and security, set with /setup-pstack and in the brief. Wake budget: the coordinator wakes only on CI finished, a Bugbot review, or a merge, drops a PR's subscriptions when it merges, and never polls; Refa follows only merges into the integration branch. Skip /split-to-prs and /multitask (they wait for a human), /best-of-n and worktrees, Custom Modes, and /canvas.
- Review and merge: Jhonny's Bugbot is set to "Run only when mentioned", so Bugbot never runs on its own. When the owning agent marks a code PR ready, it comments `bugbot run` itself (Jhonny gives agents permission). It then goes through every Bugbot finding one by one and records a decision on each: fix it (push a commit and reply with the commit) or reply with a short reason it won't (false positive or out of scope, with a follow-up issue if the problem is real), then resolves that thread. A PR merges only when every Bugbot thread has a decision and is resolved, CI is green and `guard-paths` passes. The agent re-comments `bugbot run` only after a substantial code change. Docs-only PRs (only docs or Markdown files) skip Bugbot and merge on green CI; `bugbot-gate` passes for them. Bugbot ignores comments from agent accounts, so the trigger is `bugbot-trigger.yml` posting as Jhonny (see CI baseline). Until a repo has it, Refa posts `bugbot run` from Jhonny's account right when the PR goes ready, without waiting. `.cursor/config/bugbot.yaml` sets drafts: false, frequency: oncePerPr, incremental: true, effort: low, prSummary.mode: disabled (Jhonny's personal setting has PR summaries off, so the risk score is off too), autofix.mode: disabled. Jhonny's personal Bugbot settings match it, because they override the file. No /review-bugbot, /review or Agent Review before pushing: each is billed (Bugbot is about $1 to $1.50 per run) and duplicates the single Bugbot review. Findings only produce `neutral`, and later commits may get no Bugbot check, so the required check is our own `bugbot-gate` (a Bugbot run finished on the PR), not `Cursor Bugbot`. The approver is PR Routing & Approval with APPROVAL_POLICY.md and ROUTING.md if Pro+ has it, otherwise an Automation on "Pull request opened" with approvals on that applies the same policy files. The approver doesn't approve while a Bugbot finding has neither a fix commit nor a triage reply (pstack bugbot-triage). Backlog recovery exception: when a run ends with stacked unmerged PRs, children are folded into their stack's bottom PR, Bugbot's automatic review is off for the repo during the cleanup, and Bugbot runs only on each folded bottom PR (by commenting `bugbot run`); small standalone PRs merge on green CI without Bugbot. New work still gets one Bugbot review per PR. Skip Bugbot autofix and Origin auto-merge; merging uses GitHub's own auto-merge (see Git and GitHub).
- Post-merge: adopt Automations made with /automate, running as Jhonny with approvals off: the weekly gardener (cron) and the main-branch watcher ("Workflow run completed" on main and on `refactor/run-*`; if the branch is red, open a revert PR). Each automation's prompt is mirrored in docs/automations/.
- AGENTS.md tells agents never to invoke /split-to-prs, /review-bugbot, /review or /agent-review, and to use /autopilot only when the brief asks (built-in skills can't be turned off). BUGBOT.md never asks for justifying comments.
- Repo is the source of truth: anything learned in Projects context, Automation Memories, or automation prompts gets copied into the repo.

## Preview deploys (repos with a hosted site)
Applies only when the repo has a site on Cloudflare, Vercel, Netlify, or a similar provider.
- Automatic previews are turned off once per repo, not per PR. On Vercel that's `git.deploymentEnabled: false` in vercel.json (committed by Cursor). On Cloudflare it's preview branch deployments set to none (Pages) or non-production branch builds off (Workers Builds), in the dashboard. On Netlify it's Deploy Previews set to none.
- A GitHub Actions workflow deploys the preview with the provider's CLI only when the PR leaves draft (`ready_for_review`) and on later commits to a ready PR (`synchronize`). Drafts and fork PRs never deploy. A concurrency group per PR with cancel-in-progress makes a newer deploy cancel the older one.
- The preview deploy is a required check only if the repo's end-to-end tests run against the preview, so auto-merge waits for it.
- The provider's deploy token lives in a GitHub secret, scoped to previews where the provider allows it.
- The one-time setup (dashboard setting, secret, workflow file) is Tier A. After that it runs without Jhonny.
- Cursor is connected to Jhonny's Cloudflare account, so briefs can hand Cloudflare work to Cursor: turning off automatic previews, setting up the preview workflow, creating a preview-scoped deploy token, and reading build logs. Briefs name the Cloudflare change, and the agent reports it with proof (a screenshot or the API response). Production settings, production deploys, custom domains and DNS, and deleting projects stay Tier A, and Cursor never changes them without Jhonny's approval.

## Autonomy guardrails (from research, see autonomy-research.md)

### 1. When to stop and ask
- Tier A, Jhonny decides: DB or data migrations, anything touching production; deploy, infra, and CI files; secrets; auth, billing, and permissions; breaking a public contract (API routes, shared Zod exports, worker payloads); removing user-visible behavior; framework switches; new runtime dependencies or major version bumps; raising a ratchet baseline (including a `legacy-names` shim); editing guardrail files; the one-time auto-merge setup; the integration PR into a base that deploys to production; anything irreversible or external.
- Tier B, the agent decides and records it: internal refactors behind unchanged contracts, moves, dead-code deletion, tests, lint and type fixes, dropping an old-stack mechanism whose outcome is covered, and keep, redo or drop calls in backlog recovery.
- Tier C, never escalated: retries, CI flakes, rebases, restacking a child after its parent merges, mechanical merge conflicts, formatting.
- If Jhonny doesn't answer a Tier A question, that item is skipped and the rest ships.
- Enforcement: a required `guard-paths` CI check fails on Tier A paths, and on any PR the agent labeled `tier-a`, until Jhonny applies the approval label. A Cursor hooks.json denies risky commands and fails closed. Each brief has FORBIDDEN and STANDING ORDERS sections.

### 2. Pin behavior first (follows pstack's refactoring playbook and its test-behavior principle)
- Pin the contract, not the internals. Before moving structure, write characterization tests, snapshots, or an equivalence harness at the level users see: public API, routes, UI flows, worker inputs and outputs. Type checks and lint don't count as a pin. Pin tests live in a marked place (for example tests/pins/ or *.pin.test.*).
- A refactor PR changes structure, never behavior. It can't change what a pin asserts. It can move pins along with the code.
- A refactor PR can delete or rewrite tests that only protect implementation details: tests that would still pass if every imported function returned undefined, or that assert internal calls, constants, or file layout. Each one is listed in the PR body with the reason.
- When an API is replaced, migrate every caller, delete the old API, and update tests to the new contract in the same wave (pstack: migrate callers, then delete legacy APIs). No compatibility shims, except the single external-contract shim allowed in Stack migrations.
- An intended behavior change (feature, bug fix, deprecation) goes in its own PR, labeled as a behavior change. It updates or deletes the matching pins and says why. If it removes user-visible behavior, it's Tier A.
- If a refactor uncovers a bug, ship the refactor against the current, buggy behavior first, then fix the bug in a separate PR.
- Enforcement: a required `pins-untouched` check fails a refactor PR that edits or deletes pin assertions. The approval agent checks that deleted non-pin tests are listed and justified.

### 3. Off limits
- Production data and credentials, deploy, infra, and CI files, secrets, GitHub settings, and guardrail files.
- Keep these out of the agent's machine rather than relying on instructions: the Cursor environment network is allowlist-only, no production credentials exist in it, hooks deny reading .env and secret files and deny gh api writes, deploys, remote DB commands, and force-push except `git push --force-with-lease` to the agent's own run branch. GitHub secret scanning and push protection are on.

### 4. Revertible PRs, green main
- Ruleset on main, on the project base, and on `refactor/run-*`: required checks, squash only, linear history, no force-push or deletion, signed commits, 1 approval (the Cursor approval counts).
- Use the merge queue if available; otherwise require branches to be up to date.
- If main or a run's integration branch goes red, the first action is a revert PR.

### 5. Ratchets (counts only go down)
- Duplicate code: jscpd (or the stack's equivalent) count with a shrink-only baseline; the failure says which blocks repeat and how to extract them.
- ESLint bulk suppressions with noInlineConfig, type-coverage for `any` with `@ts-ignore` and `@ts-expect-error` at zero, dependency-cruiser with a shrink-only baseline for cycles and layers, a basedpyright baseline plus Ruff counts for Python, and the `legacy-names` count during a stack migration.
- No inline disable directives, which fits the no-comments rule. A no-comments lint is required (exemption for license headers and generated files to be decided).
- Enforcement: a required `ratchet` CI job. Raising any baseline is Tier A. Each PR body shows the counts before and after.

### 6. Reporting
- PR body: what changed, the pins, the ratchet deltas, Tier B decisions, and for stack migrations the outcome each ported piece serves.
- Decision records in docs/decisions/NNNN-*.md: context, decision, alternatives, evidence, how to undo, status.
- Run report in docs/runs/YYYY-MM-DD-*.md, the one thing Jhonny reads: outcome, merged PRs, ratchet table, pins, decisions, parked Tier A items, failures, attention items, the merge metrics from merge-playbook.md, and a scorecard: PRs opened, closed unmerged %, max stack depth, CI-fix-only PRs, human interventions (target 0 for naming and signing), wall-clock, and model and token usage from the Cursor dashboard export.
- A check that couldn't run is reported as inconclusive with the reason, never as done. Fixes are re-checked on the target branch after merging.
- Enforcement: required `report-present` and `decision-link` checks.

### Open questions for the first test repo
- How often does guard-paths stop legitimate refactors?
- What counts as a good-enough pin per stack (render snapshots plus one end-to-end flow for React and React Native, request replay for Hono, golden files for Python)? Seed 5 deliberate behavior changes and count how many the pins catch.
- Exact network allowlist, and whether hooks reload mid-run.
- Does Bugbot with drafts: false and oncePerPr review exactly once when a draft is marked ready? Does it post a check on later commits? Who resolves Bugbot threads after fixes, given it doesn't re-run?
- Is PR Routing & Approval available on Pro+? Does it wait on a Bugbot check that never comes? Does the Cursor approval satisfy the required review?
- Do pstack's plugin skills load in cloud agents, or do we commit the ones we use?
- Preview deploys: provider token scope, and whether the e2e suite needs the preview.
- Do the agent's own fix pushes after approval cancel auto-merge? Does the App-token merge trigger post-merge workflows? Is a 60-minute objection window worth it? Is the merge queue available?
- With signed commits required, does GitHub let auto-merge squash a PR authored by Jhonny when auto-merge was turned on by an App token, or must it be turned on under Jhonny's identity?
- Can the Cursor agent merge with its gh token or the Cursor GitHub integration, given the earlier 403s on secrets?
- Are a stack depth of 2 and 5 open PRs the right limits, judged by the next run's metrics?
- Does the run report fit on one screen?

## Changelog
- 4.2 (2026-10-13): PRs go draft, then ready, then `main`. No `staging` branch; staging is a Railway environment only.
- 4.1 (2026-10-13): after davar #320. No checks or rulesets on `staging`; `gate` is required on `main` only and CI runs on every PR. New PR flow: draft, then ready deploys the Cloudflare preview against Railway staging and, for API changes, deploys the PR to Railway staging (one PR at a time); Railway PR environments off. All AGENTS.md prefixes are used by type; the brief names the branch and the agent renames first (no dashboard default). Cloudflare Git integration stays for production; only its preview builds are turned off.
- 4.0 (2026-10-13): after the davar post-v2 review (25 PRs, 28% closed unmerged, stack depth 8, 5 CI-fix PRs on the promotion). Every rule names its enforcer; budgets up front; new Preflight and CI baseline sections (one required `gate`, `hygiene` job for branch/signature/trailer, no branch filters, concurrency, caches, duplicate-code ratchet, Bugbot trigger Action); branch prefixes apply to refactor runs too, dashboard prefix and rename step; the cloud-agent trailer is stripped by hook and rejected by CI; integration branches get main's CI; gh is read-only and the PR tool is the write path; link-only artifacts, models by task, wake budget; time-to-rewrite question; inconclusive reporting and a run scorecard; pstack usage map.
- 3.3 (2026-10-08): agent triggers Bugbot on ready and resolves each finding with a decision.
- 3.2 (2026-10-07): Bugbot is manual only (Run only when mentioned). Agents comment `bugbot run` once when a code PR goes ready; docs-only PRs skip Bugbot.
- 3.1 (2026-10-07): backlog recovery folds each stack into its bottom PR and runs Bugbot only on those; small standalone PRs merge on green CI without Bugbot.
- 3.0 (2026-10-07): merging reworked after the first run (35 PRs, none merged, chains up to 9 deep). PRs squash-merge once open, green and reviewed: the owning agent merges until the repo has the auto-merge setup, then GitHub auto-merge does; Tier A PRs wait on Jhonny's label. A brief may name an existing branch as the integration branch. Merge as you go, one integration branch per run, limits of stack depth 2 and 5 open PRs, a written merge playbook (merge-playbook.md) with backlog recovery and end-of-run metrics. New Stack migrations section: parity by outcomes, the new stack's own idioms, an outcome-based retirement checklist, and a `legacy-names` ratchet.
- 2.10 (2026-10-07): Cursor has access to Jhonny's Cloudflare account; briefs can hand Cloudflare preview setup to it, while production, domains, DNS and deletions stay Tier A.
- 2.9 (2026-10-07): every agent commit is signed with a dedicated agent SSH signing key on the owner's account and must show Verified; replaces the outdated "Cursor Agent" authorship note.
- 2.8 (2026-10-07): branch prefixes by PR type (feat, fix, hotfix, chore, docs, refactor, test, release), one spelling each, for all work outside a refactor run, written into AGENTS.md and enforced by a CI branch-name check.
- 2.7 (2026-10-07): every branch in a refactor run is named `refactor/<name>`, never `cursor/`; briefs set the branch name.
- 2.6 (2026-10-07): added the verification setup step: verification skill, Feature Map, a control CLI with focused subcommands per app, and proof in every PR.
- 2.5 (2026-10-07): bugbot.yaml turns PR summaries off to match Jhonny's personal setting.
- 2.4 (2026-10-07): Cursor commands decided per stage (see cursor-commands.md). PRs open as drafts. Bugbot runs once when the PR leaves draft. `bugbot-gate` replaces requiring `Cursor Bugbot`. Approver fallback for Pro+. /review and Agent Review dropped. Added the preview-deploy rule.
- 2.3 (2026-10-07): Bugbot runs once per PR instead of before every push, to control cost.
- 2.2 (2026-10-07): added the Cursor native features section (adopt, test, skip) and its AGENTS.md and BUGBOT.md notes.
- 2.1 (2026-10-07): pin rule reworked. Pins cover the contract, not internals. Implementation-detail tests can be deleted when justified. Behavior changes and API replacements update tests in their own labeled PR.
- 2.0 (2026-10-06): autonomy guardrails (tiers, pins, off-limits, green main, ratchets, reporting), and merging handled by the repo.
- 1.x (2026-10-06): general rules, git and GitHub, repo review, pstack usage, default stack, reference blueprint.
