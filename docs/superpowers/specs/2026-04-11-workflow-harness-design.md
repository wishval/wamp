# Workflow Harness Design — 2026-04-11

Design for a repeatable, project-local Claude Code workflow in the Wamp repository. Captures how task lists are received, planned, executed, reviewed, committed, merged, and handed off to the next session.

## Goals

- Force `superpowers:brainstorming` before any multi-task work, so designs are explicit and reviewable.
- Let the main session (opus) decide when to dispatch subagents — parallel for independent tasks, `Explore` for code search, sonnet for mechanical edits — without user prompting.
- Guarantee a human-readable end-of-list report before any commit is treated as "done".
- Give the user a single slash command (`/wrap-session`) that ends a session cleanly: commit, merge, starter prompt for the next session.
- Keep `main` safe: never auto-commit to it, always require explicit approval for merges.
- Keep the artifacts minimal and project-local — no changes to `~/.claude/` globals.

## Non-goals

- No automatic push to any git remote.
- No support for restarting mid-list after a crash. New session just starts fresh.
- No support for parallel feature branches in a single session (use two worktrees + two terminal sessions if needed).
- No global (`~/.claude/`) changes. Workflow is Wamp-specific.
- No auto-deletion of merged feature branches (user chooses).

## Architecture

Four project-local touch points. Nothing touches global config, no new hooks in `settings.json`.

```
WinampMac/
├── CLAUDE.md                              ← new "## Workflow" section (~15 lines)
├── .claude/
│   └── commands/
│       └── wrap-session.md                ← NEW slash command definition
├── .gitignore                             ← add docs/superpowers/next-session.md
└── docs/superpowers/
    ├── specs/                             ← existing, used for brainstorm specs
    ├── plans/                             ← existing, used for implementation plans
    └── next-session.md                    ← NEW (gitignored) starter-prompt artifact
```

## Component 1 — `CLAUDE.md` workflow section

Appended to `CLAUDE.md` after the existing `## Conventions` section. Declarative, not imperative: it names the skills and commands to invoke, doesn't re-explain how they work (skills are self-documenting when loaded).

Final text (7 bullets, ~15 lines):

```markdown
## Workflow

- **Multi-task requests (2+ items)** — start with `superpowers:brainstorming`. Save the resulting plan under `docs/superpowers/plans/YYYY-MM-DD-<slug>.md` before writing code.
- **Branching** — each task list starts on a `feature/<slug>` branch off `main`. If the user is on `main` when a list begins, create the branch first. Never commit a task list directly to `main`.
- **Commit granularity** — 1 task = 1 commit. Don't batch. The pre-commit hook (`.git/hooks/pre-commit`) handles build verification for Swift changes; doc-only commits skip the build.
- **Subagent policy** — dispatch independent tasks to parallel subagents (opus for architectural/complex work, sonnet for mechanical edits). Sequential or single tasks stay in the main session. Code exploration and search always go to the `Explore` subagent.
- **Opus reviews sonnet** — when a sonnet subagent returns, the main (opus) session reviews its diff before marking the task complete. If issues are found, fix them inline in the main session rather than re-dispatching to sonnet.
- **End-of-list report** — after every task list, post a short report: (1) what was done, (2) non-obvious decisions taken mid-flight, (3) anything skipped and why. Wait for user approval before moving on. Do not request screenshots; the user provides them when they want visual feedback.
- **Session wrap-up** — when the user invokes `/wrap-session`: confirm the report, commit any pending work, ask for explicit approval, merge the feature branch into `main` with `--no-ff`, write `docs/superpowers/next-session.md` with a starter prompt, print the same prompt in chat, and tell the user they can now `/clear`.
```

The existing `## Conventions` section is untouched. Resulting CLAUDE.md grows from 82 to ~99 lines.

## Component 2 — `.claude/commands/wrap-session.md`

A project-local slash command. When the user types `/wrap-session`, Claude Code injects the command body into the main session as instructions. Six sequential steps, no parallelization:

