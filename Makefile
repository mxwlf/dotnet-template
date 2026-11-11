# Makefile for dotnet-template
#
# Provides one-command setup for this repository's shared git configuration
# and pre-commit hooks.
#
# Usage:
#   make            # same as `make help`
#   make help       # list available targets
#   make setup      # create .venv + configure the repo's git config and hooks
#   make ci         # run the full CI check suite (the command pipelines invoke)
#   make lint       # run all pre-commit hooks against all files
#   make clean      # remove the local virtualenv
#
# Requirements:
#   - GNU make, git, and a POSIX shell (on Windows: Git Bash or WSL).
#   - A Python interpreter >= $(MIN_PYTHON) reachable as `python3`. It is used
#     ONLY to create the virtualenv, so it can be any install you already have
#     (system, Homebrew, pyenv, ...). Point make at a specific one with:
#         make setup PYTHON=/path/to/python3.12
#
#   Nothing is installed globally and no exact global Python version is
#   required: `make setup` creates a repo-local virtualenv in .venv/ and
#   installs the pinned `pre-commit` from requirements-dev.txt into it.
#
# How it works:
#   `make setup` does two things:
#     1. Builds .venv/ and installs the pinned tooling into it.
#     2. Runs `git config --local include.path ../.gitconfig`, which makes this
#        repo's local config include the committed `.gitconfig`. That in turn
#        sets `core.hooksPath = .githooks/`, activating the committed hook
#        scripts (pre-commit and commit-msg) without needing `pre-commit
#        install`. Those scripts run .venv's `pre-commit`, never PATH's.

.DEFAULT_GOAL := help

SOLUTION := dotnet-template.slnx
CONFIGURATION ?= Release
ARTIFACTS_DIR ?= artifacts
# Versioning is NOT a make variable: it is derived from git history by Nerdbank.GitVersioning,
# configured in version.json. There is deliberately no VERSION override here — a version you
# could pass on the command line would disagree with the one stamped into the assembly.

# ---------------------------------------------------------------------------
# REPO-LOCAL VIRTUALENV
# ---------------------------------------------------------------------------
# The interpreter used only to *create* .venv. Override on the command line
# (e.g. `make setup PYTHON=python3.12`) to build the venv from a specific one.
PYTHON ?= python3

# Minimum version for the interpreter above: some hooks (commitizen,
# sync-pre-commit-deps) are `language: python` and require >= 3.10. Because
# their manifests say `language_version: python3`, pre-commit builds them with
# whichever interpreter is running pre-commit itself — i.e. .venv's.
MIN_PYTHON := 3.10

VENV := .venv
ifeq ($(OS),Windows_NT)
VENV_BIN := $(VENV)/Scripts
else
VENV_BIN := $(VENV)/bin
endif
PRE_COMMIT := $(VENV_BIN)/pre-commit
# Marker file recording that requirements-dev.txt has been installed into
# .venv; makes `venv` a no-op until the requirements change.
VENV_STAMP := $(VENV)/.requirements-installed

RULESETS := ./eng/scripts/github-rulesets.sh

.PHONY: setup venv ci lint pre-commit clean deepclean check-python check-dotnet help tools build test coverage pack sbom example-sbom prune-stale-output \
        rulesets-apply rulesets-diff rulesets-export

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

setup: venv ## Create the local virtualenv and configure the repo's git config + hooks
	git config --local include.path ../.gitconfig
	$(PRE_COMMIT) install-hooks

venv: $(VENV_STAMP) ## Create/update the repo-local virtualenv (.venv) with the pinned tooling

$(VENV_STAMP): requirements-dev.txt
	@$(MAKE) --no-print-directory check-python
	$(PYTHON) -m venv $(VENV)
	$(VENV_BIN)/python -m pip install --disable-pip-version-check --upgrade pip
	$(VENV_BIN)/python -m pip install --disable-pip-version-check --require-virtualenv -r requirements-dev.txt
	@touch $@

tools: check-dotnet ## Restore pinned local .NET tools
	dotnet tool restore

