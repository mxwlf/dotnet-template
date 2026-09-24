# dotnet-template

My baseline git template. It ships a shared git configuration and a set of
[pre-commit](https://pre-commit.com) hooks so every repo started from this
template gets consistent commit hygiene and commit-message formatting out of
the box.

All tooling lives in a **repo-local virtualenv** (`.venv/`) created by
`make setup`. Nothing is installed globally, and no specific global Python
version is required.

## Requirements

- **GNU make**, **git**, and a POSIX shell (on Windows: Git Bash or WSL).
- **Any Python interpreter `>= 3.10`** reachable as `python3`. It is used *only*
  to create `.venv/`, so whatever you already have works — system, Homebrew,
  pyenv, uv, asdf. If your default `python3` is older, point make at another
  interpreter instead of changing your system default:

  ```sh
  make setup PYTHON=python3.12          # or an absolute path
  ```

  Check what make will use with `make check-python`.

That is the whole list — `pre-commit` itself is **not** a prerequisite.
`make setup` installs the pinned version from
[`requirements-dev.txt`](requirements-dev.txt) into `.venv/`.

> **Why a venv instead of a required global Python version?** Some hooks
> (commitizen, sync-pre-commit-deps) are `language: python` and need
> Python `>= 3.10`. Their upstream manifests declare `language_version: python3`,
> which pre-commit resolves to *the interpreter running pre-commit itself* — not
> to whatever `python3` is on your `PATH`. So a `pre-commit` installed under an
> old interpreter (e.g. macOS's bundled Python 3.9) builds those hook
> environments with 3.9 and fails with `requires a different Python`.
>
> Rather than papering over that with per-hook `language_version` pins — which
> forced every contributor to install one exact Python version globally — the
> template runs pre-commit from `.venv/`, built from any Python `>= 3.10`. The
> hooks inherit that interpreter, so
> [`.pre-commit-config.yaml`](.pre-commit-config.yaml) needs no interpreter pins
> at all and your machine's Python setup is left alone.

## Setup

From the repository root:

```sh
make setup
```

This does three things:

1. Creates `.venv/` and installs the pinned tooling
   ([`requirements-dev.txt`](requirements-dev.txt)) into it.
2. Runs `git config --local include.path ../.gitconfig`, which makes the repo's
   local config include the committed [`.gitconfig`](.gitconfig). That config
   sets `core.hooksPath = .githooks/`, activating the committed hook scripts.
   Because the hooks live in `.githooks/` and are wired up through
   `include.path`, **`pre-commit install` is not required**.
3. Runs `pre-commit install-hooks` to pre-build the hook environments, so your
   first commit isn't slowed down by it.

You never need to *activate* `.venv`: the hook scripts in `.githooks/` and every
make target invoke `.venv/bin/pre-commit` by absolute path.

Run `make help` (or just `make`) to list the available targets.

## What gets configured

| File | Purpose |
| --- | --- |
| [`.gitconfig`](.gitconfig) | Sets `core.hooksPath = .githooks/` so the committed hooks are used. |
| [`.githooks/pre-commit`](.githooks/pre-commit) | Runs the `pre-commit`-stage hooks (formatting, secret detection, etc.) via `.venv`. |
| [`.githooks/commit-msg`](.githooks/commit-msg) | Runs commitizen via `.venv` to enforce [Conventional Commits](https://www.conventionalcommits.org/) message format. |
| [`.pre-commit-config.yaml`](.pre-commit-config.yaml) | Declares the hook repos and pinned versions (`rev`). |
| [`requirements-dev.txt`](requirements-dev.txt) | The pinned tooling installed into `.venv/` — just `pre-commit`. |
| `.venv/` | The repo-local virtualenv. Created by `make setup`, git-ignored, disposable (`make clean`). |

Each hook's own dependencies are installed by pre-commit into its own cached
environments (`~/.cache/pre-commit`, or `~/Library/Caches/pre-commit` on macOS),
not into `.venv/`.

### Hooks included

- **pre-commit-hooks**: trailing whitespace, end-of-file fixer, YAML checks,
  large-file guard (blocks files over 500 kB by default), case-conflict
  detection (catches filename collisions on case-insensitive filesystems like
  macOS/Windows), illegal Windows names, merge-conflict markers, private-key
  detection, byte-order-marker fix, and mixed line endings.
- **gitleaks**: scans for hardcoded secrets.
- **commitizen** (`commit-msg` stage): validates commit messages follow the
  Conventional Commits format, e.g.:
  ```
  feat: add user login
  fix(api): handle null response
  chore: bump dependencies
  ```
- **sync-pre-commit-deps**: keeps hook dependency versions in sync.
- **dotnet-build-test** (local): runs `make test`, which builds and then tests in
  `Release`. That is the configuration where analyzer findings are errors — Debug
  builds only warn, so you can iterate without cleaning up every diagnostic
  first, and this hook is what stops an unresolved one from being committed. It
  only runs when a build input (`.cs`, `.csproj`, `.slnx`, `.props`, `.targets`,
  `.json`) is staged, so documentation-only commits do not pay for a build and
  test run. `make lint` skips it, because `make ci` builds and tests through its
  own targets.

## CI/CD integration

This template is designed so that wiring it into **any** CI/CD platform is
simple and deterministic. It follows the industry-standard *thin wrapper*
pattern (see [Martin Fowler on Continuous
Integration](https://martinfowler.com/articles/continuousIntegration.html#AutomateTheBuild)):
all the actual check logic lives **in the repository** behind a single command,
and each CI platform's config does nothing more than check out the code,
provide a Python interpreter, and run that one command.

```
make ci                       ← single source of truth (runs locally too)
  └── .venv/ (built from requirements-dev.txt)
        └── pre-commit run --all-files
              └── hooks in .pre-commit-config.yaml

.github/workflows/ci.yml      ← thin stub: checkout → python → `make ci`
azure-pipelines.yml           ← thin stub: checkout → python → `make ci`
```

The same `make ci` a developer runs on their laptop is exactly what runs on
GitHub Actions and Azure DevOps — including building the venv, so the CI stubs
install nothing themselves. To change *what* CI does, edit the
[`Makefile`](Makefile) and [`.pre-commit-config.yaml`](.pre-commit-config.yaml)
— **not** the platform YAML.

| File | Purpose |
| --- | --- |
| [`Makefile`](Makefile) (`make ci`) | The portable entrypoint. All check logic lives here. Extend it with your project's build/test commands. |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | Thin GitHub Actions stub that runs `make ci`. |
| [`azure-pipelines.yml`](azure-pipelines.yml) | Thin Azure DevOps stub that runs `make ci`. |

### Extending `make ci` for your project

Add your build/test steps to the `ci` target in the [`Makefile`](Makefile). For
example, for a .NET project:

```make
ci: lint test ## Run the full CI check suite

test: ## Run the test suite
	dotnet test
```

Because the logic is in the Makefile, those steps run identically locally and
on every CI platform — no YAML changes required.

### What you still configure per platform (and why)

The thin-wrapper pattern minimizes platform-specific config but cannot
eliminate it. Each platform requires its own small YAML stub, and a few
concerns are inherently platform-specific and **cannot** be pushed into a
portable script:

- **The stub file itself** — GitHub needs `.github/workflows/*.yml`; Azure
  DevOps needs `azure-pipelines.yml`. The template ships both, pre-wired to
  `make ci`.
- **Triggers** (which branches/events run CI) — expressed differently on each
  platform. Both stubs ship pre-configured to run CI on:
  - **pushes** to `main`, and
  - **pull requests** targeting `main`, from any source branch.

  A pull request that never triggers a run cannot be gated on one, so the
  pull-request trigger must cover every branch you gate — see [Making CI a merge
  gate](#making-ci-a-merge-gate). Feature branches are intentionally absent from
  the push trigger: a branch with an open pull request would otherwise build the
  same commits twice for no extra signal.

  Adjust the `on`/`trigger`/`pr` sections in
  [`.github/workflows/ci.yml`](.github/workflows/ci.yml) and
  [`azure-pipelines.yml`](azure-pipelines.yml) to change this.
- **Publishing reports** — `make ci` *produces* the test and coverage reports
  identically everywhere, but surfacing them is platform-specific: GitHub
  Actions uploads them as a run artifact, Azure DevOps publishes them to its
  Tests and Code Coverage tabs. See [Where the reports
  appear](#where-the-reports-appear).
- **Secrets, service connections, OIDC, and permissions** — managed in each
  platform's settings/YAML, never in the repo.
- **Runner/agent image** and **which Python interpreter is on the agent** (the
  base for `.venv`).
- **Merge gating** — making a green run *mandatory* is a repository setting, not
  a pipeline setting. See [Making CI a merge gate](#making-ci-a-merge-gate).

Everything else — the actual checks — is shared via `make ci`.

### Making CI a merge gate

Running CI is not the same as requiring it. Nothing in this repository can stop
a commit from reaching `main` — the hooks in [`.githooks/`](.githooks) are
client-side and `git commit --no-verify` skips them, so enforcement has to live
on the server, in the forge.

**GitHub.** The gate is a [repository
ruleset](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets),
shipped here as
[`.github/rulesets/protect-main.json`](.github/rulesets/protect-main.json) so it
is reviewable and reproducible rather than click-configured. Apply it with:

```sh
make rulesets-apply     # create/update the ruleset on GitHub
make rulesets-diff      # fail if GitHub no longer matches the repo
make rulesets-export    # pull GitHub's version back in (after a UI edit)
```

These need the [GitHub CLI](https://cli.github.com), authenticated with admin
rights on the repository; unlike everything else here, `gh` is **not** installed
by `make setup`. The ruleset is reconciled **by name**, not by id: GitHub assigns
ruleset ids per repository, so a committed id would be meaningless in a repo
created from this template. `apply` looks up the name, updates the ruleset if it
exists and creates it if it does not — so it is idempotent and works on a fresh
repo. It never *deletes*; see
[`.github/rulesets/README.md`](.github/rulesets/README.md) for that and for the
full rule-by-rule breakdown.

It targets the default branch and requires the **`ci`** check — the job id in
[`.github/workflows/ci.yml`](.github/workflows/ci.yml), which is also the check
name GitHub reports — to pass before anything merges. Changes must arrive by
pull request, commits must be signed, CodeQL and code-quality findings must be
clean, and force-pushes and deletions are refused.

Two settings decide how real that gate is, and both are easy to get wrong:

- **`required_approving_review_count` is `1`, with a review dismissed on every
  push** (`dismiss_stale_reviews_on_push`). You cannot approve your own pull
  request, so on a solo or two-person repository this is *not* satisfiable on its
  own — it only works because of the bypass below. Add a `CODEOWNERS` file before
  turning `require_code_owner_review` back on, since that rule is inert without
  one.
- **`bypass_actors` grants the repository admin role a `"pull_request"` bypass.**
  This is what makes the approval above satisfiable, and it is a deliberate
  loosening: an admin can merge a pull request whose `ci` check is red. The gate
  stops an *accidental* merge of a failing build, not a determined one. The
  narrower `"pull_request"` mode is used rather than `"always"`, so direct pushes
  to the default branch stay blocked even for an admin.

  If you want the CI requirement to be absolute instead, empty `bypass_actors`
  **and** drop the approval count back to `0` in the same edit — an empty bypass
  with a non-zero count leaves a repository nobody can merge into. Requiring a
  pull request while requiring zero approvals keeps CI as the only gate and keeps
  the repository usable; that is the right configuration for a repo with no second
  reviewer, and it is what this file shipped with before it was aligned to
  `git-template`.

`strict_required_status_checks_policy` is `true`, which additionally requires a
branch to be up to date with the default branch before it merges. Without it a
stale-but-green run can merge and break `main`, because the check passed against
an older base.

One honest limit: the merge commit that lands on the default branch is a *new*
commit that CI never ran on, so what the gate guarantees is that the reviewed
*content* was green, not that a run exists for that exact SHA. Because
`strict_required_status_checks_policy` forces the branch to be up to date first,
the tree that lands is the tree that was tested — and unlike a squash or a
rebase, a merge commit keeps the tested commit itself in history as its second
parent, so the run still maps to a real commit on the default branch. The `push`
trigger on `main` records the truth afterwards but cannot block. Closing that last
gap needs a [merge
queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue),
which is only available on repositories owned by an organization.

**Azure DevOps.** There is no repository-side equivalent in YAML — for Azure
Repos the `pr:` trigger in [`azure-pipelines.yml`](azure-pipelines.yml) is
ignored entirely. Gate the branch instead with **Repos → Branches → `main` →
Branch policies → Build Validation**, pointing at this pipeline with *Policy
requirement* set to **Required**. The same two traps apply: keep the reviewer
minimum satisfiable, and leave "Allow bypass" off.

### The workflow these rules require

The workflow is **trunk-based**. `main` is the only long-lived branch: there is no
`develop` to stage through, and no release branches. Everything else is a
short-lived branch that exists just long enough to carry one pull request, and is
deleted after it merges.

With `protect-main` active, `main` cannot be written to directly. Every change
reaches it the same way:

1. **Branch off `main`.** Name it however you like — the rules place no constraint
   on source branches, and a feature branch needs no protection of its own, since
   it cannot reach `main` except through the gate below. Keep it short-lived; the
   point of trunk-based work is that branches merge in days, not weeks. Commits
   are checked locally by the hooks from `make setup`.
2. **Open a pull request into `main`.** A direct `git push origin main` is rejected
   by the ruleset, as is a force-push and a branch deletion.
3. **Let `ci` finish and pass.** It is a required check, so the merge button stays
   disabled until it reports success, and the branch must be up to date with
   `main` first. CodeQL and code-quality findings must be clean too.
4. **Merge with a merge commit, then delete the branch.** `main` accepts *only*
   merge commits — squash and rebase are not offered, because both rewrite history
   and discard the signature you made. A merge commit leaves your commits intact
   and GitHub signs the merge commit itself, satisfying `required_signatures`.

The approval in step 3 is not satisfiable on a solo repository — you cannot approve
your own pull request — so merging relies on the repository admin's
`"pull_request"` bypass. That means the gate prevents an accidental merge of a red
build rather than a determined one. See the two settings under [Making CI a merge
gate](#making-ci-a-merge-gate) for how to make it absolute instead.

### Where the reports appear

`make test` writes a TRX report and a Cobertura coverage file per test module into
`artifacts/test-results/`; `make coverage` merges the coverage files into one
report in `artifacts/coverage/` and fails the build below `COVERAGE_MIN_LINE`
(80% by default — override it, or set it empty to turn the gate off). Both
directories are gitignored, so the pipelines are what make them visible:

| Report | Where to look |
| --- | --- |
| Test results, coverage, slow tests, and each failure's recent history | **GitHub Actions → run → Summary**, as a job summary |
| Failed and skipped tests | Annotations on that Summary page, in the job log, and inline on a pull request's **Files changed** and **Checks** tabs |
| Per-assembly console output | The `make ci` step's log, one collapsible group per test module |
| The report files themselves (TRX, merged Cobertura, browsable HTML) | The **`ci-reports`** artifact on the run Summary page — uploaded even when the run is red, kept 30 days |
| Failure history snapshot | **GitHub Actions → Caches** (`gh-test-history-…`); its contents only surface inside the job summary |
| Test results and coverage on Azure DevOps | The run's native **Tests** and **Code Coverage** tabs |

Locally, `make coverage` prints the same coverage figures to the terminal and
leaves `artifacts/coverage/index.html` to open in a browser. The GitHub-specific
output is inert off a runner, so one command behaves correctly in both places.

### Determinism

- `pre-commit` is pinned in [`requirements-dev.txt`](requirements-dev.txt) and
  installed into an isolated `.venv/`, so CI and laptops run the same version
  regardless of what is installed globally.
- Hook versions are pinned via `rev` in
  [`.pre-commit-config.yaml`](.pre-commit-config.yaml).
- Both CI stubs pin the interpreter used to build `.venv` (currently 3.14) for
  reproducible runs. Any `>= 3.10` works; the pin is not a hook requirement.
- Both stubs pin the runner/agent image (currently `ubuntu-24.04`) instead of
  using `ubuntu-latest`. That label is remapped to a new Ubuntu release
  periodically, which would move the build environment on the platform's
  schedule rather than yours.
- Both stubs cache pre-commit hook environments keyed on the config file, so
  unchanged hooks are not rebuilt.

Bump these versions deliberately when you want to upgrade.

## Make targets

| Target | Description |
| --- | --- |
| `make help` | Show available targets (default when running `make`). |
| `make setup` | Create `.venv`, then configure the repo to use the shared git config and pre-commit hooks. |
| `make venv` | Create/update `.venv` from `requirements-dev.txt` (no-op when up to date). |
| `make ci` | Run the full CI check suite — the single command CI/CD pipelines invoke. Runs identically locally. |
| `make lint` | Run all pre-commit hooks against all files. |
| `make build` | Build every project with analyzers enforced. |
| `make test` | Run every test project, writing the TRX report and Cobertura coverage into `artifacts/test-results/`. On GitHub Actions, also emits the test report (log groups, failure annotations, job summary) and updates the history snapshot in `artifacts/test-history/`. |
| `make coverage` | Merge every module's Cobertura file into one report in `artifacts/coverage/` (Cobertura, markdown, text, HTML) and fail below `COVERAGE_MIN_LINE`. On GitHub Actions, appends the merged figures to the job summary. |
| `make tools` | Restore the pinned local .NET tools from `.config/dotnet-tools.json`. |
| `make clean` | Remove `.venv` (rebuild with `make setup`). |
| `make check-python` | Verify the interpreter used to build `.venv` is `>= 3.10`. |
| `make rulesets-apply` | Create/update this repo's GitHub ruleset from `.github/rulesets/`. Needs `gh`. |
| `make rulesets-diff` | Report drift between `.github/rulesets/` and the live ruleset. Needs `gh`. |
| `make rulesets-export` | Overwrite `.github/rulesets/` with the live ruleset. Needs `gh`. |

Override the interpreter for any of these with `PYTHON=...`, e.g.
`make setup PYTHON=python3.12`.

## Troubleshooting

- **`` `pre-commit` was not found in this repository's .venv/ ``** — the venv is
  missing (fresh clone, new worktree, or `make clean`). Run `make setup` from
  the repository root.
- **`Error: python3 ... but >= 3.10 is required`** — the interpreter make would
  use to build `.venv` is too old. Install any newer Python and either put it on
  your `PATH` as `python3` or pass it explicitly: `make setup PYTHON=python3.12`.
  You do **not** need to change your system default.
- **commitizen / sync-pre-commit-deps fails to build / `requires a different Python`** —
  the hooks are being run by a pre-commit *outside* `.venv/` (a global install
  under an old interpreter). Confirm `make setup` has been run and that
  `git config --get core.hooksPath` prints `.githooks/`; if a stray
  `pre-commit install` overwrote `.git/hooks/`, delete those generated files so
  `core.hooksPath` takes effect again. See
  [Requirements](#requirements) for why the interpreter is chosen this way.
- **`.venv` broke after a Python upgrade** (e.g. Homebrew replaced the
  interpreter it was built from) — recreate it: `make clean && make setup`.
- **Hook is ignored / not running** — confirm `make setup` has been run
  (`git config --get include.path` should print `../.gitconfig`) and that the
  hook scripts in `.githooks/` are executable.