1. **Verify state.** `git status --short` and `git branch --show-current`. If on `main`, exit with "nothing to wrap up". If uncommitted changes belong to the current task list, stage and commit them as a final commit using the established `feat:` / `fix:` / `chore:` / `docs:` style. If uncommitted changes clearly don't belong to the current work, surface them and ask the user; don't auto-commit.
2. **Confirm the list is truly done.** If no end-of-list report has been posted in this session, post one now (format: what was done / decisions / what was skipped). Ask explicitly: "Ready to merge `<branch>` into main?" — wait for "yes" or equivalent. This is the hard-to-reverse gate; never proceed on implicit approval.
3. **Merge to main.** Only after explicit approval: `git checkout main`, `git pull --ff-only` if a remote exists (otherwise skip silently), `git merge --no-ff <feature-branch> -m "Merge branch '<feature-branch>'"`. Do not delete the feature branch automatically — ask the user; default to keeping it. On merge conflicts, stop and let the user resolve; no auto-resolution.
4. **Generate the next-session starter prompt.** Compose a prompt under 200 words covering: project context (one sentence), what just shipped (2-3 bullets), open follow-ups mentioned but postponed, and one suggested next step framed as a question (not a lock-in). Plain text, no nested code blocks.
5. **Persist and surface the prompt.** Write it to `docs/superpowers/next-session.md` with a date header, overwriting any previous content. Print the same prompt in chat inside a single fenced code block so the user can copy it.
6. **Signal completion.** Tell the user: "Wrap-up complete. You can `/clear` and start a new session with the prompt above (or read it from `docs/superpowers/next-session.md`)." Stop. No further actions.

The command file uses a Claude Code slash-command frontmatter with a `description` field and the six steps as the body.

## Component 3 — `.gitignore` entry

Three lines appended to the end of `.gitignore`:

```gitignore

# Claude Code workflow artifacts
docs/superpowers/next-session.md
```

## Component 4 — `docs/superpowers/next-session.md`

Not created at install time. Generated lazily by the first `/wrap-session` invocation. Gitignored, so it's a local artifact — the user can edit it manually between sessions if they want to tweak the next-session handoff.

## Data flow: one full session

```
User: "Here's my task list: [5 items]"
   ↓
opus (main session): invokes brainstorming → writes plan to docs/superpowers/plans/YYYY-MM-DD-<slug>.md
   ↓
opus: checks current branch → creates feature/<slug> off main if needed
   ↓
For each task in the plan:
   opus: decides (self or parallel subagent) → executes → if sonnet, reviews diff → commits 1 task = 1 commit
   ↓
opus: posts end-of-list report → waits for approval
   ↓
[user may request fixes: opus adds tasks, re-runs the loop]
   ↓
User: "/wrap-session"
   ↓
opus: runs 6-step command → asks explicit merge approval → merges to main → writes next-session.md → prints prompt
   ↓
User: "/clear" → new session → paste starter prompt → repeat
```

## Safety properties

- **Main branch never takes direct commits from a task list.** A feature branch is always created first. This is enforced by the CLAUDE.md bullet and by the `/wrap-session` verify-state step.
- **Merges require explicit in-the-moment approval.** No prior conversational "yes, merge when done" counts. Prevents accidental merges if the user changed their mind.
- **Pre-commit hook catches build breakage before commits land.** Already in place (`.git/hooks/pre-commit`), unchanged by this design.
- **Unrelated uncommitted changes are surfaced, not auto-committed.** Protects against absorbing the user's parallel work into the wrong commit.
- **Workflow can be bypassed per-session.** Explicit user instructions override CLAUDE.md (per `superpowers:using-superpowers` priority rules). "Just fix this one thing quickly" disables the brainstorming-first rule for that interaction.
- **Full rollback in under 2 minutes.** Delete `.claude/commands/wrap-session.md`, revert the CLAUDE.md section, revert the `.gitignore` line. No persistent global state.

## Validation plan

After implementation:
1. Open a new session, give a multi-task request, observe that brainstorming is invoked without being asked.
2. Type `/` at the prompt, confirm `wrap-session` appears in the slash-command list.
3. Run `git check-ignore docs/superpowers/next-session.md` and confirm it returns the path (gitignore works).
4. Do a dry-run: create a dummy feature branch, make a trivial commit, run `/wrap-session`, verify the 6 steps execute in order, merge prompts for approval, next-session.md is written.

## Out of scope (explicitly deferred)

- Porting the workflow to user-global (`~/.claude/`). Revisit only if a second project adopts the same pattern.
- Automatic state recovery after session crash.
- Parallel feature branches in one session.
- Auto-push to remote.
- Screenshot-request automation during task execution (user provides screenshots on demand).
- Any changes to the existing pre-commit hook or to `settings.json` hooks.