# Checks that a `dotnet` exists AND that it can satisfy the SDK version pinned in global.json.
# Merely finding `dotnet` on PATH is not enough: the host is installed independently of the SDKs, so
# a machine can have the command and still have no SDK the pin accepts, and the failure then surfaces
# much later as an opaque MSBuild error.
#
# `dotnet --version` is the probe because it resolves through global.json and exits non-zero (155)
# when the pin cannot be met, printing the requested version, the offending global.json and the list
# of SDKs that are installed. `dotnet --list-sdks` is NOT usable here: it ignores global.json
# entirely and exits 0 even when the pinned SDK is absent.
#
# The pin is deliberately not auto-installed. CI installs it in .github/workflows/ci.yml with
# actions/setup-dotnet, which is the same "prerequisite installation" role actions/setup-python
# plays for $(PYTHON); on a laptop, which SDKs to install is the developer's call, so this target
# only tells them precisely what is missing.
check-dotnet: ## Verify an installed .NET SDK satisfies the version pinned in global.json
	@command -v dotnet > /dev/null 2>&1 || { \
		echo 'Error: `dotnet` was not found on your PATH.' 1>&2; \
		echo '       Install the .NET SDK pinned in global.json: https://dot.net/download' 1>&2; \
		exit 1; \
	}
	@dotnet --version > /dev/null 2>&1 || { \
		echo 'Error: no installed .NET SDK satisfies the version pinned in global.json.' 1>&2; \
		echo '       Install that SDK from https://dot.net/download, or repin global.json to one' 1>&2; \
		echo '       you already have. dotnet reports:' 1>&2; \
		dotnet --version 2>&1 | sed 's/^/       | /' 1>&2; \
		exit 1; \
	}

# ---------------------------------------------------------------------------
# CI AND ACCEPTANCE ENTRYPOINTS
# ---------------------------------------------------------------------------
# PRs run `make ci`. Each push to develop runs `make acceptance` on that
# commit. Acceptance starts with the same checks and can grow independently.
# The foundation exercises candidate creation with its example package.
ci: security-exceptions-check lint release-bundle-test build analyzers-verify test coverage ## Run the foundation CI checks (what pipelines invoke)

# Validate exception metadata even when dependency review is unavailable.
.PHONY: security-exceptions-check
security-exceptions-check: check-python ## Reject invalid or expired dependency exceptions
	@$(PYTHON) eng/scripts/security_exceptions.py > /dev/null
	@$(PYTHON) eng/scripts/validate_nuget_suppressions.py
	@$(PYTHON) -m unittest discover -s tests -p test_security_exceptions.py
	@$(PYTHON) -m unittest discover -s tests -p test_nuget_audit.py
	@$(PYTHON) -m unittest discover -s tests -p test_nuget_suppressions.py

acceptance: ci ## Run post-integration acceptance checks (extends ci by default)

# The example package reuses the build exercised by acceptance. Derived projects
# replace the package build and smoke check with their own artifact-specific steps.
candidate: pack tools check-python ## Bundle the versioned example package
	@version=$$(dotnet tool run nbgv get-version -v NuGetPackageVersion) && \
		commit=$$(git rev-parse HEAD) && \
		$(PYTHON) eng/scripts/release_bundle.py create --input "$(PACKAGE_DIR)" \
		--output "$$RELEASE_OUTPUT" --version "$$version" --commit "$$commit"

candidate-acceptance: check-python ## Check the packaged assembly and record acceptance
	$(PYTHON) eng/scripts/release_bundle.py accept "$$RELEASE_OUTPUT" "$$RELEASE_EVIDENCE" \
		$(PYTHON) eng/scripts/check_example_package.py "$$RELEASE_OUTPUT" \
		"$(ARTIFACTS_DIR)/bin/library.example/$(TEST_CONFIG_DIR)"

# Publication phases require a downstream implementation.
release: ## Reserved: create a release from an accepted candidate
	@echo 'release: not implemented for this repository' >&2; exit 2

publish: ## Reserved: promote a verified release to its destination
	@echo 'publish: not implemented for this repository' >&2; exit 2

record-release: ## Reserved: record the successfully promoted source on main
	@echo 'record-release: not implemented for this repository' >&2; exit 2


# A bundle is created from already-built files; it does not build or publish them.
# The caller supplies the version and source commit. The output must not exist.
RELEASE_INPUT ?=
RELEASE_OUTPUT ?= $(ARTIFACTS_DIR)/release-bundle
RELEASE_VERSION ?=
RELEASE_COMMIT ?=
RELEASE_EVIDENCE ?= $(ARTIFACTS_DIR)/candidate-acceptance.json
export RELEASE_INPUT RELEASE_OUTPUT RELEASE_VERSION RELEASE_COMMIT RELEASE_EVIDENCE

