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
BASELINE_REF ?=
BASELINE_PACKAGE ?=
VERSION ?=

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

RULESETS := ./scripts/github-rulesets.sh

.PHONY: setup venv ci lint pre-commit clean check-python check-dotnet help tools build test coverage sbom \
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
# CI ENTRYPOINT
# ---------------------------------------------------------------------------
# `make ci` is the SINGLE command CI/CD pipelines invoke. Both the GitHub
# Actions workflow (.github/workflows/ci.yml) and the Azure DevOps pipeline
# (azure-pipelines.yml) do nothing more than: check out the code, provide a
# Python interpreter, and run `make ci`. All actual logic lives here, in-repo,
# so it runs identically on a developer laptop and on every CI platform.
#
# Projects built from this template extend `ci` by adding their own build/test
# steps (e.g. `dotnet test`, `npm test`) as dependencies or extra recipe lines.
ci: lint build test coverage sbom ## Run the full CI check suite (what pipelines invoke)

# The dotnet-build-test hook builds and tests the staged tree on `git commit`. `ci` reaches the same
# code through its own `build` and `test` targets, so the hook is skipped here: leaving it in would
# compile and run the whole suite twice per pipeline run. It is only skipped for `--all-files` runs
# driven by make; `git commit` still runs it.
LINT_SKIP_HOOKS := dotnet-build-test

lint: pre-commit ## Run the pre-commit hooks against all files (the build/test hook is left to `build` and `test`)

pre-commit: venv ## Run the pre-commit hooks against all files (the build/test hook is left to `build` and `test`)
	SKIP=$(LINT_SKIP_HOOKS) $(PRE_COMMIT) run --all-files --show-diff-on-failure

clean: ## Remove the local virtualenv (rebuild it with `make setup`)
	rm -rf $(VENV)

# ---------------------------------------------------------------------------
# GITHUB RULESETS (branch protection as code)
# ---------------------------------------------------------------------------
# Branch protection lives in .github/rulesets/*.json and is reconciled by name,
# so `make rulesets-apply` rebuilds it in any repo created from this template.
# See scripts/github-rulesets.sh for the details.
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

build: check-dotnet ## Build every project with analyzers enforced
	dotnet build --configuration $(CONFIGURATION)

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

# Test modules live at $(ARTIFACTS_DIR)/bin/<project>/<configuration>/<project>. The artifacts output
# layout lowercases <configuration> and appends the build pivots to it, so a multi-targeted project
# produces release_net10.0 rather than plain release — hence the trailing wildcard when globbing for
# it. The apphost itself has no extension on Unix and .exe on Windows.
TEST_CONFIG_DIR := $(shell printf '%s' '$(CONFIGURATION)' | tr '[:upper:]' '[:lower:]')
TEST_EXE_EXT := $(if $(filter Windows_NT,$(OS)),.exe,)

# The modules run one at a time on purpose: GitHub's ::group:: and ::endgroup:: commands are
# sequential and anonymous, so modules running concurrently would interleave and file their output
# under the wrong heading. Every module is run even after one fails, so a red build reports all of
# its failures at once; the loop then exits non-zero. Finding no modules at all is itself a failure,
# because a test target that silently runs nothing is indistinguishable from a passing one.
test: build ## Run every test project, writing results and coverage into $(TEST_RESULTS_DIR)
	@mkdir -p $(TEST_HISTORY_DIR); \
	status=0; found=0; \
	for dir in $(ARTIFACTS_DIR)/bin/*.tests.*; do \
		name=$$(basename "$$dir"); \
		for cfg in "$$dir"/$(TEST_CONFIG_DIR)*; do \
			exe="$$cfg/$$name$(TEST_EXE_EXT)"; \
			[ -x "$$exe" ] || continue; \
			found=$$((found + 1)); \
			echo "==> $$exe"; \
			"$$exe" \
				--results-directory $(TEST_RESULTS_DIR) \
				--report-xunit-trx --report-xunit-trx-filename "$$name.trx" \
				--report-gh \
				--report-gh-history $(TEST_HISTORY_DIR)/$$name.json \
				--report-gh-history-window $(TEST_HISTORY_WINDOW_DAYS) \
				--coverage --coverage-output-format cobertura \
				--coverage-output "$$name.cobertura.xml" || status=1; \
		done; \
	done; \
	if [ "$$found" -eq 0 ]; then \
		echo 'make: found no test executables under $(ARTIFACTS_DIR)/bin/*.tests.*/$(TEST_CONFIG_DIR)*/.' 1>&2; \
		echo '      Check that `make build` succeeded and that CONFIGURATION=$(CONFIGURATION) is the one that was built.' 1>&2; \
		exit 1; \
	fi; \
	exit $$status

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
# SBOM
# ---------------------------------------------------------------------------
# Generates an SPDX 2.2 SBOM with Microsoft's sbom-tool, pinned in
# .config/dotnet-tools.json like every other local tool.
#
# WHY THIS TARGET IS .NET-SPECIFIC WHILE ITS CONTRACT IS NOT: an SBOM's substance
# is the resolved dependency graph, and that graph only exists inside an
# ecosystem's resolver — here NuGet's, via the packages.lock.json files that
# RestorePackagesWithLockFile (Directory.Build.props) keeps committed. What IS
# portable is the contract: a `sbom` target in the `ci` chain writing into
# $(ARTIFACTS_DIR), published by the CI stubs alongside the test and coverage
# reports. git-template documents that contract; this file implements it.
#
# Both paths below are variables because they are the project-specific part. A
# project that publishes a real drop should point SBOM_BUILD_DROP at its
# `dotnet publish` output rather than the whole bin tree.
SBOM_DIR ?= $(ARTIFACTS_DIR)/sbom

