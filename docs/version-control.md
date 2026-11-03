# Version Control: JJ, Git, and Worktrees

The main checkout is a [Jujutsu](https://github.com/jj-vcs/jj) (JJ) repository colocated with Git: `.jj/` and `.git/` sit side by side, and JJ keeps its view of history in sync with Git's refs. The human owner works in the main checkout with `jj`. Agents (and any parallel feature work) use separate **Git worktrees** so they never touch the owner's working copy.

This page records how those pieces fit together and how finished work reaches the owner. Facts below were observed on this repository with `jj 0.45.1`; anything not observed is marked as such.

## The model

| Thing | Where it lives | Who sees it |
| --- | --- | --- |
| Main checkout (`painter/`) | JJ working copy `@`, colocated with Git | The owner, through `jj log` / `jj st` |
| Feature worktree (`painter-<feature>/`) | A separate directory created with `git worktree add` | Only whoever opens that directory |
| Git branches and commits | The **shared** `.git` object store, used by every worktree | Everyone, once committed |

Key consequences:

- **Uncommitted work in a worktree is invisible to the owner.** JJ snapshots only the main checkout's directory. Files sitting in another worktree's directory are never imported, so `jj log` and `jj st` in the main checkout show nothing of them.
- **A Git commit is visible.** Worktrees share the main repo's Git object store. A commit made with `git commit` in a worktree is reachable from the main checkout's `.git`, and JJ imports Git branches into its own bookmarks automatically the next time any `jj` command runs there.
- **Do not make JJ commits inside a worktree.** A worktree created from this repo contains its own copy of `.jj/` (observed: the APFS clone duplicates it), and that copy has a separate JJ operation store. JJ changes made there do not appear in the owner's repo. Use plain `git` inside worktrees.
- **Git worktrees and JJ workspaces are different things.** `git worktree` is what this project uses. `jj workspace add` creates JJ-native workspaces that share one JJ repo; it is not part of this workflow.

## Starting a feature

From the main checkout, create a worktree on a new branch next to the repo:

```sh
git worktree add -b <feature-branch> ../painter-<feature> HEAD
```

Do all feature work, tests, and builds inside `../painter-<feature>`. Edit files by absolute path or with the worktree as the working directory so changes do not land in the main checkout by accident.

## When the feature is complete

"Complete" means the acceptance criteria are verified and `docs/status.md` records the results (see [AGENTS.md](../AGENTS.md)). Then, so the owner can see and adopt the work:

1. **Commit on the feature branch, from the worktree, with Git.**

   ```sh
   cd ../painter-<feature>
   git add -A
   git commit -m "<what changed and why>"
   ```

   Stage only intended files. Do not include `build/`, `.dart_tool/`, or other ignored output; check `git status` first.

2. **Stack it on the owner's current work.** The branch must descend from whatever the owner is building on, not from an older commit, or the work shows up as a side branch the owner must rebase by hand. Rebase the feature branch onto the owner's current tip (the commit the owner's `@` sits on, found with `jj log` in the main checkout), still using Git in the worktree:

   ```sh
   git rebase <owner-tip-commit>
   ```

   Rerun `flutter analyze` and `flutter test` if the rebase changed anything.

3. **Tell JJ about it.** In the main checkout any `jj` command imports the new Git commits and moves the bookmark of the same name:

   ```sh
   jj log -r '<feature-branch>'
   ```

   The commit and its bookmark are now visible as ordinary JJ changes.

4. **The owner adopts it with normal JJ operations,** for example:

   ```sh
   jj rebase -r @ -d <feature-branch>   # put the owner's working copy on top of the feature
   jj new <feature-branch>              # or start a fresh change on top of it
   ```

   or `jj bookmark set main -r <feature-branch>` if the project has a main bookmark to advance. Which of these applies is the owner's call; agents do not move the owner's `@`.

5. **Clean up after adoption.**

   ```sh
   git worktree remove ../painter-<feature>
   git branch -d <feature-branch>       # or `jj bookmark delete <feature-branch>`
   ```

## What agents must and must not do

- Work in a worktree on a feature branch; do not edit the main checkout's files.
- Commit with `git` when a unit of work is complete, so the work is visible. Uncommitted work in a worktree is not delivered.
- Do not run mutating `jj` commands (`jj new`, `jj rebase`, `jj abandon`, `jj edit`, `jj squash`, `jj bookmark set`) in the main checkout without the owner asking. Read-only `jj log`, `jj st`, and `jj show` are fine.
- Do not rewrite or delete commits and branches that already existed before the task.
- Report the branch name and tip commit when handing off, plus the exact `jj` command that shows it.

## Not verified

- Behaviour with a remote: this repository has no configured Git remote (`jj git remote list` is empty), so push/fetch flows are not described here.
- `jj workspace`-based parallel work; it is not used here.
