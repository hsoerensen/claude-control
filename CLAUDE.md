# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git Workflow

**Linear history only.** The repo is configured with `pull.rebase true` and `merge.ff only` to prevent merge commits. Always use rebase to integrate upstream changes:

- `git pull` automatically rebases (configured locally)
- Merge commits are blocked by `merge.ff only` — use `git rebase main` instead of `git merge main`
- When resolving conflicts during rebase, use `git rebase --continue` after fixing each commit

**Commit messages:** Always use `git commit -m '...'` with a single string. For multi-line messages, use multiple `-m` flags: `git commit -m 'title' -m 'body'`. Never use HEREDOC or command substitution for commit messages.

## Visual Design Anti-Patterns

**NEVER use emoji-style icons** (🔴🟠🟡🔵⚪) in CLI output. They cause cognitive overload.

**ALWAYS use small Unicode symbols** with semantic colors:
- Status: `○ ◐ ● ✓ ❄`
- Priority: `● P0` (filled circle with color)

## Project Overview

claude-control is a configuration-only project that keeps `claude remote-control` running as a persistent service with fresh git worktrees. It provides service templates (systemd, launchd), an install script, and a WorktreeCreate hook — no custom binary.

## Design Principles

**Uninstall must be as easy as install.** Every install path must have an equally simple uninstall. If a user can install with a single curl command, they must be able to uninstall with a single curl command too.

**No elevated privileges.** Everything runs in user space. No `sudo`, no writes to system directories. All files go under `~/.config/`, `~/Library/`, or similar user-owned paths.

**Plain language.** README and user-facing text must be easy to understand for non-technical, non-native English speakers. Avoid jargon in explanations — use simple words and short sentences. Troubleshooting sections may use technical terms since users there are debugging specific issues.

## Validation

```bash
bash -n install.sh
```

## Key Files

- `install.sh` — setup/uninstall script for Linux and macOS
- `templates/claude-control@.service` — systemd user unit template
- `templates/com.claude-control.plist.tmpl` — launchd plist template
- `docs/superpowers/specs/` — design spec
- `docs/superpowers/plans/` — implementation plan

## Development Workflow

For all feature work and bug fixes, follow this pipeline in order, unless granted permission to deviate:

1. **`superpowers:brainstorming`** — explore intent, propose approaches, get design approval before touching code
2. **`superpowers:writing-plans`** — produce a step-by-step implementation plan saved to `docs/superpowers/plans/`
3. **`superpowers:subagent-driven-development`** — execute the plan with fresh subagents per task and two-stage review (spec then quality) after each

Do not write code before completing steps 1 and 2.

## Session Completion

Work is not done until pushed. Every session must end with:

```bash
git pull --rebase
git push
```
