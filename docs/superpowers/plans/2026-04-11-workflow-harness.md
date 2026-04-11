# Workflow Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install a project-local Claude Code workflow in the Wamp repo: a `## Workflow` section in `CLAUDE.md`, a `/wrap-session` slash command, and a gitignored `next-session.md` artifact.

**Architecture:** Four project-local changes, zero global config. All touch points described in `docs/superpowers/specs/2026-04-11-workflow-harness-design.md`. The feature lives entirely in plain text files (Markdown + `.gitignore`) — no code compilation, no Swift changes, so the pre-commit build hook will be a no-op for every commit in this plan.

**Tech Stack:** Markdown (CLAUDE.md + slash command frontmatter), `.gitignore`, git.

---

## File structure

Files created or modified by this plan:

- **Modify** `CLAUDE.md` — append a new `## Workflow` section (~15 lines) after the existing `## Conventions` section.
- **Create** `.claude/commands/wrap-session.md` — Claude Code slash-command definition with a `description` frontmatter and a 6-step body.
- **Modify** `.gitignore` — append a 3-line block reserving `docs/superpowers/next-session.md`.
- **No file created** for `docs/superpowers/next-session.md` — it is generated lazily on the first `/wrap-session` call.

No Swift files touched. No existing conventions or sections edited in place — only appends.

---

## Task 0: Create feature branch

**Files:** none

- [ ] **Step 0.1: Verify current state**

Run: `git status --short && git branch --show-current`
Expected output:
```
main
```
(No uncommitted changes — the spec commit `d21daf9` is already in `main`.)

- [ ] **Step 0.2: Create and switch to feature branch**

Run: `git checkout -b feature/workflow-harness`
Expected output:
```
Switched to a new branch 'feature/workflow-harness'
```

- [ ] **Step 0.3: Verify branch**

Run: `git branch --show-current`
Expected output:
```
feature/workflow-harness
```

---

## Task 1: Append the `## Workflow` section to `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md` (append at end of file)

- [ ] **Step 1.1: Read current file to confirm append target**

Run: `tail -5 CLAUDE.md`
Expected: last line is either a blank line or the final bullet of the `## Conventions` section ("Playlist supports drag-and-drop ...").

- [ ] **Step 1.2: Append the workflow section**

Use the Edit tool on `CLAUDE.md`. `old_string` is the last line of the existing file (currently the final `## Conventions` bullet). `new_string` is that same line followed by a blank line and the new section.

Exact block to append:

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

- [ ] **Step 1.3: Verify the append**

Run: `wc -l CLAUDE.md && tail -20 CLAUDE.md`
Expected: line count is 82 + 17 = 99 (82 original + 1 blank separator + 1 heading + 1 blank line after heading + 7 bullets which may wrap). Tail shows the new `## Workflow` heading and all 7 bullets.

- [ ] **Step 1.4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add Workflow section to CLAUDE.md"
```
Expected: pre-commit hook runs, detects no staged `.swift` files, exits 0 immediately. Commit lands.

---

## Task 2: Create `.claude/commands/wrap-session.md`

**Files:**
- Create: `.claude/commands/wrap-session.md`

- [ ] **Step 2.1: Verify parent directory**

Run: `ls -d .claude/`
Expected: directory exists (already contains `settings.local.json` and `worktrees/`).

- [ ] **Step 2.2: Create the commands subdirectory**

Run: `mkdir -p .claude/commands`
Expected: no output. Subsequent `ls .claude/commands/` shows an empty directory.

- [ ] **Step 2.3: Create the slash-command file**

Use the Write tool to create `.claude/commands/wrap-session.md` with this exact content:

```markdown
---
description: End a work session — commit, merge feature branch to main, generate starter prompt for the next session
---

Execute these steps in order. Do not skip steps. Do not parallelize.

## 1. Verify state
- Run `git status --short` and `git branch --show-current`.
- If the current branch is `main`: stop and tell the user "nothing to wrap up — you're on main with no feature branch". Exit.
- If there are unstaged/untracked changes that belong to the current task list: stage and commit them as a final commit before proceeding. Use the established message style (`feat:` / `fix:` / `chore:` / `docs:`).
- If there are changes that clearly do NOT belong to the current work (e.g., unrelated edits): surface them to the user and ask what to do. Do not auto-commit them.

## 2. Confirm the list is truly done
- If you have not already posted an end-of-list report in this session, post one now (format: what was done / decisions taken mid-flight / what was skipped and why).
- Ask explicitly: "Ready to merge `<branch>` into main?" — wait for the user's "yes" or equivalent. Do NOT proceed on implicit approval. This is the hard-to-reverse gate.

## 3. Merge to main
- Only after explicit approval:
  - `git checkout main`
  - `git pull --ff-only` if a remote is configured (skip silently if none).
  - `git merge --no-ff <feature-branch> -m "Merge branch '<feature-branch>'"`
  - Do NOT delete the feature branch automatically. Ask the user if they want it deleted; default to keeping it.