# The files the SBOM inventories.
SBOM_BUILD_DROP ?= $(ARTIFACTS_DIR)/bin

# Where sbom-tool looks for dependencies. This must point at project.assets.json,
# NOT at the source tree: assets.json is the file NuGet writes the *resolved*
# graph into, and it is what component detection reads. Pointing this at `src`
# finds nothing at all — it silently produces an SBOM with zero packages, because
# UseArtifactsOutput (Directory.Build.props) relocates obj/ out of the project
# directories and into $(ARTIFACTS_DIR)/obj.
#
# Two things about the default scope are worth knowing, because both are
# properties of assets-based detection rather than mistakes to fix:
#
#   * It covers EVERY project that was built, test projects included, so
#     test-only packages appear in the SBOM. Narrow it for a project that ships
#     one artifact by pointing both variables at that project, e.g.
#         make sbom SBOM_BUILD_DROP=$(ARTIFACTS_DIR)/bin/library.example \
#                   SBOM_COMPONENT_PATH=$(ARTIFACTS_DIR)/obj/library.example
#     which here narrows 46 packages down to the 12 the library actually
#     resolves.
#   * Analyzers and build-time-only packages (SonarAnalyzer, Roslynator,
#     SourceLink, Nerdbank.GitVersioning ...) are included even though they are
#     `PrivateAssets` and ship nothing. They are genuine PackageReferences in
#     assets.json, and detection cannot tell a compile-time dependency from a
#     runtime one. Treat the result as "what this build consumed", which is the
#     honest reading, rather than "what the artifact contains".
SBOM_COMPONENT_PATH ?= $(ARTIFACTS_DIR)/obj

SBOM_PACKAGE_NAME ?= $(basename $(SOLUTION))
SBOM_PACKAGE_SUPPLIER ?= mxwlf
SBOM_NAMESPACE_BASE ?= https://github.com/mxwlf/dotnet-template

sbom: tools build ## Generate an SPDX 2.2 SBOM for the build output into $(SBOM_DIR)
	@set -e; \
	version="$$(dotnet nbgv get-version --variable SemVer2)"; \
	echo "make: SBOM for $(SBOM_PACKAGE_NAME) $$version"; \
	mkdir -p "$(SBOM_DIR)"; \
	dotnet sbom-tool generate \
		-b "$(SBOM_BUILD_DROP)" \
		-bc "$(SBOM_COMPONENT_PATH)" \
		-m "$(SBOM_DIR)" \
		-pn "$(SBOM_PACKAGE_NAME)" \
		-pv "$$version" \
		-ps "$(SBOM_PACKAGE_SUPPLIER)" \
		-nsb "$(SBOM_NAMESPACE_BASE)" \
		-mi SPDX:2.2 \
		-D true \
		-pm true
	@echo "make: wrote $(SBOM_DIR)/_manifest/spdx_2.2/manifest.spdx.json"

# Notes on the flags above, since several are deliberate omissions:
#   -D true   deletes any previous _manifest directory, so `make sbom` is
#             re-runnable instead of failing on a second local run.
#   -pm true  parses license and supplier metadata out of the packages already
#             on disk. Local only; no network.
#   -li       is NOT passed. It fetches license data from the ClearlyDefined API,
#             which would put a network call on the critical path of `make ci`
#             and make a green build depend on a third-party service.
#   -gt       is NOT passed, so the SPDX creationInfo timestamp is the real
#             generation time. That makes consecutive SBOMs differ by a
#             timestamp even for identical input; pinning it to the commit date
#             would buy byte-reproducibility at the cost of the document lying
#             about when it was produced.