.PHONY: release-bundle release-bundle-verify release-bundle-test verify-accepted-candidate
release-bundle: check-python ## Bundle an existing release directory and write a manifest
	$(PYTHON) eng/scripts/release_bundle.py create --input "$$RELEASE_INPUT" --output "$$RELEASE_OUTPUT" --version "$$RELEASE_VERSION" --commit "$$RELEASE_COMMIT"

release-bundle-verify: check-python ## Check the bundle payload against its manifest
	$(PYTHON) eng/scripts/release_bundle.py verify "$$RELEASE_OUTPUT"

verify-accepted-candidate: check-python ## Match a bundle to trusted evidence and expected metadata
	$(PYTHON) eng/scripts/release_bundle.py verify-accepted "$$RELEASE_OUTPUT" "$$RELEASE_EVIDENCE" \
		--version "$$RELEASE_VERSION" --commit "$$RELEASE_COMMIT"

release-bundle-test: check-python ## Test the release bundle contract
	$(PYTHON) -m unittest discover -s tests -p 'test_release_bundle.py'

# The strict analyzer default is an explicit entry per rule in
# eng/analyzers/all-rules.globalconfig, because no bulk severity entry can switch on a rule its
# analyzer ships disabled. That file is generated from the analyzers the projects resolve from NuGet
# — pinned by Directory.Packages.props and the lock files, so it is reproducible anywhere — so
# bumping an analyzer package can add rules it does not mention yet, and a rule that is not
# mentioned falls back to its own default, which for roughly a third of them is off. `verify` fails
# the build in that case rather than letting the strict bar quietly soften, and names the rules that
# differ; `sync` regenerates it.
#
# Ordered after `build` to reuse its restore. The generator reads @(ResolvedAnalyzers), which
# ResolvePackageAssets fills from project.assets.json, so it needs a restored tree; it passes
# -restore itself and is correct standalone, but running it before `build` meant paying for a
# second restore on every pipeline run. After `build` that flag costs nothing, because the assets
# are already current.
#
# The cost of this order is that a stale file is reported after the build rather than before it, so
# a package bump that adds an enabled-by-default rule can fail the build on that rule before this
# target explains why the configuration is behind. The diagnostic names the rule and the fix is
# `make analyzers-sync`, which is a short trip; a duplicated restore on every green run is not.
analyzers-sync: check-dotnet ## Regenerate eng/analyzers/all-rules.globalconfig from the resolved analyzers
	dotnet run eng/analyzers/sync-rules.cs

analyzers-verify: check-dotnet ## Fail if eng/analyzers/all-rules.globalconfig is stale
	dotnet run eng/analyzers/sync-rules.cs --check

# CI runs build, test and analyzer verification directly after lint. Keep the
# corresponding pre-commit hooks enabled for local commits and skip them here.
LINT_SKIP_HOOKS := dotnet-build-test,dotnet-analyzers-verify

lint: pre-commit ## Run the repository lint checks

pre-commit: venv ## Run hooks other than the .NET checks invoked directly by CI
	SKIP=$(LINT_SKIP_HOOKS) $(PRE_COMMIT) run --all-files --show-diff-on-failure

clean: ## Remove the local virtualenv (rebuild it with `make setup`)
	rm -rf $(VENV)

