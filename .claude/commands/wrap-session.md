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
