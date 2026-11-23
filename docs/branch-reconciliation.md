# Reconcile template branches

GitHub's **Use this template** copies the files from the default branch or, if
you select **Include all branches**, copies each branch into its own initial
commit. Those initial commits have no common ancestor, so GitHub cannot compare
them in a pull request. The template's default branch is `develop`. If you only
need `develop` and `main`, leave **Include all branches** unchecked. [GitHub's template documentation](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-repository-from-a-template)

## Run setup before making commits

Clone the generated repository and run `make setup` from its root. Setup runs
`make reconcile-branches` first. After reconciliation succeeds, setup creates or
refreshes `.venv`, configures Git to use the committed hooks, and installs the
hook environments. A reconciliation error stops setup before those local steps.

Run `make reconcile-branches` to repeat just the branch step. The target calls
[`eng/scripts/reconcile_branches.py`](../eng/scripts/reconcile_branches.py), which you
can also run directly with Python 3.10 or later.

```sh
python3 eng/scripts/reconcile_branches.py
```

The script uses Git and the credentials for `origin`. A repository with an
`origin` needs network access for the fetch if that remote is hosted. A push
requires permission to create the missing branch or update `main`. Run setup
before applying branch rules that would block the push.

## What changes on `origin`

The script fetches all branch tips from `origin`, even after a single-branch
clone. It uses the actual remote branches to decide what to do.

| Fetched branches | Result |
| --- | --- |
| Only `develop` exists | Create `main` at the same commit. |
| Only `main` exists | Create `develop` at the same commit. |
| `main` and `develop` have unrelated initial commits | Move `main` to the `develop` commit. Its files become the `develop` snapshot. |
| `main` and `develop` already share history | Finish without a push. They can be at different commits. |
| Neither `main` nor `develop` exists | Stop and report the missing branches. |
| No `origin` is configured | Skip reconciliation so a local repository can still run setup. |

Other branches copied by GitHub keep their original histories. If you want to
keep a reference to the copied `main` snapshot, fetch and save its initial
commit before running setup.

```sh
git fetch origin main
git branch main-template-snapshot FETCH_HEAD
```

## Preflight and recovery

Before any push, the script requires full history and checks that each fetched
branch still points to a root commit. It compares every local branch tip and
the current checkout, including a detached `HEAD`, with those fetched tips.
If it finds extra commits, the error names the affected refs and commit IDs.
Keep those commits and reconcile the branches manually. After both branches
share history, `make setup` can continue through its usual local steps.

The script checks Git history. An amended or replaced root commit still looks
like an initial commit, so run setup before amending any generated commits.
For a shallow clone, run `git fetch --unshallow origin` and retry.

The push uses an explicit Git lease. A new branch must still be absent, and an
existing `main` must still match the commit the script checked. Git rejects the
push if that branch changes. The script refreshes the remote-tracking refs after
a successful push. It requires a single matching fetch and push URL on `origin`
so the push goes to the remote it inspected. A rejected push reports Git's
error. Check the branch permissions or fetch and review concurrent changes
before retrying. The target can be rerun after a successful push if a later
fetch or setup step fails. [Git push documentation](https://git-scm.com/docs/git-push)

The script updates the remote branch and refreshes remote-tracking refs. Your
local branch pointers, index, and working files stay as they were. If you had
already created a local `main` from the unrelated snapshot, save it under a
different name and check out the reconciled branch. Commit or stash any local
edits you want to keep before switching.

```sh
git branch -m main main-template-snapshot
git switch --track -c main origin/main
```

Use an unused backup name. If you cloned with `--single-branch` and `main` was
outside the fetch configuration, run `git remote set-branches --add origin main`
and `git fetch origin` before switching.

## Verify the setup workflow

`make branch-reconciliation-test` exercises both creation cases, unrelated
history, repeat runs, and preflight failures against temporary local Git
repositories. `make ci` and `make acceptance` run those tests using local
fixtures.