# EVERY GENERATED TREE, NOT JUST THE ONES A BUILD WOULD OVERWRITE.
# `prune-stale-output` is the surgical tool — it removes output whose project is gone and leaves
# incremental state intact, so it can run before every build. This is the opposite: it takes the
# tree back to what a fresh clone has, for when the question is "is this real, or is my tree
# stale?" and the cheapest answer is to have no stale tree. Nothing it deletes is recoverable from
# here, and nothing it deletes needs to be: every path below is generated and gitignored.
#
# $(VENV) comes along, because a deep clean that left the toolchain behind would be answering a
# different question than the one asked.
#
# bin/ AND obj/ ARE SWEPT EVEN THOUGH THIS LAYOUT DOES NOT PRODUCE THEM. UseArtifactsOutput in
# Directory.Build.props redirects all of it under $(ARTIFACTS_DIR), so a per-project bin/ or obj/
# means something built outside that layout — a project that set its own output path, an older
# checkout, or a tool that ignored the property. Those are exactly the directories that then go
# stale invisibly, because no `dotnet build` here will ever overwrite them. Both are gitignored, so
# anything the sweep finds is generated by definition; the find prunes node_modules, $(VENV), .git
# and .idea first, because package trees are full of directories called bin.
#
# `dotnet clean` runs for completeness, giving the SDK's own notion of clean its say, but
# $(ARTIFACTS_DIR) is removed wholesale straight after, which supersedes it. It is prefixed with `-`
# so a failure cannot stop the deletions: a clean has to work when the tree is too broken to build,
# which is most of why anyone reaches for this. Verified to exit 0 with no assets file, so
# re-running this target is not an error.
#
# A REPOSITORY BUILT FROM THIS TEMPLATE EXTENDS THIS, the same way it extends `ci`. The node_modules
# prune in the find below is deliberate forward provision — it costs nothing here — but a repo that
# actually grows an npm workspace should also DELETE those trees, which means adding its own sweep:
#
#     @find web -type d \( -name node_modules -o -name dist \) -prune -print -exec rm -rf {} +
deepclean: ## Remove every generated tree: build output, test results, and the virtualenv
	@# THE GUARD RUNS BEFORE ANYTHING IS DELETED, WHICH IS WHY `clean` IS INVOKED FROM THE RECIPE
	@# RATHER THAN BEING A PREREQUISITE. As a prerequisite it ran FIRST — so a deepclean that
	@# refused an out-of-range path had already removed $(VENV) by the time it refused, which is
	@# the half-finished state the guard exists to prevent. A recipe line also keeps the ordering
	@# under `make -j`, where prerequisite order is not guaranteed.
	@case '$(ARTIFACTS_DIR)' in \
		''|/*) echo 'make: refusing to delete ARTIFACTS_DIR=$(ARTIFACTS_DIR) — must be a non-empty relative path.' 1>&2; exit 1 ;; \
	esac
	@$(MAKE) --no-print-directory clean
	-dotnet clean $(SOLUTION) --nologo --verbosity quiet
	rm -rf $(ARTIFACTS_DIR)
	@# TestResults/ is where a bare `dotnet test` writes, which the Makefile does not use but
	@# leaves available for IDEs and ad-hoc runs. Named explicitly rather than swept.
	rm -rf TestResults
	@find . \
		\( -name node_modules -o -name '$(VENV)' -o -name .git -o -name .idea \) -prune -o \
		-type d \( -name bin -o -name obj \) -prune -print -exec rm -rf {} +
	@echo 'make: deep clean complete. Restore with `make setup`.'

# ---------------------------------------------------------------------------
# GITHUB RULESETS (branch protection as code)
# ---------------------------------------------------------------------------
# Branch protection lives in .github/rulesets/*.json and is reconciled by name,
# so `make rulesets-apply` rebuilds it in any repo created from this template.
# See eng/scripts/github-rulesets.sh for the details.
#
# These targets are deliberately NOT dependencies of `ci`: rulesets are admin
# API surface, and a workflow's default GITHUB_TOKEN cannot read them. Making
# `ci` depend on them would fail for reasons unrelated to the code under test,
# and would break the rule that `make ci` runs identically on a laptop.
#
# Requires the GitHub CLI (`gh`), authenticated — unlike the targets above, this
# is not covered by `make setup`. Target another repo with REPO=owner/name.

rulesets-apply: ## Create/update this repo's GitHub rulesets from .github/rulesets/
	$(RULESETS) apply

rulesets-diff: ## Report drift between .github/rulesets/ and the live rulesets
	$(RULESETS) diff

rulesets-export: ## Overwrite .github/rulesets/ with the live rulesets
	$(RULESETS) export

check-python: ## Verify the interpreter used to build .venv is new enough
	@command -v $(PYTHON) > /dev/null 2>&1 || { \
		echo 'Error: `$(PYTHON)` was not found on your PATH.' 1>&2; \
		echo '       Install any Python >= $(MIN_PYTHON), or point make at one you have:' 1>&2; \
		echo '           make setup PYTHON=/path/to/python3' 1>&2; \
		exit 1; \
	}
	@$(PYTHON) -c 'import sys; req = tuple(int(p) for p in "$(MIN_PYTHON)".split(".")); raise SystemExit(sys.version_info[:len(req)] < req)' || { \
		echo "Error: $(PYTHON) is $$($(PYTHON) -V 2>&1 | cut -d" " -f2), but >= $(MIN_PYTHON) is required to build $(VENV)." 1>&2; \
		echo '       Any interpreter >= $(MIN_PYTHON) will do; it need not be your default python3:' 1>&2; \
		echo '           make setup PYTHON=python3.12' 1>&2; \
		exit 1; \
	}

# Remove build outputs for deleted or renamed projects while keeping incremental
# state for current projects. The test runner prunes reports using the solution's
# actual test modules and their report names.
prune-stale-output: ## Remove $(ARTIFACTS_DIR) output for projects that no longer exist
	@case '$(ARTIFACTS_DIR)' in \
		''|/*) echo 'make: refusing to prune ARTIFACTS_DIR=$(ARTIFACTS_DIR) — must be a non-empty relative path.' 1>&2; exit 1 ;; \
	esac
	@current=$$(find . -name '*.csproj' -not -path './$(ARTIFACTS_DIR)/*' -not -path './$(VENV)/*' \
		-exec basename {} .csproj \; 2> /dev/null | sort -u); \
	[ -n "$$current" ] || { echo 'make: found no .csproj files; skipping prune.' 1>&2; exit 0; }; \
	for tree in bin obj publish; do \
		[ -d "$(ARTIFACTS_DIR)/$$tree" ] || continue; \
		for dir in "$(ARTIFACTS_DIR)/$$tree"/*; do \
			[ -d "$$dir" ] || continue; \
			name=$$(basename "$$dir"); \
			printf '%s\n' "$$current" | grep -qxF "$$name" \
				|| { echo "make: pruning stale output $$dir"; rm -rf "$$dir"; }; \
		done; \
	done

build: check-dotnet prune-stale-output ## Build every project with analyzers enforced
	dotnet build "$(SOLUTION)" --configuration $(CONFIGURATION)

# Tests run on Microsoft.Testing.Platform (opted into by the "test" section of global.json), which
# makes every test project a self-contained executable that hosts its own test framework.
#
# Those executables are invoked DIRECTLY here rather than through `dotnet test`, which is the one
# place this Makefile passes up a first-party dotnet CLI command. `dotnet test` drives each module
# in MTP's server mode, where the orchestrator captures the module's stdout and re-renders it
# through its own terminal UI. That silently swallows the GitHub Actions workflow commands the
# reporter writes there — annotations, log groups and slow-test notices all disappear — and only the
# markdown job summary survives, because that one is written straight to a file. Running each module
# ourselves keeps the whole feature set, at the cost of doing the module discovery below.
# `dotnet test` is not broken by any of this and remains available for IDEs and ad-hoc runs.
#
# --results-directory keeps the TRX report and the Cobertura coverage file inside the same
# $(ARTIFACTS_DIR) tree that UseArtifactsOutput already writes bin/ and obj/ into, so
# everything a build produces — including test results — lives under one gitignored
# directory that CI can publish wholesale.
#
# --report-gh makes the run a first-class GitHub Actions experience: per-assembly log groups,
# annotations on failed and skipped tests (which also land on a pull request's "Files changed"
# diff, because the reporter emits repository-relative paths), a markdown job summary appended to
# the file named by $GITHUB_STEP_SUMMARY, and notices for slow tests. The extension that owns the
# switch (Microsoft.Testing.Extensions.GitHubActionsReport, referenced by the test project) checks
# the GITHUB_ACTIONS environment variable itself and does nothing unless it is "true", so the flag
# is passed unconditionally: `make test` stays a single command that is correct on a laptop and in
# CI alike, which is the same reason .github/workflows/ci.yml carries no logic of its own.
#
# --report-gh-history points the reporter at a bounded snapshot of past results. Every failure the
# summary reports then carries what that failure has done lately — "failed 2 and flaked 0 of 3 prior
# runs within the 30-day history window", plus p95/p99 durations — which is the difference between
# reading a red build as a real regression and recognising a test that fails every other week.
# The reporter reads the snapshot before the run and rewrites it after, but it does not move the file
# between runs: carrying it forward is the workflow's job, and .github/workflows/ci.yml does that
# with a rolling actions/cache entry. Locally the whole extension is inert, so no snapshot is read or
# written on a laptop.
#
# Samples are keyed partly by run, so history only accumulates where GITHUB_RUN_ID differs from one
# run to the next. That is free on a real runner and worth knowing if you ever fake one by hand:
# without it, every run looks like the same run and overwrites the previous samples instead of
# adding to them.
#
# The path is per-module rather than one shared file because each module rewrites the snapshot it was
# given, so pointing two modules at the same path would have the second overwrite the first's history.
TEST_RESULTS_DIR ?= $(ARTIFACTS_DIR)/test-results
TEST_HISTORY_DIR ?= $(ARTIFACTS_DIR)/test-history

# Days of history the snapshot retains (1-90). This is also the reporter's own default; it is stated
# explicitly because it is a retention decision, not an incidental one. Note that the effective span
# is whichever is shorter: this window, or how long the cache entry survives — GitHub evicts caches
# that go 7 days without a read, so a repo that sits idle for a week starts its history over.
TEST_HISTORY_WINDOW_DAYS ?= 30

# Packaging also uses the lowercased artifacts output configuration.
TEST_CONFIG_DIR := $(shell printf '%s' '$(CONFIGURATION)' | tr '[:upper:]' '[:lower:]')

test: build check-python ## Run solution test projects, writing reports and coverage
	$(PYTHON) eng/scripts/run_solution_tests.py "$(SOLUTION)" "$(CONFIGURATION)" \
		"$(TEST_RESULTS_DIR)" "$(TEST_HISTORY_DIR)" "$(TEST_HISTORY_WINDOW_DAYS)"

# ---------------------------------------------------------------------------
# COVERAGE
# ---------------------------------------------------------------------------
# `make test` leaves one Cobertura file per test module, and the GitHub Actions report summarises each
# module's coverage separately. Neither produces the number the repository is actually judged by: the
# aggregate across every module. This target merges them with ReportGenerator into a single report and
# holds that merged number to a floor.
#
# ReportGenerator is a pinned local tool (.config/dotnet-tools.json) rather than a PackageReference
# because it is a repository-wide report step, not a dependency of any one project — which is also why
# this target depends on `tools`.
#
# -reports is quoted so the shell leaves the glob alone: ReportGenerator does its own globbing, and
# expanding it here would turn one switch into several arguments. Reaching every module through one
# glob is what makes the report aggregate rather than per-project.
#
# The report types are chosen one per audience: Cobertura is the merged machine-readable file the
# Azure DevOps Code Coverage tab publishes (azure-pipelines.yml) and any external coverage service
# would consume; MarkdownSummaryGithub is the job summary block; TextSummary is what a developer sees
# on a laptop; Html is the browsable report inside the uploaded run artifact.
#
# Publishing is guarded on $GITHUB_STEP_SUMMARY rather than on a CI flag, which keeps `make coverage`
# a single command that is correct in both places — the same property `--report-gh` has in `test`,
# where the extension checks GITHUB_ACTIONS itself. Off a runner the variable is unset and the text
# summary goes to stdout instead.
#
# The exit status is captured and re-raised at the end so that a tripped threshold still publishes the
# report that explains it. Failing first would hide exactly the numbers the reader needs.
COVERAGE_DIR ?= $(ARTIFACTS_DIR)/coverage

# The floors, as percentages. ReportGenerator only accepts 1-100, so emptying a variable is how a gate
# is turned off (`make coverage COVERAGE_MIN_LINE=`). The line floor ships enabled because a gate
# nobody opts into never catches a regression; the branch floor ships off because it is the noisier of
# the two to hold a whole repository to. Both are policy, not mechanism — raise them as the suite
# grows.
COVERAGE_MIN_LINE ?= 80
COVERAGE_MIN_BRANCH ?=

COVERAGE_THRESHOLDS := \
	$(if $(COVERAGE_MIN_LINE),--minimumCoverageThresholds:lineCoverage=$(COVERAGE_MIN_LINE)) \
	$(if $(COVERAGE_MIN_BRANCH),--minimumCoverageThresholds:branchCoverage=$(COVERAGE_MIN_BRANCH))

coverage: tools test ## Merge every module's coverage into $(COVERAGE_DIR) and enforce the coverage floor
	@status=0; \
	dotnet reportgenerator \
		"-reports:$(TEST_RESULTS_DIR)/*.cobertura.xml" \
		"-targetdir:$(COVERAGE_DIR)" \
		"-reporttypes:Cobertura;MarkdownSummaryGithub;TextSummary;Html" \
		$(COVERAGE_THRESHOLDS) || status=$$?; \
	if [ -n "$$GITHUB_STEP_SUMMARY" ] && [ -f "$(COVERAGE_DIR)/SummaryGithub.md" ]; then \
		cat "$(COVERAGE_DIR)/SummaryGithub.md" >> "$$GITHUB_STEP_SUMMARY"; \
	elif [ -f "$(COVERAGE_DIR)/Summary.txt" ]; then \
		cat "$(COVERAGE_DIR)/Summary.txt"; \
	fi; \
	exit $$status

# ---------------------------------------------------------------------------
# PACKAGING
# ---------------------------------------------------------------------------
# $(TEST_CONFIG_DIR) is the lower-cased $(CONFIGURATION) that the artifacts output layout uses for
# its per-configuration subdirectories; it is shared with the test target rather than recomputed.
PACKAGE_DIR ?= $(ARTIFACTS_DIR)/package/$(TEST_CONFIG_DIR)

# --no-build, because `pack` depends on `build` and would otherwise compile the solution a second
# time. Both run at $(CONFIGURATION), so the output pack reuses is the one build just produced.
#
# Symbol packages come along automatically: IncludeSymbols and SymbolPackageFormat=snupkg in
# Directory.Build.props mean each .nupkg is accompanied by a .snupkg.
#
# Packaging metadata and the readme that ships with the package live in Directory.Build.props and
# Directory.Build.targets. Test projects set IsPackable=false themselves, so nothing here has to
# exclude them.
pack: build ## Produce the NuGet packages into $(PACKAGE_DIR)
	@# Emptied first so $(PACKAGE_DIR) holds exactly what THIS run produced. Without it the
	@# directory accumulates every version ever packed locally, and the consumers of that
	@# directory may be consumed by globs, so a stale package could otherwise be mistaken
	@# for an output of the current build.
	@# CI never saw this because a runner starts clean; a laptop does not.
	@#
	@# Only this configuration's directory is removed, so packing Debug does not discard a
	@# Release package. The guard refuses an empty or absolute path: $(PACKAGE_DIR) is composed
	@# from $(ARTIFACTS_DIR) and $(CONFIGURATION), and an `rm -rf` built from overridable
	@# variables should not be able to point at /.
	@case '$(PACKAGE_DIR)' in \
		''|/*) echo 'make: refusing to clean PACKAGE_DIR=$(PACKAGE_DIR) — must be a non-empty relative path.' 1>&2; exit 1 ;; \
	esac
	@rm -rf "$(PACKAGE_DIR)"
	@# Recreated empty rather than left absent, because `sbom` uses $(PACKAGE_DIR) as its build
	@# drop and sbom-tool fails outright on a missing -b path. A repository where nothing is
	@# packable — an application rather than a library — never has `dotnet pack` create it, so
	@# without this the SBOM step breaks on a clean tree.
	@mkdir -p "$(PACKAGE_DIR)"
	@# WarnOnPackingNonPackableProject=false, because `dotnet pack` sets it to true and the Web
	@# SDK leaves it that way, so every Microsoft.NET.Sdk.Web project that is not packable draws:
	@#
	@#     warning : This project cannot be packaged because packaging has been disabled.
	@#
	@# In an application built from this template that describes every project, so the warning
	@# reports the intended configuration as a problem — and it is a warning, which makes it
	@# noise in a build that treats warnings seriously. The SDK gates the message on exactly this
	@# property (see IsPackableFalseWarningTask in NuGet.Build.Tasks.Pack.targets), so this is the
	@# supported way to turn it off rather than a filter over the output. The case worth knowing
	@# about — that nothing was packable — is reported below as a plain message instead.
	dotnet pack --no-build --configuration $(CONFIGURATION) -p:WarnOnPackingNonPackableProject=false
	@ls -1 "$(PACKAGE_DIR)" 2> /dev/null | sed 's/^/make: packed /' || \
		{ echo 'make: pack produced nothing in $(PACKAGE_DIR).' 1>&2; exit 1; }

# ---------------------------------------------------------------------------
# SBOM
# ---------------------------------------------------------------------------
# Inventory an already-built deliverable and its resolved build dependencies.
SBOM_DIR ?= $(ARTIFACTS_DIR)/sbom
SBOM_BUILD_DROP ?=
SBOM_PROJECT ?=
SBOM_COMPONENT_PATH ?= $(if $(SBOM_PROJECT),$(ARTIFACTS_DIR)/obj/$(SBOM_PROJECT))
SBOM_PACKAGE_NAME ?=
SBOM_PACKAGE_VERSION ?=
SBOM_PACKAGE_SUPPLIER ?=
SBOM_NAMESPACE_BASE ?=
export SBOM_DIR SBOM_BUILD_DROP SBOM_COMPONENT_PATH SBOM_PACKAGE_NAME
export SBOM_PACKAGE_VERSION SBOM_PACKAGE_SUPPLIER SBOM_NAMESPACE_BASE

sbom: tools ## Generate an SPDX 2.2 SBOM for an existing, explicitly scoped deliverable
	@set -e; \
	test -n "$$SBOM_BUILD_DROP" && test -d "$$SBOM_BUILD_DROP" && \
		test -n "$$(find "$$SBOM_BUILD_DROP" -type f -print -quit)" || \
		{ echo 'make: set SBOM_BUILD_DROP to a non-empty deliverable directory.' >&2; exit 1; }; \
	test -n "$$SBOM_COMPONENT_PATH" && test -f "$$SBOM_COMPONENT_PATH/project.assets.json" || \
		{ echo 'make: set SBOM_PROJECT or SBOM_COMPONENT_PATH to select a restored project.' >&2; exit 1; }; \
	test -n "$$SBOM_PACKAGE_NAME" && test -n "$$SBOM_PACKAGE_VERSION" && \
		test -n "$$SBOM_PACKAGE_SUPPLIER" && test -n "$$SBOM_NAMESPACE_BASE" || \
		{ echo 'make: set the SBOM package name, version, supplier, and namespace base.' >&2; exit 1; }
	mkdir -p "$$SBOM_DIR"
	dotnet sbom-tool generate \
		-b "$$SBOM_BUILD_DROP" \
		-bc "$$SBOM_COMPONENT_PATH" \
		-m "$$SBOM_DIR" \
		-pn "$$SBOM_PACKAGE_NAME" \
		-pv "$$SBOM_PACKAGE_VERSION" \
		-ps "$$SBOM_PACKAGE_SUPPLIER" \
		-nsb "$$SBOM_NAMESPACE_BASE" \
		-mi SPDX:2.2 \
		-D true \
		-pm true
	@echo "make: wrote $$SBOM_DIR/_manifest/spdx_2.2/manifest.spdx.json"

example-sbom: pack tools ## Build and inventory the example NuGet packages
	@version=$$(dotnet tool run nbgv get-version -v NuGetPackageVersion) && \
		$(MAKE) sbom SBOM_BUILD_DROP="$(PACKAGE_DIR)" \
		SBOM_COMPONENT_PATH="$(ARTIFACTS_DIR)/obj/library.example" \
		SBOM_PACKAGE_NAME=mxwlf.net.library.example SBOM_PACKAGE_VERSION="$$version" \
		SBOM_PACKAGE_SUPPLIER=mxwlf SBOM_NAMESPACE_BASE=https://github.com/mxwlf/dotnet-template

# Notes on the flags above, since several are deliberate omissions:
#   -D true   deletes any previous _manifest directory, so `make sbom` is
#             re-runnable instead of failing on a second local run.
#   -pm true  parses license and supplier metadata out of the packages already
#             on disk. Local only; no network.
#   -li       is NOT passed. It fetches license data from the ClearlyDefined API,
#             which would put a network call on the SBOM generation path
#             and make a green build depend on a third-party service.
#   -gt       is NOT passed, so the SPDX creationInfo timestamp is the real
#             generation time. That makes consecutive SBOMs differ by a
#             timestamp even for identical input; pinning it to the commit date
#             would buy byte-reproducibility at the cost of the document lying
#             about when it was produced.
