# Security and dependency baseline

## Repository setup

Workflow dependencies are recorded in `.github/workflows/actions.lock`. Run
`gh actions-lock --no-interactive` after changing a workflow and commit its
result; `gh actions-lock --verify` checks references against upstream and
`gh actions-lock --verify-local` checks coverage offline. The extension is
pinned in the verification workflow. Reusable workflow calls require separate
immutable pinning. Where GitHub workflow lock files are unsupported, replace
the version references with full commit hashes and verify the fallback before
applying policy.

The `actions-lock` and `gitleaks` jobs run on all protected pull requests.
After confirming they report, require them in the live rulesets. Dependency
review fails on newly introduced high and critical findings; it requires the
dependency graph and may not be available for private repositories. For private
repositories, enable it only after validating availability by setting the
repository variable `ENABLE_DEPENDENCY_REVIEW` to `true`. The conditional job
is skipped otherwise: never require a skipped job as a security gate. Make the
job unconditional for the selected repository before requiring its context.
The workflow does not scan the entire resolved dependency tree for existing
vulnerabilities; additional ecosystem-specific scanning is still required.

Reviewed dependency-review exceptions are listed in
`.github/security-exceptions.json` as objects with a GHSA `id`, a nonempty
`reason`, and an `expires` date in YYYY-MM-DD. Empty list means no exceptions.
Each change goes through the protected PR review. The validation step rejects
invalid, duplicate, or expired exceptions. Expiry is evaluated by UTC date and
the exception remains valid through that date. Scope is the GHSA, not an
individual package or version; use the narrowest practical exception and
remove it when fixed. Exceptions do not apply to other scanners.

Dependabot groups minor and patch version updates by ecosystem; major version
updates remain separate. Independently review security updates and coordinate
packages that must move together. Dependabot targets the default branch unless
configured otherwise: set the default branch to `develop` during onboarding.

## Comparing the Git baseline

After checking out the Git template at the reviewed version, run:

```sh
.venv/bin/python eng/scripts/check_git_baseline.py --baseline /path/to/git-template
```

This checks the shared pre-commit definitions, security and lock verification
workflows, and GitHub Actions update configuration. It permits the additional
.NET local hook and the different location of the exception validator. It does
not compare every file, check live GitHub settings, or update anything. Review
other intentional differences separately. Select the baseline revision
explicitly; this manual check does not automatically fetch updates or run in CI.
