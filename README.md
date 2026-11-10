# .NET foundation template

This repository is the shared .NET layer built on the Git template. It supplies
Git hooks, a pinned SDK and tools, analyzers, build and test conventions, and a
small release-bundle contract. It is a foundation for future NuGet library,
command-line application, and Aspire service templates.

The example library and its tests exercise the foundation. The example can be
packed locally, but this repository has no active publishing workflow. A
specialized template decides what to build and where to distribute it.

## Getting started

Install Git, GNU make, Python 3.10 or later, and an SDK satisfying
[`global.json`](global.json). Then run:

```sh
make setup
make ci
```

`make setup` installs the pinned pre-commit tool in a repository-local `.venv`
and configures the Git hooks. `make ci` runs the common hooks, release-bundle
checks, a Release build with analyzers, analyzer configuration verification,
tests, and the coverage gate. GitHub Actions and Azure DevOps call the same
entry point for PRs. Pushes to `develop` run `make acceptance`, which initially
executes the same checks and can be extended independently. A full Git history
is needed for versioning.

`make help` lists the targets. `make deepclean` removes generated build and
test output as well as the local virtual environment. The common hooks include secret detection,
commit-message validation, and Markdown spelling. The .NET hook also builds and
tests staged .NET inputs at commit time; `make ci` runs those checks separately.

## Build and test conventions

- [`global.json`](global.json) selects the SDK and Microsoft Testing Platform.
- [`Directory.Build.props`](Directory.Build.props) and
  [`Directory.Build.targets`](Directory.Build.targets) set shared build,
  analyzer, and package defaults. Release builds treat warnings as errors.
- [`Directory.Packages.props`](Directory.Packages.props) and project lock files
  record package versions; [`.config/dotnet-tools.json`](.config/dotnet-tools.json)
  pins repository tools.
- `make test` discovers test executables under `artifacts/bin/*.tests.*`.
  Keep that naming convention when adding test projects. It writes TRX and
  coverage reports under `artifacts/test-results/`.
- `make coverage` merges the reports and enforces an 80% line-coverage floor by
  default; `COVERAGE_MIN_LINE` can change it.
- [`version.json`](version.json) and `Nerdbank.GitVersioning` derive versions from
  Git history. The CI checkouts fetch full history for this reason.

Both CI providers publish test and coverage results. GitHub Actions also
uploads the raw reports; Azure DevOps displays them in its test and coverage
views. Packaging and SBOM generation are optional targets, not foundation CI
requirements.

## Integration and release phases

PRs into `develop` run `make ci`. Each `develop` push runs `make acceptance` on
the integrated commit. The [integration baseline](docs/integration-release.md)
defines the shared phase names and the golden-release contract. `candidate`,
`candidate-acceptance`, `release`, `publish`, and `record-release` are reserved
targets that fail until a downstream project implements them. The bundle tool
alone does not implement any of those phases or prove acceptance or provenance.

## Release contract

See [the release contract](docs/release-contract.md) for the shared bundle,
its limitations, and the responsibilities of specialized templates. The
foundation neither publishes packages nor deploys applications. The previous
NuGet workflow is retained as [historical reference](examples/nuget-publish.yml.reference),
not as an enabled or ready-to-use publishing workflow.

The checked-in example is packable. `make pack` builds its NuGet packages and
`make sbom` produces an example SPDX document; neither publishes anything.
`make sbom` is scoped by default to `library.example` and its package output.
An adopter must configure metadata, paths, and an inventory appropriate to each
actual deliverable. In particular, one example SBOM does not establish the
contents of multiple packages or an application deployment.

## Branch protection

The committed [`protect-main` ruleset](.github/rulesets/protect-main.json)
and [`develop-protection` ruleset](.github/rulesets/develop-protection.json)
require the `ci` job on their respective branches. Create `develop` and confirm
PR checks report before applying either ruleset. They are not applied
automatically; a future promotion process needs explicitly configured authority
to advance `main`. See the [ruleset guide](.github/rulesets/README.md) for
setup, admin bypass, merge method, and portability details. A project adding
required security checks must ensure they are configured and run on every
protected pull request before applying those requirements.

## License

[MIT](LICENSE). Update project-specific package metadata and copyright details
when adapting the example to another project.

Security onboarding and exception handling are documented in [the security baseline](docs/security-baseline.md).
