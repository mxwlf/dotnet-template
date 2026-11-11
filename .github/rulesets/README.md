# Branch protection as code

The JSON files in this directory are this repository's GitHub **rulesets** —
branch protection — stored as code. Manage them from the repository root:

```sh
make rulesets-apply     # create/update the rulesets on GitHub
make rulesets-diff      # fail if GitHub no longer matches these files
make rulesets-export    # overwrite these files from GitHub (after a UI edit)
```

All three run [`eng/scripts/github-rulesets.sh`](../../eng/scripts/github-rulesets.sh),
which talks to `/repos/{owner}/{repo}/rulesets` via `gh api`. The `gh ruleset`
command group is read-only (`check`, `list`, `view`), so it cannot do this.

This file covers how the rules are *stored and rebuilt*. For the day-to-day
workflow they impose — how a change reaches `develop` — see
[Branch protection](../../README.md#branch-protection).

## What the shipped rulesets enforce

The integration branch is `develop`; `main` is intended to record the promoted
source commit. Create `develop` before applying `develop-protection`. Both
rulesets block deletion and force pushes, require a PR, one approval, resolved
review threads, an up-to-date branch and the `ci` check. They permit merge
commits and allow a repository admin to bypass the rules within a PR. That
bypass includes failing checks, so it is not a hard gate for a sole maintainer.

`protect-main` also requires signed commits and blocks branch creation.
`develop-protection` omits those two rules: a release tool may create unsigned
commits, and the integration branch must be created before protection is applied.
The policy on signatures can be tightened if the selected automation supports it.

The shipped rulesets do not grant an automation identity permission to update
`main`. A project implementing promotion must explicitly configure and review
that authority, or use a reviewed alternative. A bypass may skip the full
ruleset, including signature checks; only a verified, successfully promoted
candidate should be recorded. See the [integration and release baseline](../../docs/integration-release.md).

Merge commits preserve authors' branch commits and their signatures. The
repository must also permit merge commits; the ruleset cannot enable them.

## The ruleset cannot enable a merge method the repository forbids

`allowed_merge_methods` only *narrows* what the repository already permits. The
repository has its own `allow_merge_commit` / `allow_squash_merge` /
`allow_rebase_merge` switches, they are not part of any ruleset, and this file
cannot set them. Ask for a method the repository has switched off and the merge is
refused outright:

> Merge commits are not allowed on this repository.

This repository already has merge commits enabled, so nothing is needed here — but
a repo created from this template may not. Enable it under **Settings → General →
Pull Requests**, or:

```sh
gh api --method PATCH repos/OWNER/REPO -F allow_merge_commit=true
```

This is the one part of the gate that `make rulesets-apply` cannot reproduce for
you, because it lives on the repository rather than in a ruleset. It surfaced in
`dotnet-template`, where the first merge under this policy failed on exactly that.

## The required check must actually run

A required status check that is never reported is never green, so the pull
request waits on it forever. The `context` value here (`ci`) is the **job id**
in [`.github/workflows/ci.yml`](../workflows/ci.yml), and that workflow's
`pull_request` trigger has to include every branch these rulesets protect. If
you rename the job, or add a protected branch, update both files together.

There is a quieter version of the same failure. A job that GitHub skips because
of its own job-level `if:` is reported as **successful**, not skipped — so making
such a job a required check adds a gate that is permanently green and signals
nothing. A security workflow carrying `if: github.event_name != 'pull_request'`
is the usual way to walk into this. Before requiring a check, confirm the job
actually runs on a pull request.

(The other direction behaves differently: when an entire *workflow* is skipped by
a path or branch filter, its checks stay pending forever rather than passing.
Either way, a required check is only worth anything if it genuinely runs.)

## Roll out changes to `main`

Preview the change before applying it. Check that the named required jobs
report on a pull request targeting `main` before enforcing new requirements.

```sh
make rulesets-diff RULESET=protect-main
make rulesets-apply RULESET=protect-main
make rulesets-diff RULESET=protect-main
```

For `mxwlf/dotnet-template`, the [repository-specific definition](repositories/mxwlf/dotnet-template/protect-main.json)
preserves the existing CodeQL and code-quality gates. Diff, apply, and export
use that file for this repository. Other repositories use the portable rules
unless they provide their own definition under `repositories/OWNER/REPO/`
with the same filename and ruleset name. Add code-scanning requirements only
after configuring the corresponding scans.

## What is portable between repositories

These files are meant to be copied into repos created from this template, so
they only reference ids that mean the same thing everywhere:

- **`integration_id: 15368`** in `required_status_checks` is the GitHub Actions
  app — a global app id, identical in every repository.
- **`actor_type: "RepositoryRole"`, `actor_id: 5`** is the repository admin
  role. Role ids are global too.

Do **not** commit rulesets that reference `actor_type: "Team"` or specific
users: those ids are scoped to one organization or account and will resolve to
the wrong thing, or fail, in another repo.

Ruleset **ids** are likewise per repository, which is why `apply` matches on the
`name` field instead. Rename a ruleset in one of these files and the next
`apply` creates a second one rather than renaming the original.

## Why these targets are not part of `make ci`

Rulesets are admin API surface. A workflow's default `GITHUB_TOKEN` cannot read
them and cannot be granted the rights via `permissions:`, so a `rulesets-diff`
step in CI would fail for reasons that have nothing to do with the code under
test — and it would break the rule that `make ci` behaves the same on a laptop
as in a pipeline. Run these locally, or from a workflow with an admin PAT if you
want drift detection enforced.

## Editing

JSON has no comments. `eng/scripts/github-rulesets.sh` strips any key beginning with
`_`, so a `"_comment"` key in these files is harmless — but `make rulesets-export`
regenerates them verbatim from the API and will drop it. Durable explanation
belongs in this file.

If the project has a JSON formatter — Prettier, say — exclude this directory from
it. `make rulesets-export` writes these files in the canonical form the script
normalizes to (2-space indent, sorted keys, one array element per line), and a
formatter that collapses short arrays will disagree with that on every export:
the export dirties the tree, then the formatter undoes the export. The two will
fight indefinitely until one of them is told to stand down.

If you change protection in the GitHub UI, run `make rulesets-export` to bring
the change back into the repo; otherwise the next `make rulesets-apply` will
silently revert it.

**`apply` never deletes.** It creates and updates the rulesets named by the files
here, and ignores anything else on the repo. Removing a file therefore leaves its
ruleset live on GitHub — delete that one yourself:

```sh
id=$(gh api repos/OWNER/REPO/rulesets --jq '.[] | select(.name=="NAME") | .id')
gh api --method DELETE repos/OWNER/REPO/rulesets/$id
```

The omission is deliberate: a prune step would give a script that runs against
any repo the power to remove protection it did not create.
