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
- **Do not make JJ commits inside a worktree.** A worktree created from this repo contains its own copy of `.jj/` (observed: `ls` shows one in the APFS-cloned worktree, and `jj st` there reports the worktree's own changes). A copied `.jj/` is a separate JJ repo store, so JJ commits made there are expected not to appear in the owner's repo; this was not tested. Use plain `git` inside worktrees.
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
   git status --short          # confirm only intended files are staged
   git commit -m "<what changed and why>"
   ```

   Do not stage `build/`, `.dart_tool/`, or other ignored output.

2. **Make JJ import it and check it from the owner's side.** Any `jj` command in the main checkout imports new Git commits and creates or moves the bookmark of the same name. Read-only is enough:

   ```sh
   cd ../painter
   jj log -r '<feature-branch> | @'
   ```

   Right after step 1 the feature commit appears as a **sibling** of the owner's working copy `@` (both on the commit the branch was cut from). That is visible but not yet "on top of" the owner's work.

3. **Stack it on the owner's current work.** The owner's `@` is often an empty change, so the content is identical and stacking is only a matter of parentage. Rebase *only the feature change* onto `@`; this does not move or edit `@`:

   ```sh
   jj rebase -r <feature-branch> -d @
   ```

   If the owner's `@` has real content, this puts the feature on top of it; resolve any conflicts JJ reports before handing off. Rebase with `jj` rather than `git rebase` in the worktree: JJ is the owner's tool and it tracks `@`, whose commit id changes whenever the owner edits.

4. **Re-attach the worktree.** The JJ rebase rewrites the feature commit and moves the Git branch to the new commit id. The worktree still has the *old* commit checked out, so it shows a detached `HEAD`. Switch it to the branch again:

   ```sh
   cd ../painter-<feature>
   git switch <feature-branch>
   ```

   Further commits in the worktree then build on the stacked commit. Never `git commit` while detached; that work is not on the branch.

5. **Hand off.** Report the branch name, its tip commit, and the command that shows it (`jj log -r '<feature-branch>'`). The commit's tree is what the agent tested, so re-run `flutter analyze` and `flutter test` only if the stacking involved conflicts or the owner's `@` had real changes.

6. **The owner adopts it.** The owner chooses; agents do not move `@`. Typical options:

   ```sh
   jj new <feature-branch>               # start the next change on top of the feature
   jj rebase -r @ -d <feature-branch>    # move the current working change onto it
   jj bookmark set main -r <feature-branch>   # advance a main bookmark, if the project has one
   ```

7. **Clean up after adoption.**

   ```sh
   git worktree remove ../painter-<feature>
   jj bookmark delete <feature-branch>   # or `git branch -d <feature-branch>`
   ```

## What agents must and must not do

- Work in a worktree on a feature branch; do not edit the main checkout's files.
- Commit with `git` when a unit of work is complete, so the work is visible. Uncommitted work in a worktree is not delivered.
- In the main checkout, read-only `jj log`, `jj st`, `jj show`, and `jj diff` are always fine. Do not run other mutating `jj` commands (`jj new`, `jj edit`, `jj abandon`, `jj squash`, `jj bookmark set`) there without the owner asking. The one sanctioned exception, when the owner asks for the work to be on top of theirs, is `jj rebase -r <feature-branch> -d @`, which rewrites only the feature change.
- Never move, edit, or describe the owner's `@`.
- Do not rewrite or delete commits and branches that already existed before the task.

## Not verified

- Behaviour with a remote: this repository has no configured Git remote (`jj git remote list` is empty), so push/fetch flows are not described here.
- `jj workspace`-based parallel work; it is not used here.
