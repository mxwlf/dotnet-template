# git-template

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
  - **pushes** to `main` and `develop`, and
  - **pull requests** targeting `develop`.

  Adjust the `on`/`trigger`/`pr` sections in
  [`.github/workflows/ci.yml`](.github/workflows/ci.yml) and
  [`azure-pipelines.yml`](azure-pipelines.yml) to change this.
- **Secrets, service connections, OIDC, and permissions** — managed in each
  platform's settings/YAML, never in the repo.
- **Runner/agent image** and **which Python interpreter is on the agent** (the
  base for `.venv`).

Everything else — the actual checks — is shared via `make ci`.

### Determinism

- `pre-commit` is pinned in [`requirements-dev.txt`](requirements-dev.txt) and
  installed into an isolated `.venv/`, so CI and laptops run the same version
  regardless of what is installed globally.
- Hook versions are pinned via `rev` in
  [`.pre-commit-config.yaml`](.pre-commit-config.yaml).
- Both CI stubs pin the interpreter used to build `.venv` (currently 3.14) for
  reproducible runs. Any `>= 3.10` works; the pin is not a hook requirement.
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
| `make clean` | Remove `.venv` (rebuild with `make setup`). |
| `make check-python` | Verify the interpreter used to build `.venv` is `>= 3.10`. |

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