- If merge conflicts occur: stop, surface them, let the user resolve. Do not attempt auto-resolution.

## 4. Generate the next-session starter prompt
Compose a prompt that lets a fresh session pick up where this one left off. Include:
- **Project context** — one sentence: "Wamp, macOS/Swift/AppKit, Winamp clone, working directory `/Users/valerijbakalenko/Documents/Stranger/Code/AI/WinampMac`".
- **What just shipped** — 2-3 bullets summarizing the merged work (from the report in step 2).
- **Open follow-ups** — anything the user mentioned but postponed, or "out of scope" items from the current list that might become the next list.
- **Suggested next step** — ONE concrete suggestion for what to do next, framed as a question ("Want to tackle X next, or something else?"). Do not lock the user into a specific next task.

Keep the whole prompt under 200 words. Plain text, no code blocks nested inside it.

## 5. Persist and surface the prompt
- Write the prompt to `docs/superpowers/next-session.md`, overwriting any previous content. Include a header line with the current date (`# Next session — YYYY-MM-DD`).
- Print the exact same prompt in the chat, wrapped in a single fenced code block so the user can copy it cleanly.

## 6. Signal completion
- Tell the user: "Wrap-up complete. You can `/clear` and start a new session with the prompt above (or read it from `docs/superpowers/next-session.md`)."
- Do not take any further actions. Stop.
```

- [ ] **Step 2.4: Verify the file**

Run: `wc -l .claude/commands/wrap-session.md && head -3 .claude/commands/wrap-session.md`
Expected: line count roughly 40-50, first three lines are the frontmatter (`---`, `description: …`, `---`).

- [ ] **Step 2.5: Commit**

```bash
git add .claude/commands/wrap-session.md
git commit -m "feat: add /wrap-session slash command"
```
Expected: pre-commit passes (no Swift staged). Commit lands.

---

## Task 3: Add `.gitignore` entry for `next-session.md`

**Files:**
- Modify: `.gitignore` (append 3 lines at end)

- [ ] **Step 3.1: Read current gitignore tail**

Run: `tail -3 .gitignore`
Expected: last lines are the Playgrounds section (`timeline.xctimeline`, `playground.xcworkspace`).

- [ ] **Step 3.2: Append the workflow artifact block**

Use the Edit tool on `.gitignore`. `old_string` is the last line of the existing file (e.g. `playground.xcworkspace`), `new_string` is that same line followed by the block below.

Exact block to append:

```

# Claude Code workflow artifacts
docs/superpowers/next-session.md
```

- [ ] **Step 3.3: Verify the ignore rule**

Run: `git check-ignore -v docs/superpowers/next-session.md`
Expected output: `.gitignore:<N>:docs/superpowers/next-session.md	docs/superpowers/next-session.md` (where `<N>` is the line number of the new rule).

- [ ] **Step 3.4: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore Claude Code workflow artifacts"
```
Expected: pre-commit passes. Commit lands.

---

## Task 4: Validation

**Files:** none (read-only checks)

- [ ] **Step 4.1: Confirm all four commits are on the feature branch**

Run: `git log --oneline main..feature/workflow-harness`
Expected: three commits visible — "docs: add Workflow section", "feat: add /wrap-session slash command", "chore: gitignore Claude Code workflow artifacts".

- [ ] **Step 4.2: Confirm CLAUDE.md ends with the new section**

Run: `grep -n "^## Workflow" CLAUDE.md`
Expected output: `83:## Workflow` (or similar line number ≥82).

- [ ] **Step 4.3: Confirm slash command file exists**

Run: `test -f .claude/commands/wrap-session.md && echo "present"`
Expected output: `present`

- [ ] **Step 4.4: Confirm gitignore rule is active**

Run: `git check-ignore docs/superpowers/next-session.md`
Expected output: `docs/superpowers/next-session.md` (exit code 0).

- [ ] **Step 4.5: End-of-list report**

Post a report to the user in format B:
1. **What was done** — branch created, CLAUDE.md workflow section added, /wrap-session command created, .gitignore entry added, validation checks passed.
2. **Decisions taken mid-flight** — any deviations from the plan during execution (likely none, but surface if so).
3. **What was skipped and why** — nothing should be skipped; if the validation of slash-command discoverability (`/` menu) requires a Claude Code restart, note that as a manual post-install check the user needs to run.

Wait for user approval before proceeding to `/wrap-session`.

---

## Notes on execution

- **This plan cannot be tested by `xcodebuild`.** It touches no Swift files. Validation is done via `git` and filesystem checks.
- **Slash-command discoverability** requires Claude Code to reload its project-local commands. After Task 4 passes, the user may need to restart Claude Code (or open a new session) for `/wrap-session` to appear in the `/` menu. This is a platform limitation, not a plan failure.
- **Idempotency:** if any step needs to be re-run, all edits are append-only, so running Task 1 / Task 3 twice would duplicate content. Check before re-running.
- **Rollback:** `git checkout main && git branch -D feature/workflow-harness` reverts the entire plan. No external state to clean up.
